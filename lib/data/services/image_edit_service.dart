library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// AI 整图编辑结果：编辑后的图片字节与模型附带的文字说明
class ImageEditResult {
  final Uint8List imageBytes;
  final String? textReply;

  const ImageEditResult({required this.imageBytes, this.textReply});
}

/// AI 整图编辑服务：把整张图片发给 OpenAI 兼容端点上的绘图 / 图像编辑模型
/// (如 nano banana / gemini-2.5-flash-image / gpt-image / seedream)，按
/// 自然语言指令重绘整张图片。
///
/// 请求走标准 /chat/completions：图片以 data URL 放进 image_url 内容块，
/// 并附 modalities: ['image', 'text'] (OpenRouter 系网关要求；其余网关会
/// 忽略该字段)。返回图片的解析兼容四种主流格式：
/// 1. message.images 数组 (OpenRouter: {type:'image_url', image_url:{url}})
/// 2. message.content 为内容块数组 (newapi: {type:'image_url'|'image', ...})
/// 3. message.content 为字符串内嵌 markdown 图片 / data URL
/// 4. 图片为 http(s) 临时链接时自动下载取回字节
class ImageEditService {
  final http.Client _client;

  /// 429 频控重试前的等待时长 (测试可注入短时长)
  final Duration retryDelay;

  ImageEditService({
    http.Client? client,
    this.retryDelay = const Duration(milliseconds: 2500),
  }) : _client = client ?? http.Client();

  /// 计算 /chat/completions 完整端点 (复用 LlmProviderConfig 的拼接语义)
  static String chatCompletionsEndpoint(String baseUrl) {
    var base = baseUrl.trim();
    if (base.isEmpty) return '';
    if (base.endsWith('/')) base = base.substring(0, base.length - 1);
    if (base.endsWith('/chat/completions')) return base;
    return '$base/chat/completions';
  }

  /// 校验字节是否为受支持的图片格式 (PNG / JPEG / WebP / GIF)
  static bool looksLikeImage(Uint8List bytes) {
    if (bytes.length < 12) return false;
    // PNG: 89 50 4E 47
    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }
    // JPEG: FF D8 FF
    if (bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF) return true;
    // WebP: RIFF....WEBP
    if (bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    // GIF: GIF8
    if (bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x38) {
      return true;
    }
    return false;
  }

  /// 执行整图编辑
  ///
  /// [aspectRatio] 生图比例 (如 "16:9"，空 = 跟随原图)；[imageResolution]
  /// 分辨率档位 ("1K" / "2K" / "4K"，空 = 默认)。两者均按多写法冗余写入请求体，
  /// 不同网关认不同字段，Go 系网关对未知的顶层字段直接忽略，多传无害。
  Future<ImageEditResult> editImage({
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String prompt,
    required Uint8List imageBytes,
    String aspectRatio = '',
    String imageResolution = '',
    Duration timeout = const Duration(seconds: 240),
  }) async {
    final endpoint = chatCompletionsEndpoint(baseUrl);
    if (endpoint.isEmpty) {
      throw Exception('请先在设置中配置绘图模型供应商的基础 URL');
    }

    final dataUrl = 'data:image/png;base64,${base64Encode(imageBytes)}';
    final body = jsonEncode({
      'model': modelId,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        },
      ],
      'modalities': ['image', 'text'],
      // 生图比例与分辨率：各家网关无统一约定，同时写入三种常见拼写——
      // - aspect_ratio: OpenAI 兼容扩展惯例 (OpenRouter Image API 同名)
      // - image_config: {aspect_ratio, image_size} 对齐 google-genai SDK
      //   的 snake_case 命名，部分代理直接透传 generationConfig.imageConfig
      // - size: new-api 系网关的尺寸字段 (imagen 分支接受含冒号的比例写法)
      if (aspectRatio.isNotEmpty) ...{
        'aspect_ratio': aspectRatio,
        'image_config': {
          'aspect_ratio': aspectRatio,
          if (imageResolution.isNotEmpty) 'image_size': imageResolution,
        },
        'size': aspectRatio,
      },
      if (imageResolution.isNotEmpty && aspectRatio.isEmpty)
        'image_config': {'image_size': imageResolution},
    });

    final headers = <String, String>{
      // 必须显式声明 utf-8：http 包对字符串请求体默认 Latin-1 编码，
      // 中文指令会直接抛 "Contains invalid characters"
      'Content-Type': 'application/json; charset=utf-8',
      'Accept': 'application/json',
    };
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $trimmedKey';
    }

    http.Response response;
    try {
      response = await _client
          .post(Uri.parse(endpoint), headers: headers, body: body)
          .timeout(timeout);
    } catch (e) {
      throw Exception('网络连接失败 ($endpoint): $e');
    }

    // 429 频控：等待后单次重试 (与 NovelAI 请求同策略)
    if (response.statusCode == 429) {
      await Future<void>.delayed(retryDelay);
      try {
        response = await _client
            .post(Uri.parse(endpoint), headers: headers, body: body)
            .timeout(timeout);
      } catch (e) {
        throw Exception('网络连接失败 ($endpoint): $e');
      }
    }

    if (response.statusCode != 200) {
      final errBody = utf8.decode(response.bodyBytes, allowMalformed: true);
      String? serverMessage;
      try {
        final decoded = jsonDecode(errBody);
        if (decoded is Map<String, dynamic>) {
          final err = decoded['error'];
          if (err is Map<String, dynamic> && err['message'] is String) {
            serverMessage = err['message'] as String;
          } else if (decoded['message'] is String) {
            serverMessage = decoded['message'] as String;
          }
        }
      } catch (_) {}
      throw Exception(
        serverMessage != null
            ? '服务端响应错误 (HTTP ${response.statusCode}): $serverMessage'
            : '服务端响应错误 (HTTP ${response.statusCode}): ${errBody.length > 200 ? errBody.substring(0, 200) : errBody}',
      );
    }

    final dynamic decoded;
    try {
      decoded = jsonDecode(
        utf8.decode(response.bodyBytes, allowMalformed: true),
      );
    } catch (e) {
      throw Exception('响应不是有效的 JSON: $e');
    }

    final candidates = extractImageCandidates(decoded);
    if (candidates.isEmpty) {
      throw Exception(
        '绘图模型未返回图片。请确认所选模型具备图像输出能力 (如 nano banana / gpt-image)，'
        '或查看模型文字回复: ${_extractPlainText(decoded)}',
      );
    }

    for (final candidate in candidates) {
      final bytes = await _resolveCandidate(
        candidate,
        headers: headers,
        timeout: timeout,
      );
      if (bytes != null) {
        return ImageEditResult(
          imageBytes: bytes,
          textReply: _extractPlainText(decoded),
        );
      }
    }

    throw Exception('绘图模型返回的图片数据无法解析或下载。');
  }

  /// 下载或解码单个图片候选 (data URL 解码 / http 链接下载)，失败返回 null
  Future<Uint8List?> _resolveCandidate(
    String candidate, {
    required Map<String, String> headers,
    required Duration timeout,
  }) async {
    if (candidate.startsWith('data:')) {
      final commaIdx = candidate.indexOf(',');
      if (commaIdx < 0) return null;
      final bytes = base64TryDecode(candidate.substring(commaIdx + 1));
      if (bytes == null || !looksLikeImage(bytes)) return null;
      return bytes;
    }
    if (candidate.startsWith('http://') || candidate.startsWith('https://')) {
      try {
        final resp = await _client
            .get(Uri.parse(candidate), headers: headers)
            .timeout(timeout);
        if (resp.statusCode != 200) return null;
        final bytes = resp.bodyBytes;
        if (!looksLikeImage(bytes)) return null;
        return bytes;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  /// 从完整响应 JSON 中提取全部图片 URL 候选 (data URL 与 http 链接)
  ///
  /// 兼容四种返回格式，按可信度从高到低排序：
  /// 1. choices[0].message.images 数组 (OpenRouter)
  /// 2. choices[0].message.content 内容块数组 (image_url / output_image)
  /// 3. choices[0].message.content 字符串 (markdown 图片 / 裸 data URL)
  static List<String> extractImageCandidates(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return const [];
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return const [];
    final first = choices[0];
    if (first is! Map<String, dynamic>) return const [];
    final message = first['message'];
    if (message is! Map<String, dynamic>) return const [];

    final candidates = <String>[];

    // 1. message.images 数组
    final images = message['images'];
    if (images is List) {
      for (final item in images) {
        final url = _urlOfImageEntry(item);
        if (url != null && !candidates.contains(url)) candidates.add(url);
      }
    }

    // 2. content 内容块数组
    final content = message['content'];
    if (content is List) {
      for (final part in content) {
        if (part is Map<String, dynamic>) {
          final url = _urlOfImageEntry(part);
          if (url != null && !candidates.contains(url)) candidates.add(url);
        }
      }
    }

    // 3. content 字符串：markdown 图片 + 裸 data URL
    if (content is String && content.isNotEmpty) {
      candidates.addAll(_extractUrlsFromText(content, candidates));
    }

    return candidates;
  }

  /// 从 message 中提取模型附带的纯文字回复 (去掉图片 URL，供结果摘要展示)
  static String? _extractPlainText(dynamic decoded) {
    if (decoded is! Map<String, dynamic>) return null;
    final choices = decoded['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final first = choices[0];
    if (first is! Map<String, dynamic>) return null;
    final message = first['message'];
    if (message is! Map<String, dynamic>) return null;

    final content = message['content'];
    if (content is String) {
      final text = content
          .replaceAll(RegExp(r'!\[[^\]]*\]\([^)]*\)'), '')
          .replaceAll(RegExp(r'data:image/[^;\s]+;base64,[A-Za-z0-9+/=]+'), '')
          .trim();
      return text.isEmpty ? null : text;
    }
    if (content is List) {
      final buffer = StringBuffer();
      for (final part in content) {
        if (part is Map<String, dynamic> && part['type'] == 'text') {
          final text = part['text'];
          if (text is String) buffer.write(text);
        }
      }
      final text = buffer.toString().trim();
      return text.isEmpty ? null : text;
    }
    return null;
  }

  /// 解析单个图片条目 / 内容块的 URL 字段
  static String? _urlOfImageEntry(dynamic item) {
    if (item is! Map) return null;
    final type = item['type'];
    if (type is String &&
        type != 'image_url' &&
        type != 'image' &&
        type != 'output_image') {
      return null;
    }
    // {image_url: {url}} 或 {url: ...} 或 {b64_json: ...}
    final imageurl = item['image_url'];
    if (imageurl is Map<String, dynamic>) {
      final url = imageurl['url'];
      if (url is String && url.isNotEmpty) return url;
    }
    if (imageurl is String && imageurl.isNotEmpty) return imageurl;
    final url = item['url'];
    if (url is String && url.isNotEmpty) return url;
    final b64 = item['b64_json'];
    if (b64 is String && b64.isNotEmpty) return 'data:image/png;base64,$b64';
    return null;
  }

  /// 从文本中提取 markdown 图片与裸 data URL
  static List<String> _extractUrlsFromText(String text, List<String> existing) {
    final result = <String>[];
    void add(String url) {
      if (url.isNotEmpty && !existing.contains(url) && !result.contains(url)) {
        result.add(url);
      }
    }

    // markdown: ![alt](url)
    for (final match in RegExp(r'!\[[^\]]*\]\(([^)]+)\)').allMatches(text)) {
      add(match.group(1)?.trim() ?? '');
    }
    // 裸 data URL
    for (final match in RegExp(
      r'data:image/[a-zA-Z0-9.+-]+;base64,[A-Za-z0-9+/=]+',
    ).allMatches(text)) {
      add(match.group(0) ?? '');
    }
    return result;
  }

  static Uint8List? base64TryDecode(String input) {
    try {
      return base64Decode(input.trim());
    } catch (_) {
      return null;
    }
  }
}
