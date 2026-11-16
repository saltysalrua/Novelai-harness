import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../view_models/studio_view_model.dart';
import 'prompt_combo_card.dart';
import 'prompt_combo_edit_dialog.dart';
import 'studio_shared.dart';

/// 词库全屏沉浸式管理器视图：
/// 单一开放画布 + 顶部内联分类筛选 + 原始比例瀑布流，彻底消除冗余框与分割线。
class PromptLibraryView extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback? onClose;
  final bool connectedLeft;
  final VoidCallback? onExpandSidebar;

  const PromptLibraryView({
    super.key,
    required this.viewModel,
    this.onClose,
    this.connectedLeft = false,
    this.onExpandSidebar,
  });

  @override
  State<PromptLibraryView> createState() => _PromptLibraryViewState();
}

class _PromptLibraryViewState extends State<PromptLibraryView> {
  final TextEditingController _searchController = TextEditingController();
  late final SmoothWheelScrollController _gridScrollController;
  final ValueNotifier<int> _scrollBucket = ValueNotifier<int>(0);

  String _selectedCategory = '全部';
  String _searchQuery = '';

  // 派生状态缓存：避免每次 build 对全量词库重复统计与过滤
  List<PromptComboEntry>? _cachedSourceEntries;
  String? _cachedCategoryFilter;
  String? _cachedQueryFilter;
  List<String> _cachedCategories = const [];
  Map<String, int> _cachedCategoryCounts = const {};
  List<PromptComboEntry> _cachedFilteredEntries = const [];

  @override
  void initState() {
    super.initState();
    _gridScrollController = SmoothWheelScrollController()
      ..addListener(_onGridScrolled);
    _searchController.addListener(_onSearchControllerChanged);
  }

  void _onGridScrolled() {
    if (!_gridScrollController.hasClients) return;
    final nextBucket = (_gridScrollController.offset / 320.0).floor();
    if (nextBucket != _scrollBucket.value) {
      _scrollBucket.value = nextBucket;
    }
  }

  void _onSearchControllerChanged() {
    final q = _searchController.text.trim();
    if (q != _searchQuery) {
      setState(() => _searchQuery = q);
    }
  }

  @override
  void dispose() {
    _gridScrollController.removeListener(_onGridScrolled);
    _gridScrollController.dispose();
    _scrollBucket.dispose();
    _searchController.removeListener(_onSearchControllerChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _ensureDerivedData(List<PromptComboEntry> entries) {
    final entriesChanged = !identical(_cachedSourceEntries, entries);
    if (entriesChanged) {
      final counts = <String, int>{'全部': entries.length};
      final catSet = <String>{'全部', ...PromptComboCategories.defaults};
      for (final entry in entries) {
        final cat = entry.category.trim();
        if (cat.isNotEmpty) {
          catSet.add(cat);
          counts[cat] = (counts[cat] ?? 0) + 1;
        }
      }
      _cachedCategories = catSet.toList(growable: false);
      _cachedCategoryCounts = counts;
    }

    if (entriesChanged ||
        _cachedCategoryFilter != _selectedCategory ||
        _cachedQueryFilter != _searchQuery) {
      final q = _searchQuery.toLowerCase();
      final filterByCategory = _selectedCategory != '全部';
      final filterByQuery = q.isNotEmpty;

      if (!filterByCategory && !filterByQuery) {
        _cachedFilteredEntries = entries;
      } else {
        _cachedFilteredEntries = entries
            .where((e) {
              if (filterByCategory && e.category.trim() != _selectedCategory) {
                return false;
              }
              if (filterByQuery) {
                final matchTitle = e.title.toLowerCase().contains(q);
                final matchPrompt = e.prompt.toLowerCase().contains(q);
                final matchNegative = e.negativePrompt.toLowerCase().contains(
                  q,
                );
                final matchCategory = e.category.toLowerCase().contains(q);
                final matchTags = e.tags.any((t) => t.toLowerCase().contains(q));
                if (!matchTitle &&
                    !matchPrompt &&
                    !matchNegative &&
                    !matchCategory &&
                    !matchTags) {
                  return false;
                }
              }
              return true;
            })
            .toList(growable: false);
      }

      _cachedSourceEntries = entries;
      _cachedCategoryFilter = _selectedCategory;
      _cachedQueryFilter = _searchQuery;
    }
  }

  Future<void> _handleExport() async {
    final l10n = context.l10n;
    try {
      final jsonStr = await widget.viewModel.exportPromptLibraryJson();
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (!mounted) return;
      showAppToast(
        context,
        message: l10n.libraryExportCopied,
        tone: AppToastTone.success,
        duration: const Duration(seconds: 2),
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: l10n.libraryExportFailed(e.toString()),
        tone: AppToastTone.error,
        duration: const Duration(seconds: 2),
      );
    }
  }

  Future<void> _handleImport() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
    try {
      final result = await AppDialogScaffold.show<bool>(
        context: context,
        builder: (ctx) => AppDialogScaffold(
          title: l10n.libraryImportDialogTitle,
          width: 480,
          body: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.libraryImportPrompt,
                  style: TextStyle(fontSize: 12, color: ctx.colors.textSecondary),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  maxLines: 6,
                  style: TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    color: ctx.colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: '[{"title": "...", "prompt": "..."}]',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: ctx.colors.textMuted,
                    ),
                    filled: true,
                    fillColor: ctx.colors.elevatedBackground,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      borderSide: BorderSide(
                        color: ctx.colors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            AppActionButton(
              label: l10n.cancel,
              variant: AppActionButtonVariant.ghost,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            const SizedBox(width: 8),
            AppActionButton(
              label: l10n.import,
              variant: AppActionButtonVariant.primary,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        ),
      );

      final text = controller.text.trim();
      if (result == true && text.isNotEmpty) {
        try {
          final count = await widget.viewModel.importPromptLibraryJson(text);
          if (!mounted) return;
          showAppToast(
            context,
            message: l10n.libraryImportSuccess(count),
            tone: AppToastTone.success,
            duration: const Duration(seconds: 2),
          );
        } catch (e) {
          if (!mounted) return;
          showAppToast(
            context,
            message: l10n.libraryImportFailed(e.toString()),
            tone: AppToastTone.error,
            duration: const Duration(seconds: 2),
          );
        }
      }
    } finally {
      controller.dispose();
    }
  }

  void _applyCombo(
    PromptComboEntry combo, {
    bool replace = false,
    bool asCharacter = false,
  }) {
    final l10n = context.l10n;
    widget.viewModel.applyPromptCombo(
      combo,
      replace: replace,
      asCharacter: asCharacter,
    );

    String message;
    if (asCharacter) {
      message = l10n.libraryApplyAsCharacter(combo.title);
    } else if (replace) {
      message = l10n.libraryApplyReplace(combo.title);
    } else {
      message = combo.isCharacter && combo.negativePrompt.isNotEmpty
          ? l10n.libraryApplyAppendBoth(combo.title)
          : l10n.libraryApplyAppendPrompt(combo.title);
    }

    showAppToast(
      context,
      message: message,
      tone: AppToastTone.success,
      duration: const Duration(milliseconds: 1400),
      actionLabel: widget.onClose != null
          ? l10n.libraryReturnToWorkbench
          : null,
      onAction: widget.onClose,
    );
  }

  Future<void> _confirmDelete(PromptComboEntry combo) async {
    final l10n = context.l10n;
    final ok = await showAppConfirmDialog(
      context,
      title: l10n.libraryDeleteDialogTitle,
      message: l10n.libraryDeleteDialogMessage(combo.title),
      confirmLabel: l10n.delete,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );

    if (ok == true) {
      await widget.viewModel.deletePromptCombo(combo.id);
      if (!mounted) return;
      showAppToast(
        context,
        message: l10n.libraryDeletedCombo(combo.title),
        tone: AppToastTone.info,
        duration: const Duration(milliseconds: 1200),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        if (TickerMode.valuesOf(context).enabled)
          widget.viewModel.promptLibraryNotifier,
      ]),
      builder: (context, _) {
        final colors = context.colors;
        final allEntries = widget.viewModel.promptLibraryEntries;
        _ensureDerivedData(allEntries);
        final categories = _cachedCategories;
        final counts = _cachedCategoryCounts;
        final filtered = _cachedFilteredEntries;

        return Container(
          margin: widget.connectedLeft
              ? const EdgeInsets.fromLTRB(0, 8, 8, 8)
              : const EdgeInsets.all(8),
          decoration: ShapeDecoration(
            color: colors.canvasBackground,
            shape: StudioPanelShapeBorder(
              outerSide: BorderSide(color: colors.borderDefault),
              radius: AppRadius.lg,
              roundLeft: !widget.connectedLeft,
              roundRight: true,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 开放式顶栏与内联分类筛选 (同一画布，零分隔线、零套壳)
              _buildHeader(context, allEntries.length),
              _buildCategoryBar(context, categories, counts),

              // 2. 瀑布流画廊主体
              Expanded(
                child: filtered.isEmpty
                    ? _buildEmptyState(context, allEntries.isEmpty)
                    : _buildMasonryGallery(filtered),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, int totalCount) {
    final colors = context.colors;
    final l10n = context.l10n;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;

        final title = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.onExpandSidebar != null) ...[
              AppIconButton(
                key: const Key('library_expand_sidebar_button'),
                icon: Icons.keyboard_double_arrow_right_rounded,
                size: 30,
                iconSize: 17,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.sidebarExpandTooltip,
                onPressed: widget.onExpandSidebar,
              ),
              const SizedBox(width: 2),
            ],
            if (widget.onClose != null) ...[
              _buildCloseButton(context, compact: isNarrow),
              const SizedBox(width: 4),
            ],
            Icon(
              Icons.collections_bookmark_outlined,
              size: 18,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                l10n.tabLibrary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$totalCount',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textMuted,
              ),
            ),
          ],
        );

        final searchField = AppSearchField(
          controller: _searchController,
          hintText: l10n.librarySearchHint,
          debounceDuration: const Duration(milliseconds: 150),
          onChanged: (val) {
            final q = val.trim();
            if (q != _searchQuery) {
              setState(() => _searchQuery = q);
            }
          },
          onClear: () {
            setState(() => _searchQuery = '');
          },
        );

        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    _buildManageMenu(context, compact: true),
                    const SizedBox(width: 6),
                    _buildNewComboButton(context, compact: true),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(height: 34, child: searchField),
              ],
            ),
          );
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 8),
          child: Row(
            children: [
              Expanded(child: title),
              const SizedBox(width: 16),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: searchField,
                ),
              ),
              const SizedBox(width: 10),
              _buildManageMenu(context, compact: false),
              const SizedBox(width: 8),
              _buildNewComboButton(context, compact: false),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCategoryBar(
    BuildContext context,
    List<String> categories,
    Map<String, int> counts,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return Padding(
          padding: isNarrow
              ? const EdgeInsets.fromLTRB(12, 0, 12, 8)
              : const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: AppSegmentedPillBar<String>(
            scrollable: true,
            variant: AppPillVariant.soft,
            itemPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            selectedValue: _selectedCategory,
            onValueChanged: (cat) {
              setState(() => _selectedCategory = cat);
              if (_gridScrollController.hasClients) {
                _gridScrollController.jumpTo(0);
              }
            },
            items: [
              for (final cat in categories)
                AppSegmentedItem<String>(
                  value: cat,
                  label: comboCategoryLabelOf(l10n, cat),
                  tooltip: comboCategoryLabelOf(l10n, cat),
                  icon: _getCategoryIcon(cat),
                  activeColor: PromptComboEntry.isCharacterCategory(cat)
                      ? colors.error
                      : null,
                  badgeLabel: '${counts[cat] ?? 0}',
                ),
            ],
          ),
        );
      },
    );
  }

  /// 导入/导出菜单 (轻量底色，无边框)
  Widget _buildManageMenu(BuildContext context, {required bool compact}) {
    final colors = context.colors;
    final l10n = context.l10n;
    return PopupMenuButton<String>(
      tooltip: l10n.libraryDataManagement,
      onSelected: (val) {
        if (val == 'export') _handleExport();
        if (val == 'import') _handleImport();
      },
      itemBuilder: (ctx) => [
        PopupMenuItem(
          value: 'export',
          child: Row(
            children: [
              Icon(
                Icons.file_download_outlined,
                size: 16,
                color: colors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.libraryExportJson,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'import',
          child: Row(
            children: [
              Icon(
                Icons.file_upload_outlined,
                size: 16,
                color: colors.textPrimary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.libraryImportJson,
                style: const TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ],
      child: Container(
        padding: compact
            ? const EdgeInsets.symmetric(horizontal: 8, vertical: 7)
            : const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.more_horiz, size: 16, color: colors.textSecondary),
            if (!compact) ...[
              const SizedBox(width: 4),
              Text(
                l10n.libraryManageButton,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// + 新建词组合
  Widget _buildNewComboButton(BuildContext context, {required bool compact}) {
    final l10n = context.l10n;
    void openCreateDialog() =>
        PromptComboEditDialog.show(context, viewModel: widget.viewModel);

    if (compact) {
      return AppIconButton(
        icon: Icons.add_rounded,
        size: 34,
        iconSize: 18,
        variant: AppIconButtonVariant.primary,
        tooltip: l10n.libraryNewCombo,
        onPressed: openCreateDialog,
      );
    }
    return AppActionButton(
      icon: Icons.add_rounded,
      iconSize: 16,
      label: l10n.libraryNewCombo,
      variant: AppActionButtonVariant.primary,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      onPressed: openCreateDialog,
    );
  }

  /// 返回工作台
  Widget _buildCloseButton(BuildContext context, {required bool compact}) {
    final l10n = context.l10n;
    if (compact) {
      return AppIconButton(
        key: const Key('library_close_button'),
        icon: Icons.arrow_back_rounded,
        size: 30,
        iconSize: 17,
        variant: AppIconButtonVariant.ghost,
        tooltip: l10n.libraryReturnToWorkbench,
        onPressed: widget.onClose,
      );
    }
    return Tooltip(
      message: l10n.libraryReturnToWorkbench,
      child: AppActionButton(
        key: const Key('library_close_button'),
        icon: Icons.arrow_back_rounded,
        iconSize: 15,
        label: l10n.libraryReturn,
        variant: AppActionButtonVariant.ghost,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        onPressed: widget.onClose,
      ),
    );
  }

  IconData _getCategoryIcon(String cat) {
    return switch (cat.trim().toLowerCase()) {
      '全部' || 'all' => Icons.apps_outlined,
      '角色' || 'character' => Icons.person_outline,
      '风格' || 'style' => Icons.palette_outlined,
      '服装' || 'attire' || 'clothing' => Icons.checkroom_outlined,
      '构图' || 'composition' => Icons.crop_free_outlined,
      '环境' || 'environment' || 'background' => Icons.landscape_outlined,
      '特效' || 'effect' || 'effects' => Icons.auto_awesome_outlined,
      _ => Icons.label_outline,
    };
  }

  Widget _buildMasonryGallery(List<PromptComboEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final hPad = isNarrow ? 12.0 : 20.0;
        const spacing = 14.0;
        final usableWidth = (constraints.maxWidth - hPad * 2).clamp(
          200.0,
          double.infinity,
        );
        final columnCount = (usableWidth / 264.0).floor().clamp(1, 8);
        final columnWidth =
            (usableWidth - (columnCount - 1) * spacing) / columnCount;

        // 按估算高度贪心分列，使瀑布流各列高度保持均衡
        final columns = List.generate(
          columnCount,
          (_) => <_MasonrySlot>[],
          growable: false,
        );
        final colHeights = List<double>.filled(columnCount, 0.0);

        for (final entry in entries) {
          var targetCol = 0;
          for (var c = 1; c < columnCount; c++) {
            if (colHeights[c] < colHeights[targetCol]) {
              targetCol = c;
            }
          }
          final topY = colHeights[targetCol];
          final estHeight = _estimateCardHeight(entry, columnWidth);
          columns[targetCol].add(
            _MasonrySlot(
              entry: entry,
              topY: topY,
              bottomY: topY + estHeight,
            ),
          );
          colHeights[targetCol] = topY + estHeight + spacing;
        }

        final viewportH = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 800.0;

        return SingleChildScrollView(
          controller: _gridScrollController,
          padding: EdgeInsets.fromLTRB(hPad, 4, hPad, 20),
          child: ValueListenableBuilder<int>(
            valueListenable: _scrollBucket,
            builder: (context, bucket, _) {
              final approxOffset = bucket * 320.0;
              final visibleTop = approxOffset - 900.0;
              final visibleBottom = approxOffset + viewportH + 900.0;

              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (var c = 0; c < columnCount; c++) ...[
                    if (c > 0) const SizedBox(width: spacing),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < columns[c].length; i++) ...[
                            if (i > 0) const SizedBox(height: spacing),
                            RepaintBoundary(
                              key: ValueKey(columns[c][i].entry.id),
                              child: PromptComboCard(
                                combo: columns[c][i].entry,
                                loadImage:
                                    columns[c][i].bottomY >= visibleTop &&
                                    columns[c][i].topY <= visibleBottom,
                                onApply: (replace, asChar) => _applyCombo(
                                  columns[c][i].entry,
                                  replace: replace,
                                  asCharacter: asChar,
                                ),
                                onEdit: () {
                                  PromptComboEditDialog.show(
                                    context,
                                    viewModel: widget.viewModel,
                                    initialEntry: columns[c][i].entry,
                                  );
                                },
                                onDelete: () =>
                                    _confirmDelete(columns[c][i].entry),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        );
      },
    );
  }

  double _estimateCardHeight(PromptComboEntry entry, double columnWidth) {
    final path = entry.previewImagePath?.trim();
    if (path == null || path.isEmpty || PromptImageProbe.isKnownMissing(path)) {
      return 96.0;
    }
    final ratio = (PromptImageProbe.getCachedAspectRatio(path) ?? 1.0).clamp(
      0.45,
      2.2,
    );
    return columnWidth / ratio + 96.0;
  }

  Widget _buildEmptyState(BuildContext context, bool isCompletelyEmpty) {
    final l10n = context.l10n;
    return AppEmptyState(
      icon: Icons.collections_bookmark_outlined,
      title: isCompletelyEmpty
          ? l10n.libraryEmptyTitle
          : l10n.libraryNoMatchingTitle,
      description: isCompletelyEmpty
          ? l10n.libraryEmptyDescription
          : l10n.libraryNoMatchingDescription,
      actionLabel: isCompletelyEmpty
          ? l10n.libraryNewCombo
          : l10n.libraryResetFilter,
      actionIcon: isCompletelyEmpty ? Icons.add : Icons.refresh,
      onActionPressed: () {
        if (isCompletelyEmpty) {
          PromptComboEditDialog.show(context, viewModel: widget.viewModel);
        } else {
          setState(() {
            _searchController.clear();
            _selectedCategory = '全部';
          });
        }
      },
    );
  }
}

class _MasonrySlot {
  final PromptComboEntry entry;
  final double topY;
  final double bottomY;

  const _MasonrySlot({
    required this.entry,
    required this.topY,
    required this.bottomY,
  });
}
