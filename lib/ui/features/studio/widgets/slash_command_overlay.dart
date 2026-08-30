import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../view_models/slash_command_catalog.dart';

/// 一条斜杠指令补全建议
class SlashSuggestion {
  /// 选中后写入输入框的补全文本 (如 "/nai" 或技能 ID)
  final String completion;

  /// 列表中展示的主标题
  final String title;

  /// 列表中展示的说明文字
  final String description;

  const SlashSuggestion({
    required this.completion,
    required this.title,
    required this.description,
  });
}

/// 根据输入框文本计算补全建议 (纯函数，便于单元测试):
/// - 文本以 "/" 开头且尚无空格: 按前缀匹配指令名
/// - "/skill" 或 "/preset" 后的第一个参数: 按前缀匹配技能 ID/名称或预设
/// - 其余情况返回空列表
List<SlashSuggestion> buildSlashSuggestions({
  required String text,
  required List<Skill> skills,
  required List<AgentPreset> presets,
}) {
  if (!text.startsWith('/')) return const [];

  final spaceIdx = text.indexOf(' ');
  if (spaceIdx == -1) {
    // 指令名补全
    final query = text.substring(1).toLowerCase();
    return kSlashCommands
        .where((c) => c.name.substring(1).startsWith(query))
        .map(
          (c) => SlashSuggestion(
            completion: c.name,
            title: c.displayTitle,
            description: c.description,
          ),
        )
        .toList();
  }

  // 参数补全: 仅支持 /skill 与 /preset 的第一个参数
  final cmd = text.substring(0, spaceIdx).toLowerCase();
  final args = text.substring(spaceIdx + 1);
  if (args.contains(' ')) return const [];
  final query = args.toLowerCase();

  switch (cmd) {
    case '/skill':
      return skills
          .where(
            (s) =>
                s.id.toLowerCase().startsWith(query) ||
                s.name.toLowerCase().startsWith(query),
          )
          .map(
            (s) => SlashSuggestion(
              completion: s.id,
              title: s.name == s.id ? s.id : '${s.name} (${s.id})',
              description: s.description,
            ),
          )
          .toList();
    case '/preset':
      return presets
          .where(
            (p) =>
                p.id.toLowerCase().startsWith(query) ||
                p.name.toLowerCase().startsWith(query),
          )
          .map(
            (p) => SlashSuggestion(
              completion: p.id,
              title: p.name,
              description: p.description,
            ),
          )
          .toList();
  }
  return const [];
}

/// 悬浮在输入框上方的补全列表面板
class SlashSuggestionPanel extends StatelessWidget {
  final List<SlashSuggestion> suggestions;
  final int selectedIndex;

  /// 点击某条建议
  final ValueChanged<int> onSelected;

  /// 鼠标悬停某条建议 (用于同步高亮，不抢键盘焦点)
  final ValueChanged<int>? onHovered;

  const SlashSuggestionPanel({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.onSelected,
    this.onHovered,
  });

  static const double rowHeight = 34.0;
  static const int maxVisibleRows = 6;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      clipBehavior: Clip.antiAlias,
      color: AppTheme.pureWhite,
      child: Container(
        constraints: BoxConstraints(maxHeight: rowHeight * maxVisibleRows),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border),
        ),
        child: ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: suggestions.length,
          itemExtent: rowHeight,
          itemBuilder: (context, index) {
            final suggestion = suggestions[index];
            final isSelected = index == selectedIndex;
            return InkWell(
              onTap: () => onSelected(index),
              onHover: (_) => onHovered?.call(index),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                color: isSelected
                    ? AppTheme.notionBlue.withValues(alpha: 0.08)
                    : Colors.transparent,
                child: Row(
                  children: [
                    Container(
                      width: 3,
                      height: 18,
                      margin: const EdgeInsets.only(right: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.notionBlue
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Expanded(
                      flex: 3,
                      child: Text(
                        suggestion.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 4,
                      child: Text(
                        suggestion.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
