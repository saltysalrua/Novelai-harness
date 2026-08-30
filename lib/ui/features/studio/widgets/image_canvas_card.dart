import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_history_sidebar.dart';
import 'canvas_overlays.dart';
import 'character_position_canvas_view.dart';
import 'image_stream_view.dart';

/// 中间画板卡片：垂直图像流 + 可收起历史侧边栏 + 浮动徽章/横幅 + 角色位置交互画板
class ImageCanvasCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const ImageCanvasCard({super.key, required this.viewModel});

  @override
  State<ImageCanvasCard> createState() => _ImageCanvasCardState();
}

class _ImageCanvasCardState extends State<ImageCanvasCard> {
  bool _isHistoryOpen = false;
  late final CanvasStreamController _stream = CanvasStreamController();

  @override
  void dispose() {
    _stream.dispose();
    super.dispose();
  }

  void _viewLatest() {
    widget.viewModel.selectLatestImage();
    _stream.scrollToTop();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final gallery = viewModel.gallery;
    final isGenerating = viewModel.isGenerating;
    final isEditingPositions = viewModel.isEditingCharacterPositions;
    final selectedImage =
        viewModel.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);

    final showEmptyState = gallery.isEmpty && !isGenerating && !isEditingPositions;

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: AppTheme.paperWarmth, // Notion 统一暖纸本底色
        child: Stack(
          children: [
            // 1. 中间核心：上下滑动的垂直图像瀑布流 (单图居中 / 多图平滑瀑布流 / 临时位置占位卡片)
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1.1 主画布垂直无限滑动图像流
                  Expanded(
                    child: showEmptyState
                        ? const CanvasEmptyState()
                        : ImageStreamView(
                            viewModel: viewModel,
                            controller: _stream,
                          ),
                  ),

                  // 1.2 右侧垂直 History 缩略图侧边栏 (Notion 蓝白纯净卡片)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: (_isHistoryOpen && !isEditingPositions) ? 120 : 0,
                    curve: Curves.easeInOut,
                    clipBehavior: Clip.antiAlias,
                    decoration: const BoxDecoration(
                      color: AppTheme.pureWhite,
                      border: Border(left: BorderSide(color: AppTheme.border)),
                    ),
                    child: OverflowBox(
                      minWidth: 120,
                      maxWidth: 120,
                      alignment: Alignment.topRight,
                      child: CanvasHistorySidebar(
                        viewModel: viewModel,
                        selectedImage: selectedImage,
                        stream: _stream,
                        onClose: () => setState(() => _isHistoryOpen = false),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 2. 角色位置编辑模式下的悬浮浮动操作层 (顶部角色切换芯片 + 右下角完成编辑微胶囊)
            if (isEditingPositions)
              Positioned.fill(
                child: CanvasPositionFloatingControls(viewModel: viewModel),
              ),

            // 3. 左下角浮动参数徽章 (非位置编辑模式且选中图片时展示)
            if (selectedImage != null && !isEditingPositions)
              Positioned(
                bottom: 18,
                left: 18,
                child: CanvasParamBadges(image: selectedImage),
              ),

            // 4. 右上角浮动 History 展开按键 (仅在收回状态且非编辑模式时显示)
            if (!_isHistoryOpen && !isEditingPositions)
              Positioned(
                top: 14,
                right: 14,
                child: HistoryToggleButton(
                  onTap: () => setState(() => _isHistoryOpen = true),
                ),
              ),

            // 5. 顶部浮动：新图片生成提示气泡 (当用户未在查看最新图片且非编辑模式时显示)
            if (viewModel.hasUnseenLatest && gallery.isNotEmpty && !isEditingPositions)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: UnseenLatestBanner(
                    onViewLatest: _viewLatest,
                    onDismiss: viewModel.dismissUnseenBanner,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
