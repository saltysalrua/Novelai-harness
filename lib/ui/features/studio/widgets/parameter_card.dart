import 'package:flutter/material.dart';
import '../view_models/studio_view_model.dart';
import 'generate_dock.dart';
import 'inpaint_page.dart';
import 'parameters_page.dart';
import 'prompts_page.dart';

/// 左侧工作台面板：三页面 (参数设置 / 提示词管理 / 修复设置) + 底部生成操作坞。
/// 各页常驻挂载，切换侧边栏 Tab 时保留各自的输入光标与滚动位置。
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
    final pages = [
      ParametersPage(viewModel: viewModel),
      PromptsPage(viewModel: viewModel),
      InpaintPage(viewModel: viewModel),
    ];
    final pageIndex = switch (activeTab) {
      StudioSidebarTab.parameters => 0,
      StudioSidebarTab.prompts => 1,
      StudioSidebarTab.inpaint => 2,
      StudioSidebarTab.library => 0,
    };

    return ExcludeSemantics(
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 页面主体 (根据侧边栏 Tab 切换)
            Expanded(
              child: IndexedStack(
                index: pageIndex,
                children: [
                  // 隐藏页保留编辑状态，但不继续播放动画；页面之间隔离重绘。
                  for (var index = 0; index < pages.length; index++)
                    TickerMode(
                      enabled: index == pageIndex,
                      child: RepaintBoundary(child: pages[index]),
                    ),
                ],
              ),
            ),

            // 底部常驻操作面板 (账号/体力/免点/刷新 + 主操作按钮：生成图片/开始修复)
            GenerateDock(viewModel: viewModel),
          ],
        ),
      ),
    );
  }
}
