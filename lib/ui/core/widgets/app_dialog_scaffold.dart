import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';
import 'app_transitions.dart';

/// 统一模态对话框外壳 (Dialog Scaffold)
///
/// 具备：
/// 1. 统一的 Notion 质感外框、圆角、背景与亮暗自适应阴影；
/// 2. 顶部标准标题栏 (标题 + 可选副标题 + 关闭按钮)；
/// 3. ESC 快捷键自动捕获与退出——**内部输入框聚焦时首次 ESC 只退焦**，
///    不直接关弹窗丢数据 (第二次 ESC 才关闭)；
/// 4. 可选双栏布局 ([sidebar] 槽位，左侧贯穿导航/海报区，默认 200 宽)；
/// 5. 可选底部操作栏 (取消 / 确定 / 自定义操作)。
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

  /// 左侧双栏槽位 (如设置弹窗的贯穿导航、编辑弹窗的海报区)
  final Widget? sidebar;

  /// 左侧双栏槽位宽度 (默认 200，对齐设置弹窗侧栏规格)
  final double sidebarWidth;

  /// 是否采用 Notion 极简一体无分割线样式 (参考 MetadataReaderDialog)：
  /// 去除顶栏/底栏分割线与底栏异色条，视觉更轻盈低噪。
  final bool minimalChrome;

  /// 底部操作栏左侧附加槽位 (如删除模型、复制源码等次级动作)
  final Widget? footerLeading;

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
    this.sidebar,
    this.sidebarWidth = 200.0,
    this.minimalChrome = false,
    this.footerLeading,
  });

  /// 唤起居中弹窗便捷静态方法 (`06-modal` 动效)
  static Future<T?> show<T>({
    required BuildContext context,
    required WidgetBuilder builder,
    bool barrierDismissible = true,
  }) {
    return showAppModalDialog<T>(
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
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        // 长按 ESC 的重复事件同样消费，防止穿透到外层快捷键层
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        // 内部输入框正持有焦点时，首次 ESC 只退焦不关弹窗，避免丢数据
        // (聚焦时 primaryFocus 的 context.widget 是 Focus，
        //  需沿祖先链找 EditableTextState 判定)
        final primary = FocusManager.instance.primaryFocus;
        final primaryContext = primary?.context;
        final bool editingText =
            primaryContext?.findAncestorStateOfType<EditableTextState>() !=
            null;
        if (editingText) {
          primary!.unfocus();
          return KeyEventResult.handled;
        }
        if (onClose != null) {
          onClose!();
        } else {
          Navigator.of(context).pop();
        }
        return KeyEventResult.handled;
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
              boxShadow: context.shadowDialog,
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶部标题栏
                Container(
                  padding: minimalChrome
                      ? const EdgeInsets.fromLTRB(22, 18, 16, 8)
                      : const EdgeInsets.fromLTRB(
                          AppSpacing.xl,
                          AppSpacing.lg,
                          AppSpacing.lg,
                          AppSpacing.md,
                        ),
                  decoration: BoxDecoration(
                    color: colors.cardBackground,
                    border: minimalChrome
                        ? null
                        : Border(
                            bottom: BorderSide(color: colors.borderDefault),
                          ),
                  ),
                  child: Row(
                    crossAxisAlignment: minimalChrome
                        ? CrossAxisAlignment.start
                        : CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: minimalChrome
                                      ? colors.textMuted
                                      : colors.textSecondary,
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
                        splashRadius: minimalChrome ? 16 : 18,
                        padding: minimalChrome ? EdgeInsets.zero : null,
                        constraints: minimalChrome
                            ? const BoxConstraints.tightFor(
                                width: 28,
                                height: 28,
                              )
                            : null,
                        onPressed: onClose ?? () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),

                // 内容主体 (可选双栏: 左 sidebar 贯穿 + 右 body)
                Flexible(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (sidebar != null)
                        Container(
                          width: sidebarWidth,
                          decoration: BoxDecoration(
                            color: colors.elevatedBackground,
                            border: Border(
                              right: BorderSide(color: colors.borderDefault),
                            ),
                          ),
                          child: sidebar,
                        ),
                      Expanded(child: body),
                    ],
                  ),
                ),

                // 可选底部操作栏
                if (actions != null && actions!.isNotEmpty)
                  Container(
                    padding: minimalChrome
                        ? const EdgeInsets.fromLTRB(22, 10, 22, 18)
                        : const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xl,
                            vertical: AppSpacing.md,
                          ),
                    decoration: BoxDecoration(
                      color: minimalChrome
                          ? colors.cardBackground
                          : colors.elevatedBackground,
                      border: minimalChrome
                          ? null
                          : Border(
                              top: BorderSide(color: colors.borderDefault),
                            ),
                    ),
                    child: Row(
                      mainAxisAlignment: footerLeading != null
                          ? MainAxisAlignment.spaceBetween
                          : MainAxisAlignment.end,
                      children: [
                        if (footerLeading != null) ...[
                          footerLeading!,
                          const SizedBox(width: AppSpacing.md),
                        ],
                        Row(mainAxisSize: MainAxisSize.min, children: actions!),
                      ],
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
