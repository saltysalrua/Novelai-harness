/// NovelAI 账号、体力池与官方 Tag 联想响应数据模型。
library;

/// NovelAI 账号与体力信息
class NaiAccountInfo {
  final String tierName;
  final int tier;
  final bool active;
  final DateTime? expiresAt;
  final double staminaPercent;
  final int timeUntilNextPercent;
  final int totalAnlas;
  final int fixedAnlas;
  final int purchasedAnlas;
  final int taskPriority;
  final DateTime? nextRefillAt;
  final bool unlimitedFree;

  /// V5 体力配额池是否已透支 (透支后 Opus 免费额度失效，生图按正常价扣 Anlas)
  final bool v5QuotaExhausted;

  const NaiAccountInfo({
    required this.tierName,
    required this.tier,
    required this.active,
    this.expiresAt,
    required this.staminaPercent,
    required this.timeUntilNextPercent,
    required this.totalAnlas,
    required this.fixedAnlas,
    required this.purchasedAnlas,
    required this.taskPriority,
    this.nextRefillAt,
    required this.unlimitedFree,
    this.v5QuotaExhausted = false,
  });

  factory NaiAccountInfo.fromJson(Map<String, dynamic> json) {
    final sub = (json['subscription'] as Map<String, dynamic>?) ?? {};
    final priority = (json['priority'] as Map<String, dynamic>?) ?? {};
    final usage = (sub['usage'] as Map<String, dynamic>?) ?? {};
    final training = (sub['trainingStepsLeft'] as Map<String, dynamic>?) ?? {};
    final perks = (sub['perks'] as Map<String, dynamic>?) ?? {};

    final tier = sub['tier'] as int? ?? 0;
    const tierNames = ['Paper', 'Tablet', 'Scroll', 'Opus'];
    final tierName = tier >= 0 && tier < tierNames.length
        ? tierNames[tier]
        : 'Tier $tier';

    final expiresTimestamp = sub['expiresAt'] as int?;
    final refillTimestamp = priority['nextRefillAt'] as int?;

    final fixed = training['fixedTrainingStepsLeft'] as int? ?? 0;
    final purchased = training['purchasedTrainingSteps'] as int? ?? 0;

    return NaiAccountInfo(
      tierName: tierName,
      tier: tier,
      active: sub['active'] as bool? ?? false,
      expiresAt: expiresTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(expiresTimestamp * 1000)
          : null,
      staminaPercent: (usage['percent'] as num?)?.toDouble() ?? 100.0,
      timeUntilNextPercent: usage['timeUntilNextPercent'] as int? ?? 0,
      totalAnlas: fixed + purchased,
      fixedAnlas: fixed,
      purchasedAnlas: purchased,
      taskPriority:
          priority['taskPriority'] as int? ??
          (perks['startPriority'] as int? ?? 10),
      nextRefillAt: refillTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(refillTimestamp * 1000)
          : null,
      unlimitedFree: perks['unlimitedMaxPriority'] as bool? ?? false,
      v5QuotaExhausted: usage['isNegative'] as bool? ?? false,
    );
  }

  /// 账号是否拥有有效的 Opus 订阅权益 (决定生图免费折扣)
  bool get isOpus => tier >= 3 && active;
}

/// 官方 Danbooru Tag 联想数据
class NaiTagSuggestion {
  final String tag;
  final int count;
  final double confidence;

  const NaiTagSuggestion({
    required this.tag,
    required this.count,
    required this.confidence,
  });

  factory NaiTagSuggestion.fromJson(Map<String, dynamic> json) {
    return NaiTagSuggestion(
      tag: json['tag'] as String? ?? '',
      count: json['count'] as int? ?? 0,
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.0,
    );
  }
}
