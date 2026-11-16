import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_transitions.dart';

/// Notion 极简软框输入装饰 (无外框、柔底填充、聚焦描边)，
/// 对齐 MetadataReaderDialog / PromptComboEditDialog 的低噪质感。
InputDecoration settingsSoftInputDecoration(
  BuildContext context, {
  String? hintText,
  String? errorText,
  bool readOnly = false,
  Color? fillColor,
  EdgeInsetsGeometry contentPadding = const EdgeInsets.symmetric(
    horizontal: 11,
    vertical: 9,
  ),
  Widget? suffixIcon,
}) {
  final colors = context.colors;
  final resolvedFill =
      fillColor ??
      (readOnly
          ? colors.mutedBackground.withValues(alpha: 0.65)
          : colors.elevatedBackground);
  return InputDecoration(
    isDense: true,
    hintText: hintText != null && hintText.isNotEmpty ? hintText : null,
    hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
    errorText: errorText,
    errorStyle: const TextStyle(fontSize: 10, height: 1.1),
    filled: true,
    fillColor: resolvedFill,
    hoverColor: readOnly
        ? resolvedFill
        : colors.mutedBackground.withValues(alpha: 0.7),
    contentPadding: contentPadding,
    suffixIcon: suffixIcon,
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide.none,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide.none,
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide.none,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(
        color: readOnly ? colors.borderDefault : colors.primary,
        width: 1.5,
      ),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: colors.error, width: 1.2),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(AppRadius.md),
      borderSide: BorderSide(color: colors.error, width: 1.5),
    ),
  );
}

/// 表单小节 / 字段标题行 (11.5px 半粗 muted 文字 + 可选右侧快捷操作)
class SettingsFieldLabel extends StatelessWidget {
  final String label;
  final Widget? trailing;

  const SettingsFieldLabel({super.key, required this.label, this.trailing});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Notion 风格无框轻底分组容器 (`elevatedBackground` + 圆角，零描边低噪)
class SettingsSoftContainer extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final double radius;
  final Color? color;

  const SettingsSoftContainer({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(12),
    this.radius = AppRadius.md,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: color ?? context.colors.elevatedBackground,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: child,
    );
  }
}

/// 轻量内联文字操作 (如全选、全不选、复制、格式化 JSON)
class SettingsInlineLink extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final Color? color;

  const SettingsInlineLink({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.colors.primary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 13, color: effectiveColor),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: effectiveColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 带可见性切换的密钥输入框 (NovelAI Key / LLM Key 复用)
class SettingsKeyField extends StatefulWidget {
  final TextEditingController controller;
  final String hintText;
  final double? width;
  final bool soft;

  const SettingsKeyField({
    super.key,
    required this.controller,
    required this.hintText,
    this.width = 250,
    this.soft = false,
  });

  @override
  State<SettingsKeyField> createState() => _SettingsKeyFieldState();
}

class _SettingsKeyFieldState extends State<SettingsKeyField> {
  bool _obscure = true;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final suffix = IconButton(
      icon: AppIconSwap(
        swapKey: _obscure,
        enableBlur: false,
        child: Icon(
          _obscure ? Icons.visibility_off : Icons.visibility,
          key: ValueKey<bool>(_obscure),
          size: 15,
          color: colors.textMuted,
        ),
      ),
      onPressed: () => setState(() => _obscure = !_obscure),
    );

    final field = SizedBox(
      height: 36,
      child: TextField(
        controller: widget.controller,
        obscureText: _obscure,
        style: const TextStyle(fontSize: 12),
        decoration: widget.soft
            ? settingsSoftInputDecoration(
                context,
                hintText: widget.hintText,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 8,
                ),
                suffixIcon: suffix,
              )
            : InputDecoration(
                hintText: widget.hintText,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixIcon: suffix,
              ),
      ),
    );

    if (widget.width == null) return field;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: widget.width!),
      child: field,
    );
  }
}
