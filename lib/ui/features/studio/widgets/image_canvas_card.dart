import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_drop_target_overlay.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_transitions.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_history_sidebar.dart';
import 'canvas_overlays.dart';
import 'character_position_canvas_view.dart';
import 'freeform_annotation_board.dart';
import 'image_canvas_actions.dart';
import 'image_stream_view.dart';
import 'inpaint_canvas_overlay.dart';
import 'metadata_reader_dialog.dart';

/// 中间画板卡片：垂直图像流 + 可收起历史侧边栏 + 浮动徽章/横幅 + 角色位置交互画板 + 外部图片拖拽与粘贴导入
class ImageCanvasCard extends StatefulWidget {
  final StudioViewModel viewModel;
  final bool compact;
  final VoidCallback? onSentToInpaint;

  const ImageCanvasCard({
    super.key,
    required this.viewModel,
    this.compact = false,
    this.onSentToInpaint,
  });

  @override
  State<ImageCanvasCard> createState() => _ImageCanvasCardState();
}

class _ImageCanvasCardState extends State<ImageCanvasCard>
    with TickerProviderStateMixin {
  static const double _historySidebarWidth = 128.0;
  static const double _buttonRevealThreshold = 0.65;

  bool _isHistoryOpen = false;
  bool _lastVmHistoryOpen = false;
  bool _isDraggingOver = false;
  bool _reduceMotion = false;
  bool _tickerEnabled = true;
  bool _targetShowSidebar = false;

  late final CanvasStreamController _stream = CanvasStreamController();
  late final AnimationController _historyController;
  late final AnimationController _buttonController;
  late final CurvedAnimation _historyCurve;
  late final CurvedAnimation _buttonCurve;

  @override
  void initState() {
    super.initState();
    _isHistoryOpen = widget.viewModel.canvasHistoryOpen;
    _lastVmHistoryOpen = _isHistoryOpen;
    final initial = _computeHistoryStates();
    _targetShowSidebar = initial.showSidebar;

    _historyController = AnimationController(
      vsync: this,
      duration: AppMotionDurations.fast,
      reverseDuration: AppMotionDurations.fast,
      value: initial.showSidebar ? 1.0 : 0.0,
    )..addListener(_onHistoryControllerChanged);

    _buttonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
      reverseDuration: const Duration(milliseconds: 90),
      value: initial.showButton ? 1.0 : 0.0,
    );

    _historyCurve = CurvedAnimation(
      parent: _historyController,
      curve: AppMotionCurves.smoothOut,
      reverseCurve: AppMotionCurves.smoothOut.flipped,
    );
    _buttonCurve = CurvedAnimation(
      parent: _buttonController,
      curve: AppMotionCurves.smoothOut,
      reverseCurve: AppMotionCurves.closeEase,
    );

    widget.viewModel.addListener(_onViewModelChanged);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
    if (_reduceMotion || !_tickerEnabled) {
      _syncAnimations(immediate: true);
    }
  }

  @override
  void didUpdateWidget(covariant ImageCanvasCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_onViewModelChanged);
      widget.viewModel.addListener(_onViewModelChanged);
    }
    if (_lastVmHistoryOpen != widget.viewModel.canvasHistoryOpen) {
      _lastVmHistoryOpen = widget.viewModel.canvasHistoryOpen;
      _isHistoryOpen = _lastVmHistoryOpen;
    }
    if (oldWidget.viewModel != widget.viewModel ||
        oldWidget.compact != widget.compact) {
      _syncAnimations();
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _historyController.removeListener(_onHistoryControllerChanged);
    _historyCurve.dispose();
    _buttonCurve.dispose();
    _historyController.dispose();
    _buttonController.dispose();
    _stream.dispose();
    super.dispose();
  }

  ({bool showSidebar, bool showButton}) _computeHistoryStates() {
    final viewModel = widget.viewModel;
    final isEditingPositions =
        viewModel.isEditingCharacterPositions ||
        viewModel.isEditingWatermarkPosition;
    final isAnnotating = viewModel.board.isAnnotatingImage;
    final isInpaintTab =
        !widget.compact &&
        viewModel.activeSidebarTab == StudioSidebarTab.inpaint &&
        !isEditingPositions;
    return (
      showSidebar:
          _isHistoryOpen &&
          !isEditingPositions &&
          !isAnnotating &&
          !isInpaintTab,
      showButton:
          !_isHistoryOpen &&
          !isEditingPositions &&
          !isAnnotating &&
          !isInpaintTab,
    );
  }

  void _onViewModelChanged() {
    if (!mounted) return;
    if (_lastVmHistoryOpen != widget.viewModel.canvasHistoryOpen) {
      _lastVmHistoryOpen = widget.viewModel.canvasHistoryOpen;
      _isHistoryOpen = _lastVmHistoryOpen;
    }
    _syncAnimations();
  }

  void _onHistoryControllerChanged() {
    if (!mounted || _targetShowSidebar) return;
    if (_historyController.value <= _buttonRevealThreshold) {
      _syncButtonAnimation();
    }
  }

  void _syncAnimations({bool immediate = false}) {
    final states = _computeHistoryStates();
    _targetShowSidebar = states.showSidebar;

    if (immediate || _reduceMotion || !_tickerEnabled) {
      final targetHistoryValue = states.showSidebar ? 1.0 : 0.0;
      if (_historyController.value != targetHistoryValue) {
        _historyController.value = targetHistoryValue;
      }
      _syncButtonAnimation(immediate: true, states: states);
      return;
    }

    if (states.showSidebar) {
      if (_historyController.status != AnimationStatus.forward &&
          _historyController.status != AnimationStatus.completed) {
        _historyController.forward();
      }
    } else {
      if (_historyController.status != AnimationStatus.reverse &&
          _historyController.status != AnimationStatus.dismissed) {
        _historyController.reverse();
      }
    }

    _syncButtonAnimation(states: states);
  }

  void _syncButtonAnimation({
    bool immediate = false,
    ({bool showSidebar, bool showButton})? states,
  }) {
    final resolvedStates = states ?? _computeHistoryStates();
    final canRevealButton =
        resolvedStates.showButton &&
        (_reduceMotion ||
            !_tickerEnabled ||
            _historyController.value <= _buttonRevealThreshold);

    if (immediate || _reduceMotion || !_tickerEnabled) {
      final targetButtonValue = resolvedStates.showButton ? 1.0 : 0.0;
      if (_buttonController.value != targetButtonValue) {
        _buttonController.value = targetButtonValue;
      }
      return;
    }

    if (canRevealButton) {
      if (_buttonController.status != AnimationStatus.forward &&
          _buttonController.status != AnimationStatus.completed) {
        _buttonController.forward();
      }
    } else {
      if (_buttonController.status != AnimationStatus.reverse &&
          _buttonController.status != AnimationStatus.dismissed) {
        _buttonController.reverse();
      }
    }
  }

  void _setHistoryOpen(bool isOpen) {
    Tooltip.dismissAllToolTips();
    if (_isHistoryOpen != isOpen) {
      setState(() => _isHistoryOpen = isOpen);
    }
    _lastVmHistoryOpen = isOpen;
    widget.viewModel.setCanvasHistoryOpen(isOpen);
    _syncAnimations();
  }

  void _viewLatest() {
    widget.viewModel.selectLatestImage();
    _stream.scrollToTop();
  }

  /// 有 AI 元数据则弹窗检查，无元数据则回退导入为参考图
  Future<void> _inspectOrImportImage(Uint8List bytes, String fileName) async {
    final metadata = await ImageMetadataService.parseMetadataAsync(bytes);
    if (metadata != null && metadata.hasData && mounted) {
      await MetadataReaderDialog.show(
        context,
        metadata: metadata,
        imageBytes: bytes,
        fileName: fileName,
        viewModel: widget.viewModel,
      );
    } else if (mounted) {
      await widget.viewModel.board.importReferenceImageFromBytes(
        bytes,
        fileName: fileName,
      );
      if (mounted) {
        showCanvasSnackBar(
          context,
          context.l10n.canvasImportedReference(fileName),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        if (TickerMode.valuesOf(context).enabled) widget.viewModel,
      ]),
      builder: (context, _) {
        final viewModel = widget.viewModel;
        if (_lastVmHistoryOpen != viewModel.canvasHistoryOpen) {
          _lastVmHistoryOpen = viewModel.canvasHistoryOpen;
          _isHistoryOpen = _lastVmHistoryOpen;
        }
        final gallery = viewModel.gallery;
        final isGenerating = viewModel.isGenerating;
        final isEditingPositions =
            viewModel.isEditingCharacterPositions ||
            viewModel.isEditingWatermarkPosition;
        final isAnnotating = viewModel.board.isAnnotatingImage;
        final isInpaintTab =
            !widget.compact &&
            viewModel.activeSidebarTab == StudioSidebarTab.inpaint &&
            !isEditingPositions;
        final selectedImage =
            viewModel.selectedImage ??
            (gallery.isNotEmpty ? gallery.first : null);

        final showEmptyState =
            gallery.isEmpty &&
            !isGenerating &&
            !isEditingPositions &&
            !isAnnotating;

        final states = _computeHistoryStates();
        final showButton = states.showButton;
        final sidebarChild = CanvasHistorySidebar(
          viewModel: viewModel,
          selectedImage: selectedImage,
          stream: _stream,
          onClose: () => _setHistoryOpen(false),
        );

        final canAcceptDrop =
            (ModalRoute.of(context)?.isCurrent ?? true) &&
            TickerMode.valuesOf(context).enabled;
        return DropTarget(
      enable: canAcceptDrop,
      onDragEntered: (_) {
        if (!canAcceptDrop) return;
        setState(() => _isDraggingOver = true);
      },
      onDragExited: (_) => setState(() => _isDraggingOver = false),
      onDragDone: (details) async {
        setState(() => _isDraggingOver = false);
        if (!canAcceptDrop) return;
        for (final file in details.files) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            if (context.mounted) {
              await _inspectOrImportImage(bytes, file.name);
            }
            break;
          }
        }
      },
      // 注：全局 Ctrl+V 粘贴由 StudioView 的 HardwareKeyboard 处理器接管
      // (全局处理器先于焦点系统执行，此处不再挂 CallbackShortcuts，避免不可达死代码)
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: Container(
          color: context.colors.canvasBackground, // Notion 统一暖纸本底色
          child: Stack(
            fit: StackFit.expand,
            children: [
              // 1. 中间核心：主画布区 (随历史侧栏平滑让出宽度) + 右侧占位槽位
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1.1 主画布及其附属浮层 (底栏/徽章/保存/左上展开/新图横幅随画布自适应居中与避让)
                    Expanded(
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          isAnnotating
                              ? FreeformAnnotationBoard(viewModel: viewModel)
                              : (isInpaintTab
                                    ? InpaintRepairCanvas(viewModel: viewModel)
                                    : (showEmptyState
                                          ? CanvasEmptyState(
                                              viewModel: viewModel,
                                            )
                                          : ImageStreamView(
                                              viewModel: viewModel,
                                              controller: _stream,
                                              compact: widget.compact,
                                            ))),

                          // 角色位置编辑模式下的悬浮浮动操作层
                          if (isEditingPositions)
                            Positioned.fill(
                              child: CanvasPositionFloatingControls(
                                viewModel: viewModel,
                              ),
                            ),

                          // 底部操作浮层：窄屏合并为统一胶囊条+快捷生成，宽屏拆分为左下参数徽章 + 右下保存/快捷生成
                          if (!isEditingPositions &&
                              !isAnnotating &&
                              !isInpaintTab)
                            if (widget.compact)
                              Positioned(
                                bottom: 12,
                                left: 12,
                                right: 12,
                                child: Center(
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(
                                      maxWidth: 620,
                                    ),
                                    child: Row(
                                      mainAxisAlignment: selectedImage != null
                                          ? MainAxisAlignment.center
                                          : MainAxisAlignment.end,
                                      children: [
                                        if (selectedImage != null) ...[
                                          Expanded(
                                            child: MobileCanvasActionBar(
                                              image: selectedImage,
                                              viewModel: viewModel,
                                              onInpaintPressed:
                                                  widget.onSentToInpaint,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                        ],
                                        CanvasQuickGenerateButton(
                                          viewModel: viewModel,
                                          compact: true,
                                          iconOnly: selectedImage != null,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              if (selectedImage != null)
                                Positioned(
                                  bottom: 18,
                                  left: 18,
                                  child: CanvasParamBadges(
                                    image: selectedImage,
                                    viewModel: viewModel,
                                  ),
                                ),
                              Positioned(
                                bottom: 18,
                                right: 18,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (selectedImage != null)
                                      IgnorePointer(
                                        ignoring: !selectedImage.isUnsaved,
                                        child: AppPanelReveal(
                                          visible: selectedImage.isUnsaved,
                                          animateSize: true,
                                          enableBlur: false,
                                          slideOffset: AppMotionDistances.base,
                                          child: Padding(
                                            padding: EdgeInsets.only(
                                              right:
                                                  viewModel
                                                      .isLeftSidebarCollapsed
                                                  ? 8
                                                  : 0,
                                            ),
                                            child: CanvasSaveButton(
                                              viewModel: viewModel,
                                            ),
                                          ),
                                        ),
                                      ),
                                    if (viewModel.isLeftSidebarCollapsed)
                                      CanvasQuickGenerateButton(
                                        viewModel: viewModel,
                                      ),
                                  ],
                                ),
                              ),
                            ],

                          // 左上角浮动操作栏 (仅桌面端左侧栏完全收起时显示：
                          // 常规画板提供 展开 + 词库/标签/设置 直达；特殊模式仅保留轻量展开键)
                          if (!widget.compact &&
                              viewModel.isLeftSidebarCollapsed)
                            Positioned(
                              top: 14,
                              left: 14,
                              child: (isInpaintTab ||
                                      isEditingPositions ||
                                      isAnnotating)
                                  ? AppIconButton(
                                      key: const Key(
                                        'canvas_expand_sidebar_button',
                                      ),
                                      icon: Icons
                                          .keyboard_double_arrow_right_rounded,
                                      size: 38,
                                      iconSize: 20,
                                      variant: AppIconButtonVariant.elevated,
                                      tooltip:
                                          context.l10n.sidebarExpandTooltip,
                                      onPressed:
                                          viewModel.toggleLeftSidebarCollapsed,
                                    )
                                  : CanvasCollapsedQuickDock(
                                      viewModel: viewModel,
                                    ),
                            ),

                          // 顶部浮动：新图片生成提示气泡
                          Positioned(
                            top: 14,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              ignoring:
                                  !viewModel.hasUnseenLatest ||
                                  gallery.isEmpty ||
                                  isEditingPositions ||
                                  isAnnotating,
                              child: Center(
                                child: AppPanelReveal(
                                  visible:
                                      viewModel.hasUnseenLatest &&
                                      gallery.isNotEmpty &&
                                      !isEditingPositions &&
                                      !isAnnotating,
                                  animateSize: false,
                                  enableBlur: false,
                                  slideOffset: -AppMotionDistances.base,
                                  child: UnseenLatestBanner(
                                    onViewLatest: _viewLatest,
                                    onDismiss: viewModel.dismissUnseenBanner,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // 1.2 为右侧 History 侧边栏保留与抽屉同步的精确宽度
                    AnimatedBuilder(
                      animation: _historyController,
                      builder: (context, _) {
                        final t = _historyCurve.value.clamp(0.0, 1.0);
                        return SizedBox(width: _historySidebarWidth * t);
                      },
                    ),
                  ],
                ),
              ),

              // 2. 右上角浮动 History 展开按键 (置于侧边栏层之下：点击即刻清 Tooltip 并 90ms 急速退场，
              //    避免在侧边栏弹出后残留或悬浮于侧栏标题之上；收起时待侧栏让出角落再平滑浮现)
              Positioned(
                top: 14,
                right: 14,
                child: AnimatedBuilder(
                  animation: Listenable.merge([
                    _buttonController,
                    _historyController,
                  ]),
                  builder: (context, innerChild) {
                    final canReveal =
                        showButton &&
                        (_reduceMotion ||
                            !_tickerEnabled ||
                            _historyController.value <= _buttonRevealThreshold);
                    if (_buttonController.isDismissed && !canReveal) {
                      return const SizedBox.shrink();
                    }
                    final t = _buttonCurve.value.clamp(0.0, 1.0);
                    final interactive =
                        showButton && _historyController.isDismissed;
                    return IgnorePointer(
                      ignoring: !interactive,
                      child: TooltipVisibility(
                        visible: interactive,
                        child: Opacity(
                          opacity: t,
                          child: Transform.translate(
                            offset: Offset(10.0 * (1.0 - t), 0),
                            child: Transform.scale(
                              scale: 0.86 + 0.14 * t,
                              child: innerChild!,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: HistoryToggleButton(
                    onTap: () => _setHistoryOpen(true),
                  ),
                ),
              ),

              // 3. 右侧垂直 History 缩略图侧边栏 (位于按键层之上，从右缘完整滑入)
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                child: AnimatedBuilder(
                  animation: _historyController,
                  builder: (context, innerChild) {
                    final t = _historyCurve.value.clamp(0.0, 1.0);
                    if (t <= 0.001) return const SizedBox.shrink();
                    return SizedBox(
                      width: _historySidebarWidth * t,
                      child: ClipRect(
                        child: OverflowBox(
                          minWidth: _historySidebarWidth,
                          maxWidth: _historySidebarWidth,
                          alignment: Alignment.topLeft,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              color: context.colors.cardBackground,
                              border: Border(
                                left: BorderSide(
                                  color: context.colors.borderDefault,
                                ),
                              ),
                            ),
                            child: innerChild,
                          ),
                        ),
                      ),
                    );
                  },
                  child: sidebarChild,
                ),
              ),

              // 4. 外部拖入高亮指示层
              AppDropTargetOverlay(
                isDragging: _isDraggingOver,
                title: context.l10n.canvasDropTargetTitle,
              ),
            ],
          ),
        ),
      ),
        );
      },
    );
  }
}
