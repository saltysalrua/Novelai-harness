import 'package:flutter/material.dart';
import '../context_l10n.dart';
import '../theme/theme_context_extensions.dart';
import 'app_action_button.dart';
import 'app_dialog_scaffold.dart';
import 'app_transitions.dart';

/// 统一操作确认弹窗与破坏性警告对话框 (AppConfirmDialog)
///
/// 复用 [AppDialogScaffold] (minimalChrome) 与 [AppActionButton]，
/// 与全应用所有浮窗保持统一的 Notion 极简圆角、描边、阴影与 ESC 行为。
class AppConfirmDialog extends StatelessWidget {
  /// 弹窗标题
  final String title;

  /// 提示文本内容；当提供了 [contentWidget] 时以组件优先
  final String? message;

  /// 自定义内容组件 (如带详情列表或多行排版)
  final Widget? contentWidget;

  /// 确认按钮文案，默认 '确定'
  final String? confirmLabel;

  /// 取消按钮文案，默认 '取消'
  final String? cancelLabel;

  /// 是否为破坏性不可逆操作 (如清空、删除等)。
  final bool isDestructive;

  /// 是否允许 ESC / 右上角关闭
  final bool barrierDismissible;

  /// 点击确认回调；未指定时默认执行 `Navigator.of(context).pop(true)`
  final VoidCallback? onConfirm;

  /// 点击取消回调；未指定时默认执行 `Navigator.of(context).pop(false)`
  final VoidCallback? onCancel;

  const AppConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.contentWidget,
    this.confirmLabel,
    this.cancelLabel,
    this.isDestructive = false,
    this.barrierDismissible = true,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final cancelAction = onCancel ?? () => Navigator.of(context).pop(false);
    final confirmAction = onConfirm ?? () => Navigator.of(context).pop(true);

    return AppDialogScaffold(
      minimalChrome: true,
      title: title,
      width: 420,
      barrierDismissible: barrierDismissible,
      onClose: barrierDismissible ? cancelAction : null,
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(22, 6, 22, 12),
        child:
            contentWidget ??
            Text(
              message ?? '',
              style: TextStyle(
                fontSize: 13,
                color: colors.textSecondary,
                height: 1.5,
              ),
            ),
      ),
      actions: [
        AppActionButton(
          label: cancelLabel ?? context.maybeL10n?.cancel ?? '取消',
          variant: AppActionButtonVariant.ghost,
          onPressed: cancelAction,
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: confirmLabel ?? context.maybeL10n?.confirm ?? '确定',
          variant: isDestructive
              ? AppActionButtonVariant.danger
              : AppActionButtonVariant.primary,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          onPressed: confirmAction,
        ),
      ],
    );
  }
}

/// 弹出统一样式的确认对话框便捷函数
///
/// 返回 `true` 表示用户确认操作，`false` 或 `null` 表示取消。
Future<bool?> showAppConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  Widget? contentWidget,
  String? confirmLabel,
  String? cancelLabel,
  bool isDestructive = false,
  bool barrierDismissible = true,
}) {
  return showAppModalDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AppConfirmDialog(
      title: title,
      message: message,
      contentWidget: contentWidget,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
      barrierDismissible: barrierDismissible,
    ),
  );
}
