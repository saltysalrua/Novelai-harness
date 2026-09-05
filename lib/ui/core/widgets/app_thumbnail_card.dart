import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 缩略图角标方位 (默认右上，对齐 canvas_history_sidebar 既有规范)
enum AppThumbnailBadgePosition { topLeft, topRight }

/// 统一历史缩略图与画廊图片卡片组件
///
/// 整合原 _HistoryThumbShell、PromptComboCard 缩略外壳与参考图外壳，
/// 具备：统一的圆角、长宽比钳制、选中高亮描边、微阴影、Hover 动效、
/// 可配置方位的角标覆盖层，以及悬停时浮现的操作栏扩展槽
/// (自动落在角标的对侧角落，互不遮挡)。
class AppThumbnailCard extends StatefulWidget {
  final Uint8List? imageBytes;
  final Widget? imageWidget;
  final double aspectRatio;
  final bool isSelected;
  final String? badgeLabel;
  final Color? badgeColor;

  /// 角标方位 (默认右上，对齐既有画板历史侧栏规范)
  final AppThumbnailBadgePosition badgePosition;
  final VoidCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;
  final double radius;
  final int? cacheWidth;

  /// 悬停操作栏扩展槽 (如删除按钮/管理操作组)，悬停时淡入，
  /// 自动落在 [badgePosition] 的对侧角落
  final Widget? hoverActions;

  const AppThumbnailCard({
    super.key,
    this.imageBytes,
    this.imageWidget,
    this.aspectRatio = 1.0,
    this.isSelected = false,
    this.badgeLabel,
    this.badgeColor,
    this.badgePosition = AppThumbnailBadgePosition.topRight,
    this.onTap,
    this.onSecondaryTapUp,
    this.radius = AppRadius.md,
    this.cacheWidth = 240,
    this.hoverActions,
  }) : assert(
         imageBytes != null || imageWidget != null,
         '必须提供 imageBytes 或 imageWidget 其一',
       );

  @override
  State<AppThumbnailCard> createState() => _AppThumbnailCardState();
}

class _AppThumbnailCardState extends State<AppThumbnailCard> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isSelected = widget.isSelected;
    final clampedRatio = widget.aspectRatio.clamp(0.5, 2.0);
    final badgeOnLeft =
        widget.badgePosition == AppThumbnailBadgePosition.topLeft;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTapUp: widget.onSecondaryTapUp,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: colors.mutedBackground,
            borderRadius: BorderRadius.circular(widget.radius),
            border: Border.all(
              color: isSelected
                  ? colors.primary
                  : (_isHovered ? colors.borderHover : colors.borderDefault),
              width: isSelected ? 2.0 : 1.0,
            ),
            boxShadow: isSelected
                ? AppShadows.subtle(
                    colors.primary,
                    brightness: context.themeBrightness,
                  )
                : (_isHovered
                      ? AppShadows.subtle(
                          Colors.black,
                          brightness: context.themeBrightness,
                        )
                      : null),
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: clampedRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 图片渲染
                if (widget.imageWidget != null)
                  widget.imageWidget!
                else if (widget.imageBytes != null)
                  Image.memory(
                    widget.imageBytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    cacheWidth: widget.cacheWidth,
                  ),

                // 角标覆盖层 (如 "放大" / "未保存" / "修复" / "AI编辑")
                if (widget.badgeLabel != null)
                  Positioned(
                    top: 5,
                    left: badgeOnLeft ? 5 : null,
                    right: badgeOnLeft ? null : 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: (widget.badgeColor ?? colors.primary).withValues(
                          alpha: 0.88,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.2),
                            blurRadius: 3,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.badgeLabel!,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          height: 1.1,
                        ),
                      ),
                    ),
                  ),

                // 悬停操作栏扩展槽：落在角标对侧角落，未悬停时隐藏且不拦截手势
                if (widget.hoverActions != null)
                  Positioned(
                    top: 5,
                    left: badgeOnLeft ? null : 5,
                    right: badgeOnLeft ? 5 : null,
                    child: IgnorePointer(
                      ignoring: !_isHovered,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 120),
                        opacity: _isHovered ? 1.0 : 0.0,
                        child: widget.hoverActions,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
