import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/resizable_split_view.dart';
import '../../settings/views/settings_dialog.dart';
import '../view_models/studio_view_model.dart';
import '../widgets/agent_chat_card.dart';
import '../widgets/image_canvas_card.dart';
import '../widgets/parameter_card.dart';

class StudioView extends StatefulWidget {
  const StudioView({super.key});

  @override
  State<StudioView> createState() => _StudioViewState();
}

class _StudioViewState extends State<StudioView> {
  late final StudioViewModel _viewModel;

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
        return Scaffold(
          backgroundColor: AppTheme.background,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              // 全局错误提示条
              if (_viewModel.errorMessage != null)
                Container(
                  color: AppTheme.error.withValues(alpha: 0.15),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, size: 16, color: AppTheme.error),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _viewModel.errorMessage!,
                          style: const TextStyle(fontSize: 12, color: AppTheme.error),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close, size: 14, color: AppTheme.error),
                        onPressed: () => _viewModel.clearError(),
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),

              // 主三栏自适应可拖拽区域
              Expanded(
                child: ResizableThreeSplitView(
                  initialLeftWidth: 320,
                  initialRightWidth: 400,
                  leftChild: ParameterCard(viewModel: _viewModel),
                  centerChild: ImageCanvasCard(viewModel: _viewModel),
                  rightChild: AgentChatCard(viewModel: _viewModel),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppTheme.surface,
      elevation: 0,
      titleSpacing: 16,
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppTheme.primaryDark,
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 10),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'NovelAI Harness',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                ),
              ),
              Text(
                '极简二次元插画与分镜创作工作台',
                style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
              ),
            ],
          ),
        ],
      ),
      actions: [
        // 快速刷新账号状态
        IconButton(
          icon: _viewModel.isLoadingAccount
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.refresh, size: 18),
          tooltip: '刷新账号与体力',
          onPressed: _viewModel.isLoadingAccount
              ? null
              : () => _viewModel.refreshAccountInfo(),
        ),

        // 全局设置
        IconButton(
          icon: const Icon(Icons.settings_outlined, size: 18),
          tooltip: '全局配置 (API Key / 模型 / 存储)',
          onPressed: () => SettingsDialog.show(context, _viewModel),
        ),
        const SizedBox(width: 12),
      ],
      bottom: const PreferredSize(
        preferredSize: Size.fromHeight(1),
        child: Divider(height: 1, color: AppTheme.border),
      ),
    );
  }
}
