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
    required this.prompt,
    this.negativePrompt = '',
    this.previewImagePath,
    required this.createdAt,
    required this.updatedAt,
    this.isFavorite = false,
    this.isBuiltin = false,
    this.tags = const [],
  });

  /// 判断某分类名称是否属于“角色”分类 (中文或英文拼写)
  ///
  /// 角色分类才允许配置与应用负面提示词，全项目统一走此判断
  static bool isCharacterCategory(String category) {
    final c = category.trim().toLowerCase();
    return c == '角色' || c == 'character';
  }

  /// 是否属于角色分类 (角色分类才允许配置与应用负面提示词)
  bool get isCharacter => isCharacterCategory(category);

  PromptComboEntry copyWith({
    String? id,
    String? title,
    String? category,
    String? prompt,
    String? negativePrompt,
    String? previewImagePath,
    bool clearPreviewImage = false,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isFavorite,
    bool? isBuiltin,
    List<String>? tags,
  }) {
    final nextCategory = category ?? this.category;
    final isChar = isCharacterCategory(nextCategory);
    return PromptComboEntry(
      id: id ?? this.id,
      title: title ?? this.title,
      category: nextCategory,
      prompt: prompt ?? this.prompt,
      // 如果不是角色分类，自动将负面提示词清空
      negativePrompt: isChar ? (negativePrompt ?? this.negativePrompt) : '',
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
      'negativePrompt': isCharacter ? negativePrompt : '',
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
    final isChar = isCharacterCategory(cat);
    return PromptComboEntry(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? '未命名预设',
      category: cat,
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: isChar ? (json['negativePrompt'] as String? ?? '') : '',
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
      'PromptComboEntry(id: $id, title: $title, category: $category, isCharacter: $isCharacter)';
}
