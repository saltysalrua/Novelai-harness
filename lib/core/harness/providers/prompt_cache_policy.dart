import '../../../data/models/llm_cache_config.dart';

/// 对齐 reference/pi 的 OpenAI key / Anthropic 三断点 / affinity 策略。
/// 自动模式只识别可信域名；中转站必须显式选兼容格式，不按模型名猜协议。
class PromptCachePolicy {
  final LlmCacheConfig config;
  final Uri endpoint;
  final String model;

  const PromptCachePolicy({
    required this.config,
    required this.endpoint,
    required this.model,
  });

  LlmCacheMode get mode {
    if (config.mode != LlmCacheMode.auto) return config.mode;
    if (endpoint.host == 'api.openai.com') return LlmCacheMode.openai;
    if (endpoint.host == 'api.anthropic.com') return LlmCacheMode.anthropic;
    if (endpoint.host == 'openrouter.ai' &&
        model.trim().startsWith('anthropic/')) {
      return LlmCacheMode.anthropic;
    }
    return LlmCacheMode.auto;
  }

  /// 只修改本次请求新建的 JSON，不修改会话消息或工具注册表。
  void apply(Map<String, dynamic> body, String? sessionId) {
    if (mode == LlmCacheMode.off) return;
    if (mode == LlmCacheMode.openai) {
      final key = clampKey(sessionId);
      if (key != null && key.isNotEmpty) body['prompt_cache_key'] = key;
      if (config.retention == LlmCacheRetention.long) {
        body['prompt_cache_retention'] = '24h';
      }
    } else if (mode == LlmCacheMode.anthropic) {
      final marker = <String, dynamic>{
        'type': 'ephemeral',
        if (config.retention == LlmCacheRetention.long) 'ttl': '1h',
      };
      // 原生 Anthropic `/v1/messages` 将系统提示词放在顶层 `body['system']`。
      final topSystem = body['system'];
      if (topSystem is String && topSystem.isNotEmpty) {
        body['system'] = [
          {'type': 'text', 'text': topSystem, 'cache_control': marker},
        ];
      } else if (topSystem is List && topSystem.isNotEmpty) {
        final systemBlocks = List<dynamic>.from(topSystem);
        for (var i = systemBlocks.length - 1; i >= 0; i--) {
          final block = systemBlocks[i];
          if (block is Map && block['type'] == 'text') {
            systemBlocks[i] = <String, dynamic>{
              ...Map<String, dynamic>.from(block),
              'cache_control': marker,
            };
            body['system'] = systemBlocks;
            break;
          }
        }
      }
      final messages = (body['messages'] as List)
          .map((message) => Map<String, dynamic>.from(message as Map))
          .toList();
      body['messages'] = messages;
      for (final message in messages) {
        if (message['role'] == 'system' || message['role'] == 'developer') {
          _markText(message, marker);
          break;
        }
      }
      final tools = body['tools'];
      if (tools is List && tools.isNotEmpty) {
        body['tools'] = [
          ...tools.take(tools.length - 1),
          <String, dynamic>{
            ...Map<String, dynamic>.from(tools.last as Map),
            'cache_control': marker,
          },
        ];
      }
      for (final message in messages.reversed) {
        if (const ['user', 'assistant', 'tool'].contains(message['role']) &&
            _markText(message, marker)) {
          break;
        }
      }
    }
  }

  Map<String, String> headers(String? sessionId) {
    if (mode == LlmCacheMode.off || sessionId == null || sessionId.isEmpty) {
      return const {};
    }
    return switch (config.affinity) {
      LlmCacheAffinity.off => const {},
      LlmCacheAffinity.openai => {
        'session_id': sessionId,
        'x-client-request-id': sessionId,
        'x-session-affinity': sessionId,
      },
      LlmCacheAffinity.openrouter => {'x-session-id': sessionId},
    };
  }

  static String? clampKey(String? key) {
    if (key == null) return null;
    return String.fromCharCodes(key.runes.take(64));
  }

  static bool _markText(
    Map<String, dynamic> message,
    Map<String, dynamic> marker,
  ) {
    final content = message['content'];
    if (content is String && content.isNotEmpty) {
      message['content'] = [
        {'type': 'text', 'text': content, 'cache_control': marker},
      ];
      return true;
    }
    if (content is List) {
      for (var i = content.length - 1; i >= 0; i--) {
        final part = content[i];
        if (part is Map &&
            (part['type'] == 'text' || part['type'] == 'tool_result')) {
          message['content'] = [
            ...content.take(i),
            <String, dynamic>{
              ...Map<String, dynamic>.from(part),
              'cache_control': marker,
            },
            ...content.skip(i + 1),
          ];
          return true;
        }
      }
    }
    return false;
  }
}
