import 'package:flutter/material.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../settings/views/settings_dialog.dart';
import '../view_models/studio_view_model.dart';
import 'studio_shared.dart';

class StudioSidebar extends StatelessWidget {
  final StudioViewModel viewModel;
  final StudioSidebarTab activeTab;
  final ValueChanged<StudioSidebarTab> onTabChanged;
  final bool connectedToCard;
  final VoidCallback? onToggleCollapse;

  const StudioSidebar({
    super.key,
    required this.viewModel,
    required this.activeTab,
    required this.onTabChanged,
    this.connectedToCard = false,
    this.onToggleCollapse,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return IntrinsicWidth(
      child: Container(
        constraints: const BoxConstraints(minWidth: 62),
        margin: const EdgeInsets.fromLTRB(8, 8, 0, 8),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        clipBehavior: Clip.antiAlias,
        decoration: ShapeDecoration(
          color: colors.cardBackground,
          shape: StudioPanelShapeBorder(
            outerSide: BorderSide(color: colors.borderDefault),
            rightDividerSide: connectedToCard
                ? BorderSide(color: colors.borderSubtle)
                : null,
            radius: AppRadius.lg,
            roundLeft: true,
            roundRight: !connectedToCard,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 导航分类项：参数
            _buildNavItem(
              icon: Icons.tune_outlined,
              label: l10n.sidebarTabParameters,
              tooltip: l10n.sidebarTabParameters,
              isSelected: activeTab == StudioSidebarTab.parameters,
              isTab: true,
              onTap: () => onTabChanged(StudioSidebarTab.parameters),
            ),
            const SizedBox(height: 4),

            // 导航分类项：提示词
            _buildNavItem(
              icon: Icons.edit_note_outlined,
              label: l10n.tabPrompts,
              tooltip: l10n.tabPrompts,
              isSelected: activeTab == StudioSidebarTab.prompts,
              isTab: true,
              onTap: () => onTabChanged(StudioSidebarTab.prompts),
            ),
            const SizedBox(height: 4),

            // 导航分类项：修复
            _buildNavItem(
              icon: Icons.auto_fix_high_outlined,
              label: l10n.sidebarTabInpaint,
              tooltip: l10n.sidebarTabInpaint,
              isSelected: activeTab == StudioSidebarTab.inpaint,
              isTab: true,
              onTap: () => onTabChanged(StudioSidebarTab.inpaint),
            ),
            const SizedBox(height: 4),

            // 导航分类项：词库 (覆盖三栏的沉浸式管理)
            _buildNavItem(
              icon: Icons.collections_bookmark_outlined,
              label: l10n.tabLibrary,
              tooltip: l10n.tabLibrary,
              isSelected: activeTab == StudioSidebarTab.library,
              isTab: true,
              onTap: () => onTabChanged(StudioSidebarTab.library),
            ),

            const Spacer(),

            Divider(height: 1, color: colors.borderSubtle),
            const SizedBox(height: 6),

            if (onToggleCollapse != null) ...[
              _buildNavItem(
                key: const Key('sidebar_collapse_button'),
                icon: Icons.keyboard_double_arrow_left_rounded,
                label: l10n.sidebarCollapse,
                tooltip: l10n.sidebarCollapseTooltip,
                isSelected: false,
                onTap: onToggleCollapse!,
              ),
              const SizedBox(height: 2),
            ],

            // 底部全局设置按钮 (弹窗形式打开)
            _buildNavItem(
              icon: Icons.settings_outlined,
              label: l10n.settings,
              tooltip: l10n.sidebarSettingsTooltip,
              isSelected: false,
              onTap: () => SettingsDialog.show(context, viewModel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavItem({
    Key? key,
    required IconData icon,
    required String label,
    required String tooltip,
    required bool isSelected,
    bool isTab = false,
    required VoidCallback onTap,
  }) {
    return Semantics(
      container: true,
      button: true,
      selected: isTab ? isSelected : null,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: AppNavTile(
          key: key,
          axis: Axis.vertical,
          icon: icon,
          title: label,
          isSelected: isSelected,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          onTap: onTap,
        ),
      ),
    );
  }
}
