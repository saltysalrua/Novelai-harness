import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/tag_models.dart';

/// 内部词条结构 (内存极简化存储，节省内存开销；查询用的小写/空格形态在解析时一次性预计算)
class _DictEntry {
  final String tag;
  final String tagLower; // 小写形态 (查询预匹配)
  final String tagSpaced; // 下划线转空格的小写形态 (查询预匹配)
  final int count;
  final String? zh;
  final String zhLower; // 中文释义小写形态 (中文查询预匹配)
  final List<String> aliases;
  final DanbooruTagCategory category;

  const _DictEntry({
    required this.tag,
    required this.tagLower,
    required this.tagSpaced,
    required this.count,
    this.zh,
    this.zhLower = '',
    this.aliases = const [],
    this.category = DanbooruTagCategory.general,
  });
}

/// 后台 Isolate 顶层解析函数
List<_DictEntry> _parseDanbooruTsv(String raw) {
  final list = <_DictEntry>[];
  final lines = const LineSplitter().convert(raw);

  for (final line in lines) {
    if (line.isEmpty) continue;
    final f = line.split('\t');
    if (f.length < 2) continue;

    final tag = f[0].trim();
    if (tag.isEmpty) continue;

    final count = int.tryParse(f[1]) ?? 0;
    // 过滤使用次数 < 10 的极低频冷门词，大幅精简内存
    if (count < 10) continue;

    String? zh;
    if (f.length > 2 && f[2].trim().isNotEmpty) {
      final rawZh = f[2].trim();
      // 社区词库多释义取首个
      var cut = rawZh.length;
      for (final sep in const [',', '，', '、', '/', ';', '；', '|']) {
        final idx = rawZh.indexOf(sep);
        if (idx >= 0 && idx < cut) cut = idx;
      }
      final first = rawZh.substring(0, cut).trim();
      if (first.isNotEmpty) zh = first;
    }

    final aliases = <String>[];
    if (f.length > 3 && f[3].trim().isNotEmpty) {
      for (final a in f[3].split(',')) {
        final trimmed = a.trim();
        if (trimmed.isNotEmpty) aliases.add(trimmed);
      }
    }

    // 分类：优先读取第 5 列官方 Danbooru 分类 ID (0/1/3/4/5)，
    // 旧版 4 列词库缺失时退回启发式推断
    final cat = f.length > 4
        ? DanbooruTagCategory.fromCode(f[4])
        : _inferCategory(tag);

    // 内存优化：已是全小写/无下划线的形态直接复用同一字符串引用，
    // 避免 30 万级词条各自多拷贝两份字符串
    final tagLower = tag == tag.toLowerCase() ? tag : tag.toLowerCase();
    final tagSpaced = tagLower.contains('_')
        ? tagLower.replaceAll('_', ' ')
        : tagLower;

    list.add(
      _DictEntry(
        tag: tag,
        tagLower: tagLower,
        tagSpaced: tagSpaced,
        count: count,
        zh: zh,
        zhLower: zh?.toLowerCase() ?? '',
        aliases: aliases,
        category: cat,
      ),
    );
  }

  return list;
}

/// 旧版 4 列词库的启发式分类推断 (无官方分类数据时兜底)
DanbooruTagCategory _inferCategory(String tag) {
  if (tag.contains('(') && tag.endsWith(')')) {
    // 包含原作括号后缀的多为角色 (如 hatsune_miku_(vocaloid))
    return DanbooruTagCategory.character;
  } else if (tag.startsWith('artist:') || tag.startsWith('by_')) {
    return DanbooruTagCategory.artist;
  } else if (tag == 'highres' ||
      tag == 'absurdres' ||
      tag.startsWith('year_') ||
      tag.contains('bad_') ||
      tag.contains('quality')) {
    return DanbooruTagCategory.meta;
  }
  return DanbooruTagCategory.general;
}

/// Danbooru 本地离线标签词典服务 (单例模式)
class TagDictionaryService {
  static final TagDictionaryService instance = TagDictionaryService._();
  TagDictionaryService._();

  List<_DictEntry>? _entries;
  final Map<String, String> _tagToZh = {};
  final Map<String, DanbooruTagCategory> _tagToCat = {};

  Future<void>? _loadingFuture;
  bool get isLoaded => _entries != null;
  int get count => _entries?.length ?? 0;

  // 查询结果缓存 (超过容量上限整表清空，防止长会话无界增长)
  static const int _cacheCapacity = 500;
  final Map<String, List<TagSuggestion>> _queryCache = {};

  /// 预热并异步加载词库
  Future<void> ensureLoaded({String? rawTsvContent}) async {
    if (_entries != null) return;
    return _loadingFuture ??= _load(rawTsvContent);
  }

  /// 用外部下载的新词库内容整体热替换当前词库 (在线更新完成后调用)
  Future<void> replaceWithContent(String rawTsv) async {
    // 若正在加载旧词库，先等它结束，避免状态交叉
    await _loadingFuture;
    final parsed = await compute(_parseDanbooruTsv, rawTsv);
    _entries = parsed;
    _queryCache.clear();
    _rebuildLookupMaps(parsed);
  }

  Future<void> _load(String? rawContent) async {
    try {
      String raw;
      if (rawContent != null) {
        raw = rawContent;
      } else {
        raw = await rootBundle.loadString('assets/danbooru.tsv');
      }

      // 后台 isolate 解析
      final parsed = await compute(_parseDanbooruTsv, raw);
      _entries = parsed;
      _rebuildLookupMaps(parsed);
    } catch (e) {
      debugPrint('[TagDictionaryService] 词库加载失败或资产未找到: $e');
      _entries = [];
    }
  }

  void _rebuildLookupMaps(List<_DictEntry> parsed) {
    _tagToZh.clear();
    _tagToCat.clear();
    // 建立快速反查哈希表
    for (final entry in parsed) {
      final cleanTag = entry.tag.replaceAll('_', ' ').toLowerCase();
      if (entry.zh != null) {
        _tagToZh[cleanTag] = entry.zh!;
      }
      _tagToCat[cleanTag] = entry.category;
    }
  }

  /// 快速查询标签中文释义
  String? translationOf(String tagName) {
    final key = tagName.trim().replaceAll('_', ' ').toLowerCase();
    return _tagToZh[key];
  }

  /// 快速查询标签分类
  DanbooruTagCategory? categoryOf(String tagName) {
    final key = tagName.trim().replaceAll('_', ' ').toLowerCase();
    return _tagToCat[key];
  }

  /// 智能多模态标签搜索
  Future<List<TagSuggestion>> search(
    String query, {
    int limit = 10,
    DanbooruTagCategory? category,
  }) async {
    await ensureLoaded();
    final entries = _entries;
    if (entries == null || entries.isEmpty) return const [];

    final rawQ = query.trim().toLowerCase();
    if (rawQ.isEmpty) return const [];

    final cacheKey = '$rawQ|${category?.code ?? -1}|$limit';
    final hit = _queryCache[cacheKey];
    if (hit != null) return hit;

    final qUnderscore = rawQ.replaceAll(' ', '_');
    final qSpace = rawQ.replaceAll('_', ' ');
    final isCjk = rawQ.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);

    final matches = <TagSuggestion>[];

    for (final e in entries) {
      if (category != null && e.category != category) continue;

      final tagUnder = e.tagLower;
      final tagSpace = e.tagSpaced;
      final zh = e.zhLower;

      double score = 0.0;
      String? matchedAlias;

      if (isCjk) {
        // 中文查询模式
        if (zh.startsWith(rawQ)) {
          score = 1000.0;
        } else if (zh.contains(rawQ)) {
          score = 600.0;
        }
      } else {
        // 英文 / 拼音 / 别名查询模式
        if (tagUnder == qUnderscore || tagSpace == qSpace) {
          score = 1500.0; // 完全精确匹配
        } else if (tagUnder.startsWith(qUnderscore) ||
            tagSpace.startsWith(qSpace)) {
          score = 1000.0; // 前缀命中
        } else if (tagUnder.contains(qUnderscore) ||
            tagSpace.contains(qSpace)) {
          score = 400.0; // 包含命中
        } else if (zh.contains(rawQ)) {
          score = 300.0; // 包含匹配中文
        } else {
          // 别名匹配
          for (final a in e.aliases) {
            final aLower = a.toLowerCase();
            if (aLower.startsWith(rawQ) || aLower.startsWith(qUnderscore)) {
              score = 800.0;
              matchedAlias = a;
              break;
            } else if (aLower.contains(rawQ)) {
              score = 250.0;
              matchedAlias = a;
              break;
            }
          }
        }
      }

      if (score > 0) {
        // 叠加基于热度的对数提升分数
        final popularityBoost = e.count > 0
            ? (math.log(e.count + 1) * 8.0)
            : 0.0;
        final totalScore = score + popularityBoost;

        matches.add(
          TagSuggestion(
            tag: tagSpace,
            category: e.category,
            postCount: e.count,
            translation: e.zh,
            aliases: e.aliases,
            matchedAlias: matchedAlias,
            score: totalScore,
          ),
        );
      }
    }

    matches.sort((a, b) => b.score.compareTo(a.score));
    final results = matches.take(limit).toList();

    // 存入 LRU 缓存
    if (_queryCache.length >= _cacheCapacity) {
      _queryCache.clear();
    }
    _queryCache[cacheKey] = results;

    return results;
  }
}
