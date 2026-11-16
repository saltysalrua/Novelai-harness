import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import 'settings_shared.dart';

/// Tool 查看 Schema / 编辑 / 新建自定义工具对话框 (Pi 风格工具构建器)
///
/// 采用 Notion 极简一体无分割线布局：
/// 只读 Schema 模式直接渲染轻底可划选文档块 (零禁用态灰框)；
/// 编辑模式提供柔底无框表单与一键 JSON 格式化。
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
  late final SmoothWheelScrollController _scrollController;
  bool _copiedSchema = false;
  int _errorShakeTrigger = 0;
  Timer? _copyResetTimer;

  @override
  void initState() {
    super.initState();
    final t = widget.tool;
    _scrollController = SmoothWheelScrollController();
    _nameController = TextEditingController(text: t?.name ?? '');
    _labelController = TextEditingController(text: t?.label ?? '');
    _descController = TextEditingController(text: t?.description ?? '');

    const encoder = JsonEncoder.withIndent('  ');
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
    _scrollController.dispose();
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

  void _formatSchemaJson() {
    try {
      final decoded = jsonDecode(_schemaController.text.trim());
      const encoder = JsonEncoder.withIndent('  ');
      setState(() {
        _schemaController.text = encoder.convert(decoded);
      });
    } catch (_) {
      setState(() => _errorShakeTrigger++);
      showAppToast(
        context,
        message: context.l10n.toolFormatSchemaInvalid,
        tone: AppToastTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isReadOnly =
        widget.isReadOnlySchemaView ||
        (widget.tool != null && widget.tool!.isBuiltin);

    return AppDialogScaffold(
      minimalChrome: true,
      title: isReadOnly
          ? l10n.toolDialogSchemaTitle(
              widget.tool?.label ?? widget.tool?.name ?? '',
            )
          : (widget.tool == null
                ? l10n.toolDialogNewTitle
                : l10n.toolDialogEditTitle(widget.tool!.label)),
      subtitle: widget.tool?.name,
      width: 640,
      maxHeight: 640,
      body: AppErrorShake(
        trigger: _errorShakeTrigger,
        child: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
          child: isReadOnly
              ? _buildReadOnlySchemaBody(context)
              : _buildEditableFormBody(context),
        ),
      ),
      actions: isReadOnly
          ? [
              AppActionButton(
                label: l10n.close,
                variant: AppActionButtonVariant.primary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ]
          : [
              AppActionButton(
                label: l10n.cancel,
                variant: AppActionButtonVariant.ghost,
                onPressed: () => Navigator.of(context).pop(),
              ),
              const SizedBox(width: 8),
              AppActionButton(
                label: l10n.toolSave,
                variant: AppActionButtonVariant.primary,
                onPressed: _saveCustomTool,
              ),
            ],
    );
  }

  Widget _buildReadOnlySchemaBody(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final tool = widget.tool;
    final desc = tool?.description.trim() ?? '';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (tool != null) ...[
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppBadge(
                label: tool.isBuiltin
                    ? l10n.settingsBadgeBuiltin
                    : l10n.settingsBadgeCustom,
                variant: tool.isBuiltin
                    ? AppBadgeVariant.neutral
                    : AppBadgeVariant.success,
                fontSize: 11,
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: SelectableText(
                  tool.name,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
        ],
        SettingsFieldLabel(label: l10n.toolFieldDescription),
        const SizedBox(height: 6),
        SettingsSoftContainer(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            desc.isNotEmpty ? desc : l10n.toolNoDescription,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: desc.isNotEmpty ? colors.textPrimary : colors.textMuted,
            ),
          ),
        ),
        const SizedBox(height: 14),
        SettingsFieldLabel(
          label: l10n.toolFieldSchema,
          trailing: _buildCopySchemaAction(context),
        ),
        const SizedBox(height: 6),
        SettingsSoftContainer(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            _schemaController.text,
            style: TextStyle(
              fontSize: 12,
              fontFamily: 'monospace',
              height: 1.45,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEditableFormBody(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsFieldLabel(label: l10n.toolFieldId),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _nameController,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: settingsSoftInputDecoration(
                      context,
                      hintText: l10n.toolFieldIdHint,
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
                  SettingsFieldLabel(label: l10n.toolFieldName),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _labelController,
                    style: const TextStyle(fontSize: 12),
                    decoration: settingsSoftInputDecoration(
                      context,
                      hintText: l10n.toolFieldNameHint,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        SettingsFieldLabel(label: l10n.toolFieldDescription),
        const SizedBox(height: 6),
        TextField(
          controller: _descController,
          minLines: 2,
          maxLines: 4,
          style: const TextStyle(fontSize: 12, height: 1.4),
          decoration: settingsSoftInputDecoration(
            context,
            hintText: l10n.toolFieldDescriptionHint,
          ),
        ),
        const SizedBox(height: 12),
        SettingsFieldLabel(
          label: l10n.toolFieldSchema,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsInlineLink(
                label: l10n.toolFormatSchema,
                icon: Icons.auto_fix_high_rounded,
                onTap: _formatSchemaJson,
              ),
              const SizedBox(width: 8),
              _buildCopySchemaAction(context),
            ],
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _schemaController,
          maxLines: 8,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            height: 1.45,
          ),
          decoration: settingsSoftInputDecoration(
            context,
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
        const SizedBox(height: 12),
        SettingsFieldLabel(label: l10n.toolFieldOutputTemplate),
        const SizedBox(height: 6),
        TextField(
          controller: _templateController,
          maxLines: 3,
          style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
          decoration: settingsSoftInputDecoration(
            context,
            hintText: l10n.toolFieldOutputTemplateHint('{{query}}'),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),
      ],
    );
  }

  Widget _buildCopySchemaAction(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return InkWell(
      onTap: _copySchema,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
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
                fontSize: 11.5,
                color: _copiedSchema ? colors.success : colors.primary,
                fontWeight: FontWeight.w500,
              ),
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
