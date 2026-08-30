import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/context_menu.dart';
import '../../../../data/models/novelai_models.dart';
import '../view_models/studio_view_model.dart';

class ImageCanvasCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const ImageCanvasCard({super.key, required this.viewModel});

  @override
  State<ImageCanvasCard> createState() => _ImageCanvasCardState();
}

class _ImageCanvasCardState extends State<ImageCanvasCard> {
  bool _isHistoryOpen = false;
  final ScrollController _verticalStreamScrollController = ScrollController();
  final Map<String, GlobalKey> _itemKeyMap = {};
  bool _isAdjustingScrollAnchor = false;
  int _lastGalleryLength = 0;
  String? _lastFirstImageId;

  @override
  void dispose() {
    _verticalStreamScrollController.dispose();
    super.dispose();
  }

  GlobalKey _getItemKey(String id) {
    return _itemKeyMap.putIfAbsent(id, () => GlobalKey());
  }

  /// 复制图像位图到系统剪贴板 (可直接粘贴到聊天窗、画图等应用)
  Future<void> _copyImageToClipboard(NaiGeneratedImage image) async {
    var success = false;
    try {
      await Pasteboard.writeImage(image.uint8Bytes);
      success = true;
    } catch (_) {
      success = false;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? '已复制图像到剪贴板' : '复制图像失败'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  /// 图片右键菜单：包含超分放大 (2x / 4x)、复制图像、复制提示词、复用参数与查看大图
  void _showImageContextMenu(
    BuildContext context,
    Offset position,
    NaiGeneratedImage image,
  ) {
    if (widget.viewModel.selectedImage?.id != image.id) {
      widget.viewModel.selectImage(image);
    }

    final isGenerating = widget.viewModel.isGenerating;

    showStudioContextMenu(
      context,
      position: position,
      actions: [
        ContextMenuItem(
          icon: Icons.zoom_in_rounded,
          label: '2x 放大',
          onTap: isGenerating
              ? null
              : () => widget.viewModel.upscaleSelected(scale: 2),
        ),
        ContextMenuItem(
          icon: Icons.zoom_out_map_rounded,
          label: '4x 放大',
          onTap: isGenerating
              ? null
              : () => widget.viewModel.upscaleSelected(scale: 4),
        ),
        const ContextMenuDivider(),
        ContextMenuItem(
          icon: Icons.content_copy_rounded,
          label: '复制图像',
          onTap: () => _copyImageToClipboard(image),
        ),
        ContextMenuItem(
          icon: Icons.copy_rounded,
          label: '复制提示词',
          onTap: () {
            Clipboard.setData(
              ClipboardData(text: image.params.finalPrompt),
            );
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已复制提示词到剪贴板'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        ContextMenuItem(
          icon: Icons.sync_rounded,
          label: '复用参数',
          onTap: () {
            widget.viewModel.updateParams(image.params);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已应用该图参数至左侧面板'),
                duration: Duration(seconds: 1),
              ),
            );
          },
        ),
        const ContextMenuDivider(),
        ContextMenuItem(
          icon: Icons.fullscreen_rounded,
          label: '查看大图',
          onTap: () => _openImageDetailLightbox(context, image),
        ),
      ],
    );
  }

  void _scrollToTop() {
    if (_verticalStreamScrollController.hasClients) {
      final firstId = widget.viewModel.gallery.firstOrNull?.id;
      if (firstId != null) {
        _scrollToItem(0, firstId);
      } else {
        _verticalStreamScrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _scrollToItem(int index, String imageId) {
    final key = _itemKeyMap[imageId];
    final itemContext = key?.currentContext;
    if (itemContext != null) {
      Scrollable.ensureVisible(
        itemContext,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    } else if (_verticalStreamScrollController.hasClients) {
      final targetOffset = (index * 750.0).clamp(
        0.0,
        _verticalStreamScrollController.position.maxScrollExtent,
      );
      _verticalStreamScrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _updateActiveVisibleImage(
    StudioViewModel viewModel,
    List<NaiGeneratedImage> gallery,
  ) {
    if (_isAdjustingScrollAnchor || gallery.isEmpty) return;

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
      final key = _itemKeyMap[item.id];
      final itemContext = key?.currentContext;
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

    // 增加滞后死区 (Hysteresis): 新图片必须比当前选中的图片更靠近中心至少 50px，避免分界点抖动
    if (closestImage != null && closestImage.id != currentSelected?.id) {
      if (currentDistance - minDistance > 50.0 ||
          currentDistance == double.infinity) {
        viewModel.selectImage(closestImage);
      }
    }
  }

  void _openImageDetailLightbox(BuildContext context, NaiGeneratedImage image) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (ctx) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(16),
          child: Stack(
            children: [
              // 1. 全屏自由平移缩放画板
              Positioned.fill(
                child: InteractiveViewer(
                  minScale: 0.2,
                  maxScale: 10.0,
                  child: Center(
                    child: Image.memory(
                      image.uint8Bytes,
                      fit: BoxFit.contain,
                      gaplessPlayback: true,
                    ),
                  ),
                ),
              ),

              // 2. 顶部工具提示栏与关闭按键
              Positioned(
                top: 8,
                left: 8,
                right: 8,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: Text(
                        '${image.params.width} × ${image.params.height} · 种子: ${image.seed} · 可使用滚轮自由缩放与拖拽平移',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        color: Colors.white,
                        size: 28,
                      ),
                      tooltip: '关闭大图展示',
                      onPressed: () => Navigator.of(ctx).pop(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final gallery = viewModel.gallery;
    final selectedImage =
        viewModel.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);

    // 检测是否有新生成的图片插入到顶部 (即 gallery 在头部增加了元素)
    final firstImageId = gallery.firstOrNull?.id;
    final isNewItemPrepend =
        _lastFirstImageId != null &&
        firstImageId != _lastFirstImageId &&
        gallery.length > _lastGalleryLength;

    if (isNewItemPrepend &&
        !viewModel.isViewingLatest &&
        selectedImage != null) {
      // 获取当前正在查看的历史图片在屏幕上的真实 Y 坐标
      final currentKey = _itemKeyMap[selectedImage.id];
      final currentBox =
          currentKey?.currentContext?.findRenderObject() as RenderBox?;
      final oldY = currentBox != null && currentBox.hasSize
          ? currentBox.localToGlobal(Offset.zero).dy
          : null;

      _isAdjustingScrollAnchor = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (oldY != null) {
          final updatedBox =
              currentKey?.currentContext?.findRenderObject() as RenderBox?;
          if (updatedBox != null &&
              updatedBox.hasSize &&
              _verticalStreamScrollController.hasClients) {
            final newY = updatedBox.localToGlobal(Offset.zero).dy;
            final delta = newY - oldY;
            if (delta.abs() > 0.5) {
              _verticalStreamScrollController.jumpTo(
                (_verticalStreamScrollController.offset + delta).clamp(
                  0.0,
                  _verticalStreamScrollController.position.maxScrollExtent,
                ),
              );
            }
          }
        } else if (_verticalStreamScrollController.hasClients) {
          final index = gallery.indexWhere((img) => img.id == selectedImage.id);
          if (index >= 0) {
            _scrollToItem(index, selectedImage.id);
          }
        }
        _isAdjustingScrollAnchor = false;
      });
    } else if (isNewItemPrepend && viewModel.isViewingLatest) {
      // 如果用户正在查看最新图，新图生成后自动平滑滚动并居中最新生成的图片
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (firstImageId != null) {
          _scrollToItem(0, firstImageId);
        }
      });
    }

    _lastGalleryLength = gallery.length;
    _lastFirstImageId = firstImageId;

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
                  // 1.1 主画布垂直无限滑动图像流 (单图自适应垂直水平双向居中，多图瀑布流)
                  Expanded(
                    child: gallery.isEmpty
                        ? _buildEmptyState()
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final maxCardHeight = (constraints.maxHeight - 64)
                                  .clamp(240.0, 1600.0);
                              final maxCardWidth = (constraints.maxWidth - 48)
                                  .clamp(240.0, 1200.0);

                              // 计算顶部与底部充足的边距，确保第一张和最后一张图均可自由滑动至屏幕正中央
                              final topPadding = (constraints.maxHeight / 2 - 80).clamp(48.0, 500.0);
                              final bottomPadding = (constraints.maxHeight / 2 - 80).clamp(48.0, 500.0);

                              // 单张图片时：垂直水平双向居中展示
                              if (gallery.length == 1) {
                                final singleItem = gallery.first;
                                return SingleChildScrollView(
                                  physics: const AlwaysScrollableScrollPhysics(),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 20,
                                    vertical: 24,
                                  ),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight: (constraints.maxHeight - 48).clamp(0.0, double.infinity),
                                    ),
                                    child: Center(
                                      child: _buildImageCard(
                                        context: context,
                                        item: singleItem,
                                        isSelected: true,
                                        maxCardWidth: maxCardWidth,
                                        maxCardHeight: maxCardHeight,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              // 多张图片时：垂直无限滚动瀑布流
                              return NotificationListener<ScrollNotification>(
                                onNotification: (notification) {
                                  if (!_isAdjustingScrollAnchor &&
                                      (notification
                                              is ScrollUpdateNotification ||
                                          notification
                                              is ScrollEndNotification)) {
                                    _updateActiveVisibleImage(
                                      viewModel,
                                      gallery,
                                    );
                                  }
                                  return false;
                                },
                                child: ListView.separated(
                                  controller: _verticalStreamScrollController,
                                  physics:
                                      const AlwaysScrollableScrollPhysics(),
                                  padding: EdgeInsets.only(
                                    left: 20,
                                    right: 20,
                                    top: topPadding,
                                    bottom: bottomPadding,
                                  ),
                                  itemCount: gallery.length,
                                  separatorBuilder: (_, _) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 20,
                                    ),
                                    child: Center(
                                      child: Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: AppTheme.stone.withValues(
                                            alpha: 0.25,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  itemBuilder: (context, index) {
                                    final item = gallery[index];
                                    final isSelected =
                                        selectedImage?.id == item.id;
                                    return _buildImageCard(
                                      context: context,
                                      item: item,
                                      isSelected: isSelected,
                                      maxCardWidth: maxCardWidth,
                                      maxCardHeight: maxCardHeight,
                                    );
                                  },
                                ),
                              );
                            },
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
                      child: _buildHistorySidebar(
                        viewModel,
                        selectedImage,
                        gallery,
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
                child: _buildBottomLeftParamBadges(context, selectedImage),
              ),

            // 3. 右上角浮动 History 展开按键 (仅在收回状态时显示，点击展开)
            if (!_isHistoryOpen)
              Positioned(
                top: 14,
                right: 14,
                child: Tooltip(
                  message: '展开历史记录',
                  child: InkWell(
                    onTap: () => setState(() => _isHistoryOpen = true),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: AppTheme.pureWhite,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.history_rounded,
                        size: 20,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                ),
              ),

            // 4. 顶部浮动：新图片生成提示气泡 (当用户未在查看最新图片时显示)
            if (viewModel.hasUnseenLatest && gallery.isNotEmpty)
              Positioned(
                top: 14,
                left: 0,
                right: 0,
                child: Center(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () {
                        viewModel.selectLatestImage();
                        _scrollToTop();
                      },
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.pureWhite,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: AppTheme.notionBlue.withValues(alpha: 0.5),
                            width: 1.2,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppTheme.notionBlue.withValues(
                                alpha: 0.12,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 20,
                              height: 20,
                              decoration: const BoxDecoration(
                                color: AppTheme.skyTint,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_upward_rounded,
                                size: 13,
                                color: AppTheme.notionBlue,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text(
                              '已生成新图片 · 点击查看最新',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            InkWell(
                              onTap: () => viewModel.dismissUnseenBanner(),
                              borderRadius: BorderRadius.circular(10),
                              child: const Padding(
                                padding: EdgeInsets.all(2.0),
                                child: Icon(
                                  Icons.close_rounded,
                                  size: 14,
                                  color: AppTheme.graphite,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),

            // 5. 正在生图/处理中的进度遮罩
            if (viewModel.isGenerating)
              Positioned.fill(
                child: Container(
                  color: Colors.black.withValues(alpha: 0.45),
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.pureWhite,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(
                              AppTheme.notionBlue,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            viewModel.statusMessage ?? '正在生成中...',
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppTheme.textPrimary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
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

  /// 单个画板图片卡片组件 (居中约束、悬停与右键菜单)
  Widget _buildImageCard({
    required BuildContext context,
    required NaiGeneratedImage item,
    required bool isSelected,
    required double maxCardWidth,
    required double maxCardHeight,
  }) {
    final aspectRatio = (item.params.width > 0 && item.params.height > 0)
        ? item.params.width / item.params.height
        : 1.0;

    return Center(
      child: GestureDetector(
        key: _getItemKey(item.id),
        onTap: () => widget.viewModel.selectImage(item),
        onDoubleTap: () => _openImageDetailLightbox(
          context,
          item,
        ),
        onSecondaryTapUp: (details) => _showImageContextMenu(
          context,
          details.globalPosition,
          item,
        ),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: maxCardWidth,
            maxHeight: maxCardHeight,
          ),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected
                  ? AppTheme.notionBlue
                  : AppTheme.border,
              width: 2.0,
            ),
            boxShadow: [
              BoxShadow(
                color: isSelected
                    ? AppTheme.notionBlue.withValues(
                        alpha: 0.12,
                      )
                    : Colors.black.withValues(
                        alpha: 0.05,
                      ),
                blurRadius: isSelected ? 20 : 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: aspectRatio,
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

  /// 官方左下角悬浮参数徽章 (Notion 蓝白纯净大卡片)
  Widget _buildBottomLeftParamBadges(
    BuildContext context,
    NaiGeneratedImage currentImage,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 尺寸徽章
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: Text(
            '${currentImage.params.width}  ×  ${currentImage.params.height}',
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 种子徽章 (点击可直接复制)
        Tooltip(
          message: '点击复制随机种子',
          child: InkWell(
            onTap: () {
              Clipboard.setData(ClipboardData(text: '${currentImage.seed}'));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('已复制种子到剪贴板'),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppTheme.pureWhite,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.eco_rounded,
                    size: 16,
                    color: AppTheme.notionBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${currentImage.seed}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// 官方风格右侧垂直缩略图 History 侧边栏
  Widget _buildHistorySidebar(
    StudioViewModel viewModel,
    NaiGeneratedImage? selectedImage,
    List<NaiGeneratedImage> gallery,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 顶部官方风格 History ▸ 点击收起标头
        InkWell(
          onTap: () => setState(() => _isHistoryOpen = false),
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
                if (gallery.isNotEmpty) ...[
                  Text(
                    '${gallery.length}',
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
        ),

        // 历史图片缩略图瀑布流
        Expanded(
          child: gallery.isEmpty
              ? Center(
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
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textMuted,
                        ),
                      ),
                    ],
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(8, 10, 8, 14),
                  itemCount: gallery.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, index) {
                    final item = gallery[index];
                    final isSelected = selectedImage?.id == item.id;
                    final aspectRatio =
                        (item.params.width > 0 && item.params.height > 0)
                        ? item.params.width / item.params.height
                        : 1.0;

                    return GestureDetector(
                      onTap: () {
                        viewModel.selectImage(item);
                        if (gallery.length > 1) {
                          _scrollToItem(index, item.id);
                        }
                      },
                      onSecondaryTapUp: (details) => _showImageContextMenu(
                        context,
                        details.globalPosition,
                        item,
                      ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        decoration: BoxDecoration(
                          color: AppTheme.paperWarmth,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected
                                ? AppTheme.notionBlue
                                : AppTheme.border,
                            width: 2.0,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: AppTheme.notionBlue.withValues(
                                      alpha: 0.2,
                                    ),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  ),
                                ]
                              : null,
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: AspectRatio(
                          aspectRatio: aspectRatio.clamp(0.5, 2.0),
                          child: Image.memory(
                            item.uint8Bytes,
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.palette_outlined,
            size: 54,
            color: AppTheme.stone.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          const Text(
            '画板暂无图像',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '可在左侧配置参数后生成图片，历史记录将以垂直图像流展示',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

