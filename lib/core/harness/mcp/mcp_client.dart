import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'mcp_models.dart';

/// MCP 工具调用返回结果
class McpCallResult {
  final String text;
  final bool isError;
  final String? imageBase64;
  final String? imageMimeType;

  const McpCallResult({
    required this.text,
    this.isError = false,
    this.imageBase64,
    this.imageMimeType,
  });
}

/// MCP 客户端协议抽象
abstract class McpClient {
  Future<void> connect();
  Future<List<McpToolDescriptor>> listTools();
  Future<McpCallResult> callTool(String name, Map<String, dynamic> arguments);
  Future<void> close();
}

/// 解析 MCP `tools/call` 标准的 `result` 对象（兼容 content 数组与纯文本回退）
McpCallResult parseMcpToolCallResult(Object? result) {
  if (result is! Map) {
    return McpCallResult(text: result?.toString() ?? '');
  }
  final map = Map<String, dynamic>.from(result);
  final isError = map['isError'] == true;
  final rawContent = map['content'];
  final textParts = <String>[];
  String? imageBase64;
  String? imageMimeType;

  if (rawContent is List) {
    for (final item in rawContent) {
      if (item is! Map) continue;
      final type = item['type']?.toString() ?? '';
      switch (type) {
        case 'text':
          final t = item['text']?.toString() ?? '';
          if (t.isNotEmpty) textParts.add(t);
        case 'image':
          final data = item['data']?.toString() ?? '';
          final mime = item['mimeType']?.toString() ?? 'image/png';
          if (data.isNotEmpty) {
            imageBase64 = data;
            imageMimeType = mime;
          }
        case 'resource':
          final resource = item['resource'];
          if (resource is Map) {
            final uri = resource['uri']?.toString() ?? '';
            final text = resource['text']?.toString() ?? '';
            if (text.isNotEmpty) {
              textParts.add(uri.isNotEmpty ? '[$uri]\n$text' : text);
            } else if (uri.isNotEmpty) {
              textParts.add('[resource: $uri]');
            }
          }
        default:
          textParts.add(jsonEncode(item));
      }
    }
  } else if (map['structuredContent'] != null) {
    textParts.add(jsonEncode(map['structuredContent']));
  }

  final text = textParts.isNotEmpty
      ? textParts.join('\n')
      : (imageBase64 != null ? '(已返回图片结果)' : jsonEncode(map));
  return McpCallResult(
    text: text,
    isError: isError,
    imageBase64: imageBase64,
    imageMimeType: imageMimeType,
  );
}

/// 解析 MCP `tools/list` 返回的工具数组
List<McpToolDescriptor> parseMcpToolList(
  McpServerConfig config,
  Object? result,
) {
  if (result is! Map) return const [];
  final rawTools = result['tools'];
  if (rawTools is! List) return const [];
  final slug = config.toolPrefixSlug;
  final seen = <String>{};
  final tools = <McpToolDescriptor>[];
  for (final item in rawTools) {
    if (item is! Map) continue;
    final map = Map<String, dynamic>.from(item);
    final originalName = (map['name'] as String?)?.trim() ?? '';
    if (originalName.isEmpty) continue;
    final description = (map['description'] as String?)?.trim() ?? '';
    final rawSchema = map['inputSchema'];
    final schema = rawSchema is Map
        ? Map<String, dynamic>.from(rawSchema)
        : const <String, dynamic>{'type': 'object', 'properties': {}};
    var exposed = McpToolDescriptor.buildExposedName(slug, originalName);
    var suffix = 2;
    while (!seen.add(exposed)) {
      exposed = '${McpToolDescriptor.buildExposedName(slug, originalName)}_$suffix';
      suffix++;
    }
    tools.add(
      McpToolDescriptor(
        serverId: config.id,
        serverName: config.name,
        originalName: originalName,
        exposedName: exposed,
        description: description,
        inputSchema: schema,
      ),
    );
  }
  return tools;
}

/// Streamable HTTP / SSE MCP 客户端（跨平台，支持自定义请求头与 Mcp-Session-Id）
class HttpMcpClient implements McpClient {
  static const String _protocolVersion = '2025-03-26';

  final McpServerConfig config;
  final http.Client _httpClient;
  final bool _ownsClient;
  int _nextId = 1;
  String? _sessionId;
  bool _initialized = false;

  HttpMcpClient({required this.config, http.Client? client})
    : _httpClient = client ?? http.Client(),
      _ownsClient = client == null;

  Uri get _endpoint {
    final uri = Uri.tryParse(config.url.trim());
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      throw FormatException('无效的 MCP HTTP 端点：${config.url}');
    }
    return uri;
  }

  Map<String, String> _buildHeaders() => {
    'Content-Type': 'application/json',
    'Accept': 'application/json, text/event-stream',
    ...config.headers,
    if (_sessionId != null && _sessionId!.isNotEmpty)
      'Mcp-Session-Id': _sessionId!,
  };

  @override
  Future<void> connect() async {
    await _sendRpc('initialize', {
      'protocolVersion': _protocolVersion,
      'capabilities': const <String, Object?>{},
      'clientInfo': const {
        'name': 'novelai-harness',
        'version': '1.0.0',
      },
    });
    _initialized = true;
    // 发送标准 initialized 通知（忽略 202/204 无响应体）
    try {
      await _sendNotification('notifications/initialized', const {});
    } catch (_) {}
  }

  @override
  Future<List<McpToolDescriptor>> listTools() async {
    if (!_initialized) await connect();
    final result = await _sendRpc('tools/list', const {});
    return parseMcpToolList(config, result);
  }

  @override
  Future<McpCallResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    if (!_initialized) await connect();
    final result = await _sendRpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return parseMcpToolCallResult(result);
  }

  Future<void> _sendNotification(
    String method,
    Map<String, dynamic> params,
  ) async {
    final body = jsonEncode({
      'jsonrpc': '2.0',
      'method': method,
      'params': params,
    });
    await _httpClient
        .post(_endpoint, headers: _buildHeaders(), body: body)
        .timeout(Duration(seconds: config.timeoutSeconds));
  }

  Future<Object?> _sendRpc(String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final payload = jsonEncode({
      'jsonrpc': '2.0',
      'id': id,
      'method': method,
      'params': params,
    });
    final response = await _httpClient
        .post(_endpoint, headers: _buildHeaders(), body: payload)
        .timeout(Duration(seconds: config.timeoutSeconds));

    final returnedSession = response.headers['mcp-session-id'];
    if (returnedSession != null && returnedSession.trim().isNotEmpty) {
      _sessionId = returnedSession.trim();
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = response.body.trim();
      throw StateError(
        'MCP HTTP 请求失败 (${response.statusCode})${detail.isNotEmpty ? ': ${_truncate(detail, 240)}' : ''}',
      );
    }

    final contentType = (response.headers['content-type'] ?? '').toLowerCase();
    final decoded = contentType.contains('text/event-stream')
        ? parseSseJsonRpcResponse(response.body, expectedId: id)
        : _decodeJsonObject(response.body);

    if (decoded == null) {
      throw const FormatException('MCP 服务端未返回有效的 JSON-RPC 响应。');
    }
    if (decoded['error'] case final Map err) {
      final code = err['code'];
      final message = err['message'] ?? '未知错误';
      throw StateError('MCP 错误 ($code): $message');
    }
    return decoded['result'];
  }

  /// 解析 SSE (`text/event-stream`) 中的 JSON-RPC 响应消息
  static Map<String, dynamic>? parseSseJsonRpcResponse(
    String rawBody, {
    int? expectedId,
  }) {
    Map<String, dynamic>? lastJson;
    final dataBuffer = StringBuffer();

    void flushEvent() {
      if (dataBuffer.isEmpty) return;
      final chunk = dataBuffer.toString().trim();
      dataBuffer.clear();
      if (chunk.isEmpty || chunk == '[DONE]') return;
      final obj = _decodeJsonObject(chunk);
      if (obj != null) {
        lastJson = obj;
      }
    }

    for (final rawLine in rawBody.replaceAll('\r\n', '\n').split('\n')) {
      if (rawLine.isEmpty) {
        flushEvent();
        if (expectedId != null && lastJson?['id'] == expectedId) {
          return lastJson;
        }
        continue;
      }
      if (rawLine.startsWith('data:')) {
        if (dataBuffer.isNotEmpty) dataBuffer.write('\n');
        dataBuffer.write(rawLine.substring(5).trimLeft());
      }
    }
    flushEvent();
    return lastJson;
  }

  static Map<String, dynamic>? _decodeJsonObject(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    final decoded = jsonDecode(trimmed);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  }

  static String _truncate(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  @override
  Future<void> close() async {
    _initialized = false;
    _sessionId = null;
    if (_ownsClient) {
      _httpClient.close();
    }
  }
}

/// 桌面端本地命令行 Stdio MCP 客户端（JSON-RPC 2.0 换行分隔通信）
class StdioMcpClient implements McpClient {
  static const String _protocolVersion = '2025-03-26';

  final McpServerConfig config;
  Process? _process;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;
  final Map<int, Completer<Map<String, dynamic>>> _pending = {};
  final List<String> _stderrTail = [];
  int _nextId = 1;
  bool _initialized = false;

  StdioMcpClient({required this.config});

  static bool get isSupportedPlatform =>
      Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  @override
  Future<void> connect() async {
    if (!isSupportedPlatform) {
      throw UnsupportedError('Stdio MCP 仅支持桌面端（Windows / macOS / Linux），移动端请使用 HTTP MCP。');
    }
    final command = config.command.trim();
    if (command.isEmpty) {
      throw const FormatException('Stdio MCP 缺少可执行命令 (command)。');
    }
    await close();

    final process = await Process.start(
      command,
      config.args,
      environment: config.env.isEmpty ? null : config.env,
      runInShell: Platform.isWindows,
    );
    _process = process;

    _stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleStdoutLine,
          onError: (Object error) => _failAllPending(error),
        );

    _stderrSub = process.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final t = line.trim();
          if (t.isEmpty) return;
          _stderrTail.add(t);
          if (_stderrTail.length > 10) _stderrTail.removeAt(0);
        });

    unawaited(
      process.exitCode.then((code) {
        if (_process == process) {
          final tail = _stderrTail.isEmpty
              ? ''
              : '\nstderr: ${_stderrTail.join(' | ')}';
          _failAllPending(StateError('MCP 进程已退出 (code=$code)$tail'));
          _initialized = false;
        }
      }),
    );

    await _sendRpc('initialize', {
      'protocolVersion': _protocolVersion,
      'capabilities': const <String, Object?>{},
      'clientInfo': const {
        'name': 'novelai-harness',
        'version': '1.0.0',
      },
    });
    _initialized = true;
    _writeJsonLine({
      'jsonrpc': '2.0',
      'method': 'notifications/initialized',
      'params': const <String, Object?>{},
    });
  }

  void _handleStdoutLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) return;
      final map = Map<String, dynamic>.from(decoded);
      final rawId = map['id'];
      final id = rawId is int ? rawId : int.tryParse('$rawId');
      if (id != null && _pending.containsKey(id)) {
        _pending.remove(id)!.complete(map);
      }
    } catch (_) {
      // 忽略子进程输出到 stdout 的非 JSON 日志行
    }
  }

  void _writeJsonLine(Map<String, dynamic> payload) {
    final process = _process;
    if (process == null) {
      throw StateError('MCP Stdio 进程未启动。');
    }
    process.stdin.writeln(jsonEncode(payload));
  }

  Future<Object?> _sendRpc(String method, Map<String, dynamic> params) async {
    final id = _nextId++;
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;
    try {
      _writeJsonLine({
        'jsonrpc': '2.0',
        'id': id,
        'method': method,
        'params': params,
      });
      final response = await completer.future.timeout(
        Duration(seconds: config.timeoutSeconds),
        onTimeout: () {
          _pending.remove(id);
          final tail = _stderrTail.isEmpty
              ? ''
              : ' (${_stderrTail.last})';
          throw TimeoutException(
            'MCP 请求 "$method" 超时 (${config.timeoutSeconds}s)$tail',
          );
        },
      );
      if (response['error'] case final Map err) {
        throw StateError('MCP 错误 (${err['code']}): ${err['message'] ?? '未知错误'}');
      }
      return response['result'];
    } catch (_) {
      _pending.remove(id);
      rethrow;
    }
  }

  void _failAllPending(Object error) {
    final entries = _pending.values.toList();
    _pending.clear();
    for (final completer in entries) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
  }

  @override
  Future<List<McpToolDescriptor>> listTools() async {
    if (!_initialized || _process == null) await connect();
    final result = await _sendRpc('tools/list', const {});
    return parseMcpToolList(config, result);
  }

  @override
  Future<McpCallResult> callTool(
    String name,
    Map<String, dynamic> arguments,
  ) async {
    if (!_initialized || _process == null) await connect();
    final result = await _sendRpc('tools/call', {
      'name': name,
      'arguments': arguments,
    });
    return parseMcpToolCallResult(result);
  }

  @override
  Future<void> close() async {
    _initialized = false;
    _failAllPending(StateError('MCP 连接已关闭。'));
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    final process = _process;
    _process = null;
    if (process != null) {
      try {
        await process.stdin.close();
      } catch (_) {}
      process.kill();
    }
    _stderrTail.clear();
  }
}
