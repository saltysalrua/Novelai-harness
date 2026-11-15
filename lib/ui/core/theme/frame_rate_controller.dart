import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../../../data/services/config_service.dart';

/// 全局渲染帧率上限控制器。
///
/// - `0` 表示不限制（跟随显示器原生刷新率，如 60/120/320 Hz）；
/// - 正整数（如 `60`、`120`）表示限制最高渲染帧率，在高刷桌面显示器上配合
///   Impeller 减少 `ReactorGLES` / `RenderPassGLES` 的过度光栅提交与 Raster Jank；
/// - 生命周期与 [AppUiZoomController] 同级，全局单例且修改后即时生效。
class AppFrameRateController {
  AppFrameRateController._();

  /// 全局唯一实例
  static final AppFrameRateController instance = AppFrameRateController._();

  /// 当前生效的帧率上限（`0` = 不限制）
  final ValueNotifier<int> maxFps = ValueNotifier<int>(0);

  /// 钳制到合法范围（与 ConfigService 单一事实源对齐）
  static int clamp(int value) => ConfigService.clampMaxFrameRate(value);

  /// 配置加载/保存后同步；同值不触发监听。
  void syncFromConfig(AppConfig config) {
    final target = clamp(config.maxFrameRate);
    if (maxFps.value != target) {
      maxFps.value = target;
    }
  }

  /// 测试辅助：复位为不限制，避免用例间串扰。
  @visibleForTesting
  void resetForTest() => maxFps.value = 0;
}

/// 纯逻辑帧间隔节拍器，负责将高频 `scheduleFrame()` 合批推迟到目标帧预算窗口。
///
/// 设计要点：
/// - 若未设上限（`maxFps <= 0`）或显示器原生刷新率本就不高于上限，零延迟直通原生 VSync，
///   避免在 60Hz 显示器设置 `60 FPS` 时误跨过 VSync 边界跌到 30 FPS；
/// - 若低于显示器刷新率（如 320Hz 屏限制到 60/120 FPS），从上次真正开始 `BeginFrame`
///   的单调时间戳算起，并保留半个 VSync 提前量触发 `platformDispatcher.scheduleFrame()`，
///   既避免在空闲 VSync 上无效唤醒引擎，也避免过度滞后。
class FrameRatePacer {
  final int Function() _nowMicros;
  final double Function() _displayRefreshHz;
  final Timer Function(Duration delay, void Function() callback) _createTimer;

  int _maxFps = 0;
  int? _lastBeginFrameUs;
  Timer? _deferredTimer;

  FrameRatePacer({
    int Function()? nowMicros,
    double Function()? displayRefreshHz,
    Timer Function(Duration delay, void Function() callback)? createTimer,
  }) : _nowMicros = nowMicros ?? _defaultNowMicros,
       _displayRefreshHz = displayRefreshHz ?? _defaultDisplayRefreshHz,
       _createTimer = createTimer ?? Timer.new;

  static final Stopwatch _clock = Stopwatch()..start();
  static int _defaultNowMicros() => _clock.elapsedMicroseconds;
  static double _defaultDisplayRefreshHz() =>
      PlatformDispatcher.instance.displays.firstOrNull?.refreshRate ?? 0.0;

  int get maxFps => _maxFps;

  /// 当前是否正有一个被节拍器延迟中的待调度帧。
  bool get hasDeferredFrame => _deferredTimer != null;

  /// 更新上限；若放开限制或提高到不再需要等待的阈值，立刻唤醒被挂起的帧请求。
  void setMaxFps(int value, {VoidCallback? onFlush}) {
    final next = ConfigService.clampMaxFrameRate(value);
    if (_maxFps == next) return;
    _maxFps = next;
    if (_deferredTimer != null && (_maxFps <= 0 || _shouldDispatchNow())) {
      _cancelDeferredTimer();
      onFlush?.call();
    }
  }

  /// 响应框架 `scheduleFrame()` 请求。
  void requestFrame({
    required bool hasScheduledFrame,
    required bool framesEnabled,
    required VoidCallback schedulePlatformFrame,
    required VoidCallback retryScheduleFrame,
  }) {
    if (hasScheduledFrame || !framesEnabled) {
      return;
    }

    if (_shouldBypassCap() || _shouldDispatchNow()) {
      _cancelDeferredTimer();
      schedulePlatformFrame();
      return;
    }

    // 已有待触发的延迟调度定时器时直接合并，避免重复创建 Timer。
    if (_deferredTimer != null) return;

    final delayUs = _computeRemainingDelayUs();
    if (delayUs <= 0) {
      schedulePlatformFrame();
      return;
    }
    _deferredTimer = _createTimer(Duration(microseconds: delayUs), () {
      _deferredTimer = null;
      retryScheduleFrame();
    });
  }

  /// 记录每次真实进入 `handleBeginFrame` 的时刻，并清理冗余定时器。
  void onBeginFrame() {
    _cancelDeferredTimer();
    _lastBeginFrameUs = _nowMicros();
  }

  void dispose() {
    _cancelDeferredTimer();
  }

  bool _shouldBypassCap() {
    if (_maxFps <= 0) return true;
    final refreshHz = _displayRefreshHz();
    // 上限 >= 显示器原生刷新率时直通系统 VSync，防止定时器抖动引发降半帧（如 60->30）。
    return refreshHz > 0 && _maxFps >= refreshHz - 1.0;
  }

  bool _shouldDispatchNow() {
    if (_lastBeginFrameUs == null || _maxFps <= 0) return true;
    return _computeRemainingDelayUs() <= 0;
  }

  int _computeRemainingDelayUs() {
    final lastUs = _lastBeginFrameUs;
    if (lastUs == null || _maxFps <= 0) return 0;
    final targetIntervalUs = (1000000 / _maxFps).round();
    final refreshHz = _displayRefreshHz();
    final maxLeadUs = (targetIntervalUs ~/ 4).clamp(500, 2200);
    final leadUs = refreshHz > 0
        ? (500000 / refreshHz).round().clamp(500, maxLeadUs)
        : 1000;
    final elapsedUs = _nowMicros() - lastUs;
    final waitThresholdUs = targetIntervalUs - leadUs;
    return waitThresholdUs - elapsedUs;
  }

  void _cancelDeferredTimer() {
    _deferredTimer?.cancel();
    _deferredTimer = null;
  }
}

/// 为 [SchedulerBinding] 混入全局帧率上限能力。
mixin FrameRateCapBindingMixin on SchedulerBinding {
  late final FrameRatePacer _frameRatePacer = FrameRatePacer();

  @override
  void initInstances() {
    super.initInstances();
    final controller = AppFrameRateController.instance;
    _frameRatePacer.setMaxFps(controller.maxFps.value);
    controller.maxFps.addListener(_onMaxFpsChanged);
  }

  void _onMaxFpsChanged() {
    _frameRatePacer.setMaxFps(
      AppFrameRateController.instance.maxFps.value,
      onFlush: super.scheduleFrame,
    );
  }

  @override
  void scheduleFrame() {
    _frameRatePacer.requestFrame(
      hasScheduledFrame: hasScheduledFrame,
      framesEnabled: framesEnabled,
      schedulePlatformFrame: super.scheduleFrame,
      retryScheduleFrame: super.scheduleFrame,
    );
  }

  @override
  void handleBeginFrame(Duration? rawTimeStamp) {
    _frameRatePacer.onBeginFrame();
    super.handleBeginFrame(rawTimeStamp);
  }
}

/// 携带帧率限制能力的工程主 Binding。
class AppWidgetsFlutterBinding extends WidgetsFlutterBinding
    with FrameRateCapBindingMixin {
  /// 返回已初始化的 [WidgetsBinding] 单例，若尚未初始化则创建 [AppWidgetsFlutterBinding]。
  static WidgetsBinding ensureInitialized() {
    try {
      return WidgetsBinding.instance;
    } catch (_) {
      return AppWidgetsFlutterBinding();
    }
  }
}
