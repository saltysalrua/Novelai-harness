import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/context_menu.dart';

/// 词库单条词组合画廊卡片。
///
/// 自身不持有 ViewModel，全部动作经回调上抛：
/// - [onApply]: (replace, asCharacter) 应用到工作台提示词
/// - [onEdit] / [onDelete]: 编辑与删除
/// - 复制提示词为组件内置行为 (仅依赖剪贴板)
///
/// 卡片主体支持右键菜单 (追加 / 替换 / 作为角色 / 复制 / 编辑 / 删除)。
class PromptComboCard extends StatelessWidget {
  final PromptComboEntry combo;
  final void Function(bool replace, bool asCharacter) onApply;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const PromptComboCard({
    super.key,
    required this.combo,
    required this.onApply,
    required this.onEdit,
    required this.onDelete,
  });

  void _copyToClipboard(BuildContext context) {
    final text = combo.isCharacter && combo.negativePrompt.isNotEmpty
        ? 'Prompt: ${combo.prompt}\nNegative: ${combo.negativePrompt}'
        : combo.prompt;
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.libraryCardCopiedPrompt(combo.title)),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    final l10n = context.l10n;
    showStudioContextMenu(
      context,
      position: position,
      actions: [
        ContextMenuItem(
          icon: Icons.add_outlined,
          label: l10n.libraryMenuAppendToPrompt,
          onTap: () => onApply(false, false),
        ),
        ContextMenuItem(
          icon: Icons.swap_horiz_outlined,
          label: l10n.libraryMenuReplacePrompt,
          onTap: () => onApply(true, false),
        ),
        if (combo.isCharacter)
          ContextMenuItem(
            icon: Icons.person_add_alt_1_outlined,
            label: l10n.libraryMenuAddAsCharacter,
            onTap: () => onApply(false, true),
          ),
        const ContextMenuDivider(),
        ContextMenuItem(
          icon: Icons.copy_outlined,
          label: l10n.libraryMenuCopyPrompt,
          onTap: () => _copyToClipboard(context),
        ),
        ContextMenuItem(
          icon: Icons.edit_outlined,
          label: l10n.libraryMenuEdit,
          onTap: onEdit,
        ),
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: l10n.delete,
          onTap: onDelete,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isChar = combo.isCharacter;
    final hasNegative = isChar && combo.negativePrompt.trim().isNotEmpty;
    final hasPreview =
        combo.previewImagePath != null &&
        File(combo.previewImagePath!).existsSync();

    return AppCard(
      onContextMenu: (position) => _showContextMenu(context, position),
      elevated: true,
      radius: AppRadius.lg,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 图片优先占满剩余空间，文字与操作区保持紧凑。
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                hasPreview
                    ? Image.file(
                        File(combo.previewImagePath!),
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        gaplessPlayback: true,
                        errorBuilder: (_, _, _) =>
                            _buildPlaceholderBanner(context, isChar),
                      )
                    : _buildPlaceholderBanner(context, isChar),
                // 底部渐变条上的应用按钮：一键追加到工作台
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _buildApplyOverlay(context),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: colors.borderDefault),

          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Tooltip(
                  message: combo.title,
                  child: Text(
                    combo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 3),
                Tooltip(
                  message: hasNegative
                      ? '${combo.prompt}\nUC: ${combo.negativePrompt}'
                      : combo.prompt,
                  child: Text(
                    combo.prompt,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: colors.textMuted),
                  ),
                ),
              ],
            ),
          ),

          // 3. 底部操作栏 (醒目分类胶囊 + 快捷操作按钮)
          _buildBottomBar(context, isChar),
        ],
      ),
    );
  }

  /// 预览图底部半透明渐变应用条：点击即追加到工作台提示词
  Widget _buildApplyOverlay(BuildContext context) {
    final l10n = context.l10n;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => onApply(false, false),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.0),
                Colors.black.withValues(alpha: 0.45),
              ],
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: [
                const Icon(Icons.bolt_outlined, size: 13, color: Colors.white),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    l10n.libraryCardApply,
                    style: const TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (combo.isCharacter)
                  Tooltip(
                    message: l10n.libraryCardAddAsCharacterTooltip,
                    child: InkWell(
                      onTap: () => onApply(false, true),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 13,
                              color: Colors.white,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              l10n.libraryCardAddCharacter,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(BuildContext context, bool isChar) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      color: colors.elevatedBackground,
      child: Row(
        children: [
          // 醒目的左侧分类胶囊
          Expanded(
            child: Tooltip(
              message: comboCategoryLabelOf(l10n, combo.category),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: AppBadge(
                  label: comboCategoryLabelOf(l10n, combo.category),
                  icon: isChar ? Icons.person_outline : Icons.label_outline,
                  variant: isChar
                      ? AppBadgeVariant.error
                      : AppBadgeVariant.neutral,
                  shape: AppBadgeShape.rounded,
                  fontSize: 11,
                  iconSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),

          // 复制按钮
          AppIconButton(
            icon: Icons.copy_outlined,
            tooltip: l10n.libraryMenuCopyPrompt,
            size: 28,
            iconSize: 15,
            iconColor: colors.textPrimary,
            variant: AppIconButtonVariant.outlined,
            onPressed: () => _copyToClipboard(context),
          ),
          const SizedBox(width: 4),

          // 编辑按钮
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: l10n.libraryMenuEdit,
            size: 28,
            iconSize: 15,
            iconColor: colors.primary,
            variant: AppIconButtonVariant.outlined,
            onPressed: onEdit,
          ),
          const SizedBox(width: 4),

          // 删除按钮
          AppIconButton(
            icon: Icons.delete_outline,
            tooltip: l10n.delete,
            size: 28,
            iconSize: 15,
            iconColor: colors.error,
            variant: AppIconButtonVariant.outlined,
            onPressed: onDelete,
          ),
        ],
      ),
    );
  }

  /// 极简纯净占位图
  Widget _buildPlaceholderBanner(BuildContext context, bool isChar) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      color: colors.mutedBackground,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isChar ? Icons.person_outline : Icons.collections_outlined,
              size: 32,
              color: colors.textMuted.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.libraryCardNoPreview,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
