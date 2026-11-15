import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/core/theme/frame_rate_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeTimer implements Timer {
  final Duration delay;
  final void Function() callback;
  bool cancelled = false;
  int _tick = 0;

  _FakeTimer(this.delay, this.callback);

  @override
  void cancel() {
    cancelled = true;
  }

  @override
  bool get isActive => !cancelled && _tick == 0;

  @override
  int get tick => _tick;

  void fire() {
    if (cancelled) return;
    _tick++;
    callback();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig.maxFrameRate 持久化与安全钳制', () {
    test('默认不限制 (0) 且 copyWith 透传', () {
      const cfg = AppConfig();
      expect(cfg.maxFrameRate, 0);
      expect(cfg.copyWith(maxFrameRate: 60).maxFrameRate, 60);
      expect(cfg.copyWith(maxFrameRate: 60).copyWith().maxFrameRate, 60);
    });

    test('saveConfig -> loadConfig 往返并归一化非法值', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ConfigService();
      await service.saveConfig(const AppConfig(maxFrameRate: 120));
      expect((await service.loadConfig()).maxFrameRate, 120);

      SharedPreferences.setMockInitialValues({'novelai_max_frame_rate': -5});
      expect((await service.loadConfig()).maxFrameRate, 0);

      SharedPreferences.setMockInitialValues({'novelai_max_frame_rate': 10});
      expect(
        (await service.loadConfig()).maxFrameRate,
        ConfigService.minFrameRate,
      );

      SharedPreferences.setMockInitialValues({'novelai_max_frame_rate': 999});
      expect(
        (await service.loadConfig()).maxFrameRate,
        ConfigService.maxFrameRateLimit,
      );
    });
  });

  group('AppFrameRateController', () {
    setUp(AppFrameRateController.instance.resetForTest);

    test('syncFromConfig 同步变更且同值不重复通知', () {
      final ctrl = AppFrameRateController.instance;
      var notified = 0;
      ctrl.maxFps.addListener(() => notified++);

      ctrl.syncFromConfig(const AppConfig(maxFrameRate: 60));
      expect(ctrl.maxFps.value, 60);
      expect(notified, 1);

      ctrl.syncFromConfig(const AppConfig(maxFrameRate: 60));
      expect(notified, 1);

      ctrl.syncFromConfig(const AppConfig(maxFrameRate: 0));
      expect(ctrl.maxFps.value, 0);
      expect(notified, 2);
    });
  });

  group('FrameRatePacer 节拍器', () {
    test('不限制或上限 >= 显示器刷新率时直接调度，不推迟帧', () {
      var nowUs = 0;
      var refreshHz = 60.0;
      final timers = <_FakeTimer>[];
      var platformScheduled = 0;

      final pacer = FrameRatePacer(
        nowMicros: () => nowUs,
        displayRefreshHz: () => refreshHz,
        createTimer: (delay, cb) {
          final t = _FakeTimer(delay, cb);
          timers.add(t);
          return t;
        },
      );

      // 不限制 (0) 直通
      pacer.setMaxFps(0);
      pacer.onBeginFrame();
      nowUs = 1000;
      pacer.requestFrame(
        hasScheduledFrame: false,
        framesEnabled: true,
        schedulePlatformFrame: () => platformScheduled++,
        retryScheduleFrame: () => platformScheduled++,
      );
      expect(platformScheduled, 1);
      expect(timers, isEmpty);

      // 60Hz 显示器选 60 FPS 时同样直通原生 VSync，防止跨过 VSync 降到 30 FPS
      pacer.setMaxFps(60);
      pacer.onBeginFrame();
      nowUs += 1000;
      pacer.requestFrame(
        hasScheduledFrame: false,
        framesEnabled: true,
        schedulePlatformFrame: () => platformScheduled++,
        retryScheduleFrame: () => platformScheduled++,
      );
      expect(platformScheduled, 2);
      expect(timers, isEmpty);
    });

    test('320Hz 显示器限制 60 FPS 时合并推迟请求，并在放开限制时立即唤醒', () {
      var nowUs = 0;
      final timers = <_FakeTimer>[];
      var platformScheduled = 0;

      final pacer = FrameRatePacer(
        nowMicros: () => nowUs,
        displayRefreshHz: () => 320.0,
        createTimer: (delay, cb) {
          final t = _FakeTimer(delay, cb);
          timers.add(t);
          return t;
        },
      );

      pacer.setMaxFps(60);
      // 第一帧进入 BeginFrame
      pacer.onBeginFrame();

      // 2ms 后连续多次请求下一帧：应被合并成一个延迟 Timer
      nowUs = 2000;
      for (var i = 0; i < 3; i++) {
        pacer.requestFrame(
          hasScheduledFrame: false,
          framesEnabled: true,
          schedulePlatformFrame: () => platformScheduled++,
          retryScheduleFrame: () => platformScheduled++,
        );
      }
      expect(platformScheduled, 0);
      expect(timers.length, 1);
      expect(pacer.hasDeferredFrame, isTrue);

      // 触发延迟 Timer，调度真实平台帧
      nowUs += timers.single.delay.inMicroseconds;
      timers.single.fire();
      expect(platformScheduled, 1);
      expect(pacer.hasDeferredFrame, isFalse);

      // 再次进入 BeginFrame 后立刻请求下一帧 -> 挂起，随后放开上限 -> 立即 flush
      pacer.onBeginFrame();
      nowUs += 1000;
      pacer.requestFrame(
        hasScheduledFrame: false,
        framesEnabled: true,
        schedulePlatformFrame: () => platformScheduled++,
        retryScheduleFrame: () => platformScheduled++,
      );
      expect(timers.length, 2);
      expect(pacer.hasDeferredFrame, isTrue);

      var flushed = 0;
      pacer.setMaxFps(0, onFlush: () => flushed++);
      expect(flushed, 1);
      expect(timers.last.cancelled, isTrue);
      expect(pacer.hasDeferredFrame, isFalse);
    });
  });
}
