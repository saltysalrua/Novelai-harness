import 'dart:io';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/mcp/mcp_models.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../data/models/skill_package.dart';
import '../../../../data/services/skill_package_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/skill_error_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_control_flow.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../studio/view_models/studio_view_model.dart';
import 'mcp_server_editor_dialog.dart';
import 'presets_settings_tab.dart';
import 'settings_shared.dart';
import 'skill_card.dart';
import 'skill_editor_dialog.dart';

enum _ExtensionsSegment { skills, mcp }

enum _SkillFilterMode { all, builtin, custom, packaged }

/// 设置页「技能与 MCP」独立标签页：
/// - 技能库：拖拽导入压缩包/文件夹、多技能批量导入、筛选搜索、编辑与资源预览、内置恢复默认
/// - MCP 服务：HTTP/SSE 与 Stdio 配置、mcpServers JSON 一键导入、状态监控与 CodeMode 工具清单
class ExtensionsSettingsTab extends StatefulWidget {
  final StudioViewModel viewModel;
  final PresetsSettingsDraft presetsDraft;

  const ExtensionsSettingsTab({
    super.key,
    required this.viewModel,
    required this.presetsDraft,
  });

  @override
  State<ExtensionsSettingsTab> createState() => _ExtensionsSettingsTabState();
}

class _ExtensionsSettingsTabState extends State<ExtensionsSettingsTab> {
  late final SmoothWheelScrollController _skillsScrollController;
  late final SmoothWheelScrollController _mcpScrollController;
  final TextEditingController _skillSearchController = TextEditingController();
  _ExtensionsSegment _segment = _ExtensionsSegment.skills;
  _SkillFilterMode _skillFilter = _SkillFilterMode.all;
  bool _isDraggingFile = false;

  bool get _isDesktop =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  bool get _isMobile =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    _skillsScrollController = SmoothWheelScrollController();
    _mcpScrollController = SmoothWheelScrollController();
    _skillSearchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _skillsScrollController.dispose();
    _mcpScrollController.dispose();
    _skillSearchController.removeListener(_onSearchChanged);
    _skillSearchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  void _showSkillError(Object error) {
    if (!mounted) return;
    showAppToast(
      context,
      message: skillErrorText(context.l10n, error),
      tone: AppToastTone.error,
    );
  }

  Future<void> _enableImportedSkills(List<String> ids) async {
    if (ids.isEmpty || !mounted) return;
    final draft = widget.presetsDraft;
    final l10n = context.l10n;
    if (!draft.currentPreset.isBuiltin) {
      for (final id in ids) {
        draft.toggleSkill(id, true, l10n.presetDefaultCustomName);
      }
      setState(() {});
      return;
    }

    // 当前预设为内置只读时，提供一键「复制预设并启用」
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.skillDuplicateAndEnable,
      message: l10n.skillImportedEnableHint,
      confirmLabel: l10n.skillDuplicateAndEnable,
    );
    if (confirmed == true && mounted) {
      draft.duplicatePreset(
        draft.currentPreset,
        duplicateName: l10n.presetDuplicateName(draft.currentPreset.name),
        fallbackName: l10n.presetDefaultCustomName,
      );
      draft.setActivePreset(draft.currentPreset.id);
      for (final id in ids) {
        draft.toggleSkill(id, true, l10n.presetDefaultCustomName);
      }
      setState(() {});
    }
  }

  Future<void> _handleDecodedPackages(List<SkillPackage> packages) async {
    if (packages.isEmpty || !mounted) return;
    if (packages.length == 1) {
      final imported = packages.single;
      final result = await AppDialogScaffold.show<Skill>(
        context: context,
        builder: (ctx) => SkillEditorDialog(
          skill: imported.skill,
          isImportMode: true,
          // 导入压缩包/文件时直接展示直观的结构化预览与可点击资源文件清单
          initialRawMode: false,
          previewFiles: imported.files,
          onSave: (skill) => widget.viewModel.importSkillPackage(
            imported,
            skill,
          ),
        ),
      );
      if (result != null && mounted) {
        setState(() {});
        await _enableImportedSkills([result.id]);
      }
      return;
    }

    // 多技能压缩包：弹出批量勾选对话框
    final existingIds = widget.viewModel.availableSkills
        .map((s) => s.id.toLowerCase())
        .toSet();
    final selectedPackages = await AppDialogScaffold.show<List<SkillPackage>>(
      context: context,
      builder: (ctx) => _BatchSkillImportDialog(
        packages: packages,
        existingIdsLower: existingIds,
      ),
    );
    if (selectedPackages == null || selectedPackages.isEmpty || !mounted) {
      return;
    }

    final importedIds = <String>[];
    for (final pkg in selectedPackages) {
      try {
        final saved = await widget.viewModel.importSkillPackage(pkg, pkg.skill);
        importedIds.add(saved.id);
      } catch (error) {
        _showSkillError(error);
      }
    }
    if (!mounted) return;
    setState(() {});
    if (importedIds.isNotEmpty) {
      showAppToast(
        context,
        message: context.l10n.skillBatchImportSuccess(importedIds.length),
        tone: AppToastTone.success,
      );
      await _enableImportedSkills(importedIds);
    }
  }

  Future<void> _importFromArchiveOrFile() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: _isMobile ? FileType.any : FileType.custom,
        allowedExtensions: _isMobile ? null : const ['zip', 'skill', 'md'],
        withData: _isMobile,
      );
      if (picked == null || !mounted) return;
      final file = picked.files.single;
      final bytes = file.bytes;
      final List<SkillPackage> packages;
      if (bytes != null && bytes.isNotEmpty) {
        packages = await widget.viewModel.readSkillImportBytesAll(
          bytes,
          file.name,
        );
      } else {
        final path = file.path;
        if (path == null || path.isEmpty) {
          throw FormatException(context.l10n.skillFileUnreadable);
        }
        packages = await widget.viewModel.readSkillImportFileAll(
          path,
          filename: file.name,
        );
      }
      await _handleDecodedPackages(packages);
    } catch (error) {
      _showSkillError(error);
    }
  }

  Future<void> _importFromFolder() async {
    try {
      final path = await FilePicker.platform.getDirectoryPath();
      if (path == null || !mounted) return;
      final packages = await widget.viewModel.readSkillImportDirectoryAll(path);
      await _handleDecodedPackages(packages);
    } catch (error) {
      _showSkillError(error);
    }
  }

  Future<void> _importFromPaste() async {
    final result = await AppDialogScaffold.show<Skill>(
      context: context,
      builder: (ctx) => SkillEditorDialog(
        isImportMode: true,
        initialRawMode: true,
        onSave: (skill) =>
            widget.viewModel.saveCustomSkill(skill, requireNew: true),
      ),
    );
    if (result != null && mounted) {
      setState(() {});
      await _enableImportedSkills([result.id]);
    }
  }

  Future<void> _openNewSkillDialog() async {
    final result = await AppDialogScaffold.show<Skill>(
      context: context,
      builder: (ctx) => SkillEditorDialog(
        onSave: (skill) =>
            widget.viewModel.saveCustomSkill(skill, requireNew: true),
      ),
    );
    if (result != null && mounted) {
      setState(() {});
      await _enableImportedSkills([result.id]);
    }
  }

  Future<void> _handleDroppedPaths(List<String> paths) async {
    if (paths.isEmpty || !mounted) return;
    final allPackages = <SkillPackage>[];
    for (final path in paths) {
      try {
        final type = await FileSystemEntity.type(path, followLinks: false);
        if (type == FileSystemEntityType.directory) {
          allPackages.addAll(
            await widget.viewModel.readSkillImportDirectoryAll(path),
          );
        } else if (type == FileSystemEntityType.file) {
          allPackages.addAll(await widget.viewModel.readSkillImportFileAll(path));
        }
      } catch (error) {
        _showSkillError(error);
      }
    }
    if (allPackages.isNotEmpty && mounted) {
      await _handleDecodedPackages(allPackages);
    }
  }

  Future<void> _openEditSkillDialog(Skill skill) async {
    final overridden = widget.viewModel.isBuiltinSkillOverridden(skill.id);
    final result = await AppDialogScaffold.show<Skill>(
      context: context,
      builder: (ctx) => SkillEditorDialog(
        skill: skill,
        isOverridden: overridden,
        onReadResource: skill.resourcePaths.isNotEmpty
            ? (path) => widget.viewModel.readSkillResource(skill, path)
            : null,
        onResetDefault: overridden
            ? () async {
                await widget.viewModel.resetBuiltinSkill(skill.id);
                if (mounted) {
                  setState(() {});
                  showAppToast(
                    context,
                    message: context.l10n.skillResetDefaultSuccess(skill.name),
                    tone: AppToastTone.success,
                  );
                }
              }
            : null,
        onSave: (edited) =>
            widget.viewModel.saveCustomSkill(edited, originalId: skill.id),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        widget.presetsDraft.replaceSkillReferences(skill.id, result.id);
      });
    }
  }

  Future<void> _resetBuiltinSkill(Skill skill) async {
    try {
      await widget.viewModel.resetBuiltinSkill(skill.id);
      if (!mounted) return;
      setState(() {});
      showAppToast(
        context,
        message: context.l10n.skillResetDefaultSuccess(skill.name),
        tone: AppToastTone.success,
      );
    } catch (error) {
      _showSkillError(error);
    }
  }

  Future<void> _exportSkillPackage(Skill skill) async {
    try {
      final bytes = await widget.viewModel.exportSkillPackage(skill);
      if (!mounted) return;
      final name = SkillPackageService.skillIdPattern.hasMatch(skill.id)
          ? skill.id
          : 'skill';
      final path = await FilePicker.platform.saveFile(
        fileName: '$name.zip',
        type: FileType.custom,
        allowedExtensions: ['zip'],
        bytes: _isMobile ? bytes : null,
      );
      if (path == null) return;
      if (!_isMobile) await widget.viewModel.writeSkillExportFile(path, bytes);
      if (!mounted) return;
      showAppToast(
        context,
        message: context.l10n.presetExportSkillSuccess(skill.name),
        tone: AppToastTone.success,
      );
    } catch (error) {
      _showSkillError(error);
    }
  }

  Future<void> _deleteSkill(Skill skill) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.skillConfirmDeleteTitle,
      message: l10n.skillConfirmDeleteMessage(skill.name),
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.viewModel.deleteCustomSkill(skill.id);
      if (mounted) {
        setState(() {
          widget.presetsDraft.replaceSkillReferences(skill.id, null);
        });
      }
    } catch (error) {
      _showSkillError(error);
    }
  }

  // ------------------------- MCP 操作 -------------------------

  Future<void> _openNewMcpServerDialog() async {
    final created = await AppDialogScaffold.show<McpServerConfig>(
      context: context,
      builder: (_) => const McpServerEditorDialog(),
    );
    if (created != null && mounted) {
      await widget.viewModel.saveMcpServer(created);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openEditMcpServerDialog(McpServerConfig server) async {
    final updated = await AppDialogScaffold.show<McpServerConfig>(
      context: context,
      builder: (_) => McpServerEditorDialog(server: server),
    );
    if (updated != null && mounted) {
      await widget.viewModel.saveMcpServer(updated, originalId: server.id);
      if (mounted) setState(() {});
    }
  }

  Future<void> _openImportMcpJsonDialog() async {
    final parsed = await AppDialogScaffold.show<List<McpServerConfig>>(
      context: context,
      builder: (_) => const McpJsonImportDialog(),
    );
    if (parsed == null || parsed.isEmpty || !mounted) return;
    final count = await widget.viewModel.importMcpServers(parsed);
    if (!mounted) return;
    setState(() {});
    showAppToast(
      context,
      message: context.l10n.mcpImportJsonSuccess(count),
      tone: AppToastTone.success,
    );
  }

  void _copyMcpJson() {
    final json = McpServerConfig.encodeMcpServersJson(
      widget.viewModel.mcpServers,
    );
    Clipboard.setData(ClipboardData(text: json));
    showAppToast(
      context,
      message: context.l10n.mcpExportJsonCopied,
      tone: AppToastTone.success,
    );
  }

  Future<void> _deleteMcpServer(McpServerConfig server) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.mcpConfirmDeleteTitle,
      message: l10n.mcpConfirmDeleteMessage(server.name),
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    await widget.viewModel.deleteMcpServer(server.id);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final skillCount = widget.viewModel.availableSkills.length;
    final mcpCount = widget.viewModel.mcpServers.length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = constraints.maxWidth < 560 ? 16.0 : 28.0;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 14),
              child: AppSegmentedCardBar<_ExtensionsSegment>(
                highlightSelectedIcon: true,
                items: [
                  AppSegmentedItem(
                    value: _ExtensionsSegment.skills,
                    icon: Icons.auto_stories_outlined,
                    label: l10n.extensionsSegmentSkills,
                    badgeLabel: '$skillCount',
                  ),
                  AppSegmentedItem(
                    value: _ExtensionsSegment.mcp,
                    icon: Icons.hub_outlined,
                    label: l10n.extensionsSegmentMcp,
                    badgeLabel: '$mcpCount',
                  ),
                ],
                selectedValue: _segment,
                onValueChanged: (seg) => setState(() => _segment = seg),
              ),
            ),
            Expanded(
              child: AppPageStack(
                index: _segment.index,
                itemCount: 2,
                itemBuilder: (context, index) => SingleChildScrollView(
                  controller: index == 0
                      ? _skillsScrollController
                      : _mcpScrollController,
                  padding: EdgeInsets.fromLTRB(hPad, 2, hPad, 24),
                  child: index == 0
                      ? _buildSkillsSection(context)
                      : _buildMcpSection(context),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSkillsSection(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final allSkills = widget.viewModel.availableSkills;
    final query = _skillSearchController.text.trim().toLowerCase();

    final filtered = allSkills.where((s) {
      final passFilter = switch (_skillFilter) {
        _SkillFilterMode.all => true,
        _SkillFilterMode.builtin => s.isBuiltin,
        _SkillFilterMode.custom => !s.isBuiltin,
        _SkillFilterMode.packaged => s.resourcePaths.isNotEmpty,
      };
      if (!passFilter) return false;
      if (query.isEmpty) return true;
      return s.name.toLowerCase().contains(query) ||
          s.id.toLowerCase().contains(query) ||
          s.description.toLowerCase().contains(query);
    }).toList();

    final dropArea = AnimatedContainer(
      duration: AppMotion.resolveDuration(context, AppMotionDurations.quick),
      curve: AppMotionCurves.smoothOut,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _isDraggingFile
            ? colors.primaryTint
            : colors.elevatedBackground,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(
          color: _isDraggingFile ? colors.primary : colors.borderDefault,
          width: _isDraggingFile ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Icon(
                  _isDraggingFile
                      ? Icons.file_download_done_rounded
                      : Icons.folder_zip_outlined,
                  size: 18,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isDraggingFile
                          ? l10n.skillDropActiveTitle
                          : l10n.skillDropHintTitle,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _isDraggingFile
                            ? colors.primary
                            : colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      l10n.skillDropHintSubtitle,
                      style: TextStyle(
                        fontSize: 11.5,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          AppControlFlow(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppActionButton(
                icon: Icons.folder_zip_outlined,
                label: l10n.skillImportArchive,
                variant: AppActionButtonVariant.primary,
                onPressed: _importFromArchiveOrFile,
              ),
              if (_isDesktop)
                AppActionButton(
                  icon: Icons.folder_open_outlined,
                  label: l10n.skillImportFolder,
                  onPressed: _importFromFolder,
                ),
              AppActionButton(
                icon: Icons.content_paste_outlined,
                label: l10n.skillImportPaste,
                onPressed: _importFromPaste,
              ),
              AppActionButton(
                icon: Icons.add_rounded,
                label: l10n.presetNewSkill,
                onPressed: _openNewSkillDialog,
              ),
            ],
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isDesktop)
          Builder(
            builder: (dropContext) {
              final canAcceptDrop =
                  (ModalRoute.of(dropContext)?.isCurrent ?? true) &&
                  TickerMode.valuesOf(dropContext).enabled;
              return DropTarget(
                enable: canAcceptDrop,
                onDragEntered: (_) {
                  if (!canAcceptDrop) return;
                  setState(() => _isDraggingFile = true);
                },
                onDragExited: (_) => setState(() => _isDraggingFile = false),
                onDragDone: (detail) {
                  setState(() => _isDraggingFile = false);
                  if (!canAcceptDrop) return;
                  _handleDroppedPaths(detail.files.map((f) => f.path).toList());
                },
                child: dropArea,
              );
            },
          )
        else
          dropArea,
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final filters = Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final entry in [
                  (_SkillFilterMode.all, l10n.skillFilterAll),
                  (_SkillFilterMode.builtin, l10n.skillFilterBuiltin),
                  (_SkillFilterMode.custom, l10n.skillFilterCustom),
                  (_SkillFilterMode.packaged, l10n.skillFilterPackaged),
                ])
                  AppToolChip(
                    label: entry.$2,
                    isSelected: _skillFilter == entry.$1,
                    variant: AppToolChipVariant.tinted,
                    onTap: () => setState(() => _skillFilter = entry.$1),
                  ),
              ],
            );
            final search = SizedBox(
              width: constraints.maxWidth >= 560 ? 240 : double.infinity,
              child: AppSearchField(
                controller: _skillSearchController,
                hintText: l10n.skillSearchHint,
                height: 32,
                fontSize: 12,
                debounceDuration: Duration.zero,
                onChanged: (_) {},
              ),
            );
            if (constraints.maxWidth >= 560) {
              return Row(
                children: [
                  Expanded(child: filters),
                  const SizedBox(width: 12),
                  search,
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [filters, const SizedBox(height: 8), search],
            );
          },
        ),
        const SizedBox(height: 12),
        if (filtered.isEmpty)
          AppEmptyState(
            icon: Icons.search_off_rounded,
            title: l10n.skillNoMatching,
            isCompact: true,
          )
        else
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 10.0;
              final columns = (constraints.maxWidth / 270).floor().clamp(1, 3);
              final cardWidth =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final skill in filtered)
                    SkillCard(
                      width: cardWidth,
                      skill: skill,
                      isEnabled: false,
                      showToggleCheckbox: false,
                      isOverridden: widget.viewModel.isBuiltinSkillOverridden(
                        skill.id,
                      ),
                      onEdit: _openEditSkillDialog,
                      onExport: _exportSkillPackage,
                      onResetDefault:
                          widget.viewModel.isBuiltinSkillOverridden(skill.id)
                          ? () => _resetBuiltinSkill(skill)
                          : null,
                      onDelete: !skill.isBuiltin
                          ? () => _deleteSkill(skill)
                          : null,
                    ),
                ],
              );
            },
          ),
      ],
    );
  }

  Widget _buildMcpSection(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return ValueListenableBuilder<int>(
      valueListenable: widget.viewModel.mcpStateNotifier,
      builder: (context, _, _) {
        final servers = widget.viewModel.mcpServers;
        final totalTools = widget.viewModel.discoveredMcpTools.length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsSoftContainer(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.hub_outlined,
                    size: 16,
                    color: colors.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      l10n.mcpCodeModeNotice,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            AppSectionHeader(
              title:
                  '${l10n.extensionsSegmentMcp} (${servers.length} · ${l10n.mcpToolsCount(totalTools)})',
              trailing: AppControlFlow(
                spacing: 6,
                children: [
                  AppActionButton(
                    icon: Icons.add_rounded,
                    label: l10n.mcpAddServer,
                    variant: AppActionButtonVariant.primary,
                    onPressed: _openNewMcpServerDialog,
                  ),
                  AppActionButton(
                    icon: Icons.data_object_rounded,
                    label: l10n.mcpImportJson,
                    onPressed: _openImportMcpJsonDialog,
                  ),
                  if (servers.isNotEmpty) ...[
                    AppActionButton(
                      icon: Icons.copy_rounded,
                      label: l10n.mcpExportJson,
                      onPressed: _copyMcpJson,
                    ),
                    AppActionButton(
                      icon: Icons.refresh_rounded,
                      label: l10n.mcpReconnectAll,
                      onPressed: () => widget.viewModel.reconnectAllMcpServers(),
                    ),
                  ],
                ],
              ),
            ),
            if (servers.isEmpty)
              AppEmptyState(
                icon: Icons.extension_outlined,
                title: l10n.mcpEmptyTitle,
                description: l10n.mcpEmptySubtitle,
              )
            else
              Column(
                children: [
                  for (final server in servers) ...[
                    _McpServerCard(
                      server: server,
                      state: widget.viewModel.mcpServerState(server.id),
                      onToggle: (enabled) =>
                          widget.viewModel.toggleMcpServer(server.id, enabled),
                      onReconnect: () =>
                          widget.viewModel.reconnectMcpServer(server.id),
                      onEdit: () => _openEditMcpServerDialog(server),
                      onDelete: () => _deleteMcpServer(server),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
          ],
        );
      },
    );
  }
}

class _McpServerCard extends StatelessWidget {
  final McpServerConfig server;
  final McpServerRuntimeState state;
  final ValueChanged<bool> onToggle;
  final VoidCallback onReconnect;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _McpServerCard({
    required this.server,
    required this.state,
    required this.onToggle,
    required this.onReconnect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    final (statusLabel, statusVariant) = switch (state.status) {
      McpConnectionStatus.connected => (
        '${l10n.mcpStatusConnected} · ${l10n.mcpToolsCount(state.tools.length)}',
        AppBadgeVariant.success,
      ),
      McpConnectionStatus.connecting => (
        l10n.mcpStatusConnecting,
        AppBadgeVariant.primary,
      ),
      McpConnectionStatus.error => (
        l10n.mcpStatusError,
        AppBadgeVariant.error,
      ),
      McpConnectionStatus.disconnected => (
        l10n.mcpStatusDisconnected,
        AppBadgeVariant.neutral,
      ),
    };

    return AppCard(
      padding: const EdgeInsets.all(14),
      radius: AppRadius.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            server.name,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        AppBadge(
                          label: server.transport == McpTransportType.http
                              ? 'HTTP'
                              : 'Stdio',
                          variant: AppBadgeVariant.neutral,
                          fontSize: 10,
                        ),
                        const SizedBox(width: 6),
                        AppBadge(
                          label: statusLabel,
                          variant: statusVariant,
                          fontSize: 10,
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      server.endpointSummary,
                      style: TextStyle(
                        fontSize: 11,
                        fontFamily: 'monospace',
                        color: colors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppIconButton(
                icon: Icons.refresh_rounded,
                size: 28,
                iconSize: 15,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.mcpReconnect,
                onPressed: server.enabled ? onReconnect : null,
              ),
              AppIconButton(
                icon: Icons.edit_outlined,
                size: 28,
                iconSize: 15,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.mcpDialogEditTitle(server.name),
                onPressed: onEdit,
              ),
              AppIconButton(
                icon: Icons.delete_outline_rounded,
                size: 28,
                iconSize: 15,
                variant: AppIconButtonVariant.ghost,
                iconColor: colors.error,
                tooltip: l10n.delete,
                onPressed: onDelete,
              ),
              const SizedBox(width: 6),
              AppSwitch(
                value: server.enabled,
                width: 36,
                height: 20,
                onChanged: onToggle,
              ),
            ],
          ),
          if (state.errorMessage != null && state.errorMessage!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Text(
                state.errorMessage!,
                style: TextStyle(
                  fontSize: 11,
                  color: colors.error,
                  height: 1.35,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (state.tools.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: colors.elevatedBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: AppCollapsibleSection(
                isCard: false,
                headerPadding: const EdgeInsets.symmetric(vertical: 6),
                contentPadding: const EdgeInsets.only(bottom: 8),
                title: l10n.mcpToolsCount(state.tools.length),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final tool in state.tools)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              tool.exposedName,
                              style: TextStyle(
                                fontSize: 11,
                                fontFamily: 'monospace',
                                fontWeight: FontWeight.w600,
                                color: colors.primary,
                              ),
                            ),
                            if (tool.description.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  tool.description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 多技能压缩包批量勾选导入对话框
class _BatchSkillImportDialog extends StatefulWidget {
  final List<SkillPackage> packages;
  final Set<String> existingIdsLower;

  const _BatchSkillImportDialog({
    required this.packages,
    required this.existingIdsLower,
  });

  @override
  State<_BatchSkillImportDialog> createState() =>
      _BatchSkillImportDialogState();
}

class _BatchSkillImportDialogState extends State<_BatchSkillImportDialog> {
  late final Set<int> _selectedIndices;

  @override
  void initState() {
    super.initState();
    _selectedIndices = {
      for (var i = 0; i < widget.packages.length; i++)
        if (!widget.existingIdsLower.contains(
          widget.packages[i].skill.id.toLowerCase(),
        ))
          i,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return AppDialogScaffold(
      minimalChrome: true,
      title: l10n.skillBatchImportTitle,
      width: 560,
      height: 480,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.skillBatchImportSubtitle(widget.packages.length),
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: widget.packages.length,
                separatorBuilder: (_, _) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final pkg = widget.packages[index];
                  final skill = pkg.skill;
                  final conflict = widget.existingIdsLower.contains(
                    skill.id.toLowerCase(),
                  );
                  final checked = _selectedIndices.contains(index);
                  return AppCard(
                    isSelected: checked && !conflict,
                    onTap: conflict
                        ? null
                        : () => setState(() {
                            if (checked) {
                              _selectedIndices.remove(index);
                            } else {
                              _selectedIndices.add(index);
                            }
                          }),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    radius: AppRadius.md,
                    child: Row(
                      children: [
                        AppCheckbox(
                          value: checked && !conflict,
                          size: 16,
                          onChanged: conflict
                              ? null
                              : (v) => setState(() {
                                  if (v) {
                                    _selectedIndices.add(index);
                                  } else {
                                    _selectedIndices.remove(index);
                                  }
                                }),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      skill.name,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: conflict
                                            ? colors.textMuted
                                            : colors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (conflict)
                                    AppBadge(
                                      label: l10n.skillBatchImportConflict,
                                      variant: AppBadgeVariant.error,
                                      fontSize: 10,
                                    )
                                  else if (skill.resourcePaths.isNotEmpty)
                                    AppBadge(
                                      label: l10n.skillPackageFiles(
                                        skill.resourcePaths.length,
                                      ),
                                      variant: AppBadgeVariant.neutral,
                                      fontSize: 10,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(
                                skill.id,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontFamily: 'monospace',
                                  color: colors.textSecondary,
                                ),
                              ),
                              if (skill.description.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(
                                  skill.description,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: l10n.skillBatchImportButton(_selectedIndices.length),
          variant: AppActionButtonVariant.primary,
          onPressed: _selectedIndices.isEmpty
              ? null
              : () => Navigator.of(context).pop([
                  for (final i in _selectedIndices.toList()..sort())
                    widget.packages[i],
                ]),
        ),
      ],
    );
  }
}
