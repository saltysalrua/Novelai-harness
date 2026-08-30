import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Danbooru 标签分类标准 (官方 0/1/3/4/5 规范)
enum DanbooruTagCategory {
  general(0, '通用', Color(0xFF555555)),
  artist(1, '画师', Color(0xFF8E44AD)),
  copyright(3, '作品', Color(0xFFD81B60)),
  character(4, '角色', Color(0xFF2E7D32)),
  meta(5, '元数据', Color(0xFFE67E22));

  final int code;
  final String label;
  final Color color;

  const DanbooruTagCategory(this.code, this.label, this.color);

  static DanbooruTagCategory fromCode(dynamic code) {
    final c = switch (code) {
      int i => i,
      String s => int.tryParse(s) ?? 0,
      _ => 0,
    };
    return switch (c) {
      1 => DanbooruTagCategory.artist,
      3 => DanbooruTagCategory.copyright,
      4 => DanbooruTagCategory.character,
      5 => DanbooruTagCategory.meta,
      _ => DanbooruTagCategory.general,
    };
  }
}

/// 格式化热度数字 (如 6008644 -> "6.0M", 152000 -> "152K", 980 -> "980")
String formatTagCount(int count) {
  if (count <= 0) return '';
  if (count >= 1000000) {
    final m = count / 1000000;
    return '${m.toStringAsFixed(m >= 10 ? 0 : 1)}M';
  }
  if (count >= 1000) {
    final k = count / 1000;
    return '${k.toStringAsFixed(k >= 100 ? 0 : 1)}K';
  }
  return '$count';
}

/// 补全建议条目
class TagSuggestion {
  final String tag;
  final DanbooruTagCategory category;
  final int postCount;
  final String? translation;
  final List<String> aliases;
  final String? matchedAlias;
  final double score;

  /// 自定义插入文本 (若为词组合等复合条目，插入完整 prompt；为空时插入 tag)
  final String? insertText;

  /// 自定义分类标签 (如 "风格", "服装", "特效" 等，非空时覆盖标准分类显示)
  final String? customCategoryLabel;

  /// 是否为来自词库的复合提示词组合
  final bool isPromptCombo;

  const TagSuggestion({
    required this.tag,
    this.category = DanbooruTagCategory.general,
    this.postCount = 0,
    this.translation,
    this.aliases = const [],
    this.matchedAlias,
    this.score = 0.0,
    this.insertText,
    this.customCategoryLabel,
    this.isPromptCombo = false,
  });

  String get formattedCount => formatTagCount(postCount);
}

/// 单枚 NovelAI 标签的精准分词视图 (包含在原始字符串中的绝对坐标下标)
///
/// 结构模型：`~ {{ [ N::name:: ] }} ~`
/// - seg: 完整区间 (含 `~` 禁用符与所有权重语法)
/// - core: 剥除 `~` 后的核心部分 (括号 + 数值 + 名字)
/// - inner: 剥除外层 `{}`/`[]` 括号后的部分 (数值 + 名字)
/// - name: 最内层干净的名字文本
class NaiPromptToken {
  final int segStart;
  final int segEnd;
  final int coreStart;
  final int coreEnd;
  final int innerStart;
  final int innerEnd;
  final int nameStart;
  final int nameEnd;

  final String name;
  final int braceLevel; // 净括号层数 (+n 表示 {}，-n 表示 [])
  final double numMult; // 内层数值倍率 (无则 1.0)
  final bool disabled; // 是否禁用 (~tag~)
  final String? translation;
  final DanbooruTagCategory? category;

  const NaiPromptToken({
    required this.segStart,
    required this.segEnd,
    required this.coreStart,
    required this.coreEnd,
    required this.innerStart,
    required this.innerEnd,
    required this.nameStart,
    required this.nameEnd,
    required this.name,
    this.braceLevel = 0,
    this.numMult = 1.0,
    this.disabled = false,
    this.translation,
    this.category,
  });

  /// 自身倍率 (数值 × 1.05^braceLevel)
  double get ownMultiplier => numMult * math.pow(1.05, braceLevel).toDouble();

  /// 综合有效倍率
  double get effectiveMultiplier => ownMultiplier;
}
