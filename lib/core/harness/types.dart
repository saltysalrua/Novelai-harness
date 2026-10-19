import 'dart:convert';
import 'dart:typed_data';

/// Pi 用量口径：input 仅含未缓存输入，缓存读写独立计数。
class TokenUsage {
  final int input;
  final int output;
  final int cacheRead;
  final int cacheWrite;

  /// 所有有输入的请求是否都报告了缓存读数。混合/缺失统计不伪装成 0%。
  final bool cacheReadReported;

  const TokenUsage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    bool? cacheReadReported,
  }) : cacheReadReported = cacheReadReported ?? (cacheRead > 0);

  int get totalInput => input + cacheRead + cacheWrite;
  int get total => totalInput + output;

  double? get cacheHitRate =>
      cacheReadReported && totalInput > 0 ? cacheRead / totalInput : null;

  TokenUsage add(TokenUsage other) => TokenUsage(
    input: input + other.input,
    output: output + other.output,
    cacheRead: cacheRead + other.cacheRead,
    cacheWrite: cacheWrite + other.cacheWrite,
    cacheReadReported:
        (totalInput == 0 || cacheReadReported) &&
        (other.totalInput == 0 || other.cacheReadReported),
  );

  Map<String, dynamic> toJson() => {
    'input': input,
    'output': output,
    'cacheRead': cacheRead,
    'cacheWrite': cacheWrite,
    'cacheReadReported': cacheReadReported,
    'inputAccounting': 'exclusive',
  };

  static int _count(Object? value) =>
      value is num && value.isFinite && value > 0 ? value.toInt() : 0;

  /// API 边界单独解析，不能与落盘 Pi 字段相加。别名按 pi 优先级短路，零也有效。
  factory TokenUsage.fromOpenAiJson(Map<String, dynamic> json) {
    final details = json['prompt_tokens_details'];
    final rawRead = [
      if (details is Map) details['cached_tokens'],
      json['prompt_cache_hit_tokens'],
      json['cached_tokens'],
    ].whereType<num>().firstOrNull;
    final read = _count(rawRead);
    final write = _count(details is Map ? details['cache_write_tokens'] : null);
    final prompt = _count(json['prompt_tokens']);
    return TokenUsage(
      input: (prompt - read - write).clamp(0, prompt),
      output: _count(json['completion_tokens']),
      cacheRead: read,
      cacheWrite: write,
      cacheReadReported: rawRead != null && rawRead.isFinite && rawRead >= 0,
    );
  }

  /// 已归一化的 Pi / 本地用量。旧外部 Pi 数据维持互斥口径，不盲目减缓存。
  factory TokenUsage.fromJson(dynamic json) {
    if (json is! Map) return const TokenUsage();
    if (json is Map<String, dynamic> && json.containsKey('prompt_tokens')) {
      return TokenUsage.fromOpenAiJson(json);
    }
    final read = _count(json['cacheRead']);
    return TokenUsage(
      input: _count(json['input']),
      output: _count(json['output']),
      cacheRead: read,
      cacheWrite: _count(json['cacheWrite']),
      cacheReadReported: json['cacheReadReported'] as bool? ?? (read > 0),
    );
  }

  /// 仅本应用旧账本 v1 / api=openai-chat 会话适用：旧 input 包含缓存。
  /// 惰性读取迁移，不覆盖原始会话；新记录自带口径标记，重复读取不再减一次。
  factory TokenUsage.fromLegacyAppJson(dynamic json) {
    final usage = TokenUsage.fromJson(json);
    if (json is! Map || json['inputAccounting'] == 'exclusive') return usage;
    return TokenUsage(
      input: (usage.input - usage.cacheRead - usage.cacheWrite).clamp(
        0,
        usage.input,
      ),
      output: usage.output,
      cacheRead: usage.cacheRead,
      cacheWrite: usage.cacheWrite,
      cacheReadReported: usage.cacheReadReported,
    );
  }
}

/// 对话角色
enum AgentRole {
  system('system'),
  user('user'),
  assistant('assistant'),
  tool('tool');

  final String value;
  const AgentRole(this.value);
}

/// 工具调用定义
class ToolCall {
  final String id;
  final String name;
  final Map<String, dynamic> arguments;
  final String? thoughtSignature;

  const ToolCall({
    required this.id,
    required this.name,
    required this.arguments,
    this.thoughtSignature,
  });

  Map<String, dynamic> toOpenAiJson() {
    return {
      'id': id,
      'type': 'function',
      'function': {'name': name, 'arguments': jsonEncode(arguments)},
      if (thoughtSignature != null && thoughtSignature!.isNotEmpty)
        'extra_content': {
          'google': {'thought_signature': thoughtSignature},
        },
    };
  }
}

/// 对话消息内嵌图片 (用户上传/粘贴的图片附件，base64 + MIME)
class AgentMessageImage {
  /// 图片字节 base64 (不含 data: 前缀)
  final String base64;

  /// 图片 MIME 类型 (默认 image/png)
  final String mimeType;

  static final Expando<Uint8List> _bytesCache = Expando<Uint8List>(
    'agent_message_image_bytes',
  );

  const AgentMessageImage({required this.base64, this.mimeType = 'image/png'});

  /// 解码后的二进制字节（惰性只读缓存）
  Uint8List get bytes {
    final cached = _bytesCache[this];
    if (cached != null) return cached;
    final decoded = base64.isEmpty
        ? Uint8List(0)
        : Uint8List.fromList(base64Decode(base64));
    _bytesCache[this] = decoded;
    return decoded;
  }

  /// 预注入解码缓存（如由原始 Uint8List 编码构建时）
  void attachBytes(Uint8List bytes) {
    _bytesCache[this] = bytes;
  }

  /// 从原始字节构建并预热解码缓存
  factory AgentMessageImage.fromBytes({
    required Uint8List bytes,
    String mimeType = 'image/png',
  }) {
    final image = AgentMessageImage(
      base64: base64Encode(bytes),
      mimeType: mimeType,
    );
    _bytesCache[image] = bytes;
    return image;
  }

  /// OpenAI 多模态 image_url 填充用 data URL
  String get dataUrl => 'data:$mimeType;base64,$base64';

  Map<String, dynamic> toJson() => {'mimeType': mimeType, 'data': base64};

  factory AgentMessageImage.fromJson(dynamic json) {
    if (json is! Map) return const AgentMessageImage(base64: '');
    final data = json['data'] as String? ?? '';
    if (data.isEmpty) return const AgentMessageImage(base64: '');
    return AgentMessageImage(
      base64: data,
      mimeType: json['mimeType'] as String? ?? 'image/png',
    );
  }
}

/// 必须跨轮原样回放的一段推理。
///
/// Responses 使用 [id] / [encryptedContent] / [summary] / [content]。
/// 明文网关没有加密载荷时，[content] 为 `reasoning_text`。
/// Anthropic 使用 [signature] 或 [redactedData]。未知 id 保持为空，回放时不补造。
class ReasoningRecord {
  final String? id;
  final String? encryptedContent;
  final List<Map<String, String>> summary;
  final List<Map<String, String>> content;
  final String? signature;
  final String? redactedData;

  const ReasoningRecord({
    this.id,
    this.encryptedContent,
    this.summary = const [],
    this.content = const [],
    this.signature,
    this.redactedData,
  });

  bool get isRedacted => redactedData != null && redactedData!.isNotEmpty;

  bool get isEmpty =>
      (id == null || id!.isEmpty) &&
      (encryptedContent == null || encryptedContent!.isEmpty) &&
      summary.isEmpty &&
      content.isEmpty &&
      (signature == null || signature!.isEmpty) &&
      !isRedacted;

  /// 可见推理文本：优先明文 content，否则用 summary。
  String get plaintext {
    final fromContent = _joinText(content);
    if (fromContent.isNotEmpty) return fromContent;
    return _joinText(summary);
  }

  static String _joinText(List<Map<String, String>> parts) {
    final buffer = StringBuffer();
    for (final part in parts) {
      final text = part['text'];
      if (text != null) buffer.write(text);
    }
    return buffer.toString();
  }

  /// Responses `input` 中的 reasoning 项。没有可发送字段时返回 null。
  Map<String, dynamic>? toResponsesItem() {
    final item = <String, dynamic>{'type': 'reasoning'};
    if (id != null && id!.isNotEmpty) item['id'] = id;
    if (encryptedContent != null && encryptedContent!.isNotEmpty) {
      item['encrypted_content'] = encryptedContent;
    }
    if (summary.isNotEmpty) {
      item['summary'] = [
        for (final part in summary) Map<String, String>.from(part),
      ];
    }
    if (content.isNotEmpty) {
      item['content'] = [
        for (final part in content) Map<String, String>.from(part),
      ];
    }
    // 仅有 Anthropic 签名或 redacted 数据时，不能编造成 Responses 项。
    if (item.length == 1) return null;
    return item;
  }

  /// Anthropic Messages 的 thinking / redacted_thinking 块。
  Map<String, dynamic>? toAnthropicBlock() {
    if (isRedacted) {
      return {'type': 'redacted_thinking', 'data': redactedData};
    }
    final text = plaintext;
    final sig = signature;
    if (text.isEmpty && (sig == null || sig.isEmpty)) return null;
    return {
      'type': 'thinking',
      'thinking': text,
      if (sig != null && sig.isNotEmpty) 'signature': sig,
    };
  }

  factory ReasoningRecord.fromResponsesItem(Map<String, dynamic> item) {
    final rawId = item['id'];
    final encrypted = item['encrypted_content'];
    return ReasoningRecord(
      id: rawId is String && rawId.isNotEmpty ? rawId : null,
      encryptedContent: encrypted is String && encrypted.isNotEmpty
          ? encrypted
          : null,
      summary: textParts(item['summary'], 'summary_text', keepType: true),
      content: textParts(item['content'], 'reasoning_text', keepType: false),
    );
  }

  Map<String, dynamic> toSessionJson() => {
    'type': 'reasoning',
    if (id != null && id!.isNotEmpty) 'id': id,
    if (encryptedContent != null && encryptedContent!.isNotEmpty)
      'encrypted_content': encryptedContent,
    if (summary.isNotEmpty) 'summary': summary,
    if (content.isNotEmpty) 'content': content,
    if (signature != null && signature!.isNotEmpty) 'signature': signature,
    if (isRedacted) 'redacted_data': redactedData,
  };

  factory ReasoningRecord.fromSessionJson(Map<String, dynamic> json) {
    final rawId = json['id'];
    final encrypted = json['encrypted_content'];
    final sig = json['signature'];
    final redacted = json['redacted_data'];
    return ReasoningRecord(
      id: rawId is String && rawId.isNotEmpty ? rawId : null,
      encryptedContent: encrypted is String && encrypted.isNotEmpty
          ? encrypted
          : null,
      summary: textParts(json['summary'], 'summary_text', keepType: true),
      content: textParts(json['content'], 'reasoning_text', keepType: false),
      signature: sig is String && sig.isNotEmpty ? sig : null,
      redactedData: redacted is String && redacted.isNotEmpty ? redacted : null,
    );
  }

  /// 把摘要或 reasoning_text 内容收成稳定的字符串 map。
  /// [keepType] 为 false 时统一写成 [defaultType]，避免回放未知 part type。
  static List<Map<String, String>> textParts(
    Object? raw,
    String defaultType, {
    required bool keepType,
  }) {
    if (raw is String) {
      if (raw.isEmpty) return const [];
      return [
        {'type': defaultType, 'text': raw},
      ];
    }
    if (raw is! List) return const [];
    final parts = <Map<String, String>>[];
    for (final part in raw) {
      if (part is String) {
        if (part.isEmpty) continue;
        parts.add({'type': defaultType, 'text': part});
        continue;
      }
      if (part is! Map) continue;
      final text = part['text'];
      if (text is! String || text.isEmpty) continue;
      final rawType = part['type'];
      final type = keepType && rawType is String && rawType.isNotEmpty
          ? rawType
          : defaultType;
      parts.add({'type': type, 'text': text});
    }
    return parts;
  }
}

/// 工具执行结果
///
/// [imageBase64] / [imageMimeType] 为可选的多模态图片附件：
/// 携带时工具结果消息会以 OpenAI 多模态内容块 (text + image_url)
/// 回传给 LLM，供具备视觉能力的模型直接查看图片。
class ToolResult {
  final String toolCallId;
  final String toolName;
  final String content;
  final bool isError;

  /// 附带给 LLM 查看的图片 (PNG/JPEG 等的 base64 编码，不含 data: 前缀)
  final String? imageBase64;

  /// 图片 MIME 类型 (默认 image/png)
  final String imageMimeType;

  const ToolResult({
    required this.toolCallId,
    this.toolName = '',
    required this.content,
    this.isError = false,
    this.imageBase64,
    this.imageMimeType = 'image/png',
  });
}

/// 对话单条消息
class AgentMessage {
  final String id;
  final AgentRole role;
  final String content;
  final int? replyNumber;
  final String thoughts; // 思考过程 (Reasoning / Thinking)
  final String? thoughtSignature; // 思考加密签名 (Gemini 3/4 多轮工具与推理连续性必需)

  /// 按模型输出顺序保存的推理项，供下一轮原样回放。
  final List<ReasoningRecord> reasoningRecords;
  final List<ToolCall>? toolCalls;
  final String? toolCallId;
  final String? toolName; // 工具结果消息对应的工具名 (仅 role == tool)
  final bool isError; // 工具结果是否出错 (仅 role == tool)
  final TokenUsage? usage; // 本条 assistant 消息的 Token 用量
  final String? provider; // 产生本条消息的供应商标识 (仅 assistant)
  final String? model; // 产生本条消息的模型 ID (仅 assistant)

  /// 工具结果附带的图片 (base64，仅 role == tool，不落盘会话记录)
  final String? imageBase64;

  /// 工具结果附带图片的 MIME 类型 (默认 image/png)
  final String imageMimeType;

  /// 用户消息附带的图片 (粘贴/选择文件上传，仅 role == user)
  final List<AgentMessageImage> images;

  /// 图片所属的发送轮次 (AgentHarness 每次自增)。
  /// 只有与当前轮次相等时图片数据才会真正发给模型 (一次性展示)，
  /// 更早轮次的图片在构建请求时折叠为固定占位文本，控制视觉 Token
  /// 并保持提示缓存前缀稳定。不落盘会话记录，恢复的历史消息恒为 0。
  final int imageEpoch;

  final bool isStreaming;
  final DateTime createdAt;

  /// 工具结果附带图片的解码二进制字节缓存
  Uint8List? _imageBytes;

  /// 工具结果附带图片的解码二进制字节（惰性只读缓存）
  Uint8List? get imageBytes {
    if (imageBase64 == null || imageBase64!.isEmpty) return null;
    return _imageBytes ??= Uint8List.fromList(base64Decode(imageBase64!));
  }

  /// "provider/model" 聚合键 (用量统计用)
  String? get providerModelKey =>
      (provider == null || provider!.isEmpty || model == null || model!.isEmpty)
      ? null
      : '$provider/$model';

  AgentMessage({
    required this.id,
    required this.role,
    this.content = '',
    this.thoughts = '',
    this.thoughtSignature,
    this.reasoningRecords = const [],
    this.replyNumber,
    this.toolCalls,
    this.toolCallId,
    this.toolName,
    this.isError = false,
    this.usage,
    this.provider,
    this.model,
    this.imageBase64,
    this.imageMimeType = 'image/png',
    this.images = const [],
    this.imageEpoch = 0,
    this.isStreaming = false,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  AgentMessage copyWith({
    String? id,
    AgentRole? role,
    String? content,
    String? thoughts,
    String? thoughtSignature,
    List<ReasoningRecord>? reasoningRecords,
    int? replyNumber,
    List<ToolCall>? toolCalls,
    String? toolCallId,
    String? toolName,
    bool? isError,
    TokenUsage? usage,
    String? provider,
    String? model,
    bool? isStreaming,
    DateTime? createdAt,
    String? imageBase64,
    String? imageMimeType,
    List<AgentMessageImage>? images,
    int? imageEpoch,
  }) {
    final nextImageBase64 = imageBase64 ?? this.imageBase64;
    final copy = AgentMessage(
      id: id ?? this.id,
      role: role ?? this.role,
      content: content ?? this.content,
      thoughts: thoughts ?? this.thoughts,
      thoughtSignature: thoughtSignature ?? this.thoughtSignature,
      reasoningRecords: reasoningRecords ?? this.reasoningRecords,
      replyNumber: replyNumber ?? this.replyNumber,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId ?? this.toolCallId,
      toolName: toolName ?? this.toolName,
      isError: isError ?? this.isError,
      usage: usage ?? this.usage,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      imageBase64: nextImageBase64,
      imageMimeType: imageMimeType ?? this.imageMimeType,
      images: images ?? this.images,
      imageEpoch: imageEpoch ?? this.imageEpoch,
      isStreaming: isStreaming ?? this.isStreaming,
      createdAt: createdAt ?? this.createdAt,
    );
    if (nextImageBase64 == this.imageBase64) {
      copy._imageBytes = _imageBytes;
    }
    return copy;
  }

  /// 是否携带供视觉模型查看的图片数据 (用户附件或工具结果附带)
  bool get hasVisionImages =>
      (role == AgentRole.user && images.isNotEmpty) ||
      (role == AgentRole.tool &&
          imageBase64 != null &&
          imageBase64!.isNotEmpty);

  /// 生成"图片已折叠"的请求替身：清除全部图片数据，正文末尾附加固定占位符。
  /// 仅用于构建 LLM 请求 (UI 展示与会话落盘仍保留原消息)，占位文本必须
  /// 恒定不变，否则会击穿提示缓存前缀。
  AgentMessage withVisionImagesCollapsed(String placeholder) {
    return AgentMessage(
      id: id,
      role: role,
      content: content.isEmpty ? placeholder : '$content\n\n$placeholder',
      thoughts: thoughts,
      thoughtSignature: thoughtSignature,
      reasoningRecords: reasoningRecords,
      replyNumber: replyNumber,
      toolCalls: toolCalls,
      toolCallId: toolCallId,
      toolName: toolName,
      isError: isError,
      usage: usage,
      provider: provider,
      model: model,
      imageMimeType: imageMimeType,
      images: const [],
      imageEpoch: imageEpoch,
      isStreaming: isStreaming,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toOpenAiJson() {
    final map = <String, dynamic>{'role': role.value, 'content': content};
    if (toolCalls != null && toolCalls!.isNotEmpty) {
      map['tool_calls'] = toolCalls!.map((t) => t.toOpenAiJson()).toList();
    }
    if (toolCallId != null) {
      map['tool_call_id'] = toolCallId;
    }
    // 工具结果携带图片时，content 升级为 OpenAI 多模态内容块数组
    // (text + image_url data URL)，供视觉模型直接查看。
    if (role == AgentRole.tool &&
        imageBase64 != null &&
        imageBase64!.isNotEmpty) {
      map['content'] = [
        {'type': 'text', 'text': content},
        {
          'type': 'image_url',
          'image_url': {'url': 'data:$imageMimeType;base64,$imageBase64'},
        },
      ];
    }
    // 用户消息携带图片时，content 同样升级为多模态内容块数组
    if (role == AgentRole.user && images.isNotEmpty) {
      map['content'] = [
        if (content.isNotEmpty) {'type': 'text', 'text': content},
        for (final img in images)
          {
            'type': 'image_url',
            'image_url': {'url': img.dataUrl},
          },
      ];
    }
    return map;
  }
}

/// Harness 事件抽象
sealed class HarnessEvent {
  const HarnessEvent();
}

class TurnStartEvent extends HarnessEvent {
  final String messageId;
  TurnStartEvent(this.messageId);
}

class ThoughtDeltaEvent extends HarnessEvent {
  final String delta;
  ThoughtDeltaEvent(this.delta);
}

class ThoughtSignatureEvent extends HarnessEvent {
  final String signature;
  const ThoughtSignatureEvent(this.signature);
}

/// 一轮助手响应里按输出顺序收集到的推理项。后到的快照覆盖先前的。
class ReasoningSnapshotEvent extends HarnessEvent {
  final List<ReasoningRecord> records;
  const ReasoningSnapshotEvent(this.records);
}

class ContentDeltaEvent extends HarnessEvent {
  final String delta;
  ContentDeltaEvent(this.delta);
}

class ToolCallEvent extends HarnessEvent {
  final ToolCall toolCall;
  ToolCallEvent(this.toolCall);
}

class ToolResultEvent extends HarnessEvent {
  final ToolResult result;
  ToolResultEvent(this.result);
}

class UsageEvent extends HarnessEvent {
  final TokenUsage usage;
  UsageEvent(this.usage);
}

class TurnEndEvent extends HarnessEvent {
  final AgentMessage finalMessage;
  TurnEndEvent(this.finalMessage);
}

/// 应用自身能稳定识别、由 UI 负责本地化的 Harness 错误。
///
/// 外部供应商错误不设 code，以保留其原始详情和协议原文。
enum HarnessErrorCode {
  providerNotConfigured,
  apiKeyMissing,
  contextWindowInsufficient,
  modelRequestFailed,
}

class ErrorEvent extends HarnessEvent {
  final String error;

  /// 可本地化的应用内置错误；null 表示 [error] 应原样展示。
  final HarnessErrorCode? code;

  /// 是否为瞬态错误 (网络抖动 / 429 / 5xx / 流中断 / 空响应)。
  /// true 时 Harness 会指数退避自动重试，false 则直接终止本轮对话。
  final bool transient;

  const ErrorEvent(this.error, {this.transient = false, this.code});
}

/// 一轮流式请求失败后的自动重试通知 (退避等待前发出)
class RetryEvent extends HarnessEvent {
  /// 即将进行的第几次尝试 (从 2 开始计数，首次失败后为 2)
  final int attempt;

  /// 含首次请求在内的总尝试上限
  final int maxAttempts;

  /// 上一次失败的简短原因
  final String reason;

  /// 本次退避等待时长
  final Duration delay;

  RetryEvent({
    required this.attempt,
    required this.maxAttempts,
    required this.reason,
    required this.delay,
  });
}

/// 上下文自动压缩完成通知：更早的消息已被摘要替换。
/// 原始消息仍保留在 UI 消息流与会话落盘中，仅从 LLM 请求上下文里移出。
class CompactionEvent extends HarnessEvent {
  /// 压缩生成的结构化摘要文本
  final String summary;

  /// 压缩前的上下文 Token 估算值
  final int tokensBefore;

  /// 压缩后的上下文 Token 估算值 (含保留的近期消息窗口)
  final int tokensAfter;

  const CompactionEvent({
    required this.summary,
    required this.tokensBefore,
    required this.tokensAfter,
  });
}
