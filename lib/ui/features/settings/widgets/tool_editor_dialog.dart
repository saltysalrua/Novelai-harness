import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';

/// Tool 查看 Schema / 编辑 / 新建自定义工具对话框 (Pi 风格工具构建器)
class ToolEditorDialog extends StatefulWidget {
  final AgentTool? tool;
  final bool isReadOnlySchemaView;

  const ToolEditorDialog({
    super.key,
    this.tool,
    this.isReadOnlySchemaView = false,
  });

  @override
  State<ToolEditorDialog> createState() => _ToolEditorDialogState();
}

class _ToolEditorDialogState extends State<ToolEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _labelController;
  late final TextEditingController _descController;
  late final TextEditingController _schemaController;
  late final TextEditingController _templateController;

  @override
  void initState() {
    super.initState();
    final t = widget.tool;
    _nameController = TextEditingController(text: t?.name ?? '');
    _labelController = TextEditingController(text: t?.label ?? '');
    _descController = TextEditingController(text: t?.description ?? '');

    final encoder = const JsonEncoder.withIndent('  ');
    final schemaJson = t != null
        ? encoder.convert(t.parameters)
        : '''{
  "type": "object",
  "properties": {
    "query": {
      "type": "string",
      "description": "输入参数描述"
    }
  },
  "required": ["query"]
}''';
    _schemaController = TextEditingController(text: schemaJson);

    final custom = t is CustomAgentTool ? t : null;
    _templateController = TextEditingController(
      text: custom?.outputTemplate ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _labelController.dispose();
    _descController.dispose();
    _schemaController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isReadOnly =
        widget.isReadOnlySchemaView ||
        (widget.tool != null && widget.tool!.isBuiltin);

    return AppDialogScaffold(
      title: isReadOnly
          ? '工具 Schema (${widget.tool?.label ?? widget.tool?.name})'
          : (widget.tool == null
                ? '新建自定义工具'
                : '编辑自定义工具 (${widget.tool!.label})'),
      width: 640,
      height: 600,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: SingleChildScrollView(
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
                          controller: _nameController,
                          enabled: !isReadOnly,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                          ),
                          decoration: _fieldDecoration(
                            hint: '如 custom_tool',
                            filled: isReadOnly,
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
                          controller: _labelController,
                          enabled: !isReadOnly,
                          style: const TextStyle(fontSize: 12),
                          decoration: _fieldDecoration(
                            hint: '如 自定义工具',
                            filled: isReadOnly,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '工具描述',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _descController,
                enabled: !isReadOnly,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(fontSize: 12, height: 1.4),
                decoration: _fieldDecoration(
                  hint: '清楚描述该工具的作用与使用时机...',
                  filled: isReadOnly,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    '参数 Schema',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: () {
                      Clipboard.setData(
                        ClipboardData(text: _schemaController.text),
                      );
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('已复制 Schema JSON 至剪贴板'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.copy_rounded,
                            size: 13,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '复制 Schema',
                            style: TextStyle(
                              fontSize: 11,
                              color: colors.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _schemaController,
                enabled: !isReadOnly,
                maxLines: 8,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
                decoration: _fieldDecoration(hint: '', subtleFill: true),
              ),
              if (!isReadOnly) ...[
                const SizedBox(height: 12),
                Text(
                  '输出模板',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _templateController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                  decoration: _fieldDecoration(hint: '如：已成功执行并构建结果：{{query}}'),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            isReadOnly ? '关闭' : '取消',
            style: TextStyle(color: colors.textSecondary),
          ),
        ),
        if (!isReadOnly) ...[
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
            onPressed: _saveCustomTool,
            child: const Text('保存工具'),
          ),
        ],
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
      hintText: hint.isEmpty ? null : hint,
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

  void _saveCustomTool() {
    final name = _nameController.text.trim();
    final label = _labelController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('工具名称 (Name) 不能为空')));
      return;
    }

    Map<String, dynamic> parsedParams = const {
      'type': 'object',
      'properties': {},
    };
    try {
      final decoded = jsonDecode(_schemaController.text.trim());
      if (decoded is Map<String, dynamic>) {
        parsedParams = decoded;
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Schema JSON 解析失败: $e')));
      return;
    }

    final customTool = CustomAgentTool(
      name: name,
      label: label.isNotEmpty ? label : name,
      description: _descController.text.trim(),
      parameters: parsedParams,
      outputTemplate: _templateController.text.trim(),
    );

    Navigator.of(context).pop(customTool);
  }
}
