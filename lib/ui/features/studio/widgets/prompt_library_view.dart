import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../../core/widgets/app_search_field.dart';
import '../view_models/studio_view_model.dart';
import 'prompt_combo_card.dart';
import 'prompt_combo_edit_dialog.dart';

/// 词库全屏沉浸式管理器视图
class PromptLibraryView extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback? onClose;

  const PromptLibraryView({super.key, required this.viewModel, this.onClose});

  @override
  State<PromptLibraryView> createState() => _PromptLibraryViewState();
}

class _PromptLibraryViewState extends State<PromptLibraryView> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedCategory = '全部';
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      final q = _searchController.text.trim();
      if (q != _searchQuery) {
        setState(() => _searchQuery = q);
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<String> _getAllCategories(List<PromptComboEntry> entries) {
    final set = <String>{'全部', ...PromptComboCategories.defaults};
    for (final e in entries) {
      if (e.category.trim().isNotEmpty) {
        set.add(e.category.trim());
      }
    }
    return set.toList();
  }

  List<PromptComboEntry> _filterEntries(List<PromptComboEntry> entries) {
    return entries.where((e) {
      // 1. 分类过滤
      if (_selectedCategory != '全部') {
        if (e.category.trim() != _selectedCategory) {
          return false;
        }
      }

      // 2. 搜索关键词过滤
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchTitle = e.title.toLowerCase().contains(q);
        final matchPrompt = e.prompt.toLowerCase().contains(q);
        final matchNegative = e.negativePrompt.toLowerCase().contains(q);
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
    }).toList();
  }

  Future<void> _handleExport() async {
    final l10n = context.l10n;
    try {
      final jsonStr = await widget.viewModel.exportPromptLibraryJson();
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.libraryExportCopied),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.libraryExportFailed(e.toString())),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleImport() async {
    final l10n = context.l10n;
    final controller = TextEditingController();
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
                  fillColor: ctx.colors.mutedBackground,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: ctx.colors.borderDefault),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    borderSide: BorderSide(color: ctx.colors.borderDefault),
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
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.import),
          ),
        ],
      ),
    );

    if (result == true && controller.text.trim().isNotEmpty) {
      try {
        final count = await widget.viewModel.importPromptLibraryJson(
          controller.text.trim(),
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.libraryImportSuccess(count)),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(l10n.libraryImportFailed(e.toString())),
            duration: const Duration(seconds: 2),
          ),
        );
      }
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

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: l10n.libraryReturnToWorkbench,
          textColor: Colors.white,
          onPressed: () {
            widget.onClose?.call();
          },
        ),
      ),
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.libraryDeletedCombo(combo.title)),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final allEntries = widget.viewModel.promptLibraryEntries;
    final categories = _getAllCategories(allEntries);
    final filtered = _filterEntries(allEntries);

    return Container(
      margin: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶部操作栏
          _buildTopBar(context, allEntries.length),
          Divider(height: 1, color: colors.borderDefault),

          // 2. 主体区：左侧分类标签栏 + 竖向分割线 + 右侧词组合网格
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 侧边分类标签栏 (固定宽度 200)
                SizedBox(
                  width: 200,
                  child: _buildCategorySidebar(context, categories, allEntries),
                ),

                VerticalDivider(width: 1, color: colors.borderDefault),

                // 右侧词组合网格
                Expanded(
                  child: Container(
                    color: colors.canvasBackground,
                    child: filtered.isEmpty
                        ? _buildEmptyState(context, allEntries.isEmpty)
                        : _buildGrid(filtered),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(BuildContext context, int totalCount) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      color: colors.cardBackground,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 标题与条目统计
          Icon(
            Icons.collections_bookmark_outlined,
            size: 20,
            color: colors.primary,
          ),
          const SizedBox(width: 8),
          Text(
            l10n.tabLibrary,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          AppBadge(
            label: '$totalCount',
            variant: AppBadgeVariant.primary,
            shape: AppBadgeShape.pill,
            fontSize: 11,
          ),

          const SizedBox(width: 20),

          // 搜索框
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: AppSearchField(
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
              ),
            ),
          ),

          const SizedBox(width: 16),

          // 导入/导出
          PopupMenuButton<String>(
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
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.mutedBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.borderDefault),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.more_horiz, size: 16, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    l10n.libraryManageButton,
                    style: TextStyle(fontSize: 12, color: colors.textPrimary),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(width: 10),

          // + 新建词组合
          ElevatedButton.icon(
            onPressed: () {
              PromptComboEditDialog.show(context, viewModel: widget.viewModel);
            },
            icon: const Icon(Icons.add, size: 16),
            label: Text(
              l10n.libraryNewCombo,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
          ),
        ],
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

  Widget _buildCategorySidebar(
    BuildContext context,
    List<String> categories,
    List<PromptComboEntry> allEntries,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      color: colors.cardBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                Icon(
                  Icons.label_outline,
                  size: 14,
                  color: colors.textSecondary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.libraryCategorySidebarTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textSecondary,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.libraryEntriesCount(allEntries.length),
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colors.borderDefault),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              children: categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                final isChar = PromptComboEntry.isCharacterCategory(cat);
                final count = cat == '全部'
                    ? allEntries.length
                    : allEntries.where((e) => e.category.trim() == cat).length;
                final icon = _getCategoryIcon(cat);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: AppNavTile(
                    title: comboCategoryLabelOf(l10n, cat),
                    icon: icon,
                    badgeCount: count,
                    isSelected: isSelected,
                    onTap: () => setState(() => _selectedCategory = cat),
                    activeColor: isChar ? colors.error : colors.primary,
                    activeBackgroundColor: isChar
                        ? colors.errorSurface
                        : colors.primaryTint,
                    activeBorderColor: isChar
                        ? colors.error.withValues(alpha: 0.35)
                        : colors.primary.withValues(alpha: 0.35),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<PromptComboEntry> entries) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // 根据宽度动态计算列数 (卡片宽度约 300~360)
        final crossAxisCount = (constraints.maxWidth / 310).floor().clamp(1, 6);

        return GridView.builder(
          padding: const EdgeInsets.all(16),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
            mainAxisExtent: 420, // 增大卡片高度以容纳超大预览图与完整信息
          ),
          itemCount: entries.length,
          itemBuilder: (context, index) {
            final item = entries[index];
            return PromptComboCard(
              key: ValueKey(item.id),
              combo: item,
              onApply: (replace, asChar) =>
                  _applyCombo(item, replace: replace, asCharacter: asChar),
              onEdit: () {
                PromptComboEditDialog.show(
                  context,
                  viewModel: widget.viewModel,
                  initialEntry: item,
                );
              },
              onDelete: () => _confirmDelete(item),
            );
          },
        );
      },
    );
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
