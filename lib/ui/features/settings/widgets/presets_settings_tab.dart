import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../data/models/skill_package.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/skill_package_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_control_flow.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../studio/view_models/studio_view_model.dart';
import 'skill_card.dart';
import 'skill_editor_dialog.dart';
import 'tool_card.dart';
import 'tool_editor_dialog.dart';

/// Presets 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class PresetsSettingsDraft {
  PresetsSettingsDraft(AppConfig config) {
    presets = (config.presets.isNotEmpty ? config.presets : BuiltinPresets.all)
        .map((p) => p.copyWith())
        .toList();
    activePresetId = config.activePresetId;
    if (!presets.any((p) => p.id == activePresetId)) {
      activePresetId = presets.first.id;
    }
    selectedPresetId = activePresetId;

    final current = currentPreset;
    nameController = TextEditingController(text: current.name);
    descController = TextEditingController(text: current.description);
    promptController = TextEditingController(text: current.systemPrompt);
  }

  late final List<AgentPreset> presets;
  late String selectedPresetId;
  late String activePresetId;

  late final TextEditingController nameController;
  late final TextEditingController descController;
  late final TextEditingController promptController;

  AgentPreset get currentPreset => presets.firstWhere(
    (p) => p.id == selectedPresetId,
    orElse: () => presets.first,
  );

  /// 将表单内容写回当前编辑的预设条目
  void syncFromForm([String? fallbackName]) {
    final idx = presets.indexWhere((p) => p.id == selectedPresetId);
    if (idx >= 0) {
      presets[idx] = presets[idx].copyWith(
        name: nameController.text.trim().isEmpty
            ? (fallbackName ?? '自定义预设')
            : nameController.text.trim(),
        description: descController.text.trim(),
        systemPrompt: promptController.text.trim(),
      );
    }
  }

  /// 载入指定预设到表单
  void loadPresetToForm(AgentPreset preset) {
    selectedPresetId = preset.id;
    nameController.text = preset.name;
    descController.text = preset.description;
    promptController.text = preset.systemPrompt;
  }

  /// 切换当前编辑的预设，切换前自动同步表单
  void switchPreset(String newPresetId, [String? fallbackName]) {
    if (newPresetId == selectedPresetId) return;
    syncFromForm(fallbackName);
    loadPresetToForm(
      presets.firstWhere(
        (p) => p.id == newPresetId,
        orElse: () => presets.first,
      ),
    );
  }

  /// 设为启动时生效的默认预设
  void setActivePreset(String presetId) {
    if (activePresetId == presetId) return;
    activePresetId = presetId;
  }

  /// 新建预设并载入表单
  void addNewPreset(
    List<String> allToolNames, {
    String? defaultName,
    String? defaultDescription,
    String? defaultPrompt,
    String? fallbackName,
  }) {
    syncFromForm(fallbackName);
    final newPreset = AgentPreset(
      id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
      name: defaultName ?? '新预设 ${presets.length + 1}',
      description: defaultDescription ?? '自定义 Agent 预设描述',
      systemPrompt: defaultPrompt ?? '你是由 NovelAI Harness 驱动的绘画创作助手。',
      enabledSkillIds: const ['v5-architect'],
      enabledToolNames: allToolNames,
      allowedModifiableParams: PresetParamKeys.all,
      isBuiltin: false,
    );
    presets.add(newPreset);
    loadPresetToForm(newPreset);
  }

  /// 复制预设并载入表单
  void duplicatePreset(
    AgentPreset preset, {
    String? duplicateName,
    String? fallbackName,
  }) {
    syncFromForm(fallbackName);
    final clone = preset.copyWith(
      id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
      name: duplicateName ?? '${preset.name} (副本)',
      isBuiltin: false,
    );
    presets.add(clone);
    loadPresetToForm(clone);
  }

  /// 删除指定预设 (至少保留一个)
  void deletePreset(String presetId, [String? fallbackName]) {
    if (presets.length <= 1) return;
    syncFromForm(fallbackName);
    presets.removeWhere((p) => p.id == presetId);
    if (selectedPresetId == presetId) {
      selectedPresetId = presets.first.id;
      loadPresetToForm(presets.first);
    }
    if (activePresetId == presetId) {
      activePresetId = presets.first.id;
    }
  }

  /// 开关预设内的技能
  void toggleSkill(String skillId, bool enable, [String? fallbackName]) {
    syncFromForm(fallbackName);
    _toggleListField(
      enabled: enable,
      read: (p) => p.enabledSkillIds,
      write: (p, v) => p.copyWith(enabledSkillIds: v),
      value: skillId,
    );
  }

  /// 开关预设内的工具
  void toggleTool(String toolName, bool enable, [String? fallbackName]) {
    syncFromForm(fallbackName);
    _toggleListField(
      enabled: enable,
      read: (p) => p.enabledToolNames,
      write: (p, v) => p.copyWith(enabledToolNames: v),
      value: toolName,
    );
  }

  /// 开关预设内允许修改的生图参数
  void toggleParam(String paramKey, bool enable, [String? fallbackName]) {
    syncFromForm(fallbackName);
    _toggleListField(
      enabled: enable,
      read: (p) => p.allowedModifiableParams,
      write: (p, v) => p.copyWith(allowedModifiableParams: v),
      value: paramKey,
    );
  }

  void _toggleListField({
    required bool enabled,
    required List<String> Function(AgentPreset) read,
    required AgentPreset Function(AgentPreset, List<String>) write,
    required String value,
  }) {
    final idx = presets.indexWhere((p) => p.id == selectedPresetId);
    if (idx < 0) return;
    final current = presets[idx];
    final list = read(current).toList();
    if (enabled) {
      if (!list.contains(value)) list.add(value);
    } else {
      list.remove(value);
    }
    presets[idx] = write(current, list);
  }

  void replaceSkillReferences(String oldId, String? newId) {
    syncFromForm();
    for (var index = 0; index < presets.length; index++) {
      final ids = presets[index].enabledSkillIds
          .map((id) => id == oldId ? newId : id)
          .whereType<String>()
          .toSet()
          .toList();
      presets[index] = presets[index].copyWith(enabledSkillIds: ids);
    }
  }

  void dispose() {
    nameController.dispose();
    descController.dispose();
    promptController.dispose();
  }
}

/// Presets 页：预设选择、系统提示词、技能库与工具权限管理
class PresetsSettingsTab extends StatefulWidget {
  final StudioViewModel viewModel;
  final PresetsSettingsDraft draft;

  const PresetsSettingsTab({
    super.key,
    required this.viewModel,
    required this.draft,
  });

  @override
  State<PresetsSettingsTab> createState() => _PresetsSettingsTabState();
}

enum _SkillImportSource { file, folder, paste }

class _PresetsSettingsTabState extends State<PresetsSettingsTab> {
  PresetsSettingsDraft get _draft => widget.draft;

  void _syncSelectedAndRebuild() {
    if (!mounted) return;
    setState(() => _draft.syncFromForm(context.l10n.presetDefaultCustomName));
  }

  @override
  void initState() {
    super.initState();
    // 名称变化实时同步到预设列表，供下拉框即时显示
    _draft.nameController.addListener(_syncSelectedAndRebuild);
  }

  @override
  void dispose() {
    _draft.nameController.removeListener(_syncSelectedAndRebuild);
    super.dispose();
  }

  bool get _isDesktop =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  /// 移动端由插件写入 bytes；macOS 传 bytes 会直接抛错，桌面统一自行落盘。
  bool get _isMobile =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.android || TargetPlatform.iOS => true,
        _ => false,
      };

  void _showSkillError(Object error) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          error is FormatException
              ? error.message
              : context.l10n.skillOperationFailed(error.toString()),
        ),
      ),
    );
  }

  void _enableImportedSkill(String id) {
    if (_draft.currentPreset.isBuiltin) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.skillImportedEnableHint)),
      );
    } else {
      setState(() => _draft.toggleSkill(id, true));
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
    if (result != null && mounted) _enableImportedSkill(result.id);
  }

  Future<void> _openImportSkillDialog() async {
    final l10n = context.l10n;
    final source = await AppDialogScaffold.show<_SkillImportSource>(
      context: context,
      builder: (ctx) => AppDialogScaffold(
        title: l10n.skillDialogImportTitle,
        width: 460,
        body: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.skillPackageImportHelp),
              const SizedBox(height: 16),
              AppControlFlow(
                children: [
                  AppActionButton(
                    icon: Icons.file_open_outlined,
                    label: l10n.skillImportFile,
                    onPressed: () =>
                        Navigator.of(ctx).pop(_SkillImportSource.file),
                  ),
                  if (_isDesktop)
                    AppActionButton(
                      icon: Icons.folder_open_outlined,
                      label: l10n.skillImportFolder,
                      onPressed: () =>
                          Navigator.of(ctx).pop(_SkillImportSource.folder),
                    ),
                  AppActionButton(
                    icon: Icons.content_paste_outlined,
                    label: l10n.skillImportPaste,
                    onPressed: () =>
                        Navigator.of(ctx).pop(_SkillImportSource.paste),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (source == null || !mounted) return;
    try {
      SkillPackage? package;
      if (source == _SkillImportSource.file) {
        // 移动端 .skill 无标准 MIME，交给本地扩展名校验；桌面用对话框过滤。
        final picked = await FilePicker.platform.pickFiles(
          type: _isMobile ? FileType.any : FileType.custom,
          allowedExtensions: _isMobile ? null : const ['zip', 'skill', 'md'],
        );
        if (picked == null || !mounted) return;
        final path = picked.files.single.path;
        if (path == null) throw const FormatException('无法读取所选文件。');
        package = await widget.viewModel.readSkillImportFile(path);
      } else if (source == _SkillImportSource.folder) {
        final path = await FilePicker.platform.getDirectoryPath();
        if (path == null || !mounted) return;
        package = await widget.viewModel.readSkillImportDirectory(path);
      }
      if (!mounted) return;
      final imported = package;
      final result = await AppDialogScaffold.show<Skill>(
        context: context,
        builder: (ctx) => SkillEditorDialog(
          skill: imported?.skill,
          isImportMode: true,
          onSave: (skill) async {
            if (imported == null) {
              await widget.viewModel.saveCustomSkill(skill, requireNew: true);
            } else {
              await widget.viewModel.importSkillPackage(imported, skill);
            }
          },
        ),
      );
      if (result != null && mounted) _enableImportedSkill(result.id);
    } catch (error) {
      _showSkillError(error);
    }
  }

  Future<void> _openEditSkillDialog(Skill skill) async {
    final result = await AppDialogScaffold.show<Skill>(
      context: context,
      builder: (ctx) => SkillEditorDialog(
        skill: skill,
        onSave: (edited) =>
            widget.viewModel.saveCustomSkill(edited, originalId: skill.id),
      ),
    );
    if (result != null && mounted) {
      setState(() => _draft.replaceSkillReferences(skill.id, result.id));
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.presetExportSkillSuccess(skill.name)),
        ),
      );
    } catch (error) {
      _showSkillError(error);
    }
  }

  Future<void> _deleteSkill(String skillId) async {
    try {
      await widget.viewModel.deleteCustomSkill(skillId);
      if (mounted) setState(() => _draft.replaceSkillReferences(skillId, null));
    } catch (error) {
      _showSkillError(error);
    }
  }

  Future<void> _openNewToolDialog() async {
    final result = await AppDialogScaffold.show<CustomAgentTool>(
      context: context,
      builder: (ctx) => const ToolEditorDialog(),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomTool(result);
      setState(() => _draft.toggleTool(result.name, true));
    }
  }

  void _openInspectToolSchemaDialog(AgentTool tool) {
    AppDialogScaffold.show(
      context: context,
      builder: (ctx) =>
          ToolEditorDialog(tool: tool, isReadOnlySchemaView: true),
    );
  }

  Future<void> _openEditToolDialog(CustomAgentTool tool) async {
    final result = await AppDialogScaffold.show<CustomAgentTool>(
      context: context,
      builder: (ctx) => ToolEditorDialog(tool: tool),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomTool(result);
      setState(() {});
    }
  }

  Future<void> _deleteTool(String toolName) async {
    await widget.viewModel.deleteCustomTool(toolName);
    if (mounted) setState(() => _draft.toggleTool(toolName, false));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final currentPreset = _draft.currentPreset;
    final isSelectedActive = currentPreset.id == _draft.activePresetId;

    final availableSkills = widget.viewModel.availableSkills;
    final availableTools = widget.viewModel.availableTools;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 顶部总选择与管理坞
          AppSectionHeader(title: l10n.settingsSectionPresetSelection),
          AppSettingTile(
            title: l10n.presetCurrentPreset,
            subtitle: l10n.presetCurrentPresetSubtitle,
            control: AppControlFlow(
              children: [
                AppDropdown<String>(
                  value: _draft.selectedPresetId,
                  width: 210,
                  items: _draft.presets
                      .map(
                        (p) => AppDropdownItem(
                          value: p.id,
                          label: p.name,
                          trailing: p.id == _draft.activePresetId
                              ? AppBadge(
                                  label: l10n.presetBadgeActiveDefault,
                                  fontSize: 9,
                                )
                              : null,
                        ),
                      )
                      .toList(),
                  onChanged: (val) => setState(
                    () =>
                        _draft.switchPreset(val, l10n.presetDefaultCustomName),
                  ),
                ),

                // 设为默认按钮
                if (!isSelectedActive)
                  AppActionButton(
                    label: l10n.presetSetAsActiveDefault,
                    onPressed: () => setState(
                      () => _draft.setActivePreset(currentPreset.id),
                    ),
                  ),

                AppActionButton(
                  icon: Icons.add_rounded,
                  label: l10n.presetNewButton,
                  onPressed: () => setState(
                    () => _draft.addNewPreset(
                      widget.viewModel.availableTools
                          .map((t) => t.name)
                          .toList(),
                      defaultName: l10n.presetNewName(
                        _draft.presets.length + 1,
                      ),
                      defaultDescription: l10n.presetNewDescription,
                      defaultPrompt: l10n.presetNewSystemPrompt,
                      fallbackName: l10n.presetDefaultCustomName,
                    ),
                  ),
                ),
                AppActionButton(
                  icon: Icons.copy_rounded,
                  label: l10n.copy,
                  iconSize: 14,
                  onPressed: () => setState(
                    () => _draft.duplicatePreset(
                      currentPreset,
                      duplicateName: l10n.presetDuplicateName(
                        currentPreset.name,
                      ),
                      fallbackName: l10n.presetDefaultCustomName,
                    ),
                  ),
                ),

                // 删除按钮 (多于1个且非内置时可删)
                if (_draft.presets.length > 1 && !currentPreset.isBuiltin)
                  AppIconButton(
                    icon: Icons.delete_outline_rounded,
                    iconSize: 18,
                    variant: AppIconButtonVariant.ghost,
                    iconColor: colors.error,
                    tooltip: l10n.presetDeleteTooltip,
                    onPressed: () => setState(
                      () => _draft.deletePreset(
                        currentPreset.id,
                        l10n.presetDefaultCustomName,
                      ),
                    ),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // 2. 预设基础信息与系统提示词
          AppSectionHeader(title: l10n.settingsSectionPresetProfile),
          if (currentPreset.isBuiltin) ...[
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: colors.mutedBackground,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: colors.borderDefault),
              ),
              child: Text(
                l10n.presetBuiltinNotice,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
          ],
          AppCard(
            padding: const EdgeInsets.all(14),
            radius: AppRadius.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      flex: 4,
                      child: _buildLabeledField(
                        label: l10n.presetDisplayName,
                        controller: _draft.nameController,
                        hintText: l10n.presetDisplayNameHint,
                        readOnly: currentPreset.isBuiltin,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 6,
                      child: _buildLabeledField(
                        label: l10n.presetDescription,
                        controller: _draft.descController,
                        hintText: l10n.presetDescriptionHint,
                        readOnly: currentPreset.isBuiltin,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.presetSystemPrompt,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _draft.promptController,
                  maxLines: 6,
                  readOnly: currentPreset.isBuiltin,
                  style: const TextStyle(
                    fontSize: 12,
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                  decoration: _fieldDecoration(
                    hint: l10n.presetSystemPromptHint,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // 3. 可用 Skill 库 (Pi 标准按需加载小卡片组)
          AppSectionHeader(
            title: l10n.settingsSectionAvailableSkills,
            trailing: AppControlFlow(
              spacing: 6,
              children: [
                AppActionButton(
                  icon: Icons.file_upload_outlined,
                  label: l10n.presetImportSkill,
                  iconSize: 14,
                  onPressed: _openImportSkillDialog,
                ),
                AppActionButton(
                  icon: Icons.add_rounded,
                  label: l10n.presetNewSkill,
                  onPressed: _openNewSkillDialog,
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: availableSkills.map((skill) {
              final isEnabled = currentPreset.enabledSkillIds.contains(
                skill.id,
              );
              final isBuiltinPreset = currentPreset.isBuiltin;
              return SkillCard(
                skill: skill,
                isEnabled: isEnabled,
                onToggle: isBuiltinPreset
                    ? null
                    : (val) => setState(
                        () => _draft.toggleSkill(
                          skill.id,
                          val,
                          l10n.presetDefaultCustomName,
                        ),
                      ),
                onEdit: _openEditSkillDialog,
                onExport: _exportSkillPackage,
                onDelete: !skill.isBuiltin
                    ? () => _deleteSkill(skill.id)
                    : null,
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // 4. 开放工具库 (Enabled Tools 小卡片组)
          AppSectionHeader(
            title: l10n.settingsSectionEnabledTools,
            trailing: AppActionButton(
              icon: Icons.add_rounded,
              label: l10n.presetNewCustomTool,
              onPressed: _openNewToolDialog,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: availableTools.map((tool) {
              final isEnabled = currentPreset.isToolEnabled(tool.name);
              final isBuiltinPreset = currentPreset.isBuiltin;
              return ToolCard(
                tool: tool,
                isEnabled: isEnabled,
                onToggle: isBuiltinPreset
                    ? null
                    : (val) => setState(
                        () => _draft.toggleTool(
                          tool.name,
                          val,
                          l10n.presetDefaultCustomName,
                        ),
                      ),
                onInspectSchema: _openInspectToolSchemaDialog,
                onEditCustomTool: tool is CustomAgentTool
                    ? _openEditToolDialog
                    : null,
                onDelete: !tool.isBuiltin ? () => _deleteTool(tool.name) : null,
              );
            }).toList(),
          ),

          const SizedBox(height: 18),

          // 5. 生图参数控制权限 (Modifiable Parameters)
          AppSectionHeader(title: l10n.settingsSectionModifiableParams),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: PresetParamKeys.all.map((key) {
                final isAllowed = currentPreset.isParamModifiable(key);
                final label = switch (key) {
                  PresetParamKeys.prompt => l10n.presetParamPrompt,
                  PresetParamKeys.negativePrompt =>
                    l10n.presetParamNegativePrompt,
                  PresetParamKeys.model => l10n.presetParamModel,
                  PresetParamKeys.resolution => l10n.presetParamResolution,
                  PresetParamKeys.width => l10n.presetParamWidth,
                  PresetParamKeys.height => l10n.presetParamHeight,
                  PresetParamKeys.steps => l10n.presetParamSteps,
                  PresetParamKeys.scale => l10n.presetParamScale,
                  PresetParamKeys.cfgRescale => l10n.presetParamCfgRescale,
                  PresetParamKeys.sampler => l10n.presetParamSampler,
                  PresetParamKeys.noiseSchedule =>
                    l10n.presetParamNoiseSchedule,
                  PresetParamKeys.qualityPreset =>
                    l10n.presetParamQualityPreset,
                  PresetParamKeys.characterAiPosition =>
                    l10n.presetParamCharacterAiPosition,
                  _ => PresetParamKeys.getLabel(key),
                };
                return FilterChip(
                  label: Text(
                    label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isAllowed
                          ? FontWeight.w600
                          : FontWeight.normal,
                      color: isAllowed ? colors.primary : colors.textPrimary,
                    ),
                  ),
                  selected: isAllowed,
                  onSelected: currentPreset.isBuiltin
                      ? null
                      : (val) => setState(
                          () => _draft.toggleParam(
                            key,
                            val,
                            l10n.presetDefaultCustomName,
                          ),
                        ),
                  backgroundColor: colors.mutedBackground,
                  selectedColor: colors.primary.withValues(alpha: 0.12),
                  checkmarkColor: colors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                    side: BorderSide(
                      color: isAllowed
                          ? colors.primary.withValues(alpha: 0.5)
                          : colors.borderDefault,
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

  /// 预设表单内带标签的单行输入框
  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    bool readOnly = false,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          readOnly: readOnly,
          style: const TextStyle(fontSize: 12),
          decoration: _fieldDecoration(hint: hintText),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({required String hint}) {
    final colors = context.colors;
    return InputDecoration(
      isDense: true,
      hintText: hint,
      filled: true,
      fillColor: colors.mutedBackground,
      hoverColor: colors.mutedBackground,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: colors.borderDefault),
      ),
    );
  }
}
