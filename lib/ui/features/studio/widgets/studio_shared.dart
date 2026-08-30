import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';

/// 侧边栏页面标题与副标题 (参数设置 / 提示词管理页首复用)
class PageHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const PageHeader({super.key, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
        ),
      ],
    );
  }
}

/// 参数小节标题 (模型 / Seed / Sampler 等)
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }
}

/// 白底圆角下拉框 (模型 / 采样器 / 噪声调度复用，采用统一的精致 Notion 下拉设计)
class DropdownField<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T item) labelOf;
  final ValueChanged<T> onChanged;
  final double fontSize;
  final IconData? icon;
  final IconData Function(T item)? iconOf;
  final Widget Function(T item)? trailingOf;

  const DropdownField({
    super.key,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
    this.fontSize = 12.5,
    this.icon,
    this.iconOf,
    this.trailingOf,
  });

  IconData _resolveIcon(T item) {
    if (iconOf != null) return iconOf!(item);
    if (icon != null) return icon!;
    if (item is NaiModel) return Icons.auto_awesome_outlined;
    if (item is NaiSampler) return Icons.tune_rounded;
    if (item is NoiseSchedule) return Icons.waves_rounded;
    return Icons.category_outlined;
  }

  Widget? _resolveTrailing(T item, bool isSelected) {
    if (trailingOf != null) return trailingOf!(item);
    if (item is NaiModel) {
      if (item.isV5) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppTheme.skyTint,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: AppTheme.notionBlue.withValues(alpha: 0.2)),
          ),
          child: const Text(
            'V5',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.notionBlue,
            ),
          ),
        );
      }
    }
    if (isSelected) {
      return const Icon(
        Icons.check_rounded,
        size: 14,
        color: AppTheme.notionBlue,
      );
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          isDense: true,
          dropdownColor: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(8),
          menuMaxHeight: 400.0,
          icon: const Icon(
            Icons.arrow_drop_down_rounded,
            size: 20,
            color: AppTheme.textSecondary,
          ),
          selectedItemBuilder: (context) {
            return items.map((item) {
              final leadIcon = _resolveIcon(item);
              final trailing = _resolveTrailing(item, true);
              return Row(
                children: [
                  Icon(leadIcon, size: 14, color: AppTheme.stone),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      labelOf(item),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: fontSize,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 6),
                    trailing,
                  ],
                ],
              );
            }).toList();
          },
          items: items.map((item) {
            final isSelected = item == value;
            final leadIcon = _resolveIcon(item);
            final trailing = _resolveTrailing(item, isSelected);

            return DropdownMenuItem<T>(
              value: item,
              child: Tooltip(
                message: labelOf(item),
                waitDuration: const Duration(milliseconds: 500),
                child: Row(
                  children: [
                    Icon(
                      leadIcon,
                      size: 14,
                      color: isSelected ? AppTheme.notionBlue : AppTheme.stone,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        labelOf(item),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: fontSize,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                          color: isSelected ? AppTheme.notionBlue : AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    if (trailing != null) ...[
                      const SizedBox(width: 6),
                      trailing,
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
        ),
      ),
    );
  }
}

/// 轻量"清空"文字按钮 (提示词输入框右上角复用)
class ClearTextLink extends StatelessWidget {
  final VoidCallback onTap;

  const ClearTextLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          '清空',
          style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
        ),
      ),
    );
  }
}

/// 按 NovelAI 分词规则粗略估算提示词 Token 数 (上限按模型分词器区分)
int estimatePromptTokens(String text, {int limit = 225}) {
  if (text.trim().isEmpty) return 0;
  final parts = text.split(RegExp(r'[,，\s\n]+')).where((s) => s.isNotEmpty);
  return (parts.length * 1.35).round().clamp(0, limit);
}

/// 提示词 Token 占用进度条 (上限按模型)
class TokenProgressBar extends StatelessWidget {
  final int tokens;
  final int tokenLimit;

  const TokenProgressBar({
    super.key,
    required this.tokens,
    this.tokenLimit = 225,
  });

  @override
  Widget build(BuildContext context) {
    return LinearProgressIndicator(
      value: (tokens / tokenLimit).clamp(0.0, 1.0),
      backgroundColor: Colors.black.withValues(alpha: 0.04),
      valueColor: const AlwaysStoppedAnimation<Color>(AppTheme.notionBlue),
      minHeight: 3,
    );
  }
}
