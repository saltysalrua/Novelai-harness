import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data' show BytesBuilder;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sqlite3/sqlite3.dart';
import 'tag_dictionary_service.dart';

/// 词库主表数据源：ffdkj 每日构建的 Danbooru 标签中英文对照表 (post_count>=10 全收录)
const String kTagSqliteUrl =
    'https://raw.githubusercontent.com/ffdkj/'
    'ffdkj-Danbooru_Tag-Chinese-English-Translation-Table/main/tag.sqlite';

/// 别名数据源：Danbooru 官方 active 别名 API
const String kDanbooruAliasApi = 'https://danbooru.donmai.us/tag_aliases.json';

/// 已安装词库的元信息 (持久化在应用数据目录 tagdict/meta.json)
class TagDictMeta {
  const TagDictMeta({
    required this.entryCount,
    required this.etag,
    required this.installedAt,
    required this.lastCheckAt,
  });

  final int entryCount;
  final String etag;
  final DateTime installedAt;
  final DateTime lastCheckAt;

  Map<String, dynamic> toJson() => {
    'entryCount': entryCount,
    'etag': etag,
    'installedAt': installedAt.toIso8601String(),
    'lastCheckAt': lastCheckAt.toIso8601String(),
  };

  static TagDictMeta? fromJson(Map<String, dynamic> json) {
    final count = json['entryCount'];
    final etag = json['etag'];
    final installed = DateTime.tryParse(json['installedAt'] ?? '');
    final lastCheck = DateTime.tryParse(json['lastCheckAt'] ?? '');
    if (count is! int || etag is! String || installed == null) return null;
    // 兼容旧版本存储的弱校验前缀 (W/")，统一为规范形式
    final normalizedEtag = etag.startsWith('W/') ? etag.substring(2) : etag;
    return TagDictMeta(
      entryCount: count,
      etag: normalizedEtag,
      installedAt: installed,
      lastCheckAt: lastCheck ?? installed,
    );
  }
}

/// 一次词库更新的结果
class TagDictUpdateResult {
  const TagDictUpdateResult({
    required this.success,
    required this.message,
    this.upToDate = false,
    this.entryCount = 0,
  });

  final bool success;
  final String message;
  final bool upToDate;
  final int entryCount;
}

/// 单个标签行 (sqlite 读取结果的纯数据形态，便于合并与测试)
@immutable
class TagRow {
  const TagRow(this.name, this.category, this.cn, this.count);

  final String name;
  final int category;
  final String cn;
  final int count;
}

/// 把标签行与别名映射合并为 TSV 文本 (name/count/中文/aliases/category 五列)
/// 纯函数：词库构建 isolate 与单元测试共用，保证行为一致。
String buildTagTsv(Iterable<TagRow> rows, Map<String, List<String>> aliasMap) {
  final list = rows.toList()..sort((a, b) => b.count.compareTo(a.count));
  final buffer = StringBuffer();
  for (final r in list) {
    if (r.name.isEmpty || r.name.contains('\t') || r.name.contains('\n')) {
      continue;
    }
    final cn = r.cn.replaceAll('\t', ' ').replaceAll('\n', ' ').trim();
    final aliases = (aliasMap[r.name] ?? const <String>[]).toSet().toList()
      ..sort();
    final aliasText = aliases.take(10).where((a) => a != r.name).join(',');
    buffer.write(r.name);
    buffer.write('\t');
    buffer.write(r.count);
    buffer.write('\t');
    buffer.write(cn);
    buffer.write('\t');
    buffer.write(aliasText);
    buffer.write('\t');
    buffer.write(r.category);
    buffer.write('\n');
  }
  return buffer.toString();
}

/// 从别名缓存 TSV 文本解析出 consequent -> antecedents 映射
Map<String, List<String>> parseAliasCache(String raw) {
  final map = <String, List<String>>{};
  for (final line in const LineSplitter().convert(raw)) {
    final tab = line.indexOf('\t');
    if (tab <= 0) continue;
    final ant = line.substring(0, tab).trim();
    final con = line.substring(tab + 1).trim();
    if (ant.isEmpty || con.isEmpty || ant == con) continue;
    map.putIfAbsent(con, () => []).add(ant);
  }
  return map;
}

/// 后台 isolate 输入 (sqlite 临时文件路径 + 原始别名对列表)
class _BuildInput {
  const _BuildInput(this.sqlitePath, this.aliasPairs);

  final String sqlitePath;
  final List<List<String>> aliasPairs;
}

/// 后台 isolate 顶层函数：读取 sqlite 词库并构建 TSV 文本
_BuildOutput _buildTsvFromSqlite(_BuildInput input) {
  final db = sqlite3.open(input.sqlitePath, mode: OpenMode.readOnly);
  try {
    final rows = <TagRow>[];
    final tagNames = <String>{};
    for (final row in db.select(
      'SELECT name, category, cn_name, post_count FROM tags',
    )) {
      final name = row['name'] as String?;
      if (name == null || name.isEmpty) continue;
      final category = row['category'] as int? ?? 0;
      final cn = row['cn_name'] as String? ?? '';
      final count = row['post_count'] as int? ?? 0;
      rows.add(TagRow(name, category, cn, count));
      tagNames.add(name);
    }

    // 别名挂到正式标签名下；antecedent 本身也是正式标签的跳过 (避免重复条目)
    final aliasMap = <String, List<String>>{};
    for (final pair in input.aliasPairs) {
      final ant = pair[0];
      final con = pair[1];
      if (ant == con || tagNames.contains(ant) || !tagNames.contains(con)) {
        continue;
      }
      aliasMap.putIfAbsent(con, () => []).add(ant);
    }

    final tsv = buildTagTsv(rows, aliasMap);
    return _BuildOutput(tsv, rows.length);
  } finally {
    db.dispose();
  }
}

class _BuildOutput {
  const _BuildOutput(this.tsv, this.entryCount);

  final String tsv;
  final int entryCount;
}

/// Danbooru 在线词库更新服务 (单例)：
/// 下载 ffdkj 每日构建的 tag.sqlite + Danbooru 官方别名表，
/// 在后台 isolate 重建 TSV 词库并热替换进 TagDictionaryService。
class TagDictionaryUpdateService {
  TagDictionaryUpdateService._();

  static final TagDictionaryUpdateService instance =
      TagDictionaryUpdateService._();

  /// 测试注入点：HTTP 客户端与存储目录
  @visibleForTesting
  http.Client? httpClient;

  @visibleForTesting
  Directory? baseDirOverride;

  http.Client get _client => httpClient ?? http.Client();

  /// 单飞锁：同一时刻只允许一个更新流程在跑
  /// (防止启动自动更新与手动点击并发，争抢同一临时文件导致
  ///  SqliteException(14): 手动流程 open 的临时文件已被另一流程的
  ///  finally 清理删除)
  Future<TagDictUpdateResult>? _inFlightUpdate;

  /// 规范化 ETag：剔除弱校验前缀 W/，避免同一内容因强/弱形式切换
  /// 而被误判为新版本触发无谓下载
  static String? _normalizeEtag(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    final trimmed = raw.trim();
    return trimmed.startsWith('W/') ? trimmed.substring(2) : trimmed;
  }

  Future<Directory> _baseDir() async {
    if (baseDirOverride != null) return baseDirOverride!;
    final support = await getApplicationSupportDirectory();
    return Directory('${support.path}${Platform.pathSeparator}tagdict');
  }

  File _metaFile(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}meta.json');

  File _tsvFile(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}danbooru.tsv');

  File _aliasFile(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}aliases.tsv');

  // ---------------------------------------------------------------- 元信息

  /// 读取已安装词库的元信息 (未安装过返回 null)
  Future<TagDictMeta?> loadMeta() async {
    try {
      final dir = await _baseDir();
      final file = _metaFile(dir);
      if (!await file.exists()) return null;
      final json = jsonDecode(await file.readAsString());
      if (json is Map<String, dynamic>) return TagDictMeta.fromJson(json);
      return null;
    } catch (e) {
      debugPrint('[TagDictUpdate] 读取元信息失败: $e');
      return null;
    }
  }

  Future<void> _saveMeta(Directory dir, TagDictMeta meta) async {
    final file = _metaFile(dir);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(meta.toJson()),
      flush: true,
    );
  }

  /// 仅刷新"上次检查时间" (无更新或下载失败时也记录，避免高频重试)
  Future<void> _touchLastCheck(Directory dir, TagDictMeta? meta) async {
    final now = DateTime.now();
    final next = meta == null
        ? null
        : TagDictMeta(
            entryCount: meta.entryCount,
            etag: meta.etag,
            installedAt: meta.installedAt,
            lastCheckAt: now,
          );
    if (next != null) await _saveMeta(dir, next);
  }

  // ------------------------------------------------------------ 启动应用

  /// 启动时应用已安装的在线词库 (无则继续使用内置资产词库)
  Future<void> applyInstalledAtStartup() async {
    try {
      final dir = await _baseDir();
      final tsvFile = _tsvFile(dir);
      if (!await tsvFile.exists()) return;
      final content = await tsvFile.readAsString();
      if (content.trim().isEmpty) return;
      await TagDictionaryService.instance.replaceWithContent(content);
      debugPrint(
        '[TagDictUpdate] 已应用在线词库 '
        '(${TagDictionaryService.instance.count} 条)',
      );
    } catch (e) {
      debugPrint('[TagDictUpdate] 应用在线词库失败，回退内置词库: $e');
    }
  }

  /// 启动时后台静默检查 (节流：距上次检查不足 24 小时则跳过)
  Future<void> maybeAutoUpdate({required bool enabled}) async {
    if (!enabled) return;
    try {
      final meta = await loadMeta();
      if (meta != null &&
          DateTime.now().difference(meta.lastCheckAt).inHours < 24) {
        return;
      }
      await updateNow();
    } catch (e) {
      debugPrint('[TagDictUpdate] 自动检查更新失败 (下次启动再试): $e');
      try {
        final dir = await _baseDir();
        await _touchLastCheck(dir, await loadMeta());
      } catch (_) {}
    }
  }

  // ------------------------------------------------------------ 检查更新

  /// HEAD 请求读取上游 sqlite 的 ETag (内容哈希，免 GitHub API 限额)
  Future<String?> _fetchEtag() async {
    final resp = await _client
        .head(Uri.parse(kTagSqliteUrl))
        .timeout(const Duration(seconds: 20));
    if (resp.statusCode != 200) return null;
    return _normalizeEtag(resp.headers['etag']);
  }

  /// 是否存在新版本词库 (网络失败时返回 null，视为未知)
  Future<bool?> hasUpdate() async {
    try {
      final etag = await _fetchEtag();
      if (etag == null) return null;
      final meta = await loadMeta();
      return meta?.etag != etag;
    } catch (e) {
      debugPrint('[TagDictUpdate] 检查更新失败: $e');
      return null;
    }
  }

  // ------------------------------------------------------------ 执行更新

  /// 立即检查并下载安装最新词库。
  /// [onStatus] 用于 UI 展示阶段进度文案 (如 "下载词库 45%")。
  /// 并发调用会复用同一次在途更新 (单飞)。
  Future<TagDictUpdateResult> updateNow({
    void Function(String stage)? onStatus,
  }) {
    final inFlight = _inFlightUpdate;
    if (inFlight != null) return inFlight;
    return _inFlightUpdate = _performUpdate(
      onStatus: onStatus,
    ).whenComplete(() => _inFlightUpdate = null);
  }

  Future<TagDictUpdateResult> _performUpdate({
    void Function(String stage)? onStatus,
  }) async {
    void status(String s) => onStatus?.call(s);

    final dir = await _baseDir();
    await dir.create(recursive: true);

    // 1. ETag 判断是否需要下载 (相同则已是最新，仅刷新检查时间)
    status('检查最新版本');
    final etag = await _fetchEtag();
    final meta = await loadMeta();
    if (etag != null && meta != null && meta.etag == etag) {
      await _touchLastCheck(dir, meta);
      return const TagDictUpdateResult(
        success: true,
        upToDate: true,
        message: '词库已是最新版本',
        entryCount: 0,
      );
    }

    // 2. 下载 sqlite 词库 (约 22MB，流式读取并汇报进度)
    //    临时文件名带时间戳，避免多流程争抢同一文件
    status('下载词库数据 (约 22MB)');
    final bytes = await _downloadSqlite(
      onProgress: (p) => status('下载词库数据 ${(p * 100).round()}%'),
    );
    final sqliteTemp = File(
      '${dir.path}${Platform.pathSeparator}'
      'tag_download_${DateTime.now().microsecondsSinceEpoch}.tmp.sqlite',
    );
    await sqliteTemp.writeAsBytes(bytes, flush: true);

    try {
      // 3. 拉取 Danbooru 官方别名 (缓存 7 天)
      final aliasPairs = await _loadAliasPairs(dir, status);

      // 4. 后台 isolate 重建 TSV
      status('解析并重建词库');
      final output = await compute(
        _buildTsvFromSqlite,
        _BuildInput(sqliteTemp.path, aliasPairs),
      );

      // 5. 原子写入 (临时文件 + rename) 并热替换
      status('写入并应用新词库');
      final tsvTemp = File(
        '${dir.path}${Platform.pathSeparator}danbooru.tmp.tsv',
      );
      await tsvTemp.writeAsString(output.tsv, flush: true);
      final tsvFile = _tsvFile(dir);
      if (await tsvFile.exists()) await tsvFile.delete();
      await tsvTemp.rename(tsvFile.path);

      final now = DateTime.now();
      final newMeta = TagDictMeta(
        entryCount: output.entryCount,
        etag: etag ?? '',
        installedAt: now,
        lastCheckAt: now,
      );
      await _saveMeta(dir, newMeta);

      await TagDictionaryService.instance.replaceWithContent(output.tsv);

      return TagDictUpdateResult(
        success: true,
        message: '词库已更新',
        entryCount: output.entryCount,
      );
    } finally {
      // 清理 sqlite 临时文件
      try {
        if (await sqliteTemp.exists()) await sqliteTemp.delete();
      } catch (_) {}
    }
  }

  Future<Uint8List> _downloadSqlite({
    required void Function(double progress) onProgress,
  }) async {
    final req = http.Request('GET', Uri.parse(kTagSqliteUrl));
    final resp = await _client.send(req).timeout(const Duration(seconds: 30));

    if (resp.statusCode != 200) {
      throw HttpException('词库下载失败: HTTP ${resp.statusCode}');
    }

    final total = resp.contentLength ?? 0;
    final builder = BytesBuilder(copy: false);
    var received = 0;
    await for (final chunk in resp.stream) {
      builder.add(chunk);
      received += chunk.length;
      if (total > 0) onProgress(received / total);
    }
    return builder.takeBytes();
  }

  /// 拉取 (或复用缓存) Danbooru 官方别名对列表
  Future<List<List<String>>> _loadAliasPairs(
    Directory dir,
    void Function(String s) status,
  ) async {
    final aliasFile = _aliasFile(dir);

    // 缓存 7 天内直接复用
    if (await aliasFile.exists()) {
      final stat = await aliasFile.stat();
      if (DateTime.now().difference(stat.modified).inDays < 7) {
        final cached = parseAliasCache(await aliasFile.readAsString());
        return [
          for (final e in cached.entries)
            for (final ant in e.value) [ant, e.key],
        ];
      }
    }

    status('同步 Danbooru 官方别名表');
    final pairs = <List<String>>[];
    var page = 1;
    var consecutiveFailures = 0;
    while (true) {
      List<dynamic>? data;
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          final uri = Uri.parse(kDanbooruAliasApi).replace(
            queryParameters: {
              'search[status]': 'active',
              'limit': '1000',
              'page': '$page',
            },
          );
          final resp = await _client
              .get(uri)
              .timeout(const Duration(seconds: 30));
          if (resp.statusCode == 200) {
            data = jsonDecode(resp.body) as List<dynamic>;
            break;
          }
          throw HttpException('别名接口 HTTP ${resp.statusCode}');
        } catch (e) {
          if (attempt == 2) debugPrint('[TagDictUpdate] 别名第 $page 页失败: $e');
          await Future<void>.delayed(const Duration(milliseconds: 800));
        }
      }

      if (data == null) {
        consecutiveFailures++;
        // 连续 3 页彻底失败则放弃后续页 (已拿到的别名仍然可用)
        if (pairs.isEmpty && consecutiveFailures >= 1) break;
        if (consecutiveFailures >= 3) break;
        page++;
        continue;
      }
      consecutiveFailures = 0;

      if (data.isEmpty) break;
      for (final item in data) {
        if (item is Map<String, dynamic>) {
          final ant = item['antecedent_name'];
          final con = item['consequent_name'];
          if (ant is String &&
              con is String &&
              ant.isNotEmpty &&
              con.isNotEmpty) {
            pairs.add([ant, con]);
          }
        }
      }
      if (data.length < 1000) break;
      page++;
      status('同步 Danbooru 官方别名表 (${pairs.length} 条)');
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }

    if (pairs.isNotEmpty) {
      final buffer = StringBuffer();
      for (final p in pairs) {
        buffer.write(p[0]);
        buffer.write('\t');
        buffer.write(p[1]);
        buffer.write('\n');
      }
      await aliasFile.writeAsString(buffer.toString(), flush: true);
    }
    return pairs;
  }
}
