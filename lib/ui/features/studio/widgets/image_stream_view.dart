import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'image_canvas_actions.dart';
import 'image_lightbox.dart';

/// 画板垂直图像流的滚动协调器：
/// 持有滚动控制器与每张图的锚点 Key，供图像流、历史侧边栏与浮动横幅共同驱动滚动定位。
class CanvasStreamController {
  final ScrollController scrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeys = {};

  /// 是否正在程序化调整滚动锚点 (期间暂停"居中图自动选中"检测)
  bool isAdjustingAnchor = false;

  GlobalKey keyFor(String id) => _itemKeys.putIfAbsent(id, GlobalKey.new);

  void scrollToTop() {
    if (!scrollController.hasClients) return;
    _animateAnchor(
      scrollController.animateTo(
        0.0,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      ),
    );
  }

  void scrollToItem(int index, String imageId) {
    final itemContext = _itemKeys[imageId]?.currentContext;
    if (itemContext != null) {
      _animateAnchor(
        Scrollable.ensureVisible(
          itemContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          alignment: 0.5,
        ),
      );
    } else if (scrollController.hasClients) {
      final targetOffset = (index * 750.0).clamp(
        0.0,
        scrollController.position.maxScrollExtent,
      );
      _animateAnchor(
        scrollController.animateTo(
          targetOffset,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  /// 无动画锚定到指定图 (保持用户正在浏览的历史图视野不动)
  void anchorToItemSilently(String imageId) {
    final itemContext = _itemKeys[imageId]?.currentContext;
    if (itemContext == null) return;
    isAdjustingAnchor = true;
    Scrollable.ensureVisible(
      itemContext,
      duration: Duration.zero,
      alignment: 0.5,
    );
    isAdjustingAnchor = false;
  }

  void _animateAnchor(Future<void> future) {
    isAdjustingAnchor = true;
    future.then((_) => isAdjustingAnchor = false);
  }

  void dispose() {
    scrollController.dispose();
    _itemKeys.clear();
  }
}

/// 中间核心画板：上下滑动的垂直图像瀑布流
/// (空态/单图自适应居中 / 多图瀑布流 + 生成占位符 + 居中图自动选中)
class ImageStreamView extends StatefulWidget {
  final StudioViewModel viewModel;
  final CanvasStreamController controller;

  const ImageStreamView({
    super.key,
    required this.viewModel,
    required this.controller,
  });

  @override
  State<ImageStreamView> createState() => _ImageStreamViewState();
}

class _ImageStreamViewState extends State<ImageStreamView> {
  int _lastGalleryLength = 0;
  String? _lastFirstImageId;
  bool _lastIsGenerating = false;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final controller = widget.controller;
    final gallery = viewModel.gallery;
    final isGenerating = viewModel.isGenerating;
    final selectedImage =
        viewModel.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);

    _handleAutoScrollAnchoring(viewModel, gallery, selectedImage);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = (constraints.maxHeight - 64).clamp(240.0, 1600.0);
        final maxCardWidth = (constraints.maxWidth - 48).clamp(240.0, 1200.0);

        final firstCardParams = isGenerating
            ? viewModel.params
            : (gallery.isNotEmpty ? gallery.first.params : viewModel.params);
        final lastCardParams = gallery.isNotEmpty
            ? gallery.last.params
            : viewModel.params;

        // 精准动态上下内边距：使顶部第一张图与底部最后一张图在视口中能够 100% 垂直居中展示
        final topPadding = _centeringPaddingFor(
          constraints.maxHeight,
          firstCardParams,
          maxCardWidth,
          maxCardHeight,
        );
        final bottomPadding = _centeringPaddingFor(
          constraints.maxHeight,
          lastCardParams,
          maxCardWidth,
          maxCardHeight,
        );

        // 占位符与历史图总数 (生成中时头部多一个占位符)
        final totalItemCount = isGenerating
            ? gallery.length + 1
            : gallery.length;

        // 单元素 (首张生成占位符 / 仅一张历史图)：整体居中展示
        if (totalItemCount == 1) {
          final Widget card;
          if (isGenerating) {
            card = CanvasGeneratingCard(
              viewModel: viewModel,
              maxCardWidth: maxCardWidth,
              maxCardHeight: maxCardHeight,
            );
          } else {
            card = CanvasImageCard(
              viewModel: viewModel,
              controller: controller,
              item: gallery.first,
              isSelected: true,
              maxCardWidth: maxCardWidth,
              maxCardHeight: maxCardHeight,
            );
          }
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: (constraints.maxHeight - 48).clamp(
                  0.0,
                  double.infinity,
                ),
              ),
              child: Center(child: card),
            ),
          );
        }

        // 多张图片 (或已有图片并在生成新图)：垂直无限滚动瀑布流
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (!controller.isAdjustingAnchor &&
                (notification is ScrollUpdateNotification ||
                    notification is ScrollEndNotification)) {
              _updateActiveVisibleImage(viewModel, gallery);
            }
            return false;
          },
          child: ListView.separated(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: topPadding,
              bottom: bottomPadding,
            ),
            itemCount: totalItemCount,
            separatorBuilder: (_, _) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Center(
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.stone.withValues(alpha: 0.25),
                  ),
                ),
              ),
            ),
            itemBuilder: (context, index) {
              // 生成中时头部是占位符，其余为历史图
              if (isGenerating && index == 0) {
                return CanvasGeneratingCard(
                  viewModel: viewModel,
                  maxCardWidth: maxCardWidth,
                  maxCardHeight: maxCardHeight,
                );
              }
              final item = gallery[isGenerating ? index - 1 : index];
              final isSelected = isGenerating
                  ? !viewModel.isViewingLatest && selectedImage?.id == item.id
                  : selectedImage?.id == item.id;
              return CanvasImageCard(
                viewModel: viewModel,
                controller: controller,
                item: item,
                isSelected: isSelected,
                maxCardWidth: maxCardWidth,
                maxCardHeight: maxCardHeight,
              );
            },
          ),
        );
      },
    );
  }

  /// 依据图片纵横比估算其在瀑布流中的实际卡片高度 (用于视口居中内边距计算)
  double _estimatedCardHeight(
    NaiGenerationParams params,
    double maxCardWidth,
    double maxCardHeight,
  ) {
    final aspect = imageAspectRatioOf(params);
    if (aspect <= 0) return 400.0;
    final cardHeight = maxCardWidth / aspect;
    return cardHeight > maxCardHeight ? maxCardHeight : cardHeight;
  }

  /// 让某张卡片在视口中垂直居中所需的上下内边距
  double _centeringPaddingFor(
    double viewportHeight,
    NaiGenerationParams params,
    double maxCardWidth,
    double maxCardHeight,
  ) {
    final cardHeight = _estimatedCardHeight(
      params,
      maxCardWidth,
      maxCardHeight,
    );
    return ((viewportHeight - cardHeight) / 2).clamp(
      24.0,
      (viewportHeight / 2).clamp(24.0, 500.0),
    );
  }

  /// 新图插入/生成状态切换时自动调整滚动：
  /// - 查看最新态 -> 平滑滚回顶部看新图或占位符
  /// - 浏览历史态且刚开始生成 -> 静默锚定保持历史图视野不动
  void _handleAutoScrollAnchoring(
    StudioViewModel viewModel,
    List<NaiGeneratedImage> gallery,
    NaiGeneratedImage? selectedImage,
  ) {
    final controller = widget.controller;
    final firstImageId = gallery.firstOrNull?.id;
    final isNewItemPrepend =
        _lastFirstImageId != null &&
        firstImageId != _lastFirstImageId &&
        gallery.length > _lastGalleryLength;
    final isGeneratingChanged = _lastIsGenerating != viewModel.isGenerating;

    if (isGeneratingChanged || isNewItemPrepend) {
      if (viewModel.isViewingLatest) {
        // 如果用户处于最新图状态：新图生成/开始生成占位符时平滑滚动到顶部看最新图/占位符
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) controller.scrollToTop();
        });
      } else if (selectedImage != null &&
          isGeneratingChanged &&
          viewModel.isGenerating) {
        // 如果用户正在查看历史图且新图刚开始生成：静默无动画锚定保持历史图视野不动
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) controller.anchorToItemSilently(selectedImage.id);
        });
      }
    }

    _lastGalleryLength = gallery.length;
    _lastFirstImageId = firstImageId;
    _lastIsGenerating = viewModel.isGenerating;
  }

  /// 滚动停止时把"最接近视口中心"的图选为当前图
  /// (带 60px 滞后死区，避免分界点抖动)
  void _updateActiveVisibleImage(
    StudioViewModel viewModel,
    List<NaiGeneratedImage> gallery,
  ) {
    final controller = widget.controller;
    if (controller.isAdjustingAnchor || gallery.isEmpty) return;

    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    final viewportHeight = renderBox.size.height;
    final viewportCenterY =
        renderBox.localToGlobal(Offset.zero).dy + viewportHeight / 2;

    final currentSelected = viewModel.selectedImage;
    double currentDistance = double.infinity;
    NaiGeneratedImage? closestImage;
    double minDistance = double.infinity;

    for (final item in gallery) {
      final itemContext = controller.keyFor(item.id).currentContext;
      if (itemContext != null) {
        final itemBox = itemContext.findRenderObject() as RenderBox?;
        if (itemBox != null && itemBox.hasSize) {
          final itemCenterY =
              itemBox.localToGlobal(Offset.zero).dy + itemBox.size.height / 2;
          final distance = (itemCenterY - viewportCenterY).abs();
          if (item.id == currentSelected?.id) {
            currentDistance = distance;
          }
          if (distance < minDistance) {
            minDistance = distance;
            closestImage = item;
          }
        }
      }
    }

    // 滞后死区 (Hysteresis): 新图必须比当前选中图更靠近中心至少 60px 才切换
    if (closestImage != null && closestImage.id != currentSelected?.id) {
      if (currentDistance - minDistance > 60.0 ||
          currentDistance == double.infinity) {
        viewModel.selectImage(closestImage);
      }
    }
  }
}

/// 生图过程占位符卡片 (渲染去噪中间步与流式进度，点击回到最新)
class CanvasGeneratingCard extends StatelessWidget {
  final StudioViewModel viewModel;
  final double maxCardWidth;
  final double maxCardHeight;

  const CanvasGeneratingCard({
    super.key,
    required this.viewModel,
    required this.maxCardWidth,
    required this.maxCardHeight,
  });

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;
    final aspectRatio = imageAspectRatioOf(params);
    final previewBytes = viewModel.livePreviewBytes;
    final isSelected = viewModel.isViewingLatest;

    return Center(
      child: GestureDetector(
        onTap: () => viewModel.selectLatestImage(),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: maxCardWidth,
            maxHeight: maxCardHeight,
          ),
          decoration: _canvasCardDecoration(isSelected),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (previewBytes != null)
                  Image.memory(
                    previewBytes,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                  )
                else
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.notionBlue,
                            ),
                          ),
                        ),
                        if (viewModel.liveTotalSteps > 0 &&
                            viewModel.liveCurrentStep > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            '${viewModel.liveCurrentStep} / ${viewModel.liveTotalSteps}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                              fontFamily: 'monospace',
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ],
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

/// 画板流中的单张历史图卡片 (点击选中、双击看大图、右键菜单)
class CanvasImageCard extends StatelessWidget {
  final StudioViewModel viewModel;
  final CanvasStreamController controller;
  final NaiGeneratedImage item;
  final bool isSelected;
  final double maxCardWidth;
  final double maxCardHeight;

  const CanvasImageCard({
    super.key,
    required this.viewModel,
    required this.controller,
    required this.item,
    required this.isSelected,
    required this.maxCardWidth,
    required this.maxCardHeight,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        key: controller.keyFor(item.id),
        onTap: () => viewModel.selectImage(item),
        onDoubleTap: () => showImageLightbox(context, item),
        onSecondaryTapUp: (details) => showImageContextMenu(
          context,
          position: details.globalPosition,
          viewModel: viewModel,
          image: item,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: maxCardWidth,
            maxHeight: maxCardHeight,
          ),
          decoration: _canvasCardDecoration(isSelected),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: imageAspectRatioOf(item.params),
            child: Image.memory(
              item.uint8Bytes,
              fit: BoxFit.contain,
              gaplessPlayback: true,
            ),
          ),
        ),
      ),
    );
  }
}

/// 画板流卡片的统一白底选中态装饰
BoxDecoration _canvasCardDecoration(bool isSelected) => BoxDecoration(
  color: AppTheme.pureWhite,
  borderRadius: BorderRadius.circular(8),
  border: Border.all(
    color: isSelected ? AppTheme.notionBlue : AppTheme.border,
    width: 2.0,
  ),
  boxShadow: [
    BoxShadow(
      color: isSelected
          ? AppTheme.notionBlue.withValues(alpha: 0.12)
          : Colors.black.withValues(alpha: 0.05),
      blurRadius: isSelected ? 20 : 12,
      offset: const Offset(0, 4),
    ),
  ],
);
