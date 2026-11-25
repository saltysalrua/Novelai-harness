import 'nai_precise_reference.dart';
import 'nai_vibe_reference.dart';

/// 词组合预设分类常量
class PromptComboCategories {
  static const String character = '角色';
  static const String style = '风格';
  static const String attire = '服装';
  static const String composition = '构图';
  static const String environment = '环境';
  static const String effect = '特效';
  static const String other = '其他';

  static const List<String> defaults = [
    character,
    style,
    attire,
    composition,
    environment,
    effect,
    other,
  ];
}

/// 词库条目内保存的单张精准参考图配置
class PromptLibraryPreciseRef {
  final String id;
  final String imagePath;
  final String? fileName;
  final NaiPreciseRefType type;
  final bool preferSameOutfit;
  final double strength;
  final double fidelity;
  final double informationExtracted;
  final bool enabled;

  const PromptLibraryPreciseRef({
    required this.id,
    required this.imagePath,
    this.fileName,
    this.type = NaiPreciseRefType.characterAndStyle,
    this.preferSameOutfit = true,
    this.strength = 1.0,
    this.fidelity = 1.0,
    this.informationExtracted = 1.0,
    this.enabled = true,
  });

  PromptLibraryPreciseRef copyWith({
    String? id,
    String? imagePath,
    String? fileName,
    NaiPreciseRefType? type,
    bool? preferSameOutfit,
    double? strength,
    double? fidelity,
    double? informationExtracted,
    bool? enabled,
  }) {
    final nextType = type ?? this.type;
    final nextPreferSameOutfit =
        preferSameOutfit ??
        (type != null && type != this.type
            ? type == NaiPreciseRefType.characterAndStyle
            : this.preferSameOutfit);
    return PromptLibraryPreciseRef(
      id: id ?? this.id,
      imagePath: imagePath ?? this.imagePath,
      fileName: fileName ?? this.fileName,
      type: nextType,
      preferSameOutfit: nextPreferSameOutfit,
      strength: strength ?? this.strength,
      fidelity: fidelity ?? this.fidelity,
      informationExtracted: informationExtracted ?? this.informationExtracted,
      enabled: enabled ?? this.enabled,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'imagePath': imagePath,
    if (fileName != null && fileName!.trim().isNotEmpty) 'fileName': fileName,
    'type': type.id,
    'preferSameOutfit': preferSameOutfit,
    'strength': strength,
    'fidelity': fidelity,
    'informationExtracted': informationExtracted,
    'enabled': enabled,
  };

  factory PromptLibraryPreciseRef.fromJson(Map<String, dynamic> json) {
    final type = NaiPreciseRefType.fromId(json['type'] as String?);
    return PromptLibraryPreciseRef(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : 'lib_pref_${DateTime.now().microsecondsSinceEpoch}',
      imagePath: (json['imagePath'] as String?)?.trim() ?? '',
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

/// 词库条目内保存的单条 Vibe Transfer 配置（保留已编码向量，应用时无需重复花 2 Anlas 编码）
class PromptLibraryVibeRef {
  final String id;
  final String displayName;
  final NaiVibeSourceType sourceType;
  final String? rawImagePath;
  final String? thumbnailPath;
  final Map<String, String> encodingsByModel;
  final Map<String, double> encodedInfoExtractedByModel;
  final double strength;
  final double informationExtracted;
  final bool enabled;

  const PromptLibraryVibeRef({
    required this.id,
    required this.displayName,
    this.sourceType = NaiVibeSourceType.rawImage,
    this.rawImagePath,
    this.thumbnailPath,
    this.encodingsByModel = const {},
    this.encodedInfoExtractedByModel = const {},
    this.strength = NaiVibeReference.defaultStrength,
    this.informationExtracted = NaiVibeReference.defaultInfoExtracted,
    this.enabled = true,
  });

  /// 用于缩略图展示的本地路径（优先缩略图，回退原图）
  String? get displayImagePath {
    final thumb = thumbnailPath?.trim();
    if (thumb != null && thumb.isNotEmpty) return thumb;
    final raw = rawImagePath?.trim();
    if (raw != null && raw.isNotEmpty) return raw;
    return null;
  }

  /// 是否至少具备原图路径或模型预编码数据
  bool get hasImageOrEncoding =>
      (rawImagePath != null && rawImagePath!.trim().isNotEmpty) ||
      encodingsByModel.isNotEmpty;

  PromptLibraryVibeRef copyWith({
    String? id,
    String? displayName,
    NaiVibeSourceType? sourceType,
    String? rawImagePath,
    bool clearRawImagePath = false,
    String? thumbnailPath,
    bool clearThumbnailPath = false,
    Map<String, String>? encodingsByModel,
    Map<String, double>? encodedInfoExtractedByModel,
    double? strength,
    double? informationExtracted,
    bool? enabled,
  }) {
    return PromptLibraryVibeRef(
      id: id ?? this.id,
      displayName: displayName ?? this.displayName,
      sourceType: sourceType ?? this.sourceType,
      rawImagePath: clearRawImagePath
          ? null
          : (rawImagePath ?? this.rawImagePath),
      thumbnailPath: clearThumbnailPath
          ? null
          : (thumbnailPath ?? this.thumbnailPath),
      encodingsByModel: encodingsByModel ?? this.encodingsByModel,
      encodedInfoExtractedByModel:
          encodedInfoExtractedByModel ?? this.encodedInfoExtractedByModel,
      strength: strength ?? this.strength,
      informationExtracted: informationExtracted ?? this.informationExtracted,
      enabled: enabled ?? this.enabled,
    );
  }

  static NaiVibeSourceType _parseSourceType(String? raw) {
    return switch (raw?.trim()) {
      'naiv4vibe' => NaiVibeSourceType.naiv4vibe,
      'naiv4vibebundle' => NaiVibeSourceType.naiv4vibebundle,
      'pngEmbedded' => NaiVibeSourceType.pngEmbedded,
      _ => NaiVibeSourceType.rawImage,
    };
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'sourceType': sourceType.name,
    if (rawImagePath != null && rawImagePath!.trim().isNotEmpty)
      'rawImagePath': rawImagePath,
    if (thumbnailPath != null && thumbnailPath!.trim().isNotEmpty)
      'thumbnailPath': thumbnailPath,
    if (encodingsByModel.isNotEmpty) 'encodingsByModel': encodingsByModel,
    if (encodedInfoExtractedByModel.isNotEmpty)
      'encodedInfoExtractedByModel': encodedInfoExtractedByModel,
    'strength': strength,
    'informationExtracted': informationExtracted,
    'enabled': enabled,
  };

  factory PromptLibraryVibeRef.fromJson(Map<String, dynamic> json) {
    final encodings = <String, String>{};
    final rawEnc = json['encodingsByModel'];
    if (rawEnc is Map) {
      for (final e in rawEnc.entries) {
        final k = e.key.toString().trim();
        final v = e.value?.toString().trim() ?? '';
        if (k.isNotEmpty && v.isNotEmpty) {
          encodings[k] = v;
        }
      }
    }
    final infoMap = <String, double>{};
    final rawInfo = json['encodedInfoExtractedByModel'];
    if (rawInfo is Map) {
      for (final e in rawInfo.entries) {
        final k = e.key.toString().trim();
        final v = e.value;
        if (k.isNotEmpty && v is num) {
          infoMap[k] = v.toDouble();
        }
      }
    }
    final rawPath = (json['rawImagePath'] as String?)?.trim();
    final thumbPath = (json['thumbnailPath'] as String?)?.trim();
    return PromptLibraryVibeRef(
      id: (json['id'] as String?)?.trim().isNotEmpty == true
          ? (json['id'] as String).trim()
          : 'lib_vibe_${DateTime.now().microsecondsSinceEpoch}',
      displayName: (json['displayName'] as String?)?.trim().isNotEmpty == true
          ? (json['displayName'] as String).trim()
          : 'Vibe',
      sourceType: _parseSourceType(json['sourceType'] as String?),
      rawImagePath: rawPath != null && rawPath.isNotEmpty ? rawPath : null,
      thumbnailPath: thumbPath != null && thumbPath.isNotEmpty
          ? thumbPath
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

/// 词组合条目模型 (Prompt Combo Entry)
class PromptComboEntry {
  final String id;
  final String title;
  final String category;
  final String prompt;
  final String negativePrompt;
  final String prefixPrompt;
  final String suffixPrompt;
  final String? previewImagePath;
  final List<PromptLibraryPreciseRef> preciseReferences;
  final List<PromptLibraryVibeRef> vibeReferences;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isFavorite;
  final bool isBuiltin;
  final List<String> tags;

  const PromptComboEntry({
    required this.id,
    required this.title,
    this.category = PromptComboCategories.character,
    this.prompt = '',
    this.negativePrompt = '',
    this.prefixPrompt = '',
    this.suffixPrompt = '',
    this.previewImagePath,
    this.preciseReferences = const [],
    this.vibeReferences = const [],
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.isBuiltin = false,
    this.tags = const [],
  });

  /// 判断某分类名称是否属于“角色”分类 (中文或英文拼写)
  static bool isCharacterCategory(String category) {
    final c = category.trim().toLowerCase();
    return c == '角色' || c == 'character';
  }

  /// 判断某分类名称是否属于“风格 / 画风”分类 (中文或英文拼写)
  static bool isStyleCategory(String category) {
    final c = category.trim().toLowerCase();
    return c == '风格' || c == '画风' || c == 'style';
  }

  /// 判断某分类是否允许配置与应用负面提示词 (角色与风格分类均支持)
  static bool supportsNegativePrompt(String category) =>
      isCharacterCategory(category) || isStyleCategory(category);

  /// 是否属于角色分类
  bool get isCharacter => isCharacterCategory(category);

  /// 是否属于风格 / 画风分类
  bool get isStyle => isStyleCategory(category);

  /// 是否支持负面提示词
  bool get supportsNegative => supportsNegativePrompt(category);

  /// 是否包含结构化画风字段 (前缀 / 后缀 / 负面词)
  bool get hasStyleFields =>
      isStyle &&
      (prefixPrompt.trim().isNotEmpty ||
          suffixPrompt.trim().isNotEmpty ||
          negativePrompt.trim().isNotEmpty);

  /// 画风有效前置词：优先返回 prefixPrompt；兼容旧版仅填写 prompt 的风格条目
  String get effectiveStylePrefix {
    final p = prefixPrompt.trim();
    if (p.isNotEmpty) return p;
    if (isStyle && suffixPrompt.trim().isEmpty) {
      return prompt.trim();
    }
    return '';
  }

  /// 是否包含文本提示词内容
  bool get hasPromptText {
    if (isStyle) {
      return prefixPrompt.trim().isNotEmpty ||
          suffixPrompt.trim().isNotEmpty ||
          negativePrompt.trim().isNotEmpty ||
          prompt.trim().isNotEmpty;
    }
    return prompt.trim().isNotEmpty;
  }

  /// 是否包含关联的精准参考图
  bool get hasPreciseReferences => preciseReferences.isNotEmpty;

  /// 是否包含关联的 Vibe Transfer
  bool get hasVibeReferences => vibeReferences.isNotEmpty;

  /// 是否包含任意参考引导 (精准参考或 Vibe)
  bool get hasReferenceGuides => hasPreciseReferences || hasVibeReferences;

  /// 条目引用的全部本地托管图片路径（预览图 + 精准参考图 + Vibe 原图/缩略图）
  Iterable<String> get managedImagePaths sync* {
    final preview = previewImagePath?.trim();
    if (preview != null && preview.isNotEmpty) yield preview;
    for (final ref in preciseReferences) {
      final path = ref.imagePath.trim();
      if (path.isNotEmpty) yield path;
    }
    for (final vibe in vibeReferences) {
      final raw = vibe.rawImagePath?.trim();
      if (raw != null && raw.isNotEmpty) yield raw;
      final thumb = vibe.thumbnailPath?.trim();
      if (thumb != null && thumb.isNotEmpty) yield thumb;
    }
  }

  /// 条目是否至少包含一项有效内容（文本提示词、精准参考或 Vibe）
  bool get hasEffectiveContent => hasPromptText || hasReferenceGuides;

  /// 用于卡片与弹窗展示的摘要文本
  String get displayPromptSummary {
    String textSummary;
    if (!isStyle) {
      textSummary = prompt.trim();
    } else {
      final parts = <String>[];
      final prefix = prefixPrompt.trim();
      final suffix = suffixPrompt.trim();
      final negative = negativePrompt.trim();
      if (prefix.isNotEmpty) parts.add('前缀: $prefix');
      if (suffix.isNotEmpty) parts.add('后缀: $suffix');
      if (negative.isNotEmpty) parts.add('负面: $negative');
      if (parts.isEmpty && prompt.trim().isNotEmpty) {
        textSummary = prompt.trim();
      } else {
        textSummary = parts.join('\n');
      }
    }
    if (textSummary.isNotEmpty) return textSummary;
    final refParts = <String>[
      if (preciseReferences.isNotEmpty) '精准参考 ×${preciseReferences.length}',
      if (vibeReferences.isNotEmpty) 'Vibe ×${vibeReferences.length}',
    ];
    return refParts.join(' · ');
  }

  PromptComboEntry copyWith({
    String? id,
    String? title,
    String? category,
    String? prompt,
    String? negativePrompt,
    String? prefixPrompt,
    String? suffixPrompt,
    String? previewImagePath,
    bool clearPreviewImage = false,
    List<PromptLibraryPreciseRef>? preciseReferences,
    List<PromptLibraryVibeRef>? vibeReferences,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    bool? isBuiltin,
    List<String>? tags,
  }) {
    final nextCategory = category ?? this.category;
    final allowNeg = supportsNegativePrompt(nextCategory);
    final allowStyle = isStyleCategory(nextCategory);
    return PromptComboEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      category: nextCategory,
      prompt: prompt ?? this.prompt,
      // 仅角色与风格分类保留负面提示词，其余分类自动清空
      negativePrompt: allowNeg ? (negativePrompt ?? this.negativePrompt) : '',
      // 仅风格分类保留前置与后置词缀，其余分类自动清空
      prefixPrompt: allowStyle ? (prefixPrompt ?? this.prefixPrompt) : '',
      suffixPrompt: allowStyle ? (suffixPrompt ?? this.suffixPrompt) : '',
      previewImagePath: clearPreviewImage
          ? null
          : (previewImagePath ?? this.previewImagePath),
      preciseReferences: preciseReferences ?? this.preciseReferences,
      vibeReferences: vibeReferences ?? this.vibeReferences,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isFavorite: isFavorite ?? this.isFavorite,
      isBuiltin: isBuiltin ?? this.isBuiltin,
      tags: tags ?? this.tags,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'category': category,
      'prompt': prompt,
      'negativePrompt': supportsNegative ? negativePrompt : '',
      if (isStyle && prefixPrompt.isNotEmpty) 'prefixPrompt': prefixPrompt,
      if (isStyle && suffixPrompt.isNotEmpty) 'suffixPrompt': suffixPrompt,
      'previewImagePath': previewImagePath,
      if (preciseReferences.isNotEmpty)
        'preciseReferences': preciseReferences.map((r) => r.toJson()).toList(),
      if (vibeReferences.isNotEmpty)
        'vibeReferences': vibeReferences.map((v) => v.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'isFavorite': isFavorite,
      'isBuiltin': isBuiltin,
      'tags': tags,
    };
  }

  factory PromptComboEntry.fromJson(Map<String, dynamic> json) {
    final cat = json['category'] as String? ?? PromptComboCategories.character;
    final allowNeg = supportsNegativePrompt(cat);
    final allowStyle = isStyleCategory(cat);
    final rawRefs = json['preciseReferences'];
    final preciseRefs = <PromptLibraryPreciseRef>[];
    if (rawRefs is List) {
      for (final item in rawRefs) {
        if (item is Map<String, dynamic>) {
          final parsed = PromptLibraryPreciseRef.fromJson(item);
          if (parsed.imagePath.isNotEmpty) {
            preciseRefs.add(parsed);
          }
        }
      }
    }
    final rawVibes = json['vibeReferences'];
    final vibeRefs = <PromptLibraryVibeRef>[];
    if (rawVibes is List) {
      for (final item in rawVibes) {
        if (item is Map<String, dynamic>) {
          final parsed = PromptLibraryVibeRef.fromJson(item);
          if (parsed.hasImageOrEncoding) {
            vibeRefs.add(parsed);
          }
        }
      }
    }
    return PromptComboEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名预设',
      category: cat,
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: allowNeg ? (json['negativePrompt'] as String? ?? '') : '',
      prefixPrompt: allowStyle ? (json['prefixPrompt'] as String? ?? '') : '',
      suffixPrompt: allowStyle ? (json['suffixPrompt'] as String? ?? '') : '',
      previewImagePath: json['previewImagePath'] as String?,
      preciseReferences: preciseRefs,
      vibeReferences: vibeRefs,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      updatedAt: json['updatedAt'] != null
          ? DateTime.tryParse(json['updatedAt'] as String) ?? DateTime.now()
          : DateTime.now(),
      isFavorite: json['isFavorite'] as bool? ?? false,
      isBuiltin: json['isBuiltin'] as bool? ?? false,
      tags:
          (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  @override
  String toString() =>
      'PromptComboEntry(id: $id, title: $title, category: $category, isCharacter: $isCharacter, isStyle: $isStyle, refs: ${preciseReferences.length}, vibes: ${vibeReferences.length})';
}
