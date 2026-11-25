import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import 'package:msgpack_dart/msgpack_dart.dart' as msgpack;
import '../models/novelai_models.dart';
import 'isolated_compute.dart';
import 'precise_reference_image_service.dart';
import 'vibe_transfer_service.dart';

/// 异步并发互斥锁 (保证严格单并发，防止触发官方 429)
class AsyncLock {
  Completer<void>? _completer;

  Future<void> acquire() async {
    while (_completer != null) {
      await _completer!.future;
    }
    _completer = Completer<void>();
  }

  void release() {
    final c = _completer;
    _completer = null;
    c?.complete();
  }

  Future<T> runExclusive<T>(Future<T> Function() callback) async {
    await acquire();
    try {
      return await callback();
    } finally {
      release();
    }
  }
}

/// NovelAI 官方 API 服务
class NovelAiService {
  static const String _host = 'https://image.novelai.net';
  static const String _generateEndpoint = '$_host/ai/generate-image';
  static const String _generateStreamEndpoint =
      '$_host/ai/generate-image-stream';
  static const String _encodeVibeEndpoint = '$_host/ai/encode-vibe';
  static const String _upscaleEndpoint = '$_host/ai/upscale';

  /// V5 换代后 /ai/upscale 使用的固定模型与去模糊参数 (服务端不再接受 scale)
  static const String _upscaleModel = 'nai-diffusion-5-curated';
  static const int _upscaleDeclaredBlurSigma = 0;
  static const String _tagsEndpoint = '$_host/ai/generate-image/suggest-tags';
  static const String _userDataEndpoint = '$_host/user/data';

  static const Duration defaultRequestTimeout = Duration(seconds: 120);
  static const Duration defaultStreamIdleTimeout = Duration(seconds: 90);
  static const Duration defaultMetaTimeout = Duration(seconds: 25);

  static const String _correlationChars =
      'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  static final Random _random = Random.secure();

  final AsyncLock _lock = AsyncLock();
  final http.Client _httpClient;
  final bool _ownsClient;
  final Duration requestTimeout;
  final Duration streamIdleTimeout;
  final Duration metaTimeout;
  final Duration retryDelay;

  NovelAiService({
    http.Client? httpClient,
    this.requestTimeout = defaultRequestTimeout,
    this.streamIdleTimeout = defaultStreamIdleTimeout,
    this.metaTimeout = defaultMetaTimeout,
    this.retryDelay = const Duration(milliseconds: 2500),
  }) : _httpClient = httpClient ?? http.Client(),
       _ownsClient = httpClient == null;

  /// 关闭内部自建的 HTTP 客户端；若由外部注入客户端则交由调用方管理。
  void close() {
    if (_ownsClient) {
      _httpClient.close();
    }
  }

  /// 实时流式生成插画 (输出中间去噪步数预览与最终成图)
  Stream<NaiStreamProgress> generateImageStream({
    required String apiKey,
    required NaiGenerationParams params,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key，请在设置中输入有效的 Token。');
    }

    // 官方流式端点仅支持 V4+ 模型，旧模型静默降级为标准 ZIP 归档模式
    // (必须在拿锁前判断：generateImage 内部会自行加锁，不可重入)
    if (!params.model.isV4OrAbove) {
      final images = await generateImage(
        apiKey: apiKey,
        params: params,
      );
      if (images.isEmpty) {
        yield NaiStreamProgress.error('生图响应中未包含任何图片。');
      } else {
        yield NaiStreamProgress.finalResult(
          finalImage: images.first,
          totalSteps: params.effectiveSteps,
        );
      }
      return;
    }

    await _lock.acquire();
    try {
      final preparedRefs = await _preparePreciseReferences(
        params,
        forInpaint: false,
      );
      final preparedVibes = await _prepareVibeImagesLocked(
        apiKey: apiKey,
        params: params,
      );
      final payload = params.toApiPayload(
        streaming: true,
        preparedReferenceImages: preparedRefs,
        preparedVibeImages: preparedVibes,
      );
      yield* _executeMsgpackStream(
        apiKey: apiKey,
        body: jsonEncode(payload),
        totalSteps: params.effectiveSteps,
        httpErrorPrefix: '流式生图请求失败',
        streamErrorFallback: '生图流异常中断',
        emptyStreamMessage: '流式响应已结束，但未收到任何成图数据。',
      );
    } finally {
      _lock.release();
    }
  }

  /// 生成插画 (标准 ZIP 归档模式)
  Future<List<Uint8List>> generateImage({
    required String apiKey,
    required NaiGenerationParams params,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key，请在设置中输入有效的 Token。');
    }

    return await _lock.runExclusive(() async {
      final preparedRefs = await _preparePreciseReferences(
        params,
        forInpaint: false,
      );
      final preparedVibes = await _prepareVibeImagesLocked(
        apiKey: apiKey,
        params: params,
      );
      final payload = params.toApiPayload(
        preparedReferenceImages: preparedRefs,
        preparedVibeImages: preparedVibes,
      );
      final body = jsonEncode(payload);

      http.Response response = await _postWithAuth(
        _generateEndpoint,
        apiKey,
        body,
      );

      // 429 智能重试
      if (response.statusCode == 429) {
        await Future.delayed(retryDelay);
        response = await _postWithAuth(_generateEndpoint, apiKey, body);
      }

      if (response.statusCode != 200) {
        throw _parseHttpError(response, '生图请求失败');
      }

      final zipBytes = response.bodyBytes;
      return _extractImagesFromZip(zipBytes);
    });
  }

  /// 调用 NovelAI 官方 `/ai/encode-vibe` 对参考图进行编码 (仅 V4 / V4.5，每次消耗 2 Anlas)。
  /// 返回 Base64 编码字符串，可缓存复用避免重复扣费。
  Future<String> encodeVibe({
    required String apiKey,
    required Uint8List imageBytes,
    required NaiModel model,
    double informationExtracted = 1.0,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key，请在设置中输入有效的 Token。');
    }
    if (!model.usesEncodedVibeTransfer) {
      throw StateError('当前模型 (${model.label}) 不使用服务端 Vibe 编码。');
    }
    return _lock.runExclusive(
      () => _encodeVibeLocked(
        apiKey: apiKey,
        imageBytes: imageBytes,
        model: model,
        informationExtracted: informationExtracted,
      ),
    );
  }

  Future<String> _encodeVibeLocked({
    required String apiKey,
    required Uint8List imageBytes,
    required NaiModel model,
    required double informationExtracted,
  }) async {
    final body = jsonEncode({
      'image': base64Encode(imageBytes),
      'model': model.id,
      'information_extracted': informationExtracted.clamp(0.01, 1.0),
    });

    http.Response response = await _postWithAuth(
      _encodeVibeEndpoint,
      apiKey,
      body,
    );

    if (response.statusCode == 429) {
      await Future.delayed(retryDelay);
      response = await _postWithAuth(_encodeVibeEndpoint, apiKey, body);
    }

    if (response.statusCode != 200) {
      throw _parseHttpError(response, 'Vibe 编码请求失败');
    }

    if (response.bodyBytes.isEmpty) {
      throw Exception('Vibe 编码响应为空。');
    }
    return base64Encode(response.bodyBytes);
  }

  /// 在并发互斥锁保护下为本次生成准备 Vibe Transfer 数据：
  /// - V4 / V4.5：优先复用已缓存编码；缺失或信息提取度变化时自动调 `/ai/encode-vibe`；
  /// - V3 / Furry V3：后台 Isolate 缩放为 448×448 黑底居中 PNG Base64。
  Future<List<String>?> _prepareVibeImagesLocked({
    required String apiKey,
    required NaiGenerationParams params,
  }) async {
    final activeVibes = params.effectiveVibeReferences();
    if (activeVibes.isEmpty) return null;

    if (!params.model.usesEncodedVibeTransfer) {
      return VibeTransferService.prepareV3Images(activeVibes);
    }

    final results = <String>[];
    for (final vibe in activeVibes) {
      final cached = vibe.resolveEncodingFor(params.model);
      if (cached != null && cached.isNotEmpty) {
        results.add(cached);
        continue;
      }
      final raw = vibe.rawImageBytes;
      if (raw == null || raw.isEmpty) {
        throw StateError('Vibe「${vibe.displayName}」缺少当前模型编码且无原始图片。');
      }
      final encoding = await _encodeVibeLocked(
        apiKey: apiKey,
        imageBytes: raw,
        model: params.model,
        informationExtracted: vibe.informationExtracted,
      );
      results.add(encoding);
    }
    return results;
  }

  /// 实时流式局部重绘 (Infill)
  Stream<NaiStreamProgress> generateInfillStream({
    required String apiKey,
    required NaiGenerationParams params,
    required Uint8List sourceBytes,
    required Uint8List maskBytes,
    required int requestWidth,
    required int requestHeight,
    double strength = 0.70,
    double noise = 0.00,
  }) async* {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key，请在设置中输入有效的 Token。');
    }

    if (!params.model.isV4OrAbove) {
      final images = await generateInfill(
        apiKey: apiKey,
        params: params,
        sourceBytes: sourceBytes,
        maskBytes: maskBytes,
        requestWidth: requestWidth,
        requestHeight: requestHeight,
        strength: strength,
        noise: noise,
      );
      if (images.isEmpty) {
        yield NaiStreamProgress.error('重绘响应中未包含任何图片。');
      } else {
        yield NaiStreamProgress.finalResult(
          finalImage: images.first,
          totalSteps: params.effectiveSteps,
        );
      }
      return;
    }

    await _lock.acquire();
    try {
      final preparedRefs = await _preparePreciseReferences(
        params,
        forInpaint: true,
      );
      final payload = params.toInfillApiPayload(
        sourceBytes: sourceBytes,
        maskBytes: maskBytes,
        requestWidth: requestWidth,
        requestHeight: requestHeight,
        strength: strength,
        noise: noise,
        streaming: true,
        preparedReferenceImages: preparedRefs,
      );
      yield* _executeMsgpackStream(
        apiKey: apiKey,
        body: jsonEncode(payload),
        totalSteps: params.effectiveSteps,
        httpErrorPrefix: '流式重绘请求失败',
        streamErrorFallback: '重绘流异常中断',
        emptyStreamMessage: '流式重绘响应已结束，但未收到任何成图数据。',
      );
    } finally {
      _lock.release();
    }
  }

  Stream<NaiStreamProgress> _executeMsgpackStream({
    required String apiKey,
    required String body,
    required int totalSteps,
    required String httpErrorPrefix,
    required String streamErrorFallback,
    required String emptyStreamMessage,
  }) async* {
    final requestHeaders = {
      'Content-Type': 'application/json',
      'Accept': 'application/x-msgpack',
      'Authorization': 'Bearer ${apiKey.trim()}',
      'x-correlation-id': _generateCorrelationId(),
      'x-initiated-at': DateTime.now().toUtc().toIso8601String(),
    };

    final uri = Uri.parse(_generateStreamEndpoint);

    http.Request createRequest() {
      final req = http.Request('POST', uri);
      req.headers.addAll(requestHeaders);
      req.body = body;
      return req;
    }

    http.StreamedResponse streamedResponse = await _httpClient
        .send(createRequest())
        .timeout(requestTimeout);

    // 429 智能重试：先消费/取消废弃响应流，防止泄漏底层 socket 连接
    if (streamedResponse.statusCode == 429) {
      await _discardResponseStream(streamedResponse);
      await Future.delayed(retryDelay);
      streamedResponse = await _httpClient
          .send(createRequest())
          .timeout(requestTimeout);
    }

    if (streamedResponse.statusCode != 200) {
      final errorBytes = await streamedResponse.stream.toBytes().timeout(
        metaTimeout,
      );
      final errorBody = utf8.decode(errorBytes, allowMalformed: true);
      throw _parseHttpError(
        http.Response(errorBody, streamedResponse.statusCode),
        httpErrorPrefix,
      );
    }

    final buffer = _ByteFrameBuffer();
    var messageCount = 0;
    var hasYieldedFinal = false;
    Uint8List? lastReceivedImage;

    await for (final chunk in streamedResponse.stream.timeout(
      streamIdleTimeout,
    )) {
      buffer.append(chunk);

      while (buffer.available >= 4) {
        final messageLength = buffer.peekUint32BE();
        if (buffer.available < 4 + messageLength) {
          // 当前包不完整，等待后续数据到达
          break;
        }

        final messageBytes = buffer.takeFrame(messageLength);
        messageCount += 1;

        try {
          final decoded = msgpack.deserialize(messageBytes);
          if (decoded is! Map) continue;

          final msgMap = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );

          final eventType = msgMap['event_type']?.toString();
          if (eventType == 'error' || msgMap.containsKey('error')) {
            final err =
                msgMap['message'] ?? msgMap['error'] ?? streamErrorFallback;
            yield NaiStreamProgress.error(err.toString());
            return;
          }

          final imageBytes = _decodeStreamImage(
            msgMap['image'] ?? msgMap['data'],
          );
          if (imageBytes == null || imageBytes.isEmpty) continue;

          lastReceivedImage = imageBytes;

          if (eventType == 'final') {
            hasYieldedFinal = true;
            yield NaiStreamProgress.finalResult(
              finalImage: imageBytes,
              totalSteps: totalSteps,
            );
          } else if (eventType == null ||
              eventType.isEmpty ||
              eventType == 'intermediate') {
            final stepIx = _asInt(msgMap['step_ix']);
            final currentStep = stepIx != null ? stepIx + 1 : messageCount;
            yield NaiStreamProgress.intermediate(
              previewImage: imageBytes,
              currentStep: currentStep,
              totalSteps: totalSteps,
            );
          }
        } catch (_) {
          // 容错忽略单帧解码失败
        }
      }
    }

    // 检查是否有未处理的 final 事件或降级数据
    if (!hasYieldedFinal) {
      if (buffer.available > 0) {
        final leftoverBytes = buffer.takeRemaining();
        if (_isZip(leftoverBytes)) {
          final images = await _extractImagesFromZip(leftoverBytes);
          if (images.isNotEmpty) {
            hasYieldedFinal = true;
            yield NaiStreamProgress.finalResult(
              finalImage: images.first,
              totalSteps: totalSteps,
            );
            return;
          }
        }
      }

      // 如果流已完成但未显式收到 final 标记，将最后接收到的去噪帧作为最终成图
      if (lastReceivedImage != null && lastReceivedImage.isNotEmpty) {
        hasYieldedFinal = true;
        yield NaiStreamProgress.finalResult(
          finalImage: lastReceivedImage,
          totalSteps: totalSteps,
        );
      }
    }

    // 流已结束但既无 final 成图也无任何中间帧：显式报错，避免静默失败
    if (!hasYieldedFinal) {
      yield NaiStreamProgress.error(emptyStreamMessage);
    }
  }

  Future<List<String>?> _preparePreciseReferences(
    NaiGenerationParams params, {
    required bool forInpaint,
  }) async {
    final activeRefs = params.effectivePreciseReferences(
      forInpaint: forInpaint,
    );
    if (activeRefs.isEmpty) return null;
    return PreciseReferenceImageService.prepareImagesForModel(
      references: activeRefs,
      model: params.model,
    );
  }

  Future<void> _discardResponseStream(http.StreamedResponse response) async {
    final sub = response.stream.listen((_) {}, onError: (_) {});
    try {
      await sub.asFuture<void>().timeout(const Duration(seconds: 2));
    } catch (_) {
    } finally {
      await sub.cancel();
    }
  }

  /// 执行局部重绘 (标准 ZIP 归档模式)
  Future<List<Uint8List>> generateInfill({
    required String apiKey,
    required NaiGenerationParams params,
    required Uint8List sourceBytes,
    required Uint8List maskBytes,
    required int requestWidth,
    required int requestHeight,
    double strength = 0.70,
    double noise = 0.00,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key，请在设置中输入有效的 Token。');
    }

    final preparedRefs = await _preparePreciseReferences(
      params,
      forInpaint: true,
    );
    final payload = params.toInfillApiPayload(
      sourceBytes: sourceBytes,
      maskBytes: maskBytes,
      requestWidth: requestWidth,
      requestHeight: requestHeight,
      strength: strength,
      noise: noise,
      streaming: false,
      preparedReferenceImages: preparedRefs,
    );
    final body = jsonEncode(payload);

    return await _lock.runExclusive(() async {
      http.Response response = await _postWithAuth(
        _generateEndpoint,
        apiKey,
        body,
      );

      if (response.statusCode == 429) {
        await Future.delayed(retryDelay);
        response = await _postWithAuth(_generateEndpoint, apiKey, body);
      }

      if (response.statusCode != 200) {
        throw _parseHttpError(response, '局部重绘请求失败');
      }

      final zipBytes = response.bodyBytes;
      return _extractImagesFromZip(zipBytes);
    });
  }

  /// 图像超分放大 (V5 换代后的官方新超分模型，固定倍率输出)
  ///
  /// 新协议为 multipart 表单：图片 PNG 文件 + request JSON 文件
  /// (固定模型与 declared_blur_sigma，不再接受 scale 参数)；
  /// 响应为 ZIP 归档，兼容非打包的裸图片字节。
  Future<Uint8List> upscaleImage({
    required String apiKey,
    required Uint8List imageBytes,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key。');
    }

    return await _lock.runExclusive(() async {
      http.Response response = await _postMultipartUpscale(
        apiKey: apiKey,
        imageBytes: imageBytes,
      );

      if (response.statusCode == 429) {
        await Future.delayed(retryDelay);
        response = await _postMultipartUpscale(
          apiKey: apiKey,
          imageBytes: imageBytes,
        );
      }

      if (response.statusCode != 200) {
        throw _parseHttpError(response, '图片放大失败');
      }

      final raw = response.bodyBytes;
      if (raw.isEmpty) {
        throw Exception('未从返回数据中解析到放大后的图片。');
      }

      // 优先按 ZIP 归档解包；非打包响应则直接作为裸图片字节返回
      if (_isZip(raw)) {
        try {
          final extracted = await _extractImagesFromZip(raw);
          if (extracted.isNotEmpty) return extracted.first;
        } catch (_) {
          // 非标准 ZIP，走裸字节回退
        }
      }
      return raw;
    });
  }

  /// 构建并发送 V5 换代后的 multipart 超分请求
  Future<http.Response> _postMultipartUpscale({
    required String apiKey,
    required Uint8List imageBytes,
  }) async {
    final requestJson = jsonEncode({
      'image': 'image',
      'model': _upscaleModel,
      'declared_blur_sigma': _upscaleDeclaredBlurSigma,
    });

    final request = http.MultipartRequest('POST', Uri.parse(_upscaleEndpoint))
      ..headers['Authorization'] = 'Bearer ${apiKey.trim()}'
      ..headers['Accept'] = 'application/x-zip-compressed'
      ..files.add(
        http.MultipartFile.fromBytes(
          'image',
          imageBytes,
          filename: 'blob',
          contentType: http.MediaType('image', 'png'),
        ),
      )
      ..files.add(
        http.MultipartFile.fromBytes(
          'request',
          utf8.encode(requestJson),
          filename: 'blob',
          contentType: http.MediaType('application', 'json'),
        ),
      );

    final streamed = await _httpClient.send(request).timeout(requestTimeout);
    return await http.Response.fromStream(streamed).timeout(requestTimeout);
  }

  /// 查询 Danbooru 标签联想建议
  Future<List<NaiTagSuggestion>> suggestTags({
    required String apiKey,
    required String query,
    NaiModel model = NaiModel.v5Full,
  }) async {
    if (apiKey.trim().isEmpty || query.trim().isEmpty) {
      return [];
    }

    final uri = Uri.parse(
      '$_tagsEndpoint?model=${model.id}&prompt=${Uri.encodeComponent(query.trim())}',
    );

    try {
      final response = await _httpClient
          .get(uri, headers: {'Authorization': 'Bearer ${apiKey.trim()}'})
          .timeout(metaTimeout);

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawList = data['tags'] as List<dynamic>? ?? [];
      return rawList
          .map(
            (item) => NaiTagSuggestion.fromJson(item as Map<String, dynamic>),
          )
          .toList();
    } catch (_) {
      return [];
    }
  }

  /// 查询账号与 V5 体力池信息
  Future<NaiAccountInfo> fetchAccountInfo({required String apiKey}) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key。');
    }

    final uri = Uri.parse(_userDataEndpoint);
    final response = await _httpClient
        .get(uri, headers: {'Authorization': 'Bearer ${apiKey.trim()}'})
        .timeout(metaTimeout);

    if (response.statusCode != 200) {
      throw _parseHttpError(response, '查询账号信息失败');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return NaiAccountInfo.fromJson(data);
  }

  // --- 内部辅助方法 ---

  Future<http.Response> _postWithAuth(
    String endpoint,
    String apiKey,
    String body,
  ) async {
    return await _httpClient
        .post(
          Uri.parse(endpoint),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer ${apiKey.trim()}',
          },
          body: body,
        )
        .timeout(requestTimeout);
  }

  Future<List<Uint8List>> _extractImagesFromZip(Uint8List zipBytes) async {
    try {
      return await runIsolated(
        _extractImagesFromZipIsolate,
        IsolateBytes(zipBytes),
      );
    } catch (e) {
      throw Exception('解析图片数据流失败: $e');
    }
  }

  Exception _parseHttpError(http.Response response, String defaultPrefix) {
    final status = response.statusCode;
    final body = response.body;

    if (status == 401) {
      return Exception('$defaultPrefix: API Key 无效或已过期 (HTTP 401)');
    }
    if (status == 402) {
      return Exception('$defaultPrefix: Anlas 点数不足或需要激活订阅 (HTTP 402)');
    }
    if (status == 429) {
      return Exception('$defaultPrefix: 官方并发超限，请稍后重试 (HTTP 429)');
    }
    if (status == 400) {
      return Exception('$defaultPrefix: 参数校验失败 (HTTP 400): $body');
    }
    return Exception('$defaultPrefix (HTTP $status): $body');
  }

  static String _generateCorrelationId() {
    return List.generate(
      6,
      (_) => _correlationChars[_random.nextInt(_correlationChars.length)],
      growable: false,
    ).join();
  }

  static bool _isZip(List<int> bytes) {
    return bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4B;
  }

  static int? _asInt(dynamic val) {
    if (val is int) return val;
    if (val is num) return val.toInt();
    if (val is String) return int.tryParse(val);
    return null;
  }

  static Uint8List? _decodeStreamImage(dynamic value) {
    if (value is Uint8List) return value;
    if (value is List<int>) return Uint8List.fromList(value);
    if (value is String && value.isNotEmpty) {
      try {
        var str = value.trim();
        if (str.startsWith('data:image')) {
          final commaIdx = str.indexOf(',');
          if (commaIdx >= 0) {
            str = str.substring(commaIdx + 1);
          }
        }
        return Uint8List.fromList(base64Decode(str));
      } catch (_) {}
    }
    return null;
  }
}

class _ByteFrameBuffer {
  Uint8List _buffer = Uint8List(4096);
  int _readOffset = 0;
  int _writeOffset = 0;

  int get available => _writeOffset - _readOffset;

  void append(List<int> chunk) {
    if (chunk.isEmpty) return;
    final rem = available;
    final needed = rem + chunk.length;
    if (_writeOffset + chunk.length > _buffer.length) {
      if (needed <= _buffer.length) {
        if (rem > 0) {
          _buffer.setRange(0, rem, _buffer, _readOffset);
        }
        _readOffset = 0;
        _writeOffset = rem;
      } else {
        var newCap = _buffer.length * 2;
        while (newCap < needed) {
          newCap *= 2;
        }
        final next = Uint8List(newCap);
        if (rem > 0) {
          next.setRange(0, rem, _buffer, _readOffset);
        }
        _buffer = next;
        _readOffset = 0;
        _writeOffset = rem;
      }
    }
    _buffer.setRange(_writeOffset, _writeOffset + chunk.length, chunk);
    _writeOffset += chunk.length;
  }

  int peekUint32BE() {
    return (_buffer[_readOffset] << 24) |
        (_buffer[_readOffset + 1] << 16) |
        (_buffer[_readOffset + 2] << 8) |
        _buffer[_readOffset + 3];
  }

  Uint8List takeFrame(int messageLength) {
    final start = _readOffset + 4;
    final end = start + messageLength;
    final frame = _buffer.sublist(start, end);
    _readOffset = end;
    if (_readOffset == _writeOffset) {
      _readOffset = 0;
      _writeOffset = 0;
    }
    return frame;
  }

  Uint8List takeRemaining() {
    if (available <= 0) return Uint8List(0);
    final out = _buffer.sublist(_readOffset, _writeOffset);
    _readOffset = 0;
    _writeOffset = 0;
    return out;
  }
}

List<Uint8List> _extractImagesFromZipIsolate(IsolateBytes packed) {
  final zipBytes = packed.materialize();
  final archive = ZipDecoder().decodeBytes(zipBytes);
  final images = <Uint8List>[];

  for (final file in archive) {
    if (file.isFile && file.name.toLowerCase().endsWith('.png')) {
      final content = file.content;
      if (content is List<int>) {
        images.add(content is Uint8List ? content : Uint8List.fromList(content));
      }
    }
  }

  if (images.isEmpty && archive.isNotEmpty) {
    final first = archive.first;
    if (first.isFile && first.content is List<int>) {
      final content = first.content as List<int>;
      images.add(content is Uint8List ? content : Uint8List.fromList(content));
    }
  }

  if (images.isEmpty) {
    throw Exception('压缩包内未找到有效图像文件。');
  }

  return images;
}
