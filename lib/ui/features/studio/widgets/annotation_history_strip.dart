import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../view_models/studio_view_model.dart';
import 'image_canvas_actions.dart';

/// 批注模式下右侧收缩替换面板：极简垂直历史与参考图卡片条 (支持点击切换主图，支持拖拽放置到大画布)
class AnnotationHistoryStrip extends StatelessWidget {
  final StudioViewModel viewModel;

  const AnnotationHistoryStrip({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final gallery = viewModel.gallery;
    final selectedId = viewModel.selectedImage?.id;
    final colors = context.colors;
    final l10n = context.l10n;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colors.cardBackground,
          border: Border(left: BorderSide(color: colors.borderDefault)),
        ),
        child: Column(
          children: [
            // 1. 极简顶栏：History 计数与收起按键 (对齐设计图 History 13 ▶)
            InkWell(
              onTap: () => viewModel.board.setAnnotatingImage(false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderDefault),
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: l10n.annotHistoryTitle,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: '${gallery.length}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: colors.primary,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Icon(
                      Icons.arrow_right_rounded,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // 2. 垂直历史缩略图流 (支持 Draggable 拖拽到左侧自由大画布)
            Expanded(
              child: gallery.isEmpty
                  ? AppEmptyState(
                      icon: Icons.photo_library_outlined,
                      title: l10n.annotHistoryEmpty,
                      isCompact: true,
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(8),
                      itemCount: gallery.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = gallery[index];
                        final isSelected = item.id == selectedId;
                        final annCount = item.annotations.length;

                        final thumbnailWidget = Container(
                          width: double.infinity,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            border: Border.all(
                              color: isSelected
                                  ? colors.primary
                                  : colors.borderDefault,
                              width: isSelected ? 2.0 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: colors.primary.withValues(
                                        alpha: 0.18,
                                      ),
                                      blurRadius: 6,
                                      offset: const Offset(0, 2),
                                    ),
                                  ]
                                : null,
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: AspectRatio(
                            aspectRatio:
                                (item.params.width / item.params.height).clamp(
                                  0.5,
                                  1.8,
                                ),
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                Builder(
                                  builder: (context) {
                                    final thumb =
                                        item.thumbnailBytes ??
                                        (item.bytes.isNotEmpty
                                            ? item.bytes
                                            : null);
                                    if (thumb != null && thumb.isNotEmpty) {
                                      return Image.memory(
                                        thumb,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      );
                                    }
                                    return Container(
                                      color: colors.mutedBackground,
                                    );
                                  },
                                ),
                                // 批注条数徽章
                                if (annCount > 0)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: AppBadge(
                                      label: '$annCount',
                                      variant: AppBadgeVariant.primary,
                                      shape: AppBadgeShape.pill,
                                      fontSize: 10,
                                    ),
                                  ),
                                // 外部参考图 REF 标记
                                if (item.isImportedReference)
                                  const Positioned(
                                    bottom: 4,
                                    left: 4,
                                    child: AppBadge(
                                      label: 'REF',
                                      variant: AppBadgeVariant.dark,
                                      fontSize: 9,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );

                        return Draggable<NaiGeneratedImage>(
                          data: item,
                          feedback: Material(
                            elevation: 8,
                            borderRadius: BorderRadius.circular(8),
                            clipBehavior: Clip.antiAlias,
                            child: SizedBox(
                              width: 100,
                              height: 120,
                              child: Builder(
                                builder: (context) {
                                  final thumb =
                                      item.thumbnailBytes ??
                                      (item.bytes.isNotEmpty
                                          ? item.bytes
                                          : null);
                                  if (thumb != null && thumb.isNotEmpty) {
                                    return Image.memory(
                                      thumb,
                                      fit: BoxFit.cover,
                                    );
                                  }
                                  return Container(
                                    color: colors.mutedBackground,
                                  );
                                },
                              ),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: 0.35,
                            child: thumbnailWidget,
                          ),
                          child: GestureDetector(
                            onTap: () {
                              viewModel.board.addImageNodeToBoard(item);
                              showCanvasSnackBar(
                                context,
                                l10n.annotHistoryAddedAsReference,
                              );
                            },
                            child: thumbnailWidget,
                          ),
                        );
                      },
                    ),
            ),

            // 3. 底部导入本地参考图入口
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderDefault)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Tooltip(
                  message: l10n.annotHistoryImportTooltip,
                  child: InkWell(
                    onTap: () =>
                        pickAndImportReferenceImage(context, viewModel),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: colors.mutedBackground,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        border: Border.all(color: colors.borderDefault),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 16,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.annotHistoryImportImage,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
