import 'tag_models.dart';

/// 中文名首段截取 (与 Plana-App cnHead 同款逻辑)：
/// 逗号多段取首段，首段不含汉字视为上游未译出，返回 null。
String? danbooruCnHead(String cnName) {
  if (cnName.isEmpty) return null;
  var cut = cnName.length;
  for (final sep in const [',', '，']) {
    final i = cnName.indexOf(sep);
    if (i >= 0 && i < cut) cut = i;
  }
  final head = cnName.substring(0, cut).trim();
  if (head.isEmpty) return null;
  final hasCjk = head.runes.any((r) => r >= 0x4E00 && r <= 0x9FFF);
  return hasCjk ? head : null;
}

/// DanbooruSearch 在线语义搜词结果条目 (HF Space /api/search)
class DanbooruSearchResult {
  final String tag;

  /// 原始中文名串 (逗号分隔多段：中文名、出处、分类词)，取首段见 [cnHead]
  final String cnName;
  final DanbooruTagCategory category;
  final int count;

  /// 一句话中文简介 (Danbooru wiki 摘要)
  final String wiki;
  final double score;

  const DanbooruSearchResult({
    required this.tag,
    this.cnName = '',
    this.category = DanbooruTagCategory.general,
    this.count = 0,
    this.wiki = '',
    this.score = 0.0,
  });

  String? get cnHead => danbooruCnHead(cnName);

  factory DanbooruSearchResult.fromJson(Map<String, dynamic> json) {
    return DanbooruSearchResult(
      tag: (json['tag'] as String? ?? '').trim(),
      cnName: (json['cn_name'] as String? ?? '').trim(),
      category: _categoryFromName(json['category'] as String?),
      count: (json['count'] as num?)?.toInt() ?? 0,
      wiki: (json['wiki'] as String? ?? '').trim(),
      score: (json['final_score'] as num?)?.toDouble() ?? 0.0,
    );
  }

  /// 转换为补全建议条目 (供补全悬浮窗使用)
  ///
  /// 分数排在离线结果之前 (离线前缀满分 1500、中文前缀 1000)，
  /// 语义命中的查询本身就是中文描述，理应优先展示。
  TagSuggestion toTagSuggestion() {
    return TagSuggestion(
      tag: tag.replaceAll('_', ' '),
      category: category,
      postCount: count,
      translation: cnHead ?? (wiki.isNotEmpty ? wiki : null),
      score: 2000.0 + score * 100.0,
    );
  }
}

/// DanbooruSearch 关联推荐条目 (HF Space /api/related，标签共现)
class DanbooruRelatedTag {
  final String tag;
  final String cnName;
  final DanbooruTagCategory category;
  final String wiki;

  /// 该推荐由哪些种子标签的共现关系产生
  final List<String> sources;

  const DanbooruRelatedTag({
    required this.tag,
    this.cnName = '',
    this.category = DanbooruTagCategory.general,
    this.wiki = '',
    this.sources = const [],
  });

  String? get cnHead => danbooruCnHead(cnName);

  factory DanbooruRelatedTag.fromJson(Map<String, dynamic> json) {
    return DanbooruRelatedTag(
      tag: (json['tag'] as String? ?? '').trim(),
      cnName: (json['cn_name'] as String? ?? '').trim(),
      category: _categoryFromName(json['category'] as String?),
      wiki: (json['wiki'] as String? ?? '').trim(),
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// DanbooruSearch 推荐擅长画师条目 (HF Space /api/artists，标签-画师 NPMI 共现)
class DanbooruArtistRecommendation {
  final String artist;

  /// 命中标签与该画师的总共现次数
  final int coocCount;

  /// 该画师在 Danbooru 的总发帖数
  final int postCount;

  /// 命中的种子标签
  final List<String> sources;

  /// 该画师最常绘制的标签 (附中文译名)
  final List<String> topTags;

  const DanbooruArtistRecommendation({
    required this.artist,
    this.coocCount = 0,
    this.postCount = 0,
    this.sources = const [],
    this.topTags = const [],
  });

  factory DanbooruArtistRecommendation.fromJson(Map<String, dynamic> json) {
    return DanbooruArtistRecommendation(
      artist: (json['artist'] as String? ?? '').trim(),
      coocCount: (json['cooc_count'] as num?)?.toInt() ?? 0,
      postCount: (json['post_count'] as num?)?.toInt() ?? 0,
      sources: (json['sources'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      topTags: (json['top_tags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
    );
  }
}

/// 服务端返回的分类字符串 -> 本地枚举
DanbooruTagCategory _categoryFromName(String? name) {
  switch (name?.trim().toLowerCase()) {
    case 'artist':
      return DanbooruTagCategory.artist;
    case 'copyright':
      return DanbooruTagCategory.copyright;
    case 'character':
      return DanbooruTagCategory.character;
    case 'meta':
      return DanbooruTagCategory.meta;
    default:
      return DanbooruTagCategory.general;
  }
}
