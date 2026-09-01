import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../settings/views/settings_dialog.dart';
import '../view_models/studio_view_model.dart';

class StudioSidebar extends StatelessWidget {
  final StudioViewModel viewModel;
  final StudioSidebarTab activeTab;
  final ValueChanged<StudioSidebarTab> onTabChanged;

  const StudioSidebar({
    super.key,
    required this.viewModel,
    required this.activeTab,
    required this.onTabChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      margin: const EdgeInsets.fromLTRB(8, 8, 0, 8),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          const SizedBox(height: 8),

          // 导航分类项：参数
          _buildTabItem(
            tab: StudioSidebarTab.parameters,
            icon: Icons.tune_outlined,
            label: '参数',
            isSelected: activeTab == StudioSidebarTab.parameters,
          ),
          const SizedBox(height: 6),

          // 导航分类项：提示词
          _buildTabItem(
            tab: StudioSidebarTab.prompts,
            icon: Icons.edit_note_outlined,
            label: '提示词',
            isSelected: activeTab == StudioSidebarTab.prompts,
          ),
          const SizedBox(height: 6),

          // 导航分类项：修复
          _buildTabItem(
            tab: StudioSidebarTab.inpaint,
            icon: Icons.auto_fix_high_outlined,
            label: '修复',
            isSelected: activeTab == StudioSidebarTab.inpaint,
          ),
          const SizedBox(height: 6),

          // 导航分类项：词库 (覆盖三栏的沉浸式管理)
          _buildTabItem(
            tab: StudioSidebarTab.library,
            icon: Icons.collections_bookmark_outlined,
            label: '词库',
            isSelected: activeTab == StudioSidebarTab.library,
          ),

          const Spacer(),

          // 底部全局设置按钮 (弹窗形式打开)
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 8),
          _buildActionItem(
            icon: Icons.settings_outlined,
            label: '设置',
            tooltip: '全局配置 (API Key / 存储 / LLM)',
            onTap: () => SettingsDialog.show(context, viewModel),
          ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }

  Widget _buildTabItem({
    required StudioSidebarTab tab,
    required IconData icon,
    required String label,
    required bool isSelected,
  }) {
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: () => onTabChanged(tab),
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.skyTint : Colors.transparent,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            border: Border.all(
              color: isSelected
                  ? AppTheme.notionBlue.withValues(alpha: 0.4)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? AppTheme.notionBlue : AppTheme.graphite,
              ),
              const SizedBox(height: 3),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected ? AppTheme.notionBlue : AppTheme.graphite,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionItem({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        child: Container(
          width: 44,
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 20, color: AppTheme.graphite),
              const SizedBox(height: 3),
              Text(
                label,
                style: const TextStyle(fontSize: 10, color: AppTheme.graphite),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
