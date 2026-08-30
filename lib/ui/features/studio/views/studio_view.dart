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

  @override
  void initState() {
    super.initState();
    _viewModel = StudioViewModel();
    _viewModel.init();
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, _) {
        return CallbackShortcuts(
          bindings: <ShortcutActivator, VoidCallback>{
            const SingleActivator(LogicalKeyboardKey.escape): () {
              if (_viewModel.isGenerating) {
                _viewModel.abortGeneration();
              } else if (_viewModel.isChatStreaming) {
                _viewModel.abortChat();
              }
            },
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
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
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
                        rightChild: AgentChatCard(viewModel: _viewModel),
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
