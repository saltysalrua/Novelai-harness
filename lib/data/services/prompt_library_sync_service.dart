import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../models/prompt_library_models.dart';
import '../models/prompt_library_sync_models.dart';
import 'prompt_library_service.dart';

/// 本地图片哈希信息
typedef LocalPreviewHashInfo = ({String hash, String ext});

/// 双向合并计划 (纯数据结构，供单元测试直接断言)
class PromptLibraryMergePlan {
  final List<RemotePromptEntryRecord> toPush;
  final List<RemotePromptEntryRecord> pulledActive;
  final List<RemotePromptEntryRecord> repairPreview;
  final Set<String> deletedLocalIds;
  final int deletedRemoteCount;
  final Map<String, DateTime> nextTombstones;

  const PromptLibraryMergePlan({
    required this.toPush,
    required this.pulledActive,
    required this.repairPreview,
    required this.deletedLocalIds,
    required this.deletedRemoteCount,
    required this.nextTombstones,
  });
}

/// 纯函数：计算本地与远端的双向增量合并计划
PromptLibraryMergePlan planPromptLibraryMerge({
  required List<PromptComboEntry> localEntries,
  required Map<String, LocalPreviewHashInfo> localImageHashes,
  required Map<String, DateTime> localTombstones,
  required List<RemotePromptEntryRecord> remoteRecords,
}) {
  final localMap = <String, PromptComboEntry>{
    for (final e in localEntries)
      if (e.id.trim().isNotEmpty) e.id: e,
  };
  final remoteMap = <String, RemotePromptEntryRecord>{
    for (final r in remoteRecords)
      if (r.id.trim().isNotEmpty) r.id: r,
  };

  final allIds = <String>{
    ...localMap.keys,
    ...localTombstones.keys,
    ...remoteMap.keys,
  };

  final toPush = <RemotePromptEntryRecord>[];
  final pulledActive = <RemotePromptEntryRecord>[];
  final repairPreview = <RemotePromptEntryRecord>[];
  final deletedLocalIds = <String>{};
  var deletedRemoteCount = 0;
  final nextTombstones = <String, DateTime>{};

  for (final id in allIds) {
    final local = localMap[id];
    final localTomb = local == null ? localTombstones[id] : null;
    final remote = remoteMap[id];

    // 1. 仅本地存在
    if (remote == null) {
      if (local != null) {
        final img = localImageHashes[id];
        toPush.add(
          RemotePromptEntryRecord.fromLocalEntry(
            local,
            previewHash: img?.hash,
            previewExt: img?.ext,
          ),
        );
      } else if (localTomb != null) {
        nextTombstones[id] = localTomb;
      }
      continue;
    }

    // 2. 仅远端存在
    if (local == null && localTomb == null) {
      if (remote.isDeleted) {
        nextTombstones[id] = remote.deletedAt!;
      } else {
        pulledActive.add(remote);
      }
      continue;
    }

    // 3. 两端均存在，按 UTC 时间戳比较
    final localMs = (local?.updatedAt ?? localTomb!)
        .toUtc()
        .millisecondsSinceEpoch;
    final remoteMs = remote.effectiveTimestamp.millisecondsSinceEpoch;

    if (localMs > remoteMs) {
      if (local != null) {
        final img = localImageHashes[id];
        toPush.add(
          RemotePromptEntryRecord.fromLocalEntry(
            local,
            previewHash: img?.hash,
            previewExt: img?.ext,
          ),
        );
      } else if (localTomb != null) {
        if (!remote.isDeleted) {
          toPush.add(
            RemotePromptEntryRecord.tombstone(id: id, deletedAt: localTomb),
          );
          deletedRemoteCount++;
        }
        nextTombstones[id] = localTomb;
      }
    } else if (remoteMs > localMs) {
      if (remote.isDeleted) {
        if (local != null) {
          deletedLocalIds.add(id);
        }
        nextTombstones[id] = remote.deletedAt!;
      } else {
        pulledActive.add(remote);
      }
    } else {
      // 同毫秒平局处理
      if (local != null && remote.isDeleted) {
        deletedLocalIds.add(id);
        nextTombstones[id] = remote.deletedAt!;
      } else if (local == null && localTomb != null) {
        if (!remote.isDeleted) {
          toPush.add(
            RemotePromptEntryRecord.tombstone(id: id, deletedAt: localTomb),
          );
          deletedRemoteCount++;
        }
        nextTombstones[id] = localTomb;
      } else if (local != null && !remote.isDeleted) {
        final img = localImageHashes[id];
        if (img == null && remote.previewHash != null) {
          repairPreview.add(remote);
        }
      }
    }
  }

  return PromptLibraryMergePlan(
    toPush: toPush,
    pulledActive: pulledActive,
    repairPreview: repairPreview,
    deletedLocalIds: deletedLocalIds,
    deletedRemoteCount: deletedRemoteCount,
    nextTombstones: nextTombstones,
  );
}

/// 词库 Cloudflare 云同步服务 (Workers + D1)
///
/// 支持：
/// - 双向增量合并 (按条目 ID + updatedAt + 删除墓碑)
/// - 预览图按 SHA-256 去重增量上传与按需下载
/// - 强制上传覆盖云端 / 强制拉取覆盖本地
/// - 单飞锁防止并发同步冲突
class PromptLibrarySyncService {
  PromptLibrarySyncService({
    PromptLibraryService? libraryService,
    http.Client? httpClient,
  }) : _library = libraryService ?? PromptLibraryService.instance,
       _injectedClient = httpClient;

  static final PromptLibrarySyncService instance = PromptLibrarySyncService();

  static const Duration _requestTimeout = Duration(seconds: 30);
  static const int _maxImageBytes = 8 * 1024 * 1024;
  static const int _pushBatchSize = 100;

  final PromptLibraryService _library;
  final http.Client? _injectedClient;

  Future<PromptLibrarySyncResult>? _inFlightSync;

  /// 测试连接并读取远端命名空间统计
  Future<PromptLibrarySyncHealth> testConnection(
    PromptLibrarySyncConfig config,
  ) async {
    _validateConfig(config);
    final uri = config.resolveApiUri('/api/health', {
      'namespace': config.normalizedNamespace,
    });
    if (uri == null) {
      throw const PromptLibrarySyncException('同步服务地址格式无效');
    }

    return _withClient((client) async {
      final resp = await client
          .get(uri, headers: _authHeaders(config))
          .timeout(_requestTimeout);
      final data = _decodeJsonResponse(resp);
      return PromptLibrarySyncHealth.fromJson(data);
    });
  }

  /// 执行词库云同步 (单飞防并发)
  Future<PromptLibrarySyncResult> sync(
    PromptLibrarySyncConfig config, {
    PromptLibrarySyncMode mode = PromptLibrarySyncMode.merge,
    void Function(String stage)? onStatus,
  }) {
    final active = _inFlightSync;
    if (active != null) return active;
    return _inFlightSync = _performSync(
      config,
      mode: mode,
      onStatus: onStatus,
    ).whenComplete(() => _inFlightSync = null);
  }

  Future<PromptLibrarySyncResult> _performSync(
    PromptLibrarySyncConfig config, {
    required PromptLibrarySyncMode mode,
    void Function(String stage)? onStatus,
  }) async {
    _validateConfig(config);
    void status(String s) => onStatus?.call(s);

    return _withClient((client) async {
      switch (mode) {
        case PromptLibrarySyncMode.merge:
          return _syncMerge(client, config, status);
        case PromptLibrarySyncMode.forcePush:
          return _syncForcePush(client, config, status);
        case PromptLibrarySyncMode.forcePull:
          return _syncForcePull(client, config, status);
      }
    });
  }

  Future<PromptLibrarySyncResult> _syncMerge(
    http.Client client,
    PromptLibrarySyncConfig config,
    void Function(String) status,
  ) async {
    status('正在读取本地词库与同步状态...');
    final localEntries = await _library.loadEntries();
    final syncState = await _library.loadSyncState();

    final hashCache = Map<String, PromptPreviewHashCacheEntry>.from(
      syncState.previewHashCache,
    );
    final localImageHashes = await _collectLocalImageHashes(
      localEntries,
      hashCache,
    );
    final hashToLocalPath = await _buildExistingHashToPathMap(
      localEntries,
      localImageHashes,
      hashCache,
    );

    status('正在拉取云端词库索引...');
    final remoteSnap = await _fetchRemoteSync(client, config);

    final plan = planPromptLibraryMerge(
      localEntries: localEntries,
      localImageHashes: localImageHashes,
      localTombstones: syncState.tombstones,
      remoteRecords: remoteSnap.entries,
    );

    // 1. 增量上传缺失预览图 + 推送变更词条
    var uploadedImages = 0;
    final pushHashes = plan.toPush
        .where((e) => !e.isDeleted && e.previewHash != null)
        .map((e) => e.previewHash!)
        .toSet()
        .toList();
    if (pushHashes.isNotEmpty) {
      status('正在校验预览图哈希...');
      final missing = await _checkMissingImages(client, config, pushHashes);
      if (missing.isNotEmpty) {
        uploadedImages = await _uploadMissingImages(
          client,
          config,
          missing: missing,
          localEntries: localEntries,
          localImageHashes: localImageHashes,
          status: status,
        );
      }
    }

    var nextRevision = remoteSnap.revision;
    if (plan.toPush.isNotEmpty) {
      status('正在上传 ${plan.toPush.length} 条变更...');
      nextRevision = await _pushRecords(
        client,
        config,
        mode: 'merge',
        records: plan.toPush,
      );
    }

    // 2. 下载缺失的远端预览图，并合并生成最终本地条目
    var downloadedImages = 0;
    final pulledById = <String, RemotePromptEntryRecord>{
      for (final r in plan.pulledActive) r.id: r,
    };
    final repairById = <String, RemotePromptEntryRecord>{
      for (final r in plan.repairPreview) r.id: r,
    };

    final entriesNeedingImage = <RemotePromptEntryRecord>[
      ...plan.pulledActive,
      ...plan.repairPreview,
    ];
    final neededHashes = entriesNeedingImage
        .map((r) => r.previewHash)
        .whereType<String>()
        .where((h) => !hashToLocalPath.containsKey(h))
        .toSet()
        .toList();

    for (var i = 0; i < neededHashes.length; i++) {
      final hash = neededHashes[i];
      status('正在下载预览图 (${i + 1}/${neededHashes.length})...');
      final savedPath = await _downloadAndSaveImage(
        client,
        config,
        hash: hash,
        extHint: entriesNeedingImage
            .where((r) => r.previewHash == hash)
            .map((r) => r.previewExt)
            .firstOrNull,
        hashCache: hashCache,
      );
      if (savedPath != null) {
        hashToLocalPath[hash] = savedPath;
        downloadedImages++;
      }
    }

    // 3. 组装最终本地列表 (保留现有顺序 + 头部插入远端新增)
    final mergedEntries = <PromptComboEntry>[];
    final existingIds = <String>{};

    for (final local in localEntries) {
      if (plan.deletedLocalIds.contains(local.id)) continue;
      existingIds.add(local.id);

      final pulled = pulledById[local.id];
      if (pulled != null) {
        final previewPath = pulled.previewHash != null
            ? hashToLocalPath[pulled.previewHash!]
            : null;
        mergedEntries.add(pulled.toLocalEntry(previewImagePath: previewPath));
        continue;
      }

      final repaired = repairById[local.id];
      if (repaired != null && repaired.previewHash != null) {
        final previewPath = hashToLocalPath[repaired.previewHash!];
        mergedEntries.add(local.copyWith(previewImagePath: previewPath));
        continue;
      }

      mergedEntries.add(local);
    }

    final newFromRemote =
        plan.pulledActive
            .where((r) => !existingIds.contains(r.id))
            .toList(growable: false)
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    final prepended = <PromptComboEntry>[];
    for (final remote in newFromRemote) {
      final previewPath = remote.previewHash != null
          ? hashToLocalPath[remote.previewHash!]
          : null;
      prepended.add(remote.toLocalEntry(previewImagePath: previewPath));
    }

    final finalEntries = [...prepended, ...mergedEntries];
    final syncedAt = DateTime.now().toUtc();

    final nextState = PromptLibrarySyncState(
      lastSyncAt: syncedAt,
      lastRevision: nextRevision,
      tombstones: plan.nextTombstones,
      previewHashCache: _pruneStaleHashCache(hashCache, finalEntries),
    );

    status('正在保存本地词库...');
    await _library.applySyncOutcome(
      entries: finalEntries,
      syncState: nextState,
    );

    final pushedActive = plan.toPush.where((e) => !e.isDeleted).length;
    return PromptLibrarySyncResult(
      mode: PromptLibrarySyncMode.merge,
      pushedEntries: pushedActive,
      pulledEntries: plan.pulledActive.length,
      deletedLocal: plan.deletedLocalIds.length,
      deletedRemote: plan.deletedRemoteCount,
      uploadedImages: uploadedImages,
      downloadedImages: downloadedImages,
      revision: nextRevision,
      syncedAt: syncedAt,
    );
  }

  Future<PromptLibrarySyncResult> _syncForcePush(
    http.Client client,
    PromptLibrarySyncConfig config,
    void Function(String) status,
  ) async {
    status('正在准备全量上传...');
    final localEntries = await _library.loadEntries();
    final syncState = await _library.loadSyncState();
    final hashCache = Map<String, PromptPreviewHashCacheEntry>.from(
      syncState.previewHashCache,
    );
    final localImageHashes = await _collectLocalImageHashes(
      localEntries,
      hashCache,
    );

    final records = localEntries
        .map((entry) {
          final img = localImageHashes[entry.id];
          return RemotePromptEntryRecord.fromLocalEntry(
            entry,
            previewHash: img?.hash,
            previewExt: img?.ext,
          );
        })
        .toList(growable: false);

    var uploadedImages = 0;
    final hashes = records
        .map((r) => r.previewHash)
        .whereType<String>()
        .toSet()
        .toList();
    if (hashes.isNotEmpty) {
      status('正在检查云端预览图...');
      final missing = await _checkMissingImages(client, config, hashes);
      if (missing.isNotEmpty) {
        uploadedImages = await _uploadMissingImages(
          client,
          config,
          missing: missing,
          localEntries: localEntries,
          localImageHashes: localImageHashes,
          status: status,
        );
      }
    }

    status('正在覆盖云端词库 (${records.length} 条)...');
    final nextRevision = await _pushRecords(
      client,
      config,
      mode: 'replace',
      records: records,
    );

    final syncedAt = DateTime.now().toUtc();
    final nextState = PromptLibrarySyncState(
      lastSyncAt: syncedAt,
      lastRevision: nextRevision,
      tombstones: const {},
      previewHashCache: _pruneStaleHashCache(hashCache, localEntries),
    );
    await _library.saveSyncState(nextState);

    return PromptLibrarySyncResult(
      mode: PromptLibrarySyncMode.forcePush,
      pushedEntries: records.length,
      pulledEntries: 0,
      deletedLocal: 0,
      deletedRemote: 0,
      uploadedImages: uploadedImages,
      downloadedImages: 0,
      revision: nextRevision,
      syncedAt: syncedAt,
    );
  }

  Future<PromptLibrarySyncResult> _syncForcePull(
    http.Client client,
    PromptLibrarySyncConfig config,
    void Function(String) status,
  ) async {
    status('正在拉取云端全量词库...');
    final localEntries = await _library.loadEntries();
    final syncState = await _library.loadSyncState();
    final hashCache = Map<String, PromptPreviewHashCacheEntry>.from(
      syncState.previewHashCache,
    );
    final localImageHashes = await _collectLocalImageHashes(
      localEntries,
      hashCache,
    );
    final hashToLocalPath = await _buildExistingHashToPathMap(
      localEntries,
      localImageHashes,
      hashCache,
    );

    final remoteSnap = await _fetchRemoteSync(client, config);
    final activeRemote = remoteSnap.entries
        .where((r) => !r.isDeleted)
        .toList(growable: false);
    final remoteTombstones = <String, DateTime>{
      for (final r in remoteSnap.entries)
        if (r.isDeleted) r.id: r.deletedAt!,
    };

    final neededHashes = activeRemote
        .map((r) => r.previewHash)
        .whereType<String>()
        .where((h) => !hashToLocalPath.containsKey(h))
        .toSet()
        .toList();

    var downloadedImages = 0;
    for (var i = 0; i < neededHashes.length; i++) {
      final hash = neededHashes[i];
      status('正在下载预览图 (${i + 1}/${neededHashes.length})...');
      final savedPath = await _downloadAndSaveImage(
        client,
        config,
        hash: hash,
        extHint: activeRemote
            .where((r) => r.previewHash == hash)
            .map((r) => r.previewExt)
            .firstOrNull,
        hashCache: hashCache,
      );
      if (savedPath != null) {
        hashToLocalPath[hash] = savedPath;
        downloadedImages++;
      }
    }

    final finalEntries = activeRemote
        .map(
          (r) => r.toLocalEntry(
            previewImagePath: r.previewHash != null
                ? hashToLocalPath[r.previewHash!]
                : null,
          ),
        )
        .toList(growable: false);

    final syncedAt = DateTime.now().toUtc();
    final nextState = PromptLibrarySyncState(
      lastSyncAt: syncedAt,
      lastRevision: remoteSnap.revision,
      tombstones: remoteTombstones,
      previewHashCache: _pruneStaleHashCache(hashCache, finalEntries),
    );

    status('正在覆盖本地词库...');
    await _library.applySyncOutcome(
      entries: finalEntries,
      syncState: nextState,
    );

    return PromptLibrarySyncResult(
      mode: PromptLibrarySyncMode.forcePull,
      pushedEntries: 0,
      pulledEntries: finalEntries.length,
      deletedLocal: localEntries.length,
      deletedRemote: 0,
      uploadedImages: 0,
      downloadedImages: downloadedImages,
      revision: remoteSnap.revision,
      syncedAt: syncedAt,
    );
  }

  // ------------------------- 本地文件哈希与缓存 -------------------------

  Future<Map<String, LocalPreviewHashInfo>> _collectLocalImageHashes(
    List<PromptComboEntry> entries,
    Map<String, PromptPreviewHashCacheEntry> hashCache,
  ) async {
    final result = <String, LocalPreviewHashInfo>{};
    for (final entry in entries) {
      final rawPath = entry.previewImagePath?.trim();
      if (rawPath == null || rawPath.isEmpty) continue;
      final file = File(rawPath);
      if (!file.existsSync()) continue;

      try {
        final stat = await file.stat();
        final modMs = stat.modified.millisecondsSinceEpoch;
        final cached = hashCache[rawPath];
        if (cached != null &&
            cached.sizeBytes == stat.size &&
            cached.modifiedMs == modMs) {
          result[entry.id] = (hash: cached.sha256, ext: cached.ext);
          continue;
        }

        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        final digest = sha256.convert(bytes).toString();
        final ext = _detectImageExt(bytes, rawPath);
        hashCache[rawPath] = PromptPreviewHashCacheEntry(
          sha256: digest,
          ext: ext,
          sizeBytes: stat.size,
          modifiedMs: modMs,
        );
        result[entry.id] = (hash: digest, ext: ext);
      } catch (_) {}
    }
    return result;
  }

  Future<Map<String, String>> _buildExistingHashToPathMap(
    List<PromptComboEntry> localEntries,
    Map<String, LocalPreviewHashInfo> localImageHashes,
    Map<String, PromptPreviewHashCacheEntry> hashCache,
  ) async {
    final map = <String, String>{};
    for (final entry in localEntries) {
      final info = localImageHashes[entry.id];
      final path = entry.previewImagePath?.trim();
      if (info != null && path != null && path.isNotEmpty) {
        map.putIfAbsent(info.hash, () => path);
      }
    }
    for (final cached in hashCache.entries) {
      if (map.containsKey(cached.value.sha256)) continue;
      if (File(cached.key).existsSync()) {
        map[cached.value.sha256] = cached.key;
      }
    }
    return map;
  }

  Map<String, PromptPreviewHashCacheEntry> _pruneStaleHashCache(
    Map<String, PromptPreviewHashCacheEntry> hashCache,
    List<PromptComboEntry> activeEntries,
  ) {
    final activePaths = activeEntries
        .map((e) => e.previewImagePath?.trim())
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toSet();
    return {
      for (final e in hashCache.entries)
        if (activePaths.contains(e.key)) e.key: e.value,
    };
  }

  String _detectImageExt(Uint8List bytes, String? path) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (path != null) {
      final ext = p.extension(path).replaceAll('.', '').toLowerCase();
      if (ext == 'jpeg') return 'jpg';
      if (ext == 'png' || ext == 'jpg' || ext == 'webp' || ext == 'gif') {
        return ext;
      }
    }
    return 'png';
  }

  // ------------------------- HTTP 通信 -------------------------

  void _validateConfig(PromptLibrarySyncConfig config) {
    if (config.endpoint.trim().isEmpty) {
      throw const PromptLibrarySyncException('请先填写 Cloudflare Worker 同步服务地址');
    }
    if (config.resolveApiUri('/api/health') == null) {
      throw const PromptLibrarySyncException('同步服务地址格式无效 (需为 http/https URL)');
    }
    if (config.token.trim().isEmpty) {
      throw const PromptLibrarySyncException('请先填写同步访问密钥 (Token)');
    }
    final ns = config.normalizedNamespace;
    if (ns.length > 64 || !RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(ns)) {
      throw const PromptLibrarySyncException(
        '命名空间仅支持字母、数字、点、下划线和短横线 (最多 64 字符)',
      );
    }
  }

  Map<String, String> _authHeaders(
    PromptLibrarySyncConfig config, {
    Map<String, String>? extra,
  }) {
    return {
      'Authorization': 'Bearer ${config.token.trim()}',
      ...?extra,
    };
  }

  Future<T> _withClient<T>(Future<T> Function(http.Client client) action) async {
    final injected = _injectedClient;
    if (injected != null) {
      return action(injected);
    }
    final client = http.Client();
    try {
      return await action(client);
    } finally {
      client.close();
    }
  }

  Map<String, dynamic> _decodeJsonResponse(http.Response resp) {
    Map<String, dynamic>? decoded;
    if (resp.body.isNotEmpty) {
      try {
        final raw = jsonDecode(resp.body);
        if (raw is Map<String, dynamic>) {
          decoded = raw;
        }
      } catch (_) {}
    }

    if (resp.statusCode >= 400 || decoded?['ok'] == false) {
      final msg =
          decoded?['error'] as String? ??
          (resp.statusCode == 401
              ? '同步密钥验证失败 (401)'
              : '云同步请求失败 (HTTP ${resp.statusCode})');
      throw PromptLibrarySyncException(msg, statusCode: resp.statusCode);
    }

    if (decoded == null) {
      throw PromptLibrarySyncException(
        '云端返回了无法解析的响应',
        statusCode: resp.statusCode,
      );
    }
    return decoded;
  }

  Future<({int revision, List<RemotePromptEntryRecord> entries})>
  _fetchRemoteSync(http.Client client, PromptLibrarySyncConfig config) async {
    final uri = config.resolveApiUri('/api/sync', {
      'namespace': config.normalizedNamespace,
    })!;
    final resp = await client
        .get(uri, headers: _authHeaders(config))
        .timeout(_requestTimeout);
    final data = _decodeJsonResponse(resp);
    final revision = (data['revision'] as num?)?.toInt() ?? 0;
    final rawEntries = data['entries'];
    final entries = <RemotePromptEntryRecord>[];
    if (rawEntries is List) {
      for (final item in rawEntries) {
        if (item is Map<String, dynamic>) {
          final parsed = RemotePromptEntryRecord.fromJson(item);
          if (parsed.id.isNotEmpty) {
            entries.add(parsed);
          }
        }
      }
    }
    return (revision: revision, entries: entries);
  }

  Future<List<String>> _checkMissingImages(
    http.Client client,
    PromptLibrarySyncConfig config,
    List<String> hashes,
  ) async {
    final uri = config.resolveApiUri('/api/images/check')!;
    final resp = await client
        .post(
          uri,
          headers: _authHeaders(
            config,
            extra: const {'Content-Type': 'application/json'},
          ),
          body: jsonEncode({'hashes': hashes}),
        )
        .timeout(_requestTimeout);
    final data = _decodeJsonResponse(resp);
    final rawMissing = data['missing'];
    if (rawMissing is! List) return const [];
    return rawMissing.map((e) => e.toString()).toList(growable: false);
  }

  Future<int> _uploadMissingImages(
    http.Client client,
    PromptLibrarySyncConfig config, {
    required List<String> missing,
    required List<PromptComboEntry> localEntries,
    required Map<String, LocalPreviewHashInfo> localImageHashes,
    required void Function(String) status,
  }) async {
    final hashToSource = <String, ({String path, String ext})>{};
    for (final entry in localEntries) {
      final info = localImageHashes[entry.id];
      final path = entry.previewImagePath?.trim();
      if (info != null && path != null && path.isNotEmpty) {
        hashToSource.putIfAbsent(info.hash, () => (path: path, ext: info.ext));
      }
    }

    var uploaded = 0;
    for (var i = 0; i < missing.length; i++) {
      final hash = missing[i];
      final source = hashToSource[hash];
      if (source == null) continue;
      final file = File(source.path);
      if (!file.existsSync()) continue;

      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) continue;
      if (bytes.length > _maxImageBytes) {
        throw PromptLibrarySyncException(
          '预览图超过 8 MiB 上传限制 (${p.basename(source.path)})',
        );
      }

      status('正在上传预览图 (${i + 1}/${missing.length})...');
      final uri = config.resolveApiUri('/api/images/$hash')!;
      final mime = switch (source.ext) {
        'jpg' || 'jpeg' => 'image/jpeg',
        'webp' => 'image/webp',
        'gif' => 'image/gif',
        _ => 'image/png',
      };
      final resp = await client
          .put(
            uri,
            headers: _authHeaders(
              config,
              extra: {'Content-Type': mime, 'X-Image-Ext': source.ext},
            ),
            body: bytes,
          )
          .timeout(const Duration(seconds: 60));
      _decodeJsonResponse(resp);
      uploaded++;
    }
    return uploaded;
  }

  Future<String?> _downloadAndSaveImage(
    http.Client client,
    PromptLibrarySyncConfig config, {
    required String hash,
    String? extHint,
    required Map<String, PromptPreviewHashCacheEntry> hashCache,
  }) async {
    final uri = config.resolveApiUri('/api/images/$hash')!;
    final resp = await client
        .get(uri, headers: _authHeaders(config))
        .timeout(const Duration(seconds: 60));
    if (resp.statusCode == 404) {
      debugPrint('[PromptSync] 云端缺失预览图: $hash');
      return null;
    }
    if (resp.statusCode >= 400) {
      throw PromptLibrarySyncException(
        '下载预览图失败 (HTTP ${resp.statusCode})',
        statusCode: resp.statusCode,
      );
    }

    final bytes = resp.bodyBytes;
    if (bytes.isEmpty) return null;
    final actualHash = sha256.convert(bytes).toString();
    if (actualHash != hash) {
      throw const PromptLibrarySyncException('下载的预览图 SHA-256 校验失败');
    }

    final ext = _detectImageExt(bytes, extHint != null ? 'x.$extHint' : null);
    final savedPath = await _library.savePreviewImageBytes(
      bytes,
      extension: ext,
    );
    if (savedPath != null) {
      try {
        final stat = await File(savedPath).stat();
        hashCache[savedPath] = PromptPreviewHashCacheEntry(
          sha256: hash,
          ext: ext,
          sizeBytes: stat.size,
          modifiedMs: stat.modified.millisecondsSinceEpoch,
        );
      } catch (_) {}
    }
    return savedPath;
  }

  Never _rethrowPushError(
    PromptLibrarySyncException e,
    List<RemotePromptEntryRecord> records,
  ) {
    final hasAffixOnlyStyle = records.any(
      (r) =>
          !r.isDeleted &&
          PromptComboEntry.isStyleCategory(r.category) &&
          r.prompt.trim().isEmpty &&
          (r.prefixPrompt.trim().isNotEmpty ||
              r.suffixPrompt.trim().isNotEmpty ||
              r.negativePrompt.trim().isNotEmpty),
    );
    if (e.statusCode == 400 &&
        hasAffixOnlyStyle &&
        e.message.contains('缺少 title 或 prompt')) {
      throw PromptLibrarySyncException(
        '云端 Worker 版本过旧，不支持新版「风格」前后缀词条同步，请在 cloudflare/prompt-library-sync 目录重新执行 npm run deploy 升级后重试 (${e.message})',
        statusCode: e.statusCode,
      );
    }
    throw e;
  }

  Future<int> _pushRecords(
    http.Client client,
    PromptLibrarySyncConfig config, {
    required String mode,
    required List<RemotePromptEntryRecord> records,
  }) async {
    final uri = config.resolveApiUri('/api/sync/push')!;
    if (mode == 'replace' || records.length <= _pushBatchSize) {
      final resp = await client
          .post(
            uri,
            headers: _authHeaders(
              config,
              extra: const {'Content-Type': 'application/json'},
            ),
            body: jsonEncode({
              'namespace': config.normalizedNamespace,
              'mode': mode,
              'entries': records.map((e) => e.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 60));
      try {
        final data = _decodeJsonResponse(resp);
        return (data['revision'] as num?)?.toInt() ?? 0;
      } on PromptLibrarySyncException catch (e) {
        _rethrowPushError(e, records);
      }
    }

    var latestRevision = 0;
    for (var i = 0; i < records.length; i += _pushBatchSize) {
      final end = (i + _pushBatchSize < records.length)
          ? i + _pushBatchSize
          : records.length;
      final slice = records.sublist(i, end);
      final resp = await client
          .post(
            uri,
            headers: _authHeaders(
              config,
              extra: const {'Content-Type': 'application/json'},
            ),
            body: jsonEncode({
              'namespace': config.normalizedNamespace,
              'mode': mode,
              'entries': slice.map((e) => e.toJson()).toList(),
            }),
          )
          .timeout(const Duration(seconds: 60));
      try {
        final data = _decodeJsonResponse(resp);
        latestRevision = (data['revision'] as num?)?.toInt() ?? latestRevision;
      } on PromptLibrarySyncException catch (e) {
        _rethrowPushError(e, slice);
      }
    }
    return latestRevision;
  }
}
