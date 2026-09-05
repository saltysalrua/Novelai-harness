import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_copyable_box.dart';
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
        content: Text('已复制「${combo.title}」提示词到剪贴板'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showContextMenu(BuildContext context, Offset position) {
    showStudioContextMenu(
      context,
      position: position,
      actions: [
        ContextMenuItem(
          icon: Icons.add_outlined,
          label: '追加到工作台提示词',
          onTap: () => onApply(false, false),
        ),
        ContextMenuItem(
          icon: Icons.swap_horiz_outlined,
          label: '替换工作台提示词',
          onTap: () => onApply(true, false),
        ),
        if (combo.isCharacter)
          ContextMenuItem(
            icon: Icons.person_add_alt_1_outlined,
            label: '添加为多角色卡片',
            onTap: () => onApply(false, true),
          ),
        const ContextMenuDivider(),
        ContextMenuItem(
          icon: Icons.copy_outlined,
          label: '复制提示词',
          onTap: () => _copyToClipboard(context),
        ),
        ContextMenuItem(icon: Icons.edit_outlined, label: '编辑', onTap: onEdit),
        ContextMenuItem(
          icon: Icons.delete_outline,
          label: '删除',
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
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      elevated: true,
      radius: AppRadius.lg,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶部超大预览图 / 占位图 (含应用到工作台悬浮按钮)
          SizedBox(
            height: 210,
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
                  child: _buildApplyOverlay(),
                ),
              ],
            ),
          ),

          Divider(height: 1, color: colors.borderDefault),

          // 2. 标题与提示词内容区
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 组合名称
                  Text(
                    combo.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 6),

                  // 主提示词预览块
                  Expanded(
                    child: AppCopyableBox(
                      content: combo.prompt,
                      showCopyButton: false,
                      selectable: false,
                      maxLines: hasNegative ? 2 : 4,
                      fontSize: 11,
                      radius: AppRadius.sm,
                      padding: const EdgeInsets.all(7),
                    ),
                  ),

                  // 负面提示词预览块 (仅角色分类且非空时展示)
                  if (hasNegative) ...[
                    const SizedBox(height: 5),
                    AppCopyableBox(
                      content: combo.negativePrompt,
                      prefixBadge: 'UC:',
                      prefixBadgeColor: colors.error,
                      showCopyButton: false,
                      selectable: false,
                      maxLines: 1,
                      fontSize: 11,
                      radius: AppRadius.sm,
                      backgroundColor: colors.errorSurface,
                      borderColor: colors.error.withValues(alpha: 0.25),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 4,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          Divider(height: 1, color: colors.borderDefault),

          // 3. 底部操作栏 (醒目分类胶囊 + 快捷操作按钮)
          _buildBottomBar(context, isChar),
        ],
      ),
    );
  }

  /// 预览图底部半透明渐变应用条：点击即追加到工作台提示词
  Widget _buildApplyOverlay() {
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
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            child: Row(
              children: [
                const Icon(Icons.bolt_outlined, size: 13, color: Colors.white),
                const SizedBox(width: 5),
                const Expanded(
                  child: Text(
                    '应用到工作台',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
                if (combo.isCharacter)
                  Tooltip(
                    message: '添加为工作台多角色卡片',
                    child: InkWell(
                      onTap: () => onApply(false, true),
                      borderRadius: BorderRadius.circular(4),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 2,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.person_add_alt_1_outlined,
                              size: 13,
                              color: Colors.white,
                            ),
                            SizedBox(width: 3),
                            Text(
                              '+ 角色',
                              style: TextStyle(
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: colors.elevatedBackground,
      child: Row(
        children: [
          // 醒目的左侧分类胶囊
          AppBadge(
            label: combo.category,
            icon: isChar ? Icons.person_outline : Icons.label_outline,
            variant: isChar ? AppBadgeVariant.error : AppBadgeVariant.neutral,
            shape: AppBadgeShape.rounded,
            fontSize: 11,
            iconSize: 13,
          ),

          const Spacer(),

          // 复制按钮
          AppIconButton(
            icon: Icons.copy_outlined,
            tooltip: '复制提示词',
            size: 32,
            iconSize: 17,
            iconColor: colors.textPrimary,
            variant: AppIconButtonVariant.outlined,
            onPressed: () => _copyToClipboard(context),
          ),
          const SizedBox(width: 6),

          // 编辑按钮
          AppIconButton(
            icon: Icons.edit_outlined,
            tooltip: '编辑',
            size: 32,
            iconSize: 17,
            iconColor: colors.primary,
            variant: AppIconButtonVariant.outlined,
            onPressed: onEdit,
          ),
          const SizedBox(width: 6),

          // 删除按钮
          AppIconButton(
            icon: Icons.delete_outline,
            tooltip: '删除',
            size: 32,
            iconSize: 17,
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
              '无预览图',
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
