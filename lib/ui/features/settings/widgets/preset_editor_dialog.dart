import 'package:flutter/material.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../core/theme/app_theme.dart';

class PresetEditorDialog extends StatefulWidget {
  final AgentPreset preset;
  final bool isNew;

  const PresetEditorDialog({
    super.key,
    required this.preset,
    this.isNew = false,
  });

  static Future<AgentPreset?> show(
    BuildContext context, {
    required AgentPreset preset,
    bool isNew = false,
  }) {
    return showDialog<AgentPreset>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => PresetEditorDialog(preset: preset, isNew: isNew),
    );
  }

  @override
  State<PresetEditorDialog> createState() => _PresetEditorDialogState();
}

class _PresetEditorDialogState extends State<PresetEditorDialog> {
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _systemPromptController;
  late Set<String> _enabledSkillIds;
  late Set<String> _enabledToolNames;
  late Set<String> _allowedModifiableParams;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.preset.name);
    _descController = TextEditingController(text: widget.preset.description);
    _systemPromptController =
        TextEditingController(text: widget.preset.systemPrompt);
    _enabledSkillIds = Set.from(widget.preset.enabledSkillIds);
    _enabledToolNames = Set.from(
      widget.preset.enabledToolNames.isNotEmpty
          ? widget.preset.enabledToolNames
          : PresetToolKeys.all,
    );
    _allowedModifiableParams = Set.from(
      widget.preset.allowedModifiableParams.isNotEmpty
          ? widget.preset.allowedModifiableParams
          : PresetParamKeys.all,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  void _handleSave() {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('预设名称不能为空')),
      );
      return;
    }

    final updated = widget.preset.copyWith(
      name: name,
      description: _descController.text.trim(),
      systemPrompt: _systemPromptController.text.trim(),
      enabledSkillIds: _enabledSkillIds.toList(),
      enabledToolNames: _enabledToolNames.toList(),
      allowedModifiableParams: _allowedModifiableParams.toList(),
    );

    Navigator.of(context).pop(updated);
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.75).clamp(480.0, 960.0);
    final dialogHeight = (screenSize.height * 0.85).clamp(420.0, 920.0);

    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 顶部标题栏
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: const BoxDecoration(
                  color: AppTheme.surfaceElevated,
                  border: Border(bottom: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.tune_outlined,
                      size: 18,
                      color: AppTheme.notionBlue,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      widget.isNew ? '新建 Agent 预设' : '编辑 Agent 预设',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: AppTheme.stone,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
              ),

              // 2. 中间表单滚动区
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // 基础信息
                      _buildSectionTitle('基础信息'),
                      _buildTextField(
                        controller: _nameController,
                        label: '预设名称',
                        hint: '例如：V5 自然语言架构师',
                      ),
                      const SizedBox(height: 12),
                      _buildTextField(
                        controller: _descController,
                        label: '预设描述',
                        hint: '简要说明该预设的适用场景与风格特性',
                        maxLines: 2,
                      ),

                      const SizedBox(height: 20),
                      // 第一部分：系统提示词
                      _buildSectionTitle('一、系统提示词 (System Prompt)'),
                      const Text(
                        '定义 AI 助手的核心人设、工作流与交互规范。在对话启动时作为最高优先级指令注入。',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _systemPromptController,
                        minLines: 5,
                        maxLines: 12,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          height: 1.4,
                        ),
                        decoration: InputDecoration(
                          hintText: '输入系统提示词...',
                          filled: true,
                          fillColor: AppTheme.paperWarmth,
                          contentPadding: const EdgeInsets.all(12),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppTheme.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: AppTheme.border),
                          ),
                        ),
                      ),

                      const SizedBox(height: 20),
                      // 第二部分：可用的 Skill (按需加载)
                      _buildSectionTitle('二、可用的 Skill (Pi 标准按需加载)'),
                      const Text(
                        '勾选该预设允许调用的专业技能。系统仅在上下文注入轻量技能清单 (<available_skills>)，当任务匹配时由 Agent 通过 load_skill 按需动态调入完整指令。',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildSkillsSelector(),

                      const SizedBox(height: 20),
                      // 第三部分：开放工具与生图参数修改权限
                      _buildSectionTitle('三、开放工具与生图参数权限'),
                      const Text(
                        '配置 Agent 允许调用的功能工具，以及允许修改的工作台生图参数（修改后将实时同步工作台 UI 面板）。',
                        style: TextStyle(
                          fontSize: 11.5,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _buildToolsSelector(),
                      const SizedBox(height: 12),
                      _buildParamsSelector(),
                    ],
                  ),
                ),
              ),

              // 3. 底部操作栏
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: AppTheme.border)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        '取消',
                        style: TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.notionBlue,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      onPressed: _handleSave,
                      child: const Text(
                        '保存预设',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 1,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: controller,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 12.5),
          decoration: InputDecoration(
            hintText: hint,
            filled: true,
            fillColor: AppTheme.paperWarmth,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 10,
              vertical: 8,
            ),
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

  /// Skill 多选列表
  Widget _buildSkillsSelector() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: BuiltinSkills.all.map((skill) {
          final isSelected = _enabledSkillIds.contains(skill.id);
          return CheckboxListTile(
            value: isSelected,
            dense: true,
            activeColor: AppTheme.notionBlue,
            title: Text(
              skill.name,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary,
              ),
            ),
            subtitle: Text(
              skill.description,
              style: const TextStyle(
                fontSize: 11,
                color: AppTheme.textSecondary,
              ),
            ),
            onChanged: (val) {
              setState(() {
                if (val == true) {
                  _enabledSkillIds.add(skill.id);
                } else {
                  _enabledSkillIds.remove(skill.id);
                }
              });
            },
          );
        }).toList(),
      ),
    );
  }

  /// 开放工具多选区
  Widget _buildToolsSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '开放工具列表 (Enabled Tools)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: PresetToolKeys.labels.entries.map((entry) {
              final isEnabled = _enabledToolNames.contains(entry.key);
              return InkWell(
                onTap: () {
                  setState(() {
                    if (isEnabled) {
                      _enabledToolNames.remove(entry.key);
                    } else {
                      _enabledToolNames.add(entry.key);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: isEnabled,
                        activeColor: AppTheme.notionBlue,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _enabledToolNames.add(entry.key);
                            } else {
                              _enabledToolNames.remove(entry.key);
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  /// 生图参数修改权限勾选区
  Widget _buildParamsSelector() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '允许修改的生图参数权限 (Modifiable Studio Parameters)',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: PresetParamKeys.labels.entries.map((entry) {
              final isAllowed = _allowedModifiableParams.contains(entry.key);
              return InkWell(
                onTap: () {
                  setState(() {
                    if (isAllowed) {
                      _allowedModifiableParams.remove(entry.key);
                    } else {
                      _allowedModifiableParams.add(entry.key);
                    }
                  });
                },
                borderRadius: BorderRadius.circular(6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 20,
                      height: 20,
                      child: Checkbox(
                        value: isAllowed,
                        activeColor: AppTheme.notionBlue,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _allowedModifiableParams.add(entry.key);
                            } else {
                              _allowedModifiableParams.remove(entry.key);
                            }
                          });
                        },
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      entry.value,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}
