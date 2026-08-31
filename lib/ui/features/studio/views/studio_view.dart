import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_title_bar.dart';
import '../../../core/widgets/resizable_split_view.dart';
import '../view_models/studio_view_model.dart';
import '../widgets/agent_chat_card.dart';
import '../widgets/annotation_history_strip.dart';
import '../widgets/image_canvas_card.dart';
import '../widgets/parameter_card.dart';
import '../widgets/prompt_library_view.dart';
import '../widgets/studio_sidebar.dart';

class StudioView extends StatefulWidget {
  const StudioView({super.key});

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

  @override
  void initState() {
    super.initState();
    _viewModel = StudioViewModel();
    _viewModel.init();
    HardwareKeyboard.instance.addHandler(_handleGlobalKeyEvents);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleGlobalKeyEvents);
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

    // 当处于批注模式时：
    if (_viewModel.isAnnotatingImage) {
      if (_isTypingText()) return false;
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        if (event is KeyDownEvent) {
          _viewModel.setAnnotatingImage(false);
        }
        return true;
      }
    }

    // 当处于角色位置编辑模式时：
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

    return false;
  }

  /// 根级 ESC：双击 400ms 内进入回溯视图；单击中断生成/流式
  ///
  /// 焦点在对话卡内时由卡片自身的 onKeyEvent 先行处理 (handled)，不会走到这里；
  /// 这里兜底的是焦点落在左侧面板或根部无焦点区域的场景。
  void _handleGlobalEsc() {
    final now = DateTime.now();
    final isDoublePress =
        _lastRootEscTime != null &&
        now.difference(_lastRootEscTime!) <= const Duration(milliseconds: 400);
    _lastRootEscTime = now;

    if (isDoublePress) {
      if (_viewModel.isChatStreaming) {
        _viewModel.abortChat();
      }
      _chatCardKey.currentState?.openRewindView();
      return;
    }

    if (_viewModel.activeSidebarTab == StudioSidebarTab.library) {
      _viewModel.setActiveSidebarTab(_previousSidebarTab);
      return;
    }

    if (_viewModel.isAnnotatingImage) {
      _viewModel.setAnnotatingImage(false);
      return;
    }

    if (_viewModel.isEditingCharacterPositions) {
      _viewModel.setEditingCharacterPositions(false);
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
            // Ctrl+O: 全局展开/折叠对话思考块 (与 Pi TUI 习惯一致)
            const SingleActivator(LogicalKeyboardKey.keyO, control: true): () =>
                _viewModel.toggleThinkingExpanded(),
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: AppTheme.background,
              body: Column(
                children: [
                  // 顶部自定义 Notion 风格标题栏 (支持窗口拖拽与三键控制)
                  const CustomTitleBar(),

                  // 全局错误提示微胶囊
                  if (_viewModel.errorMessage != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDEEED),
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusButton,
                        ),
                        border: Border.all(
                          color: AppTheme.coral.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 16,
                            color: AppTheme.coral,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _viewModel.errorMessage!,
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.charcoal,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 14,
                              color: AppTheme.graphite,
                            ),
                            onPressed: () => _viewModel.clearError(),
                            visualDensity: VisualDensity.compact,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                          ),
                        ],
                      ),
                    ),

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
                                _viewModel.activeSidebarTab !=
                                    StudioSidebarTab.library) {
                              _previousSidebarTab = _viewModel.activeSidebarTab;
                            }
                            _viewModel.setActiveSidebarTab(tab);
                          },
                        ),

                        // 2. 主区域：全屏词库视图 (覆盖所有三栏) 或 主三栏自适应工作台
                        Expanded(
                          child: isLibraryTab
                              ? PromptLibraryView(
                                  viewModel: _viewModel,
                                  onClose: () {
                                    _viewModel.setActiveSidebarTab(
                                      _previousSidebarTab,
                                    );
                                  },
                                )
                              : ResizableThreeSplitView(
                                  key: ValueKey('split-${_viewModel.isAnnotatingImage}'),
                                  initialLeftWidth: _viewModel.splitLeftWidth,
                                  initialRightWidth: _viewModel.isAnnotatingImage
                                      ? 110.0
                                      : _viewModel.splitRightWidth,
                                  minRightWidth:
                                      _viewModel.isAnnotatingImage ? 90.0 : 280.0,
                                  maxRightWidth:
                                      _viewModel.isAnnotatingImage ? 160.0 : 560.0,
                                  onWidthsChanged: (left, right) {
                                    if (!_viewModel.isAnnotatingImage) {
                                      _viewModel.updateSplitWidths(left, right);
                                    }
                                  },
                                  leftChild: ParameterCard(
                                    viewModel: _viewModel,
                                    activeTab: _viewModel.activeSidebarTab,
                                  ),
                                  centerChild: ImageCanvasCard(
                                    viewModel: _viewModel,
                                  ),
                                  rightChild: _viewModel.isAnnotatingImage
                                      ? AnnotationHistoryStrip(
                                          viewModel: _viewModel,
                                        )
                                      : AgentChatCard(
                                          key: _chatCardKey,
                                          viewModel: _viewModel,
                                        ),
                                ),
                        ),
                      ],
                    ),
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
