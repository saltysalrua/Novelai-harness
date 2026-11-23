import 'dart:convert';

/// MCP 传输协议类型
enum McpTransportType {
  /// Streamable HTTP / SSE（全平台可用，含移动端与桌面端）
  http,

  /// 本地子进程 Stdio（仅桌面端 Windows / macOS / Linux 可用）
  stdio,
}

McpTransportType parseMcpTransportType(String? raw) => switch (raw) {
  'stdio' => McpTransportType.stdio,
  _ => McpTransportType.http,
};

String mcpTransportTypeStorage(McpTransportType type) => switch (type) {
  McpTransportType.http => 'http',
  McpTransportType.stdio => 'stdio',
};

/// 单个 MCP Server 配置（持久化于 AppConfig）
class McpServerConfig {
  final String id;
  final String name;
  final McpTransportType transport;
  final bool enabled;

  /// Streamable HTTP 端点 URL（transport == http 时必填）
  final String url;

  /// 自定义 HTTP 请求头（如 Authorization: Bearer ...）
  final Map<String, String> headers;

  /// Stdio 可执行命令（transport == stdio 时必填）
  final String command;

  /// Stdio 命令行参数
  final List<String> args;

  /// Stdio 附加环境变量
  final Map<String, String> env;

  /// 单次请求超时（秒）
  final int timeoutSeconds;

  const McpServerConfig({
    required this.id,
    required this.name,
    required this.transport,
    this.enabled = true,
    this.url = '',
    this.headers = const {},
    this.command = '',
    this.args = const [],
    this.env = const {},
    this.timeoutSeconds = 30,
  });

  McpServerConfig copyWith({
    String? id,
    String? name,
    McpTransportType? transport,
    bool? enabled,
    String? url,
    Map<String, String>? headers,
    String? command,
    List<String>? args,
    Map<String, String>? env,
    int? timeoutSeconds,
  }) {
    return McpServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      transport: transport ?? this.transport,
      enabled: enabled ?? this.enabled,
      url: url ?? this.url,
      headers: headers ?? Map<String, String>.from(this.headers),
      command: command ?? this.command,
      args: args ?? List<String>.from(this.args),
      env: env ?? Map<String, String>.from(this.env),
      timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
    );
  }

  /// 生成适合作为工具名前缀的规范化短键（仅保留字母、数字与下划线）
  String get toolPrefixSlug {
    final raw = (id.trim().isNotEmpty ? id : name).toLowerCase();
    final slug = raw
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return slug.isEmpty ? 'server' : slug;
  }

  /// 配置摘要（用于卡片副标题展示）
  String get endpointSummary => switch (transport) {
    McpTransportType.http => url.trim(),
    McpTransportType.stdio =>
      [command.trim(), ...args].where((s) => s.isNotEmpty).join(' '),
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'transport': mcpTransportTypeStorage(transport),
    'enabled': enabled,
    if (url.isNotEmpty) 'url': url,
    if (headers.isNotEmpty) 'headers': headers,
    if (command.isNotEmpty) 'command': command,
    if (args.isNotEmpty) 'args': args,
    if (env.isNotEmpty) 'env': env,
    'timeoutSeconds': timeoutSeconds,
  };

  factory McpServerConfig.fromJson(Map<String, dynamic> json) {
    Map<String, String> parseStringMap(Object? raw) {
      if (raw is! Map) return const {};
      return {
        for (final entry in raw.entries)
          if (entry.key.toString().trim().isNotEmpty)
            entry.key.toString().trim(): entry.value?.toString() ?? '',
      };
    }

    final rawUrl = (json['url'] ?? json['serverUrl'] ?? '').toString().trim();
    final rawCommand = (json['command'] ?? '').toString().trim();
    final explicitTransport = json['transport']?.toString() ??
        json['type']?.toString();
    final transport = explicitTransport != null && explicitTransport.isNotEmpty
        ? parseMcpTransportType(explicitTransport)
        : (rawCommand.isNotEmpty && rawUrl.isEmpty
              ? McpTransportType.stdio
              : McpTransportType.http);
    final id = (json['id'] as String?)?.trim() ?? '';
    final name = (json['name'] as String?)?.trim() ?? '';
    final resolvedId = id.isNotEmpty
        ? id
        : (name.isNotEmpty
              ? sanitizeServerId(name)
              : 'mcp_${DateTime.now().millisecondsSinceEpoch}');
    return McpServerConfig(
      id: resolvedId,
      name: name.isNotEmpty ? name : resolvedId,
      transport: transport,
      enabled: json['enabled'] as bool? ?? true,
      url: rawUrl,
      headers: parseStringMap(json['headers']),
      command: rawCommand,
      args: (json['args'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
      env: parseStringMap(json['env']),
      timeoutSeconds: ((json['timeoutSeconds'] as num?)?.toInt() ?? 30)
          .clamp(5, 300),
    );
  }

  static String sanitizeServerId(String raw) {
    final cleaned = raw
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return cleaned.isEmpty ? 'mcp-server' : cleaned;
  }

  /// 解析标准 `mcpServers` JSON（兼容 Claude Desktop / Cursor / Antigravity 格式）
  /// 以及单对象或数组格式。
  static List<McpServerConfig> parseMcpServersJson(String rawJson) {
    final trimmed = rawJson.trim();
    if (trimmed.isEmpty) {
      throw const FormatException('JSON 内容为空。');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } on FormatException catch (e) {
      throw FormatException('JSON 格式错误：${e.message}');
    }

    final results = <McpServerConfig>[];
    if (decoded is List) {
      for (final item in decoded) {
        if (item is! Map) {
          throw const FormatException('mcpServers 数组中的每项必须是 JSON 对象。');
        }
        results.add(
          McpServerConfig.fromJson(Map<String, dynamic>.from(item)),
        );
      }
    } else if (decoded is Map) {
      final map = Map<String, dynamic>.from(decoded);
      final nested = map['mcpServers'];
      if (nested is Map) {
        for (final entry in nested.entries) {
          if (entry.value is! Map) continue;
          final item = Map<String, dynamic>.from(entry.value as Map);
          final key = entry.key.toString().trim();
          item.putIfAbsent('id', () => sanitizeServerId(key));
          item.putIfAbsent('name', () => key);
          results.add(McpServerConfig.fromJson(item));
        }
      } else if (map.containsKey('url') ||
          map.containsKey('serverUrl') ||
          map.containsKey('command')) {
        results.add(McpServerConfig.fromJson(map));
      } else {
        // 兼容直接粘贴 {"server-name": {"command": ...}} 的无外层包装写法
        for (final entry in map.entries) {
          if (entry.value is! Map) continue;
          final item = Map<String, dynamic>.from(entry.value as Map);
          if (!item.containsKey('url') &&
              !item.containsKey('serverUrl') &&
              !item.containsKey('command')) {
            continue;
          }
          final key = entry.key.toString().trim();
          item.putIfAbsent('id', () => sanitizeServerId(key));
          item.putIfAbsent('name', () => key);
          results.add(McpServerConfig.fromJson(item));
        }
      }
    } else {
      throw const FormatException('JSON 根节点必须是对象或数组。');
    }

    if (results.isEmpty) {
      throw const FormatException(
        '未识别到有效的 MCP 服务配置（需包含 url 或 command 字段）。',
      );
    }
    return results;
  }

  /// 导出为标准 `mcpServers` JSON 文本
  static String encodeMcpServersJson(List<McpServerConfig> servers) {
    final map = <String, dynamic>{};
    for (final s in servers) {
      map[s.id] = switch (s.transport) {
        McpTransportType.http => {
          'url': s.url,
          if (s.headers.isNotEmpty) 'headers': s.headers,
        },
        McpTransportType.stdio => {
          'command': s.command,
          if (s.args.isNotEmpty) 'args': s.args,
          if (s.env.isNotEmpty) 'env': s.env,
        },
      };
    }
    return const JsonEncoder.withIndent('  ').convert({'mcpServers': map});
  }
}

/// MCP 远程/本地工具描述符
class McpToolDescriptor {
  final String serverId;
  final String serverName;
  final String originalName;
  final String exposedName;
  final String description;
  final Map<String, dynamic> inputSchema;

  const McpToolDescriptor({
    required this.serverId,
    required this.serverName,
    required this.originalName,
    required this.exposedName,
    required this.description,
    required this.inputSchema,
  });

  static String buildExposedName(String serverSlug, String originalName) {
    final toolSlug = originalName
        .trim()
        .replaceAll(RegExp(r'[^a-zA-Z0-9_-]+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    final safeTool = toolSlug.isEmpty ? 'tool' : toolSlug;
    return 'mcp_${serverSlug}_$safeTool';
  }
}

/// MCP 服务运行时连接状态
enum McpConnectionStatus { disconnected, connecting, connected, error }

/// 单台 MCP 服务的运行时快照
class McpServerRuntimeState {
  final String serverId;
  final McpConnectionStatus status;
  final List<McpToolDescriptor> tools;
  final String? errorMessage;
  final DateTime? lastSyncedAt;

  const McpServerRuntimeState({
    required this.serverId,
    this.status = McpConnectionStatus.disconnected,
    this.tools = const [],
    this.errorMessage,
    this.lastSyncedAt,
  });

  McpServerRuntimeState copyWith({
    McpConnectionStatus? status,
    List<McpToolDescriptor>? tools,
    String? errorMessage,
    bool clearError = false,
    DateTime? lastSyncedAt,
  }) {
    return McpServerRuntimeState(
      serverId: serverId,
      status: status ?? this.status,
      tools: tools ?? this.tools,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}
