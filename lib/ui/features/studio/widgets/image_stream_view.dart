import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../../core/widgets/context_menu.dart';
import '../view_models/studio_view_model.dart';
import 'character_position_canvas_view.dart';
import 'image_canvas_actions.dart';
import 'image_lightbox.dart';

/// 瀑布流卡片之间的固定分隔高度 (上下各 20px padding + 8px 圆点)
const double kCanvasStreamSeparatorExtent = 48.0;

/// 依据图片纵横比与画板约束计算卡片在瀑布流中的精确高度 (含上下各 2px 边框)
double canvasStreamCardHeight(
  NaiGenerationParams params,
  double maxCardWidth,
  double maxCardHeight,
) {
  final aspect = imageAspectRatioOf(params);
  if (aspect <= 0) return 400.0;
  const borderThickness = 4.0; // _canvasCardDecoration 上下各 2px border
  final innerWidth = math.max(0.0, maxCardWidth - borderThickness);
  final naturalHeight = innerWidth / aspect + borderThickness;
  return naturalHeight.clamp(0.0, maxCardHeight);
}

/// 让某张卡片在视口中垂直居中所需的上下内边距
double canvasStreamCenteringPadding(
  double viewportHeight,
  NaiGenerationParams params,
  double maxCardWidth,
  double maxCardHeight,
) {
  final cardHeight = canvasStreamCardHeight(
    params,
    maxCardWidth,
    maxCardHeight,
  );
  return ((viewportHeight - cardHeight) / 2).clamp(
    24.0,
    (viewportHeight / 2).clamp(24.0, 500.0),
  );
}

/// 画板垂直图像流的滚动协调器：
/// 持有滚动控制器与每张图的锚点 Key，供图像流、历史侧边栏与浮动横幅共同驱动滚动定位。
class CanvasStreamController {
  final ScrollController scrollController = SmoothWheelScrollController();
  final Map<String, GlobalKey> _itemKeys = {};

  StudioViewModel? _viewModel;
  double _viewportHeight = 0;
  double _maxCardWidth = 0;
  double _maxCardHeight = 0;
  bool _compact = false;
  int _anchorEpoch = 0;

  /// 是否正在程序化调整滚动锚点 (期间暂停"居中图自动选中"检测)
  bool isAdjustingAnchor = false;

  GlobalKey keyFor(String id) => _itemKeys.putIfAbsent(id, GlobalKey.new);

  void pruneKeys(Set<String> validIds) {
    if (_itemKeys.isEmpty) return;
    _itemKeys.removeWhere((id, _) => !validIds.contains(id));
  }

  /// 同步当前视口与卡片布局约束，供跳转定位与卡片列表共享单一高度事实源
  void attachLayout({
    required StudioViewModel viewModel,
    required double viewportHeight,
    required double maxCardWidth,
    required double maxCardHeight,
    required bool compact,
  }) {
    _viewModel = viewModel;
    _viewportHeight = viewportHeight;
    _maxCardWidth = maxCardWidth;
    _maxCardHeight = maxCardHeight;
    _compact = compact;
  }

  /// 基于所有历史图真实宽高比计算目标卡片居中的精确滚动偏移
  double? computeCenterOffsetForImage(
    String imageId, {
    int? fallbackGalleryIndex,
  }) {
    final vm = _viewModel;
    if (vm == null || _viewportHeight <= 0 || _maxCardWidth <= 0) return null;
    final gallery = vm.gallery;
    if (gallery.isEmpty) return null;

    var galleryIndex = gallery.indexWhere((item) => item.id == imageId);
    if (galleryIndex < 0) {
      if (fallbackGalleryIndex != null &&
          fallbackGalleryIndex >= 0 &&
          fallbackGalleryIndex < gallery.length) {
        galleryIndex = fallbackGalleryIndex;
      } else {
        return null;
      }
    }

    final isGenerating = vm.isGenerating;
    final selectedImage =
        vm.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);
    final isEditingPositions =
        vm.isEditingCharacterPositions || vm.isEditingWatermarkPosition;
    final targetAspect = imageAspectRatioOf(vm.params);
    final selectedAspect = selectedImage != null
        ? imageAspectRatioOf(selectedImage.params)
        : 0.0;
    final isAspectMatching =
        selectedImage != null && (targetAspect - selectedAspect).abs() < 0.01;
    final showPositionPlaceholder = isEditingPositions && !isAspectMatching;

    final itemParams = <NaiGenerationParams>[
      if (isGenerating) vm.params,
      if (showPositionPlaceholder) vm.params,
      for (final item in gallery) item.params,
    ];
    final headerCount =
        (isGenerating ? 1 : 0) + (showPositionPlaceholder ? 1 : 0);
    final cardIndex = headerCount + galleryIndex;
    if (cardIndex < 0 || cardIndex >= itemParams.length) return null;
    if (itemParams.length <= 1) return 0.0;

    final topPadding = canvasStreamCenteringPadding(
      _viewportHeight,
      itemParams.first,
      _maxCardWidth,
      _maxCardHeight,
    );
    final calculatedBottomPadding = canvasStreamCenteringPadding(
      _viewportHeight,
      itemParams.last,
      _maxCardWidth,
      _maxCardHeight,
    );
    final bottomPadding = _compact
        ? math.max(76.0, calculatedBottomPadding)
        : calculatedBottomPadding;

    var offset = topPadding;
    double? targetCardCenter;
    for (var i = 0; i < itemParams.length; i++) {
      final cardHeight = canvasStreamCardHeight(
        itemParams[i],
        _maxCardWidth,
        _maxCardHeight,
      );
      if (i == cardIndex) {
        targetCardCenter = offset + cardHeight / 2.0;
      }
      offset += cardHeight;
      if (i < itemParams.length - 1) {
        offset += kCanvasStreamSeparatorExtent;
      }
    }
    if (targetCardCenter == null) return null;

    final totalContentHeight = offset + bottomPadding;
    final maxExtent = math.max(0.0, totalContentHeight - _viewportHeight);
    return (targetCardCenter - _viewportHeight / 2.0).clamp(0.0, maxExtent);
  }

  void scrollToTop() {
    if (!scrollController.hasClients) return;
    _animateAnchor(
      scrollController.animateTo(
        0.0,
        duration: AppMotionDurations.medium,
        curve: AppMotionCurves.smoothOut,
      ),
    );
  }

  void scrollToItem(int index, String imageId) {
    if (!scrollController.hasClients) return;
    final targetOffset = computeCenterOffsetForImage(
      imageId,
      fallbackGalleryIndex: index,
    );
    if (targetOffset != null) {
      final epoch = ++_anchorEpoch;
      isAdjustingAnchor = true;
      final pos = scrollController.position;
      final clampedTarget = targetOffset.clamp(
        pos.minScrollExtent,
        pos.maxScrollExtent,
      );
      scrollController
          .animateTo(
            clampedTarget,
            duration: AppMotionDurations.medium,
            curve: AppMotionCurves.smoothOut,
          )
          .whenComplete(() {
            if (_anchorEpoch != epoch) return;
            final ctx = _itemKeys[imageId]?.currentContext;
            if (ctx != null && ctx.mounted && scrollController.hasClients) {
              final renderBox = ctx.findRenderObject() as RenderBox?;
              final scrollRender =
                  scrollController.position.context.notificationContext
                          ?.findRenderObject()
                      as RenderBox?;
              if (renderBox != null &&
                  renderBox.hasSize &&
                  scrollRender != null &&
                  scrollRender.hasSize) {
                final itemCenter = renderBox
                    .localToGlobal(Offset(0, renderBox.size.height / 2))
                    .dy;
                final viewportCenter = scrollRender
                    .localToGlobal(Offset(0, scrollRender.size.height / 2))
                    .dy;
                if ((itemCenter - viewportCenter).abs() > 1.0) {
                  _ensureItemVisible(
                    ctx,
                    duration: Duration.zero,
                    alignment: 0.5,
                  ).whenComplete(() {
                    if (_anchorEpoch == epoch) {
                      isAdjustingAnchor = false;
                    }
                  });
                  return;
                }
              }
            }
            isAdjustingAnchor = false;
          });
      return;
    }

    final itemContext = _itemKeys[imageId]?.currentContext;
    if (itemContext != null) {
      _animateAnchor(
        _ensureItemVisible(
          itemContext,
          duration: AppMotionDurations.medium,
          curve: AppMotionCurves.smoothOut,
          alignment: 0.5,
        ),
      );
      return;
    }
    // 布局未附着时的兜底：先按估算高度滚到附近，等卡片挂载后再二次居中
    final fallbackOffset = (index * 750.0).clamp(
      0.0,
      scrollController.position.maxScrollExtent,
    );
    final epoch = ++_anchorEpoch;
    isAdjustingAnchor = true;
    scrollController
        .animateTo(
          fallbackOffset,
          duration: AppMotionDurations.medium,
          curve: AppMotionCurves.smoothOut,
        )
        .whenComplete(() {
          if (_anchorEpoch != epoch) return;
          final ctx = _itemKeys[imageId]?.currentContext;
          if (ctx == null || !ctx.mounted) {
            isAdjustingAnchor = false;
            return;
          }
          _ensureItemVisible(
            ctx,
            duration: AppMotionDurations.fast,
            curve: AppMotionCurves.smoothOut,
            alignment: 0.5,
          ).whenComplete(() {
            if (_anchorEpoch == epoch) {
              isAdjustingAnchor = false;
            }
          });
        });
  }

  /// 无动画锚定到指定图 (保持用户正在浏览的历史图视野不动)
  void anchorToItemSilently(String imageId) {
    if (!scrollController.hasClients) return;
    final targetOffset = computeCenterOffsetForImage(imageId);
    if (targetOffset != null) {
      isAdjustingAnchor = true;
      final pos = scrollController.position;
      scrollController.jumpTo(
        targetOffset.clamp(pos.minScrollExtent, pos.maxScrollExtent),
      );
      isAdjustingAnchor = false;
      return;
    }
    final itemContext = _itemKeys[imageId]?.currentContext;
    if (itemContext == null) return;
    isAdjustingAnchor = true;
    _ensureItemVisible(itemContext, duration: Duration.zero, alignment: 0.5);
    isAdjustingAnchor = false;
  }

  /// 只滚动画板自己的纵向视口，不能用 Scrollable.ensureVisible：
  /// 后者会继续滚动祖先 PageView，使窄屏参数页短暂滑入画板。
  Future<void> _ensureItemVisible(
    BuildContext itemContext, {
    Duration duration = Duration.zero,
    Curve curve = Curves.ease,
    double alignment = 0.5,
  }) async {
    if (!scrollController.hasClients || !itemContext.mounted) return;
    final target = itemContext.findRenderObject();
    if (target == null || !target.attached) return;
    await scrollController.position.ensureVisible(
      target,
      duration: duration,
      curve: curve,
      alignment: alignment,
    );
  }

  void _animateAnchor(Future<void> future) {
    final epoch = ++_anchorEpoch;
    isAdjustingAnchor = true;
    future.whenComplete(() {
      if (_anchorEpoch == epoch) {
        isAdjustingAnchor = false;
      }
    });
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
  final bool compact;

  const ImageStreamView({
    super.key,
    required this.viewModel,
    required this.controller,
    this.compact = false,
  });

  @override
  State<ImageStreamView> createState() => _ImageStreamViewState();
}

class _ImageStreamViewState extends State<ImageStreamView> {
  int _lastGalleryLength = 0;
  String? _lastFirstImageId;
  bool _lastIsGenerating = false;
  bool _selectionScheduled = false;

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final controller = widget.controller;
    final gallery = viewModel.gallery;
    final isGenerating = viewModel.isGenerating;
    final selectedImage =
        viewModel.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);

    _handleAutoScrollAnchoring(viewModel, gallery, selectedImage);

    final isEditingPositions =
        viewModel.isEditingCharacterPositions ||
        viewModel.isEditingWatermarkPosition;
    final targetAspect = viewModel.params.width / viewModel.params.height;
    final selectedAspect = selectedImage != null
        ? (selectedImage.params.width / selectedImage.params.height)
        : 0.0;
    final isAspectMatching =
        selectedImage != null && (targetAspect - selectedAspect).abs() < 0.01;

    // 当且仅当正在编辑角色/水印位置，且当前选中的图与目标比例不匹配(或画板无图)时展示临时占位符
    final showPositionPlaceholder = isEditingPositions && !isAspectMatching;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = (constraints.maxHeight - 64).clamp(240.0, 1600.0);
        final rawMaxCardWidth = (constraints.maxWidth - 48).clamp(240.0, 1200.0);
        final listInnerWidth = math.max(0.0, constraints.maxWidth - 40);
        final maxCardWidth = math.min(rawMaxCardWidth, listInnerWidth);

        controller.attachLayout(
          viewModel: viewModel,
          viewportHeight: constraints.maxHeight,
          maxCardWidth: maxCardWidth,
          maxCardHeight: maxCardHeight,
          compact: widget.compact,
        );

        final firstCardParams = (isGenerating || showPositionPlaceholder)
            ? viewModel.params
            : (gallery.isNotEmpty ? gallery.first.params : viewModel.params);
        final lastCardParams = gallery.isNotEmpty
            ? gallery.last.params
            : viewModel.params;

        // 精准动态上下内边距：使顶部第一张图与底部最后一张图在视口中能够 100% 垂直居中展示
        final topPadding = canvasStreamCenteringPadding(
          constraints.maxHeight,
          firstCardParams,
          maxCardWidth,
          maxCardHeight,
        );
        final calculatedBottomPadding = canvasStreamCenteringPadding(
          constraints.maxHeight,
          lastCardParams,
          maxCardWidth,
          maxCardHeight,
        );
        final bottomPadding = widget.compact
            ? math.max(76.0, calculatedBottomPadding)
            : calculatedBottomPadding;

        // 占位符与历史图总数 (生成中或比例不匹配的位置编辑模式下头部多一个占位符)
        final totalItemCount =
            (isGenerating ? 1 : 0) +
            (showPositionPlaceholder ? 1 : 0) +
            gallery.length;

        // 单元素 (首张生成占位符 / 临时位置占位卡片 / 仅一张历史图)：整体居中展示
        if (totalItemCount == 1) {
          final Widget card;
          if (isGenerating) {
            card = CanvasGeneratingCard(
              viewModel: viewModel,
              maxCardWidth: maxCardWidth,
              maxCardHeight: maxCardHeight,
            );
          } else if (showPositionPlaceholder) {
            card = CanvasPositionPlaceholderCard(
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
              compact: widget.compact,
            );
          }
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.fromLTRB(
              20,
              24,
              20,
              widget.compact ? 84 : 24,
            ),
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

        final headerCount =
            (isGenerating ? 1 : 0) + (showPositionPlaceholder ? 1 : 0);
        final totalSliverCount = totalItemCount * 2 - 1;

        NaiGenerationParams cardParamsAt(int cardIndex) {
          if (cardIndex < headerCount) return viewModel.params;
          return gallery[cardIndex - headerCount].params;
        }

        // 多张图片 (或已有图片并在生成新图/展示临时位置卡片)：
        // 使用带精确 itemExtentBuilder 的变高列表，消除混排不同分辨率图片时
        // 懒加载高度估算失真造成的跳转偏移误差。
        return NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            // 滚动帧只移动画布；停止后才同步选中图与全局面板。
            // 不逐帧扫描整个历史列表，也不让 notifyListeners 打断滑行。
            if (notification.depth == 0 &&
                !controller.isAdjustingAnchor &&
                notification is ScrollEndNotification) {
              _scheduleActiveImageSelection();
            }
            return false;
          },
          child: ListView.builder(
            controller: controller.scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
            addAutomaticKeepAlives: false,
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: topPadding,
              bottom: bottomPadding,
            ),
            itemCount: totalSliverCount,
            itemExtentBuilder: (sliverIndex, _) {
              if (sliverIndex < 0 || sliverIndex >= totalSliverCount) {
                return null;
              }
              if (sliverIndex.isOdd) return kCanvasStreamSeparatorExtent;
              final cardIndex = sliverIndex ~/ 2;
              return canvasStreamCardHeight(
                cardParamsAt(cardIndex),
                maxCardWidth,
                maxCardHeight,
              );
            },
            itemBuilder: (context, sliverIndex) {
              if (sliverIndex.isOdd) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: context.colors.textMuted.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                );
              }
              var adjustedIndex = sliverIndex ~/ 2;
              if (isGenerating) {
                if (adjustedIndex == 0) {
                  return CanvasGeneratingCard(
                    viewModel: viewModel,
                    maxCardWidth: maxCardWidth,
                    maxCardHeight: maxCardHeight,
                  );
                }
                adjustedIndex -= 1;
              }
              if (showPositionPlaceholder) {
                if (adjustedIndex == 0) {
                  return CanvasPositionPlaceholderCard(
                    viewModel: viewModel,
                    maxCardWidth: maxCardWidth,
                    maxCardHeight: maxCardHeight,
                  );
                }
                adjustedIndex -= 1;
              }
              final item = gallery[adjustedIndex];
              final isSelected =
                  !isGenerating &&
                  !showPositionPlaceholder &&
                  selectedImage?.id == item.id;
              return CanvasImageCard(
                viewModel: viewModel,
                controller: controller,
                item: item,
                isSelected: isSelected,
                maxCardWidth: maxCardWidth,
                maxCardHeight: maxCardHeight,
                compact: widget.compact,
              );
            },
          ),
        );
      },
    );
  }

  void _scheduleActiveImageSelection() {
    if (_selectionScheduled) return;
    _selectionScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _selectionScheduled = false;
      if (!mounted) return;
      final controller = widget.controller;
      final scroll = controller.scrollController;
      // 连续滚轮重启滑行时也会发出短暂的 ScrollEnd，下一帧确认真正停下。
      if (!scroll.hasClients ||
          scroll.position.isScrollingNotifier.value ||
          controller.isAdjustingAnchor) {
        return;
      }
      _updateActiveVisibleImage(widget.viewModel, widget.viewModel.gallery);
    });
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

    if (gallery.length != _lastGalleryLength ||
        firstImageId != _lastFirstImageId) {
      controller.pruneKeys(gallery.map((item) => item.id).toSet());
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
    final isSelected = viewModel.isViewingLatest;
    final aspectRatio = imageAspectRatioOf(params);
    // 按实际显示尺寸解码 (预览帧每步全量重解码，全分辨率纹理会拖慢 UI 线程)
    final displayWidth = maxCardWidth < maxCardHeight * aspectRatio
        ? maxCardWidth
        : maxCardHeight * aspectRatio;
    final previewCacheWidth = (((displayWidth * 1.5) / 128.0).ceil() * 128)
        .clamp(128, 4096);

    return Center(
      child: GestureDetector(
        onTap: () => viewModel.selectLatestImage(),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: maxCardWidth,
            maxHeight: maxCardHeight,
          ),
          decoration: _canvasCardDecoration(context, isSelected),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(
            aspectRatio: aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 去噪中间帧仅在本占位卡内部局部重绘，
                // 生图期间主工作台零重建
                ListenableBuilder(
                  listenable: viewModel.liveProgressController,
                  builder: (context, _) {
                    final previewBytes = viewModel.livePreviewBytes;
                    if (previewBytes != null) {
                      return Image.memory(
                        previewBytes,
                        fit: BoxFit.contain,
                        gaplessPlayback: true,
                        cacheWidth: previewCacheWidth,
                      );
                    }
                    return Stack(
                      fit: StackFit.expand,
                      children: [
                        const AppSkeletonBox(
                          width: double.infinity,
                          height: double.infinity,
                          radius: 0,
                        ),
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AppMatrixDotLoader(
                                dotSize: 4.0,
                                gap: 3.0,
                                variant: AppMatrixDotVariant.orbit,
                                activeColor: context.colors.primary,
                              ),
                              if (viewModel.liveTotalSteps > 0 &&
                                  viewModel.liveCurrentStep > 0) ...[
                                const SizedBox(height: 10),
                                Text(
                                  '${viewModel.liveCurrentStep} / ${viewModel.liveTotalSteps}',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: context.colors.textSecondary,
                                    fontFamily: 'monospace',
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    );
                  },
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
  final bool compact;

  const CanvasImageCard({
    super.key,
    required this.viewModel,
    required this.controller,
    required this.item,
    required this.isSelected,
    required this.maxCardWidth,
    required this.maxCardHeight,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final isEditingPositions =
        viewModel.isEditingCharacterPositions ||
        viewModel.isEditingWatermarkPosition;
    final targetAspect = viewModel.params.width / viewModel.params.height;
    final itemAspect = imageAspectRatioOf(item.params);
    final isAspectMatching = (targetAspect - itemAspect).abs() < 0.01;
    final isPositionOverlayActive =
        isEditingPositions && isSelected && isAspectMatching;

    // 按实际显示尺寸解码：全分辨率纹理 (1216px 级) 在多图滚动时
    // 造成大量纹理内存与光栅化压力
    final displayWidth = maxCardWidth < maxCardHeight * itemAspect
        ? maxCardWidth
        : maxCardHeight * itemAspect;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (((displayWidth * dpr) / 128.0).ceil() * 128).clamp(
      128,
      4096,
    );

    return Center(
      child: StudioContextMenuRegion(
        key: controller.keyFor(item.id),
        onShow: isPositionOverlayActive
            ? null
            : (position) {
                if (compact) {
                  showMobileImageActionSheet(
                    context,
                    viewModel: viewModel,
                    image: item,
                  );
                } else {
                  showImageContextMenu(
                    context,
                    position: position,
                    viewModel: viewModel,
                    image: item,
                  );
                }
              },
        child: GestureDetector(
          onTap: () => viewModel.selectImage(item),
          onDoubleTap: isPositionOverlayActive
              ? null
              : () => showImageLightbox(
                  context,
                  item,
                  loader: () => viewModel.ensureImageLoaded(item),
                ),
          child: Container(
            constraints: BoxConstraints(
              maxWidth: maxCardWidth,
              maxHeight: maxCardHeight,
            ),
            decoration: _canvasCardDecoration(context, isSelected),
            clipBehavior: Clip.antiAlias,
            child: AspectRatio(
              aspectRatio: imageAspectRatioOf(item.params),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ValueListenableBuilder<Map<String, Uint8List>>(
                    valueListenable: viewModel.imageBytesNotifier,
                    builder: (context, bytesMap, _) {
                      final fullBytes = item.bytes.isNotEmpty
                          ? item.bytes
                          : bytesMap[item.id];
                      final thumb = item.thumbnailBytes;
                      final displayBytes =
                          (fullBytes != null && fullBytes.isNotEmpty)
                          ? fullBytes
                          : ((thumb != null && thumb.isNotEmpty) ? thumb : null);

                      if (isSelected &&
                          (fullBytes == null || fullBytes.isEmpty)) {
                        viewModel.ensureImageLoaded(item);
                      }

                      final hasImage = displayBytes != null;
                      return AppSkeletonReveal(
                        isLoaded: hasImage,
                        enableBlur: false,
                        skeleton: SizedBox.expand(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              const AppSkeletonBox(
                                width: double.infinity,
                                height: double.infinity,
                                radius: 0,
                              ),
                              Center(
                                child: AppMatrixDotLoader(
                                  dotSize: 3.5,
                                  gap: 2.5,
                                  variant: AppMatrixDotVariant.pulse,
                                  activeColor: context.colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                        child: hasImage
                            ? SizedBox.expand(
                                child: Image.memory(
                                  displayBytes,
                                  fit: BoxFit.contain,
                                  gaplessPlayback: true,
                                  cacheWidth: cacheWidth,
                                ),
                              )
                            : const SizedBox.expand(),
                      );
                    },
                  ),
                  if (isPositionOverlayActive)
                    if (viewModel.isEditingWatermarkPosition)
                      WatermarkPositionOverlay(viewModel: viewModel)
                    else
                      CharacterPositionOverlay(viewModel: viewModel),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 画板流卡片的统一白底选中态装饰
BoxDecoration _canvasCardDecoration(BuildContext context, bool isSelected) {
  final colors = context.colors;
  return BoxDecoration(
    color: colors.cardBackground,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(
      color: isSelected ? colors.primary : colors.borderDefault,
      width: 2.0,
    ),
    boxShadow: [
      BoxShadow(
        color: isSelected
            ? colors.primary.withValues(alpha: 0.12)
            : (context.isDarkMode
                  ? Colors.black.withValues(alpha: 0.3)
                  : Colors.black.withValues(alpha: 0.05)),
        blurRadius: isSelected ? 20 : 12,
        offset: const Offset(0, 4),
      ),
    ],
  );
}
