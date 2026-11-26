import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:http/http.dart' as http;

import '../../../data/models/llm_cache_config.dart';
import '../tools/agent_tool.dart';
import '../types.dart';
import 'llm_provider.dart';
import 'prompt_cache_policy.dart';
import 'prompt_tool_codec.dart';
import 'provider_http_transport.dart';
import 'tool_call_ids.dart';

/// Google Gemini Interactions API 提供商 (`/v1beta/interactions` / `/v1/interactions`)。
///
/// 原生支持 Gemini 4 Argon / Gemini 3.8 / Gemini 2.5 系列的：
/// - `input` Step 序列 (`user_input` / `thought` / `model_output` / `function_call` / `function_result`)
/// - `generation_config` (`thinking_level` / `thinking_summaries` / `tool_choice`)
/// - `thought_signature` 跨轮次无损回传 (签名仅存于 thought 步的 signature 字段，
///   function_call 步携带 thought_signature 会被 400 拒绝)
/// - SSE 流式事件 (`step.start` / `step.delta` / `step.stop` / `interaction.completed`) 与非流式 JSON 兜底
class GoogleInteractionsProvider implements LlmProvider, LlmRequestOverhead {
  /// 官方文档指定的跳过签名校验哑值：客户端未捕获到真实签名时
  /// (旧历史/异构模型/摘要削减) 填入该值跳过当前轮的签名强制校验。
  /// 探针实证 (2026-12, gemini-4-hydrogen)：thought 步携带该值可通过校验。
  static const String _kSkipThoughtSignatureValidator =
      'skip_thought_signature_validator';

  final String apiKey;
  final String baseUrl;
  @override
  final String modelId;

  /// 是否启用深度思考 (Reasoning / Thinking)
  final bool reasoning;

  /// 思考强度等级 (low / medium / high)
  final String thinkingEffort;

  /// 是否将工具调用编码为提示词文本
  final bool promptToolUse;

  /// 关闭后请求非流式 Interaction，并解析完整 JSON。
  final bool streaming;

  final LlmCacheConfig cacheConfig;
  final http.Client _client;
  final bool _ownsClient;
  final Duration requestStartupTimeout;
  final Duration streamIdleTimeout;

  GoogleInteractionsProvider({
    required this.apiKey,
    this.baseUrl =
        'https://generativelanguage.googleapis.com/v1beta/interactions',
    this.modelId = 'gemini-4-argon',
    this.reasoning = true,
    this.thinkingEffort = 'medium',
    this.promptToolUse = false,
    this.streaming = true,
    this.cacheConfig = const LlmCacheConfig(),
    this.requestStartupTimeout = ProviderHttpTransport.requestStartupTimeout,
    this.streamIdleTimeout = ProviderHttpTransport.streamIdleTimeout,
    http.Client? client,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null;

  @override
  void close() {
    if (_ownsClient) _client.close();
  }

  @override
  String get requestProtocolPrompt =>
      promptToolUse ? PromptToolCodec.instructions : '';

  /// 规范化发送给 Google Interactions API 的模型 ID (剥离前导 `models/`)
  static String normalizeModelId(String rawModelId) {
    final trimmed = rawModelId.trim();
    if (trimmed.startsWith('models/')) {
      return trimmed.substring('models/'.length);
    }
    return trimmed;
  }

  /// 解析最终 `/interactions` 端点地址
  static String resolveEndpointUrl(String rawBaseUrl) {
    var endpoint = rawBaseUrl.trim();
    while (endpoint.endsWith('/')) {
      endpoint = endpoint.substring(0, endpoint.length - 1);
    }
    if (endpoint.endsWith('/openai/interactions')) {
      endpoint =
          '${endpoint.substring(0, endpoint.length - '/openai/interactions'.length)}/interactions';
    } else if (endpoint.endsWith('/openai')) {
      endpoint = endpoint.substring(0, endpoint.length - '/openai'.length);
    }
    if (endpoint.endsWith('/interactions')) {
      return endpoint;
    }
    final uri = Uri.tryParse(endpoint);
    if (uri != null &&
        uri.host == 'generativelanguage.googleapis.com' &&
        (uri.path.isEmpty || uri.path == '/')) {
      return '$endpoint/v1beta/interactions';
    }
    return '$endpoint/interactions';
  }

  /// 将本应用六档思考强度收敛为 Google Interactions API 支持的等级
  static String resolveThinkingLevel(
    String rawEffort, {
    required String modelId,
    required bool reasoning,
  }) {
    final lowerModel = normalizeModelId(modelId).toLowerCase();
    final supportsMinimal =
        lowerModel.contains('flash') &&
        !lowerModel.contains('gemini-3.8-flash');
    if (!reasoning) {
      return supportsMinimal ? 'minimal' : 'low';
    }
    return switch (rawEffort) {
      'none' || 'off' || 'minimal' => supportsMinimal ? 'minimal' : 'low',
      'low' => 'low',
      'medium' => 'medium',
      'high' || 'xhigh' || 'max' => 'high',
      _ => 'medium',
    };
  }

  @override
  Stream<HarnessEvent> streamChat({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    double temperature = 0.7,
    String? promptCacheKey,
  }) async* {
    if (apiKey.trim().isEmpty) {
      yield const ErrorEvent(
        '未配置 LLM API Key，请先在右上角设置中填写。',
        code: HarnessErrorCode.apiKeyMissing,
      );
      return;
    }

    final endpoint = resolveEndpointUrl(baseUrl);
    final uri = Uri.parse(endpoint);
    final isOfficialGoogle = uri.host == 'generativelanguage.googleapis.com';

    final normalizedMessages = normalizeToolCallIds(messages);
    final requestBody = buildRequestBody(
      messages: normalizedMessages,
      tools: tools,
      modelId: modelId,
      reasoning: reasoning,
      thinkingEffort: thinkingEffort,
      promptToolUse: promptToolUse,
      temperature: temperature,
      stream: streaming,
    );

    final cachePolicy = PromptCachePolicy(
      config: cacheConfig,
      endpoint: uri,
      model: modelId,
    );

    final abortTrigger = Completer<void>();
    final request = http.AbortableRequest(
      'POST',
      uri,
      abortTrigger: abortTrigger.future,
    );
    request.headers['Content-Type'] = 'application/json';
    request.headers['Accept'] = streaming
        ? 'text/event-stream'
        : 'application/json';
    final trimmedKey = apiKey.trim();
    request.headers['x-goog-api-key'] = trimmedKey;
    if (!isOfficialGoogle) {
      request.headers['Authorization'] = 'Bearer $trimmedKey';
      request.headers.addAll(cachePolicy.headers(promptCacheKey));
    }
    request.body = jsonEncode(requestBody);

    try {
      final response = await ProviderHttpTransport.sendAbortable(
        client: _client,
        request: request,
        abortTrigger: abortTrigger,
        timeout: requestStartupTimeout,
      );

      if (response.statusCode != 200) {
        final errorBody = await ProviderHttpTransport.readResponseText(
          response,
          timeout: requestStartupTimeout,
          abortTrigger: abortTrigger,
          timeoutMessage: '读取错误响应超时',
        );
        final status = response.statusCode;
        final isTransient =
            status == 408 || status == 429 || (status >= 500 && status <= 599);
        yield ErrorEvent(
          'LLM API 响应错误 (HTTP $status): ${_extractErrorMessage(errorBody)}',
          transient: isTransient,
        );
        return;
      }

      yield* _parseStreamOrJsonResponse(
        response,
        normalizedMessages: normalizedMessages,
        tools: tools,
        abortTrigger: abortTrigger,
      );
    } on TimeoutException catch (e) {
      yield ErrorEvent('网络请求异常: $e', transient: true);
    } catch (e) {
      yield ErrorEvent('网络请求异常: $e', transient: true);
    }
  }

  /// 构建 Google Interactions API 请求体 (供单测直接校验与复用)
  static Map<String, dynamic> buildRequestBody({
    required List<AgentMessage> messages,
    required List<AgentTool> tools,
    required String modelId,
    required bool reasoning,
    required String thinkingEffort,
    required bool promptToolUse,
    double? temperature,
    bool stream = true,
  }) {
    final normalizedMessages = normalizeToolCallIds(messages);

    final systemSegments = <String>[];
    final inputSteps = <Map<String, dynamic>>[];
    final toolNameByCallId = <String, String>{};

    if (promptToolUse) {
      final serialized = PromptToolCodec.serialize(normalizedMessages, tools);
      for (final item in serialized) {
        final role = item['role'] as String? ?? '';
        final content = item['content'];
        if (role == 'system') {
          if (content is String && content.trim().isNotEmpty) {
            systemSegments.add(content);
          }
        } else if (role == 'assistant') {
          final text = content is String ? content : '';
          if (text.isNotEmpty) {
            inputSteps.add({
              'type': 'model_output',
              'content': [
                {'type': 'text', 'text': text},
              ],
            });
          }
        } else if (role == 'user') {
          final parts = <Map<String, dynamic>>[];
          if (content is String) {
            parts.add({'type': 'text', 'text': content});
          } else if (content is List) {
            for (final block in content) {
              if (block is! Map) continue;
              if (block['type'] == 'text') {
                parts.add({'type': 'text', 'text': block['text'] ?? ''});
              } else if (block['type'] == 'image_url') {
                final imageUrl = block['image_url'];
                final url = imageUrl is Map ? imageUrl['url'] as String? : null;
                final parsed = _parseDataUrl(url);
                if (parsed != null) {
                  parts.add({
                    'type': 'image',
                    'data': parsed.base64,
                    'mime_type': parsed.mimeType,
                  });
                }
              }
            }
          }
          if (parts.isNotEmpty) {
            inputSteps.add({'type': 'user_input', 'content': parts});
          }
        }
      }
    } else {
      final pendingCallIds = <String>[];
      final pendingToolImageParts = <Map<String, dynamic>>[];

      void flushToolImages() {
        if (pendingToolImageParts.isEmpty) return;
        inputSteps.add({
          'type': 'user_input',
          'content': [
            {'type': 'text', 'text': '以下是前面工具结果附带的图片，请直接查看。'},
            ...pendingToolImageParts,
          ],
        });
        pendingToolImageParts.clear();
      }

      for (final msg in normalizedMessages) {
        if (msg.role != AgentRole.tool) {
          flushToolImages();
        }
        switch (msg.role) {
          case AgentRole.system:
            if (msg.content.trim().isNotEmpty) {
              systemSegments.add(msg.content);
            }

          case AgentRole.user:
            final contentParts = <Map<String, dynamic>>[
              if (msg.content.isNotEmpty || msg.images.isEmpty)
                {'type': 'text', 'text': msg.content},
              for (final img in msg.images)
                if (img.base64.isNotEmpty)
                  {
                    'type': 'image',
                    'data': img.base64,
                    'mime_type': img.mimeType,
                  },
            ];
            if (contentParts.isEmpty) {
              contentParts.add({'type': 'text', 'text': ''});
            }
            inputSteps.add({'type': 'user_input', 'content': contentParts});

          case AgentRole.assistant:
            final signature = _resolveAssistantThoughtSignature(msg);
            final hasToolCalls = msg.toolCalls?.isNotEmpty ?? false;
            // Interactions API 无状态模式契约 (探针实证 2026-12):
            // 签名只能放在 thought 步的 signature 字段里;
            // function_call 步携带 thought_signature 会被 400 拒绝
            // (Unknown parameter 'thought_signature' at 'input[N]')。
            // 含函数调用的回复必须有带签名的 thought 步;
            // 未捕获到真实签名时回传官方 dummy 值跳过校验。
            final effectiveSignature =
                (signature != null && signature.isNotEmpty)
                ? signature
                : (hasToolCalls ? _kSkipThoughtSignatureValidator : null);
            if (msg.thoughts.isNotEmpty ||
                (effectiveSignature != null && effectiveSignature.isNotEmpty)) {
              inputSteps.add({
                'type': 'thought',
                'signature': ?effectiveSignature,
                if (msg.thoughts.isNotEmpty)
                  'summary': [
                    {'type': 'text', 'text': msg.thoughts},
                  ],
              });
            }

            if (msg.content.isNotEmpty) {
              inputSteps.add({
                'type': 'model_output',
                'content': [
                  {'type': 'text', 'text': msg.content},
                ],
              });
            }
            if (hasToolCalls) {
              final calls = msg.toolCalls!;
              for (final tc in calls) {
                toolNameByCallId[tc.id] = tc.name;
                pendingCallIds.add(tc.id);
                inputSteps.add({
                  'type': 'function_call',
                  'id': tc.id,
                  'name': tc.name,
                  'arguments': tc.arguments,
                });
              }
            }

          case AgentRole.tool:
            var callId = msg.toolCallId?.trim() ?? '';
            if (callId.isEmpty && pendingCallIds.isNotEmpty) {
              callId = pendingCallIds.removeAt(0);
            } else if (callId.isNotEmpty) {
              pendingCallIds.remove(callId);
            }
            final resolvedName =
                (msg.toolName != null && msg.toolName!.isNotEmpty)
                ? msg.toolName!
                : (toolNameByCallId[callId] ?? 'tool');
            final hasImage =
                msg.imageBase64 != null && msg.imageBase64!.isNotEmpty;
            if (callId.isEmpty) {
              // 孤立工具结果无法配对 call_id，降级为 user_input 避免空 call_id 触发 400
              final fallbackText = '[工具 $resolvedName 结果] ${msg.content}'.trim();
              inputSteps.add({
                'type': 'user_input',
                'content': [
                  {'type': 'text', 'text': fallbackText},
                  if (hasImage)
                    {
                      'type': 'image',
                      'data': msg.imageBase64,
                      'mime_type': msg.imageMimeType,
                    },
                ],
              });
              break;
            }
            // Interactions API 规范允许 FunctionResultStep.result 为 object / string / array；
            // 统一使用 JSON 对象 ({result: ...} / {error: ...}) 映射底层 Gemini
            // FunctionResponse.response (google.protobuf.Struct)，避免传数组在非多模态
            // 后端或兼容网关上触发「Proto field is not repeating, cannot start list」400。
            final resultText = msg.content.isEmpty && hasImage
                ? '图片见随后的附件。'
                : msg.content;
            inputSteps.add({
              'type': 'function_result',
              'call_id': callId,
              'name': resolvedName,
              'result': msg.isError
                  ? <String, dynamic>{'error': resultText}
                  : <String, dynamic>{'result': resultText},
              if (msg.isError) 'is_error': true,
            });
            if (hasImage) {
              pendingToolImageParts.addAll([
                {
                  'type': 'text',
                  'text': jsonEncode({
                    'tool_name': resolvedName,
                    'tool_call_id': callId,
                  }),
                },
                {
                  'type': 'image',
                  'data': msg.imageBase64,
                  'mime_type': msg.imageMimeType,
                },
              ]);
            }
        }
      }
      flushToolImages();
    }

    final generationConfig = <String, dynamic>{
      'thinking_level': resolveThinkingLevel(
        thinkingEffort,
        modelId: modelId,
        reasoning: reasoning,
      ),
      'thinking_summaries': reasoning ? 'auto' : 'none',
      'temperature': ?temperature,
      if (tools.isNotEmpty && !promptToolUse) 'tool_choice': 'auto',
    };

    return <String, dynamic>{
      'model': normalizeModelId(modelId),
      if (systemSegments.isNotEmpty)
        'system_instruction': systemSegments.join('\n\n'),
      'input': inputSteps,
      if (tools.isNotEmpty && !promptToolUse)
        'tools': tools
            .map(
              (t) => <String, dynamic>{
                'type': 'function',
                'name': t.name,
                'description': t.description,
                'parameters': t.parameters,
              },
            )
            .toList(),
      'generation_config': generationConfig,
      'stream': stream,
    };
  }

  static ({String mimeType, String base64})? _parseDataUrl(String? url) {
    if (url == null || !url.startsWith('data:')) return null;
    final commaIdx = url.indexOf(',');
    if (commaIdx < 0) return null;
    final header = url.substring(5, commaIdx);
    final data = url.substring(commaIdx + 1);
    final semiIdx = header.indexOf(';');
    final mime = semiIdx >= 0 ? header.substring(0, semiIdx) : header;
    return (mimeType: mime.isEmpty ? 'image/png' : mime, base64: data);
  }

  static String? _resolveAssistantThoughtSignature(AgentMessage msg) {
    if (msg.thoughtSignature != null && msg.thoughtSignature!.isNotEmpty) {
      return msg.thoughtSignature;
    }
    if (msg.toolCalls != null) {
      for (final tc in msg.toolCalls!) {
        if (tc.thoughtSignature != null && tc.thoughtSignature!.isNotEmpty) {
          return tc.thoughtSignature;
        }
      }
    }
    return null;
  }

  Stream<HarnessEvent> _parseStreamOrJsonResponse(
    http.StreamedResponse response, {
    required List<AgentMessage> normalizedMessages,
    required List<AgentTool> tools,
    required Completer<void> abortTrigger,
  }) async* {
    final stepStates = <int, _InteractionStepState>{};
    final stepIndexById = <String, int>{};
    String? latestThoughtSignature;
    TokenUsage? latestUsage;
    final rawLines = <String>[];
    var sawSseData = false;
    var emittedContent = false;
    var emittedThoughts = false;
    final rawToolCalls = <ToolCall>[];
    FormatException? promptParseError;

    int resolveStepIndex(Map<String, dynamic> json, {bool allocate = false}) {
      final explicitIndex = (json['index'] as num?)?.toInt();
      final stepId =
          (json['step_id'] as String?) ??
          (_asMap(json['step'])?['id'] as String?);
      if (explicitIndex != null) {
        if (stepId != null && stepId.isNotEmpty) {
          stepIndexById[stepId] = explicitIndex;
        }
        return explicitIndex;
      }
      if (stepId != null && stepId.isNotEmpty) {
        return stepIndexById.putIfAbsent(stepId, () => stepStates.length);
      }
      return allocate ? stepStates.length : 0;
    }

    final promptParser = promptToolUse ? PromptToolStreamParser(tools) : null;

    Iterable<ContentDeltaEvent> emitContentText(String text) {
      if (text.isEmpty || promptParseError != null) return const [];
      emittedContent = true;
      if (promptParser != null) {
        try {
          return promptParser.add(text);
        } on FormatException catch (e) {
          promptParseError = e;
          return const [];
        }
      }
      return [ContentDeltaEvent(text)];
    }

    String? currentEventType;

    try {
      final lines = response.stream
          .timeout(streamIdleTimeout)
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());

      await for (final line in lines) {
        if (!sawSseData) {
          rawLines.add(line);
        }
        final trimmed = line.trim();
        if (trimmed.isEmpty) {
          currentEventType = null;
          continue;
        }
        if (trimmed.startsWith('event:')) {
          currentEventType = trimmed.substring(6).trim();
          continue;
        }
        if (!trimmed.startsWith('data:')) continue;

        if (!sawSseData) {
          sawSseData = true;
          rawLines.clear();
        }
        final dataStr = trimmed.substring(5).trim();
        if (dataStr.isEmpty || dataStr == '[DONE]') continue;

        Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(dataStr);
          if (decoded is! Map<String, dynamic>) continue;
          json = decoded;
        } catch (_) {
          continue;
        }

        final eventType =
            (json['event_type'] as String?) ??
            (json['event'] as String?) ??
            (json['type'] as String?) ??
            currentEventType ??
            '';

        // 1. 错误事件
        if (eventType == 'error' ||
            eventType == 'interaction.failed' ||
            json['error'] is Map) {
          final interactionMap = _asMap(json['interaction']);
          final errObj = json['error'] ?? interactionMap?['error'];
          final msg = _formatErrorObject(errObj) ?? 'Interactions API 流式请求失败';
          final codeStr = errObj is Map ? '${errObj['code'] ?? ''}' : '';
          final transient =
              codeStr == '429' ||
              codeStr == '500' ||
              codeStr == '503' ||
              msg.toLowerCase().contains('overloaded') ||
              msg.toLowerCase().contains('rate limit');
          yield ErrorEvent(msg, transient: transient);
          return;
        }

        // 2. 用量统计提取
        final usageMap =
            _asMap(json['usage']) ??
            _asMap(_asMap(json['interaction'])?['usage']) ??
            _asMap(_asMap(json['metadata'])?['total_usage']);
        if (usageMap != null) {
          latestUsage = parseInteractionsUsage(usageMap);
        }

        // 3. step.start (Google 会在 step.start 的 step 中直接携带首段 summary / content / function_call)
        if (eventType == 'step.start' || eventType == 'content.start') {
          final index = resolveStepIndex(json, allocate: true);
          final stepMap = _asMap(json['step']) ?? _asMap(json['content']);
          final stepType = stepMap?['type'] as String? ?? '';
          final state = stepStates.putIfAbsent(
            index,
            () => _InteractionStepState(index: index, type: stepType),
          );
          if (stepType.isNotEmpty) state.type = stepType;

          if (stepMap != null) {
            final sig = stepMap['signature'] as String?;
            if (sig != null && sig.isNotEmpty) {
              state.signature = sig;
              latestThoughtSignature = sig;
              yield ThoughtSignatureEvent(sig);
            }

            if (state.type == 'thought') {
              final summaryText =
                  _extractBlocksText(stepMap['summary']) ??
                  _extractBlocksText(stepMap['content']) ??
                  (stepMap['text'] as String? ?? '');
              if (summaryText.isNotEmpty) {
                emittedThoughts = true;
                yield ThoughtDeltaEvent(summaryText);
              }
            } else if (state.type == 'model_output' || state.type == 'text') {
              final text =
                  _extractBlocksText(stepMap['content']) ??
                  (stepMap['text'] as String? ?? '');
              for (final evt in emitContentText(text)) {
                yield evt;
              }
            } else if (state.type == 'function_call') {
              state.absorbFunctionCallMap(stepMap);
            }
          }
          continue;
        }

        // 4. step.delta / content.delta
        if (eventType == 'step.delta' || eventType == 'content.delta') {
          final index = resolveStepIndex(json);
          final delta = _asMap(json['delta']);
          if (delta == null) continue;
          final deltaType = delta['type'] as String? ?? '';
          final state = stepStates.putIfAbsent(
            index,
            () => _InteractionStepState(index: index, type: deltaType),
          );

          switch (deltaType) {
            case 'thought_signature':
              final sig = delta['signature'] as String?;
              if (sig != null && sig.isNotEmpty) {
                state.signature = sig;
                latestThoughtSignature = sig;
                yield ThoughtSignatureEvent(sig);
              }

            case 'thought_summary' || 'thought':
              final sig = delta['signature'] as String?;
              if (sig != null && sig.isNotEmpty) {
                state.signature = sig;
                latestThoughtSignature = sig;
                yield ThoughtSignatureEvent(sig);
              }
              final thoughtText =
                  _extractThoughtDeltaText(delta) ??
                  (delta['text'] as String? ?? '');
              if (thoughtText.isNotEmpty) {
                emittedThoughts = true;
                yield ThoughtDeltaEvent(thoughtText);
              }

            case 'text':
              final text =
                  (delta['text'] as String?) ??
                  _extractBlocksText(delta['content']) ??
                  '';
              if (state.type == 'thought') {
                if (text.isNotEmpty) {
                  emittedThoughts = true;
                  yield ThoughtDeltaEvent(text);
                }
              } else {
                for (final evt in emitContentText(text)) {
                  yield evt;
                }
              }

            case 'function_call' || 'arguments_delta' || 'arguments':
              state.type = 'function_call';
              state.absorbFunctionCallDelta(delta);

            default:
              final sig = delta['signature'] as String?;
              if (sig != null && sig.isNotEmpty) {
                state.signature = sig;
                latestThoughtSignature = sig;
                yield ThoughtSignatureEvent(sig);
              }
              if (delta.containsKey('name') ||
                  delta.containsKey('arguments') ||
                  delta.containsKey('arguments_delta') ||
                  delta.containsKey('partial_arguments') ||
                  state.type == 'function_call') {
                state.type = 'function_call';
                state.absorbFunctionCallDelta(delta);
              } else if (state.type == 'thought') {
                final thoughtText = _extractThoughtDeltaText(delta);
                if (thoughtText != null && thoughtText.isNotEmpty) {
                  emittedThoughts = true;
                  yield ThoughtDeltaEvent(thoughtText);
                }
              } else {
                final text =
                    (delta['text'] as String?) ??
                    _extractBlocksText(delta['content']);
                if (text != null && text.isNotEmpty) {
                  for (final evt in emitContentText(text)) {
                    yield evt;
                  }
                }
              }
          }
          continue;
        }

        // 5. step.stop / content.stop
        if (eventType == 'step.stop' || eventType == 'content.stop') {
          final index = resolveStepIndex(json);
          final state = stepStates[index];
          if (state != null &&
              state.type == 'function_call' &&
              !state.emittedToolCall &&
              state.name.isNotEmpty) {
            state.emittedToolCall = true;
            if (!promptToolUse) {
              rawToolCalls.add(
                state.toToolCall(thoughtSignature: latestThoughtSignature),
              );
            }
          }
          continue;
        }

        // 6. interaction.completed / interaction.complete
        if (eventType == 'interaction.completed' ||
            eventType == 'interaction.complete' ||
            json['interaction'] is Map) {
          final interactionMap = _asMap(json['interaction']) ?? json;
          final uMap = _asMap(interactionMap['usage']);
          if (uMap != null) {
            latestUsage = parseInteractionsUsage(uMap);
          }
          final status = interactionMap['status']?.toString();
          final failed =
              status == 'failed' ||
              status == 'cancelled' ||
              interactionMap['error'] is Map;
          final incomplete = status == 'incomplete';
          if (failed || incomplete) {
            final reason =
                interactionMap['incomplete_reason'] ??
                interactionMap['status_reason'] ??
                _formatErrorObject(interactionMap['error']);
            final reasonText = '${reason ?? status}';
            final lowerReason = reasonText.toLowerCase();
            final transient =
                lowerReason.contains('rate') ||
                lowerReason.contains('overload') ||
                lowerReason.contains('timeout') ||
                lowerReason.contains('503') ||
                lowerReason.contains('429');
            yield ErrorEvent(
              incomplete
                  ? 'Interactions API 响应被截断或未完成: $reasonText'
                  : (_formatErrorObject(interactionMap['error']) ??
                        'Interactions API 请求失败: $reasonText'),
              transient: transient,
            );
            if (latestUsage != null) {
              yield UsageEvent(latestUsage);
            }
            return;
          }
          yield* _emitRemainingFromInteractionMap(
            interactionMap,
            stepStates: stepStates,
            emittedContent: () => emittedContent,
            emittedThoughts: () => emittedThoughts,
            rawToolCalls: rawToolCalls,
            latestThoughtSignature: latestThoughtSignature,
            onSignature: (sig) => latestThoughtSignature = sig,
            emitContentText: emitContentText,
          );
        }
      }

      // 非流式 JSON 响应兜底
      if (!sawSseData && rawLines.isNotEmpty) {
        final fullBody = rawLines.join('\n').trim();
        if (fullBody.startsWith('{')) {
          try {
            final decoded = jsonDecode(fullBody);
            if (decoded is Map<String, dynamic>) {
              if (decoded['error'] is Map) {
                yield ErrorEvent(
                  _formatErrorObject(decoded['error']) ??
                      'Interactions API 请求失败',
                );
              } else {
                final interactionMap =
                    _asMap(decoded['interaction']) ?? decoded;
                final uMap = _asMap(interactionMap['usage']);
                if (uMap != null) {
                  latestUsage = parseInteractionsUsage(uMap);
                }
                final status = interactionMap['status']?.toString();
                final failed =
                    status == 'failed' ||
                    status == 'cancelled' ||
                    interactionMap['error'] is Map;
                final incomplete = status == 'incomplete';
                if (failed || incomplete) {
                  final reason =
                      interactionMap['incomplete_reason'] ??
                      interactionMap['status_reason'] ??
                      _formatErrorObject(interactionMap['error']);
                  yield ErrorEvent(
                    incomplete
                        ? 'Interactions API 响应不完整: ${reason ?? status}'
                        : (_formatErrorObject(interactionMap['error']) ??
                              'Interactions API 请求失败: ${reason ?? status}'),
                  );
                } else {
                  yield* _emitRemainingFromInteractionMap(
                    interactionMap,
                    stepStates: stepStates,
                    emittedContent: () => emittedContent,
                    emittedThoughts: () => emittedThoughts,
                    rawToolCalls: rawToolCalls,
                    latestThoughtSignature: latestThoughtSignature,
                    onSignature: (sig) => latestThoughtSignature = sig,
                    emitContentText: emitContentText,
                  );
                }
              }
            }
          } catch (_) {}
        }
      }

      // 冲刷未收到 step.stop 但已缓冲完成的 function_call 步骤
      if (!promptToolUse) {
        final sortedIndices = stepStates.keys.toList()..sort();
        for (final idx in sortedIndices) {
          final state = stepStates[idx]!;
          if (state.type == 'function_call' &&
              !state.emittedToolCall &&
              state.name.isNotEmpty) {
            state.emittedToolCall = true;
            rawToolCalls.add(
              state.toToolCall(thoughtSignature: latestThoughtSignature),
            );
          }
        }
      }

      if (promptParser != null) {
        if (promptParseError != null) throw promptParseError!;
        for (final evt in promptParser.finish()) {
          yield evt;
        }
      }

      final completedCalls = <ToolCall>[
        ...?promptParser?.calls,
        ...rawToolCalls,
      ];
      if (completedCalls.isNotEmpty) {
        final normalized = normalizeToolCallIds([
          ...normalizedMessages,
          AgentMessage(
            id: 'pending_tool_calls',
            role: AgentRole.assistant,
            toolCalls: completedCalls,
          ),
        ]).last.toolCalls!;
        for (final call in normalized) {
          yield ToolCallEvent(call);
        }
      }
    } on FormatException catch (e) {
      yield ErrorEvent('工具调用格式错误: ${e.message}');
    } catch (e) {
      if (e is TimeoutException && !abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
      yield ErrorEvent('解析流式数据异常: $e', transient: true);
    }

    if (latestUsage != null) {
      yield UsageEvent(latestUsage);
    }
  }

  Stream<HarnessEvent> _emitRemainingFromInteractionMap(
    Map<String, dynamic> interactionMap, {
    required Map<int, _InteractionStepState> stepStates,
    required bool Function() emittedContent,
    required bool Function() emittedThoughts,
    required List<ToolCall> rawToolCalls,
    required String? latestThoughtSignature,
    required void Function(String) onSignature,
    required Iterable<ContentDeltaEvent> Function(String) emitContentText,
  }) async* {
    final outputs =
        interactionMap['steps'] ??
        interactionMap['output'] ??
        interactionMap['outputs'];
    if (outputs is! List) return;

    final allowThoughtEmit = !emittedThoughts();
    final allowContentEmit = !emittedContent();
    final allowToolEmit = rawToolCalls.isEmpty;
    var currentSignature = latestThoughtSignature;

    for (var i = 0; i < outputs.length; i++) {
      final item = _asMap(outputs[i]);
      if (item == null) continue;
      final type = item['type'] as String? ?? '';
      switch (type) {
        case 'thought':
          final sig = item['signature'] as String?;
          if (sig != null && sig.isNotEmpty && sig != currentSignature) {
            currentSignature = sig;
            onSignature(sig);
            yield ThoughtSignatureEvent(sig);
          }
          if (allowThoughtEmit) {
            final text =
                _extractBlocksText(item['summary']) ??
                _extractBlocksText(item['content']) ??
                (item['text'] as String? ?? '');
            if (text.isNotEmpty) {
              yield ThoughtDeltaEvent(text);
            }
          }

        case 'model_output' || 'text':
          if (allowContentEmit) {
            final text =
                _extractBlocksText(item['content']) ??
                (item['text'] as String? ?? '');
            if (text.isNotEmpty) {
              for (final evt in emitContentText(text)) {
                yield evt;
              }
            }
          }

        case 'function_call':
          final existing = stepStates[i];
          if ((existing == null || !existing.emittedToolCall) &&
              allowToolEmit &&
              !promptToolUse) {
            final state = _InteractionStepState(index: i, type: 'function_call')
              ..absorbFunctionCallMap(item)
              ..emittedToolCall = true;
            stepStates[i] = state;
            if (state.name.isNotEmpty) {
              rawToolCalls.add(
                state.toToolCall(thoughtSignature: currentSignature),
              );
            }
          }
      }
    }
  }

  /// 解析 Google Interactions API 的 `Usage` 对象并对齐本应用互斥 `TokenUsage` 口径
  static TokenUsage parseInteractionsUsage(Map<String, dynamic> usage) {
    int count(Object? v) => v is num && v.isFinite && v > 0 ? v.toInt() : 0;

    final rawCached = usage['total_cached_tokens'] ?? usage['cached_tokens'];
    final cacheRead = count(rawCached);
    final totalInput = count(
      usage['total_input_tokens'] ??
          usage['input_tokens'] ??
          usage['prompt_tokens'],
    );
    final toolUseInput = count(usage['total_tool_use_tokens']);
    final outputTokens = count(
      usage['total_output_tokens'] ??
          usage['output_tokens'] ??
          usage['completion_tokens'],
    );
    final thoughtTokens = count(
      usage['total_thought_tokens'] ?? usage['thought_tokens'],
    );

    final uncachedInput = math.max(0, totalInput + toolUseInput - cacheRead);
    return TokenUsage(
      input: uncachedInput,
      output: outputTokens + thoughtTokens,
      cacheRead: cacheRead,
      cacheReadReported:
          rawCached is num && rawCached.isFinite && rawCached >= 0,
    );
  }

  static Map<String, dynamic>? _asMap(Object? value) =>
      value is Map<String, dynamic> ? value : null;

  static String? _extractBlocksText(Object? blocks) {
    if (blocks is String) return blocks;
    if (blocks is! List) return null;
    final buffer = StringBuffer();
    for (final item in blocks) {
      if (item is Map<String, dynamic>) {
        final text = item['text'] as String?;
        if (text != null && text.isNotEmpty) {
          buffer.write(text);
        }
      }
    }
    return buffer.isEmpty ? null : buffer.toString();
  }

  static String? _extractThoughtDeltaText(Map<String, dynamic> delta) {
    final direct = delta['text'] as String?;
    if (direct != null && direct.isNotEmpty) return direct;
    final content = delta['content'];
    if (content is Map<String, dynamic>) {
      final text = content['text'] as String?;
      if (text != null && text.isNotEmpty) return text;
    }
    return _extractBlocksText(content) ?? _extractBlocksText(delta['summary']);
  }

  static String _extractErrorMessage(String rawBody) {
    final trimmed = rawBody.trim();
    if (trimmed.isEmpty) return '空错误响应';
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is Map<String, dynamic>) {
        final msg =
            _formatErrorObject(decoded['error']) ?? _formatErrorObject(decoded);
        if (msg != null && msg.isNotEmpty) return msg;
      }
    } catch (_) {}
    return trimmed;
  }

  static String? _formatErrorObject(Object? errObj) {
    if (errObj is String && errObj.isNotEmpty) return errObj;
    if (errObj is Map) {
      final message = errObj['message'] as String?;
      final status = errObj['status'] as String?;
      if (message != null && message.isNotEmpty) {
        return status != null && status.isNotEmpty
            ? '[$status] $message'
            : message;
      }
    }
    return null;
  }
}

class _InteractionStepState {
  final int index;
  String type;
  String? signature;
  String? callThoughtSignature;
  String id = '';
  String name = '';
  Map<String, dynamic>? parsedArguments;
  final StringBuffer argumentsBuffer = StringBuffer();
  bool emittedToolCall = false;

  _InteractionStepState({required this.index, required this.type});

  void absorbFunctionCallMap(Map<String, dynamic> map) {
    final rawId = (map['id'] as String?) ?? (map['call_id'] as String?);
    if (rawId != null && rawId.isNotEmpty) id = rawId;
    final rawName = map['name'] as String?;
    if (rawName != null && rawName.isNotEmpty) name = rawName;
    final rawSig = map['thought_signature'] ?? map['thoughtSignature'];
    if (rawSig is String && rawSig.isNotEmpty) {
      callThoughtSignature = rawSig;
    }
    final args = map['arguments'];
    if (args is Map<String, dynamic>) {
      parsedArguments = Map<String, dynamic>.from(args);
    } else if (args is String && args.isNotEmpty) {
      argumentsBuffer.write(args);
    }
  }

  void absorbFunctionCallDelta(Map<String, dynamic> delta) {
    absorbFunctionCallMap(delta);
    final argsDelta =
        (delta['arguments_delta'] as String?) ??
        (delta['partial_arguments'] as String?);
    if (argsDelta != null && argsDelta.isNotEmpty) {
      argumentsBuffer.write(argsDelta);
    }
  }

  ToolCall toToolCall({String? thoughtSignature}) {
    Map<String, dynamic> args = parsedArguments ?? <String, dynamic>{};
    if (args.isEmpty && argumentsBuffer.isNotEmpty) {
      final raw = argumentsBuffer.toString().trim();
      if (raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is! Map<String, dynamic>) {
          throw FormatException('工具 "$name" 参数不是 JSON 对象');
        }
        args = decoded;
      }
    }
    final effectiveId = id.isNotEmpty ? id : 'call_${index + 1}';
    return ToolCall(
      id: effectiveId,
      name: name,
      arguments: args,
      thoughtSignature: callThoughtSignature ?? signature ?? thoughtSignature,
    );
  }
}
