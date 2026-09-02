import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/novelai_models.dart';
import 'models_dev_catalog.dart';

/// 在线拉取远程供应商模型列表的原始条目 (仅服务端直接给出的字段)
class _RawModelEntry {
  final String id;
  final String? displayName;
  final bool? reasoning;
  final bool? multimodal;
  final bool? imageOutput;
  final int? contextWindow;
  final int? maxTokens;

  const _RawModelEntry({
    required this.id,
    this.displayName,
    this.reasoning,
    this.multimodal,
    this.imageOutput,
    this.contextWindow,
    this.maxTokens,
  });
}

/// 在线拉取结果：模型列表 + models.dev 元数据命中统计
class RemoteModelFetchResult {
  final List<LlmModelConfig> models;
  final int enrichedCount;

  const RemoteModelFetchResult({
    required this.models,
    required this.enrichedCount,
  });
}

/// 在线拉取与探测远程大语言模型列表服务
///
/// 能力元数据按以下优先级解析：
/// 1. 服务端返回的原生字段 (OpenRouter 的 architecture / context_length 等)
/// 2. models.dev 在线目录 (pi / pi-ai 同款权威数据源)
/// 3. 本地启发式猜测 (id 关键词匹配，兜底)
class LlmModelFetcher {
  final http.Client _client;
  final ModelsDevCatalog modelsDevCatalog;

  LlmModelFetcher({http.Client? client, ModelsDevCatalog? modelsDevCatalog})
    : _client = client ?? http.Client(),
      modelsDevCatalog = modelsDevCatalog ?? ModelsDevCatalog.instance;

  /// 计算用于获取模型列表的端点 URL
  static String calculateModelsEndpoint(String baseUrl, LlmProtocol protocol) {
    var base = baseUrl.trim();
    if (base.isEmpty) return '';
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }

    // 移除尾部可能附带的特定对话端点
    if (base.endsWith('/chat/completions')) {
      base = base.substring(0, base.length - '/chat/completions'.length);
    } else if (base.endsWith('/responses')) {
      base = base.substring(0, base.length - '/responses'.length);
    } else if (base.endsWith('/messages')) {
      base = base.substring(0, base.length - '/messages'.length);
    }

    if (base.endsWith('/models') || base.endsWith('/api/tags')) {
      return base;
    }

    // Ollama 端口 11434 且无 /v1 时优先 /api/tags，或直接拼接 /models
    if (base.contains(':11434') && !base.contains('/v1')) {
      return '$base/api/tags';
    }

    return '$base/models';
  }

  /// 智能检测模型是否具备深度思考 / 推理能力 (启发式兜底)
  static bool detectReasoningCapability(String modelId) {
    final lower = modelId.toLowerCase();
    return lower.contains('reasoner') ||
        lower.contains('-r1') ||
        lower.contains('r1-') ||
        lower.contains('_r1') ||
        lower.endsWith('r1') ||
        lower.contains('o1-') ||
        lower.contains('o1_') ||
        lower.contains('o3-') ||
        lower.contains('o3_') ||
        lower.contains('claude-3-7') ||
        lower.contains('claude-3.7') ||
        lower.contains('thinking') ||
        lower.contains('qwq') ||
        lower.contains('deepseek-r') ||
        lower.contains('sonar-reasoning');
  }

  /// 智能检测模型是否具备多模态 / 图像视觉理解能力 (启发式兜底)
  static bool detectMultimodalCapability(String modelId) {
    final lower = modelId.toLowerCase();
    return lower.contains('gpt-4o') ||
        lower.contains('4o-') ||
        lower.contains('4o_') ||
        lower.endsWith('4o') ||
        lower.contains('vision') ||
        lower.contains('-vl') ||
        lower.contains('_vl') ||
        lower.contains('claude-3') ||
        lower.contains('gemini') ||
        lower.contains('pixtral') ||
        lower.contains('llava') ||
        lower.contains('qvq') ||
        lower.contains('qwen-vl');
  }

  /// 智能检测模型是否具备图像生成 / 整图编辑输出能力 (启发式兜底)
  ///
  /// 只匹配明确的绘图 / 图像编辑模型关键字；vision 多模态模型 (如 qwen-vl、
  /// gpt-4o vision) 只能看图不能产图，不在此列。
  static bool detectImageOutputCapability(String modelId) {
    final lower = modelId.toLowerCase();
    return lower.contains(
          'flash-image',
        ) || // gemini-2.5-flash-image (nano banana)
        lower.contains('nano-banana') ||
        lower.contains('banana') ||
        lower.contains('gpt-image') ||
        lower.contains('dall-e') ||
        lower.contains('seedream') ||
        lower.contains('seededit') ||
        lower.contains('qwen-image') ||
        lower.contains('image-generation') ||
        lower.contains('image-edit') ||
        lower.contains('flux-kontext') ||
        lower.contains('imagen') ||
        lower.contains('image-preview');
  }

  /// 智能检测模型上下文窗口大小 (启发式兜底)
  static int detectContextWindow(String modelId) {
    final lower = modelId.toLowerCase();
    if (lower.contains('gemini-2.5-pro')) return 2000000;
    if (lower.contains('gemini-2.5-flash') || lower.contains('gemini-1.5')) {
      return 1000000;
    }
    if (lower.contains('claude') || lower.contains('o3-mini')) {
      return 200000;
    }
    if (lower.contains('gpt-4o') ||
        lower.contains('qwen2.5-coder') ||
        lower.contains('llama-3.3')) {
      return 128000;
    }
    if (lower.contains('deepseek')) return 64000;
    return 128000;
  }

  /// 发起在线网络请求获取远程供应商模型列表
  ///
  /// [existingModels] 为当前已配置的模型列表：同 id 模型保留用户设置的
  /// 名称与温度，仅刷新能力元数据；远端不存在的本地自定义模型会追加保留。
  Future<RemoteModelFetchResult> fetchRemoteModels({
    required String baseUrl,
    required LlmProtocol protocol,
    required String apiKey,
    List<LlmModelConfig> existingModels = const [],
  }) async {
    final endpoint = calculateModelsEndpoint(baseUrl, protocol);
    if (endpoint.isEmpty) {
      throw Exception('请先填写有效的 API 基础 URL');
    }

    final uri = Uri.parse(endpoint);
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    final trimmedKey = apiKey.trim();
    if (trimmedKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $trimmedKey';
      if (protocol == LlmProtocol.anthropicMessages ||
          baseUrl.contains('anthropic.com')) {
        headers['x-api-key'] = trimmedKey;
        headers['anthropic-version'] = '2023-06-01';
      }
    }

    http.Response response;
    try {
      response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 12));
    } catch (e) {
      throw Exception('网络连接失败 ($endpoint): $e');
    }

    if (response.statusCode != 200) {
      final errBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      throw Exception(
        '服务端响应错误 (HTTP ${response.statusCode}): ${errBody.length > 200 ? errBody.substring(0, 200) : errBody}',
      );
    }

    final dynamic decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );

    final rawModels = _parseRawModels(decoded);
    if (rawModels.isEmpty) {
      throw Exception('未能在返回数据中解析出模型列表');
    }

    // 合成能力元数据并统计 models.dev 命中数
    var enrichedCount = 0;
    final models = <LlmModelConfig>[];
    for (final raw in rawModels) {
      final dev = await _lookupDev(raw.id);
      if (dev != null) enrichedCount++;
      models.add(_resolveModelConfig(raw, dev, existingModels));
    }

    // 远端不存在的本地自定义模型追加保留
    final remoteIds = models.map((m) => m.id).toSet();
    for (final existing in existingModels) {
      if (!remoteIds.contains(existing.id)) {
        models.add(existing);
      }
    }

    return RemoteModelFetchResult(models: models, enrichedCount: enrichedCount);
  }

  Future<ModelsDevModelInfo?> _lookupDev(String modelId) async {
    try {
      return await modelsDevCatalog.lookup(modelId);
    } catch (_) {
      return null;
    }
  }

  /// 解析服务端原始模型条目 (支持 OpenAI / Anthropic / Ollama / 根数组等格式)
  List<_RawModelEntry> _parseRawModels(dynamic decoded) {
    List<dynamic>? items;
    if (decoded is Map<String, dynamic> && decoded['data'] is List) {
      items = decoded['data'] as List<dynamic>;
    } else if (decoded is Map<String, dynamic> && decoded['models'] is List) {
      items = decoded['models'] as List<dynamic>;
    } else if (decoded is List) {
      items = decoded;
    }
    if (items == null) return const [];

    final result = <_RawModelEntry>[];
    for (final item in items) {
      if (item is! Map<String, dynamic>) continue;
      final rawId = (item['id'] ?? item['model'] ?? item['name']) as String?;
      if (rawId == null || rawId.isEmpty) continue;
      final cleanId = rawId.startsWith('models/')
          ? rawId.substring('models/'.length)
          : rawId;
      result.add(_parseRawEntry(cleanId, item));
    }
    return result;
  }

  /// 提取服务端直接给出的能力字段 (OpenRouter 及部分兼容网关)
  _RawModelEntry _parseRawEntry(String id, Map<String, dynamic> item) {
    final displayName =
        item['display_name'] as String? ??
        item['displayName'] as String? ??
        (item['name'] is String && item['name'] != id
            ? item['name'] as String?
            : null);

    // OpenRouter: architecture.input_modalities / modality
    bool? multimodal;
    bool? imageOutput;
    final architecture = item['architecture'];
    if (architecture is Map<String, dynamic>) {
      final inputModalities = architecture['input_modalities'];
      if (inputModalities is List && inputModalities.isNotEmpty) {
        multimodal = inputModalities.any((m) => m.toString().contains('image'));
      } else {
        final modality = architecture['modality'];
        if (modality is String && modality.contains('image')) {
          multimodal = true;
        }
      }
      // OpenRouter: architecture.output_modalities 含 image 即为绘图模型
      final outputModalities = architecture['output_modalities'];
      if (outputModalities is List) {
        imageOutput = outputModalities.any((m) => m == 'image');
      }
    }

    // 思考能力: OpenRouter reasoning 字段或 supported_parameters 含 reasoning
    bool? reasoning = item['reasoning'] as bool?;
    final supportedParameters = item['supported_parameters'];
    if (reasoning == null && supportedParameters is List) {
      if (supportedParameters.any((p) => p == 'reasoning')) {
        reasoning = true;
      }
    }

    // 上下文窗口: OpenRouter context_length 及各家兼容字段
    int? contextWindow =
        (item['context_length'] as num?)?.toInt() ??
        (item['context_window'] as num?)?.toInt() ??
        (item['max_context_length'] as num?)?.toInt() ??
        (item['max_model_len'] as num?)?.toInt();
    if (contextWindow == null && architecture is Map<String, dynamic>) {
      contextWindow = (architecture['context_length'] as num?)?.toInt();
    }

    // 最大输出: OpenRouter top_provider.max_completion_tokens 及兼容字段
    int? maxTokens =
        (item['max_completion_tokens'] as num?)?.toInt() ??
        (item['max_output_tokens'] as num?)?.toInt() ??
        (item['max_tokens'] as num?)?.toInt();
    if (maxTokens == null) {
      final topProvider = item['top_provider'];
      if (topProvider is Map<String, dynamic>) {
        maxTokens =
            (topProvider['max_completion_tokens'] as num?)?.toInt() ??
            (topProvider['max_output_tokens'] as num?)?.toInt();
        contextWindow ??= (topProvider['context_length'] as num?)?.toInt();
      }
    }

    return _RawModelEntry(
      id: id,
      displayName: displayName,
      reasoning: reasoning,
      multimodal: multimodal,
      imageOutput: imageOutput,
      contextWindow: contextWindow,
      maxTokens: maxTokens,
    );
  }

  /// 按优先级合成最终模型配置: 服务端原生字段 > models.dev > 启发式
  LlmModelConfig _resolveModelConfig(
    _RawModelEntry raw,
    ModelsDevModelInfo? dev,
    List<LlmModelConfig> existingModels,
  ) {
    final existing = existingModels.where((m) => m.id == raw.id).firstOrNull;

    final isReasoning =
        raw.reasoning ?? dev?.reasoning ?? detectReasoningCapability(raw.id);
    final multimodalFlag =
        raw.multimodal ??
        ((dev?.input.contains('image') ?? false) ||
            detectMultimodalCapability(raw.id));

    var levels = const <ThinkingEffort>[];
    if (dev != null && dev.reasoning && dev.thinkingLevels.isNotEmpty) {
      levels = dev.thinkingLevels;
    } else if (isReasoning && dev == null) {
      levels = const [ThinkingEffort.high];
    }

    final contextWindow =
        raw.contextWindow ?? dev?.contextWindow ?? detectContextWindow(raw.id);
    final maxTokens = raw.maxTokens ?? dev?.maxTokens ?? 8192;

    final imageOutput =
        raw.imageOutput ??
        dev?.imageOutput ??
        (existing?.imageOutput ?? false) || detectImageOutputCapability(raw.id);

    // 用户改过名字 (name != id) 则保留，否则采用远端显示名
    final name = (existing != null && existing.name != existing.id)
        ? existing.name
        : (raw.displayName ?? dev?.name ?? raw.id);
    final temperature = existing?.temperature ?? (isReasoning ? 0.6 : 0.7);

    return LlmModelConfig(
      id: raw.id,
      name: name,
      reasoning: isReasoning,
      input: multimodalFlag ? const ['text', 'image'] : const ['text'],
      supportedThinkingLevels: levels,
      contextWindow: contextWindow,
      maxTokens: maxTokens,
      temperature: temperature,
      imageOutput: imageOutput,
    );
  }
}
