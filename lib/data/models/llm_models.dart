/// LLM 供应商与模型配置 (协议、思考强度、模型元数据与出厂目录)。
library;

/// LLM 接口协议类型 (纯结构化枚举，UI 展示名由 model_label_l10n 接管)
enum LlmProtocol {
  openAiChat('openai', '/chat/completions'),
  openAiResponses('responses', '/responses'),
  anthropicMessages('messages', '/messages');

  final String id;
  final String defaultPath;
  const LlmProtocol(this.id, this.defaultPath);

  static LlmProtocol fromId(String id) {
    return LlmProtocol.values.firstWhere(
      (p) => p.id == id,
      orElse: () => LlmProtocol.openAiChat,
    );
  }
}

/// 思考参数请求格式 (对齐 pi openai-completions 的 thinkingFormat 兼容矩阵)
///
/// 不同供应商用不同字段开关思维链，格式不匹配时思考会被上游静默丢弃。
/// 纯结构化枚举，UI 展示名由 model_label_l10n 接管。
enum ThinkingParamFormat {
  auto('auto'),
  openai('openai'),
  deepseek('deepseek'),
  qwen('qwen'),
  qwenChatTemplate('qwen_chat_template'),
  zai('zai'),
  openrouter('openrouter'),
  together('together');

  final String id;
  const ThinkingParamFormat(this.id);

  static ThinkingParamFormat fromId(String? id) {
    return ThinkingParamFormat.values.firstWhere(
      (f) => f.id == id,
      orElse: () => ThinkingParamFormat.auto,
    );
  }
}

/// LLM 思考强度等级 (Reasoning / Thinking Effort)。
/// 纯结构化枚举，UI 展示名由 l10n chatThinkingEffort* 词条接管。
enum ThinkingEffort {
  off('off'),
  low('low'),
  medium('medium'),
  high('high');

  final String id;
  const ThinkingEffort(this.id);

  static ThinkingEffort fromId(String? id) {
    return ThinkingEffort.values.firstWhere(
      (e) => e.id == id,
      orElse: () => ThinkingEffort.medium,
    );
  }
}

/// 单个 LLM 模型元数据与配置项 (对标 pi-ai ModelCatalog 规范)
class LlmModelConfig {
  final String id;
  final String name;
  final bool reasoning;
  final List<String> input; // ['text'] 或 ['text', 'image'] (多模态视觉)
  final List<ThinkingEffort> supportedThinkingLevels; // 支持的思考等级梯度
  final int contextWindow; // 上下文窗口大小 (tokens)
  final int maxTokens; // 最大输出 tokens
  final double temperature;

  /// 是否具备图像生成 / 整图编辑输出能力 (如 nano banana / gpt-image)
  final bool imageOutput;

  const LlmModelConfig({
    required this.id,
    required this.name,
    this.reasoning = false,
    this.input = const ['text'],
    this.supportedThinkingLevels = const [],
    this.contextWindow = 128000,
    this.maxTokens = 8192,
    this.temperature = 0.7,
    this.imageOutput = false,
  });

  /// 是否具备多模态 / 图像视觉理解能力
  bool get isMultimodal => input.contains('image');

  /// 是否为图像生成 / 编辑模型 (可执行 AI 整图编辑)
  bool get isImageModel => imageOutput;

  /// 是否支持深度思考 / 推理扩展
  bool get supportsThinking => reasoning || supportedThinkingLevels.isNotEmpty;

  /// 快捷思考梯度 (若支持思考且无细分梯度，默认返回 high)
  ThinkingEffort get defaultThinkingEffort {
    if (supportedThinkingLevels.isNotEmpty) {
      return supportedThinkingLevels.contains(ThinkingEffort.medium)
          ? ThinkingEffort.medium
          : supportedThinkingLevels.last;
    }
    return reasoning ? ThinkingEffort.high : ThinkingEffort.off;
  }

  LlmModelConfig copyWith({
    String? id,
    String? name,
    bool? reasoning,
    List<String>? input,
    List<ThinkingEffort>? supportedThinkingLevels,
    int? contextWindow,
    int? maxTokens,
    double? temperature,
    bool? imageOutput,
  }) {
    return LlmModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      reasoning: reasoning ?? this.reasoning,
      input: input ?? this.input,
      supportedThinkingLevels:
          supportedThinkingLevels ?? this.supportedThinkingLevels,
      contextWindow: contextWindow ?? this.contextWindow,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
      imageOutput: imageOutput ?? this.imageOutput,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'reasoning': reasoning,
    'input': input,
    'supportedThinkingLevels': supportedThinkingLevels
        .map((e) => e.id)
        .toList(),
    'contextWindow': contextWindow,
    'maxTokens': maxTokens,
    'temperature': temperature,
    if (imageOutput) 'imageOutput': true,
  };

  factory LlmModelConfig.fromJson(Map<String, dynamic> json) {
    List<ThinkingEffort> levels = [];
    if (json['supportedThinkingLevels'] is List) {
      levels = (json['supportedThinkingLevels'] as List<dynamic>)
          .map((e) => ThinkingEffort.fromId(e as String?))
          .toList();
    } else if (json['thinkingEffort'] != null) {
      levels = [ThinkingEffort.fromId(json['thinkingEffort'] as String?)];
    }

    List<String> inputs = const ['text'];
    if (json['input'] is List) {
      inputs = (json['input'] as List<dynamic>)
          .map((e) => e.toString())
          .toList();
    }

    final isReasoning = json['reasoning'] as bool? ?? levels.isNotEmpty;

    return LlmModelConfig(
      id: json['id'] as String? ?? 'deepseek-chat',
      name:
          json['name'] as String? ?? (json['id'] as String? ?? 'Custom Model'),
      reasoning: isReasoning,
      input: inputs,
      supportedThinkingLevels: levels,
      contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 128000,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 8192,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
      imageOutput: json['imageOutput'] as bool? ?? false,
    );
  }
}

/// LLM 供应商配置模型
class LlmProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  final LlmProtocol protocol;
  final String apiKey;
  final List<LlmModelConfig> models;
  final String activeModelId;

  /// 思考参数请求格式 (auto = 按 baseUrl 域名自动识别，中转站可手动指定)
  final ThinkingParamFormat thinkingParamFormat;

  const LlmProviderConfig({
    required this.id,
    required this.name,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.protocol = LlmProtocol.openAiChat,
    this.apiKey = '',
    this.models = const [],
    this.activeModelId = '',
    this.thinkingParamFormat = ThinkingParamFormat.auto,
  });

  /// 获取当前激活的模型配置
  LlmModelConfig get activeModel {
    if (models.isEmpty) {
      return const LlmModelConfig(id: 'default', name: '默认模型');
    }
    return models.firstWhere(
      (m) => m.id == activeModelId,
      orElse: () => models.first,
    );
  }

  /// 动态计算最终完整的请求 API URL
  String get fullEndpointUrl {
    var base = baseUrl.trim();
    if (base.isEmpty) return '';
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final path = protocol.defaultPath;
    if (base.endsWith(path)) return base;
    return '$base$path';
  }

  LlmProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    LlmProtocol? protocol,
    String? apiKey,
    List<LlmModelConfig>? models,
    String? activeModelId,
    ThinkingParamFormat? thinkingParamFormat,
  }) {
    return LlmProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      protocol: protocol ?? this.protocol,
      apiKey: apiKey ?? this.apiKey,
      models: models ?? this.models,
      activeModelId: activeModelId ?? this.activeModelId,
      thinkingParamFormat: thinkingParamFormat ?? this.thinkingParamFormat,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'protocol': protocol.id,
    'apiKey': apiKey,
    'models': models.map((m) => m.toJson()).toList(),
    'activeModelId': activeModelId.isNotEmpty
        ? activeModelId
        : (models.isNotEmpty ? models.first.id : ''),
    'thinkingParamFormat': thinkingParamFormat.id,
  };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    List<LlmModelConfig> parsedModels = [];
    if (json['models'] is List) {
      parsedModels = (json['models'] as List<dynamic>)
          .map((e) => LlmModelConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // 兼容旧配置无 models 的情况
    if (parsedModels.isEmpty) {
      final oldModel = json['model'] as String? ?? 'deepseek-chat';
      final oldTemp = (json['temperature'] as num?)?.toDouble() ?? 0.7;
      parsedModels = [
        LlmModelConfig(id: oldModel, name: oldModel, temperature: oldTemp),
      ];
    }

    final activeId =
        json['activeModelId'] as String? ??
        (json['model'] as String? ?? parsedModels.first.id);

    return LlmProviderConfig(
      id:
          json['id'] as String? ??
          'provider_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Custom Provider',
      baseUrl: json['baseUrl'] as String? ?? 'https://api.deepseek.com/v1',
      protocol: LlmProtocol.fromId(json['protocol'] as String? ?? 'openai'),
      apiKey: json['apiKey'] as String? ?? '',
      models: parsedModels,
      activeModelId: activeId,
      thinkingParamFormat: ThinkingParamFormat.fromId(
        json['thinkingParamFormat'] as String?,
      ),
    );
  }

  /// 对标 pi-ai 的权威内置出厂预设供应商与模型目录
  static List<LlmProviderConfig> get defaultProviders => [
    // 1. DeepSeek 官方
    const LlmProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'deepseek-chat',
      models: [
        LlmModelConfig(
          id: 'deepseek-chat',
          name: 'DeepSeek V3',
          reasoning: false,
          input: ['text'],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'deepseek-reasoner',
          name: 'DeepSeek R1',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [ThinkingEffort.high],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.6,
        ),
      ],
    ),

    // 2. OpenAI 官方
    const LlmProviderConfig(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'gpt-4o',
      models: [
        LlmModelConfig(
          id: 'gpt-4o',
          name: 'GPT-4o',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 128000,
          maxTokens: 16384,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'gpt-4o-mini',
          name: 'GPT-4o Mini',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 128000,
          maxTokens: 16384,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'o3-mini',
          name: 'o3-mini',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 200000,
          maxTokens: 100000,
          temperature: 1.0,
        ),
        LlmModelConfig(
          id: 'o1',
          name: 'o1',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 200000,
          maxTokens: 100000,
          temperature: 1.0,
        ),
      ],
    ),

    // 3. Anthropic 官方
    const LlmProviderConfig(
      id: 'anthropic',
      name: 'Anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      protocol: LlmProtocol.anthropicMessages,
      apiKey: '',
      activeModelId: 'claude-3-7-sonnet-20250219',
      models: [
        LlmModelConfig(
          id: 'claude-3-7-sonnet-20250219',
          name: 'Claude 3.7 Sonnet',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 200000,
          maxTokens: 64000,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'claude-3-5-sonnet-20241022',
          name: 'Claude 3.5 Sonnet',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 200000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'claude-3-5-haiku-20241022',
          name: 'Claude 3.5 Haiku',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 200000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
      ],
    ),

    // 4. Google (Gemini)
    const LlmProviderConfig(
      id: 'google',
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'gemini-2.5-flash',
      models: [
        LlmModelConfig(
          id: 'gemini-2.5-flash',
          name: 'Gemini 2.5 Flash',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 1000000,
          maxTokens: 65536,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'gemini-2.5-pro',
          name: 'Gemini 2.5 Pro',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 2000000,
          maxTokens: 65536,
          temperature: 0.7,
        ),
      ],
    ),

    // 5. SiliconFlow (硅基流动)
    const LlmProviderConfig(
      id: 'siliconflow',
      name: 'SiliconFlow',
      baseUrl: 'https://api.siliconflow.cn/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'deepseek-ai/DeepSeek-V3',
      models: [
        LlmModelConfig(
          id: 'deepseek-ai/DeepSeek-V3',
          name: 'DeepSeek V3 (SiliconFlow)',
          reasoning: false,
          input: ['text'],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'deepseek-ai/DeepSeek-R1',
          name: 'DeepSeek R1 (SiliconFlow)',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [ThinkingEffort.high],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.6,
        ),
        LlmModelConfig(
          id: 'Qwen/Qwen2.5-Coder-32B-Instruct',
          name: 'Qwen 2.5 Coder 32B',
          reasoning: false,
          input: ['text'],
          contextWindow: 128000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
      ],
    ),

    // 6. Ollama 本地模型
    const LlmProviderConfig(
      id: 'ollama',
      name: 'Ollama (Local)',
      baseUrl: 'http://localhost:11434/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'llama3.3',
      models: [
        LlmModelConfig(
          id: 'llama3.3',
          name: 'Llama 3.3 70B',
          reasoning: false,
          input: ['text'],
          contextWindow: 128000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'deepseek-r1:14b',
          name: 'DeepSeek R1 14B',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [ThinkingEffort.high],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.6,
        ),
        LlmModelConfig(
          id: 'qwen2.5:7b',
          name: 'Qwen 2.5 7B',
          reasoning: false,
          input: ['text'],
          contextWindow: 32000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
      ],
    ),
  ];
}
