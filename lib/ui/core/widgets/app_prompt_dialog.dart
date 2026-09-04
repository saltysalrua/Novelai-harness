import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一单行输入模态对话框 (AppPromptDialog)
///
/// 代码证据出处：
/// - `agent_session_list_view.dart:55-120` (_showRenameDialog 会话重命名模态弹窗)
///
/// 核心职责：
/// 统一单行短文本录入模态，支持自动聚焦、输入清洗、非空/自定义校验、
/// 回车直接提交以及取消返回 null，消灭零散手写的重命名与文本弹窗。
class AppPromptDialog extends StatefulWidget {
  /// 弹窗标题
  final String title;

  /// 初始默认文本
  final String? initialValue;

  /// 输入框占位提示语
  final String? hintText;

  /// 标题前缀小图标 (可选)
  final IconData? icon;

  /// 确认按钮文案，默认 '确定'
  final String confirmLabel;

  /// 取消按钮文案，默认 '取消'
  final String cancelLabel;

  /// 是否允许提交空白内容，默认 false (自动校验非空)
  final bool allowEmpty;

  /// 自定义非空或格式校验回调 (返回错误提示文字；返回 null 表示校验通过)
  final String? Function(String?)? validator;

  /// 提交确认回调；若未指定则默认执行 `Navigator.of(context).pop(text)`
  final ValueChanged<String>? onConfirm;

  /// 取消回调；若未指定则默认执行 `Navigator.of(context).pop(null)`
  final VoidCallback? onCancel;

  const AppPromptDialog({
    super.key,
    required this.title,
    this.initialValue,
    this.hintText,
    this.icon,
    this.confirmLabel = '确定',
    this.cancelLabel = '取消',
    this.allowEmpty = false,
    this.validator,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<AppPromptDialog> createState() => _AppPromptDialogState();
}

class _AppPromptDialogState extends State<AppPromptDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();

    if (!widget.allowEmpty && text.isEmpty) {
      setState(() {
        _errorText = '内容不能为空';
      });
      return;
    }

    if (widget.validator != null) {
      final customError = widget.validator!(text);
      if (customError != null) {
        setState(() {
          _errorText = customError;
        });
        return;
      }
    }

    if (widget.onConfirm != null) {
      widget.onConfirm!(text);
    } else {
      Navigator.of(context).pop(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AlertDialog(
      backgroundColor: colors.cardBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.borderDefault),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: 18, color: colors.primary),
            const SizedBox(width: 8),
          ],
          Text(
            widget.title,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              style: TextStyle(fontSize: 13, color: colors.textPrimary),
              decoration: InputDecoration(
                hintText: widget.hintText ?? '请输入内容...',
                hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                filled: true,
                fillColor: colors.mutedBackground.withValues(alpha: 0.5),
                errorText: _errorText,
                errorStyle: TextStyle(fontSize: 11, color: colors.error),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
              ),
              onChanged: (_) {
                if (_errorText != null) {
                  setState(() => _errorText = null);
                }
              },
              onSubmitted: (_) => _handleSubmit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: widget.onCancel ?? () => Navigator.of(context).pop(null),
          style: TextButton.styleFrom(
            foregroundColor: colors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(widget.cancelLabel),
        ),
        FilledButton(
          onPressed: _handleSubmit,
          style: FilledButton.styleFrom(
            backgroundColor: colors.primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// 弹出单行输入模态弹窗便捷函数
///
/// 用户输入并提交后返回输入的有效文本；若用户取消或关闭弹窗则返回 `null`。
Future<String?> showAppPromptDialog(
  BuildContext context, {
  required String title,
  String? initialValue,
  String? hintText,
  IconData? icon,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool allowEmpty = false,
  String? Function(String?)? validator,
  bool barrierDismissible = true,
}) {
  return showDialog<String>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AppPromptDialog(
      title: title,
      initialValue: initialValue,
      hintText: hintText,
      icon: icon,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      allowEmpty: allowEmpty,
      validator: validator,
    ),
  );
}
