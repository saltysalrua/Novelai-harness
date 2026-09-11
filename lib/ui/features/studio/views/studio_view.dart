import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../../data/services/window_state_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/theme/ui_zoom_controller.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../../core/widgets/app_segmented_controls.dart';
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

  /// 对话卡是否处于覆盖视图 (会话抽屉 / 历史回溯)：
  /// 该状态在卡片内部，靠 [AgentChatCard.onOverlayViewChanged] 回写到宿主，
  /// 以便系统返回键的 canPop 判态能跟上变化。
  bool _chatOverlayView = false;

  /// 根级 ESC 首按时刻 (双击窗口判定)
  DateTime? _lastRootEscTime;

  /// 手机/窄屏模式三卡片水平滑动控制器
  late final PageController _mobilePageController;
  int _mobilePageIndex = 0;

  @override
  void initState() {
    super.initState();
    _viewModel = StudioViewModel();
    _viewModel.init();
    _mobilePageController = PageController(initialPage: 0);
    WindowStateService.instance.beforeClose = _viewModel.flushPendingSaves;
    StudioView.testViewModelHook = _viewModel;
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvents);
  }

  @override
  void dispose() {
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
      _viewModel.setActiveSidebarTab(_previousSidebarTab);
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
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
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
                // 系统返回键 (Android 手势/物理键) 先在层内消费，无可消费层时交还系统。
                // canPop 由判态驱动：无层内动作时保持 true，交由系统正常退出/回桌面。
                return PopScope(
                  canPop: !_hasSystemBackAction(isNarrow: isNarrow),
                  onPopInvokedWithResult: (didPop, _) {
                    if (didPop) return;
                    _handleSystemBack(isNarrow: isNarrow);
                  },
                  child: Scaffold(
                    backgroundColor: context.colors.canvasBackground,
                    body: isNarrow
                        ? _buildNarrowLayout(
                            context,
                            isLibraryTab: isLibraryTab,
                          )
                        : _buildWideLayout(context, isLibraryTab: isLibraryTab),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  /// 桌面端 / 宽屏 (宽度 >= [StudioView.wideLayoutMinWidth])：保持经典三栏自适应工作台与无边框拖拽标题栏
  Widget _buildWideLayout(BuildContext context, {required bool isLibraryTab}) {
    return Column(
      children: [
        // 顶部自定义 Notion 风格标题栏 (支持窗口拖拽与三键控制)
        const CustomTitleBar(),

        // 全局错误提示微胶囊
        if (_viewModel.errorMessage != null) _buildErrorMessage(context),

        // 主体区域：最左侧导航栏 + 主工作台/全屏词库覆盖视图
        Expanded(
          child: Row(
            children: [
              // 1. 最左侧 Notion 极简侧边栏
              StudioSidebar(
                viewModel: _viewModel,
                activeTab: _viewModel.activeSidebarTab,
                onTabChanged: (tab) {
                  FocusManager.instance.primaryFocus?.unfocus();
                  if (tab == StudioSidebarTab.library &&
                      _viewModel.activeSidebarTab != StudioSidebarTab.library) {
                    _previousSidebarTab = _viewModel.activeSidebarTab;
                  }
                  _viewModel.setActiveSidebarTab(tab);
                },
              ),

              // 2. 主区域：全屏词库视图 (覆盖所有三栏) 或 主三栏自适应工作台
              Expanded(
                child: AppPageStack(
                  index: isLibraryTab ? 1 : 0,
                  itemCount: 2,
                  itemBuilder: (context, index) => index == 1
                      ? PromptLibraryView(
                          viewModel: _viewModel,
                          onClose: () {
                            _viewModel.setActiveSidebarTab(_previousSidebarTab);
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
                          onWidthsChanged: (left, right) {
                            if (!_viewModel.board.isAnnotatingImage) {
                              _viewModel.updateSplitWidths(left, right);
                            }
                          },
                          leftChild: ParameterCard(
                            viewModel: _viewModel,
                            activeTab: _viewModel.activeSidebarTab,
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

  /// 移动端 / 窄屏 (宽度 < [StudioView.wideLayoutMinWidth])：
  /// 1. 移动端顶部无底色文字页签，桌面保留窗口内的紧凑胶囊拖拽条；
  /// 2. 中间三卡片采用 PageView 组织，一次展示一片，支持水平手势横滑翻页；
  /// 3. 底部沉浸式导航栏 100% 完整继承左侧侧边栏 5 项功能 (参数、提示词、修复、词库、设置)；
  /// 4. 词库以覆盖层形式叠在工作台上并保活 (AppPageStack)，不卸载三卡片 PageView，
  ///    保证胶囊高亮与当前卡片状态永不脱节；
  /// 5. UI 缩放完全由根级 [AppUiZoomController] 单一事实源控制，窄屏不再叠加第二层缩放。
  Widget _buildNarrowLayout(
    BuildContext context, {
    required bool isLibraryTab,
  }) {
    return SafeArea(
      top: true,
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部统一导航 (卡片指示/切换 + 桌面拖拽控制)
          _MobileTopBar(
            activeIndex: _mobilePageIndex,
            isChatStreaming: _viewModel.isChatStreaming,
            onPageSelected: (index) {
              if (isLibraryTab) {
                _viewModel.setActiveSidebarTab(_previousSidebarTab);
              }
              _setMobilePage(index);
            },
          ),

          // 全局错误提示微胶囊 (直接置于顶部栏正下方)
          if (_viewModel.errorMessage != null) _buildErrorMessage(context),

          // 中间核心区域：三卡片 PageView 始终保活，词库以覆盖层形式叠在其上。
          // 关键：用 Visibility(maintainSize) 隐藏而非卸载 —— 卸载或 Offstage 会把
          // PageView 视口压成 0 尺寸，导致 PageController 位置被重置，
          // 出现「页面回到第 0 页但胶囊仍高亮旧卡片」的状态脱节。
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
                    physics:
                        (_viewModel.board.isAnnotatingImage ||
                            (_viewModel.activeSidebarTab ==
                                    StudioSidebarTab.inpaint &&
                                _mobilePageIndex == 1))
                        ? const NeverScrollableScrollPhysics()
                        : const PageScrollPhysics(),
                    onPageChanged: _onMobilePageChanged,
                    children: [
                      // Page 0: 生图/工作台面板 (参数 / 提示词 / 修复配置 + 底部生成坞)
                      ParameterCard(
                        compact: true,
                        viewModel: _viewModel,
                        activeTab: _viewModel.activeSidebarTab,
                      ),
                      // Page 1: 画布面板
                      ImageCanvasCard(viewModel: _viewModel),
                      // Page 2: AI 助手面板 (批注模式时显示批注历史)
                      _viewModel.board.isAnnotatingImage
                          ? AnnotationHistoryStrip(viewModel: _viewModel)
                          : AgentChatCard(
                              key: _chatCardKey,
                              compact: true,
                              viewModel: _viewModel,
                              onEscape: _handleGlobalEsc,
                              onOverlayViewChanged: _onChatOverlayViewChanged,
                            ),
                    ],
                  ),
                ),
                if (isLibraryTab)
                  PromptLibraryView(
                    viewModel: _viewModel,
                    onClose: () {
                      _viewModel.setActiveSidebarTab(_previousSidebarTab);
                    },
                  ),
              ],
            ),
          ),

          // 底部沉浸式导航栏 (完整承接原左侧 5 个核心功能：参数、提示词、修复、词库、设置)
          // 软键盘展开时让出底部快捷栏占用，不挤压输入与消息区。
          if (MediaQuery.viewInsetsOf(context).bottom == 0)
            _buildMobileBottomBar(context, isLibraryTab: isLibraryTab),
        ],
      ),
    );
  }

  /// 窄屏三卡片切换单一入口：先落状态再动画，保证胶囊高亮与当前页面永不脱节。
  ///
  /// 顶部胶囊与底部导航栏的点击、手势横滑全部经此入口；
  /// 不依赖 PageView 的 `onPageChanged` 回调 (它在重新挂载时不会触发)。
  void _setMobilePage(int index, {bool animate = true}) {
    if (index < 0 || index > 2) return;
    if (_mobilePageIndex != index) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _mobilePageIndex = index);
    }
    if (!animate || !_mobilePageController.hasClients) return;
    final current = _mobilePageController.page?.round();
    if (current == index) return;
    _mobilePageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  /// 手势横滑翻页后的状态回写 (唯一由 PageView 反向同步索引的入口)
  void _onMobilePageChanged(int index) {
    if (_mobilePageIndex != index) {
      FocusManager.instance.primaryFocus?.unfocus();
      setState(() => _mobilePageIndex = index);
    }
  }

  /// 切换底部导航页签并回到工作台卡片
  void _selectSidebarTabFromBottomBar(StudioSidebarTab tab) {
    _viewModel.setActiveSidebarTab(tab);
    _setMobilePage(0);
  }

  /// 对话卡覆盖视图开合回写 (刷新系统返回键判态)
  void _onChatOverlayViewChanged() {
    final hasOverlay = _chatCardKey.currentState?.hasOverlayView ?? false;
    if (_chatOverlayView != hasOverlay) {
      setState(() => _chatOverlayView = hasOverlay);
    }
  }

  /// 系统返回键是否存在可消费的层内动作 (与 [_handleSystemBack] 分支顺序严格一致)
  bool _hasSystemBackAction({required bool isNarrow}) {
    if (_viewModel.activeSidebarTab == StudioSidebarTab.library) return true;
    if (_chatOverlayView) return true;
    if (_viewModel.board.isAnnotatingImage) return true;
    if (_viewModel.isEditingCharacterPositions) return true;
    if (_viewModel.isEditingWatermarkPosition) return true;
    if (isNarrow && _mobilePageIndex != 0) return true;
    return false;
  }

  /// 系统返回键 (Android 物理键/侧滑手势) 单一处理入口：
  /// 词库覆盖层 → 对话卡覆盖视图 → 批注/定位编辑模式 → 窄屏三卡片回到第 0 卡片；
  /// 以上均无命中时不动手，由 [PopScope] 的 canPop 交还系统。
  void _handleSystemBack({required bool isNarrow}) {
    if (_viewModel.activeSidebarTab == StudioSidebarTab.library) {
      _viewModel.setActiveSidebarTab(_previousSidebarTab);
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
    if (isNarrow && _mobilePageIndex != 0) {
      _setMobilePage(0);
    }
  }

  /// 全局错误提示微胶囊
  Widget _buildErrorMessage(BuildContext context) {
    final colors = context.colors;
    return Container(
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
              _viewModel.errorMessage!,
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
            onPressed: () => _viewModel.clearError(),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// 移动端沉浸式底部导航栏 (纯粹承接原左侧 5 项功能：参数、提示词、修复、词库、设置)
  Widget _buildMobileBottomBar(
    BuildContext context, {
    required bool isLibraryTab,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;

    final isPage0 = !isLibraryTab && _mobilePageIndex == 0;
    final isParamsSelected =
        isPage0 && _viewModel.activeSidebarTab == StudioSidebarTab.parameters;
    final isPromptsSelected =
        isPage0 && _viewModel.activeSidebarTab == StudioSidebarTab.prompts;
    final isInpaintSelected =
        isPage0 && _viewModel.activeSidebarTab == StudioSidebarTab.inpaint;

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(top: BorderSide(color: colors.borderDefault, width: 1)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 2, 4, 0),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                // 1. 参数设置
                _buildBottomBarItem(
                  context,
                  key: const Key('mobile_nav_parameters'),
                  icon: Icons.tune_outlined,
                  label: l10n.sidebarTabParameters,
                  isSelected: isParamsSelected,
                  onTap: () => _selectSidebarTabFromBottomBar(
                    StudioSidebarTab.parameters,
                  ),
                ),

                // 2. 提示词管理
                _buildBottomBarItem(
                  context,
                  key: const Key('mobile_nav_prompts'),
                  icon: Icons.edit_note_outlined,
                  label: l10n.tabPrompts,
                  isSelected: isPromptsSelected,
                  onTap: () =>
                      _selectSidebarTabFromBottomBar(StudioSidebarTab.prompts),
                ),

                // 3. 局部修复
                _buildBottomBarItem(
                  context,
                  key: const Key('mobile_nav_inpaint'),
                  icon: Icons.auto_fix_high_outlined,
                  label: l10n.sidebarTabInpaint,
                  isSelected: isInpaintSelected,
                  onTap: () =>
                      _selectSidebarTabFromBottomBar(StudioSidebarTab.inpaint),
                ),

                // 4. 词库
                _buildBottomBarItem(
                  context,
                  key: const Key('mobile_nav_library'),
                  icon: Icons.collections_bookmark_outlined,
                  label: l10n.tabLibrary,
                  isSelected: isLibraryTab,
                  onTap: () {
                    if (!isLibraryTab) {
                      _previousSidebarTab = _viewModel.activeSidebarTab;
                      _viewModel.setActiveSidebarTab(StudioSidebarTab.library);
                    } else {
                      // 关闭词库回到进入前的侧栏页签，并保留当前卡片 (不强制跳回第 0 页)
                      _viewModel.setActiveSidebarTab(_previousSidebarTab);
                    }
                  },
                ),

                // 5. 设置
                _buildBottomBarItem(
                  context,
                  key: const Key('mobile_nav_settings'),
                  icon: Icons.settings_outlined,
                  label: l10n.settings,
                  isSelected: false,
                  onTap: () => SettingsDialog.show(context, _viewModel),
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
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: AppNavTile(
        key: key,
        title: label,
        icon: icon,
        isSelected: isSelected,
        onTap: onTap,
        axis: Axis.vertical,
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
      ),
    );
  }
}

/// 移动端 / 窄屏三卡片导航：复用统一分段控件，移动端使用无框文字页签
///
/// - 中间：三卡片分段胶囊指示器 [生图] [画板] [助手]，平滑跟随与点击切页；
///   可用宽度不足时自动退化为图标胶囊 (带 Tooltip)，彻底避免窄屏溢出；
/// - 桌面端 (Windows/macOS/Linux)：背景支持拖拽窗口移动与双击最大化，右侧提供最小化与关闭按键；
/// - 移动端 (Android/iOS)：不渲染胶囊外框和装饰图标，仅保留文字与选中下划线，
///   整体高度对齐桌面标题栏 (32)，不占用竖屏空间。
class _MobileTopBar extends StatefulWidget {
  final int activeIndex;
  final ValueChanged<int> onPageSelected;
  final bool isChatStreaming;

  const _MobileTopBar({
    required this.activeIndex,
    required this.onPageSelected,
    this.isChatStreaming = false,
  });

  @override
  State<_MobileTopBar> createState() => _MobileTopBarState();
}

class _MobileTopBarState extends WindowControlsState<_MobileTopBar> {
  static const double _windowControlsWidth = 3 * 24.0;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return SizedBox(
      key: const ValueKey('mobile_top_bar'),
      height: 32.0,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.cardBackground,
          border: Border(
            bottom: BorderSide(color: colors.borderDefault, width: 1),
          ),
        ),
        child: buildWindowDragArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // 可用宽度不足时退化为图标胶囊 (Tooltip 补足语义)，避免窄屏 / 大缩放溢出
              final reserved = isDesktopWindow ? _windowControlsWidth : 0.0;
              final compact = constraints.maxWidth - reserved < 280;

              return Row(
                children: [
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 440),
                          child: AppSegmentedPillBar<int>(
                            items: [
                              AppSegmentedItem(
                                value: 0,
                                label: compact && isDesktopWindow
                                    ? ''
                                    : l10n.mobileTabStudio,
                                tooltip: l10n.mobileTabStudio,
                                icon: isDesktopWindow
                                    ? Icons.auto_awesome_rounded
                                    : null,
                              ),
                              AppSegmentedItem(
                                value: 1,
                                label: compact && isDesktopWindow
                                    ? ''
                                    : l10n.mobileTabCanvas,
                                tooltip: l10n.mobileTabCanvas,
                                icon: isDesktopWindow
                                    ? Icons.palette_outlined
                                    : null,
                              ),
                              AppSegmentedItem(
                                value: 2,
                                label: compact && isDesktopWindow
                                    ? ''
                                    : l10n.mobileTabChat,
                                tooltip: l10n.mobileTabChat,
                                icon: isDesktopWindow
                                    ? Icons.chat_bubble_outline_rounded
                                    : null,
                                badge: widget.isChatStreaming,
                              ),
                            ],
                            selectedValue: widget.activeIndex,
                            onValueChanged: widget.onPageSelected,
                            variant: isDesktopWindow
                                ? AppPillVariant.soft
                                : AppPillVariant.underline,
                            expand: true,
                            radius: isDesktopWindow ? AppRadius.md : 0,
                            minHeight: isDesktopWindow ? 24 : 32,
                            itemPadding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            spacing: isDesktopWindow ? 6 : 0,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // 右侧：桌面端显示窗口控制三键，移动端不占位
                  if (isDesktopWindow) ...[
                    AppWindowButton(
                      icon: Icons.remove,
                      iconSize: 11,
                      height: 32,
                      width: 24,
                      tooltip: '最小化',
                      onPressed: minimizeWindow,
                    ),
                    AppWindowButton(
                      icon: windowIsMaximized
                          ? Icons.filter_none_rounded
                          : Icons.crop_square_rounded,
                      iconSize: windowIsMaximized ? 10 : 11,
                      height: 32,
                      width: 24,
                      tooltip: windowIsMaximized ? '向下还原' : '最大化',
                      onPressed: toggleMaximizeWindow,
                    ),
                    AppWindowButton(
                      icon: Icons.close_rounded,
                      iconSize: 12,
                      height: 32,
                      width: 24,
                      tooltip: '关闭',
                      isClose: true,
                      onPressed: closeAppWindow,
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
