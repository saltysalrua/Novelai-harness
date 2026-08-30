import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import '../models/danbooru_search_models.dart';
import '../models/tag_models.dart';

/// DanbooruSearch 在线语义检索服务 (SAkizuki/DanbooruSearch HF Space 公开 API)
///
/// 三个端点 (api_fastapi.py)：
/// - POST /search  中文/英文自然语言 -> 标准标签 (语义向量匹配，支持模糊描述)
/// - POST /related 标签共现关联推荐
/// - POST /artists 推荐擅长绘制指定标签元素的画师 (NPMI 共现)
///
/// 语义搜索实测 10~30s、画师推荐 30~60s (HF 免费实例算力波动)，
/// 因此所有调用方都必须做好异步慢路径处理；本服务内部做结果缓存，
/// 网络失败静默抛 [DanbooruSearchException]，由调用方决定降级行为。
class DanbooruSearchService {
  static final DanbooruSearchService instance = DanbooruSearchService._();

  DanbooruSearchService._() : _client = http.Client();

  /// 测试或自定义部署用构造
  DanbooruSearchService.forTesting({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client() {
    if (baseUrl != null) _baseUrl = baseUrl;
  }

  final http.Client _client;

  /// 服务基址 (DanbooruSearch HF Space 的 FastAPI 层，挂载在 /api 路径)
  String _baseUrl = 'https://sakizuki-danboorusearch.hf.space/api';

  String get baseUrl => _baseUrl;

  /// 允许运行时切换服务地址 (自建部署场景)
  set baseUrl(String value) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) _baseUrl = trimmed.replaceAll(RegExp(r'/+$'), '');
  }

  static const Duration _searchTimeout = Duration(seconds: 90);
  static const Duration _relatedTimeout = Duration(seconds: 60);
  static const Duration _artistsTimeout = Duration(seconds: 120);

  // 结果缓存 (键=方法+规范化参数)；超过阈值整表清空防长会话无界增长
  static const int _cacheCapacity = 200;
  final Map<String, Object> _cache = {};

  void _cachePut(String key, Object value) {
    if (_cache.length >= _cacheCapacity) _cache.clear();
    _cache[key] = value;
  }

  bool _isCjk(String s) => s.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);

  /// 查询是否包含汉字 (供补全层分流在线增强路径)
  bool isCjkQuery(String s) => _isCjk(s);

  // ── 语义搜词 ──────────────────────────────────────────────

  /// 中文/英文自然语言描述 -> Danbooru 标准标签列表。
  ///
  /// [useSegmentation] 开启时自动拆分长句概念分别检索 (适合完整画面描述)；
  /// 查询单一概念时建议关闭。返回结果已按服务端语义得分降序。
  Future<List<DanbooruSearchResult>> searchTags(
    String query, {
    int limit = 20,
    int topK = 5,
    bool useSegmentation = true,
  }) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final cacheKey = 'search|$q|$limit|$topK|$useSegmentation';
    final hit = _cache[cacheKey];
    if (hit is List<DanbooruSearchResult>) return hit;

    final body = <String, dynamic>{
      'query': q,
      'top_k': topK,
      'limit': limit,
      'popularity_weight': 0.15,
      'show_nsfw': true,
      'use_segmentation': useSegmentation,
      'target_layers': const ['英文', '中文扩展词', '释义', '中文核心词'],
      'target_categories': const ['General', 'Character', 'Copyright'],
    };

    final data = await _postJson('/search', body, _searchTimeout);
    final results = (data['results'] as List<dynamic>? ?? [])
        .map((e) => DanbooruSearchResult.fromJson(e as Map<String, dynamic>))
        .where((r) => r.tag.isNotEmpty)
        .toList();

    _cachePut(cacheKey, results);
    return results;
  }

  // ── 关联推荐 (标签共现) ──────────────────────────────────

  /// 给定种子标签列表，返回 Danbooru 图库中经常与其共同出现的关联标签。
  ///
  /// 多个种子标签时按整组共现关系综合推荐。服务端会自动做
  /// 拼写纠错 (Danbooru Tag Alias 规范化)，纠错映射在 [corrections] 返回。
  Future<List<DanbooruRelatedTag>> relatedTags(
    List<String> tags, {
    int limit = 20,
    bool showNsfw = true,
    List<DanbooruTagCategory>? categories,
    Map<String, String>? corrections,
  }) async {
    final seeds = tags
        .map((t) => t.trim().toLowerCase().replaceAll(' ', '_'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (seeds.isEmpty) return const [];

    final cacheKey =
        'related|${seeds.join(',')}|$limit|$showNsfw|${categories?.map((c) => c.code).join(',')}';
    final hit = _cache[cacheKey];
    if (hit is List<DanbooruRelatedTag>) return hit;

    final body = <String, dynamic>{
      'tags': seeds,
      'limit': limit,
      'show_nsfw': showNsfw,
      if (categories != null && categories.isNotEmpty)
        'target_categories': [
          for (final c in categories)
            switch (c) {
              DanbooruTagCategory.artist => 'Artist',
              DanbooruTagCategory.copyright => 'Copyright',
              DanbooruTagCategory.character => 'Character',
              DanbooruTagCategory.meta => 'Meta',
              _ => 'General',
            },
        ],
    };

    final data = await _postJson('/related', body, _relatedTimeout);
    _collectCorrections(data, corrections);
    final results = (data['results'] as List<dynamic>? ?? [])
        .map((e) => DanbooruRelatedTag.fromJson(e as Map<String, dynamic>))
        .where((r) => r.tag.isNotEmpty)
        .toList();

    _cachePut(cacheKey, results);
    return results;
  }

  // ── 推荐擅长画师 (标签-画师 NPMI 共现) ───────────────────

  /// 给定标签列表，推荐擅长绘制这些标签元素的画师。
  /// [minCooc] 为单个 (标签, 画师) 对的最小共现次数门槛。
  Future<List<DanbooruArtistRecommendation>> recommendArtists(
    List<String> tags, {
    int limit = 12,
    int minCooc = 3,
    Map<String, String>? corrections,
  }) async {
    final seeds = tags
        .map((t) => t.trim().toLowerCase().replaceAll(' ', '_'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (seeds.isEmpty) return const [];

    final cacheKey = 'artists|${seeds.join(',')}|$limit|$minCooc';
    final hit = _cache[cacheKey];
    if (hit is List<DanbooruArtistRecommendation>) return hit;

    final body = <String, dynamic>{
      'tags': seeds,
      'limit': limit,
      'min_cooc': minCooc,
      'show_nsfw': true,
    };

    final data = await _postJson('/artists', body, _artistsTimeout);
    _collectCorrections(data, corrections);
    final results = (data['results'] as List<dynamic>? ?? [])
        .map(
          (e) =>
              DanbooruArtistRecommendation.fromJson(e as Map<String, dynamic>),
        )
        .where((r) => r.artist.isNotEmpty)
        .toList();

    _cachePut(cacheKey, results);
    return results;
  }

  // ── 内部 ────────────────────────────────────────────────

  /// 服务连通性探测 (HF Space 冷启动可能要数十秒唤醒)
  Future<bool> healthCheck() async {
    try {
      final resp = await _client
          .get(Uri.parse('$_baseUrl/health'))
          .timeout(const Duration(seconds: 15));
      if (resp.statusCode != 200) return false;
      final j = jsonDecode(utf8.decode(resp.bodyBytes));
      return j is Map && j['loaded'] == true;
    } catch (_) {
      return false;
    }
  }

  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
    Duration timeout,
  ) async {
    try {
      final resp = await _client
          .post(
            Uri.parse('$_baseUrl$path'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(timeout);

      if (resp.statusCode != 200) {
        throw DanbooruSearchException(
          '服务返回 HTTP ${resp.statusCode}',
          statusCode: resp.statusCode,
        );
      }
      final decoded = jsonDecode(utf8.decode(resp.bodyBytes));
      if (decoded is! Map<String, dynamic>) {
        throw const DanbooruSearchException('服务返回格式异常');
      }
      // 纠错后仍无有效标签时服务端返回 {"error": ...}
      if (decoded.containsKey('error')) {
        throw DanbooruSearchException(decoded['error'].toString());
      }
      return decoded;
    } on DanbooruSearchException {
      rethrow;
    } on TimeoutException {
      throw const DanbooruSearchException('请求超时，服务可能正在唤醒或繁忙');
    } catch (e) {
      throw DanbooruSearchException('网络请求失败: $e');
    }
  }

  /// 收集服务端的标签拼写纠错映射 (原词 -> 规范标签)
  void _collectCorrections(
    Map<String, dynamic> data,
    Map<String, String>? out,
  ) {
    if (out == null) return;
    final corrections = data['corrections'];
    if (corrections is Map) {
      corrections.forEach((k, v) {
        if (k is String && v is String) out[k] = v;
      });
    }
  }

  void dispose() => _client.close();
}

/// DanbooruSearch 服务异常
class DanbooruSearchException implements Exception {
  final String message;
  final int? statusCode;

  const DanbooruSearchException(this.message, {this.statusCode});

  @override
  String toString() => message;
}
