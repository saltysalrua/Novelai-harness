import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一全屏/全区域拖拽吸附覆层指示器 (AppDropTargetOverlay)
///
/// 代码证据出处：
/// - `freeform_annotation_board.dart:413-468` (画板外部/内部图片拖入高亮指示器)
/// - `image_canvas_card.dart:190-234` (主画布图片文件拖入高亮指示器)
///
/// 核心职责：
/// 极简参数化驱动组件 `(isDragging, icon, title, subtitle)`，彻底消灭画布与自由画板中
/// 完全相同的 40+ 行 `Positioned.fill + 10%蓝底 + 3px蓝边框 + 居中下载卡片` 重复代码。
class AppDropTargetOverlay extends StatelessWidget {
  /// 是否正处于拖拽悬停吸附态
  final bool isDragging;

  /// 居中提示卡片的图标，默认 [Icons.file_download_outlined]
  final IconData icon;

  /// 主标题提示文案，默认 '松开鼠标导入图片'
  final String title;

  /// 副标题辅助文案 (可选，如 '自动识别生成元数据')
  final String? subtitle;

  /// 自定义外层背景色 (覆盖预设 10% 主题主色)
  final Color? backgroundColor;

  /// 自定义外层高亮边框色 (覆盖预设主题主色)
  final Color? borderColor;

  /// 边框粗细，默认 3.0
  final double borderWidth;

  /// 是否自动包裹为 [Positioned.fill] (放置在 Stack 顶层时非常方便)，默认 true
  final bool usePositionedFill;

  const AppDropTargetOverlay({
    super.key,
    required this.isDragging,
    this.icon = Icons.file_download_outlined,
    this.title = '松开鼠标导入图片',
    this.subtitle,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 3.0,
    this.usePositionedFill = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!isDragging) {
      return const SizedBox.shrink();
    }

    final colors = context.colors;
    final effectiveBg =
        backgroundColor ?? colors.primary.withValues(alpha: 0.10);
    final effectiveBorder = borderColor ?? colors.primary;

    Widget overlay = IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          color: effectiveBg,
          border: Border.all(color: effectiveBorder, width: borderWidth),
        ),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(AppRadius.md),
              boxShadow: context.shadowElevated,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 22, color: effectiveBorder),
                const SizedBox(width: 8),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (usePositionedFill) {
      overlay = Positioned.fill(child: overlay);
    }

    return overlay;
  }
}
