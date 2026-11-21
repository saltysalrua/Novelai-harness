import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/models/prompt_library_sync_models.dart';
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
import '../../../core/widgets/context_menu.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../settings/widgets/settings_shared.dart';
import '../view_models/studio_view_model.dart';
import 'prompt_combo_card.dart';
import 'prompt_combo_edit_dialog.dart';
import 'prompt_library_sync_dialog.dart';
import 'studio_shared.dart';

/// 词库全屏沉浸式管理器视图：
/// 单一开放画布 + 顶部内联分类筛选 + 原始比例瀑布流，彻底消除冗余框与分割线。
class PromptLibraryView extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback? onClose;
  final VoidCallback? onSentToChat;
  final bool connectedLeft;
  final VoidCallback? onExpandSidebar;

  /// 窄屏移动端紧凑模式：贴边全屏画布、合并顶部工具条并与双列高密度瀑布流协同。
  final bool compact;

  const PromptLibraryView({
    super.key,
    required this.viewModel,
    this.onClose,
    this.onSentToChat,
    this.connectedLeft = false,
    this.onExpandSidebar,
    this.compact = false,
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
                final matchPrefix = e.prefixPrompt.toLowerCase().contains(q);
                final matchSuffix = e.suffixPrompt.toLowerCase().contains(q);
                final matchNegative = e.negativePrompt.toLowerCase().contains(
                  q,
                );
                final matchCategory = e.category.toLowerCase().contains(q);
                final matchTags = e.tags.any((t) => t.toLowerCase().contains(q));
                if (!matchTitle &&
                    !matchPrompt &&
                    !matchPrefix &&
                    !matchSuffix &&
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
          minimalChrome: true,
          body: Padding(
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 16),
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
                  decoration: settingsSoftInputDecoration(
                    ctx,
                    hintText: '[{"title": "...", "prompt": "..."}]',
                    contentPadding: const EdgeInsets.all(12),
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

  void _applyStyleCombo(PromptComboEntry combo, {required bool replace}) {
    final l10n = context.l10n;
    widget.viewModel.applyPromptCombo(
      combo,
      replace: replace,
      asStyle: true,
    );
    showAppToast(
      context,
      message: l10n.libraryApplyStyleSuccess(combo.title),
      tone: AppToastTone.success,
      duration: const Duration(milliseconds: 1400),
      actionLabel: widget.onClose != null
          ? l10n.libraryReturnToWorkbench
          : null,
      onAction: widget.onClose,
    );
  }

  void _sendCharacterToAgent(PromptComboEntry combo) {
    final l10n = context.l10n;
    widget.viewModel.insertCharacterToChatInput(combo);
    showAppToast(
      context,
      message: l10n.librarySentCharacterToAgent(combo.title),
      tone: AppToastTone.success,
      duration: const Duration(milliseconds: 1400),
    );
    (widget.onSentToChat ?? widget.onClose)?.call();
  }

  Future<void> _handleSync(PromptLibrarySyncMode mode) async {
    final vm = widget.viewModel;
    if (!vm.promptLibrarySyncConfig.isConfigured) {
      await PromptLibrarySyncDialog.show(context, viewModel: vm);
      return;
    }
    if (vm.isSyncingPromptLibrary) return;

    final confirmed = await confirmPromptLibrarySyncMode(context, mode);
    if (!confirmed || !mounted) return;

    final l10n = context.l10n;
    try {
      final result = await vm.syncPromptLibrary(mode: mode);
      if (!mounted) return;
      showAppToast(
        context,
        message: formatPromptLibrarySyncSummary(l10n, result),
        tone: AppToastTone.success,
        duration: const Duration(seconds: 3),
      );
    } catch (e) {
      if (!mounted) return;
      showAppToast(
        context,
        message: l10n.librarySyncFailed(e.toString()),
        tone: AppToastTone.error,
        duration: const Duration(seconds: 3),
      );
    }
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
          margin: widget.compact
              ? EdgeInsets.zero
              : (widget.connectedLeft
                    ? const EdgeInsets.fromLTRB(0, 8, 8, 8)
                    : const EdgeInsets.all(8)),
          decoration: widget.compact
              ? BoxDecoration(color: colors.canvasBackground)
              : ShapeDecoration(
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

        // 移动端紧凑壳层：顶部栏已展示「词库」标题，此处合并为单行搜索+操作条释放纵向空间
        if (widget.compact) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: Row(
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
                  const SizedBox(width: 4),
                ],
                Expanded(child: SizedBox(height: 34, child: searchField)),
                const SizedBox(width: 6),
                _buildSyncButton(context, compact: true),
                const SizedBox(width: 6),
                _buildManageMenu(context, compact: true),
                const SizedBox(width: 6),
                _buildNewComboButton(context, compact: true),
              ],
            ),
          );
        }

        if (isNarrow) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: title),
                    _buildSyncButton(context, compact: true),
                    const SizedBox(width: 6),
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
                  constraints: const BoxConstraints(maxWidth: 280),
                  child: SizedBox(height: 34, child: searchField),
                ),
              ),
              const SizedBox(width: 10),
              _buildSyncButton(context, compact: false),
              const SizedBox(width: 8),
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
              ? const EdgeInsets.fromLTRB(10, 0, 10, 6)
              : const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: AppSegmentedPillBar<String>(
            scrollable: true,
            variant: AppPillVariant.soft,
            spacing: isNarrow ? 4.0 : 6.0,
            itemPadding: isNarrow
                ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4)
                : const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
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

  /// 快捷云同步按钮 (已配置则触发双向合并，未配置则打开设置弹窗)
  Widget _buildSyncButton(BuildContext context, {required bool compact}) {
    final l10n = context.l10n;
    final vm = widget.viewModel;
    final syncing = vm.isSyncingPromptLibrary;
    final stage = vm.promptSyncStage;
    final tooltip = syncing
        ? (stage ?? l10n.librarySyncingLabel)
        : l10n.librarySyncButton;

    if (compact) {
      return AppIconButton(
        key: const Key('library_cloud_sync_button'),
        icon: syncing ? Icons.sync_rounded : Icons.cloud_sync_outlined,
        size: 34,
        iconSize: 17,
        variant: AppIconButtonVariant.outlined,
        tooltip: tooltip,
        onPressed: syncing
            ? null
            : () => _handleSync(PromptLibrarySyncMode.merge),
      );
    }

    return Tooltip(
      message: tooltip,
      child: SizedBox(
        height: 34,
        child: AppActionButton(
          key: const Key('library_cloud_sync_button'),
          icon: Icons.cloud_sync_outlined,
          iconSize: 15,
          label: syncing ? l10n.librarySyncingLabel : l10n.librarySyncButton,
          variant: AppActionButtonVariant.outlined,
          isLoading: syncing,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 0),
          onPressed: syncing
              ? null
              : () => _handleSync(PromptLibrarySyncMode.merge),
        ),
      ),
    );
  }

  /// 统一 Notion 风格管理弹出菜单 (导出 / 导入 / 云同步设置与恢复)
  Widget _buildManageMenu(BuildContext context, {required bool compact}) {
    final l10n = context.l10n;

    void openMenu(BuildContext btnContext) {
      final renderObj = btnContext.findRenderObject();
      if (renderObj is! RenderBox) return;
      final bottomLeft = renderObj.localToGlobal(
        Offset(0, renderObj.size.height + 6),
      );
      showStudioContextMenu(
        btnContext,
        position: bottomLeft,
        actions: [
          ContextMenuItem(
            icon: Icons.tune_outlined,
            label: l10n.librarySyncSettingsMenu,
            onTap: () => PromptLibrarySyncDialog.show(
              context,
              viewModel: widget.viewModel,
            ),
          ),
          const ContextMenuDivider(),
          ContextMenuItem(
            icon: Icons.file_download_outlined,
            label: l10n.libraryExportJson,
            onTap: _handleExport,
          ),
          ContextMenuItem(
            icon: Icons.file_upload_outlined,
            label: l10n.libraryImportJson,
            onTap: _handleImport,
          ),
        ],
      );
    }

    return Builder(
      builder: (btnContext) {
        if (compact) {
          return AppIconButton(
            key: const Key('library_manage_menu_button'),
            icon: Icons.more_horiz_rounded,
            size: 34,
            iconSize: 18,
            variant: AppIconButtonVariant.outlined,
            tooltip: l10n.libraryDataManagement,
            onPressed: () => openMenu(btnContext),
          );
        }
        return Tooltip(
          message: l10n.libraryDataManagement,
          child: SizedBox(
            height: 34,
            child: AppActionButton(
              key: const Key('library_manage_menu_button'),
              icon: Icons.more_horiz_rounded,
              iconSize: 16,
              label: l10n.libraryManageButton,
              variant: AppActionButtonVariant.outlined,
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 0),
              onPressed: () => openMenu(btnContext),
            ),
          ),
        );
      },
    );
  }

  /// + 新建词组合
  Widget _buildNewComboButton(BuildContext context, {required bool compact}) {
    final l10n = context.l10n;
    void openCreateDialog() => PromptComboEditDialog.show(
      context,
      viewModel: widget.viewModel,
      initialCategory: _selectedCategory != '全部' ? _selectedCategory : null,
    );

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
    return SizedBox(
      height: 34,
      child: AppActionButton(
        icon: Icons.add_rounded,
        iconSize: 16,
        label: l10n.libraryNewCombo,
        variant: AppActionButtonVariant.primary,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 0),
        onPressed: openCreateDialog,
      ),
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

  int _resolveColumnCount(double usableWidth, {required bool isNarrow}) {
    if (!isNarrow) {
      return (usableWidth / 264.0).floor().clamp(1, 8);
    }
    if (usableWidth >= 480) return 3;
    if (usableWidth >= 280) return 2;
    return 1;
  }

  Widget _buildMasonryGallery(List<PromptComboEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final hPad = isNarrow ? 8.0 : 20.0;
        final spacing = isNarrow ? 8.0 : 14.0;
        final usableWidth = (constraints.maxWidth - hPad * 2).clamp(
          200.0,
          double.infinity,
        );
        final columnCount = _resolveColumnCount(usableWidth, isNarrow: isNarrow);
        final columnWidth =
            (usableWidth - (columnCount - 1) * spacing) / columnCount;
        final isCompactCard = isNarrow || columnWidth < 230.0;

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
          final estHeight = _estimateCardHeight(
            entry,
            columnWidth,
            compact: isCompactCard,
          );
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
          padding: EdgeInsets.fromLTRB(hPad, 2, hPad, isNarrow ? 14 : 20),
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
                    if (c > 0) SizedBox(width: spacing),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < columns[c].length; i++) ...[
                            if (i > 0) SizedBox(height: spacing),
                            RepaintBoundary(
                              key: ValueKey(columns[c][i].entry.id),
                              child: PromptComboCard(
                                combo: columns[c][i].entry,
                                compact: isCompactCard,
                                loadImage:
                                    columns[c][i].bottomY >= visibleTop &&
                                    columns[c][i].topY <= visibleBottom,
                                onApply: (replace, asChar) => _applyCombo(
                                  columns[c][i].entry,
                                  replace: replace,
                                  asCharacter: asChar,
                                ),
                                onApplyStyle: columns[c][i].entry.isStyle
                                    ? (replace) => _applyStyleCombo(
                                        columns[c][i].entry,
                                        replace: replace,
                                      )
                                    : null,
                                onSendToAgent: columns[c][i].entry.isCharacter
                                    ? () => _sendCharacterToAgent(
                                        columns[c][i].entry,
                                      )
                                    : null,
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

  double _estimateCardHeight(
    PromptComboEntry entry,
    double columnWidth, {
    required bool compact,
  }) {
    final path = entry.previewImagePath?.trim();
    final textSectionHeight = compact ? 108.0 : 96.0;
    if (path == null || path.isEmpty || PromptImageProbe.isKnownMissing(path)) {
      return textSectionHeight;
    }
    final ratio = (PromptImageProbe.getCachedAspectRatio(path) ?? 1.0).clamp(
      0.45,
      2.2,
    );
    return columnWidth / ratio + textSectionHeight;
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
