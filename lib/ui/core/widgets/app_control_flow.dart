import 'package:flutter/material.dart';

/// 尾部控件流式排布容器 (设置项 / 工具条通用原子组件)
///
/// 宽屏空间充足时所有子控件单行自然排布 (与 `Row(mainAxisSize: min)` 等效)；
/// 宽度不足时自动折行，彻底杜绝窄屏 RenderFlex 溢出。
///
/// - 放在 [AppSettingTile] 的 `control` 槽位时：宽屏由外层 Row 收窄标题、
///   窄屏由 Tile 折到标题下方，本组件在两种形态下都不溢出。
/// - 需要整行铺满并对齐 (如首尾分居) 时，外包 `SizedBox(width: double.infinity)`
///   再配合 `alignment: WrapAlignment.spaceBetween`。
class AppControlFlow extends StatelessWidget {
  /// 子控件列表 (间距由 [spacing] / [runSpacing] 统一控制，勿混入 SizedBox 占位)
  final List<Widget> children;

  /// 同行相邻子控件间距
  final double spacing;

  /// 折行后行间距
  final double runSpacing;

  /// 行内对齐方式 (仅在折行后的短行上有可分布空隙时生效)
  final WrapAlignment alignment;

  /// 行间纵向对齐方式
  final WrapCrossAlignment crossAxisAlignment;

  const AppControlFlow({
    super.key,
    required this.children,
    this.spacing = 8,
    this.runSpacing = 8,
    this.alignment = WrapAlignment.start,
    this.crossAxisAlignment = WrapCrossAlignment.center,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: spacing,
      runSpacing: runSpacing,
      alignment: alignment,
      crossAxisAlignment: crossAxisAlignment,
      children: children,
    );
  }
}