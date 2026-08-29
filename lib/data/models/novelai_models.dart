
/// NovelAI 官方支持的模型列表
enum NaiModel {
  v5Full('nai-diffusion-5-full', 'NAI-Diffusion-v5-Full'),
  v5Curated('nai-diffusion-5-curated', 'NAI-Diffusion-v5-Curated'),
  v45Full('nai-diffusion-4-5-full', 'NAI-Diffusion-v4.5-Full'),
  v45Curated('nai-diffusion-4-5-curated', 'NAI-Diffusion-v4.5-Curated'),
  v4Full('nai-diffusion-4-full', 'NAI-Diffusion-v4-Full'),
  v4Curated('nai-diffusion-4-curated', 'NAI-Diffusion-v4-Curated'),
  v3('nai-diffusion-3', 'NAI-Diffusion-v3'),
  v3Furry('nai-diffusion-furry-3', 'NAI-Diffusion-Furry-v3');

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
  kEuler('k_euler', 'Euler'),
  kEulerAncestral('k_euler_ancestral', 'Euler Ancestral'),
  kDpmpp2m('k_dpmpp_2m', 'DPM++ 2M'),
  kDpmpp2sAncestral('k_dpmpp_2s_ancestral', 'DPM++ 2S Ancestral'),
  kDpmppSde('k_dpmpp_sde', 'DPM++ SDE'),
  ddim('ddim', 'DDIM'),
  kDpm2('k_dpm_2', 'DPM2'),
  kDpm2Ancestral('k_dpm_2_ancestral', 'DPM2 Ancestral'),
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
  karras('karras', 'Karras'),
  exponential('exponential', 'Exponential'),
  polyexponential('polyexponential', 'Polyexponential'),
  native('native', 'Native'),
  linear('linear', 'Linear');

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

/// 分辨率预设分类 (匹配 NovelAI 官方标准: Normal, Large, Wallpaper, Small, Custom)
enum ResolutionCategory {
  normal('normal', 'Normal'),
  large('large', 'Large'),
  wallpaper('wallpaper', 'Wallpaper'),
  small('small', 'Small'),
  custom('custom', 'Custom');

  final String key;
  final String label;
  const ResolutionCategory(this.key, this.label);

  static ResolutionCategory fromDimensions(int width, int height) {
    if ((width == 832 && height == 1216) ||
        (width == 1216 && height == 832) ||
        (width == 1024 && height == 1024)) {
      return ResolutionCategory.normal;
    }
    if ((width == 1024 && height == 1536) ||
        (width == 1536 && height == 1024) ||
        (width == 1472 && height == 1472)) {
      return ResolutionCategory.large;
    }
    if ((width == 1088 && height == 1920) ||
        (width == 1920 && height == 1088)) {
      return ResolutionCategory.wallpaper;
    }
    if ((width == 512 && height == 768) ||
        (width == 768 && height == 512) ||
        (width == 640 && height == 640)) {
      return ResolutionCategory.small;
    }
    return ResolutionCategory.custom;
  }
}

/// 分辨率方向 (横屏、竖屏、正方形)
enum ResolutionOrientation {
  landscape('landscape', '横屏'),
  portrait('portrait', '竖屏'),
  square('square', '正方形');

  final String key;
  final String label;
  const ResolutionOrientation(this.key, this.label);

  static ResolutionOrientation fromDimensions(int width, int height) {
    if (width > height) return ResolutionOrientation.landscape;
    if (width < height) return ResolutionOrientation.portrait;
    return ResolutionOrientation.square;
  }
}

/// 分辨率计算辅助工具
class ResolutionPresetHelper {
  /// 判断该分类是否支持 1:1 正方形比例 (Wallpaper 壁纸分类官方无 1:1)
  static bool supportsSquare(ResolutionCategory category) {
    return category != ResolutionCategory.wallpaper;
  }

  static (int width, int height) getDimensions(
    ResolutionCategory category,
    ResolutionOrientation orientation,
  ) {
    switch (category) {
      case ResolutionCategory.normal:
        switch (orientation) {
          case ResolutionOrientation.landscape:
            return (1216, 832);
          case ResolutionOrientation.portrait:
            return (832, 1216);
          case ResolutionOrientation.square:
            return (1024, 1024);
        }
      case ResolutionCategory.large:
        switch (orientation) {
          case ResolutionOrientation.landscape:
            return (1536, 1024);
          case ResolutionOrientation.portrait:
            return (1024, 1536);
          case ResolutionOrientation.square:
            return (1472, 1472);
        }
      case ResolutionCategory.wallpaper:
        switch (orientation) {
          case ResolutionOrientation.landscape:
            return (1920, 1088);
          case ResolutionOrientation.portrait:
            return (1088, 1920);
          case ResolutionOrientation.square:
            return (1920, 1088); // 壁纸无 1:1，回退为横屏
        }
      case ResolutionCategory.small:
        switch (orientation) {
          case ResolutionOrientation.landscape:
            return (768, 512);
          case ResolutionOrientation.portrait:
            return (512, 768);
          case ResolutionOrientation.square:
            return (640, 640);
        }
      case ResolutionCategory.custom:
        return (832, 1216);
    }
  }
}

/// 兼容老预设定义
enum ResolutionPreset {
  portrait('portrait', '竖屏 (832x1216)', 832, 1216, true),
  landscape('landscape', '横屏 (1216x832)', 1216, 832, true),
  square('square', '正方形 (1024x1024)', 1024, 1024, true),
  wallpaper('wallpaper', '壁纸 (1920x1088)', 1920, 1088, false),
  portraitLarge('portrait_large', '大竖屏 (1024x1536)', 1024, 1536, false),
  landscapeLarge('landscape_large', '大横屏 (1536x1024)', 1536, 1024, false);

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
      'Paper',
      'Tablet',
      'Scroll',
      'Opus',
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
