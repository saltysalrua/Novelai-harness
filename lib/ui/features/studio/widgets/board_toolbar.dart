import 'package:flutter/material.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_floating_dock.dart';
import '../../../core/widgets/app_tool_chip.dart';

/// 画板圈选工具类型
enum AnnotationToolMode {
  rect('圈选选区'),
  point('图钉锚点');

  final String label;
  const AnnotationToolMode(this.label);

  String localizedLabel(BuildContext context) {
    return switch (this) {
      AnnotationToolMode.rect => context.l10n.boardToolRect,
      AnnotationToolMode.point => context.l10n.boardToolPoint,
    };
  }
}

/// 自由大画布顶部浮动工具坞 (漫游/圈选/图钉/便利贴/参考图/粘贴/适应视口)
class BoardAnnotationToolbar extends StatelessWidget {
  final AnnotationToolMode toolMode;
  final bool isPanMode;
  final ValueChanged<AnnotationToolMode> onToolModeChanged;
  final VoidCallback onPanModeToggled;
  final VoidCallback onResetView;
  final VoidCallback onAddNote;
  final VoidCallback onImportImage;
  final VoidCallback onPasteImage;

  const BoardAnnotationToolbar({
    super.key,
    required this.toolMode,
    required this.isPanMode,
    required this.onToolModeChanged,
    required this.onPanModeToggled,
    required this.onResetView,
    required this.onAddNote,
    required this.onImportImage,
    required this.onPasteImage,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return AppFloatingDock(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoardToolbarItem(
            icon: Icons.pan_tool_outlined,
            label: l10n.boardToolPan,
            isSelected: isPanMode,
            onTap: onPanModeToggled,
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.crop_square_rounded,
            label: l10n.boardToolRect,
            isSelected: !isPanMode && toolMode == AnnotationToolMode.rect,
            onTap: () => onToolModeChanged(AnnotationToolMode.rect),
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.push_pin_outlined,
            label: l10n.boardToolPoint,
            isSelected: !isPanMode && toolMode == AnnotationToolMode.point,
            onTap: () => onToolModeChanged(AnnotationToolMode.point),
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 16, color: colors.borderDefault),
          const SizedBox(width: 6),
          BoardToolbarItem(
            icon: Icons.note_add_outlined,
            label: l10n.boardToolAddNote,
            isSelected: false,
            onTap: onAddNote,
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.add_photo_alternate_outlined,
            label: l10n.boardToolAddImage,
            isSelected: false,
            onTap: onImportImage,
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.content_paste_rounded,
            label: l10n.boardToolPasteImage,
            isSelected: false,
            onTap: onPasteImage,
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 16, color: colors.borderDefault),
          const SizedBox(width: 6),
          BoardToolbarItem(
            icon: Icons.center_focus_strong_outlined,
            label: l10n.boardToolResetView,
            isSelected: false,
            onTap: onResetView,
          ),
        ],
      ),
    );
  }
}

/// 工具坞单键 (委托至统一的 [AppToolChip] 原子组件)
class BoardToolbarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const BoardToolbarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppToolChip(
      icon: icon,
      label: label,
      isSelected: isSelected,
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      fontSize: 12,
    );
  }
}
