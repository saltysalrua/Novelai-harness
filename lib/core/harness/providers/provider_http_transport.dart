import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../types.dart';
import 'endpoint_capability_cache.dart';
import 'prompt_tool_codec.dart';
import 'tool_call_ids.dart';

/// 多协议 HTTP 传输、缓存降级与 SSE/JSON 共用执行辅助工具。
class ProviderHttpTransport {
  /// 首包响应头及非流式整包等待上限（5 分钟）：
  /// 兼容假流式网关、非流式请求以及深度思考模型的长首包等待窗口。
  static const Duration requestStartupTimeout = Duration(seconds: 300);

  /// SSE 流式空闲超时上限（3 分钟）：
  /// 兼容先回 200 响应头但深度思考阶段较久无数据帧的网关。
  static const Duration streamIdleTimeout = Duration(seconds: 180);

  /// 判定 HTTP 状态码是否为瞬态可重试错误 (请求超时 / 频控 / 服务端临时故障)
  static bool isTransientStatus(int code) =>
      code == 408 || code == 429 || (code >= 500 && code <= 599);

  /// 规范化即将发出的工具调用 ID，防止与历史消息 ID 碰撞。
  static List<ToolCall> normalizePendingToolCalls(
    List<AgentMessage> messages,
    List<ToolCall> pendingCalls,
  ) {
    return normalizeToolCallIds([
      ...messages,
      AgentMessage(
        id: 'pending_tool_calls',
        role: AgentRole.assistant,
        toolCalls: pendingCalls,
      ),
    ]).last.toolCalls!;
  }

  /// 发送可中止的 HTTP 请求；等待响应头超时时立即触发 [abortTrigger] 断开底层连接，
  /// 防止客户端超时放弃后上游继续在后台跑完生成并重复计费。
  static Future<http.StreamedResponse> sendAbortable({
    required http.Client client,
    required http.AbortableRequest request,
    required Completer<void> abortTrigger,
    Duration timeout = requestStartupTimeout,
  }) async {
    final sendFuture = client.send(request);
    try {
      return await sendFuture.timeout(
        timeout,
        onTimeout: () {
          if (!abortTrigger.isCompleted) {
            abortTrigger.complete();
          }
          throw TimeoutException(
            '等待模型响应头超时 (${timeout.inSeconds}s)',
            timeout,
          );
        },
      );
    } on TimeoutException {
      // 忽略底层连接被中止后晚到抛出的 RequestAbortedException，避免未捕获异步异常。
      unawaited(sendFuture.then<void>((_) {}, onError: (Object _) {}));
      rethrow;
    }
  }

  /// 读取完整响应体文本；超时时触发 [abortTrigger]（若提供）断开底层连接。
  static Future<String> readResponseText(
    http.StreamedResponse response, {
    Duration timeout = requestStartupTimeout,
    Completer<void>? abortTrigger,
    String timeoutMessage = '读取模型完整响应超时',
  }) async {
    final bodyFuture = response.stream.bytesToString();
    try {
      return await bodyFuture.timeout(
        timeout,
        onTimeout: () {
          if (abortTrigger != null && !abortTrigger.isCompleted) {
            abortTrigger.complete();
          }
          throw TimeoutException(
            '$timeoutMessage (${timeout.inSeconds}s)',
            timeout,
          );
        },
      );
    } on TimeoutException {
      unawaited(bodyFuture.then<void>((_) {}, onError: (Object _) {}));
      rethrow;
    }
  }

  /// 发送 JSON POST 请求 (按端点特征附带鉴权与协议头)。
  static Future<http.StreamedResponse> sendJsonPost({
    required http.Client client,
    required String endpoint,
    required String apiKey,
    required Map<String, dynamic> requestBody,
    required Map<String, String> cacheHeaders,
    Duration timeout = requestStartupTimeout,
    Completer<void>? abortTrigger,
  }) {
    final effectiveAbort = abortTrigger ?? Completer<void>();
    final request = http.AbortableRequest(
      'POST',
      Uri.parse(endpoint),
      abortTrigger: effectiveAbort.future,
    );
    request.headers['Content-Type'] = 'application/json';
    request.headers.addAll(cacheHeaders);
    final trimmedKey = apiKey.trim();
    if (endpoint.endsWith('/messages')) {
      request.headers['x-api-key'] = trimmedKey;
      request.headers['anthropic-version'] = '2023-06-01';
    }
    if (trimmedKey.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $trimmedKey';
    }
    request.body = jsonEncode(requestBody);
    return sendAbortable(
      client: client,
      request: request,
      abortTrigger: effectiveAbort,
      timeout: timeout,
    );
  }

  /// HTTP 400 降级重试：错误体明确拒绝 prompt_cache_key / prompt_cache_retention
  /// 或 include(reasoning.encrypted_content) 时移除该字段、记入能力缓存并重发。
  static Future<(http.StreamedResponse, String?)> drainRejectedCacheFields({
    required http.StreamedResponse initialResponse,
    required http.Client client,
    required String apiKey,
    required String model,
    required String endpoint,
    required Map<String, dynamic> requestBody,
    required Map<String, String> cacheHeaders,
    required EndpointCapabilityCache capabilityCache,
    Duration timeout = requestStartupTimeout,
    Completer<void>? abortTrigger,
  }) async {
    var streamedResponse = initialResponse;
    while (streamedResponse.statusCode == 400) {
      final errBody = await readResponseText(
        streamedResponse,
        timeout: timeout,
        abortTrigger: abortTrigger,
        timeoutMessage: '读取错误响应超时',
      );
      final lower = errBody.toLowerCase();
      String? rejectedField;
      if (RegExp(
        r'unsupported|not supported|unknown|unrecognized|not permitted|not allowed|extra inputs',
      ).hasMatch(lower)) {
        for (final field in const [
          'prompt_cache_key',
          'prompt_cache_retention',
        ]) {
          if (requestBody.containsKey(field) && lower.contains(field)) {
            rejectedField = field;
            break;
          }
        }
      }
      if (rejectedField == null) {
        final include = requestBody['include'];
        if (include is List &&
            include.contains('reasoning.encrypted_content') &&
            (lower.contains('include') ||
                lower.contains('encrypted_content'))) {
          capabilityCache.markEncryptedReasoningUnsupported(endpoint, model);
          requestBody.remove('include');
          streamedResponse = await sendJsonPost(
            client: client,
            endpoint: endpoint,
            apiKey: apiKey,
            requestBody: requestBody,
            cacheHeaders: cacheHeaders,
            timeout: timeout,
            abortTrigger: abortTrigger,
          );
          continue;
        }
        return (streamedResponse, errBody);
      }
      capabilityCache.markCacheFieldUnsupported(endpoint, model, rejectedField);
      requestBody.remove(rejectedField);
      streamedResponse = await sendJsonPost(
        client: client,
        endpoint: endpoint,
        apiKey: apiKey,
        requestBody: requestBody,
        cacheHeaders: cacheHeaders,
        timeout: timeout,
        abortTrigger: abortTrigger,
      );
    }
    return (streamedResponse, null);
  }

  /// 读取非 200 HTTP 响应体并封装为 [ErrorEvent]。
  static Future<ErrorEvent> readHttpErrorEvent(
    http.StreamedResponse response, {
    Duration timeout = requestStartupTimeout,
    Completer<void>? abortTrigger,
  }) async {
    try {
      final errBody = await readResponseText(
        response,
        timeout: timeout,
        abortTrigger: abortTrigger,
        timeoutMessage: '读取错误响应超时',
      );
      return ErrorEvent(
        'LLM API 响应错误 (HTTP ${response.statusCode}): $errBody',
        transient: isTransientStatus(response.statusCode),
      );
    } catch (e) {
      return ErrorEvent('网络请求异常: $e', transient: true);
    }
  }

  /// 执行标准 event/data SSE 或非流式 JSON 回退协议流（Anthropic Messages 与
  /// OpenAI Responses 共用帧状态机与提示词工具解析收尾）。
  static Stream<HarnessEvent> executeSseOrJsonProtocolStream({
    required http.StreamedResponse streamedResponse,
    required List<AgentMessage> messages,
    required PromptToolStreamParser? promptParser,
    required String completionMarker,
    required String prematureEndMessage,
    Duration streamIdleTimeout = ProviderHttpTransport.streamIdleTimeout,
    Completer<void>? abortTrigger,
    required List<HarnessEvent> Function(
      Map<String, dynamic> json,
      String? eventType,
    )
    onSseJson,
    required List<HarnessEvent> Function() onSseFinish,
    required ({
      String? error,
      bool transientError,
      List<ReasoningRecord> reasoningRecords,
      String reasoning,
      List<String> thoughtSignatures,
      String text,
      List<ToolCall> toolCalls,
      TokenUsage? usage,
    })
    Function(Map<String, dynamic> json)
    parseNonSseJson,
  }) async* {
    FormatException? promptParseError;
    var streamCompleted = false;
    var failed = false;
    final calls = <ToolCall>[];
    TokenUsage? latestUsage;

    List<ContentDeltaEvent> contentEvents(String text) {
      if (text.isEmpty || promptParseError != null) return const [];
      try {
        return promptParser?.add(text) ?? [ContentDeltaEvent(text)];
      } on FormatException catch (error) {
        promptParseError = error;
        return const [];
      }
    }

    Iterable<HarnessEvent> absorb(List<HarnessEvent> events) sync* {
      for (final event in events) {
        if (event is ContentDeltaEvent) {
          yield* contentEvents(event.delta);
        } else if (event is ToolCallEvent) {
          calls.add(event.toolCall);
        } else if (event is ErrorEvent) {
          failed = true;
          yield event;
        } else if (event is UsageEvent) {
          latestUsage = event.usage;
        } else {
          yield event;
        }
      }
    }

    final prelude = StringBuffer();
    var sawSse = false;
    String? pendingEvent;

    try {
      final lineStream = streamedResponse.stream
          .timeout(streamIdleTimeout)
          .transform(const Utf8Decoder(allowMalformed: true))
          .transform(const LineSplitter());

      await for (final line in lineStream) {
        final trimmed = line.trim();
        if (!sawSse) {
          if (trimmed.startsWith('data:') || trimmed.startsWith('event:')) {
            sawSse = true;
          } else {
            prelude.writeln(line);
            continue;
          }
        }
        if (trimmed.isEmpty) {
          pendingEvent = null;
          continue;
        }
        if (trimmed.startsWith(':')) continue;
        if (trimmed.startsWith('event:')) {
          pendingEvent = trimmed.substring(6).trim();
          continue;
        }
        if (!trimmed.startsWith('data:')) continue;

        final data = trimmed.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') {
          streamCompleted = true;
          pendingEvent = null;
          break;
        }

        Map<String, dynamic> json;
        try {
          final decoded = jsonDecode(data);
          if (decoded is! Map) {
            pendingEvent = null;
            continue;
          }
          json = Map<String, dynamic>.from(decoded);
        } catch (_) {
          pendingEvent = null;
          continue;
        }

        if (json['type'] == completionMarker ||
            pendingEvent == completionMarker) {
          streamCompleted = true;
        }
        for (final evt in absorb(onSseJson(json, pendingEvent))) {
          yield evt;
        }
        pendingEvent = null;
      }
    } catch (e) {
      if (e is TimeoutException &&
          abortTrigger != null &&
          !abortTrigger.isCompleted) {
        abortTrigger.complete();
      }
      failed = true;
      yield ErrorEvent('解析流式数据异常: $e', transient: true);
    }

    if (!sawSse) {
      final raw = prelude.toString().trim();
      if (raw.isEmpty) return;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) {
          yield const ErrorEvent('解析流式数据异常: 非 JSON 响应', transient: true);
          return;
        }
        final completion = parseNonSseJson(Map<String, dynamic>.from(decoded));
        if (completion.error != null) {
          failed = true;
          yield ErrorEvent(
            completion.error!,
            transient: completion.transientError,
          );
        } else {
          if (completion.reasoningRecords.isNotEmpty) {
            yield ReasoningSnapshotEvent(completion.reasoningRecords);
          }
          if (completion.reasoning.isNotEmpty) {
            yield ThoughtDeltaEvent(completion.reasoning);
          }
          for (final sig in completion.thoughtSignatures) {
            yield ThoughtSignatureEvent(sig);
          }
          for (final evt in contentEvents(completion.text)) {
            yield evt;
          }
          calls.addAll(completion.toolCalls);
          streamCompleted = true;
        }
        latestUsage = completion.usage;
      } catch (e) {
        yield ErrorEvent('解析流式数据异常: $e', transient: true);
        return;
      }
    } else {
      for (final evt in absorb(onSseFinish())) {
        yield evt;
      }
    }

    if (promptParser != null && !failed) {
      final parseError = promptParseError;
      if (parseError != null) {
        failed = true;
        yield ErrorEvent('工具调用格式错误: ${parseError.message}');
      } else if (!streamCompleted) {
        failed = true;
        yield const ErrorEvent('提示词工具调用响应流提前结束，未执行。');
      } else {
        try {
          for (final evt in promptParser.finish()) {
            yield evt;
          }
        } on FormatException catch (e) {
          failed = true;
          yield ErrorEvent('工具调用格式错误: ${e.message}');
        }
      }
    } else if (promptParser == null && !failed && !streamCompleted) {
      failed = true;
      yield ErrorEvent(prematureEndMessage, transient: true);
    }

    final promptCalls =
        !failed && promptParser != null && promptParseError == null
        ? promptParser.calls
        : const <ToolCall>[];
    if (!failed && (calls.isNotEmpty || promptCalls.isNotEmpty)) {
      for (final call in normalizePendingToolCalls(messages, [
        ...calls,
        ...promptCalls,
      ])) {
        yield ToolCallEvent(call);
      }
    }

    final usage = latestUsage;
    if (usage != null && usage.total > 0) {
      yield UsageEvent(usage);
    }
  }
}
