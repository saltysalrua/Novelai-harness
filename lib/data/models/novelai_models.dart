
/// NovelAI 官方支持的模型列表
enum NaiModel {
  v5Full('nai-diffusion-5-full', 'V5 旗舰版 (最新)'),
  v5Curated('nai-diffusion-5-curated', 'V5 审美精选版'),
  v45Full('nai-diffusion-4-5-full', 'V4.5 旗舰版'),
  v45Curated('nai-diffusion-4-5-curated', 'V4.5 审美精选版'),
  v4Full('nai-diffusion-4-full', 'V4 经典版'),
  v4Curated('nai-diffusion-4-curated', 'V4 精选版'),
  v3('nai-diffusion-3', 'V3 动漫经典版'),
  v3Furry('nai-diffusion-furry-3', 'V3 Furry 兽人版');

  final String id;
  final String label;
  const NaiModel(this.id, this.label);

  static NaiModel fromId(String id) {
    return NaiModel.values.firstWhere(
      (m) => m.id == id,
      orElse: () => NaiModel.v5Full,
    );
  }

  bool get isV4OrAbove =>
      id.startsWith('nai-diffusion-5') || id.startsWith('nai-diffusion-4');
}

/// 采样算法
enum NaiSampler {
  kEuler('k_euler', 'Euler (快速清晰)'),
  kEulerAncestral('k_euler_ancestral', 'Euler A (柔和生动)'),
  kDpmpp2m('k_dpmpp_2m', 'DPM++ 2M (高质量收敛)'),
  kDpmpp2sAncestral('k_dpmpp_2s_ancestral', 'DPM++ 2S A'),
  kDpmppSde('k_dpmpp_sde', 'DPM++ SDE (细腻质感)'),
  ddim('ddim', 'DDIM'),
  kDpm2('k_dpm_2', 'DPM2'),
  kDpm2Ancestral('k_dpm_2_ancestral', 'DPM2 A'),
  kDpmAdaptive('k_dpm_adaptive', 'DPM Adaptive');

  final String id;
  final String label;
  const NaiSampler(this.id, this.label);

  static NaiSampler fromId(String id) {
    return NaiSampler.values.firstWhere(
      (s) => s.id == id,
      orElse: () => NaiSampler.kEuler,
    );
  }
}

/// 噪声计划
enum NoiseSchedule {
  karras('karras', 'Karras (推荐高频细节)'),
  exponential('exponential', 'Exponential (指数调度)'),
  polyexponential('polyexponential', 'Polyexponential'),
  native('native', 'Native (原生)'),
  linear('linear', 'Linear (线性)');

  final String id;
  final String label;
  const NoiseSchedule(this.id, this.label);

  static NoiseSchedule fromId(String id) {
    return NoiseSchedule.values.firstWhere(
      (n) => n.id == id,
      orElse: () => NoiseSchedule.karras,
    );
  }
}

/// 分辨率预设
enum ResolutionPreset {
  portrait('portrait', '标准竖屏', 832, 1216, true),
  landscape('landscape', '标准横屏', 1216, 832, true),
  square('square', '标准正方形', 1024, 1024, true),
  wallpaper('wallpaper', '超宽壁纸', 1920, 1088, false),
  portraitLarge('portrait_large', '大竖屏', 1024, 1536, false),
  landscapeLarge('landscape_large', '大横屏', 1536, 1024, false);

  final String key;
  final String label;
  final int width;
  final int height;
  final bool isOpusFree;

  const ResolutionPreset(
    this.key,
    this.label,
    this.width,
    this.height,
    this.isOpusFree,
  );

  static ResolutionPreset fromKey(String key) {
    return ResolutionPreset.values.firstWhere(
      (r) => r.key == key,
      orElse: () => ResolutionPreset.portrait,
    );
  }
}

/// 图像生成请求参数
class NaiGenerationParams {
  final String prompt;
  final String negativePrompt;
  final NaiModel model;
  final int width;
  final int height;
  final int steps;
  final double scale;
  final double cfgRescale;
  final NaiSampler sampler;
  final NoiseSchedule noiseSchedule;
  final int seed;
  final int nSamples;
  final bool qualityToggle;
  final int ucPreset;
  final String? prefixPrompt;
  final String? suffixPrompt;
  final bool applyFixedPrompts;

  const NaiGenerationParams({
    required this.prompt,
    this.negativePrompt = '',
    this.model = NaiModel.v5Full,
    this.width = 832,
    this.height = 1216,
    this.steps = 28,
    this.scale = 5.0,
    this.cfgRescale = 0.0,
    this.sampler = NaiSampler.kEuler,
    this.noiseSchedule = NoiseSchedule.karras,
    this.seed = -1,
    this.nSamples = 1,
    this.qualityToggle = true,
    this.ucPreset = 0,
    this.prefixPrompt,
    this.suffixPrompt,
    this.applyFixedPrompts = true,
  });

  /// 组合最终正向词
  String get finalPrompt {
    if (!applyFixedPrompts) return prompt.trim();
    final parts = <String>[];
    if (prefixPrompt != null && prefixPrompt!.trim().isNotEmpty) {
      parts.add(prefixPrompt!.trim());
    }
    if (prompt.trim().isNotEmpty) {
      parts.add(prompt.trim());
    }
    if (suffixPrompt != null && suffixPrompt!.trim().isNotEmpty) {
      parts.add(suffixPrompt!.trim());
    }
    return parts.join(', ');
  }

  /// 判定是否符合 Opus 免点数条件 (像素数 <= 1048576 且 步数 <= 28 且 样本数 = 1)
  bool get isOpusFree =>
      width * height <= 1048576 && steps <= 28 && nSamples == 1;

  /// 构建发送给 NovelAI 官方的 JSON 请求体
  Map<String, dynamic> toApiPayload() {
    final effectivePrompt = finalPrompt;
    final isV4OrAbove = model.isV4OrAbove;

    final baseParameters = <String, dynamic>{
      'width': width,
      'height': height,
      'scale': scale,
      'scale_rescale': cfgRescale,
      'sampler': sampler.id,
      'noise_schedule': noiseSchedule.id,
      'steps': steps,
      'n_samples': nSamples,
      'ucPreset': ucPreset,
      'qualityToggle': qualityToggle,
      'dynamic_thresholding': false,
      'controlnet_strength': 1.0,
      'legacy': false,
      'negative_prompt': negativePrompt,
      'seed': seed,
      'sm': false,
      'sm_dyn': false,
      'add_original_image': false,
    };

    if (isV4OrAbove) {
      return {
        'input': effectivePrompt,
        'model': model.id,
        'action': 'generate',
        'parameters': {
          ...baseParameters,
          'use_coords': false,
          'characterPrompts': [],
          'v4_prompt': {
            'caption': {
              'base_caption': effectivePrompt,
              'char_captions': [],
            },
            'use_coords': false,
            'use_order': true,
          },
          'v4_negative_prompt': {
            'caption': {
              'base_caption': negativePrompt,
              'char_captions': [],
            },
          },
        },
      };
    }

    return {
      'input': effectivePrompt,
      'model': model.id,
      'action': 'generate',
      'parameters': baseParameters,
    };
  }

  NaiGenerationParams copyWith({
    String? prompt,
    String? negativePrompt,
    NaiModel? model,
    int? width,
    int? height,
    int? steps,
    double? scale,
    double? cfgRescale,
    NaiSampler? sampler,
    NoiseSchedule? noiseSchedule,
    int? seed,
    int? nSamples,
    bool? qualityToggle,
    int? ucPreset,
    String? prefixPrompt,
    String? suffixPrompt,
    bool? applyFixedPrompts,
  }) {
    return NaiGenerationParams(
      prompt: prompt ?? this.prompt,
      negativePrompt: negativePrompt ?? this.negativePrompt,
      model: model ?? this.model,
      width: width ?? this.width,
      height: height ?? this.height,
      steps: steps ?? this.steps,
      scale: scale ?? this.scale,
      cfgRescale: cfgRescale ?? this.cfgRescale,
      sampler: sampler ?? this.sampler,
      noiseSchedule: noiseSchedule ?? this.noiseSchedule,
      seed: seed ?? this.seed,
      nSamples: nSamples ?? this.nSamples,
      qualityToggle: qualityToggle ?? this.qualityToggle,
      ucPreset: ucPreset ?? this.ucPreset,
      prefixPrompt: prefixPrompt ?? this.prefixPrompt,
      suffixPrompt: suffixPrompt ?? this.suffixPrompt,
      applyFixedPrompts: applyFixedPrompts ?? this.applyFixedPrompts,
    );
  }
}

/// 生成结果单张图片数据与元信息
class NaiGeneratedImage {
  final String id;
  final List<int> bytes;
  final String? localFilePath;
  final NaiGenerationParams params;
  final DateTime createdAt;
  final int seed;
  final bool isOpusFree;

  const NaiGeneratedImage({
    required this.id,
    required this.bytes,
    this.localFilePath,
    required this.params,
    required this.createdAt,
    required this.seed,
    required this.isOpusFree,
  });
}

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
  });

  factory NaiAccountInfo.fromJson(Map<String, dynamic> json) {
    final sub = (json['subscription'] as Map<String, dynamic>?) ?? {};
    final priority = (json['priority'] as Map<String, dynamic>?) ?? {};
    final usage = (sub['usage'] as Map<String, dynamic>?) ?? {};
    final training = (sub['trainingStepsLeft'] as Map<String, dynamic>?) ?? {};
    final perks = (sub['perks'] as Map<String, dynamic>?) ?? {};

    final tier = sub['tier'] as int? ?? 0;
    const tierNames = [
      'Paper (免费)',
      'Tablet (初级)',
      'Scroll (中级)',
      'Opus (大师/无限)'
    ];
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
      taskPriority: priority['taskPriority'] as int? ??
          (perks['startPriority'] as int? ?? 10),
      nextRefillAt: refillTimestamp != null
          ? DateTime.fromMillisecondsSinceEpoch(refillTimestamp * 1000)
          : null,
      unlimitedFree: perks['unlimitedMaxPriority'] as bool? ?? false,
    );
  }
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
