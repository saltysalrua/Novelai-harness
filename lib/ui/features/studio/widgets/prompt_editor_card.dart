import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import 'studio_shared.dart';

/// 只读灰色标签数据 (PREFIX / SUFFIX / QUALITY / BG / UC 预设词展示)
class GrayTag {
  final String label;
  final String text;

  const GrayTag(this.label, this.text);
}

/// 提示词编辑卡：只读标签头 + 主输入框 + 只读标签脚 + 工具条 + Token 进度条。
/// 正向提示词与负面排除词、垂直堆叠与标签页两种布局共用同一张卡。
class PromptEditorCard extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String hintText;

  /// 输入框行数范围 (堆叠模式较矮，标签页模式较高)
  final int minLines;
  final int maxLines;

  /// 输入框上方只读标签 (如 PREFIX 前置词)
  final List<GrayTag> headerTags;

  /// 输入框下方只读标签 (如 SUFFIX / QUALITY / BG 或官方 UC 预设词)
  final List<GrayTag> footerTags;

  /// 底部工具条 (胶囊开关与预设下拉等)
  final Widget? toolbar;

  /// Token 估算值，用于底部进度条
  final int tokenEstimate;

  /// Token 上限 (按模型分词器区分)
  final int tokenLimit;

  const PromptEditorCard({
    super.key,
    required this.controller,
    required this.onChanged,
    required this.hintText,
    this.minLines = 4,
    this.maxLines = 10,
    this.headerTags = const [],
    this.footerTags = const [],
    this.toolbar,
    required this.tokenEstimate,
    this.tokenLimit = 225,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (headerTags.isNotEmpty) _TagPanel(tags: headerTags, atTop: true),
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: controller,
              minLines: minLines,
              maxLines: maxLines,
              style: const TextStyle(
                fontSize: 13,
                height: 1.45,
                color: AppTheme.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: const TextStyle(
                  fontSize: 12.5,
                  color: AppTheme.textMuted,
                ),
                contentPadding: EdgeInsets.zero,
                isDense: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onChanged: onChanged,
            ),
          ),
          if (footerTags.isNotEmpty) _TagPanel(tags: footerTags, atTop: false),
          if (toolbar != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: toolbar,
            ),
          TokenProgressBar(tokens: tokenEstimate, tokenLimit: tokenLimit),
        ],
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted.withValues(alpha: atTop ? 0.5 : 0.35),
        border: atTop
            ? const Border(bottom: BorderSide(color: AppTheme.borderSubtle))
            : const Border(top: BorderSide(color: AppTheme.borderSubtle)),
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
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.only(top: 1, right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
          decoration: BoxDecoration(
            color: AppTheme.borderSubtle,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            tag.label,
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: AppTheme.textMuted,
            ),
          ),
        ),
        Expanded(
          child: Text(
            tag.text,
            style: const TextStyle(
              fontSize: 12,
              height: 1.4,
              color: AppTheme.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}
