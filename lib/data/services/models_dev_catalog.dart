import 'dart:convert';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:http/http.dart' as http;
import '../models/novelai_models.dart';

/// models.dev 在线模型能力目录
///
/// models.dev 是社区维护的 LLM 元数据库 (pi / pi-ai 同款数据源)，
/// 提供每个模型的深度思考能力、输入模态、上下文窗口与最大输出 tokens
/// 等经过验证的权威数据，替代本地硬编码的猜测式能力判断。
class ModelsDevCatalog {
  ModelsDevCatalog({http.Client? client}) : _client = client ?? http.Client();

  static final ModelsDevCatalog instance = ModelsDevCatalog();

  final http.Client _client;

  /// 小写索引键 -> 候选模型条目 (同一 id 可能出现在多个供应商下)，加载成功后缓存
  Future<Map<String, List<ModelsDevModelInfo>>>? _loading;
  bool _loadFailed = false;

  /// 官方目录地址
  static const String catalogUrl = 'https://models.dev/api.json';

  /// 已知的一线供应商优先级 (同名模型 id 冲突时优先取这些供应商的条目)
  static const List<String> _preferredProviders = [
    'openai',
    'anthropic',
    'google',
    'deepseek',
    'mistral',
    'xai',
    'meta',
    'qwen',
    'moonshotai',
  ];

  /// 加载失败后本次会话内不再重试 (避免每次查询都等超时)
  Future<Map<String, List<ModelsDevModelInfo>>>? _getLoading() {
    if (_loadFailed) return null;
    return _loading ??= _load().then(
      (index) => index,
      onError: (_) {
        _loadFailed = true;
        _loading = null;
        return <String, List<ModelsDevModelInfo>>{};
      },
    );
  }

  Future<Map<String, List<ModelsDevModelInfo>>> _load() async {
    final response = await _client
        .get(Uri.parse(catalogUrl))
        .timeout(const Duration(seconds: 25));
    if (response.statusCode != 200) {
      throw Exception('models.dev 目录请求失败 (HTTP ${response.statusCode})');
    }
    final decoded = jsonDecode(
      utf8.decode(response.bodyBytes, allowMalformed: true),
    );
    if (decoded is! Map<String, dynamic>) {
      throw Exception('models.dev 目录格式异常');
    }
    return _buildIndex(decoded);
  }

  /// 解析目录 JSON 并构建查找索引
  @visibleForTesting
  static Map<String, List<ModelsDevModelInfo>> buildIndex(
    Map<String, dynamic> catalog,
  ) {
    final index = <String, List<ModelsDevModelInfo>>{};
    catalog.forEach((providerId, providerValue) {
      if (providerValue is! Map<String, dynamic>) return;
      final models = providerValue['models'];
      if (models is! Map<String, dynamic>) return;

      models.forEach((modelId, modelValue) {
        if (modelValue is! Map<String, dynamic>) return;
        final info = _parseEntry(providerId, modelId, modelValue);
        if (info == null) return;

        final key = modelId.toLowerCase();
        (index[key] ??= []).add(info);
        // 供应商前缀形式 (如 openrouter 的 "deepseek/deepseek-v3") 也可裸名命中
        final slash = modelId.lastIndexOf('/');
        if (slash >= 0 && slash < modelId.length - 1) {
          final base = modelId.substring(slash + 1).toLowerCase();
          (index[base] ??= []).add(info);
        }
      });
    });

    // 同键冲突时把一线供应商的条目排到最前
    final preferred = _preferredProviders.toSet();
    for (final entries in index.values) {
      entries.sort((a, b) {
        final pa = preferred.contains(a.providerId) ? 0 : 1;
        final pb = preferred.contains(b.providerId) ? 0 : 1;
        return pa.compareTo(pb);
      });
    }
    return index;
  }

  Map<String, List<ModelsDevModelInfo>> _buildIndex(
    Map<String, dynamic> catalog,
  ) => buildIndex(catalog);

  static ModelsDevModelInfo? _parseEntry(
    String providerId,
    String modelId,
    Map<String, dynamic> json,
  ) {
    // 只索引能输出文本的对话模型 (跳过 embedding / 生图专用模型)
    final modalities = json['modalities'];
    if (modalities is Map<String, dynamic>) {
      final output = modalities['output'];
      if (output is List && output.isNotEmpty && !output.contains('text')) {
        return null;
      }
    }

    final limit = json['limit'];
    int? context;
    int? outputLimit;
    if (limit is Map<String, dynamic>) {
      context = (limit['context'] as num?)?.toInt();
      outputLimit = (limit['output'] as num?)?.toInt();
    }

    final input = <String>['text'];
    if (modalities is Map<String, dynamic>) {
      final rawInput = modalities['input'];
      if (rawInput is List && rawInput.isNotEmpty) {
        input
          ..clear()
          ..addAll(
            rawInput
                .map((e) => e.toString())
                .where((m) => m == 'text' || m == 'image'),
          );
        if (input.isEmpty || !input.contains('text')) input.insert(0, 'text');
      }
    }

    return ModelsDevModelInfo(
      providerId: providerId,
      id: modelId,
      name: json['name'] as String? ?? modelId,
      reasoning: json['reasoning'] as bool? ?? false,
      thinkingLevels: _parseThinkingLevels(json['reasoning_options']),
      input: input,
      contextWindow: context,
      maxTokens: outputLimit,
    );
  }

  /// 将 models.dev 的 reasoning_options effort 值映射为本地思考等级
  static List<ThinkingEffort> _parseThinkingLevels(dynamic reasoningOptions) {
    if (reasoningOptions is! List) return const [];
    final efforts = <String>[];
    for (final option in reasoningOptions) {
      if (option is Map<String, dynamic> && option['type'] == 'effort') {
        final values = option['values'];
        if (values is List) {
          efforts.addAll(values.map((e) => e.toString()));
        }
      }
    }
    if (efforts.isEmpty) return const [];

    final levels = <ThinkingEffort>[];
    for (final value in efforts) {
      final ThinkingEffort? level = switch (value) {
        'minimal' || 'low' => ThinkingEffort.low,
        'medium' => ThinkingEffort.medium,
        'high' || 'xhigh' || 'max' => ThinkingEffort.high,
        _ => null,
      };
      if (level != null && !levels.contains(level)) levels.add(level);
    }
    // 保持 low -> medium -> high 的稳定顺序
    levels.sort((a, b) => a.index.compareTo(b.index));
    return levels;
  }

  /// 按模型 id 查询能力元数据
  ///
  /// 匹配顺序：完整 id -> 去掉供应商前缀的裸名 -> 去掉 Ollama ":tag" 后缀
  /// -> 去掉日期版本后缀 (如 gpt-4o-2024-08-06 -> gpt-4o)。
  /// 目录不可用或无匹配时返回 null，由调用方回退到本地启发式判断。
  Future<ModelsDevModelInfo?> lookup(String modelId) async {
    final trimmed = modelId.trim();
    if (trimmed.isEmpty) return null;

    final loading = _getLoading();
    if (loading == null) return null;
    final index = await loading;
    if (index.isEmpty) return null;

    for (final key in candidateKeys(trimmed)) {
      final entries = index[key];
      if (entries != null && entries.isNotEmpty) return entries.first;
    }
    return null;
  }

  /// 生成逐级放宽的候选查找键 (全部小写)
  @visibleForTesting
  static List<String> candidateKeys(String modelId) {
    final keys = <String>[];
    void add(String value) {
      final key = value.trim().toLowerCase();
      if (key.isNotEmpty && !keys.contains(key)) keys.add(key);
    }

    add(modelId);

    // 去掉供应商前缀: "deepseek/deepseek-v3" -> "deepseek-v3"
    final slash = modelId.lastIndexOf('/');
    var base = slash >= 0 ? modelId.substring(slash + 1) : modelId;
    if (base != modelId) add(base);

    // 去掉 Ollama 标签: "deepseek-r1:14b" -> "deepseek-r1"
    final colon = base.indexOf(':');
    if (colon > 0) {
      final noTag = base.substring(0, colon);
      add(noTag);
      base = noTag;
    }

    // 去掉日期版本后缀: "gpt-4o-2024-08-06" -> "gpt-4o"
    final dateStripped = base.replaceAllMapped(
      RegExp(r'-\d{4}-\d{2}-\d{2}$'),
      (_) => '',
    );
    if (dateStripped != base) add(dateStripped);

    return keys;
  }

  /// 仅用于测试：重置内存缓存与失败标记
  @visibleForTesting
  void debugReset() {
    _loading = null;
    _loadFailed = false;
  }
}

/// models.dev 目录中的单个模型能力条目
class ModelsDevModelInfo {
  final String providerId;
  final String id;
  final String name;
  final bool reasoning;
  final List<ThinkingEffort> thinkingLevels;
  final List<String> input;
  final int? contextWindow;
  final int? maxTokens;

  const ModelsDevModelInfo({
    required this.providerId,
    required this.id,
    required this.name,
    required this.reasoning,
    required this.thinkingLevels,
    required this.input,
    this.contextWindow,
    this.maxTokens,
  });
}
