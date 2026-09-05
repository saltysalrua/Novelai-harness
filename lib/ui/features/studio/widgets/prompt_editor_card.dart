import 'package:flutter/material.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_progress_bar.dart';
import 'prompt_edit_actions.dart';
import 'prompt_resize_handle.dart';
import 'tag_browser_dialog.dart';

/// 只读灰色标签数据 (PREFIX / SUFFIX / QUALITY / BG / UC 预设词展示)
class GrayTag {
  final String label;
  final String text;

  const GrayTag(this.label, this.text);
}

/// 提示词编辑卡：只读标签头 + 主输入框 (支持上下拖拽调节高度) + 调节手柄 + 只读标签脚 + 工具条 + 快捷标签操作 + Token 进度条。
/// 正向提示词与负面排除词、垂直堆叠与标签页两种布局共用同一张卡。
class PromptEditorCard extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  /// 输入框行数参考 (用于推导初始默认高度)
  final int minLines;
  final int maxLines;

  /// 最小高度与最大高度限制
  final double minHeight;
  final double maxHeight;

  /// 初始高度 (持久化加载的高度)
  final double? initialHeight;

  /// 高度变更回调 (用于持久化)
  final ValueChanged<double>? onHeightChanged;

  /// 输入框上方只读标签 (如 PREFIX 前置词)
  final List<GrayTag> headerTags;

  /// 输入框下方只读标签 (如 SUFFIX / QUALITY / BG 或官方 UC 预设词)
  final List<GrayTag> footerTags;

  /// 底部工具条 (胶囊开关与预设下拉等)
  final Widget? toolbar;

  /// 是否显示快捷标签工具条 (加权/降权/禁用/格式化/标签库)
  final bool showQuickActions;

  /// Token 估算值，用于底部进度条
  final int tokenEstimate;

  /// Token 上限 (按模型分词器区分)
  final int tokenLimit;

  /// 是否启用 Danbooru 自动补全 (设置项控制)
  final bool enableAutocomplete;

  /// 标签库与补全建议中是否显示中文释义 (设置项控制)
  final bool showTranslation;

  const PromptEditorCard({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.minLines = 4,
    this.maxLines = 10,
    this.minHeight = 70.0,
    this.maxHeight = 600.0,
    this.initialHeight,
    this.onHeightChanged,
    this.headerTags = const [],
    this.footerTags = const [],
    this.toolbar,
    this.showQuickActions = true,
    required this.tokenEstimate,
    this.tokenLimit = 225,
    this.enableAutocomplete = true,
    this.showTranslation = true,
  });

  /// 按行数参考推导的默认输入区高度 (布局模式切换时变化)
  double get _defaultInputHeight =>
      (minLines * 24.0 + 20.0).clamp(minHeight, maxHeight);

  void _openTagBrowser(BuildContext context) {
    TagBrowserDialog.show(
      context,
      showTranslation: showTranslation,
      onTagSelected: (tag) {
        final text = controller.text;
        final trimmed = text.trim();
        final newText = trimmed.isEmpty
            ? tag
            : (trimmed.endsWith(',') ? '$trimmed $tag' : '$trimmed, $tag');
        controller.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: newText.length),
        );
        onChanged(newText);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerTags.isNotEmpty) _TagPanel(tags: headerTags, atTop: true),
          ResizableTextField(
            controller: controller,
            onChanged: onChanged,
            hintText: hintText,
            defaultHeight: _defaultInputHeight,
            initialHeight: initialHeight,
            onHeightChanged: onHeightChanged,
            minHeight: minHeight,
            maxHeight: maxHeight,
            resizeTooltip: '拖动调整提示词输入区高度 (双击重置)',
            enableAutocomplete: enableAutocomplete,
            showTranslation: showTranslation,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            style: TextStyle(
              fontSize: 14,
              height: 1.48,
              color: colors.textPrimary,
            ),
            hintStyle: TextStyle(
              fontSize: 13,
              height: 1.48,
              color: colors.textMuted,
            ),
          ),
          if (footerTags.isNotEmpty) _TagPanel(tags: footerTags, atTop: false),
          if (toolbar != null || showQuickActions)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (toolbar != null) ...[
                    toolbar!,
                    if (showQuickActions) const SizedBox(height: 4),
                  ],
                  if (showQuickActions)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        _QuickActionButton(
                          tooltip: '增加标签数值权重 (Ctrl+↑，格式 x.x::tag::)',
                          label: '+0.1',
                          onTap: () => PromptEditActions.adjustWeight(
                            controller,
                            onChanged,
                            up: true,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _QuickActionButton(
                          tooltip: '降低标签数值权重 (Ctrl+↓，格式 x.x::tag::)',
                          label: '-0.1',
                          onTap: () => PromptEditActions.adjustWeight(
                            controller,
                            onChanged,
                            up: false,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _QuickActionButton(
                          tooltip: '切换禁用状态 (Ctrl+/)',
                          label: '~',
                          onTap: () => PromptEditActions.toggleDisabled(
                            controller,
                            onChanged,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _QuickActionButton(
                          tooltip: '格式化与SD语法转换 (Ctrl+Shift+F)',
                          icon: Icons.auto_fix_high_outlined,
                          onTap: () => PromptEditActions.formatPrompt(
                            controller,
                            onChanged,
                          ),
                        ),
                        const SizedBox(width: 4),
                        _QuickActionButton(
                          tooltip: '打开 Danbooru 标签灵感库',
                          icon: Icons.style_outlined,
                          onTap: () => _openTagBrowser(context),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          AppProgressBar(
            value: (tokenEstimate / tokenLimit).clamp(0.0, 1.0),
            height: 3,
          ),
        ],
      ),
    );
  }
}

/// 快捷小按钮
class _QuickActionButton extends StatelessWidget {
  final String? label;
  final IconData? icon;
  final String tooltip;
  final VoidCallback onTap;

  const _QuickActionButton({
    this.label,
    this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: Material(
        color: colors.canvasBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          hoverColor: colors.primary.withValues(alpha: 0.1),
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border.all(color: colors.borderSubtle),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: icon != null
                ? Icon(icon, size: 13, color: colors.textSecondary)
                : Text(
                    label ?? '',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}

/// 只读标签面板 (灰底 + 与输入区隔开的细分割线)
class _TagPanel extends StatelessWidget {
  final List<GrayTag> tags;
  final bool atTop;

  const _TagPanel({required this.tags, required this.atTop});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colors.mutedBackground.withValues(alpha: atTop ? 0.5 : 0.35),
        border: atTop
            ? Border(bottom: BorderSide(color: colors.borderSubtle))
            : Border(top: BorderSide(color: colors.borderSubtle)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < tags.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            _TagRow(tag: tags[i]),
          ],
        ],
      ),
    );
  }
}

/// 单行只读标签：胶囊徽标 + 灰色文本
class _TagRow extends StatelessWidget {
  final GrayTag tag;

  const _TagRow({required this.tag});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1.5, right: 6),
          child: AppBadge(
            label: tag.label,
            variant: AppBadgeVariant.neutral,
            shape: AppBadgeShape.rounded,
            fontSize: 10,
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          ),
        ),
        Expanded(
          child: Text(
            tag.text,
            style: TextStyle(
              fontSize: 13,
              height: 1.4,
              color: colors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
