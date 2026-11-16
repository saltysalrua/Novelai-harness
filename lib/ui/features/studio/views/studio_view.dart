import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../../data/services/window_state_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../../../core/widgets/app_keep_alive_page.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/custom_title_bar.dart';
import '../../../core/widgets/resizable_split_view.dart';
import '../../../core/widgets/window_controls.dart';
import '../../settings/views/settings_dialog.dart';
import '../view_models/studio_view_model.dart';
import '../widgets/agent_chat_card.dart';
import '../widgets/annotation_history_strip.dart';
import '../widgets/image_canvas_actions.dart';
import '../widgets/image_canvas_card.dart';
import '../widgets/metadata_reader_dialog.dart';
import '../widgets/parameter_card.dart';
import '../widgets/prompt_library_view.dart';
import '../widgets/studio_sidebar.dart';

class StudioView extends StatefulWidget {
  const StudioView({super.key});

  /// 宽屏三栏工作台的最小可用宽度 (窄屏双层布局与宽屏三栏布局的唯一切换断点)。
  ///
  /// 三栏最小宽度 (左 240 + 中 300 + 右 280) 加分隔条与侧栏余量约需 900px；
  /// 低于此宽度统一改用窄屏双层布局，避免三栏被压到内容溢出，
  /// 也保证窄屏形态全应用只有一套。
  static const double wideLayoutMinWidth = 900;

  /// 仅供完整应用测试读取活动 ViewModel (注入消息/断言快捷键状态)
  @visibleForTesting
  static StudioViewModel? testViewModelHook;

  @override
  State<StudioView> createState() => _StudioViewState();
}

class _StudioViewState extends State<StudioView> {
  late final StudioViewModel _viewModel;

  /// 进入全屏词库前的侧边栏页签 (用于退出词库时恢复)
  StudioSidebarTab _previousSidebarTab = StudioSidebarTab.parameters;

  /// 对话卡状态键：根级双击 ESC 时跨组件调起回溯视图
  final GlobalKey<AgentChatCardState> _chatCardKey =
      GlobalKey<AgentChatCardState>();

  /// 根级 ESC 首按时刻 (双击窗口判定)
  DateTime? _lastRootEscTime;

  /// 手机/窄屏模式三卡片水平滑动控制器
  late final PageController _mobilePageController;
  int _mobilePageIndex = 0;

  /// 窄屏跨屏工作流状态追踪 (用于生成/定位编辑/修复/批注发送时的自动流转)
  bool _isNarrowViewport = false;
  bool _wasGenerating = false;
  bool _wasEditingPositions = false;
  bool _wasAnnotating = false;
  StudioSidebarTab? _lastObservedSidebarTab;
  int? _pageBeforePositionEdit;
  int? _pageBeforeInpaint;
  late Object _lastShellSig;
  int _outerBuildSeq = 0;
  int _cachedOuterBuildSeq = -1;
  bool? _cachedIsNarrow;
  Widget? _cachedLayoutBody;

  Object _computeShellSig() {
    final selected =
        _viewModel.selectedImage ??
        (_viewModel.gallery.isNotEmpty ? _viewModel.gallery.first : null);
    return (
      _viewModel.errorMessage,
      _viewModel.activeSidebarTab,
      _viewModel.isLeftSidebarCollapsed,
      _viewModel.board.isAnnotatingImage,
      _viewModel.isEditingCharacterPositions,
      _viewModel.isEditingWatermarkPosition,
      _viewModel.isGenerating,
      _viewModel.isChatStreaming,
      selected?.id,
    );
  }

  void _onViewModelChanged() {
    _handleViewModelStateTransitions();
    if (!mounted) return;
    final nextSig = _computeShellSig();
    if (nextSig != _lastShellSig) {
      _lastShellSig = nextSig;
      setState(() {});
    }
  }

  @override
  void initState() {
    super.initState();
    _viewModel = StudioViewModel();
    _viewModel.init();
    _mobilePageController = PageController(initialPage: 0);
    _wasGenerating = _viewModel.isGenerating;
    _wasEditingPositions =
        _viewModel.isEditingCharacterPositions ||
        _viewModel.isEditingWatermarkPosition;
    _wasAnnotating = _viewModel.board.isAnnotatingImage;
    _lastObservedSidebarTab = _viewModel.activeSidebarTab;
    if (_viewModel.activeSidebarTab != StudioSidebarTab.library) {
      _previousSidebarTab = _viewModel.activeSidebarTab;
    }
    _lastShellSig = _computeShellSig();
    _viewModel.addListener(_onViewModelChanged);
    WindowStateService.instance.beforeClose = _viewModel.flushPendingSaves;
    StudioView.testViewModelHook = _viewModel;
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvents);
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelChanged);
    _mobilePageController.dispose();
    if (WindowStateService.instance.beforeClose ==
        _viewModel.flushPendingSaves) {
      WindowStateService.instance.beforeClose = null;
    }
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvents);
    if (StudioView.testViewModelHook == _viewModel) {
      StudioView.testViewModelHook = null;
    }
    _viewModel.dispose();
    super.dispose();
  }

  bool _isTypingText() {
    final currentFocus = FocusManager.instance.primaryFocus;
    if (currentFocus == null || currentFocus.context == null) return false;
    final widget = currentFocus.context!.widget;
    if (widget is EditableText) return true;
    return currentFocus.context!
            .findAncestorWidgetOfExactType<EditableText>() !=
        null;
  }

  bool _handleGlobalKeyEvents(KeyEvent event) {
    // 仅处理按下与长按重复；ESC 重复必须一并吞掉，否则会穿透到根级
    // 双击 ESC 判定，长按 ESC 误触发回溯视图
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;

    // 输出期间 Esc 不依赖输入框/补全菜单的焦点冒泡，优先停止 Agent。
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      if (event is KeyRepeatEvent) return true;
      if (_viewModel.isChatStreaming) {
        _handleGlobalEsc();
        return true;
      }
    }

    // 当处于批注模式时：
    if (_viewModel.board.isAnnotatingImage) {
      if (_isTypingText()) return false;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (event is KeyDownEvent) {
          _viewModel.board.setAnnotatingImage(false);
        }
        return true;
      }
    }

    // 当处于角色或水印位置编辑模式时：
    if (_viewModel.isEditingCharacterPositions) {
      if (_isTypingText()) return false;

      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.arrowLeft ||
          key == LogicalKeyboardKey.arrowUp) {
        _viewModel.cycleSelectedCharacter(-1);
        return true;
      }
      if (key == LogicalKeyboardKey.arrowRight ||
          key == LogicalKeyboardKey.arrowDown) {
        _viewModel.cycleSelectedCharacter(1);
        return true;
      }
      if (key == LogicalKeyboardKey.escape) {
        // 仅首次按下退出，重复事件只消费不动作
        if (event is KeyDownEvent) {
          _viewModel.setEditingCharacterPositions(false);
        }
        return true;
      }
    }

    if (_viewModel.isEditingWatermarkPosition) {
      if (_isTypingText()) return false;
      final key = event.logicalKey;
      if (key == LogicalKeyboardKey.escape) {
        if (event is KeyDownEvent) {
          _viewModel.setEditingWatermarkPosition(false);
        }
        return true;
      }
    }

    // 全局快捷键 Ctrl+V / Cmd+V 粘贴检查图片元数据
    final isControlOrCmd =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    if (isControlOrCmd && event.logicalKey == LogicalKeyboardKey.keyV) {
      if (!_isTypingText() &&
          !_viewModel.isEditingCharacterPositions &&
          !_viewModel.isEditingWatermarkPosition &&
          !_viewModel.board.isAnnotatingImage) {
        if (event is KeyDownEvent) {
          _handleGlobalPaste();
        }
        return true;
      }
    }

    // 全局 Ctrl+O / Cmd+O：全局展开/折叠对话思考块 (与 Pi TUI 习惯一致)。
    // 走 HardwareKeyboard 优先分发而非焦点链 CallbackShortcuts，
    // 下拉菜单/覆盖层聚焦、焦点悬空等场景同样百分百生效
    if (isControlOrCmd && event.logicalKey == LogicalKeyboardKey.keyO) {
      // 长按重复事件只消费不动作
      if (event is KeyDownEvent) {
        _viewModel.toggleThinkingExpanded();
      }
      return true;
    }

    // 浏览器式整体 UI 缩放：Ctrl+= 放大 / Ctrl+- 缩小 / Ctrl+0 重置。
    // 输入框聚焦时交还给文本编辑链路 (打字场景不该抢键)；
    // 长按 KeyRepeatEvent 连续步进 (与方向键循环同理)。
    if (isControlOrCmd) {
      final key = event.logicalKey;
      final bool isZoomKey;
      if (key == LogicalKeyboardKey.equal ||
          key == LogicalKeyboardKey.numpadAdd ||
          key == LogicalKeyboardKey.minus ||
          key == LogicalKeyboardKey.numpadSubtract) {
        isZoomKey = true;
      } else if (key == LogicalKeyboardKey.digit0 ||
          key == LogicalKeyboardKey.numpad0) {
        isZoomKey = true;
      } else {
        isZoomKey = false;
      }
      if (isZoomKey && !_isTypingText()) {
        if (key == LogicalKeyboardKey.equal ||
            key == LogicalKeyboardKey.numpadAdd) {
          _viewModel.zoomInUi();
        } else if (key == LogicalKeyboardKey.minus ||
            key == LogicalKeyboardKey.numpadSubtract) {
          _viewModel.zoomOutUi();
        } else {
          _viewModel.resetUiZoom();
        }
        return true;
      }
    }

    return false;
  }

  /// 全局 Ctrl+V 粘贴图片处理：优先解析并弹窗检查元数据，无元数据则导入为画板参考图
  Future<void> _handleGlobalPaste() async {
    try {
      final (imageBytes, fileName) =
          await ImageMetadataService.readClipboardImageAsync();
      if (imageBytes != null && imageBytes.isNotEmpty && mounted) {
        final metadata = await ImageMetadataService.parseMetadataAsync(
          imageBytes,
        );
        if (metadata != null && metadata.hasData && mounted) {
          await MetadataReaderDialog.show(
            context,
            metadata: metadata,
            imageBytes: imageBytes,
            fileName: fileName ?? context.l10n.studioClipboardImageDefaultName,
            viewModel: _viewModel,
          );
        } else if (mounted) {
          await _viewModel.board.importReferenceImageFromBytes(
            imageBytes,
            fileName: fileName,
          );
          if (mounted) {
            showCanvasSnackBar(context, context.l10n.studioImportedReference);
          }
        }
      }
    } catch (_) {}
  }

  /// 根级 ESC：双击 400ms 内进入回溯视图；单击中断生成/流式
  ///
  /// 输出期间由 HardwareKeyboard 优先分发，其余场景由焦点链分发。
  /// 对话卡通过 onEscape 复用同一计时器，避免跨焦点双击判定失效。
  void _handleGlobalEsc() {
    final now = DateTime.now();
    final isDoublePress =
        _lastRootEscTime != null &&
        now.difference(_lastRootEscTime!) <= const Duration(milliseconds: 400);
    _lastRootEscTime = now;

    if (isDoublePress) {
      _lastRootEscTime = null;
      if (_viewModel.isChatStreaming) {
        _viewModel.abortChat();
      }
      _chatCardKey.currentState?.openRewindView();
      return;
    }

    if (_viewModel.isChatStreaming) {
      _viewModel.abortChat();
      return;
    }

    if (_viewModel.activeSidebarTab == StudioSidebarTab.library) {
      _viewModel.setActiveSidebarTab(_previousSidebarTab, expandSidebar: false);
      return;
    }

    if (_viewModel.board.isAnnotatingImage) {
      _viewModel.board.setAnnotatingImage(false);
      return;
    }

    if (_viewModel.isEditingCharacterPositions) {
      _viewModel.setEditingCharacterPositions(false);
      return;
    }

    if (_viewModel.isEditingWatermarkPosition) {
      _viewModel.setEditingWatermarkPosition(false);
      return;
    }

    if (_viewModel.isGenerating) {
      _viewModel.abortGeneration();
    } else if (_viewModel.isChatStreaming) {
      _viewModel.abortChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    _outerBuildSeq++;
    final isLibraryTab =
        _viewModel.activeSidebarTab == StudioSidebarTab.library;

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): _handleGlobalEsc,
        // Ctrl+O 改由 _handleGlobalKeyEvents (HardwareKeyboard 优先分发)
        // 统一处理，避免焦点链漏派
      },
      child: Focus(
        autofocus: true,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow =
                constraints.maxWidth < StudioView.wideLayoutMinWidth;
            _isNarrowViewport = isNarrow;
            // 仅在宽窄断点切换或外层 Shell 重建时重新构建三栏/窄屏骨架，
            // 窗口拖动缩放时不于 LAYOUT 阶段同步重建整棵工作台树。
            if (_cachedLayoutBody != null &&
                _cachedIsNarrow == isNarrow &&
                _cachedOuterBuildSeq == _outerBuildSeq) {
              return _cachedLayoutBody!;
            }
            _cachedIsNarrow = isNarrow;
            _cachedOuterBuildSeq = _outerBuildSeq;
            // 系统返回键 (Android 手势/物理键) 先在层内消费，无可消费层时交还系统。
            // canPop 由判态驱动：无层内动作时保持 true，交由系统正常退出/回桌面。
            return _cachedLayoutBody = PopScope(
              canPop: !_hasSystemBackAction(isNarrow: isNarrow),
              onPopInvokedWithResult: (didPop, _) {
                if (didPop) return;
                _handleSystemBack(isNarrow: isNarrow);
              },
              child: Scaffold(
                backgroundColor: context.colors.canvasBackground,
                body: isNarrow
                    ? _buildNarrowLayout(context, isLibraryTab: isLibraryTab)
                    : _buildWideLayout(context, isLibraryTab: isLibraryTab),
              ),
            );
          },
        ),
      ),
    );
  }

  /// 桌面端 / 宽屏 (宽度 >= [StudioView.wideLayoutMinWidth])：保持经典三栏自适应工作台与无边框拖拽标题栏
  Widget _buildWideLayout(BuildContext context, {required bool isLibraryTab}) {
    final isLeftCollapsed = _viewModel.isLeftSidebarCollapsed;

    return Column(
      children: [
        // 顶部自定义 Notion 风格标题栏 (支持窗口拖拽与三键控制)
        if (kIsWeb || defaultTargetPlatform != TargetPlatform.macOS)
          const CustomTitleBar(),

        // 全局错误提示微胶囊
        _StudioErrorBanner(
          errorMessage: _viewModel.errorMessage,
          onDismiss: _viewModel.clearError,
        ),

        // 主体区域：最左侧导航栏 + 主工作台/全屏词库覆盖视图
        Expanded(
          child: Row(
            children: [
              // 1. 最左侧 Notion 极简侧边栏 (可完全收起，保持子树状态)
              AppPanelReveal(
                visible: !isLeftCollapsed,
                axis: Axis.horizontal,
                alignment: Alignment.centerLeft,
                openDuration: AppMotionDurations.fast,
                closeDuration: AppMotionDurations.quick,
                slideOffset: AppMotionDistances.base,
                enableBlur: false,
                maintainState: true,
                child: StudioSidebar(
                  viewModel: _viewModel,
                  activeTab: _viewModel.activeSidebarTab,
                  connectedToCard: true,
                  onToggleCollapse: _viewModel.toggleLeftSidebarCollapsed,
                  onTabChanged: (tab) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    if (tab == StudioSidebarTab.library) {
                      if (_viewModel.activeSidebarTab ==
                          StudioSidebarTab.library) {
                        _viewModel.setActiveSidebarTab(
                          _previousSidebarTab,
                          expandSidebar: false,
                        );
                        return;
                      }
                      _previousSidebarTab = _viewModel.activeSidebarTab;
                    }
                    _viewModel.setActiveSidebarTab(tab);
                  },
                ),
              ),

              // 2. 主区域：全屏词库视图 (覆盖所有三栏) 或 主三栏自适应工作台
              Expanded(
                child: AppPageStack(
                  index: isLibraryTab ? 1 : 0,
                  itemCount: 2,
                  itemBuilder: (context, index) => index == 1
                      ? PromptLibraryView(
                          viewModel: _viewModel,
                          connectedLeft: !isLeftCollapsed,
                          onExpandSidebar: isLeftCollapsed
                              ? _viewModel.toggleLeftSidebarCollapsed
                              : null,
                          onClose: () {
                            _viewModel.setActiveSidebarTab(
                              _previousSidebarTab,
                              expandSidebar: false,
                            );
                          },
                        )
                      : ResizableThreeSplitView(
                          key: ValueKey(
                            'split-${_viewModel.board.isAnnotatingImage}',
                          ),
                          initialLeftWidth: _viewModel.splitLeftWidth,
                          initialRightWidth: _viewModel.board.isAnnotatingImage
                              ? 110.0
                              : _viewModel.splitRightWidth,
                          minRightWidth: _viewModel.board.isAnnotatingImage
                              ? 90.0
                              : 280.0,
                          maxRightWidth: _viewModel.board.isAnnotatingImage
                              ? 160.0
                              : 560.0,
                          leftCollapsed: isLeftCollapsed,
                          onWidthsChanged: (left, right) {
                            if (!_viewModel.board.isAnnotatingImage) {
                              _viewModel.updateSplitWidths(left, right);
                            }
                          },
                          leftChild: ParameterCard(
                            viewModel: _viewModel,
                            activeTab: _viewModel.activeSidebarTab,
                            connectedLeft: true,
                          ),
                          centerChild: ImageCanvasCard(viewModel: _viewModel),
                          rightChild: _viewModel.board.isAnnotatingImage
                              ? AnnotationHistoryStrip(viewModel: _viewModel)
                              : AgentChatCard(
                                  key: _chatCardKey,
                                  viewModel: _viewModel,
                                  onEscape: _handleGlobalEsc,
                                  onOverlayViewChanged:
                                      _onChatOverlayViewChanged,
                                ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 移动端 / 窄屏方案 A (宽度 < [StudioView.wideLayoutMinWidth])：
  /// 1. 底部 4 个一级主导航：[生图] (Page 0) / [画板] (Page 1) / [助手] (Page 2) / [词库] (Overlay)；
  /// 2. 顶部上下文子导航栏：在「生图」页承载 [参数 | 提示词 | 局部修复] 二级分段切换，
  ///    在画板/助手/词库页显示上下文标题与快捷操作，右侧常驻「设置」入口（及桌面窗口三键）；
  /// 3. 局部修复在 Page 0 内同屏整合蒙版画板 + 参数抽屉 + 生成坞，画板 Page 1 保持纯粹图像流；
  /// 4. 支持跨屏工作流自动流转（开始生图 → 画板、编辑位置 → 画板并自动返回、发送修复 → 局部修复、发送批注 → 助手）。
  Widget _buildNarrowLayout(
    BuildContext context, {
    required bool isLibraryTab,
  }) {
    final isEditingPositions =
        _viewModel.isEditingCharacterPositions ||
        _viewModel.isEditingWatermarkPosition;
    final lockHorizontalPageSwipe =
        _viewModel.board.isAnnotatingImage ||
        (isEditingPositions && _mobilePageIndex == 1) ||
        (_viewModel.activeSidebarTab == StudioSidebarTab.inpaint &&
            _mobilePageIndex == 0);
    final selectedImage =
        _viewModel.selectedImage ??
        (_viewModel.gallery.isNotEmpty ? _viewModel.gallery.first : null);

    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部上下文子导航 + 常驻设置 (+ 桌面端窗口拖拽控制)
          _MobileTopBar(
            activeIndex: _mobilePageIndex,
            isLibraryTab: isLibraryTab,
            activeSidebarTab: _viewModel.activeSidebarTab,
            isEditingPositions: isEditingPositions,
            isEditingWatermarkPosition: _viewModel.isEditingWatermarkPosition,
            isAnnotating: _viewModel.board.isAnnotatingImage,
            hasSelectedImage: selectedImage != null,
            onStudioTabSelected: (tab) {
              _viewModel.setActiveSidebarTab(tab, expandSidebar: false);
            },
            onOpenSettings: () => SettingsDialog.show(context, _viewModel),
            onReadImageMetadata: () =>
                pickAndInspectImageMetadata(context, _viewModel),
            onQuickInpaint: selectedImage == null
                ? null
                : () {
                    _viewModel.sendImageToInpaint(selectedImage);
                    _setMobilePage(0);
                  },
          ),

          // 全局错误提示微胶囊 (直接置于顶部栏正下方)
          _StudioErrorBanner(
            errorMessage: _viewModel.errorMessage,
            onDismiss: _viewModel.clearError,
          ),

          // 中间核心区域：三卡片 PageView 始终保活，词库以覆盖层形式叠在其上。
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Visibility(
                  visible: !isLibraryTab,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: true,
                  maintainInteractivity: false,
                  child: PageView(
                    controller: _mobilePageController,
                    physics: lockHorizontalPageSwipe
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: _onMobilePageChanged,
                    children: [
                      // Page 0: 生图工作台面板 (参数 / 提示词 / 同屏局部修复 + 底部生成坞)
                      AppKeepAlivePage(
                        active: _mobilePageIndex == 0,
                        child: ParameterCard(
                          compact: true,
                          viewModel: _viewModel,
                          activeTab: _viewModel.activeSidebarTab,
                          onExitInpaint: _exitInpaintFromNarrow,
                        ),
                      ),
                      // Page 1: 画板面板 (窄屏模式启用统一底栏与 ActionSheet)
                      AppKeepAlivePage(
                        active: _mobilePageIndex == 1,
                        child: ImageCanvasCard(
                          compact: true,
                          viewModel: _viewModel,
                          onSentToInpaint: () => _setMobilePage(0),
                        ),
                      ),
                      // Page 2: AI 助手面板 (批注模式依然保活助手，不替换为桌面拖拽历史条)
                      AppKeepAlivePage(
                        active: _mobilePageIndex == 2,
                        child: KeyedSubtree(
                          key: const ValueKey<String>('narrow_page_chat'),
                          child: AgentChatCard(
                            key: _chatCardKey,
                            compact: true,
                            viewModel: _viewModel,
                            onEscape: _handleGlobalEsc,
                            onOverlayViewChanged: _onChatOverlayViewChanged,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                IgnorePointer(
                  ignoring: !isLibraryTab,
                  child: AppPanelReveal(
                    visible: isLibraryTab,
                    animateSize: false,
                    openDuration: AppMotionDurations.fast,
                    closeDuration: AppMotionDurations.quick,
                    slideOffset: AppMotionDistances.medium,
                    enableBlur: false,
                    child: PromptLibraryView(
                      viewModel: _viewModel,
                      onClose: () {
                        _viewModel.setActiveSidebarTab(
                          _previousSidebarTab,
                          expandSidebar: false,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 底部一级主导航栏：[生图] [画板] [助手] [词库]
          // 软键盘展开时让出底部快捷栏占用，不挤压输入与消息区。
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            _buildMobileBottomBar(context, isLibraryTab: isLibraryTab),
        ],
      ),
    );
  }

  /// 窄屏跨屏工作流状态流转与记忆恢复
  void _handleViewModelStateTransitions() {
    final isGenerating = _viewModel.isGenerating;
    final isEditingPositions =
        _viewModel.isEditingCharacterPositions ||
        _viewModel.isEditingWatermarkPosition;
    final isAnnotating = _viewModel.board.isAnnotatingImage;
    final currentTab = _viewModel.activeSidebarTab;

    if (currentTab != StudioSidebarTab.library) {
      _previousSidebarTab = currentTab;
    }

    if (mounted && _isNarrowViewport) {
      // 1. 角色/水印位置编辑：自动前往 Page 1 画板，完成/取消后自动返回来源页
      if (!_wasEditingPositions && isEditingPositions) {
        _pageBeforePositionEdit = _mobilePageIndex;
        if (_mobilePageIndex != 1) {
          _setMobilePage(1);
        }
      } else if (_wasEditingPositions && !isEditingPositions) {
        final returnPage = _pageBeforePositionEdit;
        _pageBeforePositionEdit = null;
        if (returnPage != null && _mobilePageIndex == 1 && returnPage != 1) {
          _setMobilePage(returnPage);
        }
      }

      // 2. 由图片或批注触发「发送到修复」进入局部修复页签时，记录来源页并自动前往 Page 0 同屏工作台
      if (_lastObservedSidebarTab != null &&
          _lastObservedSidebarTab != StudioSidebarTab.library &&
          _lastObservedSidebarTab != StudioSidebarTab.inpaint &&
          currentTab == StudioSidebarTab.inpaint &&
          !isEditingPositions) {
        _pageBeforeInpaint = _mobilePageIndex;
        if (_mobilePageIndex != 0) {
          _setMobilePage(0);
        }
      } else if (_lastObservedSidebarTab == StudioSidebarTab.inpaint &&
          currentTab != StudioSidebarTab.inpaint &&
          currentTab != StudioSidebarTab.library) {
        _pageBeforeInpaint = null;
      }

      // 3. 在参数/提示词页开始生图时，自动切换到画板页观看去噪实时流
      if (!_wasGenerating &&
          isGenerating &&
          currentTab != StudioSidebarTab.inpaint &&
          _mobilePageIndex == 0) {
        _setMobilePage(1);
      }

      // 4. 进入批注模式自动切到画板页；发送批注到 AI 进入流式回复时自动切到助手页
      if (!_wasAnnotating && isAnnotating) {
        if (_mobilePageIndex != 1) {
          _setMobilePage(1);
        }
      } else if (_wasAnnotating &&
          !isAnnotating &&
          _viewModel.isChatStreaming) {
        _setMobilePage(2);
      }
    }

    _wasGenerating = isGenerating;
    _wasEditingPositions = isEditingPositions;
    _wasAnnotating = isAnnotating;
    _lastObservedSidebarTab = currentTab;
  }

  /// 窄屏三卡片切换单一入口：先落状态再动画，保证底部高亮与当前页面永不脱节。
  void _setMobilePage(int index, {bool animate = true}) {
    if (index < 0 || index > 2) return;
    if (_mobilePageIndex != index) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _mobilePageIndex = index);
    }
    if (!animate) return;
    if (_mobilePageController.hasClients) {
      final current = _mobilePageController.page?.round();
      if (current == index) return;
      if (AppMotion.shouldReduceMotion(context)) {
        _mobilePageController.jumpToPage(index);
        return;
      }
      _mobilePageController.animateToPage(
        index,
        duration: AppMotionDurations.fast,
        curve: AppMotionCurves.smoothOut,
      );
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_mobilePageController.hasClients) return;
        if (_mobilePageController.page?.round() != _mobilePageIndex) {
          _mobilePageController.jumpToPage(_mobilePageIndex);
        }
      });
    }
  }

  /// 手势横滑翻页后的状态回写 (唯一由 PageView 反向同步索引的入口)
  void _onMobilePageChanged(int index) {
    if (_mobilePageIndex != index) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _mobilePageIndex = index);
    }
  }

  /// 切换底部一级主导航 (若处于词库覆盖层则先退出回到之前的创作子页签)
  void _selectMobilePrimaryTab(int index) {
    if (_viewModel.activeSidebarTab == StudioSidebarTab.library) {
      _viewModel.setActiveSidebarTab(_previousSidebarTab, expandSidebar: false);
    }
    _setMobilePage(index);
  }

  /// 窄屏下退出局部修复模式：切回修复前子页签，若由画板跳转而来则返回原页
  void _exitInpaintFromNarrow() {
    final returnPage = _pageBeforeInpaint;
    _pageBeforeInpaint = null;
    _viewModel.exitInpaintMode(expandSidebar: false);
    if (_isNarrowViewport &&
        returnPage != null &&
        returnPage != 0 &&
        _mobilePageIndex == 0) {
      _setMobilePage(returnPage);
    }
  }

  /// 对话卡覆盖视图开合回写：canPop 判态在 build 中动态读取卡片 State，
  /// 这里只需触发一次重建让 [PopScope] 跟上新状态。
  /// 注意不能在宿主缓存布尔——批注模式会把 AgentChatCard 整体卸载，
  /// 缓存会滞留 true 导致系统返回键被死锁拦截。
  void _onChatOverlayViewChanged() {
    setState(() {});
  }

  /// 系统返回键是否存在可消费的层内动作 (与 [_handleSystemBack] 分支顺序严格一致)
  bool _hasSystemBackAction({required bool isNarrow}) {
    if (_viewModel.activeSidebarTab == StudioSidebarTab.library) return true;
    // 动态读取卡片当前 State：卡片被批注模式卸载后 currentState 为 null，
    // 判态自然归 false，不会吞掉返回键。
    if (_chatCardKey.currentState?.hasOverlayView ?? false) return true;
    if (_viewModel.board.isAnnotatingImage) return true;
    if (_viewModel.isEditingCharacterPositions) return true;
    if (_viewModel.isEditingWatermarkPosition) return true;
    if (isNarrow &&
        _mobilePageIndex == 0 &&
        _viewModel.activeSidebarTab == StudioSidebarTab.inpaint) {
      return true;
    }
    if (isNarrow && _mobilePageIndex != 0) return true;
    return false;
  }

  /// 系统返回键 (Android 物理键/侧滑手势) 单一处理入口：
  /// 词库覆盖层 → 对话卡覆盖视图 → 批注/定位编辑模式 → 窄屏修复模式 → 窄屏三卡片回到第 0 卡片；
  /// 以上均无命中时不动手，由 [PopScope] 的 canPop 交还系统。
  void _handleSystemBack({required bool isNarrow}) {
    if (_viewModel.activeSidebarTab == StudioSidebarTab.library) {
      _viewModel.setActiveSidebarTab(_previousSidebarTab, expandSidebar: false);
      return;
    }
    if (_chatCardKey.currentState?.dismissOverlayView() ?? false) return;
    if (_viewModel.board.isAnnotatingImage) {
      _viewModel.board.setAnnotatingImage(false);
      return;
    }
    if (_viewModel.isEditingCharacterPositions) {
      _viewModel.setEditingCharacterPositions(false);
      return;
    }
    if (_viewModel.isEditingWatermarkPosition) {
      _viewModel.setEditingWatermarkPosition(false);
      return;
    }
    if (isNarrow &&
        _mobilePageIndex == 0 &&
        _viewModel.activeSidebarTab == StudioSidebarTab.inpaint) {
      _exitInpaintFromNarrow();
      return;
    }
    if (isNarrow && _mobilePageIndex != 0) {
      _setMobilePage(0);
    }
  }

  /// 移动端方案 A 一级底部主导航栏：生图 / 画板 / 助手 / 词库
  Widget _buildMobileBottomBar(
    BuildContext context, {
    required bool isLibraryTab,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(top: BorderSide(color: colors.borderDefault, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 2),
          child: SizedBox(
            height: 46,
            child: AppSlidingSelectionBar(
              selectedIndex: isLibraryTab ? 3 : _mobilePageIndex.clamp(0, 2),
              expand: true,
              indicatorDecorationBuilder: (context, _) => BoxDecoration(
                color: colors.primaryTint,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.35),
                  width: 1.0,
                ),
              ),
              children: [
                // 1. 生图 (工作台参数/提示词/局部修复)
                _buildBottomBarItem(
                  context,
                  key: const Key('segmented_pill_0'),
                  icon: Icons.auto_awesome_outlined,
                  label: l10n.mobileTabStudio,
                  isSelected: !isLibraryTab && _mobilePageIndex == 0,
                  onTap: () => _selectMobilePrimaryTab(0),
                ),

                // 2. 画板 (图像流 / 位置编辑 / 自由批注画布)
                _buildBottomBarItem(
                  context,
                  key: const Key('segmented_pill_1'),
                  icon: Icons.palette_outlined,
                  label: l10n.mobileTabCanvas,
                  badgeText: _viewModel.isGenerating ? '●' : null,
                  isSelected: !isLibraryTab && _mobilePageIndex == 1,
                  onTap: () => _selectMobilePrimaryTab(1),
                ),

                // 3. 助手 (AI 对话与智能生图)
                _buildBottomBarItem(
                  context,
                  key: const Key('segmented_pill_2'),
                  icon: Icons.chat_bubble_outline_rounded,
                  label: l10n.mobileTabChat,
                  badgeText: _viewModel.isChatStreaming ? '●' : null,
                  isSelected: !isLibraryTab && _mobilePageIndex == 2,
                  onTap: () => _selectMobilePrimaryTab(2),
                ),

                // 4. 词库 (提示词组合管理器覆盖层)
                _buildBottomBarItem(
                  context,
                  key: const Key('mobile_nav_library'),
                  icon: Icons.collections_bookmark_outlined,
                  label: l10n.tabLibrary,
                  isSelected: isLibraryTab,
                  onTap: () {
                    if (!isLibraryTab) {
                      _previousSidebarTab = _viewModel.activeSidebarTab;
                      _viewModel.setActiveSidebarTab(
                        StudioSidebarTab.library,
                        expandSidebar: false,
                      );
                    } else {
                      _viewModel.setActiveSidebarTab(
                        _previousSidebarTab,
                        expandSidebar: false,
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBarItem(
    BuildContext context, {
    Key? key,
    required IconData icon,
    required String label,
    required bool isSelected,
    String? badgeText,
    required VoidCallback onTap,
  }) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned.fill(
          child: AppNavTile(
            key: key,
            title: label,
            icon: icon,
            isSelected: isSelected,
            activeBackgroundColor: Colors.transparent,
            activeBorderColor: Colors.transparent,
            margin: EdgeInsets.zero,
            enableSplash: false,
            onTap: onTap,
            axis: Axis.vertical,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
          ),
        ),
        if (badgeText != null)
          Positioned(
            top: 4,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: ExcludeSemantics(
                child: Center(
                  child: Transform.translate(
                    offset: const Offset(11, 0),
                    child: const _BottomBarPopDot(),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 移动端底栏状态指示点 (`03-notification-badge`)
class _BottomBarPopDot extends StatefulWidget {
  const _BottomBarPopDot();

  @override
  State<_BottomBarPopDot> createState() => _BottomBarPopDotState();
}

class _BottomBarPopDotState extends State<_BottomBarPopDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _initialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.verySlow,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = 1.0;
      _initialized = true;
    } else if (!_initialized) {
      _initialized = true;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final dot = Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(
        color: colors.primary,
        shape: BoxShape.circle,
        border: Border.all(color: colors.cardBackground, width: 1),
      ),
    );
    if (_reduceMotion) return dot;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _controller.value;
        if (v >= 1.0) return child!;
        final slideT = AppMotionCurves.smoothOut
            .transform((v / 0.52).clamp(0.0, 1.0))
            .clamp(0.0, 1.0);
        final popT = AppMotionCurves.bounce.transform(v);
        final fadeT = AppMotionCurves.smoothOut
            .transform((v / 0.80).clamp(0.0, 1.0))
            .clamp(0.0, 1.0);
        return Opacity(
          opacity: fadeT,
          child: Transform.translate(
            offset: Offset(-4.0 * (1.0 - slideT), 6.0 * (1.0 - slideT)),
            child: Transform.scale(scale: popT, child: child),
          ),
        );
      },
      child: dot,
    );
  }
}

/// 全局错误提示微胶囊 (`07-panel-reveal` + `12-error-state-shake`)
class _StudioErrorBanner extends StatefulWidget {
  final String? errorMessage;
  final VoidCallback onDismiss;

  const _StudioErrorBanner({
    required this.errorMessage,
    required this.onDismiss,
  });

  @override
  State<_StudioErrorBanner> createState() => _StudioErrorBannerState();
}

class _StudioErrorBannerState extends State<_StudioErrorBanner> {
  String _cachedMessage = '';
  int _shakeTrigger = 0;

  @override
  void initState() {
    super.initState();
    if (widget.errorMessage != null) {
      _cachedMessage = widget.errorMessage!;
    }
  }

  @override
  void didUpdateWidget(covariant _StudioErrorBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.errorMessage;
    if (next != null && next != oldWidget.errorMessage) {
      _cachedMessage = next;
      _shakeTrigger++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final visible = widget.errorMessage != null;
    if (widget.errorMessage != null) {
      _cachedMessage = widget.errorMessage!;
    }

    return AppPanelReveal(
      visible: visible,
      openDuration: AppMotionDurations.fast,
      closeDuration: AppMotionDurations.quick,
      slideOffset: AppMotionDistances.base,
      enableBlur: false,
      child: AppErrorShake(
        trigger: _shakeTrigger,
        child: Container(
          margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: colors.errorSurface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: colors.error.withValues(alpha: 0.3),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.error_outline, size: 16, color: colors.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _cachedMessage,
                  style: TextStyle(
                    fontSize: 12,
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, size: 14, color: colors.textSecondary),
                tooltip: context.l10n.close,
                onPressed: widget.onDismiss,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 移动端 / 窄屏顶部上下文子导航栏：
///
/// - 生图页 (Page 0)：呈现 [参数 | 提示词 | 局部修复] 二级分段切换条；
/// - 画板/助手/词库：呈现当前视图图标与标题 (+ 画板页选中图像时的快捷修复动作)；
/// - 右侧常驻「设置」入口，桌面窄屏窗口额外保留窗口拖拽与三键控制。
class _MobileTopBar extends StatefulWidget {
  final int activeIndex;
  final bool isLibraryTab;
  final StudioSidebarTab activeSidebarTab;
  final bool isEditingPositions;
  final bool isEditingWatermarkPosition;
  final bool isAnnotating;
  final bool hasSelectedImage;
  final ValueChanged<StudioSidebarTab> onStudioTabSelected;
  final VoidCallback onOpenSettings;
  final VoidCallback? onReadImageMetadata;
  final VoidCallback? onQuickInpaint;

  const _MobileTopBar({
    required this.activeIndex,
    required this.isLibraryTab,
    required this.activeSidebarTab,
    required this.isEditingPositions,
    required this.isEditingWatermarkPosition,
    required this.isAnnotating,
    required this.hasSelectedImage,
    required this.onStudioTabSelected,
    required this.onOpenSettings,
    this.onReadImageMetadata,
    this.onQuickInpaint,
  });

  @override
  State<_MobileTopBar> createState() => _MobileTopBarState();
}

class _MobileTopBarState extends WindowControlsState<_MobileTopBar> {
  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final height = isDesktopWindow ? 34.0 : 42.0;
    final btnSize = isDesktopWindow ? 26.0 : 32.0;

    return SizedBox(
      key: const ValueKey('mobile_top_bar'),
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          border: Border(
            bottom: BorderSide(color: colors.borderDefault, width: 1),
          ),
        ),
        child: buildWindowDragArea(
          child: Row(
            children: [
              Expanded(child: _buildLeadingContext(context, l10n)),

              if (!widget.isLibraryTab &&
                  widget.activeIndex == 1 &&
                  !widget.isEditingPositions &&
                  !widget.isAnnotating &&
                  widget.onReadImageMetadata != null)
                AppIconButton(
                  key: const Key('mobile_topbar_read_metadata_button'),
                  icon: Icons.image_search_outlined,
                  variant: AppIconButtonVariant.ghost,
                  size: btnSize,
                  tooltip: l10n.canvasActionReadMetadata,
                  onPressed: widget.onReadImageMetadata,
                ),

              if (!widget.isLibraryTab &&
                  widget.activeIndex == 1 &&
                  !widget.isEditingPositions &&
                  !widget.isAnnotating &&
                  widget.hasSelectedImage &&
                  widget.onQuickInpaint != null)
                AppIconButton(
                  key: const Key('mobile_topbar_inpaint_button'),
                  icon: Icons.auto_fix_high_outlined,
                  variant: AppIconButtonVariant.ghost,
                  size: btnSize,
                  tooltip: l10n.canvasActionSendToInpaint,
                  onPressed: widget.onQuickInpaint,
                ),

              Padding(
                padding: EdgeInsets.only(
                  right: showCustomWindowControls ? 2 : 6,
                ),
                child: AppIconButton(
                  key: const Key('mobile_nav_settings'),
                  icon: Icons.settings_outlined,
                  variant: AppIconButtonVariant.ghost,
                  size: btnSize,
                  tooltip: l10n.settings,
                  onPressed: widget.onOpenSettings,
                ),
              ),

              if (showCustomWindowControls) ...[
                AppWindowButton(
                  icon: Icons.remove,
                  iconSize: 11,
                  height: height,
                  width: 24,
                  tooltip: l10n.windowMinimize,
                  onPressed: minimizeWindow,
                ),
                AppWindowButton(
                  icon: windowIsMaximized
                      ? Icons.filter_none_rounded
                      : Icons.crop_square_rounded,
                  iconSize: windowIsMaximized ? 10 : 11,
                  height: height,
                  width: 24,
                  tooltip: windowIsMaximized
                      ? l10n.windowRestore
                      : l10n.windowMaximize,
                  onPressed: toggleMaximizeWindow,
                ),
                AppWindowButton(
                  icon: Icons.close_rounded,
                  iconSize: 12,
                  height: height,
                  width: 24,
                  tooltip: l10n.close,
                  isClose: true,
                  onPressed: closeAppWindow,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeadingContext(BuildContext context, AppLocalizations l10n) {
    final colors = context.colors;

    if (!widget.isLibraryTab && widget.activeIndex == 0) {
      return Padding(
        padding: EdgeInsets.symmetric(
          horizontal: 8,
          vertical: isDesktopWindow ? 3 : 5,
        ),
        child: AppSegmentedCardBar<StudioSidebarTab>(
          items: [
            AppSegmentedItem(
              key: const Key('mobile_nav_parameters'),
              value: StudioSidebarTab.parameters,
              icon: Icons.tune_outlined,
              label: l10n.sidebarTabParameters,
            ),
            AppSegmentedItem(
              key: const Key('mobile_nav_prompts'),
              value: StudioSidebarTab.prompts,
              icon: Icons.edit_note_outlined,
              label: l10n.tabPrompts,
            ),
            AppSegmentedItem(
              key: const Key('mobile_nav_inpaint'),
              value: StudioSidebarTab.inpaint,
              icon: Icons.auto_fix_high_outlined,
              label: l10n.sidebarTabInpaint,
            ),
          ],
          selectedValue: widget.activeSidebarTab,
          expand: true,
          spacing: 2,
          trackPadding: const EdgeInsets.all(2),
          itemPadding: EdgeInsets.symmetric(
            horizontal: 6,
            vertical: isDesktopWindow ? 1 : 3,
          ),
          fontSize: isDesktopWindow ? 11.5 : 12.5,
          iconSize: isDesktopWindow ? 13 : 14,
          highlightSelectedIcon: true,
          onValueChanged: widget.onStudioTabSelected,
        ),
      );
    }

    IconData icon;
    String title;
    String? modeBadge;
    if (widget.isLibraryTab) {
      icon = Icons.collections_bookmark_outlined;
      title = l10n.tabLibrary;
    } else if (widget.activeIndex == 1) {
      title = l10n.mobileTabCanvas;
      if (widget.isAnnotating) {
        icon = Icons.draw_rounded;
        modeBadge = l10n.canvasAnnotate;
      } else if (widget.isEditingWatermarkPosition) {
        icon = Icons.open_with_rounded;
        modeBadge = l10n.watermarkPositionTitle;
      } else if (widget.isEditingPositions) {
        icon = Icons.open_with_rounded;
        modeBadge = l10n.charPromptCanvasEdit;
      } else {
        icon = Icons.palette_outlined;
      }
    } else {
      icon = Icons.chat_bubble_outline_rounded;
      title = l10n.mobileTabChat;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colors.primary),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
              ),
            ),
          ),
          if (modeBadge != null) ...[
            const SizedBox(width: 8),
            AppBadge.pill(
              label: modeBadge,
              variant: AppBadgeVariant.primary,
              fontSize: 10,
            ),
          ],
        ],
      ),
    );
  }
}
