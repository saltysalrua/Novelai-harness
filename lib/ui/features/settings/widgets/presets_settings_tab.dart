import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/theme/app_theme.dart';
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

  late final TextEditingController nameController;
  late final TextEditingController descController;
  late final TextEditingController promptController;

  AgentPreset get currentPreset => presets.firstWhere(
    (p) => p.id == selectedPresetId,
    orElse: () => presets.first,
  );

  /// 将表单内容写回当前编辑的预设条目
  void syncFromForm() {
    final idx = presets.indexWhere((p) => p.id == selectedPresetId);
    if (idx >= 0) {
      presets[idx] = presets[idx].copyWith(
        name: nameController.text.trim().isEmpty
            ? '自定义预设'
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
  void switchPreset(String newPresetId) {
    if (newPresetId == selectedPresetId) return;
    syncFromForm();
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
  void addNewPreset(List<String> allToolNames) {
    syncFromForm();
    final newPreset = AgentPreset(
      id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
      name: '新预设 ${presets.length + 1}',
      description: '自定义 Agent 预设描述',
      systemPrompt: '你是由 NovelAI Harness 驱动的绘画创作助手。',
      enabledSkillIds: const ['v5-architect'],
      enabledToolNames: allToolNames,
      allowedModifiableParams: PresetParamKeys.all,
      isBuiltin: false,
    );
    presets.add(newPreset);
    loadPresetToForm(newPreset);
  }

  /// 复制预设并载入表单
  void duplicatePreset(AgentPreset preset) {
    syncFromForm();
    final clone = preset.copyWith(
      id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
      name: '${preset.name} (副本)',
      isBuiltin: false,
    );
    presets.add(clone);
    loadPresetToForm(clone);
  }

  /// 删除指定预设 (至少保留一个)
  void deletePreset(String presetId) {
    if (presets.length <= 1) return;
    syncFromForm();
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
  void toggleSkill(String skillId, bool enable) {
    syncFromForm();
    _toggleListField(
      enabled: enable,
      read: (p) => p.enabledSkillIds,
      write: (p, v) => p.copyWith(enabledSkillIds: v),
      value: skillId,
    );
  }

  /// 开关预设内的工具
  void toggleTool(String toolName, bool enable) {
    syncFromForm();
    _toggleListField(
      enabled: enable,
      read: (p) => p.enabledToolNames,
      write: (p, v) => p.copyWith(enabledToolNames: v),
      value: toolName,
    );
  }

  /// 开关预设内允许修改的生图参数
  void toggleParam(String paramKey, bool enable) {
    syncFromForm();
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

class _PresetsSettingsTabState extends State<PresetsSettingsTab> {
  PresetsSettingsDraft get _draft => widget.draft;

  void _syncSelectedAndRebuild() {
    if (!mounted) return;
    setState(() => _draft.syncFromForm());
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

  Future<void> _openNewSkillDialog() async {
    final result = await showSettingsDialog<Skill>(
      context,
      (ctx) => const SkillEditorDialog(),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomSkill(result);
      setState(() => _draft.toggleSkill(result.id, true));
    }
  }

  Future<void> _openImportSkillDialog() async {
    final result = await showSettingsDialog<Skill>(
      context,
      (ctx) => const SkillEditorDialog(isImportMode: true),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomSkill(result);
      setState(() => _draft.toggleSkill(result.id, true));
    }
  }

  Future<void> _openEditSkillDialog(Skill skill) async {
    final result = await showSettingsDialog<Skill>(
      context,
      (ctx) => SkillEditorDialog(skill: skill),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomSkill(result);
      setState(() {});
    }
  }

  void _exportSkillMd(Skill skill) {
    Clipboard.setData(ClipboardData(text: skill.toSkillMd()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 Skill [${skill.name}] 为标准 SKILL.md 至剪贴板'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteSkill(String skillId) async {
    await widget.viewModel.deleteCustomSkill(skillId);
    if (mounted) setState(() => _draft.toggleSkill(skillId, false));
  }

  Future<void> _openNewToolDialog() async {
    final result = await showSettingsDialog<CustomAgentTool>(
      context,
      (ctx) => const ToolEditorDialog(),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomTool(result);
      setState(() => _draft.toggleTool(result.name, true));
    }
  }

  void _openInspectToolSchemaDialog(AgentTool tool) {
    showSettingsDialog(
      context,
      (ctx) => ToolEditorDialog(tool: tool, isReadOnlySchemaView: true),
    );
  }

  Future<void> _openEditToolDialog(CustomAgentTool tool) async {
    final result = await showSettingsDialog<CustomAgentTool>(
      context,
      (ctx) => ToolEditorDialog(tool: tool),
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
    final currentPreset = _draft.currentPreset;
    final isSelectedActive = currentPreset.id == _draft.activePresetId;

    final availableSkills = widget.viewModel.availableSkills;
    final availableTools = widget.viewModel.availableTools;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 顶部总选择与管理坞
        const SettingsGroupTitle('Preset Selection'),
        SettingsCard(
          title: '当前预设',
          subtitle: '选择要配置的 Agent 预设（系统提示词、可用技能、工具与参数权限）',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsIdDropdown(
                value: _draft.selectedPresetId,
                items: _draft.presets
                    .map(
                      (p) => DropdownMenuItem<String>(
                        value: p.id,
                        child: Row(
                          children: [
                            Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            if (p.id == _draft.activePresetId) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: AppTheme.notionBlue,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                                child: const Text(
                                  '当前默认',
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _draft.switchPreset(val));
                  }
                },
              ),
              const SizedBox(width: 8),

              // 设为默认按钮
              if (!isSelectedActive)
                SettingsActionButton(
                  icon: null,
                  label: '设为当前默认',
                  onPressed: () =>
                      setState(() => _draft.setActivePreset(currentPreset.id)),
                ),

              const SizedBox(width: 6),
              SettingsActionButton(
                icon: Icons.add_rounded,
                label: '新建',
                onPressed: () => setState(
                  () => _draft.addNewPreset(
                    widget.viewModel.availableTools.map((t) => t.name).toList(),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SettingsActionButton(
                icon: Icons.copy_rounded,
                label: '复制',
                iconSize: 14,
                onPressed: () =>
                    setState(() => _draft.duplicatePreset(currentPreset)),
              ),

              // 删除按钮 (多于1个且非内置时可删)
              if (_draft.presets.length > 1 && !currentPreset.isBuiltin) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                  tooltip: '删除此预设',
                  onPressed: () =>
                      setState(() => _draft.deletePreset(currentPreset.id)),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. 预设基础信息与系统提示词
        const SettingsGroupTitle('Preset Profile & System Prompt'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: _buildLabeledField(
                      label: '预设显示名称',
                      controller: _draft.nameController,
                      hintText: '如 V5 自然语言架构师',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: _buildLabeledField(
                      label: '预设描述',
                      controller: _draft.descController,
                      hintText: '如 擅长 V5 自然语言散文提示词...',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '系统提示词 (System Prompt - 作为对话首要根基指令)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _draft.promptController,
                maxLines: 6,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: '输入 AI 助手的核心人设与工作流指引...',
                  filled: true,
                  fillColor: AppTheme.paperWarmth,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 3. 可用 Skill 库 (Pi 标准按需加载小卡片组)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SettingsGroupTitle('Available Skills'),
            Row(
              children: [
                SettingsActionButton(
                  icon: Icons.file_upload_outlined,
                  label: '导入 SKILL.md',
                  iconSize: 14,
                  onPressed: _openImportSkillDialog,
                ),
                const SizedBox(width: 6),
                SettingsActionButton(
                  icon: Icons.add_rounded,
                  label: '新建 Skill',
                  onPressed: _openNewSkillDialog,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: availableSkills.map((skill) {
            final isEnabled = currentPreset.enabledSkillIds.contains(skill.id);
            return SkillCard(
              skill: skill,
              isEnabled: isEnabled,
              onToggle: (val) =>
                  setState(() => _draft.toggleSkill(skill.id, val)),
              onEdit: _openEditSkillDialog,
              onExport: _exportSkillMd,
              onDelete: !skill.isBuiltin ? () => _deleteSkill(skill.id) : null,
            );
          }).toList(),
        ),

        const SizedBox(height: 18),

        // 4. 开放工具库 (Enabled Tools 小卡片组)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SettingsGroupTitle('Enabled Tools'),
            SettingsActionButton(
              icon: Icons.add_rounded,
              label: '新建自定义工具',
              onPressed: _openNewToolDialog,
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: availableTools.map((tool) {
            final isEnabled = currentPreset.isToolEnabled(tool.name);
            return ToolCard(
              tool: tool,
              isEnabled: isEnabled,
              onToggle: (val) =>
                  setState(() => _draft.toggleTool(tool.name, val)),
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
        const SettingsGroupTitle('Modifiable Parameters'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PresetParamKeys.all.map((key) {
              final isAllowed = currentPreset.isParamModifiable(key);
              final label = PresetParamKeys.getLabel(key);
              return FilterChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isAllowed ? FontWeight.w600 : FontWeight.normal,
                    color: isAllowed
                        ? AppTheme.notionBlue
                        : AppTheme.textPrimary,
                  ),
                ),
                selected: isAllowed,
                onSelected: (val) =>
                    setState(() => _draft.toggleParam(key, val)),
                backgroundColor: AppTheme.surfaceVariant,
                selectedColor: AppTheme.notionBlue.withValues(alpha: 0.12),
                checkmarkColor: AppTheme.notionBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: isAllowed
                        ? AppTheme.notionBlue.withValues(alpha: 0.5)
                        : AppTheme.border,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  /// 预设表单内带标签的单行输入框
  Widget _buildLabeledField({
    required String label,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          style: const TextStyle(fontSize: 12),
          decoration: InputDecoration(
            isDense: true,
            hintText: hintText,
            filled: true,
            fillColor: AppTheme.paperWarmth,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: AppTheme.border),
            ),
          ),
        ),
      ],
    );
  }
}
