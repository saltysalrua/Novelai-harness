import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../tools/agent_tool.dart';
import '../tools/vision_image_codec.dart';
import '../types.dart';
import 'mcp_client.dart';
import 'mcp_models.dart';

/// 将单个 MCP 工具适配为 [AgentTool]，默认通过 CodeMode 精简工具表面调度。
class McpAgentTool extends AgentTool {
  final McpToolDescriptor descriptor;
  final Future<McpCallResult> Function(Map<String, dynamic> args) invoke;
  final bool Function()? isModelMultimodal;

  McpAgentTool({
    required this.descriptor,
    required this.invoke,
    this.isModelMultimodal,
  }) : super(
         name: descriptor.exposedName,
         label: '[MCP:${descriptor.serverName}] ${descriptor.originalName}',
         description: descriptor.description.isNotEmpty
             ? '[MCP · ${descriptor.serverName}] ${descriptor.description}'
             : '[MCP · ${descriptor.serverName}] 调用 ${descriptor.originalName}',
         parameters: descriptor.inputSchema,
         isBuiltin: false,
         // 强制收纳到 CodeMode 二级索引，通过 describe_tools + run_pipeline 按需调度
         preferCompactSurface: true,
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    try {
      final result = await invoke(args);
      String? imageBase64;
      String imageMimeType = 'image/png';
      if (result.imageBase64 != null &&
          result.imageBase64!.isNotEmpty &&
          isModelMultimodal?.call() == true) {
        try {
          final rawBytes = base64Decode(result.imageBase64!);
          final compressed = await compressVisionImage(rawBytes);
          imageBase64 = base64Encode(compressed.bytes);
          imageMimeType = compressed.mimeType;
        } catch (_) {
          // 图片解码失败时保留纯文本，不阻断工具返回
        }
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: result.text,
        isError: result.isError,
        imageBase64: imageBase64,
        imageMimeType: imageMimeType,
      );
    } catch (error) {
      return ToolResult(
        toolCallId: toolCallId,
        content: 'MCP 工具 ${descriptor.exposedName} 执行失败：$error',
        isError: true,
      );
    }
  }
}

/// 统一管理多个 MCP Server 的连接、工具发现与调用生命周期。
class McpManager {
  final http.Client? _sharedHttpClient;
  final McpClient Function(McpServerConfig config)? clientFactory;
  final void Function()? onStateChanged;

  final Map<String, McpServerConfig> _configs = {};
  final Map<String, McpClient> _clients = {};
  final Map<String, McpServerRuntimeState> _states = {};
  bool _disposed = false;

  McpManager({
    http.Client? httpClient,
    this.clientFactory,
    this.onStateChanged,
  }) : _sharedHttpClient = httpClient;

  Map<String, McpServerRuntimeState> get states => Map.unmodifiable(_states);

  McpServerRuntimeState stateOf(String serverId) =>
      _states[serverId] ?? McpServerRuntimeState(serverId: serverId);

  List<McpToolDescriptor> get discoveredTools {
    final all = <McpToolDescriptor>[];
    for (final cfg in _configs.values) {
      if (!cfg.enabled) continue;
      final state = _states[cfg.id];
      if (state != null && state.status == McpConnectionStatus.connected) {
        all.addAll(state.tools);
      }
    }
    return List.unmodifiable(all);
  }

  /// 同步最新配置列表：断开已删除或配置变更的服务，并为新增/启用的服务保留或触发连接。
  Future<void> syncConfigs(
    List<McpServerConfig> configs, {
    bool autoConnectEnabled = true,
  }) async {
    if (_disposed) return;
    final nextById = {for (final c in configs) c.id: c};

    // 1. 清理已移除的服务
    final removedIds = _configs.keys
        .where((id) => !nextById.containsKey(id))
        .toList();
    for (final id in removedIds) {
      await _disconnectInternal(id, removeState: true);
      _configs.remove(id);
    }

    // 2. 处理新增或变更的服务
    final toConnect = <McpServerConfig>[];
    for (final cfg in configs) {
      final prev = _configs[cfg.id];
      _configs[cfg.id] = cfg;
      _states.putIfAbsent(
        cfg.id,
        () => McpServerRuntimeState(serverId: cfg.id),
      );
      if (!cfg.enabled) {
        await _disconnectInternal(cfg.id);
        continue;
      }
      final changed = prev == null || !_sameConnectionSpec(prev, cfg);
      if (changed) {
        await _disconnectInternal(cfg.id);
        if (autoConnectEnabled) {
          toConnect.add(cfg);
        }
      } else if (autoConnectEnabled &&
          _states[cfg.id]?.status == McpConnectionStatus.disconnected) {
        toConnect.add(cfg);
      }
    }
    _notify();

    if (toConnect.isNotEmpty) {
      await Future.wait(toConnect.map((c) => connectServer(c.id)));
    }
  }

  static bool _sameConnectionSpec(McpServerConfig a, McpServerConfig b) {
    if (a.transport != b.transport ||
        a.url != b.url ||
        a.command != b.command ||
        a.timeoutSeconds != b.timeoutSeconds) {
      return false;
    }
    if (a.args.length != b.args.length) return false;
    for (var i = 0; i < a.args.length; i++) {
      if (a.args[i] != b.args[i]) return false;
    }
    if (a.headers.length != b.headers.length || a.env.length != b.env.length) {
      return false;
    }
    for (final e in a.headers.entries) {
      if (b.headers[e.key] != e.value) return false;
    }
    for (final e in a.env.entries) {
      if (b.env[e.key] != e.value) return false;
    }
    return true;
  }

  /// 连接（或重连）指定 MCP 服务并刷新工具清单
  Future<McpServerRuntimeState> connectServer(String serverId) async {
    final cfg = _configs[serverId];
    if (cfg == null) {
      return McpServerRuntimeState(
        serverId: serverId,
        status: McpConnectionStatus.error,
        errorMessage: '未找到 MCP 服务配置。',
      );
    }
    await _disconnectInternal(serverId);
    _states[serverId] = McpServerRuntimeState(
      serverId: serverId,
      status: McpConnectionStatus.connecting,
    );
    _notify();

    final client = _createClient(cfg);
    _clients[serverId] = client;
    try {
      await client.connect();
      final tools = await client.listTools();
      if (_disposed || _clients[serverId] != client) {
        await client.close();
        return stateOf(serverId);
      }
      final next = McpServerRuntimeState(
        serverId: serverId,
        status: McpConnectionStatus.connected,
        tools: List.unmodifiable(tools),
        lastSyncedAt: DateTime.now(),
      );
      _states[serverId] = next;
      _notify();
      return next;
    } catch (error) {
      if (_clients[serverId] == client) {
        _clients.remove(serverId);
      }
      try {
        await client.close();
      } catch (_) {}
      final next = McpServerRuntimeState(
        serverId: serverId,
        status: McpConnectionStatus.error,
        errorMessage: error.toString(),
      );
      _states[serverId] = next;
      _notify();
      return next;
    }
  }

  /// 重连所有已启用的 MCP 服务
  Future<void> reconnectAllEnabled() async {
    final enabledIds = _configs.values
        .where((c) => c.enabled)
        .map((c) => c.id)
        .toList();
    await Future.wait(enabledIds.map(connectServer));
  }

  /// 构造当前所有已连接 MCP 工具的 [McpAgentTool] 列表（供 ToolRegistry 注册）
  List<McpAgentTool> buildAgentTools({bool Function()? isModelMultimodal}) {
    final tools = <McpAgentTool>[];
    for (final desc in discoveredTools) {
      tools.add(
        McpAgentTool(
          descriptor: desc,
          isModelMultimodal: isModelMultimodal,
          invoke: (args) => callTool(desc.serverId, desc.originalName, args),
        ),
      );
    }
    return tools;
  }

  Future<McpCallResult> callTool(
    String serverId,
    String originalToolName,
    Map<String, dynamic> args,
  ) async {
    var client = _clients[serverId];
    if (client == null) {
      final state = await connectServer(serverId);
      if (state.status != McpConnectionStatus.connected) {
        throw StateError(state.errorMessage ?? 'MCP 服务未连接。');
      }
      client = _clients[serverId];
    }
    if (client == null) {
      throw StateError('MCP 服务未连接。');
    }
    return client.callTool(originalToolName, args);
  }

  McpClient _createClient(McpServerConfig config) {
    if (clientFactory != null) return clientFactory!(config);
    return switch (config.transport) {
      McpTransportType.http => HttpMcpClient(
        config: config,
        client: _sharedHttpClient,
      ),
      McpTransportType.stdio => StdioMcpClient(config: config),
    };
  }

  Future<void> _disconnectInternal(
    String serverId, {
    bool removeState = false,
  }) async {
    final old = _clients.remove(serverId);
    if (old != null) {
      try {
        await old.close();
      } catch (_) {}
    }
    if (removeState) {
      _states.remove(serverId);
    } else if (_states.containsKey(serverId)) {
      _states[serverId] = McpServerRuntimeState(
        serverId: serverId,
        status: McpConnectionStatus.disconnected,
      );
    }
  }

  void _notify() {
    if (!_disposed) {
      onStateChanged?.call();
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    final ids = _clients.keys.toList();
    for (final id in ids) {
      await _disconnectInternal(id, removeState: true);
    }
    _configs.clear();
    _states.clear();
  }
}
