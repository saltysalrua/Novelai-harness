import 'package:flutter/material.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../settings/views/settings_dialog.dart';
import '../view_models/studio_view_model.dart';
import 'notification_center_popover.dart';
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
            // 顶部收起按钮 (与收起后画板左上角展开按钮位置对齐)
            if (onToggleCollapse != null) ...[
              _buildNavItem(
                key: const Key('sidebar_collapse_button'),
                icon: Icons.keyboard_double_arrow_left_rounded,
                label: l10n.sidebarCollapse,
                tooltip: l10n.sidebarCollapseTooltip,
                isSelected: false,
                onTap: onToggleCollapse!,
              ),
              const SizedBox(height: 6),
              Divider(height: 1, color: colors.borderSubtle),
              const SizedBox(height: 6),
            ],

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

            // 导航分类项：精准参考
            _buildNavItem(
              key: const Key('sidebar_tab_reference'),
              icon: Icons.style_outlined,
              label: l10n.sidebarTabReference,
              tooltip: l10n.tabReference,
              isSelected: activeTab == StudioSidebarTab.reference,
              isTab: true,
              showBadgeDot:
                  !viewModel.isComfyUiMode &&
                  viewModel.hasActiveReferenceGuide,
              onTap: () => onTabChanged(StudioSidebarTab.reference),
            ),
            const SizedBox(height: 4),

            // 导航分类项：修复
            _buildNavItem(
              icon: Icons.auto_fix_high_outlined,
              label: l10n.sidebarTabInpaint,
              tooltip: l10n.sidebarTabInpaint,
              isSelected: activeTab == StudioSidebarTab.inpaint,
              isTab: true,
              showBadgeDot:
                  viewModel.isExecutingInpaint || viewModel.isExecutingAiEdit,
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

            // 通知与错误记录浮窗入口
            Builder(
              builder: (buttonContext) => _buildNavItem(
                key: const Key('sidebar_notifications_button'),
                icon: Icons.notifications_none_rounded,
                label: l10n.notifications,
                tooltip: l10n.notificationsTooltip,
                isSelected: false,
                showBadgeDot: viewModel.unreadNotificationCount > 0,
                badgeColor: colors.error,
                onTap: () => NotificationCenterPopover.show(
                  buttonContext,
                  viewModel: viewModel,
                  preferAbove: true,
                ),
              ),
            ),
            const SizedBox(height: 4),

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
    bool showBadgeDot = false,
    Color? badgeColor,
    required VoidCallback onTap,
  }) {
    final navTile = AppNavTile(
      key: key,
      axis: Axis.vertical,
      icon: icon,
      title: label,
      isSelected: isSelected,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      onTap: onTap,
    );

    return Semantics(
      container: true,
      button: true,
      selected: isTab ? isSelected : null,
      child: Tooltip(
        message: tooltip,
        excludeFromSemantics: true,
        child: Stack(
          clipBehavior: Clip.none,
          fit: StackFit.passthrough,
          children: [
            navTile,
            if (showBadgeDot)
              Positioned(
                top: 6,
                right: 8,
                child: IgnorePointer(
                  child: ExcludeSemantics(
                    child: _SidebarBadgeDot(color: badgeColor),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 侧栏导航状态点 (`03-notification-badge`)
class _SidebarBadgeDot extends StatefulWidget {
  final Color? color;

  const _SidebarBadgeDot({this.color});

  @override
  State<_SidebarBadgeDot> createState() => _SidebarBadgeDotState();
}

class _SidebarBadgeDotState extends State<_SidebarBadgeDot>
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
        color: widget.color ?? colors.primary,
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
