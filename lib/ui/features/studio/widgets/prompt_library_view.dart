import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/theme/app_theme.dart';
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
    try {
      final jsonStr = await widget.viewModel.exportPromptLibraryJson();
      await Clipboard.setData(ClipboardData(text: jsonStr));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制词库 JSON 数据到剪贴板，可粘贴备份或分享'),
          duration: Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('导出失败: $e'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleImport() async {
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.pureWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          '导入词库 JSON',
          style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '请粘贴导出的词库 JSON 文本：',
                style: TextStyle(fontSize: 12, color: AppTheme.graphite),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: controller,
                maxLines: 6,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: InputDecoration(
                  hintText: '[{"title": "...", "prompt": "..."}]',
                  filled: true,
                  fillColor: AppTheme.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('导入'),
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
            content: Text('成功导入 $count 个新词组合条目'),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('导入失败，请检查 JSON 格式: $e'),
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
    widget.viewModel.applyPromptCombo(
      combo,
      replace: replace,
      asCharacter: asCharacter,
    );

    String message;
    if (asCharacter) {
      message = '已添加角色卡片: ${combo.title}';
    } else if (replace) {
      message = '已替换工作台提示词: ${combo.title}';
    } else {
      message = combo.isCharacter && combo.negativePrompt.isNotEmpty
          ? '已追加正负提示词: ${combo.title}'
          : '已追加主提示词: ${combo.title}';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(milliseconds: 1200),
        behavior: SnackBarBehavior.floating,
        action: SnackBarAction(
          label: '返回工作台',
          textColor: Colors.white,
          onPressed: () {
            widget.onClose?.call();
          },
        ),
      ),
    );
  }

  Future<void> _confirmDelete(PromptComboEntry combo) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.pureWhite,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTheme.radiusCard),
          side: const BorderSide(color: AppTheme.border),
        ),
        title: const Text(
          '删除词组合',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        content: Text(
          '确定要删除词组合「${combo.title}」吗？此操作无法撤销。',
          style: const TextStyle(fontSize: 12.5, color: AppTheme.charcoal),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.coral,
              foregroundColor: Colors.white,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await widget.viewModel.deletePromptCombo(combo.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已删除词组合: ${combo.title}'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final allEntries = widget.viewModel.promptLibraryEntries;
    final categories = _getAllCategories(allEntries);
    final filtered = _filterEntries(allEntries);

    return Container(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. 顶部操作栏
          _buildTopBar(allEntries.length),
          const Divider(height: 1, color: AppTheme.border),

          // 2. 主体区：左侧分类标签栏 + 竖向分割线 + 右侧词组合网格
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 侧边分类标签栏 (固定宽度 200)
                SizedBox(
                  width: 200,
                  child: _buildCategorySidebar(categories, allEntries),
                ),

                const VerticalDivider(width: 1, color: AppTheme.border),

                // 右侧词组合网格
                Expanded(
                  child: Container(
                    color: AppTheme.surfaceElevated,
                    child: filtered.isEmpty
                        ? _buildEmptyState(allEntries.isEmpty)
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

  Widget _buildTopBar(int totalCount) {
    return Container(
      color: AppTheme.pureWhite,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 标题与条目统计
          const Icon(
            Icons.collections_bookmark_outlined,
            size: 20,
            color: AppTheme.notionBlue,
          ),
          const SizedBox(width: 8),
          const Text(
            '词库',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: AppTheme.charcoal,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              color: AppTheme.skyTint,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$totalCount',
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.notionBlue,
              ),
            ),
          ),

          const SizedBox(width: 20),

          // 搜索框
          Expanded(
            child: Container(
              height: 34,
              constraints: const BoxConstraints(maxWidth: 360),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(fontSize: 12, color: AppTheme.charcoal),
                decoration: InputDecoration(
                  hintText: '搜索词组合名称、提示词、标签...',
                  hintStyle: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.graphite,
                  ),
                  prefixIcon: const Icon(
                    Icons.search,
                    size: 16,
                    color: AppTheme.graphite,
                  ),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.close, size: 14),
                          onPressed: () => _searchController.clear(),
                        )
                      : null,
                  contentPadding: EdgeInsets.zero,
                  filled: true,
                  fillColor: AppTheme.surfaceMuted,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    borderSide: const BorderSide(
                      color: AppTheme.notionBlue,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 16),

          // 导入/导出
          PopupMenuButton<String>(
            tooltip: '数据管理',
            onSelected: (val) {
              if (val == 'export') _handleExport();
              if (val == 'import') _handleImport();
            },
            itemBuilder: (ctx) => [
              const PopupMenuItem(
                value: 'export',
                child: Row(
                  children: [
                    Icon(
                      Icons.file_download_outlined,
                      size: 16,
                      color: AppTheme.charcoal,
                    ),
                    SizedBox(width: 8),
                    Text('导出词库 (JSON)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'import',
                child: Row(
                  children: [
                    Icon(
                      Icons.file_upload_outlined,
                      size: 16,
                      color: AppTheme.charcoal,
                    ),
                    SizedBox(width: 8),
                    Text('导入词库 (JSON)', style: TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.more_horiz, size: 16, color: AppTheme.graphite),
                  SizedBox(width: 4),
                  Text(
                    '管理',
                    style: TextStyle(fontSize: 12, color: AppTheme.charcoal),
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
            label: const Text(
              '新建词组合',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
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
    List<String> categories,
    List<PromptComboEntry> allEntries,
  ) {
    return Container(
      color: AppTheme.pureWhite,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: [
                const Icon(
                  Icons.label_outline,
                  size: 14,
                  color: AppTheme.graphite,
                ),
                const SizedBox(width: 6),
                const Text(
                  '标签分类',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.graphite,
                    letterSpacing: 0.5,
                  ),
                ),
                const Spacer(),
                Text(
                  '${allEntries.length} 条',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: AppTheme.graphite,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: AppTheme.border),
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

                final activeColor =
                    isChar ? AppTheme.coral : AppTheme.notionBlue;
                final activeBgColor =
                    isChar ? const Color(0xFFFFECEB) : AppTheme.skyTint;
                final activeBorderColor = isChar
                    ? AppTheme.coral.withValues(alpha: 0.35)
                    : AppTheme.notionBlue.withValues(alpha: 0.35);

                return Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => setState(() => _selectedCategory = cat),
                      borderRadius:
                          BorderRadius.circular(AppTheme.radiusButton),
                      splashColor: Colors.transparent,
                      highlightColor: Colors.transparent,
                      hoverColor: isSelected
                          ? Colors.transparent
                          : AppTheme.surfaceMuted.withValues(alpha: 0.6),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 100),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected ? activeBgColor : Colors.transparent,
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          border: Border.all(
                            color: isSelected
                                ? activeBorderColor
                                : activeBorderColor.withValues(alpha: 0.0),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              icon,
                              size: 15,
                              color: isSelected
                                  ? activeColor
                                  : AppTheme.graphite,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? activeColor
                                      : AppTheme.charcoal,
                                ),
                              ),
                            ),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 100),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 1.5,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? (isChar
                                        ? AppTheme.coral.withValues(
                                            alpha: 0.15,
                                          )
                                        : AppTheme.notionBlue.withValues(
                                            alpha: 0.15,
                                          ))
                                    : AppTheme.surfaceMuted,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                '$count',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? activeColor
                                      : AppTheme.graphite,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
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

  Widget _buildEmptyState(bool isCompletelyEmpty) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.collections_bookmark_outlined,
            size: 48,
            color: AppTheme.graphite.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 12),
          Text(
            isCompletelyEmpty ? '词库暂无条目' : '没有匹配的词组合',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.charcoal,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            isCompletelyEmpty
                ? '点击右上角「新建词组合」创建您的第一个专属提示词组合'
                : '请尝试更换搜索词或分类筛选条件',
            style: const TextStyle(fontSize: 12, color: AppTheme.graphite),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () {
              if (isCompletelyEmpty) {
                PromptComboEditDialog.show(
                  context,
                  viewModel: widget.viewModel,
                );
              } else {
                setState(() {
                  _searchController.clear();
                  _selectedCategory = '全部';
                });
              }
            },
            icon: Icon(isCompletelyEmpty ? Icons.add : Icons.refresh, size: 15),
            label: Text(isCompletelyEmpty ? '新建词组合' : '重置筛选条件'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
              elevation: 0,
            ),
          ),
        ],
      ),
    );
  }
}
