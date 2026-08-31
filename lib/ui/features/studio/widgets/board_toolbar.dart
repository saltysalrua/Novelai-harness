import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'canvas_overlays.dart';

/// 画板圈选工具类型
enum AnnotationToolMode {
  rect('圈选选区'),
  point('图钉锚点');

  final String label;
  const AnnotationToolMode(this.label);
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: canvasBadgeDecoration(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BoardToolbarItem(
            icon: Icons.pan_tool_outlined,
            label: '漫游',
            isSelected: isPanMode,
            onTap: onPanModeToggled,
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.crop_square_rounded,
            label: '圈选选区',
            isSelected: !isPanMode && toolMode == AnnotationToolMode.rect,
            onTap: () => onToolModeChanged(AnnotationToolMode.rect),
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.push_pin_outlined,
            label: '图钉锚点',
            isSelected: !isPanMode && toolMode == AnnotationToolMode.point,
            onTap: () => onToolModeChanged(AnnotationToolMode.point),
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 16, color: AppTheme.border),
          const SizedBox(width: 6),
          BoardToolbarItem(
            icon: Icons.note_add_outlined,
            label: '+ 便利贴',
            isSelected: false,
            onTap: onAddNote,
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.add_photo_alternate_outlined,
            label: '+ 参考图',
            isSelected: false,
            onTap: onImportImage,
          ),
          const SizedBox(width: 4),
          BoardToolbarItem(
            icon: Icons.content_paste_rounded,
            label: '粘贴图 (Ctrl+V)',
            isSelected: false,
            onTap: onPasteImage,
          ),
          const SizedBox(width: 6),
          Container(width: 1, height: 16, color: AppTheme.border),
          const SizedBox(width: 6),
          BoardToolbarItem(
            icon: Icons.center_focus_strong_outlined,
            label: '适应视口',
            isSelected: false,
            onTap: onResetView,
          ),
        ],
      ),
    );
  }
}

/// 工具坞单键 (选中态蓝底白字)
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
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: isSelected ? AppTheme.notionBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isSelected ? Colors.white : AppTheme.textPrimary,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? Colors.white : AppTheme.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
