import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../data/models/skill_package.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/preset_transfer_service.dart';
import '../../../../data/services/skill_package_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/skill_error_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_control_flow.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../studio/view_models/studio_view_model.dart';
import 'settings_shared.dart';
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
  bool _loadingForm = false;

  late final TextEditingController nameController;
  late final TextEditingController descController;
  late final TextEditingController promptController;

  AgentPreset get currentPreset => presets.firstWhere(
    (p) => p.id == selectedPresetId,
    orElse: () => presets.first,
  );

  /// 将表单内容写回当前编辑的预设条目
  void syncFromForm([String? fallbackName]) {
    if (_loadingForm || currentPreset.isBuiltin) return;
    final idx = presets.indexWhere((p) => p.id == selectedPresetId);
    if (idx >= 0) {
      presets[idx] = presets[idx].copyWith(
        name: nameController.text.trim().isEmpty
            ? (fallbackName ?? '自定义预设')
            : nameController.text,
        description: descController.text,
        systemPrompt: promptController.text,
      );
    }
  }

  /// 载入指定预设到表单
  void loadPresetToForm(AgentPreset preset) {
    _loadingForm = true;
    try {
      selectedPresetId = preset.id;
      nameController.text = preset.name;
      descController.text = preset.description;
      promptController.text = preset.systemPrompt;
    } finally {
      _loadingForm = false;
    }
  }

  void appendImportedPresets(
    List<AgentPreset> imported, [
    String? fallbackName,
  ]) {
    if (imported.isEmpty) return;
    syncFromForm(fallbackName);
    presets.addAll(imported);
    loadPresetToForm(imported.first);
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

  /// 批量设置预设内的技能
  void setAllSkills(List<String> skillIds, [String? fallbackName]) {
    syncFromForm(fallbackName);
    _replaceListField(
      write: (p, v) => p.copyWith(enabledSkillIds: v),
      values: skillIds,
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

  /// 批量设置预设内的工具
  void setAllTools(List<String> toolNames, [String? fallbackName]) {
    syncFromForm(fallbackName);
    _replaceListField(
      write: (p, v) => p.copyWith(enabledToolNames: v),
      values: toolNames,
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

  /// 批量设置预设内允许修改的生图参数
  void setAllParams(List<String> paramKeys, [String? fallbackName]) {
    syncFromForm(fallbackName);
    _replaceListField(
      write: (p, v) => p.copyWith(allowedModifiableParams: v),
      values: paramKeys,
    );
  }

  /// 开关预设是否允许通过 CodeMode 调用已连接的 MCP 工具
  void setAllowMcpTools(bool allow, [String? fallbackName]) {
    syncFromForm(fallbackName);
    final idx = presets.indexWhere((p) => p.id == selectedPresetId);
    if (idx < 0 || presets[idx].isBuiltin) return;
    presets[idx] = presets[idx].copyWith(allowMcpTools: allow);
  }

  void _replaceListField({
    required AgentPreset Function(AgentPreset, List<String>) write,
    required List<String> values,
  }) {
    final idx = presets.indexWhere((p) => p.id == selectedPresetId);
    if (idx < 0 || presets[idx].isBuiltin) return;
    presets[idx] = write(presets[idx], List<String>.of(values));
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
  final VoidCallback? onOpenExtensionsTab;

  const PresetsSettingsTab({
    super.key,
    required this.viewModel,
    required this.draft,
    this.onOpenExtensionsTab,
  });

  @override
  State<PresetsSettingsTab> createState() => _PresetsSettingsTabState();
}

enum _SkillImportSource { file, folder, paste }

class _PresetsSettingsTabState extends State<PresetsSettingsTab> {
  PresetsSettingsDraft get _draft => widget.draft;
  late final SmoothWheelScrollController _scrollController;
  final TextEditingController _skillSearchController = TextEditingController();
  final TextEditingController _toolSearchController = TextEditingController();
  bool _copiedPrompt = false;
  Timer? _copyPromptTimer;

  void _syncSelectedAndRebuild() {
    if (!mounted) return;
    setState(() => _draft.syncFromForm(context.l10n.presetDefaultCustomName));
  }

  void _onFilterChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _scrollController = SmoothWheelScrollController();
    _draft.nameController.addListener(_syncSelectedAndRebuild);
    _skillSearchController.addListener(_onFilterChanged);
    _toolSearchController.addListener(_onFilterChanged);
  }

  @override
  void dispose() {
    _copyPromptTimer?.cancel();
    _scrollController.dispose();
    _draft.nameController.removeListener(_syncSelectedAndRebuild);
    _skillSearchController.removeListener(_onFilterChanged);
    _toolSearchController.removeListener(_onFilterChanged);
    _skillSearchController.dispose();
    _toolSearchController.dispose();
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
    showAppToast(
      context,
      message: skillErrorText(context.l10n, error),
      tone: AppToastTone.error,
    );
  }

  void _enableImportedSkill(String id) {
    if (_draft.currentPreset.isBuiltin) {
      setState(() {});
      showAppToast(
        context,
        message: context.l10n.skillImportedEnableHint,
        tone: AppToastTone.info,
      );
    } else {
      setState(() => _draft.toggleSkill(id, true));
    }
  }

  void _showPresetError(Object error) {
    if (!mounted) return;
    final l10n = context.l10n;
    final message = switch (error) {
      PresetImportException(code: PresetImportError.invalidJson) =>
        l10n.presetImportInvalidJson,
      PresetImportException(
        code: PresetImportError.invalidField,
        :final detail,
      ) =>
        l10n.presetImportInvalidField(detail),
      PresetImportException(
        code: PresetImportError.unknownTool,
        :final detail,
      ) =>
        l10n.presetImportUnknownTool(detail),
      PresetImportException(
        code: PresetImportError.unknownParameter,
        :final detail,
      ) =>
        l10n.presetImportUnknownParameter(detail),
      _ => l10n.presetTransferFailed(error.toString()),
    };
    showAppToast(context, message: message, tone: AppToastTone.error);
  }

  void _copySystemPrompt() {
    Clipboard.setData(ClipboardData(text: _draft.promptController.text));
    _copyPromptTimer?.cancel();
    setState(() => _copiedPrompt = true);
    _copyPromptTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copiedPrompt = false);
    });
    showAppToast(
      context,
      message: context.l10n.presetCopiedPrompt,
      tone: AppToastTone.success,
      duration: const Duration(milliseconds: 1400),
    );
  }

  Future<void> _confirmDeletePreset(AgentPreset preset) async {
    if (_draft.presets.length <= 1 || preset.isBuiltin) return;
    final l10n = context.l10n;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.presetConfirmDeleteTitle,
      message: l10n.presetConfirmDeleteMessage(preset.name),
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      setState(
        () => _draft.deletePreset(preset.id, l10n.presetDefaultCustomName),
      );
    }
  }

  Future<void> _importPresets() async {
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );
      if (picked == null || !mounted) return;
      final file = picked.files.single;
      final source = file.bytes != null
          ? utf8.decode(file.bytes!)
          : file.path != null
          ? await File(file.path!).readAsString()
          : null;
      if (!mounted) return;
      if (source == null) {
        throw const PresetImportException(PresetImportError.invalidJson);
      }
      final imported = PresetTransferService.decode(
        source,
        existing: _draft.presets,
        availableToolNames: widget.viewModel.availableTools.map((t) => t.name),
      );
      setState(
        () => _draft.appendImportedPresets(
          imported,
          context.l10n.presetDefaultCustomName,
        ),
      );
      showAppToast(
        context,
        message: context.l10n.presetImportedDraft(imported.length),
        tone: AppToastTone.success,
      );
    } catch (error) {
      _showPresetError(error);
    }
  }

  Future<void> _exportPreset() async {
    try {
      _draft.syncFromForm(context.l10n.presetDefaultCustomName);
      final bytes = Uint8List.fromList(
        utf8.encode(PresetTransferService.encode(_draft.currentPreset)),
      );
      final path = await FilePicker.platform.saveFile(
        dialogTitle: context.l10n.presetExportButton,
        fileName: 'agent-preset.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: _isMobile ? bytes : null,
      );
      if (path == null) return;
      if (!_isMobile) await File(path).writeAsBytes(bytes);
    } catch (error) {
      _showPresetError(error);
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
        minimalChrome: true,
        title: l10n.skillDialogImportTitle,
        width: 460,
        body: Padding(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSoftContainer(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Text(
                  l10n.skillPackageImportHelp,
                  style: TextStyle(
                    fontSize: 12,
                    color: ctx.colors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _ImportOptionCard(
                icon: Icons.file_open_outlined,
                title: l10n.skillImportFile,
                description: l10n.skillImportFileDesc,
                onTap: () => Navigator.of(ctx).pop(_SkillImportSource.file),
              ),
              if (_isDesktop) ...[
                const SizedBox(height: 8),
                _ImportOptionCard(
                  icon: Icons.folder_open_outlined,
                  title: l10n.skillImportFolder,
                  description: l10n.skillImportFolderDesc,
                  onTap: () => Navigator.of(ctx).pop(_SkillImportSource.folder),
                ),
              ],
              const SizedBox(height: 8),
              _ImportOptionCard(
                icon: Icons.content_paste_outlined,
                title: l10n.skillImportPaste,
                description: l10n.skillImportPasteDesc,
                onTap: () => Navigator.of(ctx).pop(_SkillImportSource.paste),
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
        // 移动端 .skill 无标准 MIME，且部分 SAF 文档不暴露本地路径，需同时拉取 bytes 并保留原始文件名。
        final picked = await FilePicker.platform.pickFiles(
          type: _isMobile ? FileType.any : FileType.custom,
          allowedExtensions: _isMobile ? null : const ['zip', 'skill', 'md'],
          withData: _isMobile,
        );
        if (picked == null || !mounted) return;
        final file = picked.files.single;
        final bytes = file.bytes;
        if (bytes != null && bytes.isNotEmpty) {
          package = await widget.viewModel.readSkillImportBytes(
            bytes,
            file.name,
          );
        } else {
          final path = file.path;
          if (path == null || path.isEmpty) {
            throw FormatException(l10n.skillFileUnreadable);
          }
          package = await widget.viewModel.readSkillImportFile(
            path,
            filename: file.name,
          );
        }
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
          initialRawMode: imported == null,
          previewFiles: imported?.files,
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
      setState(() => _draft.replaceSkillReferences(skill.id, result.id));
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
      if (mounted) setState(() => _draft.replaceSkillReferences(skill.id, null));
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

  Future<void> _deleteTool(AgentTool tool) async {
    final l10n = context.l10n;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.toolConfirmDeleteTitle,
      message: l10n.toolConfirmDeleteMessage(tool.label),
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed != true || !mounted) return;
    await widget.viewModel.deleteCustomTool(tool.name);
    if (mounted) setState(() => _draft.toggleTool(tool.name, false));
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final currentPreset = _draft.currentPreset;
    final isSelectedActive = currentPreset.id == _draft.activePresetId;

    final availableSkills = widget.viewModel.availableSkills;
    // MCP 工具归入「技能与 MCP」独立管理并通过 CodeMode 按需索引，不挤占预设静态工具网格
    final availableTools = widget.viewModel.availableTools
        .where((t) => !t.name.startsWith('mcp_'))
        .toList();

    final skillQuery = _skillSearchController.text.trim().toLowerCase();
    final filteredSkills = skillQuery.isEmpty
        ? availableSkills
        : availableSkills
              .where(
                (s) =>
                    s.name.toLowerCase().contains(skillQuery) ||
                    s.id.toLowerCase().contains(skillQuery) ||
                    s.description.toLowerCase().contains(skillQuery),
              )
              .toList();

    final toolQuery = _toolSearchController.text.trim().toLowerCase();
    final filteredTools = toolQuery.isEmpty
        ? availableTools
        : availableTools
              .where(
                (t) =>
                    t.label.toLowerCase().contains(toolQuery) ||
                    t.name.toLowerCase().contains(toolQuery) ||
                    t.description.toLowerCase().contains(toolQuery),
              )
              .toList();

    final enabledSkillCount = availableSkills
        .where((s) => currentPreset.enabledSkillIds.contains(s.id))
        .length;
    final enabledToolCount = availableTools
        .where((t) => currentPreset.isToolEnabled(t.name))
        .length;
    final enabledParamCount = PresetParamKeys.all
        .where(currentPreset.isParamModifiable)
        .length;

    return LayoutBuilder(
      builder: (context, outerConstraints) {
        final hPad = outerConstraints.maxWidth < 560 ? 16.0 : 28.0;
        return SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. 预设快捷选择条 + 管理操作坞
              AppSectionHeader(
                title: l10n.settingsSectionPresetSelection,
                subtitle: l10n.presetCurrentPresetSubtitle,
                trailing: AppControlFlow(
                  spacing: 6,
                  children: [
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
                    AppActionButton(
                      icon: Icons.file_open_outlined,
                      label: l10n.presetImportButton,
                      onPressed: _importPresets,
                    ),
                    AppActionButton(
                      icon: Icons.download_outlined,
                      label: l10n.presetExportButton,
                      onPressed: _exportPreset,
                    ),
                  ],
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _draft.presets.map((p) {
                  return _PresetPill(
                    preset: p,
                    isSelected: p.id == _draft.selectedPresetId,
                    isActiveDefault: p.id == _draft.activePresetId,
                    defaultBadgeLabel: l10n.presetBadgeActiveDefault,
                    onTap: () => setState(
                      () => _draft.switchPreset(
                        p.id,
                        l10n.presetDefaultCustomName,
                      ),
                    ),
                  );
                }).toList(),
              ),

              const SizedBox(height: 18),

              // 2. 预设基础信息与系统提示词
              AppSectionHeader(
                title: l10n.settingsSectionPresetProfile,
                trailing: AppControlFlow(
                  spacing: 6,
                  children: [
                    if (isSelectedActive)
                      AppBadge(
                        icon: Icons.check_circle_outline_rounded,
                        label: l10n.presetBadgeActiveDefault,
                        variant: AppBadgeVariant.primary,
                        fontSize: 11,
                      )
                    else
                      AppActionButton(
                        icon: Icons.check_circle_outline_rounded,
                        label: l10n.presetSetAsActiveDefault,
                        iconSize: 14,
                        onPressed: () => setState(
                          () => _draft.setActivePreset(currentPreset.id),
                        ),
                      ),
                    if (_draft.presets.length > 1 && !currentPreset.isBuiltin)
                      AppIconButton(
                        icon: Icons.delete_outline_rounded,
                        iconSize: 17,
                        size: 30,
                        variant: AppIconButtonVariant.ghost,
                        iconColor: colors.error,
                        tooltip: l10n.presetDeleteTooltip,
                        onPressed: () => _confirmDeletePreset(currentPreset),
                      ),
                  ],
                ),
              ),
              AppPanelReveal(
                visible: currentPreset.isBuiltin,
                enableBlur: false,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: SettingsSoftContainer(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.lock_outline_rounded,
                          size: 15,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            l10n.presetBuiltinNotice,
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SettingsInlineLink(
                          label: l10n.presetDuplicateToEdit,
                          icon: Icons.copy_rounded,
                          onTap: () => setState(
                            () => _draft.duplicatePreset(
                              currentPreset,
                              duplicateName: l10n.presetDuplicateName(
                                currentPreset.name,
                              ),
                              fallbackName: l10n.presetDefaultCustomName,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              AppCard(
                padding: const EdgeInsets.all(16),
                radius: AppRadius.lg,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final twoCol = constraints.maxWidth >= 480;
                    final nameField = _buildLabeledField(
                      label: l10n.presetDisplayName,
                      controller: _draft.nameController,
                      hintText: l10n.presetDisplayNameHint,
                      readOnly: currentPreset.isBuiltin,
                    );
                    final descField = _buildLabeledField(
                      label: l10n.presetDescription,
                      controller: _draft.descController,
                      hintText: l10n.presetDescriptionHint,
                      readOnly: currentPreset.isBuiltin,
                    );

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (twoCol)
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(flex: 4, child: nameField),
                              const SizedBox(width: 12),
                              Expanded(flex: 6, child: descField),
                            ],
                          )
                        else ...[
                          nameField,
                          const SizedBox(height: 10),
                          descField,
                        ],
                        const SizedBox(height: 12),
                        SettingsFieldLabel(
                          label: l10n.presetSystemPrompt,
                          trailing: InkWell(
                            onTap: _copySystemPrompt,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 2,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  AppIconSwap(
                                    swapKey: _copiedPrompt,
                                    enableBlur: false,
                                    child: _copiedPrompt
                                        ? AppSuccessCheck(
                                            key: const ValueKey<bool>(true),
                                            size: 13,
                                            color: colors.success,
                                          )
                                        : Icon(
                                            Icons.copy_rounded,
                                            key: const ValueKey<bool>(false),
                                            size: 13,
                                            color: colors.primary,
                                          ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    l10n.presetCopyPrompt,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w500,
                                      color: _copiedPrompt
                                          ? colors.success
                                          : colors.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _draft.promptController,
                          maxLines: 7,
                          readOnly: currentPreset.isBuiltin,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            height: 1.48,
                          ),
                          decoration: settingsSoftInputDecoration(
                            context,
                            hintText: l10n.presetSystemPromptHint,
                            readOnly: currentPreset.isBuiltin,
                            contentPadding: const EdgeInsets.all(12),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),

              const SizedBox(height: 20),

              // 3. 可用 Skill 库
              AppSectionHeader(
                title:
                    '${l10n.settingsSectionAvailableSkills} ($enabledSkillCount/${availableSkills.length})',
                trailing: AppControlFlow(
                  spacing: 6,
                  children: [
                    if (widget.onOpenExtensionsTab != null)
                      AppActionButton(
                        icon: Icons.extension_outlined,
                        label: l10n.skillManageLibraryButton,
                        iconSize: 14,
                        onPressed: widget.onOpenExtensionsTab,
                      ),
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
              if (availableSkills.length > 4 || !currentPreset.isBuiltin) ...[
                _buildFilterStrip(
                  controller: _skillSearchController,
                  searchHint: l10n.skillSearchHint,
                  showSearch: availableSkills.length > 4,
                  showBulkActions: !currentPreset.isBuiltin,
                  onEnableAll: () => setState(
                    () => _draft.setAllSkills(
                      availableSkills.map((s) => s.id).toList(),
                      l10n.presetDefaultCustomName,
                    ),
                  ),
                  onDisableAll: () => setState(
                    () => _draft.setAllSkills(
                      const [],
                      l10n.presetDefaultCustomName,
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (filteredSkills.isEmpty)
                AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: l10n.skillNoMatching,
                  isCompact: true,
                )
              else
                _buildResponsiveGrid(
                  itemCount: filteredSkills.length,
                  itemBuilder: (index, cardWidth) {
                    final skill = filteredSkills[index];
                    final isEnabled = currentPreset.enabledSkillIds.contains(
                      skill.id,
                    );
                    final isOverridden = widget.viewModel
                        .isBuiltinSkillOverridden(skill.id);
                    return SkillCard(
                      width: cardWidth,
                      skill: skill,
                      isEnabled: isEnabled,
                      isOverridden: isOverridden,
                      onToggle: currentPreset.isBuiltin
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
                      onResetDefault: isOverridden
                          ? () => _resetBuiltinSkill(skill)
                          : null,
                      onDelete: !skill.isBuiltin
                          ? () => _deleteSkill(skill)
                          : null,
                    );
                  },
                ),

              const SizedBox(height: 22),

              // 4. 开放工具库
              AppSectionHeader(
                title:
                    '${l10n.settingsSectionEnabledTools} ($enabledToolCount/${availableTools.length})',
                trailing: AppActionButton(
                  icon: Icons.add_rounded,
                  label: l10n.presetNewCustomTool,
                  onPressed: _openNewToolDialog,
                ),
              ),
              SettingsSoftContainer(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.hub_outlined,
                      size: 16,
                      color: currentPreset.allowMcpTools
                          ? colors.primary
                          : colors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.presetAllowMcpTools,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            l10n.presetAllowMcpToolsHint,
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.textSecondary,
                              height: 1.35,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    AppSwitch(
                      value: currentPreset.allowMcpTools,
                      width: 36,
                      height: 20,
                      onChanged: currentPreset.isBuiltin
                          ? null
                          : (val) => setState(
                              () => _draft.setAllowMcpTools(
                                val,
                                l10n.presetDefaultCustomName,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              _buildFilterStrip(
                controller: _toolSearchController,
                searchHint: l10n.toolSearchHint,
                showSearch: availableTools.length > 4,
                showBulkActions: !currentPreset.isBuiltin,
                onEnableAll: () => setState(
                  () => _draft.setAllTools(
                    availableTools.map((t) => t.name).toList(),
                    l10n.presetDefaultCustomName,
                  ),
                ),
                onDisableAll: () => setState(
                  () => _draft.setAllTools(
                    const [],
                    l10n.presetDefaultCustomName,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              if (filteredTools.isEmpty)
                AppEmptyState(
                  icon: Icons.search_off_rounded,
                  title: l10n.toolNoMatching,
                  isCompact: true,
                )
              else
                _buildResponsiveGrid(
                  itemCount: filteredTools.length,
                  itemBuilder: (index, cardWidth) {
                    final tool = filteredTools[index];
                    final isEnabled = currentPreset.isToolEnabled(tool.name);
                    return ToolCard(
                      width: cardWidth,
                      tool: tool,
                      isEnabled: isEnabled,
                      onToggle: currentPreset.isBuiltin
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
                      onDelete: !tool.isBuiltin
                          ? () => _deleteTool(tool)
                          : null,
                    );
                  },
                ),

              const SizedBox(height: 22),

              // 5. 生图参数控制权限 (Notion 柔底无框胶囊组，对齐元数据弹窗筛选区)
              AppSectionHeader(
                title:
                    '${l10n.settingsSectionModifiableParams} ($enabledParamCount/${PresetParamKeys.all.length})',
                trailing: !currentPreset.isBuiltin
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SettingsInlineLink(
                            label: l10n.presetEnableAll,
                            onTap: () => setState(
                              () => _draft.setAllParams(
                                PresetParamKeys.all,
                                l10n.presetDefaultCustomName,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          SettingsInlineLink(
                            label: l10n.presetDisableAll,
                            onTap: () => setState(
                              () => _draft.setAllParams(
                                const [],
                                l10n.presetDefaultCustomName,
                              ),
                            ),
                          ),
                        ],
                      )
                    : null,
              ),
              SettingsSoftContainer(
                padding: const EdgeInsets.all(12),
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
                    return AppToolChip(
                      label: label,
                      isSelected: isAllowed,
                      variant: AppToolChipVariant.tinted,
                      unselectedBackgroundColor: colors.cardBackground,
                      onTap: currentPreset.isBuiltin
                          ? null
                          : () => setState(
                              () => _draft.toggleParam(
                                key,
                                !isAllowed,
                                l10n.presetDefaultCustomName,
                              ),
                            ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterStrip({
    required TextEditingController controller,
    required String searchHint,
    required bool showSearch,
    required bool showBulkActions,
    required VoidCallback onEnableAll,
    required VoidCallback onDisableAll,
  }) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final searchField = SizedBox(
          width: constraints.maxWidth >= 520 ? 260 : double.infinity,
          child: AppSearchField(
            controller: controller,
            hintText: searchHint,
            height: 32,
            fontSize: 12,
            debounceDuration: Duration.zero,
            onChanged: (_) {},
          ),
        );
        final bulkActions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsInlineLink(label: l10n.presetEnableAll, onTap: onEnableAll),
            const SizedBox(width: 6),
            SettingsInlineLink(
              label: l10n.presetDisableAll,
              onTap: onDisableAll,
            ),
          ],
        );

        if (showSearch && showBulkActions && constraints.maxWidth >= 520) {
          return Row(
            children: [searchField, const Spacer(), bulkActions],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showSearch) searchField,
            if (showSearch && showBulkActions) const SizedBox(height: 6),
            if (showBulkActions)
              Align(alignment: Alignment.centerRight, child: bulkActions),
          ],
        );
      },
    );
  }

  Widget _buildResponsiveGrid({
    required int itemCount,
    required Widget Function(int index, double cardWidth) itemBuilder,
  }) {
    const spacing = 10.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 270).floor().clamp(1, 3);
        final cardWidth =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (var i = 0; i < itemCount; i++) itemBuilder(i, cardWidth),
          ],
        );
      },
    );
  }

  /// 预设表单内带标签的单行输入框
  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    required String hintText,
    bool readOnly = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsFieldLabel(label: label),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: TextField(
            controller: controller,
            readOnly: readOnly,
            style: const TextStyle(fontSize: 12),
            decoration: settingsSoftInputDecoration(
              context,
              hintText: hintText,
              readOnly: readOnly,
            ),
          ),
        ),
      ],
    );
  }
}

/// 顶部预设快捷切换胶囊
class _PresetPill extends StatefulWidget {
  final AgentPreset preset;
  final bool isSelected;
  final bool isActiveDefault;
  final String defaultBadgeLabel;
  final VoidCallback onTap;

  const _PresetPill({
    required this.preset,
    required this.isSelected,
    required this.isActiveDefault,
    required this.defaultBadgeLabel,
    required this.onTap,
  });

  @override
  State<_PresetPill> createState() => _PresetPillState();
}

class _PresetPillState extends State<_PresetPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = widget.isSelected
        ? colors.primaryTint
        : (_hovered
              ? colors.mutedBackground.withValues(alpha: 0.8)
              : colors.elevatedBackground);
    final border = widget.isSelected
        ? colors.primary.withValues(alpha: 0.5)
        : colors.borderDefault;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.resolveDuration(context, AppMotionDurations.quick),
          curve: AppMotionCurves.smoothOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.preset.isBuiltin) ...[
                Icon(
                  Icons.lock_outline_rounded,
                  size: 12.5,
                  color: widget.isSelected ? colors.primary : colors.textMuted,
                ),
                const SizedBox(width: 5),
              ],
              Text(
                widget.preset.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.isSelected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: widget.isSelected ? colors.primary : colors.textPrimary,
                ),
              ),
              if (widget.isActiveDefault) ...[
                const SizedBox(width: 6),
                AppBadge(
                  label: widget.defaultBadgeLabel,
                  variant: widget.isSelected
                      ? AppBadgeVariant.primary
                      : AppBadgeVariant.neutral,
                  fontSize: 9.5,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 技能导入方式选择卡片 (Notion 风格可点击选项行)
class _ImportOptionCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _ImportOptionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      radius: AppRadius.md,
      backgroundColor: colors.elevatedBackground,
      borderColor: colors.borderDefault,
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colors.primaryTint,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Icon(icon, size: 17, color: colors.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colors.textMuted,
          ),
        ],
      ),
    );
  }
}
