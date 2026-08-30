import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_history_sidebar.dart';
import 'canvas_overlays.dart';
import 'image_stream_view.dart';

/// 中间画板卡片：垂直图像流 + 可收起历史侧边栏 + 浮动徽章/横幅
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
    final selectedImage =
        viewModel.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);

    return Card(
      margin: EdgeInsets.zero,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Container(
        color: AppTheme.paperWarmth, // Notion 统一暖纸本底色
        child: Stack(
          children: [
            // 1. 中间核心：上下滑动的垂直图像瀑布流 (单图居中 / 多图平滑瀑布流)
            Positioned.fill(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1.1 主画布垂直无限滑动图像流
                  Expanded(
                    child: gallery.isEmpty && !isGenerating
                        ? const CanvasEmptyState()
                        : ImageStreamView(
                            viewModel: viewModel,
                            controller: _stream,
                          ),
                  ),

                  // 1.2 右侧垂直 History 缩略图侧边栏 (Notion 蓝白纯净卡片)
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: _isHistoryOpen ? 120 : 0,
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

            // 2. 左下角浮动参数徽章 (Notion 蓝白卡片，大号易读)
            if (selectedImage != null)
              Positioned(
                bottom: 18,
                left: 18,
                child: CanvasParamBadges(image: selectedImage),
              ),

            // 3. 右上角浮动 History 展开按键 (仅在收回状态时显示，点击展开)
            if (!_isHistoryOpen)
              Positioned(
                top: 14,
                right: 14,
                child: HistoryToggleButton(
                  onTap: () => setState(() => _isHistoryOpen = true),
                ),
              ),

            // 4. 顶部浮动：新图片生成提示气泡 (当用户未在查看最新图片时显示)
            if (viewModel.hasUnseenLatest && gallery.isNotEmpty)
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
