import 'package:flutter/material.dart';
import '../view_models/studio_view_model.dart';
import 'generate_dock.dart';
import 'parameters_page.dart';
import 'prompts_page.dart';
import 'studio_sidebar.dart';

/// 左侧工作台面板：双页面 (参数设置 / 提示词管理) + 底部生成操作坞。
/// 双页常驻挂载，切换侧边栏 Tab 时保留各自的输入光标与滚动位置。
class ParameterCard extends StatelessWidget {
  final StudioViewModel viewModel;
  final StudioSidebarTab activeTab;

  const ParameterCard({
    super.key,
    required this.viewModel,
    this.activeTab = StudioSidebarTab.parameters,
  });

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 页面主体 (根据侧边栏 Tab 切换)
            Expanded(
              child: IndexedStack(
                index: activeTab == StudioSidebarTab.parameters ? 0 : 1,
                children: [
                  ParametersPage(viewModel: viewModel),
                  PromptsPage(viewModel: viewModel),
                ],
              ),
            ),

            // 底部常驻操作面板 (账号/体力/免点/刷新 + 生成图片)
            GenerateDock(viewModel: viewModel),
          ],
        ),
      ),
    );
  }
}
