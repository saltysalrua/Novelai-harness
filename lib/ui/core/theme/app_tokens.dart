import 'package:flutter/material.dart';

/// 全局设计系统度量令牌 (Design Tokens)
///
/// 统一管理应用内的间距、圆角与阴影规范，彻底消灭孤立魔法数字。

/// 统一间距标尺
abstract final class AppSpacing {
  /// 4.0 - 微型间距 (图标与文字间隙、内边距微调)
  static const double xs = 4.0;

  /// 8.0 - 小型间距 (紧凑排列、列表间隔、卡片内边距)
  static const double sm = 8.0;

  /// 12.0 - 中型间距 (标准卡片内边距、控件间距)
  static const double md = 12.0;

  /// 16.0 - 宽松间距 (页面边距、区域分隔)
  static const double lg = 16.0;

  /// 20.0 - 大型间距 (主卡片内边距、分组间距)
  static const double xl = 20.0;

  /// 24.0 - 超大间距 (全屏外边距、弹窗外边距)
  static const double xxl = 24.0;
}

/// 统一圆角标尺
abstract final class AppRadius {
  /// 4.0 - 胶囊微圆角 (Badge、微型 Tag)
  static const double sm = 4.0;

  /// 8.0 - 标准圆角 (输入框、按钮、下拉框、小卡片)
  static const double md = 8.0;

  /// 12.0 - 大圆角 (主面板卡片、弹窗)
  static const double lg = 12.0;

  /// 9999.0 - 药丸圆角 (Pill 选择器、椭圆徽章)
  static const double pill = 9999.0;
}

/// 统一阴影层级
abstract final class AppShadows {
  /// 卡片微弱浮起 (微质感，适合工作台悬浮操作坞)
  static List<BoxShadow> subtle(Color shadowColor) => [
        BoxShadow(
          color: shadowColor.withValues(alpha: 0.06),
          blurRadius: 8,
          offset: const Offset(0, 2),
        ),
      ];

  /// 下拉菜单与浮动弹出层
  static List<BoxShadow> elevated(Color shadowColor) => [
        BoxShadow(
          color: shadowColor.withValues(alpha: 0.12),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];

  /// 模态居中弹窗
  static List<BoxShadow> dialog(Color shadowColor) => [
        BoxShadow(
          color: shadowColor.withValues(alpha: 0.20),
          blurRadius: 28,
          offset: const Offset(0, 8),
        ),
      ];
}
