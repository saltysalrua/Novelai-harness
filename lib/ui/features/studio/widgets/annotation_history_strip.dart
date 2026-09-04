import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
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

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          color: AppTheme.pureWhite,
          border: Border(left: BorderSide(color: AppTheme.border)),
        ),
        child: Column(
          children: [
            // 1. 极简顶栏：History 计数与收起按键 (对齐设计图 History 13 ▶)
            InkWell(
              onTap: () => viewModel.setAnnotatingImage(false),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                decoration: const BoxDecoration(
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(
                              text: 'History ',
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            TextSpan(
                              text: '${gallery.length}',
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.notionBlue,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const Icon(
                      Icons.arrow_right_rounded,
                      size: 16,
                      color: AppTheme.textSecondary,
                    ),
                  ],
                ),
              ),
            ),

            // 2. 垂直历史缩略图流 (支持 Draggable 拖拽到左侧自由大画布)
            Expanded(
              child: gallery.isEmpty
                  ? const Center(
                      child: Text(
                        '无图片',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textMuted,
                        ),
                      ),
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
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.notionBlue
                                  : AppTheme.border,
                              width: isSelected ? 2.0 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: AppTheme.notionBlue.withValues(
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
                                    final thumb = item.thumbnailBytes ??
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
                                      color: AppTheme.surfaceMuted,
                                    );
                                  },
                                ),
                                // 批注条数徽章
                                if (annCount > 0)
                                  Positioned(
                                    top: 4,
                                    right: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1.5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppTheme.notionBlue,
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '$annCount',
                                        style: const TextStyle(
                                          fontSize: 9.5,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                // 外部参考图 REF 标记
                                if (item.isImportedReference)
                                  Positioned(
                                    bottom: 4,
                                    left: 4,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black87,
                                        borderRadius: BorderRadius.circular(3),
                                      ),
                                      child: const Text(
                                        'REF',
                                        style: TextStyle(
                                          fontSize: 8.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
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
                                  final thumb = item.thumbnailBytes ??
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
                                    color: AppTheme.surfaceMuted,
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
                              viewModel.addImageNodeToBoard(item);
                              showCanvasSnackBar(context, '已将历史图片添加为大画布参考图');
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
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: SizedBox(
                width: double.infinity,
                child: Tooltip(
                  message: '导入本地图片为参考图',
                  child: InkWell(
                    onTap: () =>
                        pickAndImportReferenceImage(context, viewModel),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: AppTheme.paperWarmth,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: const Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_photo_alternate_outlined,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                          SizedBox(height: 2),
                          Text(
                            '导入图片',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
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
