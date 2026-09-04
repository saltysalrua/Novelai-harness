import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一操作确认弹窗与破坏性警告对话框 (AppConfirmDialog)
///
/// 代码证据出处：
/// - `image_canvas_actions.dart:200-237` (_confirmClearHistory 清空画板历史弹窗)
/// - `prompt_library_view.dart:230-260` (_confirmDelete 删除词组合弹窗)
/// - `agent_session_list_view.dart:122-164` (_showDeleteConfirmDialog 删除会话弹窗)
///
/// 核心职责：
/// 彻底消灭全工程手写的 `AlertDialog` 与硬编码珊瑚红 (`AppTheme.coral`)，
/// 统一 Notion 圆角外框、亮暗自适应背景、破坏性 (珊瑚红/Error) 与标准 (品牌蓝/Primary)
/// 双模式确认按钮，以及标准取消按钮。
class AppConfirmDialog extends StatelessWidget {
  /// 弹窗标题
  final String title;

  /// 提示文本内容；当提供了 [contentWidget] 时以组件优先
  final String? message;

  /// 自定义内容组件 (如带详情列表或多行排版)
  final Widget? contentWidget;

  /// 确认按钮文案，默认 '确定'
  final String confirmLabel;

  /// 取消按钮文案，默认 '取消'
  final String cancelLabel;

  /// 是否为破坏性不可逆操作 (如清空、删除等)。
  /// 为 true 时确认按钮呈现警示色并在视觉上强调不可撤销性。
  final bool isDestructive;

  /// 点击确认回调；未指定时默认执行 `Navigator.of(context).pop(true)`
  final VoidCallback? onConfirm;

  /// 点击取消回调；未指定时默认执行 `Navigator.of(context).pop(false)`
  final VoidCallback? onCancel;

  const AppConfirmDialog({
    super.key,
    required this.title,
    this.message,
    this.contentWidget,
    this.confirmLabel = '确定',
    this.cancelLabel = '取消',
    this.isDestructive = false,
    this.onConfirm,
    this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final confirmBgColor = isDestructive ? colors.error : colors.primary;

    return AlertDialog(
      backgroundColor: colors.cardBackground,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: BorderSide(color: colors.borderDefault),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      contentPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
      ),
      content:
          contentWidget ??
          Text(
            message ?? '',
            style: TextStyle(
              fontSize: 12.5,
              color: colors.textSecondary,
              height: 1.45,
            ),
          ),
      actions: [
        TextButton(
          onPressed: onCancel ?? () => Navigator.of(context).pop(false),
          style: TextButton.styleFrom(
            foregroundColor: colors.textSecondary,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(cancelLabel),
        ),
        FilledButton(
          onPressed: onConfirm ?? () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: confirmBgColor,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          child: Text(confirmLabel),
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
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool isDestructive = false,
  bool barrierDismissible = true,
}) {
  return showDialog<bool>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (ctx) => AppConfirmDialog(
      title: title,
      message: message,
      contentWidget: contentWidget,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      isDestructive: isDestructive,
    ),
  );
}
