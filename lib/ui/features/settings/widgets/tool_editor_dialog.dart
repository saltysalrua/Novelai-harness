import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../core/theme/app_theme.dart';

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
    final schemaJson = t != null ? encoder.convert(t.parameters) : '''{
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
    _templateController =
        TextEditingController(text: custom?.outputTemplate ?? '');
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
    final isReadOnly = widget.isReadOnlySchemaView ||
        (widget.tool != null && widget.tool!.isBuiltin);

    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Container(
        width: 640,
        height: 600,
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 头部
            Row(
              children: [
                Icon(
                  isReadOnly ? Icons.code_rounded : Icons.build_circle_outlined,
                  size: 20,
                  color: AppTheme.notionBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  isReadOnly
                      ? '工具 Schema (${widget.tool?.label ?? widget.tool?.name})'
                      : (widget.tool == null
                          ? '新建自定义工具'
                          : '编辑自定义工具 (${widget.tool!.label})'),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const Spacer(),
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

            // 正文表单
            Expanded(
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
                                controller: _nameController,
                                enabled: !isReadOnly,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontFamily: 'monospace',
                                ),
                                decoration: InputDecoration(
                                  hintText: '如 custom_tool',
                                  isDense: true,
                                  filled: true,
                                  fillColor: isReadOnly
                                      ? AppTheme.surfaceVariant
                                      : AppTheme.pureWhite,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        const BorderSide(color: AppTheme.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        const BorderSide(color: AppTheme.border),
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
                                controller: _labelController,
                                enabled: !isReadOnly,
                                style: const TextStyle(fontSize: 12),
                                decoration: InputDecoration(
                                  hintText: '如 自定义工具',
                                  isDense: true,
                                  filled: true,
                                  fillColor: isReadOnly
                                      ? AppTheme.surfaceVariant
                                      : AppTheme.pureWhite,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        const BorderSide(color: AppTheme.border),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(6),
                                    borderSide:
                                        const BorderSide(color: AppTheme.border),
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
                      '工具描述',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    TextField(
                      controller: _descController,
                      enabled: !isReadOnly,
                      minLines: 2,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 12, height: 1.4),
                      decoration: InputDecoration(
                        hintText: '清楚描述该工具的作用与使用时机...',
                        isDense: true,
                        filled: true,
                        fillColor: isReadOnly
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
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        const Text(
                          '参数 Schema',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
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
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.copy_rounded,
                                    size: 13, color: AppTheme.notionBlue),
                                SizedBox(width: 4),
                                Text(
                                  '复制 Schema',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.notionBlue,
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
                        fontSize: 11.5,
                        fontFamily: 'monospace',
                        height: 1.4,
                      ),
                      decoration: InputDecoration(
                        filled: true,
                        fillColor:
                            AppTheme.surfaceVariant.withValues(alpha: 0.3),
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
                    if (!isReadOnly) ...[
                      const SizedBox(height: 12),
                      const Text(
                        '输出模板',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _templateController,
                        maxLines: 3,
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontFamily: 'monospace',
                        ),
                        decoration: InputDecoration(
                          hintText: '如：已成功执行并构建结果：{{query}}',
                          filled: true,
                          fillColor: AppTheme.pureWhite,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppTheme.border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(6),
                            borderSide:
                                const BorderSide(color: AppTheme.border),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),
            const Divider(height: 1, color: AppTheme.border),
            const SizedBox(height: 16),

            // 底部操作栏
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(
                    isReadOnly ? '关闭' : '取消',
                    style: const TextStyle(color: AppTheme.stone),
                  ),
                ),
                if (!isReadOnly) ...[
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
                    onPressed: _saveCustomTool,
                    child: const Text('保存工具'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _saveCustomTool() {
    final name = _nameController.text.trim();
    final label = _labelController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('工具名称 (Name) 不能为空')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Schema JSON 解析失败: $e')),
      );
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
