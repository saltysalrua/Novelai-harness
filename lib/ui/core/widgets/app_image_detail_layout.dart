import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 图片详情双区布局：大图优先，工具栏在图外，详情独立滚动。
///
/// 仅负责布局与预览手势，不持有业务状态。窄窗口改为上下分区，
/// 不把大图缩成缩略图，也不允许缩放后的画面溢出遮盖工具或表单。
class AppImageDetailLayout extends StatelessWidget {
  final ImageProvider<Object>? image;
  final Widget placeholder;
  final Widget? previewFooter;
  final Widget details;

  const AppImageDetailLayout({
    super.key,
    required this.image,
    required this.placeholder,
    required this.details,
    this.previewFooter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final preview = ColoredBox(
      color: colors.mutedBackground,
      child: ClipRect(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: image == null
              ? placeholder
              : InteractiveViewer(
                  key: ValueKey(image),
                  minScale: 1,
                  maxScale: 5,
                  child: SizedBox.expand(
                    child: Image(
                      image: image!,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => placeholder,
                    ),
                  ),
                ),
        ),
      ),
    );
    final footer = previewFooter == null
        ? null
        : Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: colors.elevatedBackground,
              border: Border(top: BorderSide(color: colors.borderDefault)),
            ),
            child: previewFooter,
          );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 900) {
          // 先给换行工具栏分配高度，再分配图文空间，避免长文案挤小图片。
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(flex: 3, child: preview),
              ?footer,
              Divider(height: 1, thickness: 1, color: colors.borderDefault),
              Expanded(flex: 2, child: details),
            ],
          );
        }
        final detailsWidth = (constraints.maxWidth * 0.4).clamp(340.0, 480.0);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: preview),
                  ?footer,
                ],
              ),
            ),
            VerticalDivider(
              width: 1,
              thickness: 1,
              color: colors.borderDefault,
            ),
            SizedBox(width: detailsWidth, child: details),
          ],
        );
      },
    );
  }
}
