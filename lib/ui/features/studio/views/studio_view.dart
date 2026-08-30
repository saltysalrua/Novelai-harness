import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/custom_title_bar.dart';
import '../../../core/widgets/resizable_split_view.dart';
import '../view_models/studio_view_model.dart';
import '../widgets/agent_chat_card.dart';
import '../widgets/image_canvas_card.dart';
import '../widgets/parameter_card.dart';
import '../widgets/studio_sidebar.dart';

class StudioView extends StatefulWidget {
  const StudioView({super.key});

  @override
  State<StudioView> createState() => _StudioViewState();
}

class _StudioViewState extends State<StudioView> {
  late final StudioViewModel _viewModel;
  StudioSidebarTab _activeTab = StudioSidebarTab.parameters;

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
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): _handleGlobalEsc,
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

                  // 主体区域：最左侧导航栏 + 主三栏自适应可拖拽工作台
                  Expanded(
                    child: Row(
                      children: [
                        // 1. 最左侧 Notion 极简侧边栏
                        StudioSidebar(
                          viewModel: _viewModel,
                          activeTab: _activeTab,
                          onTabChanged: (tab) {
                            // 双页常驻挂载，切页时释放焦点，避免按键落入隐藏页面的输入框
                            FocusManager.instance.primaryFocus?.unfocus();
                            setState(() {
                              _activeTab = tab;
                            });
                          },
                        ),

                        // 2. 主三栏工作台
                        Expanded(
                          child: ResizableThreeSplitView(
                            initialLeftWidth: 320,
                            initialRightWidth: 400,
                            leftChild: ParameterCard(
                              viewModel: _viewModel,
                              activeTab: _activeTab,
                            ),
                            centerChild: ImageCanvasCard(viewModel: _viewModel),
                            rightChild: AgentChatCard(
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
