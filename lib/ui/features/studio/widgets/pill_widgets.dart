import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 胶囊形状小尺寸下拉框 (Quality Tags / UC Preset 预设切换复用，采用统一的精致 Notion 下拉设计，紧凑无多余空隙)
class PillDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T item) labelOf;
  final ValueChanged<T> onChanged;
  final IconData? icon;
  final IconData Function(T item)? iconOf;

  const PillDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.icon,
    this.iconOf,
  });

  IconData _resolveIcon(T item) {
    if (iconOf != null) return iconOf!(item);
    if (icon != null) return icon!;
    final str = item.toString().toLowerCase();
    if (str.contains('quality') || str.contains('standard') || str.contains('heavy') || str.contains('light')) {
      return Icons.auto_awesome_rounded;
    }
    if (str.contains('uc') || str.contains('human') || str.contains('furry') || str.contains('focus')) {
      return Icons.shield_outlined;
    }
    return Icons.tune_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final leadIcon = _resolveIcon(value);

    return PopupMenuButton<T>(
      initialValue: value,
      tooltip: '',
      onSelected: onChanged,
      color: AppTheme.pureWhite,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      constraints: const BoxConstraints(minWidth: 195, maxWidth: 300),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppTheme.border),
      ),
      itemBuilder: (context) {
        return items.map((item) {
          final isSelected = item == value;
          final itemIcon = _resolveIcon(item);

          return PopupMenuItem<T>(
            value: item,
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  itemIcon,
                  size: 15,
                  color: isSelected ? AppTheme.notionBlue : AppTheme.stone,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    labelOf(item),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                      color: isSelected ? AppTheme.notionBlue : AppTheme.textPrimary,
                    ),
                  ),
                ),
                if (isSelected) ...[
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.check_rounded,
                    size: 15,
                    color: AppTheme.notionBlue,
                  ),
                ],
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 9),
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: AppTheme.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(leadIcon, size: 13, color: AppTheme.stone),
            const SizedBox(width: 5),
            Text(
              labelOf(value),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            const SizedBox(width: 3),
            const Icon(
              Icons.arrow_drop_down_rounded,
              size: 18,
              color: AppTheme.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 胶囊切换按钮 (Transparent BG / Affixes 快捷开关复用)
class ToggleChip extends StatelessWidget {
  final bool isActive;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const ToggleChip({
    super.key,
    required this.isActive,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3.5),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.skyTint : AppTheme.surfaceMuted,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: isActive
                ? AppTheme.notionBlue.withValues(alpha: 0.5)
                : AppTheme.border,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 11.5,
              color: isActive ? AppTheme.notionBlue : AppTheme.textMuted,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: isActive ? AppTheme.notionBlue : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
