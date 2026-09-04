import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/tag_models.dart';
import 'prompt_library_service.dart';
import 'isolated_compute.dart';

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

// ==================== 后台检索 Isolate (阶段2 性能治理) ====================
//
// 32 万词条的线性扫描逐次检索不再占用 UI 主线程：常驻 worker isolate
// 持有词条全量引用 (同 isolate 组内按引用共享，近零拷贝)，主线程把
// 查询词发过去，扫描完成后回传 top-N 结果。worker 不可用时 (启动失败/
// 测试 FakeAsync 环境) 自动退回主线程同步扫描，行为完全兼容。

/// worker 初始化消息：携带词条全量与回投端口
class _SearchInit {
  final List<_DictEntry> entries;
  final SendPort replyPort;
  const _SearchInit(this.entries, this.replyPort);
}

/// 词库热替换消息 (在线更新完成后同步新词条给 worker)
class _SearchReplace {
  final List<_DictEntry> entries;
  const _SearchReplace(this.entries);
}

/// 一次检索请求
class _SearchQuery {
  final int id;
  final String rawQuery;
  final DanbooruTagCategory? category;
  final int limit;
  const _SearchQuery(this.id, this.rawQuery, this.category, this.limit);
}

/// 检索回投结果
class _SearchReply {
  final int id;
  final List<TagSuggestion> results;
  const _SearchReply(this.id, this.results);
}

/// 常驻检索 isolate 主入口：持有词条引用，逐请求线性扫描
void _searchIsolateMain(_SearchInit init) {
  var entries = init.entries;
  final command = ReceivePort();
  init.replyPort.send(command.sendPort);
  command.listen((message) {
    if (message is _SearchQuery) {
      List<TagSuggestion> results = const [];
      try {
        results = _scanEntries(
          entries,
          message.rawQuery,
          category: message.category,
          limit: message.limit,
        );
      } catch (_) {}
      init.replyPort.send(_SearchReply(message.id, results));
    } else if (message is _SearchReplace) {
      entries = message.entries;
    }
  });
}

/// 词条线性扫描与打分 (后台 isolate 与主线程兑底共用同一实现)
List<TagSuggestion> _scanEntries(
  List<_DictEntry> entries,
  String rawQ, {
  DanbooruTagCategory? category,
  int limit = 10,
}) {
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
  return matches.take(limit).toList();
}

/// Danbooru 本地离线标签词典服务 (单例模式)
class TagDictionaryService {
  static final TagDictionaryService instance = TagDictionaryService._();
  TagDictionaryService._();

  /// 后台检索 Isolate 开关：
  /// 生产环境默认开启 (32 万条扫描不占 UI 主线程)；
  /// widget 测试的 FakeAsync 环境无法处理真实 Isolate 回投，
  /// 相关测试在 setUp 中置 false 退回主线程同步扫描。
  static bool backgroundSearchEnabled = true;

  List<_DictEntry>? _entries;
  final Map<String, String> _tagToZh = {};
  final Map<String, DanbooruTagCategory> _tagToCat = {};

  // ---- 后台检索 worker isolate 状态 ----
  ReceivePort? _workerPort;
  SendPort? _workerCommandPort;
  Isolate? _workerIsolate;
  Future<void>? _workerBoot;
  bool _workerBroken = false;
  final Map<int, Completer<List<TagSuggestion>>> _pendingSearches = {};
  int _searchSeq = 0;

  Future<void>? _loadingFuture;
  bool get isLoaded => _entries != null;
  int get count => _entries?.length ?? 0;

  // 查询结果缓存 (超过容量上限整表清空，防止长会话无界增长)
  static const int _cacheCapacity = 500;
  final Map<String, List<TagSuggestion>> _queryCache = {};

  /// 预热并异步加载词库 (加载完成后顺手预热后台检索 worker)
  Future<void> ensureLoaded({String? rawTsvContent}) async {
    if (_entries != null) return;
    return _loadingFuture ??= _load(rawTsvContent);
  }

  /// 清空查询结果缓存 (词库内容变更后调用，防止陈旧建议残留)
  void clearQueryCache() => _queryCache.clear();

  /// 用外部下载的新词库内容整体热替换当前词库 (在线更新完成后调用)
  Future<void> replaceWithContent(String rawTsv) async {
    // 若正在加载旧词库，先等它结束，避免状态交叉
    await _loadingFuture;
    final parsed = await runIsolated(_parseDanbooruTsv, rawTsv);
    _entries = parsed;
    _queryCache.clear();
    _rebuildLookupMaps(parsed);
    // 后台 worker 同步持有新词条引用
    _workerCommandPort?.send(_SearchReplace(parsed));
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
      final parsed = await runIsolated(_parseDanbooruTsv, raw);
      _entries = parsed;
      _rebuildLookupMaps(parsed);
      // 预热常驻检索 worker (失败静默，后续检索自动主线程兑底)
      unawaited(_ensureSearchWorker());
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

  // ==================== 后台检索 worker 管理 ====================

  /// 确保后台检索 worker 已就绪 (幂等；不可用时不做任何事)
  Future<void> _ensureSearchWorker() async {
    if (!backgroundSearchEnabled || _workerBroken) return;
    if (_workerCommandPort != null) return;
    final entries = _entries;
    if (entries == null || entries.isEmpty) return;
    final boot = _workerBoot ??= _bootSearchWorker(entries);
    await boot;
    _workerBoot = null;
  }

  /// 启动常驻检索 isolate 并等待指令端口就绪
  Future<void> _bootSearchWorker(List<_DictEntry> entries) async {
    final port = ReceivePort();
    final errorPort = ReceivePort();
    final ready = Completer<void>();

    Isolate? spawned;
    try {
      spawned = await Isolate.spawn(
        _searchIsolateMain,
        _SearchInit(entries, port.sendPort),
        onError: errorPort.sendPort,
      );
    } catch (e) {
      debugPrint('[TagDictionaryService] 检索 isolate 启动失败，回退主线程: $e');
      _workerBroken = true;
      port.close();
      errorPort.close();
      return;
    }

    _workerIsolate = spawned;
    _workerPort = port;
    port.listen((message) {
      if (message is SendPort) {
        _workerCommandPort = message;
        if (!ready.isCompleted) ready.complete();
      } else if (message is _SearchReply) {
        final completer = _pendingSearches.remove(message.id);
        if (completer != null && !completer.isCompleted) {
          completer.complete(message.results);
        }
      }
    });
    errorPort.listen((_) => _failSearchWorker());

    // 就绪等待保险丝：超时则永久回退主线程 (正常情况下毫秒级就绪)
    try {
      await ready.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      debugPrint('[TagDictionaryService] 检索 isolate 就绪超时，回退主线程');
      _failSearchWorker();
    }
  }

  /// worker 损坏：终后续检索全部主线程兑底，唤醒挂起请求
  void _failSearchWorker() {
    if (_workerBroken) return;
    _workerBroken = true;
    _workerCommandPort = null;
    _workerPort?.close();
    _workerPort = null;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    final pending = List.of(_pendingSearches.values);
    _pendingSearches.clear();
    for (final c in pending) {
      if (!c.isCompleted) c.completeError(StateError('检索 isolate 不可用'));
    }
  }

  /// 经后台 worker 检索：返回 null 表示不可用/超时，调用方主线程兑底
  Future<List<TagSuggestion>?> _searchViaWorker(
    String rawQ,
    DanbooruTagCategory? category,
    int limit,
  ) async {
    if (!backgroundSearchEnabled || _workerBroken) return null;
    try {
      await _ensureSearchWorker();
      final command = _workerCommandPort;
      if (command == null) return null;

      final id = ++_searchSeq;
      final completer = Completer<List<TagSuggestion>>();
      _pendingSearches[id] = completer;
      command.send(_SearchQuery(id, rawQ, category, limit));
      try {
        return await completer.future.timeout(const Duration(seconds: 3));
      } finally {
        // 超时/异常路径的挂起请求清理 (正常回投路径已在端口监听里移除)
        _pendingSearches.remove(id);
      }
    } catch (_) {
      return null;
    }
  }

  /// 智能多模态标签搜索
  Future<List<TagSuggestion>> search(
    String query, {
    int limit = 10,
    DanbooruTagCategory? category,
    bool includePromptCombos = true,
  }) async {
    final rawQ = query.trim().toLowerCase();
    if (rawQ.isEmpty) return const [];

    // 1. 若无特定 Danbooru 分类过滤，检索词库中的所有自定义词组合
    final comboMatches = (category == null && includePromptCombos)
        ? PromptLibraryService.instance.searchAsSuggestions(query, limit: 5)
        : const <TagSuggestion>[];

    await ensureLoaded();
    final entries = _entries;
    if (entries == null || entries.isEmpty) {
      return comboMatches.take(limit).toList();
    }

    final cacheKey =
        '$rawQ|${category?.code ?? -1}|$limit|$includePromptCombos';
    final hit = _queryCache[cacheKey];
    if (hit != null) return hit;

    // 2. 32 万词条线性扫描优先在后台 isolate 执行 (不占 UI 主线程)；
    //    worker 不可用时主线程同步兑底 (行为与旧实现完全一致)
    final dictMatches =
        await _searchViaWorker(rawQ, category, limit) ??
        _scanEntries(entries, rawQ, category: category, limit: limit);

    // 所有条目 (词库 + Danbooru 词典) 参与公平打分排序
    final matches = <TagSuggestion>[...comboMatches, ...dictMatches];
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
