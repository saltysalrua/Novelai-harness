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

  /// 条目是否至少包含一项有效提示词内容
  bool get hasEffectiveContent {
    if (isStyle) {
      return prefixPrompt.trim().isNotEmpty ||
          suffixPrompt.trim().isNotEmpty ||
          negativePrompt.trim().isNotEmpty ||
          prompt.trim().isNotEmpty;
    }
    return prompt.trim().isNotEmpty;
  }

  /// 用于卡片与弹窗展示的摘要文本
  String get displayPromptSummary {
    if (!isStyle) return prompt;
    final parts = <String>[];
    final prefix = prefixPrompt.trim();
    final suffix = suffixPrompt.trim();
    final negative = negativePrompt.trim();
    if (prefix.isNotEmpty) parts.add('前缀: $prefix');
    if (suffix.isNotEmpty) parts.add('后缀: $suffix');
    if (negative.isNotEmpty) parts.add('负面: $negative');
    if (parts.isEmpty && prompt.trim().isNotEmpty) {
      return prompt;
    }
    return parts.join('\n');
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
    return PromptComboEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名预设',
      category: cat,
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: allowNeg ? (json['negativePrompt'] as String? ?? '') : '',
      prefixPrompt: allowStyle ? (json['prefixPrompt'] as String? ?? '') : '',
      suffixPrompt: allowStyle ? (json['suffixPrompt'] as String? ?? '') : '',
      previewImagePath: json['previewImagePath'] as String?,
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
      'PromptComboEntry(id: $id, title: $title, category: $category, isCharacter: $isCharacter, isStyle: $isStyle)';
}
