import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_segmented_controls.dart';

/// Skill 查看 / 编辑 / 导入对话框 (支持 Pi 标准 SKILL.md 导入导出)
class SkillEditorDialog extends StatefulWidget {
  final Skill? skill;
  final bool isImportMode;

  const SkillEditorDialog({super.key, this.skill, this.isImportMode = false});

  @override
  State<SkillEditorDialog> createState() => _SkillEditorDialogState();
}

enum _SkillEditorViewMode { structured, raw }

class _SkillEditorDialogState extends State<SkillEditorDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _promptController;
  late final TextEditingController _rawMdController;

  bool _disableInvocation = false;
  _SkillEditorViewMode _viewMode = _SkillEditorViewMode.structured;

  @override
  void initState() {
    super.initState();
    final s = widget.skill;
    _idController = TextEditingController(text: s?.id ?? '');
    _nameController = TextEditingController(text: s?.name ?? '');
    _descController = TextEditingController(text: s?.description ?? '');
    _promptController = TextEditingController(text: s?.systemPrompt ?? '');
    _disableInvocation = s?.disableModelInvocation ?? false;

    _rawMdController = TextEditingController(
      text: s != null ? s.toSkillMd() : '',
    );
    _viewMode = widget.isImportMode
        ? _SkillEditorViewMode.raw
        : _SkillEditorViewMode.structured;
  }

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    _descController.dispose();
    _promptController.dispose();
    _rawMdController.dispose();
    super.dispose();
  }

  void _syncFromRaw() {
    final parsed = Skill.fromSkillMd(
      _rawMdController.text,
      defaultId: _idController.text.trim().isNotEmpty
          ? _idController.text.trim()
          : 'imported-skill',
    );
    setState(() {
      _idController.text = parsed.id;
      _nameController.text = parsed.name;
      _descController.text = parsed.description;
      _promptController.text = parsed.systemPrompt;
      _disableInvocation = parsed.disableModelInvocation;
    });
  }

  void _syncToRaw() {
    final skill = Skill(
      id: _idController.text.trim(),
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      systemPrompt: _promptController.text.trim(),
      disableModelInvocation: _disableInvocation,
    );
    _rawMdController.text = skill.toSkillMd();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isBuiltin = widget.skill?.isBuiltin ?? false;

    return AppDialogScaffold(
      title: widget.isImportMode
          ? '导入标准 SKILL.md'
          : (widget.skill == null
                ? '新建 Skill'
                : '编辑 Skill (${widget.skill!.name})'),
      width: 680,
      height: 640,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 视图切换模式
            Row(
              children: [
                AppSegmentedPillBar<_SkillEditorViewMode>(
                  items: const [
                    AppSegmentedItem(
                      value: _SkillEditorViewMode.structured,
                      label: '结构化编辑',
                    ),
                    AppSegmentedItem(
                      value: _SkillEditorViewMode.raw,
                      label: 'SKILL.md 源码',
                    ),
                  ],
                  selectedValue: _viewMode,
                  onValueChanged: (mode) {
                    if (mode == _SkillEditorViewMode.structured &&
                        _viewMode == _SkillEditorViewMode.raw) {
                      _syncFromRaw();
                    } else if (mode == _SkillEditorViewMode.raw &&
                        _viewMode == _SkillEditorViewMode.structured) {
                      _syncToRaw();
                    }
                    setState(() => _viewMode = mode);
                  },
                ),
                const Spacer(),
                Icon(
                  widget.isImportMode
                      ? Icons.file_upload_outlined
                      : Icons.psychology_outlined,
                  size: 20,
                  color: colors.primary,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // 正文区
            Expanded(
              child: _viewMode == _SkillEditorViewMode.raw
                  ? _buildRawEditor()
                  : _buildStructuredEditor(isBuiltin),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          children: [
            AppActionButton(
              label: '复制 SKILL.md',
              icon: Icons.copy_rounded,
              onPressed: () {
                _syncToRaw();
                Clipboard.setData(ClipboardData(text: _rawMdController.text));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('已复制标准 SKILL.md 内容至剪贴板'),
                    duration: Duration(seconds: 2),
                  ),
                );
              },
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('取消', style: TextStyle(color: colors.textSecondary)),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: colors.primary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              onPressed: _save,
              child: const Text('保存 Skill'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStructuredEditor(bool isBuiltin) {
    final colors = context.colors;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '标识',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _idController,
                      enabled: !isBuiltin,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: _fieldDecoration(
                        hint: '如 v5-architect',
                        filled: isBuiltin,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '名称',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 12),
                      decoration: _fieldDecoration(hint: '如 V5 自然语言架构师'),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '技能描述',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 12, height: 1.4),
            decoration: _fieldDecoration(hint: '简要说明该技能擅长处理的任务场景...'),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '技能指令',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              InkWell(
                onTap: () =>
                    setState(() => _disableInvocation = !_disableInvocation),
                borderRadius: BorderRadius.circular(4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: _disableInvocation,
                        visualDensity: VisualDensity.compact,
                        onChanged: (v) =>
                            setState(() => _disableInvocation = v ?? false),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '禁止自动调用',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _promptController,
            maxLines: 12,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: _fieldDecoration(
              hint: '输入该技能加载后生效的完整提示词与规范...',
              subtleFill: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRawEditor() {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '粘贴或编辑标准 SKILL.md (含 YAML Frontmatter 与 Markdown Body)：',
          style: TextStyle(fontSize: 12, color: colors.textSecondary),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _rawMdController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: _fieldDecoration(
              hint:
                  '---\nname: my-skill\ndescription: Skill description...\n---\n\nSkill prompt content...',
              subtleFill: true,
            ),
          ),
        ),
      ],
    );
  }

  InputDecoration _fieldDecoration({
    required String hint,
    bool filled = false,
    bool subtleFill = false,
  }) {
    final colors = context.colors;
    final fill = subtleFill
        ? colors.mutedBackground.withValues(alpha: 0.3)
        : (filled ? colors.mutedBackground : colors.cardBackground);
    return InputDecoration(
      hintText: hint,
      isDense: true,
      filled: true,
      fillColor: fill,
      hoverColor: fill,
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

  void _save() {
    if (_viewMode == _SkillEditorViewMode.raw) {
      _syncFromRaw();
    }
    final id = _idController.text.trim();
    final name = _nameController.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Skill 标识 (ID) 不能为空')));
      return;
    }

    final skill = Skill(
      id: id,
      name: name.isNotEmpty ? name : id,
      description: _descController.text.trim(),
      systemPrompt: _promptController.text.trim(),
      disableModelInvocation: _disableInvocation,
      isBuiltin: widget.skill?.isBuiltin ?? false,
    );

    Navigator.of(context).pop(skill);
  }
}
