import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/context_l10n.dart';

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
  bool _copiedSchema = false;
  int _errorShakeTrigger = 0;
  Timer? _copyResetTimer;

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
    _copyResetTimer?.cancel();
    _nameController.dispose();
    _labelController.dispose();
    _descController.dispose();
    _schemaController.dispose();
    _templateController.dispose();
    super.dispose();
  }

  void _copySchema() {
    Clipboard.setData(ClipboardData(text: _schemaController.text));
    _copyResetTimer?.cancel();
    setState(() => _copiedSchema = true);
    _copyResetTimer = Timer(const Duration(milliseconds: 1600), () {
      if (mounted) setState(() => _copiedSchema = false);
    });
    showAppToast(
      context,
      message: context.l10n.toolCopySchemaSuccess,
      tone: AppToastTone.success,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isReadOnly =
        widget.isReadOnlySchemaView ||
        (widget.tool != null && widget.tool!.isBuiltin);

    return AppDialogScaffold(
      title: isReadOnly
          ? l10n.toolDialogSchemaTitle(
              widget.tool?.label ?? widget.tool?.name ?? '',
            )
          : (widget.tool == null
                ? l10n.toolDialogNewTitle
                : l10n.toolDialogEditTitle(widget.tool!.label)),
      width: 640,
      height: 600,
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: AppErrorShake(
          trigger: _errorShakeTrigger,
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
                          l10n.toolFieldId,
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
                            hint: l10n.toolFieldIdHint,
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
                          l10n.toolFieldName,
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
                            hint: l10n.toolFieldNameHint,
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
                l10n.toolFieldDescription,
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
                  hint: l10n.toolFieldDescriptionHint,
                  filled: isReadOnly,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Text(
                    l10n.toolFieldSchema,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    onTap: _copySchema,
                    borderRadius: BorderRadius.circular(4),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      child: Row(
                        children: [
                          AppIconSwap(
                            swapKey: _copiedSchema,
                            enableBlur: false,
                            child: _copiedSchema
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
                            l10n.toolCopySchema,
                            style: TextStyle(
                              fontSize: 11,
                              color: _copiedSchema
                                  ? colors.success
                                  : colors.primary,
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
                  l10n.toolFieldOutputTemplate,
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
                  decoration: _fieldDecoration(
                    hint: l10n.toolFieldOutputTemplateHint('{{query}}'),
                  ),
                ),
              ],
            ],
          ),
        ),
        ),
      ),
      actions: [
        AppActionButton(
          label: isReadOnly ? l10n.close : l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        if (!isReadOnly) ...[
          const SizedBox(width: 8),
          AppActionButton(
            label: l10n.toolSave,
            variant: AppActionButtonVariant.primary,
            onPressed: _saveCustomTool,
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
      setState(() => _errorShakeTrigger++);
      showAppToast(
        context,
        message: context.l10n.toolNameEmptyError,
        tone: AppToastTone.error,
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
      setState(() => _errorShakeTrigger++);
      showAppToast(
        context,
        message: context.l10n.toolSchemaParseError('$e'),
        tone: AppToastTone.error,
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
