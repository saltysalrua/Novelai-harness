import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:http/http.dart' as http;
import '../models/novelai_models.dart';

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
  static const String _upscaleEndpoint = '$_host/ai/upscale';
  static const String _tagsEndpoint = '$_host/ai/generate-image/suggest-tags';
  static const String _userDataEndpoint = '$_host/user/data';

  final AsyncLock _lock = AsyncLock();
  final http.Client _httpClient;

  NovelAiService({http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  /// 生成插画
  Future<List<Uint8List>> generateImage({
    required String apiKey,
    required NaiGenerationParams params,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key，请在设置中输入有效的 Token。');
    }

    final payload = params.toApiPayload();
    final body = jsonEncode(payload);

    return await _lock.runExclusive(() async {
      http.Response response = await _postWithAuth(
        _generateEndpoint,
        apiKey,
        body,
      );

      // 429 智能重试
      if (response.statusCode == 429) {
        await Future.delayed(const Duration(milliseconds: 2500));
        response = await _postWithAuth(_generateEndpoint, apiKey, body);
      }

      if (response.statusCode != 200) {
        throw _parseHttpError(response, '生图请求失败');
      }

      final zipBytes = response.bodyBytes;
      return _extractImagesFromZip(zipBytes);
    });
  }

  /// 图像超分放大 (2x / 4x)
  Future<Uint8List> upscaleImage({
    required String apiKey,
    required Uint8List imageBytes,
    int scale = 4,
  }) async {
    if (apiKey.trim().isEmpty) {
      throw Exception('未配置 NovelAI API Key。');
    }

    final base64Image = base64Encode(imageBytes);
    final payload = {
      'image': base64Image,
      'scale': scale == 2 ? 2 : 4,
    };
    final body = jsonEncode(payload);

    return await _lock.runExclusive(() async {
      http.Response response = await _postWithAuth(
        _upscaleEndpoint,
        apiKey,
        body,
      );

      if (response.statusCode == 429) {
        await Future.delayed(const Duration(milliseconds: 2500));
        response = await _postWithAuth(_upscaleEndpoint, apiKey, body);
      }

      if (response.statusCode != 200) {
        throw _parseHttpError(response, '图片放大失败');
      }

      final extracted = _extractImagesFromZip(response.bodyBytes);
      if (extracted.isEmpty) {
        throw Exception('未从返回数据中解析到放大后的图片。');
      }
      return extracted.first;
    });
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
      final response = await _httpClient.get(
        uri,
        headers: {
          'Authorization': 'Bearer ${apiKey.trim()}',
        },
      );

      if (response.statusCode != 200) {
        return [];
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final rawList = data['tags'] as List<dynamic>? ?? [];
      return rawList
          .map((item) => NaiTagSuggestion.fromJson(item as Map<String, dynamic>))
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
    final response = await _httpClient.get(
      uri,
      headers: {
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
    );

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
    return await _httpClient.post(
      Uri.parse(endpoint),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer ${apiKey.trim()}',
      },
      body: body,
    );
  }

  List<Uint8List> _extractImagesFromZip(Uint8List zipBytes) {
    try {
      final archive = ZipDecoder().decodeBytes(zipBytes);
      final images = <Uint8List>[];

      for (final file in archive) {
        if (file.isFile && file.name.toLowerCase().endsWith('.png')) {
          final content = file.content;
          if (content is List<int>) {
            images.add(Uint8List.fromList(content));
          }
        }
      }

      if (images.isEmpty && archive.isNotEmpty) {
        final first = archive.first;
        if (first.isFile && first.content is List<int>) {
          images.add(Uint8List.fromList(first.content as List<int>));
        }
      }

      if (images.isEmpty) {
        throw Exception('压缩包内未找到有效图像文件。');
      }

      return images;
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
}
