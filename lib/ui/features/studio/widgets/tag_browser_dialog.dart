import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../data/models/tag_models.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../core/theme/app_theme.dart';
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
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.35),
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
    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 40, vertical: 40),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 600),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部搜索与标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Row(
                children: [
                  const Icon(
                    Icons.style_outlined,
                    color: AppTheme.notionBlue,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Danbooru 标签灵感库',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SizedBox(
                      height: 34,
                      child: TextField(
                        controller: _searchController,
                        onChanged: _onSearchChanged,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          hintText: '输入英文或中文搜索 14万+ Danbooru 标签...',
                          hintStyle: const TextStyle(
                            fontSize: 12.5,
                            color: AppTheme.textMuted,
                          ),
                          prefixIcon: const Icon(
                            Icons.search,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                          suffixIcon: _searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 14),
                                  onPressed: () {
                                    _searchController.clear();
                                    _onSearchChanged('');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: AppTheme.paperWarmth,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusButton,
                            ),
                            borderSide: const BorderSide(
                              color: AppTheme.border,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusButton,
                            ),
                            borderSide: const BorderSide(
                              color: AppTheme.border,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppTheme.radiusButton,
                            ),
                            borderSide: const BorderSide(
                              color: AppTheme.notionBlue,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  IconButton(
                    icon: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.borderSubtle),

            // 主体内容
            Expanded(
              child: _isSearching
                  ? _buildSearchResults()
                  : _buildPresetBrowser(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchResults() {
    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          '未找到匹配标签',
          style: TextStyle(color: AppTheme.textMuted, fontSize: 13),
        ),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      itemCount: _searchResults.length,
      separatorBuilder: (context, index) =>
          const Divider(height: 1, color: AppTheme.borderSubtle),
      itemBuilder: (context, index) {
        final item = _searchResults[index];
        return InkWell(
          onTap: () => _addTag(item.tag),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
            child: Row(
              children: [
                TagCategoryPill(category: item.category, fontSize: 10.5),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        item.tag,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      if (widget.showTranslation &&
                          item.translation != null &&
                          item.translation!.isNotEmpty)
                        Text(
                          item.translation!,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                    ],
                  ),
                ),
                TagCountText(formattedCount: item.formattedCount, fontSize: 11),
                const SizedBox(width: 8),
                const Icon(
                  Icons.add_circle_outline,
                  size: 16,
                  color: AppTheme.notionBlue,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPresetBrowser() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 左侧分类导航
        Container(
          width: 160,
          decoration: const BoxDecoration(
            color: AppTheme.paperWarmth,
            border: Border(right: BorderSide(color: AppTheme.borderSubtle)),
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
                    color: isSelected ? AppTheme.pureWhite : Colors.transparent,
                    border: isSelected
                        ? const Border(
                            left: BorderSide(
                              color: AppTheme.notionBlue,
                              width: 3,
                            ),
                          )
                        : null,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        group.icon,
                        size: 15,
                        color: isSelected
                            ? AppTheme.notionBlue
                            : AppTheme.textSecondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        group.title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: isSelected
                              ? AppTheme.notionBlue
                              : AppTheme.textPrimary,
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
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
    return Material(
      color: AppTheme.paperWarmth,
      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        hoverColor: AppTheme.notionBlue.withValues(alpha: 0.1),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.border),
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
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
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  if (zh.isNotEmpty)
                    Text(
                      zh,
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTheme.textMuted,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 6),
              const Icon(Icons.add, size: 14, color: AppTheme.notionBlue),
            ],
          ),
        ),
      ),
    );
  }
}
