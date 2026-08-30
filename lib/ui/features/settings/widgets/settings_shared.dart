import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 设置页小节标题 (General / Models / Presets 各页复用)
class SettingsGroupTitle extends StatelessWidget {
  final String title;

  const SettingsGroupTitle(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

/// 统一设置项卡片 (标题 + 副标题 + 右侧控件 + 可选底部扩展内容)
class SettingsCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget control;
  final Widget? bottomChild;

  const SettingsCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.control,
    this.bottomChild,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              control,
            ],
          ),
          if (bottomChild != null) ...[const SizedBox(height: 8), bottomChild!],
        ],
      ),
    );
  }
}

/// 统一圆角下拉选择框 (设置页各处复用)
class SettingsDropdown<T> extends StatelessWidget {
  final T value;
  final List<T> items;
  final String Function(T item) labelBuilder;
  final ValueChanged<T?> onChanged;

  const SettingsDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.labelBuilder,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelBuilder(item),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          icon: const Icon(
            Icons.unfold_more_rounded,
            size: 16,
            color: AppTheme.stone,
          ),
          dropdownColor: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// 统一细边框操作小按钮 (新建 / 复制 / 选择 / 导入等操作坞复用)
class SettingsActionButton extends StatelessWidget {
  final IconData? icon;
  final String label;
  final VoidCallback? onPressed;
  final double iconSize;

  const SettingsActionButton({
    super.key,
    this.icon,
    required this.label,
    required this.onPressed,
    this.iconSize = 15,
  });

  @override
  Widget build(BuildContext context) {
    if (icon == null) {
      return OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppTheme.border),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.textPrimary,
          ),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppTheme.border),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
      icon: icon != null
          ? Icon(icon, size: iconSize, color: AppTheme.textPrimary)
          : const SizedBox.shrink(),
      label: Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }
}

/// 统一 ID 下拉选择框 (供应商 / 预设等字符串 ID 选择复用，支持自定义条目内容)
class SettingsIdDropdown extends StatelessWidget {
  final String value;
  final List<DropdownMenuItem<String>> items;
  final ValueChanged<String?> onChanged;

  const SettingsIdDropdown({
    super.key,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          items: items,
          onChanged: onChanged,
          icon: const Icon(
            Icons.unfold_more_rounded,
            size: 16,
            color: AppTheme.stone,
          ),
          dropdownColor: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// 带可见性切换的密钥输入框 (NovelAI Key / LLM Key 复用)
class SettingsKeyField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final double width;

  const SettingsKeyField({
    super.key,
    required this.controller,
    required this.hintText,
    this.width = 250,
  });

  @override
  State<SettingsKeyField> createState() => _SettingsKeyFieldState();
}

class _SettingsKeyFieldState extends State<SettingsKeyField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: 36,
      child: TextField(
        controller: widget.controller,
        obscureText: _obscure,
        style: const TextStyle(fontSize: 12),
        decoration: InputDecoration(
          hintText: widget.hintText,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 8,
          ),
          suffixIcon: IconButton(
            icon: Icon(
              _obscure ? Icons.visibility_off : Icons.visibility,
              size: 15,
              color: AppTheme.textMuted,
            ),
            onPressed: () => setState(() => _obscure = !_obscure),
          ),
        ),
      ),
    );
  }
}

/// 设置域统一遮罩弹窗 (统一黑色半透明遮罩)
Future<T?> showSettingsDialog<T>(BuildContext context, WidgetBuilder builder) {
  return showDialog<T>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: builder,
  );
}
