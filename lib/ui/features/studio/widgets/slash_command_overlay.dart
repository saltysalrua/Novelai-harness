import 'package:flutter/material.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_autocomplete_panel.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../l10n/app_localizations.dart';
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
///
/// 传 [l10n] 时指令名补全的标题/说明本地化；技能与预设的说明属
/// 数据域文本原样透传。缺省 l10n 回退中文数据域文案。
List<SlashSuggestion> buildSlashSuggestions({
  required String text,
  required List<Skill> skills,
  required List<AgentPreset> presets,
  AppLocalizations? l10n,
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
            title: l10n != null
                ? c.localizedDisplayTitle(l10n)
                : c.displayTitle,
            description: l10n != null
                ? slashCommandDescriptionOf(l10n, c)
                : c.description,
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

/// 斜杠指令 OverlayPortal 菜单弹出容器 (Recipe 05: 0.97->1.0 开场，1.0->0.99 轻快退场；
/// 仅用 Transform.scale，首帧即保留面板完整布局尺寸)。
class SlashCommandOverlayShell extends StatefulWidget {
  final bool visible;
  final VoidCallback? onDismissComplete;
  final Alignment alignment;
  final Widget child;

  const SlashCommandOverlayShell({
    super.key,
    required this.visible,
    required this.child,
    this.onDismissComplete,
    this.alignment = Alignment.bottomLeft,
  });

  @override
  State<SlashCommandOverlayShell> createState() =>
      _SlashCommandOverlayShellState();
}

class _SlashCommandOverlayShellState extends State<SlashCommandOverlayShell>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.dropdownOpen,
      reverseDuration: AppMotionDurations.dropdownClose,
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.dismissed &&
          !widget.visible &&
          mounted) {
        widget.onDismissComplete?.call();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation(initial: _controller.value == 0.0 && widget.visible);
  }

  @override
  void didUpdateWidget(SlashCommandOverlayShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _syncAnimation();
    }
  }

  void _syncAnimation({bool initial = false}) {
    final reduce = AppMotion.shouldReduceMotion(context);
    if (reduce) {
      _controller.value = widget.visible ? 1.0 : 0.0;
      if (!widget.visible) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !widget.visible) {
            widget.onDismissComplete?.call();
          }
        });
      }
      return;
    }
    if (widget.visible) {
      if (initial || _controller.status == AnimationStatus.dismissed) {
        _controller.forward(from: 0.0);
      } else {
        _controller.forward();
      }
    } else {
      _controller.reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final closing =
        !widget.visible || _controller.status == AnimationStatus.reverse;
    return IgnorePointer(
      ignoring: !widget.visible,
      child: AnimatedBuilder(
        animation: _controller,
        child: widget.child,
        builder: (context, child) {
          final curve = closing
              ? AppMotionCurves.closeEase
              : AppMotionCurves.smoothOut;
          final t = curve.transform(_controller.value).clamp(0.0, 1.0);
          final startScale = closing
              ? AppMotionScales.dropdownClose
              : AppMotionScales.dropdown;
          final scale = startScale + (1.0 - startScale) * t;
          return Opacity(
            opacity: t,
            child: Transform.scale(
              alignment: widget.alignment,
              scale: scale,
              child: child,
            ),
          );
        },
      ),
    );
  }
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
    final colors = context.colors;

    return AppAutocompletePanel<SlashSuggestion>(
      items: suggestions,
      selectedIndex: selectedIndex,
      maxHeight: rowHeight * maxVisibleRows,
      padding: const EdgeInsets.all(4),
      onSelect: (item) => onSelected(suggestions.indexOf(item)),
      onHover: onHovered,
      itemBuilder: (context, suggestion, index, isSelected) {
        return Container(
          height: rowHeight,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isSelected ? colors.primaryTint : null,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
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
                    color: isSelected ? colors.primary : colors.textPrimary,
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
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
