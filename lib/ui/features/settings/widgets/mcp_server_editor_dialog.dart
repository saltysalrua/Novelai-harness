import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../core/harness/mcp/mcp_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import 'settings_shared.dart';

/// MCP 服务新建 / 编辑弹窗
class McpServerEditorDialog extends StatefulWidget {
  final McpServerConfig? server;

  const McpServerEditorDialog({super.key, this.server});

  @override
  State<McpServerEditorDialog> createState() => _McpServerEditorDialogState();
}

class _McpServerEditorDialogState extends State<McpServerEditorDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _idController;
  late final TextEditingController _urlController;
  late final TextEditingController _headersController;
  late final TextEditingController _commandController;
  late final TextEditingController _argsController;
  late final TextEditingController _envController;
  late final TextEditingController _timeoutController;
  late final SmoothWheelScrollController _scrollController;
  late McpTransportType _transport;

  bool get _isDesktop =>
      !kIsWeb &&
      switch (defaultTargetPlatform) {
        TargetPlatform.windows ||
        TargetPlatform.macOS ||
        TargetPlatform.linux => true,
        _ => false,
      };

  @override
  void initState() {
    super.initState();
    final s = widget.server;
    _transport = s?.transport ?? McpTransportType.http;
    _nameController = TextEditingController(text: s?.name ?? '');
    _idController = TextEditingController(text: s?.id ?? '');
    _urlController = TextEditingController(text: s?.url ?? '');
    _headersController = TextEditingController(
      text: s == null
          ? ''
          : s.headers.entries.map((e) => '${e.key}: ${e.value}').join('\n'),
    );
    _commandController = TextEditingController(text: s?.command ?? '');
    _argsController = TextEditingController(text: s?.args.join('\n') ?? '');
    _envController = TextEditingController(
      text: s == null
          ? ''
          : s.env.entries.map((e) => '${e.key}=${e.value}').join('\n'),
    );
    _timeoutController = TextEditingController(
      text: '${s?.timeoutSeconds ?? 30}',
    );
    _scrollController = SmoothWheelScrollController();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _idController.dispose();
    _urlController.dispose();
    _headersController.dispose();
    _commandController.dispose();
    _argsController.dispose();
    _envController.dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  Map<String, String> _parseKeyValueLines(String raw, String sep) {
    final map = <String, String>{};
    for (final line in raw.replaceAll('\r\n', '\n').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      final idx = trimmed.indexOf(sep);
      if (idx <= 0) continue;
      final key = trimmed.substring(0, idx).trim();
      final value = trimmed.substring(idx + sep.length).trim();
      if (key.isNotEmpty) map[key] = value;
    }
    return map;
  }

  List<String> _parseLines(String raw) => raw
      .replaceAll('\r\n', '\n')
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  void _save() {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    final url = _urlController.text.trim();
    final command = _commandController.text.trim();
    final validEndpoint = _transport == McpTransportType.http
        ? url.isNotEmpty
        : command.isNotEmpty;
    if (name.isEmpty || !validEndpoint) {
      showAppToast(
        context,
        message: l10n.mcpValidationError,
        tone: AppToastTone.error,
      );
      return;
    }
    final rawId = _idController.text.trim();
    final resolvedId = rawId.isNotEmpty
        ? McpServerConfig.sanitizeServerId(rawId)
        : (widget.server?.id ?? McpServerConfig.sanitizeServerId(name));
    final timeout = (int.tryParse(_timeoutController.text.trim()) ?? 30).clamp(
      5,
      300,
    );

    final config = McpServerConfig(
      id: resolvedId,
      name: name,
      transport: _transport,
      enabled: widget.server?.enabled ?? true,
      url: _transport == McpTransportType.http ? url : '',
      headers: _transport == McpTransportType.http
          ? _parseKeyValueLines(_headersController.text, ':')
          : const {},
      command: _transport == McpTransportType.stdio ? command : '',
      args: _transport == McpTransportType.stdio
          ? _parseLines(_argsController.text)
          : const [],
      env: _transport == McpTransportType.stdio
          ? _parseKeyValueLines(_envController.text, '=')
          : const {},
      timeoutSeconds: timeout,
    );
    Navigator.of(context).pop(config);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return AppDialogScaffold(
      minimalChrome: true,
      title: widget.server == null
          ? l10n.mcpDialogNewTitle
          : l10n.mcpDialogEditTitle(widget.server!.name),
      subtitle: widget.server?.id,
      width: 580,
      height: 580,
      body: SingleChildScrollView(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsFieldLabel(label: l10n.mcpFieldTransport),
            const SizedBox(height: 6),
            AppSegmentedCardBar<McpTransportType>(
              items: [
                AppSegmentedItem(
                  value: McpTransportType.http,
                  label: l10n.mcpTransportHttp,
                ),
                AppSegmentedItem(
                  value: McpTransportType.stdio,
                  label: l10n.mcpTransportStdio,
                ),
              ],
              selectedValue: _transport,
              onValueChanged: (v) => setState(() => _transport = v),
            ),
            if (_transport == McpTransportType.stdio && !_isDesktop) ...[
              const SizedBox(height: 8),
              SettingsSoftContainer(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Text(
                  l10n.mcpStdioDesktopOnly,
                  style: TextStyle(fontSize: 11.5, color: colors.warning),
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SettingsFieldLabel(label: l10n.mcpFieldName),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _nameController,
                        style: const TextStyle(fontSize: 12),
                        decoration: settingsSoftInputDecoration(
                          context,
                          hintText: l10n.mcpFieldNameHint,
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
                      SettingsFieldLabel(label: l10n.mcpFieldId),
                      const SizedBox(height: 6),
                      TextField(
                        controller: _idController,
                        style: const TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                        decoration: settingsSoftInputDecoration(
                          context,
                          hintText: l10n.mcpFieldIdHint,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_transport == McpTransportType.http) ...[
              SettingsFieldLabel(label: l10n.mcpFieldUrl),
              const SizedBox(height: 6),
              TextField(
                controller: _urlController,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: settingsSoftInputDecoration(
                  context,
                  hintText: l10n.mcpFieldUrlHint,
                ),
              ),
              const SizedBox(height: 12),
              SettingsFieldLabel(label: l10n.mcpFieldHeaders),
              const SizedBox(height: 6),
              TextField(
                controller: _headersController,
                minLines: 3,
                maxLines: 5,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
                decoration: settingsSoftInputDecoration(
                  context,
                  hintText: l10n.mcpFieldHeadersHint,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ] else ...[
              SettingsFieldLabel(label: l10n.mcpFieldCommand),
              const SizedBox(height: 6),
              TextField(
                controller: _commandController,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                decoration: settingsSoftInputDecoration(
                  context,
                  hintText: l10n.mcpFieldCommandHint,
                ),
              ),
              const SizedBox(height: 12),
              SettingsFieldLabel(label: l10n.mcpFieldArgs),
              const SizedBox(height: 6),
              TextField(
                controller: _argsController,
                minLines: 3,
                maxLines: 6,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
                decoration: settingsSoftInputDecoration(
                  context,
                  hintText: l10n.mcpFieldArgsHint,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
              const SizedBox(height: 12),
              SettingsFieldLabel(label: l10n.mcpFieldEnv),
              const SizedBox(height: 6),
              TextField(
                controller: _envController,
                minLines: 2,
                maxLines: 4,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.45,
                ),
                decoration: settingsSoftInputDecoration(
                  context,
                  hintText: l10n.mcpFieldEnvHint,
                  contentPadding: const EdgeInsets.all(10),
                ),
              ),
            ],
            const SizedBox(height: 12),
            SizedBox(
              width: 140,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsFieldLabel(label: l10n.mcpFieldTimeout),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _timeoutController,
                    keyboardType: TextInputType.number,
                    style: const TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                    ),
                    decoration: settingsSoftInputDecoration(
                      context,
                      hintText: '30',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: l10n.save,
          variant: AppActionButtonVariant.primary,
          onPressed: _save,
        ),
      ],
    );
  }
}

/// 粘贴标准 mcpServers JSON 一键导入弹窗
class McpJsonImportDialog extends StatefulWidget {
  const McpJsonImportDialog({super.key});

  @override
  State<McpJsonImportDialog> createState() => _McpJsonImportDialogState();
}

class _McpJsonImportDialogState extends State<McpJsonImportDialog> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _import() {
    try {
      final parsed = McpServerConfig.parseMcpServersJson(_controller.text);
      Navigator.of(context).pop(parsed);
    } catch (error) {
      showAppToast(
        context,
        message: error is FormatException ? error.message : error.toString(),
        tone: AppToastTone.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return AppDialogScaffold(
      minimalChrome: true,
      title: l10n.mcpImportJsonTitle,
      width: 600,
      height: 460,
      body: Padding(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mcpImportJsonHelp,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: TextField(
                controller: _controller,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: 'monospace',
                  height: 1.48,
                ),
                decoration: settingsSoftInputDecoration(
                  context,
                  hintText:
                      '{\n  "mcpServers": {\n    "context7": {\n      "url": "https://mcp.context7.com/mcp"\n    },\n    "filesystem": {\n      "command": "npx",\n      "args": ["-y", "@modelcontextprotocol/server-filesystem", "D:/Workspace"]\n    }\n  }\n}',
                  contentPadding: const EdgeInsets.all(12),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: l10n.mcpImportJson,
          variant: AppActionButtonVariant.primary,
          onPressed: _import,
        ),
      ],
    );
  }
}
