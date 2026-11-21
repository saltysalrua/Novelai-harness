/// ComfyUI PromptToolkit AI Bridge 客户端服务。
///
/// 通过 PromptToolkit 自定义节点在 ComfyUI 服务器上注册的 `/pt/ai/*` HTTP
/// 路由驱动 ComfyUI：推送提示词 / 分辨率 / 采样参数、请求排队、轮询成品图。
/// 服务地址可自定义 (默认本机，支持局域网手机/平板联机场景)。
///
/// 协议事实源：reference/PromptToolkit `nodes/ai_bridge.py`。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/comfyui_models.dart';

/// ComfyUI AI Bridge 通信服务 (无状态，可按 baseUrl 随时重建)。
class ComfyUiService {
  /// 服务基地址，如 `http://127.0.0.1:8188` 或局域网 `http://192.168.1.20:8188`
  final String baseUrl;

  final http.Client _httpClient;
  final bool _ownsClient;

  ComfyUiService({required this.baseUrl, http.Client? httpClient})
    : _httpClient = httpClient ?? http.Client(),
      _ownsClient = httpClient == null;

  void close() {
    if (_ownsClient) _httpClient.close();
  }

  Uri _uri(String path, [Map<String, String>? query]) =>
      Uri.parse('$baseUrl$path').replace(queryParameters: query);

  // ------------------------- 探测与注册表 -------------------------

  /// 拉取 Bridge 三张注册表快照 (提示词 / 分辨率 / 采样参数节点)。
  ///
  /// `/pt/ai/params` 为 ParamsPanelPT 引入的新路由，旧版插件返回 404 时
  /// 按空表容错 (paramsNodeIds 为空，负向词与采样参数将不下发)。
  Future<ComfyUiBridgeState> fetchBridgeState({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    // 三个端点彼此独立，并行请求减少探测等待耗时；
    // `/pt/ai/params` 为 ParamsPanelPT 新路由，旧版返回 404 时按空表容错。
    final promptsFuture = _getJson('/pt/ai/prompt', timeout);
    final resolutionsFuture = _getJson('/pt/ai/resolution', timeout);
    final paramsFuture = _getJson('/pt/ai/params', timeout)
        .then<Map<String, dynamic>>(
          (value) => value,
          onError: (Object error, StackTrace stackTrace) {
            if (error is ComfyUiBridgeException) {
              return const <String, dynamic>{};
            }
            Error.throwWithStackTrace(error, stackTrace);
          },
        );
    final results = await Future.wait<Map<String, dynamic>>([
      promptsFuture,
      resolutionsFuture,
      paramsFuture,
    ]);
    return ComfyUiBridgeState.fromResponses(
      prompts: results[0],
      resolutions: results[1],
      params: results[2],
      baseUrl: baseUrl,
    );
  }

  // ------------------------- 参数下发 -------------------------

  /// 实时拉取 ComfyUI 服务器当前可用的采样器与调度器清单。
  ///
  /// 走 ComfyUI 标准 `/object_info` 端点 (无需 Bridge 路由)：优先读
  /// ParamsPanelPT 节点定义；节点不存在或旧版插件无采样器字段时，
  /// 回退到原生 KSampler 节点定义。两处都拿不到则抛出异常。
  Future<ComfyUiOptionCatalog> fetchOptionCatalog({
    Duration timeout = const Duration(seconds: 5),
  }) async {
    for (final nodeClass in const ['ParamsPanelPT', 'KSampler']) {
      final Map<String, dynamic> body;
      try {
        body = await _getJson('/object_info/$nodeClass', timeout);
      } on ComfyUiBridgeException {
        continue; // 节点未注册/旧版插件 → 尝试下一个
      }
      final samplers = _comboValues(body, 'sampler_name');
      final schedulers = _comboValues(body, 'scheduler');
      if (samplers.isEmpty && schedulers.isEmpty) continue;
      return ComfyUiOptionCatalog(samplers: samplers, schedulers: schedulers);
    }
    throw const ComfyUiBridgeException('服务器未返回可用的采样器与调度器清单');
  }

  /// 从 `/object_info/<Node>` 响应中提取组合 widget 的可选值列表。
  /// 响应结构为 `{<Node>: {input: {required: {field: [[values...], {...}]}}}}`，
  /// 与 ComfyUI 官方节点定义序列化格式一致。
  List<String> _comboValues(Map<String, dynamic> body, String field) {
    for (final spec in body.values) {
      if (spec is! Map<String, dynamic>) continue;
      final input = spec['input'];
      if (input is! Map<String, dynamic>) continue;
      final section = input['required'] ?? input['optional'];
      if (section is! Map<String, dynamic>) continue;
      final fieldSpec = section[field];
      if (fieldSpec is! List || fieldSpec.isEmpty) continue;
      final values = fieldSpec.first;
      if (values is! List) continue;
      return [
        for (final v in values)
          if (v is String) v,
      ];
    }
    return const [];
  }

  /// 设置 PromptPanel 节点的正向提示词 (前端画布 widget 实时同步)
  Future<void> setPrompt(String nodeId, String positive) =>
      _postJson('/pt/ai/prompt/set', {'node_id': nodeId, 'positive': positive});

  /// 设置 ResolutionMasterPT 节点的宽高 (batch 等字段不动)
  Future<void> setResolution(String nodeId, int width, int height) => _postJson(
    '/pt/ai/resolution/set',
    {'node_id': nodeId, 'width': width, 'height': height},
  );

  /// 设置 ParamsPanelPT 节点的负向词与采样参数 (仅下发补丁内非空字段)
  Future<void> setParams(String nodeId, ComfyUiParamsPatch patch) {
    if (patch.isEmpty) return Future.value();
    return _postJson('/pt/ai/params/set', {
      'node_id': nodeId,
      ...patch.toJson(),
    });
  }

  /// 请求前端按下 Queue (需要 ComfyUI 浏览器画布在线)
  Future<void> queue() => _postJson('/pt/ai/queue', const {});

  // ------------------------- 成品图 -------------------------

  /// 拉取最新的 Bridge 发布图片列表 (newest first)
  Future<List<ComfyUiBridgeImage>> latestImages({
    int limit = 5,
    Duration timeout = const Duration(seconds: 5),
  }) async {
    final body = await _getJson('/pt/ai/image/latest', timeout, {
      'limit': '$limit',
    });
    final list = body['images'];
    if (list is! List) return const [];
    return [
      for (final e in list)
        if (e is Map<String, dynamic>) ComfyUiBridgeImage.fromJson(e),
    ];
  }

  /// 拉取指定序号 (0 = 最新) 的全分辨率图片字节
  Future<Uint8List> rawImageBytes({
    int index = 0,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final response = await _run(
      () => _httpClient.get(_uri('/pt/ai/image/raw', {'index': '$index'})),
      timeout,
    );
    if (response.statusCode != 200) {
      throw ComfyUiBridgeException(
        '拉取图片失败 (HTTP ${response.statusCode})',
        isConnectionError: false,
      );
    }
    return response.bodyBytes;
  }

  // ------------------------- HTTP 基础设施 -------------------------

  Future<Map<String, dynamic>> _getJson(
    String path,
    Duration timeout, [
    Map<String, String>? query,
  ]) async {
    final response = await _run(
      () => _httpClient.get(_uri(path, query)),
      timeout,
    );
    return _decodeJsonBody(response);
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _run(
      () => _httpClient.post(
        _uri(path),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      ),
      const Duration(seconds: 8),
    );
    return _decodeJsonBody(response);
  }

  /// 执行请求并统一把连接层异常翻译成 [ComfyUiBridgeException]
  Future<http.Response> _run(
    Future<http.Response> Function() action,
    Duration timeout,
  ) async {
    try {
      return await action().timeout(timeout);
    } on TimeoutException {
      throw ComfyUiBridgeException('连接 $baseUrl 超时', isConnectionError: true);
    } on http.ClientException catch (e) {
      throw ComfyUiBridgeException(
        '无法连接 $baseUrl (${e.message})',
        isConnectionError: true,
      );
    }
  }

  Map<String, dynamic> _decodeJsonBody(http.Response response) {
    if (response.statusCode != 200) {
      var detail = '';
      if (response.body.isNotEmpty) {
        try {
          final decoded = jsonDecode(utf8.decode(response.bodyBytes));
          if (decoded is Map<String, dynamic> && decoded['error'] is String) {
            detail = decoded['error'] as String;
          }
        } catch (_) {}
      }
      throw ComfyUiBridgeException(
        detail.isEmpty ? 'HTTP ${response.statusCode}' : detail,
      );
    }
    try {
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is Map<String, dynamic>) return decoded;
    } catch (_) {}
    throw const ComfyUiBridgeException('响应不是有效的 JSON 对象');
  }
}
