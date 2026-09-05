import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../data/models/tag_models.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_search_field.dart';
import 'tag_inspiration_presets.dart';
import 'tag_suggestion_tile.dart';

/// 标签灵感浏览器弹窗
class TagBrowserDialog extends StatefulWidget {
  final ValueChanged<String> onTagSelected;

  /// 是否显示中文释义 (设置项控制)
  final bool showTranslation;

  const TagBrowserDialog({
    super.key,
    required this.onTagSelected,
    this.showTranslation = true,
  });

  static Future<void> show(
    BuildContext context, {
    required ValueChanged<String> onTagSelected,
    bool showTranslation = true,
  }) {
    return AppDialogScaffold.show(
      context: context,
      builder: (ctx) => TagBrowserDialog(
        onTagSelected: onTagSelected,
        showTranslation: showTranslation,
      ),
    );
  }

  @override
  State<TagBrowserDialog> createState() => _TagBrowserDialogState();
}

class _TagBrowserDialogState extends State<TagBrowserDialog> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _searchDebounce;
  List<TagSuggestion> _searchResults = [];
  bool _isSearching = false;
  int _activeCategoryIndex = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final q = query.trim();

    if (q.isEmpty) {
      setState(() {
        _isSearching = false;
        _searchResults = const [];
      });
      return;
    }

    // 防抖后搜索，并在写回前校验查询词未过期 (防止慢请求覆盖新结果)
    _searchDebounce = Timer(const Duration(milliseconds: 120), () async {
      final results = await TagDictionaryService.instance.search(q, limit: 30);
      if (!mounted || _searchController.text.trim() != q) return;
      setState(() => _searchResults = results);
    });

    if (!_isSearching) setState(() => _isSearching = true);
  }

  void _addTag(String tag, [String? zh]) {
    widget.onTagSelected(tag);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: zh == null ? Text('已添加标签: $tag') : Text('已添加标签: $tag ($zh)'),
        duration: const Duration(milliseconds: 900),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return AppDialogScaffold(
      title: 'Danbooru 标签灵感库',
      width: 720,
      height: 600,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部搜索条
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
            child: AppSearchField(
              controller: _searchController,
              hintText: '输入英文或中文搜索 14万+ Danbooru 标签...',
              debounceDuration: const Duration(milliseconds: 120),
              onChanged: _onSearchChanged,
              onClear: () {
                _searchController.clear();
                _onSearchChanged('');
              },
            ),
          ),
          Divider(height: 1, color: colors.borderDefault),

          // 主体内容
          Expanded(
            child: _isSearching
                ? _buildSearchResults(context)
                : _buildPresetBrowser(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final colors = context.colors;
    if (_searchResults.isEmpty) {
      return const AppEmptyState(
        icon: Icons.search_off_outlined,
        title: '未找到匹配标签',
        description: '请尝试输入其他英文或中文关键词检索',
        isCompact: true,
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) =>
          Divider(height: 1, color: colors.borderDefault),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return InkWell(
          onTap: () => _addTag(item.tag),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          hoverColor: colors.primaryTint.withValues(alpha: 0.5),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              children: [
                TagCategoryPill(category: item.category, fontSize: 11),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.tag,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (widget.showTranslation &&
                          item.translation != null &&
                          item.translation!.isNotEmpty)
                        Text(
                          item.translation!,
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                TagCountText(formattedCount: item.formattedCount, fontSize: 11),
                const SizedBox(width: 8),
                Icon(Icons.add_circle_outline, size: 16, color: colors.primary),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetBrowser(BuildContext context) {
    final colors = context.colors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧分类导航
        Container(
          width: 160,
          decoration: BoxDecoration(
            color: colors.mutedBackground,
            border: Border(right: BorderSide(color: colors.borderDefault)),
          ),
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: kTagInspirationPresets.length,
            itemBuilder: (context, index) {
              final group = kTagInspirationPresets[index];
              final isSelected = index == _activeCategoryIndex;

              return InkWell(
                onTap: () => setState(() => _activeCategoryIndex = index),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? colors.cardBackground
                        : Colors.transparent,
                    border: isSelected
                        ? Border(
                            left: BorderSide(color: colors.primary, width: 3),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        group.icon,
                        size: 15,
                        color: isSelected
                            ? colors.primary
                            : colors.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        group.title,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? colors.primary
                              : colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        // 右侧标签卡片列表
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                kTagInspirationPresets[_activeCategoryIndex].title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final (tag, zh)
                      in kTagInspirationPresets[_activeCategoryIndex].tags)
                    _TagChipItem(
                      tag: tag,
                      zh: widget.showTranslation ? zh : '',
                      onTap: () => _addTag(tag, zh),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _TagChipItem extends StatelessWidget {
  final String tag;
  final String zh;
  final VoidCallback onTap;

  const _TagChipItem({
    required this.tag,
    required this.zh,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: colors.cardBackground,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        hoverColor: colors.primaryTint.withValues(alpha: 0.6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: colors.borderDefault),
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tag,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  if (zh.isNotEmpty)
                    Text(
                      zh,
                      style: TextStyle(fontSize: 11, color: colors.textMuted),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              Icon(Icons.add, size: 14, color: colors.primary),
            ],
          ),
        ),
      ),
    );
  }
}
