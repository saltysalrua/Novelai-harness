import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../core/theme/app_theme.dart';

/// Skill 查看 / 编辑 / 导入对话框 (支持 Pi 标准 SKILL.md 导入导出)
class SkillEditorDialog extends StatefulWidget {
  final Skill? skill;
  final bool isImportMode;

  const SkillEditorDialog({
    super.key,
    this.skill,
    this.isImportMode = false,
  });

  @override
  State<SkillEditorDialog> createState() => _SkillEditorDialogState();
}

class _SkillEditorDialogState extends State<SkillEditorDialog> {
  late final TextEditingController _idController;
  late final TextEditingController _nameController;
  late final TextEditingController _descController;
  late final TextEditingController _promptController;
  late final TextEditingController _rawMdController;

  bool _disableInvocation = false;
  bool _isRawMode = false;

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
    _isRawMode = widget.isImportMode;
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
    final isBuiltin = widget.skill?.isBuiltin ?? false;

    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Container(
        width: 680,
        height: 640,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Icon(
                  widget.isImportMode
                      ? Icons.file_upload_outlined
                      : Icons.psychology_outlined,
                  size: 20,
                  color: AppTheme.notionBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  widget.isImportMode
                      ? '导入标准 SKILL.md'
                      : (widget.skill == null
                          ? '新建 Skill'
                          : '编辑 Skill (${widget.skill!.name})'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
                // 视图切换模式
                Container(
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      _ModeTab(
                        label: '结构化编辑',
                        isActive: !_isRawMode,
                        onTap: () {
                          if (_isRawMode) _syncFromRaw();
                          setState(() => _isRawMode = false);
                        },
                      ),
                      _ModeTab(
                        label: 'SKILL.md 源码',
                        isActive: _isRawMode,
                        onTap: () {
                          if (!_isRawMode) _syncToRaw();
                          setState(() => _isRawMode = true);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.close, size: 18, color: AppTheme.stone),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: '关闭',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 16),

            // 正文区
            Expanded(
              child: _isRawMode ? _buildRawEditor() : _buildStructuredEditor(isBuiltin),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 16),

            // 底部操作栏
            Row(
              children: [
                // 复制到剪贴板
                OutlinedButton.icon(
                  icon: const Icon(Icons.copy_rounded, size: 14),
                  label: const Text('复制 SKILL.md'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.textPrimary,
                    side: const BorderSide(color: AppTheme.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  onPressed: () {
                    _syncToRaw();
                    Clipboard.setData(
                      ClipboardData(text: _rawMdController.text),
                    );
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
                  child: const Text('取消', style: TextStyle(color: AppTheme.stone)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.notionBlue,
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
        ),
      ),
    );
  }

  Widget _buildStructuredEditor(bool isBuiltin) {
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
                    const Text(
                      '标识',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
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
                      decoration: InputDecoration(
                        hintText: '如 v5-architect',
                        isDense: true,
                        filled: true,
                        fillColor: isBuiltin
                            ? AppTheme.surfaceVariant
                            : AppTheme.pureWhite,
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
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '名称',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _nameController,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: '如 V5 自然语言架构师',
                        isDense: true,
                        filled: true,
                        fillColor: AppTheme.pureWhite,
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
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            '技能描述',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: _descController,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(fontSize: 12, height: 1.4),
            decoration: InputDecoration(
              hintText: '简要说明该技能擅长处理的任务场景...',
              isDense: true,
              filled: true,
              fillColor: AppTheme.pureWhite,
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
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                '技能指令',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
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
                    const Text(
                      '禁止自动调用',
                      style: TextStyle(fontSize: 11.5, color: AppTheme.stone),
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
            decoration: InputDecoration(
              hintText: '输入该技能加载后生效的完整提示词与规范...',
              isDense: true,
              filled: true,
              fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.3),
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
    );
  }

  Widget _buildRawEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '粘贴或编辑标准 SKILL.md (含 YAML Frontmatter 与 Markdown Body)：',
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: TextField(
            controller: _rawMdController,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            style: const TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              height: 1.4,
            ),
            decoration: InputDecoration(
              hintText: '---\nname: my-skill\ndescription: Skill description...\n---\n\nSkill prompt content...',
              filled: true,
              fillColor: AppTheme.surfaceVariant.withValues(alpha: 0.3),
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
        ),
      ],
    );
  }

  void _save() {
    if (_isRawMode) {
      _syncFromRaw();
    }
    final id = _idController.text.trim();
    final name = _nameController.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Skill 标识 (ID) 不能为空')),
      );
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

class _ModeTab extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _ModeTab({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.pureWhite : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
          boxShadow: isActive
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 2,
                  ),
                ]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
            color: isActive ? AppTheme.notionBlue : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
