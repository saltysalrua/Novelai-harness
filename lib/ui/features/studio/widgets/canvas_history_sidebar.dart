import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_thumbnail_card.dart';
import '../../../core/widgets/app_transitions.dart';
import '../view_models/studio_view_model.dart';
import 'image_canvas_actions.dart';
import 'image_stream_view.dart';

/// 右侧垂直缩略图 History 侧边栏 (点选定位画板流、右键同款菜单)
class CanvasHistorySidebar extends StatelessWidget {
  final StudioViewModel viewModel;
  final NaiGeneratedImage? selectedImage;
  final CanvasStreamController stream;
  final VoidCallback onClose;

  const CanvasHistorySidebar({
    super.key,
    required this.viewModel,
    required this.selectedImage,
    required this.stream,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final gallery = viewModel.gallery;
    final isGenerating = viewModel.isGenerating;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部 History 标头 (点击收起)
        HistorySidebarHeader(galleryCount: gallery.length, onCollapse: onClose),
        Expanded(
          child: gallery.isEmpty && !isGenerating
              ? const _HistoryEmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                  itemCount: isGenerating ? gallery.length + 1 : gallery.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    // 生成中时头部是实时预览缩略图
                    if (isGenerating && index == 0) {
                      return _GeneratingHistoryThumb(
                        viewModel: viewModel,
                        stream: stream,
                      );
                    }
                    final item = gallery[isGenerating ? index - 1 : index];
                    final isSelected = isGenerating
                        ? !viewModel.isViewingLatest &&
                              selectedImage?.id == item.id
                        : selectedImage?.id == item.id;
                    return _ImageHistoryThumb(
                      viewModel: viewModel,
                      stream: stream,
                      item: item,
                      isSelected: isSelected,
                      // 单图且未生成时已在画板居中，无需滚动定位
                      scrollToStream: isGenerating || gallery.length > 1,
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// History 标头 (标题 + 数量徽章 + 收起按键，42px 高度与右侧会话栏顶栏对齐)
class HistorySidebarHeader extends StatelessWidget {
  final int galleryCount;
  final VoidCallback? onCollapse;

  const HistorySidebarHeader({
    super.key,
    required this.galleryCount,
    this.onCollapse,
  });

  void _handleCollapse() {
    Tooltip.dismissAllToolTips();
    onCollapse?.call();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onCollapse != null ? _handleCollapse : null,
        child: Container(
          height: 42,
          padding: const EdgeInsets.fromLTRB(10, 0, 6, 0),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: colors.borderDefault)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        context.l10n.history,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (galleryCount > 0) ...[
                      const SizedBox(width: 4),
                      Text(
                        '$galleryCount',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          fontFeatures: const [FontFeature.tabularFigures()],
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 2),
              AppIconButton(
                key: const Key('canvas_collapse_history_button'),
                icon: Icons.keyboard_double_arrow_right_rounded,
                size: 26,
                iconSize: 16,
                variant: AppIconButtonVariant.ghost,
                tooltip: context.l10n.sidebarCollapse,
                onPressed: onCollapse != null ? _handleCollapse : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 历史图缩略图 (点击选中并定位画板流，右键同款菜单)
class _ImageHistoryThumb extends StatelessWidget {
  final StudioViewModel viewModel;
  final CanvasStreamController stream;
  final NaiGeneratedImage item;
  final bool isSelected;
  final bool scrollToStream;

  const _ImageHistoryThumb({
    required this.viewModel,
    required this.stream,
    required this.item,
    required this.isSelected,
    required this.scrollToStream,
  });

  @override
  Widget build(BuildContext context) {
    final index = viewModel.gallery.indexOf(item);
    final thumb =
        item.thumbnailBytes ?? (item.bytes.isNotEmpty ? item.bytes : null);

    return AppThumbnailCard(
      isSelected: isSelected,
      aspectRatio: imageAspectRatioOf(item.params),
      imageBytes: thumb,
      imageWidget: thumb == null
          ? const AppSkeletonBox(
              width: double.infinity,
              height: double.infinity,
              radius: 0,
            )
          : null,
      cacheWidth: 240,
      badgeLabel: historyBadgeLabelOf(context.l10n, item.provenance),
      badgeColor: Colors.black.withValues(alpha: 0.72),
      onTap: () {
        viewModel.selectImage(item);
        if (scrollToStream) stream.scrollToItem(index, item.id);
      },
      onContextMenu: (position) => showImageContextMenu(
        context,
        position: position,
        viewModel: viewModel,
        image: item,
      ),
    );
  }
}

/// 生成中实时预览缩略图 (去噪中间步 + 步数，点击回到最新)
class _GeneratingHistoryThumb extends StatelessWidget {
  final StudioViewModel viewModel;
  final CanvasStreamController stream;

  const _GeneratingHistoryThumb({
    required this.viewModel,
    required this.stream,
  });

  @override
  Widget build(BuildContext context) {
    return AppThumbnailCard(
      isSelected: viewModel.isViewingLatest,
      aspectRatio: imageAspectRatioOf(viewModel.params),
      onTap: () {
        viewModel.selectLatestImage();
        stream.scrollToTop();
      },
      // 去噪中间帧仅在缩略图内部局部重绘，生成期间侧栏零重建
      imageWidget: ListenableBuilder(
        listenable: viewModel.liveProgressController,
        builder: (context, _) {
          final previewBytes = viewModel.livePreviewBytes;
          return previewBytes != null
              ? Image.memory(
                  previewBytes,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                  // 预览帧每步全量重解码，按缩略图尺寸解码降低 UI 线程压力
                  cacheWidth: 240,
                )
              : Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppMatrixDotLoader(
                        dotSize: 2.5,
                        gap: 2.0,
                        variant: AppMatrixDotVariant.pulse,
                        activeColor: context.colors.primary,
                      ),
                      if (viewModel.liveTotalSteps > 0 &&
                          viewModel.liveCurrentStep > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '${viewModel.liveCurrentStep}/${viewModel.liveTotalSteps}',
                          style: TextStyle(
                            fontSize: 9,
                            color: context.colors.textSecondary,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
        },
      ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return AppEmptyState(
      icon: Icons.history_rounded,
      title: context.l10n.canvasHistoryEmpty,
      isCompact: true,
    );
  }
}
