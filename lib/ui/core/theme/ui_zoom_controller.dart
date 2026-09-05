import 'package:flutter/material.dart';

import '../../../data/services/config_service.dart';

/// 全局 UI 缩放控制器 (浏览器式整体缩放，Ctrl+= / Ctrl+- / Ctrl+0)。
///
/// - `main.dart` 启动时按持久化配置 [syncFromConfig] 校正首帧缩放；
/// - `MaterialApp.builder` 用 [ValueListenableBuilder] 监听 [zoom]，把整个
///   Navigator 子树包进 [AppUiZoomScope]：布局在 `窗口逻辑尺寸 / zoom` 的
///   缩小坐标系里完成，再经 `Transform.scale` 视觉放大回窗口物理尺寸——
///   文本按放大后的物理尺寸重新光栅化，清晰度无损；
/// - 快捷键步进 0.05 (5%)，范围 [ConfigService.minUiZoom] ~ [ConfigService.maxUiZoom]；
/// - 控制器完全独立于 StudioViewModel，阶段 4 拆 Controller 时零迁移成本。
///
/// 故意不放在 ViewModel/Mixin 上：UI 缩放是应用根级 (MaterialApp) 状态，
/// 生命周期长于任何一个工作台会话——与 AppThemeModeController 同构。
class AppUiZoomController {
  AppUiZoomController._();

  /// 全局唯一实例 (应用生命周期级别，永不 dispose)
  static final AppUiZoomController instance = AppUiZoomController._();

  /// 当前生效缩放系数 (1.0 = 100%)
  final ValueNotifier<double> zoom = ValueNotifier<double>(1.0);

  /// 快捷键/滑块步进粒度 (5%)
  static const double step = 0.05;

  /// 钳制到合法范围 (与 ConfigService 单一事实源对齐)
  static double clamp(double value) => ConfigService.clampUiZoom(value);

  /// 配置保存/加载后同步；值未变化时不触发通知。
  void syncFromConfig(AppConfig config) {
    final target = clamp(config.uiZoom);
    if (zoom.value != target) {
      zoom.value = target;
    }
  }

  /// 步进缩放 (正数放大 / 负数缩小)，返回钳制后的新值。
  double adjust(double delta) {
    final target = clamp(zoom.value + delta);
    zoom.value = target;
    return target;
  }

  /// 重置为 100%
  void reset() => zoom.value = 1.0;

  /// 测试辅助：复位 100%，避免用例间串扰。
  @visibleForTesting
  void resetForTest() => zoom.value = 1.0;
}

/// 整体 UI 缩放作用域：把子树的布局坐标系缩到 `1 / zoom`，再视觉放大回原尺寸。
///
/// 实现要点：
/// - 布局尺寸与 [MediaQuery] 的 size 一起缩小，全屏路由屏障/对话框按缩小后的
///   逻辑屏幕排版，经缩放放大后恰好铺满物理窗口，不会溢出；
/// - 命中测试：用 [FittedBox] 而非 `OverflowBox + Transform.scale`。RenderFittedBox
///   自身按完整窗口尺寸参与边界检查，hitTestChildren 先逆变换再下发给子树；
///   而 OverflowBox+Transform 方案下缩小布局的 SizedBox 会在窗口坐标系里先行
///   做边界检查，zoom>1 时窗口右带/下带「窗口尺寸/zoom」之外的区域全部点击
///   无效 (生成坞/标题栏按钮死区)；
/// - zoom == 1.0 时原样直通 (零开销零影响)。
class AppUiZoomScope extends StatelessWidget {
  final double zoom;
  final Widget child;

  const AppUiZoomScope({super.key, required this.zoom, required this.child});

  @override
  Widget build(BuildContext context) {
    if (zoom == 1.0) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final scaledWidth = constraints.maxWidth / zoom;
        final scaledHeight = constraints.maxHeight / zoom;
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(size: Size(scaledWidth, scaledHeight)),
          // FittedBox 给子树无约束布局空间，内层 SizedBox 固定缩小后的逻辑尺寸；
          // fit: fill 在等比尺寸下均匀放大 zoom 倍铺满窗口。
          child: FittedBox(
            fit: BoxFit.fill,
            clipBehavior: Clip.none,
            child: SizedBox(
              width: scaledWidth,
              height: scaledHeight,
              child: child,
            ),
          ),
        );
      },
    );
  }
}
