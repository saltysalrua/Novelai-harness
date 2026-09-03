import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一模态对话框外壳 (Dialog Scaffold)
///
/// 具备：
/// 1. 统一的 Notion 质感外框、圆角、背景与层级阴影；
/// 2. 顶部标准标题栏 (标题 + 可选副标题 + 关闭按钮)；
/// 3. ESC 快捷键自动捕获与退出；
/// 4. 可选底部操作栏 (取消 / 确定 / 自定义操作)。
class AppDialogScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final double width;
  final double? height;
  final double? maxHeight;
  final List<Widget>? actions;
  final VoidCallback? onClose;
  final bool barrierDismissible;

  const AppDialogScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.width = 680.0,
    this.height,
    this.maxHeight = 720.0,
    this.actions,
    this.onClose,
    this.barrierDismissible = true,
  });

  /// 唤起居中弹窗便捷静态方法
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return showDialog<T>(
      context: context,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: builder,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          if (onClose != null) {
            onClose!();
          } else {
            Navigator.of(context).pop();
          }
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: width,
            height: height,
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width - 48,
              maxHeight: maxHeight ?? (MediaQuery.of(context).size.height - 48),
            ),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderDefault),
              boxShadow: AppShadows.dialog(Colors.black),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部标题栏
                Container(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.lg, AppSpacing.lg, AppSpacing.md),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    border: Border(bottom: BorderSide(color: colors.borderDefault)),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                            ),
                            if (subtitle != null && subtitle!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                subtitle!,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: colors.textSecondary,
                        ),
                        splashRadius: 18,
                        onPressed: onClose ?? () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // 内容主体
                Flexible(child: body),

                // 可选底部操作栏
                if (actions != null && actions!.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xl,
                      vertical: AppSpacing.md,
                    ),
                    decoration: BoxDecoration(
                      color: colors.elevatedBackground,
                      border: Border(top: BorderSide(color: colors.borderDefault)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: actions!,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
