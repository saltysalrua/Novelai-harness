import 'dart:async';
import 'package:flutter/material.dart';
import '../../../../data/models/tag_models.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
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
  final SmoothWheelScrollController _presetScrollController =
      SmoothWheelScrollController();
  final SmoothWheelScrollController _searchScrollController =
      SmoothWheelScrollController();
  Timer? _searchDebounce;
  List<TagSuggestion> _searchResults = [];
  bool _isSearching = false;
  int _activeCategoryIndex = 0;

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _presetScrollController.dispose();
    _searchScrollController.dispose();
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
    final l10n = context.l10n;
    showAppToast(
      context,
      message: zh == null
          ? l10n.tagBrowserAddedTag(tag)
          : l10n.tagBrowserAddedTagWithZh(tag, zh),
      tone: AppToastTone.success,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return AppDialogScaffold(
      minimalChrome: true,
      title: l10n.tagBrowserTitle,
      width: 720,
      height: 600,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部搜索条
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
            child: AppSearchField(
              controller: _searchController,
              hintText: l10n.tagBrowserSearchHint,
              debounceDuration: const Duration(milliseconds: 120),
              onChanged: _onSearchChanged,
              onClear: () {
                _searchController.clear();
                _onSearchChanged('');
              },
            ),
          ),
          Divider(height: 1, color: colors.borderSubtle),

          // 主体内容 (使用 AppPageStack 单向入场，避免双视图叠影残留)
          Expanded(
            child: AppPageStack(
              index: _isSearching ? 1 : 0,
              itemCount: 2,
              itemBuilder: (context, index) => index == 1
                  ? _buildSearchResults(context)
                  : _buildPresetBrowser(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    if (_searchResults.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off_outlined,
        title: l10n.tagBrowserNoMatchingTitle,
        isCompact: true,
      );
    }

    return ListView.separated(
      controller: _searchScrollController,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
    final l10n = context.l10n;
    final tagList = ListView(
      controller: _presetScrollController,
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (tag, zh)
                in kTagInspirationGroups[_activeCategoryIndex].tags)
              _TagChipItem(
                tag: tag,
                zh: widget.showTranslation ? zh : '',
                onTap: () => _addTag(tag, zh),
              ),
          ],
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: AppSegmentedPillBar<int>(
                  scrollable: true,
                  variant: AppPillVariant.soft,
                  selectedValue: _activeCategoryIndex,
                  onValueChanged: (index) =>
                      setState(() => _activeCategoryIndex = index),
                  items: [
                    for (var i = 0; i < kTagInspirationGroups.length; i++)
                      AppSegmentedItem<int>(
                        value: i,
                        icon: kTagInspirationGroups[i].icon,
                        label: kTagInspirationGroups[i].localizedTitle(l10n),
                      ),
                  ],
                ),
              ),
              Expanded(child: tagList),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 左侧分类导航
            Container(
              width: 164,
              decoration: BoxDecoration(
                color: colors.elevatedBackground,
                border: Border(right: BorderSide(color: colors.borderSubtle)),
              ),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: kTagInspirationGroups.length,
                itemBuilder: (context, index) {
                  final group = kTagInspirationGroups[index];
                  final isSelected = index == _activeCategoryIndex;

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: AppNavTile(
                      icon: group.icon,
                      title: group.localizedTitle(l10n),
                      isSelected: isSelected,
                      onTap: () => setState(() => _activeCategoryIndex = index),
                    ),
                  );
                },
              ),
            ),

            // 右侧标签卡片列表
            Expanded(child: tagList),
          ],
        );
      },
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
        child: AnimatedContainer(
          duration: AppMotion.resolveDuration(
            context,
            AppMotionDurations.quick,
          ),
          curve: AppMotionCurves.smoothOut,
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
