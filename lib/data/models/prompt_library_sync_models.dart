import 'nai_precise_reference.dart';
import 'nai_vibe_reference.dart';
import 'prompt_library_models.dart';

/// 词库云同步模式
enum PromptLibrarySyncMode {
  /// 双向增量合并 (按 id + updatedAt / 删除墓碑比较)
  merge,

  /// 强制上传覆盖云端 (本地为唯一真相)
  forcePush,

  /// 强制拉取覆盖本地 (云端为唯一真相)
  forcePull,
}

/// 词库云同步连接配置
class PromptLibrarySyncConfig {
  final String endpoint;
  final String token;
  final String namespace;

  const PromptLibrarySyncConfig({
    this.endpoint = '',
    this.token = '',
    this.namespace = 'default',
  });

  /// 规范化后的命名空间 (空串回退 `'default'`)
  String get normalizedNamespace {
    final trimmed = namespace.trim();
    return trimmed.isEmpty ? 'default' : trimmed;
  }

  /// 是否已配置必要凭证
  bool get isConfigured => endpoint.trim().isNotEmpty && token.trim().isNotEmpty;

  /// 解析并校验服务地址；格式无效返回 null
  Uri? resolveApiUri(String path, [Map<String, String>? queryParameters]) {
    var raw = endpoint.trim();
    if (raw.isEmpty) return null;
    if (!raw.contains('://')) {
      raw = 'https://$raw';
    }
    final base = Uri.tryParse(raw);
    if (base == null ||
        !base.hasAuthority ||
        (base.scheme != 'http' && base.scheme != 'https')) {
      return null;
    }

    final baseSegments = base.pathSegments.where((s) => s.isNotEmpty).toList();
    final relSegments = path
        .split('/')
        .where((s) => s.isNotEmpty)
        .toList(growable: false);

    return base.replace(
      pathSegments: [...baseSegments, ...relSegments],
      queryParameters: queryParameters != null && queryParameters.isNotEmpty
          ? queryParameters
          : null,
    );
  }
}

/// 本地预览图文件哈希缓存条目 (避免重复计算未变更图片的 SHA-256)
class PromptPreviewHashCacheEntry {
  final String sha256;
  final String ext;
  final int sizeBytes;
  final int modifiedMs;

  const PromptPreviewHashCacheEntry({
    required this.sha256,
    required this.ext,
    required this.sizeBytes,
    required this.modifiedMs,
  });

  Map<String, dynamic> toJson() => {
    'sha256': sha256,
    'ext': ext,
    'sizeBytes': sizeBytes,
    'modifiedMs': modifiedMs,
  };

  static PromptPreviewHashCacheEntry? fromJson(Map<String, dynamic> json) {
    final sha = json['sha256'];
    final ext = json['ext'];
    final size = json['sizeBytes'];
    final mod = json['modifiedMs'];
    if (sha is! String ||
        sha.length != 64 ||
        ext is! String ||
        size is! int ||
        mod is! int) {
      return null;
    }
    return PromptPreviewHashCacheEntry(
      sha256: sha,
      ext: ext,
      sizeBytes: size,
      modifiedMs: mod,
    );
  }
}

/// 本地持久化同步状态 (删除墓碑 + 哈希缓存 + 上次同步元信息)
class PromptLibrarySyncState {
  final DateTime? lastSyncAt;
  final int lastRevision;
  final Map<String, DateTime> tombstones;
  final Map<String, PromptPreviewHashCacheEntry> previewHashCache;

  const PromptLibrarySyncState({
    this.lastSyncAt,
    this.lastRevision = 0,
    this.tombstones = const {},
    this.previewHashCache = const {},
  });

  PromptLibrarySyncState copyWith({
    DateTime? lastSyncAt,
    bool clearLastSyncAt = false,
    int? lastRevision,
    Map<String, DateTime>? tombstones,
    Map<String, PromptPreviewHashCacheEntry>? previewHashCache,
  }) {
    return PromptLibrarySyncState(
      lastSyncAt: clearLastSyncAt ? null : (lastSyncAt ?? this.lastSyncAt),
      lastRevision: lastRevision ?? this.lastRevision,
      tombstones: tombstones ?? this.tombstones,
      previewHashCache: previewHashCache ?? this.previewHashCache,
    );
  }

  Map<String, dynamic> toJson() => {
    'lastSyncAt': lastSyncAt?.toUtc().toIso8601String(),
    'lastRevision': lastRevision,
    'tombstones': {
      for (final e in tombstones.entries) e.key: e.value.toUtc().toIso8601String(),
    },
    'previewHashCache': {
      for (final e in previewHashCache.entries) e.key: e.value.toJson(),
    },
  };

  factory PromptLibrarySyncState.fromJson(Map<String, dynamic> json) {
    final lastSyncRaw = json['lastSyncAt'];
    final lastSyncAt = lastSyncRaw is String
        ? DateTime.tryParse(lastSyncRaw)?.toUtc()
        : null;
    final lastRevision = json['lastRevision'] is int
        ? json['lastRevision'] as int
        : 0;

    final tombstones = <String, DateTime>{};
    final rawTombstones = json['tombstones'];
    if (rawTombstones is Map) {
      for (final entry in rawTombstones.entries) {
        final key = entry.key.toString().trim();
        final val = entry.value;
        if (key.isEmpty || val is! String) continue;
        final dt = DateTime.tryParse(val)?.toUtc();
        if (dt != null) tombstones[key] = dt;
      }
    }

    final hashCache = <String, PromptPreviewHashCacheEntry>{};
    final rawCache = json['previewHashCache'];
    if (rawCache is Map) {
      for (final entry in rawCache.entries) {
        final key = entry.key.toString();
        final val = entry.value;
        if (key.isEmpty || val is! Map<String, dynamic>) continue;
        final parsed = PromptPreviewHashCacheEntry.fromJson(val);
        if (parsed != null) hashCache[key] = parsed;
      }
    }

    return PromptLibrarySyncState(
      lastSyncAt: lastSyncAt,
      lastRevision: lastRevision,
      tombstones: tombstones,
      previewHashCache: hashCache,
    );
  }
}

/// 远端同步精准参考条目（图片内容以 SHA-256 存入 sync_images 去重）
class RemotePreciseRefRecord {
  final String id;
  final String imageHash;
  final String imageExt;
  final String? fileName;
  final NaiPreciseRefType type;
  final bool preferSameOutfit;
  final double strength;
  final double fidelity;
  final double informationExtracted;
  final bool enabled;

  const RemotePreciseRefRecord({
    required this.id,
    required this.imageHash,
    this.imageExt = 'png',
    this.fileName,
    this.type = NaiPreciseRefType.characterAndStyle,
    this.preferSameOutfit = true,
    this.strength = 1.0,
    this.fidelity = 1.0,
    this.informationExtracted = 1.0,
    this.enabled = true,
  });

  PromptLibraryPreciseRef? toLocal(String? Function(String hash) resolvePath) {
    final path = resolvePath(imageHash);
    if (path == null || path.trim().isEmpty) return null;
    return PromptLibraryPreciseRef(
      id: id,
      imagePath: path,
      fileName: fileName,
      type: type,
      preferSameOutfit: preferSameOutfit,
      strength: strength,
      fidelity: fidelity,
      informationExtracted: informationExtracted,
      enabled: enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'imageHash': imageHash,
    'imageExt': imageExt,
    if (fileName != null && fileName!.trim().isNotEmpty) 'fileName': fileName,
    'type': type.id,
    'preferSameOutfit': preferSameOutfit,
    'strength': strength,
    'fidelity': fidelity,
    'informationExtracted': informationExtracted,
    'enabled': enabled,
  };

  static RemotePreciseRefRecord? fromJson(Map<String, dynamic> json) {
    final rawHash = (json['imageHash'] as String?)?.trim().toLowerCase() ?? '';
    if (rawHash.length != 64) return null;
    final rawExt = (json['imageExt'] as String?)?.trim().toLowerCase() ?? 'png';
    final type = NaiPreciseRefType.fromId(json['type'] as String?);
    return RemotePreciseRefRecord(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : 'ref_${rawHash.substring(0, 8)}',
      imageHash: rawHash,
      imageExt: rawExt.isNotEmpty ? rawExt : 'png',
      fileName: (json['fileName'] as String?)?.trim(),
      type: type,
      preferSameOutfit: json['preferSameOutfit'] is bool
          ? json['preferSameOutfit'] as bool
          : type == NaiPreciseRefType.characterAndStyle,
      strength: (json['strength'] as num?)?.toDouble() ?? 1.0,
      fidelity: (json['fidelity'] as num?)?.toDouble() ?? 1.0,
      informationExtracted:
          (json['informationExtracted'] as num?)?.toDouble() ?? 1.0,
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
  }
}

/// 远端同步 Vibe Transfer 条目（原图/缩略图按 SHA-256 存 sync_images，编码向量直存）
class RemoteVibeRefRecord {
  final String id;
  final String displayName;
  final NaiVibeSourceType sourceType;
  final String? rawImageHash;
  final String? rawImageExt;
  final String? thumbnailHash;
  final String? thumbnailExt;
  final Map<String, String> encodingsByModel;
  final Map<String, double> encodedInfoExtractedByModel;
  final double strength;
  final double informationExtracted;
  final bool enabled;

  const RemoteVibeRefRecord({
    required this.id,
    required this.displayName,
    this.sourceType = NaiVibeSourceType.rawImage,
    this.rawImageHash,
    this.rawImageExt,
    this.thumbnailHash,
    this.thumbnailExt,
    this.encodingsByModel = const {},
    this.encodedInfoExtractedByModel = const {},
    this.strength = NaiVibeReference.defaultStrength,
    this.informationExtracted = NaiVibeReference.defaultInfoExtracted,
    this.enabled = true,
  });

  PromptLibraryVibeRef? toLocal(String? Function(String hash) resolvePath) {
    final rawPath = rawImageHash != null ? resolvePath(rawImageHash!) : null;
    final thumbPath =
        thumbnailHash != null ? resolvePath(thumbnailHash!) : null;
    if ((rawPath == null || rawPath.isEmpty) && encodingsByModel.isEmpty) {
      return null;
    }
    return PromptLibraryVibeRef(
      id: id,
      displayName: displayName,
      sourceType: sourceType,
      rawImagePath: rawPath,
      thumbnailPath: thumbPath,
      encodingsByModel: encodingsByModel,
      encodedInfoExtractedByModel: encodedInfoExtractedByModel,
      strength: strength,
      informationExtracted: informationExtracted,
      enabled: enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'sourceType': sourceType.name,
    if (rawImageHash != null) 'rawImageHash': rawImageHash,
    if (rawImageHash != null && rawImageExt != null) 'rawImageExt': rawImageExt,
    if (thumbnailHash != null) 'thumbnailHash': thumbnailHash,
    if (thumbnailHash != null && thumbnailExt != null)
      'thumbnailExt': thumbnailExt,
    if (encodingsByModel.isNotEmpty) 'encodingsByModel': encodingsByModel,
    if (encodedInfoExtractedByModel.isNotEmpty)
      'encodedInfoExtractedByModel': encodedInfoExtractedByModel,
    'strength': strength,
    'informationExtracted': informationExtracted,
    'enabled': enabled,
  };

  static NaiVibeSourceType _parseSourceType(String? raw) {
    return switch (raw?.trim()) {
      'naiv4vibe' => NaiVibeSourceType.naiv4vibe,
      'naiv4vibebundle' => NaiVibeSourceType.naiv4vibebundle,
      'pngEmbedded' => NaiVibeSourceType.pngEmbedded,
      _ => NaiVibeSourceType.rawImage,
    };
  }

  static RemoteVibeRefRecord? fromJson(Map<String, dynamic> json) {
    final rawHashRaw = (json['rawImageHash'] as String?)?.trim().toLowerCase();
    final rawImageHash =
        rawHashRaw != null && rawHashRaw.length == 64 ? rawHashRaw : null;
    final thumbHashRaw =
        (json['thumbnailHash'] as String?)?.trim().toLowerCase();
    final thumbnailHash =
        thumbHashRaw != null && thumbHashRaw.length == 64 ? thumbHashRaw : null;

    final encodings = <String, String>{};
    final rawEnc = json['encodingsByModel'];
    if (rawEnc is Map) {
      for (final e in rawEnc.entries) {
        final k = e.key.toString().trim();
        final v = e.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) encodings[k] = v;
      }
    }
    final infoMap = <String, double>{};
    final rawInfo = json['encodedInfoExtractedByModel'];
    if (rawInfo is Map) {
      for (final e in rawInfo.entries) {
        final k = e.key.toString().trim();
        final v = e.value;
        if (k.isNotEmpty && v is num) infoMap[k] = v.toDouble();
      }
    }
    if (rawImageHash == null && encodings.isEmpty) return null;

    final rawExt = (json['rawImageExt'] as String?)?.trim().toLowerCase();
    final thumbExt = (json['thumbnailExt'] as String?)?.trim().toLowerCase();
    return RemoteVibeRefRecord(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : 'vibe_${DateTime.now().microsecondsSinceEpoch}',
      displayName: (json['displayName'] as String?)?.trim().isNotEmpty == true
          ? (json['displayName'] as String).trim()
          : 'Vibe',
      sourceType: _parseSourceType(json['sourceType'] as String?),
      rawImageHash: rawImageHash,
      rawImageExt: rawImageHash != null
          ? (rawExt != null && rawExt.isNotEmpty ? rawExt : 'png')
          : null,
      thumbnailHash: thumbnailHash,
      thumbnailExt: thumbnailHash != null
          ? (thumbExt != null && thumbExt.isNotEmpty ? thumbExt : 'png')
          : null,
      encodingsByModel: encodings,
      encodedInfoExtractedByModel: infoMap,
      strength:
          (json['strength'] as num?)?.toDouble() ??
          NaiVibeReference.defaultStrength,
      informationExtracted:
          ((json['informationExtracted'] as num?)?.toDouble() ??
                  NaiVibeReference.defaultInfoExtracted)
              .clamp(0.01, 1.0)
              .toDouble(),
      enabled: json['enabled'] is bool ? json['enabled'] as bool : true,
    );
  }
}

/// 远端词条同步协议实体 (含删除墓碑与内容哈希)
class RemotePromptEntryRecord {
  final String id;
  final String title;
  final String category;
  final String prompt;
  final String negativePrompt;
  final String prefixPrompt;
  final String suffixPrompt;
  final List<String> tags;
  final bool isFavorite;
  final bool isBuiltin;
  final String? previewHash;
  final String? previewExt;
  final List<RemotePreciseRefRecord> preciseReferences;
  final List<RemoteVibeRefRecord> vibeReferences;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final int revision;

  const RemotePromptEntryRecord({
    required this.id,
    required this.title,
    required this.category,
    required this.prompt,
    this.negativePrompt = '',
    this.prefixPrompt = '',
    this.suffixPrompt = '',
    this.tags = const [],
    this.isFavorite = false,
    this.isBuiltin = false,
    this.previewHash,
    this.previewExt,
    this.preciseReferences = const [],
    this.vibeReferences = const [],
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
    this.revision = 0,
  });

  bool get isDeleted => deletedAt != null;

  DateTime get effectiveTimestamp => (deletedAt ?? updatedAt).toUtc();

  /// 该远端条目引用的全部图片 SHA-256 哈希（预览图 + 精准参考图 + Vibe 原图/缩略图）
  Iterable<String> get allReferencedImageHashes sync* {
    if (previewHash != null && previewHash!.isNotEmpty) yield previewHash!;
    for (final ref in preciseReferences) {
      if (ref.imageHash.isNotEmpty) yield ref.imageHash;
    }
    for (final vibe in vibeReferences) {
      if (vibe.rawImageHash != null && vibe.rawImageHash!.isNotEmpty) {
        yield vibe.rawImageHash!;
      }
      if (vibe.thumbnailHash != null && vibe.thumbnailHash!.isNotEmpty) {
        yield vibe.thumbnailHash!;
      }
    }
  }

  /// 按图片哈希查找扩展名提示
  String? extHintForHash(String hash) {
    if (previewHash == hash) return previewExt;
    for (final ref in preciseReferences) {
      if (ref.imageHash == hash) return ref.imageExt;
    }
    for (final vibe in vibeReferences) {
      if (vibe.rawImageHash == hash) return vibe.rawImageExt;
      if (vibe.thumbnailHash == hash) return vibe.thumbnailExt;
    }
    return null;
  }

  factory RemotePromptEntryRecord.fromLocalEntry(
    PromptComboEntry entry, {
    String? previewHash,
    String? previewExt,
    Map<String, ({String hash, String ext})> pathHashes = const {},
  }) {
    final remoteRefs = <RemotePreciseRefRecord>[];
    for (final ref in entry.preciseReferences) {
      final info = pathHashes[ref.imagePath.trim()];
      if (info == null) continue;
      remoteRefs.add(
        RemotePreciseRefRecord(
          id: ref.id,
          imageHash: info.hash,
          imageExt: info.ext,
          fileName: ref.fileName,
          type: ref.type,
          preferSameOutfit: ref.preferSameOutfit,
          strength: ref.strength,
          fidelity: ref.fidelity,
          informationExtracted: ref.informationExtracted,
          enabled: ref.enabled,
        ),
      );
    }

    final remoteVibes = <RemoteVibeRefRecord>[];
    for (final vibe in entry.vibeReferences) {
      final rawInfo = vibe.rawImagePath != null
          ? pathHashes[vibe.rawImagePath!.trim()]
          : null;
      final thumbInfo = vibe.thumbnailPath != null
          ? pathHashes[vibe.thumbnailPath!.trim()]
          : null;
      if (rawInfo == null && vibe.encodingsByModel.isEmpty) continue;
      remoteVibes.add(
        RemoteVibeRefRecord(
          id: vibe.id,
          displayName: vibe.displayName,
          sourceType: vibe.sourceType,
          rawImageHash: rawInfo?.hash,
          rawImageExt: rawInfo?.ext,
          thumbnailHash: thumbInfo?.hash,
          thumbnailExt: thumbInfo?.ext,
          encodingsByModel: vibe.encodingsByModel,
          encodedInfoExtractedByModel: vibe.encodedInfoExtractedByModel,
          strength: vibe.strength,
          informationExtracted: vibe.informationExtracted,
          enabled: vibe.enabled,
        ),
      );
    }

    return RemotePromptEntryRecord(
      id: entry.id,
      title: entry.title,
      category: entry.category,
      prompt: entry.prompt,
      negativePrompt: entry.supportsNegative ? entry.negativePrompt : '',
      prefixPrompt: entry.isStyle ? entry.prefixPrompt : '',
      suffixPrompt: entry.isStyle ? entry.suffixPrompt : '',
      tags: entry.tags,
      isFavorite: entry.isFavorite,
      isBuiltin: entry.isBuiltin,
      previewHash: previewHash,
      previewExt: previewExt,
      preciseReferences: remoteRefs,
      vibeReferences: remoteVibes,
      createdAt: entry.createdAt.toUtc(),
      updatedAt: entry.updatedAt.toUtc(),
    );
  }

  factory RemotePromptEntryRecord.tombstone({
    required String id,
    required DateTime deletedAt,
  }) {
    final utc = deletedAt.toUtc();
    return RemotePromptEntryRecord(
      id: id,
      title: '',
      category: PromptComboCategories.other,
      prompt: '',
      createdAt: utc,
      updatedAt: utc,
      deletedAt: utc,
    );
  }

  PromptComboEntry toLocalEntry({
    String? previewImagePath,
    String? Function(String hash)? resolveImagePath,
  }) {
    final resolver = resolveImagePath ?? (_) => null;
    final localRefs = preciseReferences
        .map((r) => r.toLocal(resolver))
        .whereType<PromptLibraryPreciseRef>()
        .toList(growable: false);
    final localVibes = vibeReferences
        .map((v) => v.toLocal(resolver))
        .whereType<PromptLibraryVibeRef>()
        .toList(growable: false);
    return PromptComboEntry(
      id: id,
      title: title,
      category: category,
      prompt: prompt,
      negativePrompt: PromptComboEntry.supportsNegativePrompt(category)
          ? negativePrompt
          : '',
      prefixPrompt: PromptComboEntry.isStyleCategory(category)
          ? prefixPrompt
          : '',
      suffixPrompt: PromptComboEntry.isStyleCategory(category)
          ? suffixPrompt
          : '',
      previewImagePath: previewImagePath,
      preciseReferences: localRefs,
      vibeReferences: localVibes,
      createdAt: createdAt.toLocal(),
      updatedAt: updatedAt.toLocal(),
      isFavorite: isFavorite,
      isBuiltin: isBuiltin,
      tags: tags,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'category': category,
    'prompt': prompt,
    'negativePrompt': PromptComboEntry.supportsNegativePrompt(category)
        ? negativePrompt
        : '',
    if (PromptComboEntry.isStyleCategory(category) && prefixPrompt.isNotEmpty)
      'prefixPrompt': prefixPrompt,
    if (PromptComboEntry.isStyleCategory(category) && suffixPrompt.isNotEmpty)
      'suffixPrompt': suffixPrompt,
    'tags': tags,
    'isFavorite': isFavorite,
    'isBuiltin': isBuiltin,
    'previewHash': previewHash,
    'previewExt': previewExt,
    if (preciseReferences.isNotEmpty)
      'preciseReferences': preciseReferences.map((r) => r.toJson()).toList(),
    if (vibeReferences.isNotEmpty)
      'vibeReferences': vibeReferences.map((v) => v.toJson()).toList(),
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'deletedAt': deletedAt?.toUtc().toIso8601String(),
  };

  factory RemotePromptEntryRecord.fromJson(Map<String, dynamic> json) {
    final fallbackNow = DateTime.now().toUtc();
    final createdAt = json['createdAt'] is String
        ? (DateTime.tryParse(json['createdAt'] as String)?.toUtc() ??
              fallbackNow)
        : fallbackNow;
    final updatedAt = json['updatedAt'] is String
        ? (DateTime.tryParse(json['updatedAt'] as String)?.toUtc() ??
              createdAt)
        : createdAt;
    final deletedRaw = json['deletedAt'];
    final deletedAt = deletedRaw is String && deletedRaw.trim().isNotEmpty
        ? DateTime.tryParse(deletedRaw)?.toUtc()
        : null;
    final cat = json['category'] as String? ?? PromptComboCategories.other;
    final allowNeg = PromptComboEntry.supportsNegativePrompt(cat);
    final allowStyle = PromptComboEntry.isStyleCategory(cat);
    final rawHash = json['previewHash'];
    final previewHash = rawHash is String && rawHash.trim().isNotEmpty
        ? rawHash.trim().toLowerCase()
        : null;
    final rawExt = json['previewExt'];
    final previewExt = previewHash != null && rawExt is String && rawExt.trim().isNotEmpty
        ? rawExt.trim().toLowerCase()
        : null;

    final preciseRefs = <RemotePreciseRefRecord>[];
    final rawRefs = json['preciseReferences'];
    if (rawRefs is List) {
      for (final item in rawRefs) {
        if (item is Map<String, dynamic>) {
          final parsed = RemotePreciseRefRecord.fromJson(item);
          if (parsed != null) preciseRefs.add(parsed);
        }
      }
    }

    final vibeRefs = <RemoteVibeRefRecord>[];
    final rawVibes = json['vibeReferences'];
    if (rawVibes is List) {
      for (final item in rawVibes) {
        if (item is Map<String, dynamic>) {
          final parsed = RemoteVibeRefRecord.fromJson(item);
          if (parsed != null) vibeRefs.add(parsed);
        }
      }
    }

    return RemotePromptEntryRecord(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      category: cat,
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: allowNeg ? (json['negativePrompt'] as String? ?? '') : '',
      prefixPrompt: allowStyle ? (json['prefixPrompt'] as String? ?? '') : '',
      suffixPrompt: allowStyle ? (json['suffixPrompt'] as String? ?? '') : '',
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
      isFavorite: json['isFavorite'] as bool? ?? false,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      previewHash: previewHash,
      previewExt: previewExt,
      preciseReferences: preciseRefs,
      vibeReferences: vibeRefs,
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: deletedAt,
      revision: (json['revision'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 云端健康检查统计响应
class PromptLibrarySyncHealth {
  final String namespace;
  final int revision;
  final int activeEntries;
  final int tombstoneEntries;
  final int imageCount;
  final int imageBytes;
  final DateTime serverTime;

  const PromptLibrarySyncHealth({
    required this.namespace,
    required this.revision,
    required this.activeEntries,
    required this.tombstoneEntries,
    required this.imageCount,
    required this.imageBytes,
    required this.serverTime,
  });

  factory PromptLibrarySyncHealth.fromJson(Map<String, dynamic> json) {
    return PromptLibrarySyncHealth(
      namespace: json['namespace'] as String? ?? 'default',
      revision: (json['revision'] as num?)?.toInt() ?? 0,
      activeEntries: (json['activeEntries'] as num?)?.toInt() ?? 0,
      tombstoneEntries: (json['tombstoneEntries'] as num?)?.toInt() ?? 0,
      imageCount: (json['imageCount'] as num?)?.toInt() ?? 0,
      imageBytes: (json['imageBytes'] as num?)?.toInt() ?? 0,
      serverTime: json['serverTime'] is String
          ? (DateTime.tryParse(json['serverTime'] as String)?.toUtc() ??
                DateTime.now().toUtc())
          : DateTime.now().toUtc(),
    );
  }
}

/// 一次云同步执行摘要
class PromptLibrarySyncResult {
  final PromptLibrarySyncMode mode;
  final int pushedEntries;
  final int pulledEntries;
  final int deletedLocal;
  final int deletedRemote;
  final int uploadedImages;
  final int downloadedImages;
  final int revision;
  final DateTime syncedAt;

  const PromptLibrarySyncResult({
    required this.mode,
    required this.pushedEntries,
    required this.pulledEntries,
    required this.deletedLocal,
    required this.deletedRemote,
    required this.uploadedImages,
    required this.downloadedImages,
    required this.revision,
    required this.syncedAt,
  });

  bool get hasChanges =>
      pushedEntries > 0 ||
      pulledEntries > 0 ||
      deletedLocal > 0 ||
      deletedRemote > 0 ||
      uploadedImages > 0 ||
      downloadedImages > 0;
}

/// 云同步业务异常 (携带可选 HTTP 状态码)
class PromptLibrarySyncException implements Exception {
  final String message;
  final int? statusCode;

  const PromptLibrarySyncException(this.message, {this.statusCode});

  @override
  String toString() =>
      statusCode != null ? '[$statusCode] $message' : message;
}
