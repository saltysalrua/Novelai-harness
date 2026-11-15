import 'package:flutter/material.dart';
import '../context_l10n.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一全屏/全区域拖拽吸附覆层指示器 (AppDropTargetOverlay, `07-panel-reveal`)
///
/// 代码证据出处：
/// - `freeform_annotation_board.dart:413-468` (画板外部/内部图片拖入高亮指示器)
/// - `image_canvas_card.dart:190-234` (主画布图片文件拖入高亮指示器)
///
/// 核心职责：
/// 极简参数化驱动组件 `(isDragging, icon, title, subtitle)`，拖入悬停时以平滑淡入 +
/// `0.97 -> 1.0` 缩放揭示，离开时平滑收起，并安全适配系统减弱动画设置。
class AppDropTargetOverlay extends StatefulWidget {
  /// 是否正处于拖拽悬停吸附态
  final bool isDragging;

  /// 居中提示卡片的图标，默认 [Icons.file_download_outlined]
  final IconData icon;

  /// 主标题提示文案，默认 '松开鼠标导入图片'
  final String? title;

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
    this.title,
    this.subtitle,
    this.backgroundColor,
    this.borderColor,
    this.borderWidth = 3.0,
    this.usePositionedFill = true,
  });

  @override
  State<AppDropTargetOverlay> createState() => _AppDropTargetOverlayState();
}

class _AppDropTargetOverlayState extends State<AppDropTargetOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _curved;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.fast,
      reverseDuration: AppMotionDurations.quick,
      value: widget.isDragging ? 1.0 : 0.0,
    );
    _curved = _controller.drive(CurveTween(curve: AppMotionCurves.smoothOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = widget.isDragging ? 1.0 : 0.0;
    }
  }

  @override
  void didUpdateWidget(covariant AppDropTargetOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isDragging != widget.isDragging) {
      if (_reduceMotion) {
        _controller.value = widget.isDragging ? 1.0 : 0.0;
      } else if (widget.isDragging) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveBg =
        widget.backgroundColor ?? colors.primary.withValues(alpha: 0.10);
    final effectiveBorder = widget.borderColor ?? colors.primary;

    final card = Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: context.shadowElevated,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(widget.icon, size: 22, color: effectiveBorder),
          const SizedBox(width: 8),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title ?? context.maybeL10n?.commonDropImage ?? '松开鼠标导入图片',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              if (widget.subtitle != null && widget.subtitle!.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  widget.subtitle!,
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ],
          ),
        ],
      ),
    );

    final Widget overlay = IgnorePointer(
      child: AnimatedBuilder(
        animation: _curved,
        builder: (context, child) {
          if (_controller.isDismissed && !widget.isDragging) {
            return const SizedBox.shrink();
          }

          final t = _reduceMotion
              ? (widget.isDragging ? 1.0 : 0.0)
              : _curved.value.clamp(0.0, 1.0);
          final scale =
              AppMotionScales.dropdown + (1.0 - AppMotionScales.dropdown) * t;

          return Opacity(
            opacity: t,
            child: Container(
              decoration: BoxDecoration(
                color: effectiveBg,
                border: Border.all(
                  color: effectiveBorder,
                  width: widget.borderWidth,
                ),
              ),
              child: Center(
                child: Transform.scale(scale: scale, child: child),
              ),
            ),
          );
        },
        child: card,
      ),
    );

    if (widget.usePositionedFill) {
      return Positioned.fill(child: overlay);
    }

    return overlay;
  }
}
