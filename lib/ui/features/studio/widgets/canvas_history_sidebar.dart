import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
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
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
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

/// History 标头 (标题 + 数量 + 收起箭头)
class HistorySidebarHeader extends StatelessWidget {
  final int galleryCount;
  final VoidCallback? onCollapse;

  const HistorySidebarHeader({
    super.key,
    required this.galleryCount,
    this.onCollapse,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onCollapse,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: AppTheme.border)),
        ),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'History',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (galleryCount > 0) ...[
              Text(
                '$galleryCount',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.notionBlue,
                ),
              ),
              const SizedBox(width: 2),
            ],
            const Icon(
              Icons.arrow_right_rounded,
              size: 20,
              color: AppTheme.textPrimary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 缩略图外壳：统一的手势、选中态描边与阴影装饰
class _HistoryThumbShell extends StatelessWidget {
  final bool isSelected;
  final double aspectRatio;
  final Widget content;
  final GestureTapCallback? onTap;
  final GestureTapUpCallback? onSecondaryTapUp;

  const _HistoryThumbShell({
    required this.isSelected,
    required this.aspectRatio,
    required this.content,
    this.onTap,
    this.onSecondaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onSecondaryTapUp: onSecondaryTapUp,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppTheme.notionBlue : AppTheme.border,
            width: 2.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.notionBlue.withValues(alpha: 0.2),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        clipBehavior: Clip.antiAlias,
        child: AspectRatio(
          aspectRatio: aspectRatio.clamp(0.5, 2.0),
          child: content,
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
    return _HistoryThumbShell(
      isSelected: isSelected,
      aspectRatio: imageAspectRatioOf(item.params),
      onTap: () {
        viewModel.selectImage(item);
        if (scrollToStream) stream.scrollToItem(index, item.id);
      },
      onSecondaryTapUp: (details) => showImageContextMenu(
        context,
        position: details.globalPosition,
        viewModel: viewModel,
        image: item,
      ),
      content: Image.memory(
        item.uint8Bytes,
        fit: BoxFit.cover,
        gaplessPlayback: true,
        // 侧栏缩略图宽约 104px，按 2x 解码已够清晰，避免全分辨率纹理
        cacheWidth: 240,
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
    final previewBytes = viewModel.livePreviewBytes;
    return _HistoryThumbShell(
      isSelected: viewModel.isViewingLatest,
      aspectRatio: imageAspectRatioOf(viewModel.params),
      onTap: () {
        viewModel.selectLatestImage();
        stream.scrollToTop();
      },
      content: previewBytes != null
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
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.0,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.notionBlue,
                      ),
                    ),
                  ),
                  if (viewModel.liveTotalSteps > 0 &&
                      viewModel.liveCurrentStep > 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${viewModel.liveCurrentStep}/${viewModel.liveTotalSteps}',
                      style: const TextStyle(
                        fontSize: 9,
                        color: AppTheme.textSecondary,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
    );
  }
}

class _HistoryEmptyState extends StatelessWidget {
  const _HistoryEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.history_rounded,
            size: 24,
            color: AppTheme.stone.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 6),
          const Text(
            '暂无历史',
            style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }
}
