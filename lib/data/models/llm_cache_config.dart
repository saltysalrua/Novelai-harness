/// Chat Completions 缓存兼容策略。关闭仅停止发送提示，不禁用上游自动缓存。
enum LlmCacheMode { auto, off, openai, anthropic }

/// 长缓存需端点明确支持：OpenAI 24h / Anthropic 1h，可能改变计费。
enum LlmCacheRetention { short, long }

/// 对齐 pi 的可选 session-affinity 格式，未知中转站默认不注入。
enum LlmCacheAffinity { off, openai, openrouter }

class LlmCacheConfig {
  final LlmCacheMode mode;
  final LlmCacheRetention retention;
  final LlmCacheAffinity affinity;

  const LlmCacheConfig({
    this.mode = LlmCacheMode.auto,
    this.retention = LlmCacheRetention.short,
    this.affinity = LlmCacheAffinity.off,
  });

  LlmCacheConfig copyWith({
    LlmCacheMode? mode,
    LlmCacheRetention? retention,
    LlmCacheAffinity? affinity,
  }) => LlmCacheConfig(
    mode: mode ?? this.mode,
    retention: retention ?? this.retention,
    affinity: affinity ?? this.affinity,
  );

  Map<String, dynamic> toJson() => {
    'mode': mode.name,
    'retention': retention.name,
    'affinity': affinity.name,
  };

  factory LlmCacheConfig.fromJson(Object? json) {
    if (json is! Map) return const LlmCacheConfig();
    T value<T extends Enum>(List<T> values, String key) => values.firstWhere(
      (value) => value.name == json[key],
      orElse: () => values.first,
    );
    return LlmCacheConfig(
      mode: value(LlmCacheMode.values, 'mode'),
      retention: value(LlmCacheRetention.values, 'retention'),
      affinity: value(LlmCacheAffinity.values, 'affinity'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LlmCacheConfig &&
          mode == other.mode &&
          retention == other.retention &&
          affinity == other.affinity;

  @override
  int get hashCode => Object.hash(mode, retention, affinity);
}
