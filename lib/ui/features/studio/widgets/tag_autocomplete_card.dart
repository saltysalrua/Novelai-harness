import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/tag_models.dart';
import '../../../core/theme/app_theme.dart';
import 'tag_suggestion_tile.dart';

/// 自动补全浮动卡片视图 (Notion 极简风格，无多余头部，支持键盘自然平滑可视导航)
class TagAutocompleteCard extends StatefulWidget {
  final List<TagSuggestion> suggestions;
  final int selectedIndex;
  final String query;

  /// 是否显示中文释义 (设置项控制)
  final bool showTranslation;

  /// 是否为键盘按键导航触发 (键盘导航时平滑滚动入视野，鼠标 hover 绝不触发滚动)
  final bool isKeyboardNavigated;

  final ValueChanged<TagSuggestion> onSelect;
  final ValueChanged<int> onHover;

  const TagAutocompleteCard({
    super.key,
    required this.suggestions,
    required this.selectedIndex,
    required this.query,
    this.showTranslation = true,
    this.isKeyboardNavigated = false,
    required this.onSelect,
    required this.onHover,
  });

  @override
  State<TagAutocompleteCard> createState() => _TagAutocompleteCardState();
}

class _TagAutocompleteCardState extends State<TagAutocompleteCard> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = [];
  Offset? _lastPointerPos;
  DateTime? _lastKeyboardNavTime;

  @override
  void initState() {
    super.initState();
    _updateKeys();
  }

  @override
  void didUpdateWidget(covariant TagAutocompleteCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.suggestions.length != widget.suggestions.length) {
      _updateKeys();
    }
    // 仅在键盘上下键导航时才检查滚动入视野，鼠标 hover 绝不触发滚动
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        widget.isKeyboardNavigated) {
      _lastKeyboardNavTime = DateTime.now();
      _scrollToIndex(widget.selectedIndex);
    }
  }

  void _handlePointerHover(PointerHoverEvent event, int index) {
    // 1. 若最近 250ms 内刚发生过键盘导航，忽略滚动引起的被动 hover
    if (_lastKeyboardNavTime != null &&
        DateTime.now().difference(_lastKeyboardNavTime!).inMilliseconds < 250) {
      _lastPointerPos = event.position;
      return;
    }

    // 2. 检查鼠标是否真的在屏幕上有物理位移 (防止列表滚动时静止鼠标被动触发)
    if (_lastPointerPos != null) {
      final delta = (event.position - _lastPointerPos!).distance;
      if (delta < 2.5) {
        return;
      }
    }

    _lastPointerPos = event.position;
    widget.onHover(index);
  }

  void _updateKeys() {
    _itemKeys.clear();
    for (int i = 0; i < widget.suggestions.length; i++) {
      _itemKeys.add(GlobalKey());
    }
  }

  void _scrollToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index >= 0 && index < _itemKeys.length) {
        final keyContext = _itemKeys[index].currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(
            keyContext,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          border: Border.all(color: AppTheme.border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 18,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 320),
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: ListView.separated(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 4),
              shrinkWrap: true,
              itemCount: widget.suggestions.length,
              separatorBuilder: (context, index) =>
                  const Divider(height: 1, color: AppTheme.borderSubtle),
              itemBuilder: (context, index) {
                final item = widget.suggestions[index];
                final isSelected = index == widget.selectedIndex;
                final itemKey = index < _itemKeys.length
                    ? _itemKeys[index]
                    : null;

                return Container(
                  key: itemKey,
                  child: MouseRegion(
                    onHover: (e) => _handlePointerHover(e, index),
                    cursor: SystemMouseCursors.click,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (_) {
                        // 立即在 pointer down 时执行精准上屏
                        widget.onSelect(item);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        color: isSelected
                            ? AppTheme.notionBlue.withValues(alpha: 0.08)
                            : Colors.transparent,
                        child: Row(
                          children: [
                            // 分类标识胶囊
                            TagCategoryPill(
                              category: item.category,
                              customLabel: item.customCategoryLabel,
                            ),
                            const SizedBox(width: 8),

                            // 英文 Tag + 匹配高亮
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _buildHighlightedTag(
                                    item.tag,
                                    widget.query,
                                    isSelected,
                                  ),
                                  if (widget.showTranslation &&
                                      item.translation != null &&
                                      item.translation!.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 1),
                                      child: Text(
                                        item.translation!,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: isSelected
                                              ? AppTheme.notionBlue
                                              : AppTheme.textSecondary,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            // 词库特殊标识 / 别名 / 热度统计
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (item.isPromptCombo)
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF0EFEB),
                                      borderRadius: BorderRadius.circular(4),
                                      border: Border.all(
                                        color: AppTheme.graphite
                                            .withValues(alpha: 0.3),
                                      ),
                                    ),
                                    child: const Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.collections_bookmark_outlined,
                                          size: 10,
                                          color: AppTheme.charcoal,
                                        ),
                                        SizedBox(width: 3),
                                        Text(
                                          '词库',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            fontWeight: FontWeight.w600,
                                            color: AppTheme.charcoal,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                else
                                  TagCountText(
                                    formattedCount: item.formattedCount,
                                  ),
                                if (item.matchedAlias != null)
                                  Text(
                                    '别名: ${item.matchedAlias}',
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      color: AppTheme.textMuted,
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHighlightedTag(String tag, String q, bool isSelected) {
    final lowerTag = tag.toLowerCase();
    final lowerQ = q.toLowerCase();
    final matchIndex = lowerTag.indexOf(lowerQ);

    if (matchIndex < 0) {
      return Text(
        tag,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? AppTheme.notionBlue : AppTheme.textPrimary,
        ),
      );
    }

    final before = tag.substring(0, matchIndex);
    final match = tag.substring(matchIndex, matchIndex + q.length);
    final after = tag.substring(matchIndex + q.length);

    return Text.rich(
      TextSpan(
        style: TextStyle(
          fontSize: 12.5,
          fontFamily: AppTheme.fontFamily,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          color: isSelected ? AppTheme.notionBlue : AppTheme.textPrimary,
        ),
        children: [
          if (before.isNotEmpty) TextSpan(text: before),
          TextSpan(
            text: match,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
            ),
          ),
          if (after.isNotEmpty) TextSpan(text: after),
        ],
      ),
    );
  }
}
