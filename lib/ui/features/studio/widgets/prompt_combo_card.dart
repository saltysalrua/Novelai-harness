import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/theme/app_theme.dart';
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

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Center(child: Icon(icon, size: 17, color: color)),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isChar = combo.isCharacter;
    final hasNegative = isChar && combo.negativePrompt.trim().isNotEmpty;
    final hasPreview =
        combo.previewImagePath != null &&
        File(combo.previewImagePath!).existsSync();

    return GestureDetector(
      // 卡片主体右键：完整应用选项菜单
      onSecondaryTapDown: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. 顶部超大预览图 / Notion 占位图 (含应用到工作台悬浮按钮)
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
                          errorBuilder: (_, _, _) =>
                              _buildPlaceholderBanner(isChar),
                        )
                      : _buildPlaceholderBanner(isChar),
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

            const Divider(height: 1, color: AppTheme.border),

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
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.charcoal,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 主提示词预览块 (Notion 极简纯净浅灰)
                    Expanded(
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(7),
                        decoration: BoxDecoration(
                          color: AppTheme.surfaceMuted,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          border: Border.all(color: AppTheme.border),
                        ),
                        child: Text(
                          combo.prompt,
                          maxLines: hasNegative ? 2 : 4,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.charcoal,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ),

                    // 负面提示词预览块 (仅角色分类且非空时展示)
                    if (hasNegative) ...[
                      const SizedBox(height: 5),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFCF5F5),
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          border: Border.all(
                            color: AppTheme.coral.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'UC: ',
                              style: TextStyle(
                                fontSize: 9.5,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.coral,
                              ),
                            ),
                            Expanded(
                              child: Text(
                                combo.negativePrompt,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  color: AppTheme.charcoal,
                                  height: 1.2,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppTheme.border),

            // 3. 底部操作栏 (醒目分类胶囊 + 快捷操作按钮)
            _buildBottomBar(context, isChar),
          ],
        ),
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
                                fontSize: 10.5,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      color: AppTheme.paperWarmth,
      child: Row(
        children: [
          // 醒目的左侧分类胶囊
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: isChar ? const Color(0xFFFFECEB) : AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                color: isChar
                    ? AppTheme.coral.withValues(alpha: 0.35)
                    : AppTheme.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  isChar ? Icons.person_outline : Icons.label_outline,
                  size: 12.5,
                  color: isChar ? AppTheme.coral : AppTheme.graphite,
                ),
                const SizedBox(width: 4),
                Text(
                  combo.category,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isChar ? FontWeight.w600 : FontWeight.w500,
                    color: isChar ? AppTheme.coral : AppTheme.charcoal,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // 复制按钮
          _buildActionButton(
            icon: Icons.copy_outlined,
            tooltip: '复制提示词',
            color: AppTheme.charcoal,
            onTap: () => _copyToClipboard(context),
          ),
          const SizedBox(width: 6),

          // 编辑按钮
          _buildActionButton(
            icon: Icons.edit_outlined,
            tooltip: '编辑',
            color: AppTheme.notionBlue,
            onTap: onEdit,
          ),
          const SizedBox(width: 6),

          // 删除按钮
          _buildActionButton(
            icon: Icons.delete_outline,
            tooltip: '删除',
            color: AppTheme.coral,
            onTap: onDelete,
          ),
        ],
      ),
    );
  }

  /// Notion 风格极简纯净占位图
  Widget _buildPlaceholderBanner(bool isChar) {
    return Container(
      color: const Color(0xFFF4F3EF),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isChar ? Icons.person_outline : Icons.collections_outlined,
              size: 32,
              color: AppTheme.graphite.withValues(alpha: 0.35),
            ),
            const SizedBox(height: 6),
            Text(
              '无预览图',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.graphite.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
