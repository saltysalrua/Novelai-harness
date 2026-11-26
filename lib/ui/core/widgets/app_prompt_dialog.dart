import 'package:flutter/material.dart';
import '../context_l10n.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'app_action_button.dart';
import 'app_dialog_scaffold.dart';
import 'app_transitions.dart';

/// 统一单行输入模态对话框 (AppPromptDialog)
///
/// 复用 [AppDialogScaffold] (minimalChrome) 与柔底输入框、统一 [AppActionButton]，
/// 支持自动聚焦、非空/自定义校验、回车提交以及首次 ESC 退焦保护。
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
  final String? confirmLabel;

  /// 取消按钮文案，默认 '取消'
  final String? cancelLabel;

  /// 是否允许提交空白内容，默认 false (自动校验非空)
  final bool allowEmpty;

  /// 自定义非空或格式校验回调 (返回错误提示文字；返回 null 表示校验通过)
  final String? Function(String?)? validator;

  /// 是否允许点击外部或 ESC 关闭
  final bool barrierDismissible;

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
    this.confirmLabel,
    this.cancelLabel,
    this.allowEmpty = false,
    this.validator,
    this.barrierDismissible = true,
    this.onConfirm,
    this.onCancel,
  });

  @override
  State<AppPromptDialog> createState() => _AppPromptDialogState();
}

class _AppPromptDialogState extends State<AppPromptDialog> {
  late final TextEditingController _controller;
  final AppErrorShakeController _shakeController = AppErrorShakeController();
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue ?? '');
  }

  @override
  void dispose() {
    _shakeController.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    final text = _controller.text.trim();

    if (!widget.allowEmpty && text.isEmpty) {
      setState(() {
        _errorText = context.maybeL10n?.commonRequiredInput ?? '内容不能为空';
      });
      _shakeController.shake();
      return;
    }

    if (widget.validator != null) {
      final customError = widget.validator!(text);
      if (customError != null) {
        setState(() {
          _errorText = customError;
        });
        _shakeController.shake();
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
    final cancelAction = widget.onCancel ?? () => Navigator.of(context).pop(null);

    return AppDialogScaffold(
      minimalChrome: true,
      title: widget.title,
      width: 420,
      barrierDismissible: widget.barrierDismissible,
      onClose: widget.barrierDismissible ? cancelAction : null,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
        child: AppErrorShake(
          controller: _shakeController,
          child: TextField(
            controller: _controller,
            autofocus: true,
            style: TextStyle(fontSize: 13, color: colors.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText:
                  widget.hintText ??
                  context.maybeL10n?.commonInputHint ??
                  '请输入内容…',
              hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              filled: true,
              fillColor: colors.elevatedBackground,
              hoverColor: colors.mutedBackground.withValues(alpha: 0.7),
              errorText: _errorText,
              errorStyle: TextStyle(fontSize: 11, color: colors.error),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: colors.primary, width: 1.5),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: colors.error, width: 1.2),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: BorderSide(color: colors.error, width: 1.5),
              ),
            ),
            onChanged: (_) {
              if (_errorText != null) {
                setState(() => _errorText = null);
              }
            },
            onSubmitted: (_) => _handleSubmit(),
          ),
        ),
      ),
      actions: [
        AppActionButton(
          label: widget.cancelLabel ?? context.maybeL10n?.cancel ?? '取消',
          variant: AppActionButtonVariant.ghost,
          onPressed: cancelAction,
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: widget.confirmLabel ?? context.maybeL10n?.confirm ?? '确定',
          variant: AppActionButtonVariant.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          onPressed: _handleSubmit,
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
  String? confirmLabel,
  String? cancelLabel,
  bool allowEmpty = false,
  String? Function(String?)? validator,
  bool barrierDismissible = true,
}) {
  return showAppModalDialog<String>(
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
      barrierDismissible: barrierDismissible,
    ),
  );
}
