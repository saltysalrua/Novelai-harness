import 'dart:async';
import 'dart:convert';
import 'dart:io' show GZipCodec;
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/nai_special_tags.dart';
import '../models/tag_models.dart';
import 'isolated_compute.dart';
import 'prompt_library_service.dart';
import 'tag_dictionary_update_service.dart';

/// 内部词条结构 (内存极简化存储，节省内存开销；查询用的小写/空格形态在解析时一次性预计算)
class _DictEntry {
  final String tag;
  final String tagLower; // 小写形态 (查询预匹配)
  final String tagSpaced; // 下划线转空格的小写形态 (查询预匹配)
  final int count;
  final double popularityBoost; // 基于热度的对数加权 (解析期预计算)
  final String? zh;
  final String zhLower; // 中文释义小写形态 (中文查询预匹配)
  final List<String> aliases;
  final DanbooruTagCategory category;

  /// NovelAI 官方专属词条的分组胶囊文案 (Danbooru 词条为 null)
  final String? specialLabel;

  const _DictEntry({
    required this.tag,
    required this.tagLower,
    required this.tagSpaced,
    required this.count,
    this.popularityBoost = 0.0,
    this.zh,
    this.zhLower = '',
    this.aliases = const [],
    this.category = DanbooruTagCategory.general,
    this.specialLabel,
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

    List<String> aliases = const <String>[];
    if (f.length > 3 && f[3].trim().isNotEmpty) {
      final parsedAliases = <String>[];
      for (final a in f[3].split(',')) {
        final trimmed = a.trim();
        if (trimmed.isNotEmpty) parsedAliases.add(trimmed);
      }
      if (parsedAliases.isNotEmpty) aliases = parsedAliases;
    }

    // 分类：优先读取第 5 列官方 Danbooru 分类 ID (0/1/3/4/5)，
    // 旧版 4 列词库缺失时退回启发式推断
    final cat = f.length > 4
        ? DanbooruTagCategory.fromCode(f[4])
        : _inferCategory(tag);

    // 内存优化：已是全小写/无下划线的形态直接复用同一字符串引用，
    // 避免 30 万级词条各自多拷贝两份字符串
    final lowered = tag.toLowerCase();
    final tagLower = tag == lowered ? tag : lowered;
    final tagSpaced = tagLower.contains('_')
        ? tagLower.replaceAll('_', ' ')
        : tagLower;
    final popularityBoost = count > 0 ? (math.log(count + 1) * 8.0) : 0.0;

    list.add(
      _DictEntry(
        tag: tag,
        tagLower: tagLower,
        tagSpaced: tagSpaced,
        count: count,
        popularityBoost: popularityBoost,
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

// ==================== NovelAI 官方专属词条 ====================
//
// 官方文档 (docs.novelai.net/en/image/tags) 定义的 Quality / Aesthetic /
// Complexity / Dataset / Alpha / Renamed / Other 专属标签在 Danbooru 词库中
// 完全不存在，此处转成与 Danbooru 同构的词条参与统一扫描，使标签补全、
// 灵感库、提示词高亮与 Agent 离线检索一次性全部获得官方专属词。

/// NovelAI 专属词条的词典视图 (年代标签 year XXXX 为动态合成，不在此列)
final List<_DictEntry> _naiSpecialEntries = [
  for (final t in kNaiSpecialTags)
    _DictEntry(
      tag: t.tag,
      tagLower: t.tag,
      tagSpaced: t.tag,
      count: 0,
      zh: t.displayZh,
      zhLower: t.displayZh.toLowerCase(),
      aliases: t.aliases,
      category: t.category,
      specialLabel: t.group.pillLabel,
    ),
];

/// 官方专属词条的等效热度加权
///
/// 专属词条在 Danbooru 词库里没有热度计数 (postCount = 0)，不加权就会被任何
/// 有热度的同档位词条挤到末尾 (输入 best 时 best quality 会排在 bestiality 之后)。
/// 此处按「等效 10 万热度」加权 (log(1e5) × 8 ≈ 92)：胜过冷门 Danbooru 词条，
/// 但仍让位于 long hair (616 万) / looking at viewer (487 万) 这类超高频词，
/// 因此短前缀查询的热度排序不会被破坏 (加权只影响总分，不影响展示计数)。
const double _kNaiSpecialBoost = 92.0;

/// 年代标签候选下界 (上界取当前年份，任意年份官方均可用)
const int _kOldestYearTag = 1900;

// ==================== 后台检索 Isolate (阶段2 性能治理) ====================
//
// 32 万词条的解压、解析与线性扫描全部留在常驻 worker isolate 内部：
// 主线程仅保留轻量反查表 (_tagToZh / _tagToCat)，零全表滞留、零跨 isolate 复制。
// worker 不可用时 (启动失败或测试 FakeAsync 环境) 自动退回兼容路径。

/// 可跨 Isolate 传输的词库源 (原始 TSV 文本或 gzip 压缩资产字节)
class _DictSource {
  final String? tsv;
  final IsolateBytes? gzipBytes;

  const _DictSource.tsv(String this.tsv) : gzipBytes = null;
  const _DictSource.gzip(IsolateBytes this.gzipBytes) : tsv = null;

  List<_DictEntry> parse() {
    final text =
        tsv ?? utf8.decode(GZipCodec().decode(gzipBytes!.materialize()));
    return _parseDanbooruTsv(text);
  }
}

/// 由词条表构建轻量中英文反查哈希表 (复用已预计算的 tagSpaced)
({Map<String, String> tagToZh, Map<String, DanbooruTagCategory> tagToCat})
_buildLookupMaps(List<_DictEntry> parsed) {
  final tagToZh = <String, String>{};
  final tagToCat = <String, DanbooruTagCategory>{};
  for (final entry in parsed) {
    final cleanTag = entry.tagSpaced;
    if (entry.zh != null) {
      tagToZh[cleanTag] = entry.zh!;
    }
    tagToCat[cleanTag] = entry.category;
  }
  return (tagToZh: tagToZh, tagToCat: tagToCat);
}

List<_DictEntry> _parseDictSourceTask(_DictSource source) => source.parse();

/// worker 词库加载/热替换请求：由 worker 自行解压解析并建反查表
class _SearchLoadSource {
  final int id;
  final _DictSource source;
  const _SearchLoadSource(this.id, this.source);
}

/// 将此前主线程已解析的词条迁移进新启动的 worker
class _SearchSetEntries {
  final List<_DictEntry> entries;
  const _SearchSetEntries(this.entries);
}

/// 运行期切回主线程兜底检索时按需导出现有词条
class _SearchDumpEntries {
  final int id;
  const _SearchDumpEntries(this.id);
}

/// 词库加载完成回投给主线程的轻量摘要 (仅条目数 + 反查映射)
class _DictLoadedReply {
  final int id;
  final int entryCount;
  final Map<String, String> tagToZh;
  final Map<String, DanbooruTagCategory> tagToCat;
  const _DictLoadedReply(
    this.id,
    this.entryCount,
    this.tagToZh,
    this.tagToCat,
  );
}

/// 词库在 worker 内加载失败的异常通知
class _DictLoadError {
  final int id;
  final String error;
  const _DictLoadError(this.id, this.error);
}

/// 导出的词条回投
class _SearchEntriesReply {
  final int id;
  final List<_DictEntry> entries;
  const _SearchEntriesReply(this.id, this.entries);
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

/// 常驻检索 isolate 主入口：持有唯一词条全表，逐请求扫描 Top-K
void _searchIsolateMain(SendPort replyPort) {
  List<_DictEntry> entries = const [];
  final command = ReceivePort();
  replyPort.send(command.sendPort);
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
      replyPort.send(_SearchReply(message.id, results));
    } else if (message is _SearchLoadSource) {
      try {
        entries = message.source.parse();
        final maps = _buildLookupMaps(entries);
        replyPort.send(
          _DictLoadedReply(
            message.id,
            entries.length,
            maps.tagToZh,
            maps.tagToCat,
          ),
        );
      } catch (e, st) {
        replyPort.send(_DictLoadError(message.id, '$e\n$st'));
      }
    } else if (message is _SearchSetEntries) {
      entries = message.entries;
    } else if (message is _SearchDumpEntries) {
      replyPort.send(_SearchEntriesReply(message.id, entries));
    }
  });
}

class _ScoredMatch {
  final _DictEntry entry;
  final double score;
  final String? matchedAlias;
  final int order;

  const _ScoredMatch(this.entry, this.score, this.matchedAlias, this.order);

  TagSuggestion toSuggestion() => TagSuggestion(
        tag: entry.tagSpaced,
        category: entry.category,
        postCount: entry.count,
        translation: entry.zh,
        aliases: entry.aliases,
        matchedAlias: matchedAlias,
        score: score,
        customCategoryLabel: entry.specialLabel,
      );
}

bool _isWorseMatch(_ScoredMatch a, _ScoredMatch b) =>
    a.score != b.score ? a.score < b.score : a.order > b.order;

void _topKHeapPush(List<_ScoredMatch> heap, _ScoredMatch item) {
  var i = heap.length;
  heap.add(item);
  while (i > 0) {
    final p = (i - 1) >> 1;
    if (!_isWorseMatch(heap[i], heap[p])) break;
    final tmp = heap[i];
    heap[i] = heap[p];
    heap[p] = tmp;
    i = p;
  }
}

void _topKHeapReplaceRoot(List<_ScoredMatch> heap, _ScoredMatch item) {
  heap[0] = item;
  final len = heap.length;
  var i = 0;
  while (true) {
    final l = (i << 1) + 1;
    if (l >= len) break;
    final r = l + 1;
    final w = (r < len && _isWorseMatch(heap[r], heap[l])) ? r : l;
    if (!_isWorseMatch(heap[w], heap[i])) break;
    final tmp = heap[i];
    heap[i] = heap[w];
    heap[w] = tmp;
    i = w;
  }
}

({double score, String? matchedAlias}) _scoreDictEntry(
  _DictEntry e,
  String rawQ,
  String qUnderscore,
  String qSpace,
  bool isCjk, {
  required bool isSpecial,
}) {
  final tagUnder = e.tagLower;
  final tagSpace = e.tagSpaced;
  final zh = e.zhLower;

  if (isCjk) {
    if (zh.startsWith(rawQ)) return (score: 1000.0, matchedAlias: null);
    if (zh.contains(rawQ)) return (score: 600.0, matchedAlias: null);
    return const (score: 0.0, matchedAlias: null);
  }

  if (tagUnder == qUnderscore || tagSpace == qSpace) {
    return const (score: 1500.0, matchedAlias: null);
  }
  if (tagUnder.startsWith(qUnderscore) || tagSpace.startsWith(qSpace)) {
    return const (score: 1000.0, matchedAlias: null);
  }
  if (tagUnder.contains(qUnderscore) || tagSpace.contains(qSpace)) {
    return const (score: 400.0, matchedAlias: null);
  }
  if (isSpecial) {
    final aliasHit = _matchAlias(e.aliases, rawQ, qUnderscore);
    final zhHit = zh.contains(rawQ) ? 300.0 : 0.0;
    if (aliasHit != null && aliasHit.$2 >= zhHit) {
      return (score: aliasHit.$2, matchedAlias: aliasHit.$1);
    }
    return (score: zhHit, matchedAlias: null);
  }
  if (zh.contains(rawQ)) {
    return const (score: 300.0, matchedAlias: null);
  }
  final aliasHit = _matchAlias(e.aliases, rawQ, qUnderscore);
  if (aliasHit != null) {
    return (score: aliasHit.$2, matchedAlias: aliasHit.$1);
  }
  return const (score: 0.0, matchedAlias: null);
}

/// 词条线性扫描与有界 Top-K 打分 (后台 isolate 与主线程兜底共用同一实现)
List<TagSuggestion> _scanEntries(
  List<_DictEntry> entries,
  String rawQ, {
  DanbooruTagCategory? category,
  int limit = 10,
}) {
  if (limit <= 0) return const [];

  final qUnderscore = rawQ.replaceAll(' ', '_');
  final qSpace = rawQ.replaceAll('_', ' ');
  final isCjk = rawQ.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);

  // 先扫描少量 NovelAI 官方专属词条，记录需要与 Danbooru 同名合并的标签集合
  final specialMatches = <TagSuggestion>[];
  final specialTagSet = <String>{};
  for (final e in _naiSpecialEntries) {
    if (category != null && e.category != category) continue;
    final hit = _scoreDictEntry(
      e,
      rawQ,
      qUnderscore,
      qSpace,
      isCjk,
      isSpecial: true,
    );
    if (hit.score > 0) {
      final totalScore = hit.score + e.popularityBoost + _kNaiSpecialBoost;
      specialTagSet.add(e.tagSpaced);
      specialMatches.add(
        TagSuggestion(
          tag: e.tagSpaced,
          category: e.category,
          postCount: e.count,
          translation: e.zh,
          aliases: e.aliases,
          matchedAlias: hit.matchedAlias,
          score: totalScore,
          customCategoryLabel: e.specialLabel,
        ),
      );
    }
  }

  // 主词典维持容量为 limit 的最小堆：未进入 Top-K 的低分命中直接丢弃，零对象分配
  final heap = <_ScoredMatch>[];
  final specialDanbooruMerges = <TagSuggestion>[];
  for (var i = 0; i < entries.length; i++) {
    final e = entries[i];
    if (category != null && e.category != category) continue;
    final hit = _scoreDictEntry(
      e,
      rawQ,
      qUnderscore,
      qSpace,
      isCjk,
      isSpecial: false,
    );
    if (hit.score <= 0) continue;

    final totalScore = hit.score + e.popularityBoost;
    if (specialTagSet.isNotEmpty && specialTagSet.contains(e.tagSpaced)) {
      specialDanbooruMerges.add(
        TagSuggestion(
          tag: e.tagSpaced,
          category: e.category,
          postCount: e.count,
          translation: e.zh,
          aliases: e.aliases,
          matchedAlias: hit.matchedAlias,
          score: totalScore,
          customCategoryLabel: e.specialLabel,
        ),
      );
      continue;
    }

    if (heap.length < limit) {
      _topKHeapPush(heap, _ScoredMatch(e, totalScore, hit.matchedAlias, i));
    } else {
      final worst = heap[0];
      if (totalScore > worst.score ||
          (totalScore == worst.score && i < worst.order)) {
        _topKHeapReplaceRoot(
          heap,
          _ScoredMatch(e, totalScore, hit.matchedAlias, i),
        );
      }
    }
  }

  // 按扫描顺序排好 Top-K，确保后续合并与稳定排序与全量扫描 100% 一致
  heap.sort((a, b) => a.order.compareTo(b.order));
  final combined = <TagSuggestion>[
    ...specialDanbooruMerges,
    for (final m in heap) m.toSuggestion(),
    ...specialMatches,
  ];
  final results = _dedupeSuggestions(combined);
  results.sort((a, b) => b.score.compareTo(a.score));
  return results.take(limit).toList();
}

/// 别名匹配：返回命中别名与其档位分数 (前缀命中 800 / 包含命中 250)
(String, double)? _matchAlias(
  List<String> aliases,
  String rawQ,
  String qUnderscore,
) {
  for (final a in aliases) {
    final aLower = a.toLowerCase();
    if (aLower.startsWith(rawQ) || aLower.startsWith(qUnderscore)) {
      return (a, 800.0);
    } else if (aLower.contains(rawQ)) {
      return (a, 250.0);
    }
  }
  return null;
}

/// 同名词条去重 (Danbooru 词库 / NovelAI 专属清单 / 年代合成 / 词组合)
///
/// `transparent background`、`alpha transparency` 等词条两侧都有：保留携带官方
/// 分组胶囊与模型可用范围说明的专属词条，并合并 Danbooru 侧的热度计数与别名。
List<TagSuggestion> _dedupeSuggestions(List<TagSuggestion> matches) {
  final byTag = <String, TagSuggestion>{};
  for (final m in matches) {
    final prev = byTag[m.tag];
    byTag[m.tag] = prev == null ? m : _mergeSuggestions(prev, m);
  }
  return byTag.values.toList();
}

TagSuggestion _mergeSuggestions(TagSuggestion a, TagSuggestion b) {
  final keep = a.customCategoryLabel != null ? a : b;
  final other = identical(keep, a) ? b : a;
  return TagSuggestion(
    tag: keep.tag,
    category: keep.category,
    postCount: math.max(keep.postCount, other.postCount),
    translation: (keep.translation?.isNotEmpty ?? false)
        ? keep.translation
        : other.translation,
    aliases: keep.aliases.isNotEmpty ? keep.aliases : other.aliases,
    matchedAlias: keep.matchedAlias ?? other.matchedAlias,
    score: math.max(keep.score, other.score),
    insertText: keep.insertText ?? other.insertText,
    customCategoryLabel: keep.customCategoryLabel ?? other.customCategoryLabel,
    isPromptCombo: keep.isPromptCombo || other.isPromptCombo,
  );
}

/// 年代标签 (`year XXXX`) 动态合成
///
/// 官方文档：XXXX 可为任意年份，词典无法穷举，故按查询前缀实时生成候选并
/// 近年优先。支持 `year` / `year 20` / `year 2014` / `year_2014` 与中文 `年*`。
List<TagSuggestion> _yearTagMatches(
  String rawQ,
  int limit, {
  DanbooruTagCategory? category,
}) {
  if (category != null && category != DanbooruTagCategory.meta) {
    return const [];
  }

  final q = rawQ.replaceAll('_', ' ').trim();
  final match = RegExp(r'^year\s*(\d{0,4})$').firstMatch(q);
  final String digits;
  if (match != null) {
    digits = match.group(1) ?? '';
  } else if (q.startsWith('年')) {
    digits = ''; // 中文「年 / 年代 / 年份」
  } else {
    return const [];
  }

  if (digits.length == 4) return [_yearSuggestion(digits, exact: true)];

  final results = <TagSuggestion>[];
  for (
    var year = DateTime.now().year;
    year >= _kOldestYearTag && results.length < limit;
    year--
  ) {
    if ('$year'.startsWith(digits)) {
      results.add(_yearSuggestion('$year', exact: false));
    }
  }
  return results;
}

/// 单条年代建议：[exact] 为真表示查询已给出完整四位年份 (精确档)，
/// 否则仅是 `year` / `year 20` 这类前缀查询 (前缀档，不越级抬高)
TagSuggestion _yearSuggestion(String year, {required bool exact}) {
  final tag = 'year $year';
  return TagSuggestion(
    tag: tag,
    category: DanbooruTagCategory.meta,
    customCategoryLabel: NaiSpecialTagGroup.year.pillLabel,
    translation: naiYearTagTranslation(tag),
    // 同档位内以年份新近度决定先后
    score:
        (exact ? 1500.0 : 1000.0) + _kNaiSpecialBoost + int.parse(year) * 0.001,
  );
}

/// Danbooru 本地离线标签词典服务 (单例模式)
class TagDictionaryService {
  static final TagDictionaryService instance = TagDictionaryService._();

  TagDictionaryService._() {
    // 官方专属词条先入反查表，词库加载/热替换后再覆盖一次
    _seedSpecialLookups();
  }

  /// 后台检索 Isolate 开关：
  /// 生产环境默认开启 (32 万条扫描不占 UI 主线程)；
  /// widget 测试的 FakeAsync 环境无法处理真实 Isolate 回投，
  /// 相关测试在 setUp 中置 false 退回主线程同步扫描。
  static bool backgroundSearchEnabled = true;

  List<_DictEntry>? _entries;
  bool _loaded = false;
  bool _loadedFromInstalled = false;
  int _entryCount = 0;
  int _revision = 0;
  Future<void> _replaceQueue = Future.value();

  @visibleForTesting
  int get retainedMainEntryCount => _entries?.length ?? 0;

  /// 是否已直接加载磁盘中已安装的在线更新词库 (用于跳过启动阶段二次重复解析)
  bool get loadedFromInstalled => _loadedFromInstalled;

  final Map<String, String> _tagToZh = {};
  final Map<String, DanbooruTagCategory> _tagToCat = {};

  // ---- 后台检索 worker isolate 状态 ----
  ReceivePort? _workerPort;
  ReceivePort? _workerErrorPort;
  Completer<void>? _workerReady;
  SendPort? _workerCommandPort;
  Isolate? _workerIsolate;
  Future<void>? _workerBoot;
  bool _workerBroken = false;
  final Map<int, Completer<List<TagSuggestion>>> _pendingSearches = {};
  final Map<int, Completer<_DictLoadedReply>> _pendingLoads = {};
  final Map<int, Completer<List<_DictEntry>>> _pendingDumps = {};
  int _searchSeq = 0;

  Future<void>? _loadingFuture;
  bool get isLoaded => _loaded;
  int get count => _entryCount;
  int get revision => _revision;

  // 查询结果缓存 (超过容量上限整表清空，防止长会话无界增长)
  static const int _cacheCapacity = 500;
  final Map<String, List<TagSuggestion>> _queryCache = {};

  /// 预热并异步加载词库 (优先直接读取已安装在线词库，否则解压加载内置 gz 资产)
  Future<void> ensureLoaded({String? rawTsvContent}) async {
    if (_loaded) return;
    return _loadingFuture ??= _load(rawTsvContent);
  }

  /// 清空查询结果缓存 (词库内容变更后调用，防止陈旧建议残留)
  void clearQueryCache() => _queryCache.clear();

  /// 用外部下载的新词库内容整体热替换当前词库 (在线更新完成后调用)
  Future<void> replaceWithContent(
    String rawTsv, {
    bool fromInstalled = false,
  }) {
    final task = _replaceQueue.catchError((Object _) {}).then((_) async {
      await _loadingFuture;
      await _workerBoot;
      await _applyDictSource(
        _DictSource.tsv(rawTsv),
        fromInstalled: fromInstalled,
      );
    });
    _replaceQueue = task;
    return task;
  }

  Future<_DictSource?> _resolveDefaultSource() async {
    final installed =
        await TagDictionaryUpdateService.instance.readInstalledTsvIfPresent();
    if (installed != null) {
      _loadedFromInstalled = true;
      return _DictSource.tsv(installed);
    }
    _loadedFromInstalled = false;
    final data = await rootBundle.load('assets/danbooru.tsv.gz');
    final compressed = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    return _DictSource.gzip(IsolateBytes(compressed));
  }

  Future<void> _load(String? rawContent) async {
    try {
      late final _DictSource source;
      var fromInstalled = false;
      if (rawContent != null) {
        source = _DictSource.tsv(rawContent);
      } else {
        final resolved = await _resolveDefaultSource();
        if (resolved == null) {
          _entries = [];
          _loaded = true;
          return;
        }
        source = resolved;
        fromInstalled = _loadedFromInstalled;
      }
      await _applyDictSource(source, fromInstalled: fromInstalled);
    } catch (e) {
      debugPrint('[TagDictionaryService] 词库加载失败或资产未找到: $e');
      _entries = [];
      _loaded = true;
      _loadedFromInstalled = false;
    }
  }

  Future<void> _applyDictSource(
    _DictSource source, {
    required bool fromInstalled,
  }) async {
    if (await _ensureSearchWorker()) {
      final command = _workerCommandPort;
      if (command != null) {
        final loadId = ++_searchSeq;
        final completer = Completer<_DictLoadedReply>();
        _pendingLoads[loadId] = completer;
        command.send(_SearchLoadSource(loadId, source));
        try {
          final reply = await completer.future.timeout(
            const Duration(seconds: 30),
          );
          _applyLookupMaps(reply.tagToZh, reply.tagToCat);
          _entries = null;
          _entryCount = reply.entryCount;
          _loadedFromInstalled = fromInstalled;
          _loaded = true;
          _revision++;
          _queryCache.clear();
          return;
        } catch (e) {
          _pendingLoads.remove(loadId);
          debugPrint('[TagDictionaryService] worker 加载失败，回退主线程解析: $e');
          _failSearchWorker();
        }
      }
    }

    // worker 禁用 (FakeAsync 测试) 或不可用时的兼容路径
    final List<_DictEntry> parsed;
    if (!backgroundSearchEnabled &&
        source.tsv != null &&
        source.tsv!.length < 65536) {
      parsed = source.parse();
    } else {
      parsed = await runIsolated(_parseDictSourceTask, source);
    }
    _entries = parsed;
    _entryCount = parsed.length;
    _loadedFromInstalled = fromInstalled;
    _loaded = true;
    _revision++;
    _queryCache.clear();
    _rebuildLookupMaps(parsed);
  }

  void _applyLookupMaps(
    Map<String, String> tagToZh,
    Map<String, DanbooruTagCategory> tagToCat,
  ) {
    _tagToZh
      ..clear()
      ..addAll(tagToZh);
    _tagToCat
      ..clear()
      ..addAll(tagToCat);
    // NovelAI 官方专属词条覆盖同名 Danbooru 释义 (携带官方语义与模型可用范围)
    _seedSpecialLookups();
  }

  void _rebuildLookupMaps(List<_DictEntry> parsed) {
    final maps = _buildLookupMaps(parsed);
    _applyLookupMaps(maps.tagToZh, maps.tagToCat);
  }

  /// 将官方专属标签写入反查表 (提示词高亮的中文释义与分类着色)
  void _seedSpecialLookups() {
    for (final t in kNaiSpecialTags) {
      final key = t.tag.toLowerCase();
      _tagToZh[key] = t.displayZh;
      _tagToCat[key] = t.category;
    }
  }

  /// 快速查询标签中文释义
  String? translationOf(String tagName) {
    final key = tagName.trim().replaceAll('_', ' ').toLowerCase();
    // 年代标签 (year XXXX) 为动态词条，不入反查表
    return _tagToZh[key] ?? naiYearTagTranslation(key);
  }

  /// 快速查询标签分类
  DanbooruTagCategory? categoryOf(String tagName) {
    final key = tagName.trim().replaceAll('_', ' ').toLowerCase();
    final hit = _tagToCat[key];
    if (hit != null) return hit;
    return parseNaiYearTag(key) == null ? null : DanbooruTagCategory.meta;
  }

  // ==================== 后台检索 worker 管理 ====================

  /// 确保后台检索 worker 已就绪 (幂等；不可用时返回 false)
  Future<bool> _ensureSearchWorker() async {
    if (!backgroundSearchEnabled || _workerBroken) return false;
    if (_workerCommandPort == null) {
      final boot = _workerBoot ??= _bootSearchWorker();
      await boot;
      _workerBoot = null;
    }
    final command = _workerCommandPort;
    if (command == null || _workerBroken) return false;

    // 若此前已在禁用后台检索状态下在主线程加载过词条，切换开启时同步迁移到 worker
    final mainEntries = _entries;
    if (mainEntries != null) {
      if (mainEntries.isNotEmpty) {
        command.send(_SearchSetEntries(mainEntries));
      }
      _entries = null;
    }
    return true;
  }

  /// 启动常驻检索 isolate 并等待指令端口就绪 (不拷贝全表，毫秒级就绪)
  Future<void> _bootSearchWorker() async {
    final port = ReceivePort();
    final errorPort = ReceivePort();
    final ready = Completer<void>();
    _workerReady = ready;
    _workerErrorPort = errorPort;

    Isolate? spawned;
    try {
      spawned = await Isolate.spawn(
        _searchIsolateMain,
        port.sendPort,
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
    port.listen(_onWorkerMessage);
    errorPort.listen((_) => _failSearchWorker());

    // 就绪等待保险丝：超时则永久回退主线程 (正常情况下毫秒级就绪)
    try {
      await ready.future.timeout(const Duration(seconds: 2));
    } on TimeoutException {
      debugPrint('[TagDictionaryService] 检索 isolate 就绪超时，回退主线程');
      _failSearchWorker();
    }
  }

  void _onWorkerMessage(Object? message) {
    if (message is SendPort) {
      _workerCommandPort = message;
      final ready = _workerReady;
      if (ready != null && !ready.isCompleted) ready.complete();
    } else if (message is _SearchReply) {
      final completer = _pendingSearches.remove(message.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message.results);
      }
    } else if (message is _DictLoadedReply) {
      final completer = _pendingLoads.remove(message.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message);
      }
    } else if (message is _DictLoadError) {
      final completer = _pendingLoads.remove(message.id);
      if (completer != null && !completer.isCompleted) {
        completer.completeError(StateError(message.error));
      }
    } else if (message is _SearchEntriesReply) {
      final completer = _pendingDumps.remove(message.id);
      if (completer != null && !completer.isCompleted) {
        completer.complete(message.entries);
      }
    }
  }

  /// worker 损坏：后续按需走孤立解析兜底，唤醒所有挂起请求
  void _failSearchWorker() {
    if (_workerBroken) return;
    _workerBroken = true;
    _workerCommandPort = null;
    _workerPort?.close();
    _workerPort = null;
    _workerErrorPort?.close();
    _workerErrorPort = null;
    _workerIsolate?.kill(priority: Isolate.immediate);
    _workerIsolate = null;
    final pendingSearches = List.of(_pendingSearches.values);
    _pendingSearches.clear();
    for (final c in pendingSearches) {
      if (!c.isCompleted) c.completeError(StateError('检索 isolate 不可用'));
    }
    final pendingLoads = List.of(_pendingLoads.values);
    _pendingLoads.clear();
    for (final c in pendingLoads) {
      if (!c.isCompleted) c.completeError(StateError('检索 isolate 不可用'));
    }
    final pendingDumps = List.of(_pendingDumps.values);
    _pendingDumps.clear();
    for (final c in pendingDumps) {
      if (!c.isCompleted) c.completeError(StateError('检索 isolate 不可用'));
    }
  }

  /// 经后台 worker 检索：返回 null 表示不可用/超时，调用方走兜底路径
  Future<List<TagSuggestion>?> _searchViaWorker(
    String rawQ,
    DanbooruTagCategory? category,
    int limit,
  ) async {
    if (!backgroundSearchEnabled || _workerBroken) return null;
    try {
      if (!await _ensureSearchWorker()) return null;
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

  Future<List<TagSuggestion>> _fallbackSearch(
    String rawQ,
    DanbooruTagCategory? category,
    int limit,
  ) async {
    final entries = _entries;
    if (entries != null) {
      return _scanEntries(entries, rawQ, category: category, limit: limit);
    }

    // 测试切关 backgroundSearchEnabled 时主线程无全表，从存活 worker 临时导出并主线程扫描
    final command = _workerCommandPort;
    if (!_workerBroken && command != null) {
      final dumpId = ++_searchSeq;
      final completer = Completer<List<_DictEntry>>();
      _pendingDumps[dumpId] = completer;
      command.send(_SearchDumpEntries(dumpId));
      try {
        final exported = await completer.future.timeout(
          const Duration(seconds: 5),
        );
        return _scanEntries(exported, rawQ, category: category, limit: limit);
      } catch (_) {
        _pendingDumps.remove(dumpId);
      }
    }

    // 生产 worker 崩溃兜底：按需在独立 isolate 重新读取压缩资产或已安装词库扫描，主线程不滞留原始文本
    final source = await _resolveDefaultSource();
    if (source == null) {
      return _scanEntries(const [], rawQ, category: category, limit: limit);
    }
    return runIsolated(_fallbackSearchSourceTask, (
      source: source,
      query: rawQ,
      category: category,
      limit: limit,
    ));
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

    // 2. 年代标签 (year XXXX) 动态合成：官方任意年份可用，词典无法穷举
    final yearMatches = _yearTagMatches(rawQ, limit, category: category);

    await ensureLoaded();
    final revision = _revision;
    if (_entryCount == 0) {
      // 词库缺失/为空时仍扫描官方专属清单 (传空词条表即可命中专属词)
      final specialMatches = _scanEntries(
        const [],
        rawQ,
        category: category,
        limit: limit,
      );
      final fallback = _dedupeSuggestions([
        ...comboMatches,
        ...yearMatches,
        ...specialMatches,
      ])..sort((a, b) => b.score.compareTo(a.score));
      return fallback.take(limit).toList();
    }

    final cacheKey =
        '$rawQ|${category?.code ?? -1}|$limit|$includePromptCombos';
    final hit = _queryCache[cacheKey];
    if (hit != null) return hit;

    // 3. 32 万词条线性扫描优先在后台 isolate 执行 (不占 UI 主线程)；
    //    worker 不可用时主线程同步兑底 (行为与旧实现完全一致)
    final workerMatches = await _searchViaWorker(rawQ, category, limit);
    final dictMatches =
        workerMatches ?? await _fallbackSearch(rawQ, category, limit);
    if (revision != _revision) {
      return search(
        query,
        limit: limit,
        category: category,
        includePromptCombos: includePromptCombos,
      );
    }

    // 所有条目 (词组合 + 年代合成 + Danbooru 词典 + 官方专属词) 参与公平打分排序
    final matches = _dedupeSuggestions([
      ...comboMatches,
      ...yearMatches,
      ...dictMatches,
    ]);
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

List<TagSuggestion> _fallbackSearchSourceTask(
  ({
    _DictSource source,
    String query,
    DanbooruTagCategory? category,
    int limit,
  })
  task,
) => _scanEntries(
  task.source.parse(),
  task.query,
  category: task.category,
  limit: task.limit,
);
