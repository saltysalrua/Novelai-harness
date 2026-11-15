import 'package:flutter/widgets.dart';

/// 全局动效时长令牌 (Motion Duration Tokens)
///
/// 映射自 `transitions.dev` `_root.css` 语义化时间刻度，统一应用内的入场、
/// 退场、微交互与循环动效节拍，避免孤立的硬编码毫秒数。
abstract final class AppMotionDurations {
  /// 40ms - 逐项交错延迟步长 (`--duration-stagger`)
  static const Duration stagger = Duration(milliseconds: 40);

  /// 50ms - 思考状态切换间隙 / Tooltip 退场 (`--think-gap`, `--tt-out-dur`)
  static const Duration gap = Duration(milliseconds: 50);

  /// 60ms - 晃动恢复段 / 流式逐词间隔 (`--shake-dur-b`, `--stream-gap`)
  static const Duration shakeLegB = Duration(milliseconds: 60);

  /// 70ms - 数字跳入尾数交错延迟 (`--digit-stagger`)
  static const Duration numberStagger = Duration(milliseconds: 70);

  /// 80ms - 极微延迟、Tooltip 触发延迟、成功勾选路径延迟 (`--duration-micro`)
  static const Duration micro = Duration(milliseconds: 80);

  /// 150ms - 快速切换 (弹窗/下拉关闭、文本状态切换、Tooltip 入场) (`--duration-quick`)
  static const Duration quick = Duration(milliseconds: 150);

  /// 200ms - 交错文本静默淡出 (`--stagger` exit)
  static const Duration staggerExit = Duration(milliseconds: 200);

  /// 250ms - 标准轻快过渡 (图标切换、弹窗/下拉打开、标签滑动、页面侧滑) (`--duration-fast`)
  static const Duration fast = Duration(milliseconds: 250);

  /// 280ms - 错误晃动总时长 (80 * 2 + 60 * 2) (`--shake-dur-a * 2 + --shake-dur-b * 2`)
  static const Duration shakeTotal = Duration(milliseconds: 280);

  /// 300ms - 卡片尺寸自适应 (`--resize-dur`)
  static const Duration cardResize = Duration(milliseconds: 300);

  /// 320ms - 头像/标签悬停抬升 (`--avatar-dur`)
  static const Duration avatarHover = Duration(milliseconds: 320);

  /// 350ms - 中等过渡 (面板关闭、Toast 打开、流式淡入) (`--duration-medium`)
  static const Duration medium = Duration(milliseconds: 350);

  /// 400ms - 较慢过渡 (面板打开、骨架屏揭示、悬浮倾斜跟随) (`--duration-slow`)
  static const Duration slow = Duration(milliseconds: 400);

  /// 500ms - 强调时刻 (数字弹出、成功勾选、文本交错揭示) (`--duration-very-slow`)
  static const Duration verySlow = Duration(milliseconds: 500);

  /// 1000ms - 骨架屏单次脉冲 / 卡片倾斜回正 (`--pulse-dur`, `--tilt-return`)
  static const Duration hoverTiltReturn = Duration(milliseconds: 1000);

  /// 1200ms - 4x4 矩阵点阵加载器周期 (`--matrix-cycle`)
  static const Duration matrixCycle = Duration(milliseconds: 1200);

  /// 2000ms - 文字流光循环 / 思考状态停留时长 (`--shimmer-dur`, `--think-hold`)
  static const Duration shimmer = Duration(milliseconds: 2000);

  // --- 语义别名 (便于按组件场景直觉引用) ---

  /// 250ms - 模态框打开 (`--modal-open-dur`)
  static const Duration modalOpen = fast;

  /// 150ms - 模态框关闭 (`--modal-close-dur`)
  static const Duration modalClose = quick;

  /// 250ms - 下拉菜单打开 (`--dropdown-open-dur`)
  static const Duration dropdownOpen = fast;

  /// 150ms - 下拉菜单关闭 (`--dropdown-close-dur`)
  static const Duration dropdownClose = quick;

  /// 400ms - 面板展开 (`--panel-open-dur`)
  static const Duration panelOpen = slow;

  /// 350ms - 面板收起 (`--panel-close-dur`)
  static const Duration panelClose = medium;

  /// 350ms - Toast 弹入 (`--toast-open`)
  static const Duration toastOpen = medium;

  /// 250ms - Toast 收起 (`--toast-close`)
  static const Duration toastClose = fast;

  /// 150ms - 思考状态文本切换 (`--think-swap`)
  static const Duration thinkSwap = quick;

  /// 2000ms - 思考状态停留 (`--think-hold`)
  static const Duration thinkHold = shimmer;

  /// 150ms - Tooltip 入场 (`--tt-in-dur`)
  static const Duration tooltipIn = quick;

  /// 50ms - Tooltip 退场 (`--tt-out-dur`)
  static const Duration tooltipOut = gap;

  /// 80ms - Tooltip 悬停延迟 (`--tt-delay`)
  static const Duration tooltipDelay = micro;

  /// 160ms - Tooltip 目标间位移动画 (`--tt-move-dur`)
  static const Duration tooltipMove = Duration(milliseconds: 160);

  /// 80ms - 错误晃动主摆幅段 (`--shake-dur-a`)
  static const Duration shakeLegA = micro;

  /// 400ms - 卡片 3D 倾斜跟随 (`--tilt-follow`)
  static const Duration hoverTiltFollow = slow;

  /// 300ms - 卡片 3D 倾斜高光淡入淡出 (`--tilt-glare-fade`)
  static const Duration hoverTiltGlareFade = cardResize;

  /// 500ms - 数字弹出动画 (`--digit-dur`)
  static const Duration numberPopIn = verySlow;

  /// 1000ms - 骨架屏脉冲 (`--pulse-dur`)
  static const Duration skeletonPulse = hoverTiltReturn;

  /// 400ms - 骨架屏内容揭示 (`--reveal-dur`)
  static const Duration skeletonReveal = slow;

  /// 60ms - 流式文字词间间隔 (`--stream-gap`)
  static const Duration streamGap = shakeLegB;

  /// 350ms - 流式文字单词淡入 (`--stream-fade`)
  static const Duration streamFade = medium;
}

/// 全局动效缓动曲线令牌 (Motion Curve Tokens)
///
/// 映射自 `transitions.dev` `_root.css` 曲线集合。
abstract final class AppMotionCurves {
  /// 平滑减速度曲线 (`cubic-bezier(0.22, 1.0, 0.36, 1.0)`)
  ///
  /// 适用于弹窗、下拉、面板展开收起、页面侧滑与尺寸变化。
  static const Curve smoothOut = Cubic(0.22, 1.0, 0.36, 1.0);

  /// 对称缓入缓出 (`ease-in-out`)
  ///
  /// 适用于图标切换、文本原地切换、骨架屏揭示与点阵呼吸。
  static const Curve inOut = Curves.easeInOut;

  /// 标准缓出 (`ease-out`)
  ///
  /// 适用于 Tooltip 出现与消失、边框颜色渐退。
  static const Curve out = Curves.easeOut;

  /// 线性匀速 (`linear`)
  ///
  /// 适用于流光扫掠、骨架脉冲、加载循环。
  static const Curve linear = Curves.linear;

  /// 轻微回弹曲线 (`cubic-bezier(0.34, 1.36, 0.64, 1.0)`)
  ///
  /// **警告：该曲线在收尾阶段会过冲大于 1.0。仅限空间位移、缩放等几何变换使用，**
  /// **严禁用于透明度 (Opacity)、颜色插值或模糊半径 (Blur sigma)，否则会触发越界断言或视觉闪烁。**
  static const Curve bounce = Cubic(0.34, 1.36, 0.64, 1.0);

  /// 强力弹簧回弹曲线 (`cubic-bezier(0.34, 3.85, 0.64, 1.0)`)
  ///
  /// **警告：该曲线会产生大幅度过冲 (> 1.0)。仅限空间位移、缩放等几何变换 (如悬停回弹) 使用，**
  /// **严禁用于透明度 (Opacity)、颜色插值或模糊半径 (Blur sigma)。**
  static const Curve bounceStrong = Cubic(0.34, 3.85, 0.64, 1.0);

  /// 数字弹出过冲曲线 (`cubic-bezier(0.34, 1.45, 0.64, 1.0)`)
  ///
  /// **警告：仅限空间位移、缩放等几何变换使用，严禁用于透明度或模糊半径。**
  static const Curve digitPop = Cubic(0.34, 1.45, 0.64, 1.0);

  /// 开关与勾选微弹跳曲线 (`cubic-bezier(0.34, 1.35, 0.64, 1.0)`)
  ///
  /// **警告：仅限空间位移、缩放等几何变换使用，严禁用于透明度或模糊半径。**
  static const Curve toggleBounce = Cubic(0.34, 1.35, 0.64, 1.0);

  /// 退场加速曲线 (`cubic-bezier(0.4, 0.0, 0.2, 1.0)`)
  static const Curve closeEase = Cubic(0.4, 0.0, 0.2, 1.0);

  /// 滚轮数字平滑减速曲线 (`cubic-bezier(0.16, 1.0, 0.3, 1.0)`)
  static const Curve reel = Cubic(0.16, 1.0, 0.3, 1.0);
}

/// 全局动效位移动距令牌 (Motion Distance Tokens, 逻辑像素 dp)
abstract final class AppMotionDistances {
  /// 4.0 - 微位移 (文本原地切换 `--distance-micro` / 错误晃动回弹 `--shake-overshoot`)
  static const double micro = 4.0;

  /// 6.0 - 小位移 (错误晃动主摆幅 `--distance-small`)
  static const double small = 6.0;

  /// 8.0 - 基础位移 (数字弹出、页面侧滑、思考状态切换 `--distance-base`)
  static const double base = 8.0;

  /// 12.0 - 中位移 (交错文本揭示 `--distance-medium`)
  static const double medium = 12.0;

  /// 16.0 - Toast 升起位移 (`--toast-distance`)
  static const double toast = 16.0;

  /// 30.0 - 强调大位移 (`--distance-large`)
  static const double large = 30.0;

  /// 100.0 - 展开面板位移参考 (`--panel-translate-y`)
  static const double panel = 100.0;

  /// 4.0 - 错误晃动二次回弹幅度 (`--shake-overshoot`)
  static const double shakeOvershoot = 4.0;

  /// -4.0 - 悬停向上抬升偏移 (`--avatar-lift`)
  static const double avatarLift = -4.0;
}

/// 全局动效缩放系数令牌 (Motion Scale Tokens)
abstract final class AppMotionScales {
  /// 0.96 - 模态对话框入场/退场缩放 (`--scale-large` / `--modal-scale`)
  static const double modal = 0.96;

  /// 0.97 - 下拉菜单/Toast 入场缩放 (`--scale-medium` / `--dropdown-pre-scale`)
  static const double dropdown = 0.97;

  /// 0.98 - Tooltip 入场缩放 (`--scale-small` / `--tt-scale`)
  static const double tooltip = 0.98;

  /// 0.99 - 下拉菜单退场缩放 (`--scale-tiny` / `--dropdown-closing-scale`)
  static const double dropdownClose = 0.99;

  /// 0.25 - 图标切换起始缩微比例 (`--icon-swap-start-scale`)
  static const double iconSwapStart = 0.25;

  /// 1.05 - 悬停元素强调放大比例 (`--avatar-scale`)
  static const double avatarHover = 1.05;
}

/// 全局动效高斯模糊半径令牌 (Motion Blur Sigma Tokens)
abstract final class AppMotionBlurs {
  /// 2.0 - 轻量模糊 (图标切换、文本切换、面板揭示、数字弹出 `--blur-small`)
  static const double small = 2.0;

  /// 3.0 - 中等模糊 (页面侧滑、交错文本揭示 `--blur-medium`)
  static const double medium = 3.0;

  /// 8.0 - 强模糊 (强调入场 `--blur-large`)
  static const double large = 8.0;
}

/// 动效辅助工具与无障碍减弱动画判定
abstract final class AppMotion {
  /// 检测系统/用户是否开启了「减弱动态效果」(prefers-reduced-motion)
  static bool shouldReduceMotion(BuildContext context) {
    return MediaQuery.disableAnimationsOf(context);
  }

  /// 在减弱动态效果开启时将时长归零，否则返回原始 [duration]
  static Duration resolveDuration(BuildContext context, Duration duration) {
    return shouldReduceMotion(context) ? Duration.zero : duration;
  }

  /// 在减弱动态效果开启时退回线性曲线，否则返回原始 [curve]
  static Curve resolveCurve(BuildContext context, Curve curve) {
    return shouldReduceMotion(context) ? Curves.linear : curve;
  }
}
