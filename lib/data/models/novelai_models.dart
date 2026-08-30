import 'dart:typed_data';

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

  bool get isV5 => id.startsWith('nai-diffusion-5');

  /// 模型出厂默认 CFG Scale (官网对齐，切模型时若未手动调整则跟随)
  double get defaultScale => switch (this) {
    NaiModel.v5Full || NaiModel.v5Curated => 7.0,
    NaiModel.v45Full || NaiModel.v45Curated => 5.0,
    NaiModel.v4Full || NaiModel.v4Curated => 5.5,
    NaiModel.v3 => 5.0,
    NaiModel.v3Furry => 6.2,
  };

  /// 模型出厂默认采样步数 (v3 及以上均为 23)
  int get defaultSteps => 23;

  /// 提示词 Token 上限 (V5=qwen3.5 1471/703，V4+=t5 512，V3=clip 225)
  int get tokenLimit => switch (this) {
    NaiModel.v5Full => 1471,
    NaiModel.v5Curated => 703,
    NaiModel.v45Full ||
    NaiModel.v45Curated ||
    NaiModel.v4Full ||
    NaiModel.v4Curated => 512,
    NaiModel.v3 || NaiModel.v3Furry => 225,
  };

  /// Native 噪声调度是否可选 (官网仅在 v3 及更早提供)
  bool get allowsNativeNoiseSchedule => !isV4OrAbove;

  /// 是否支持 `text:` 原生文字渲染段 (官网能力位 `text`，V4 起为 true)。
  /// 质量词等自动追加的内容必须留在 `text:` 之前，否则会被画进图里的文字。
  bool get supportsTextRendering => isV4OrAbove;
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
  final String qualityPreset;
  final int ucPreset;
  final String ucPresetKey;
  final bool transparentBg;
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
    this.qualityPreset = 'Standard',
    this.ucPreset = 0,
    this.ucPresetKey = 'Heavy',
    this.transparentBg = false,
    this.prefixPrompt,
    this.suffixPrompt,
    this.applyFixedPrompts = true,
  });

  /// 组合最终正向词 (词缀 + 核心词 + 透明背景标签)
  String get finalPrompt {
    final parts = <String>[];
    if (applyFixedPrompts &&
        prefixPrompt != null &&
        prefixPrompt!.trim().isNotEmpty) {
      parts.add(prefixPrompt!.trim());
    }
    if (prompt.trim().isNotEmpty) {
      parts.add(prompt.trim());
    }
    if (applyFixedPrompts &&
        suffixPrompt != null &&
        suffixPrompt!.trim().isNotEmpty) {
      parts.add(suffixPrompt!.trim());
    }
    if (transparentBg) {
      parts.add('transparent background');
    }
    return parts.join(', ');
  }

  /// 组合实际发送的正向词 (finalPrompt + 官方质量词后缀)。
  /// NovelAI v4+ 的 API 不再在服务端按 qualityToggle 拼接质量词，需客户端拼好文本。
  String get effectivePrompt {
    final qualityTags = qualityToggle
        ? NovelAiQualityTagsHelper.getQualityTags(model, qualityPreset)
        : '';
    if (qualityTags.trim().isEmpty) return finalPrompt;
    return NovelAiPromptText.appendSuffixWithTextAwareness(
      finalPrompt,
      qualityTags,
      supportsTextRendering: model.supportsTextRendering,
    );
  }

  /// 组合实际发送的负面词 (官方 UC 预设前缀 + 自定义排除词)。
  /// 官网把预设内容拼在用户负面提示词前面，并做 nsfw 双向处理：
  /// 正向词不含 nsfw 时在负面词最开头附加 nsfw 压制；含 nsfw 时反而移除以放开。
  String get effectiveNegativePrompt {
    final ucText = NovelAiUndesiredContentHelper.getUndesiredContent(
      model,
      ucPresetKey,
    );
    var effective = [
      ucText,
      negativePrompt.trim(),
    ].where((s) => s.isNotEmpty).join(', ');

    if (NovelAiPromptText.containsNsfwTag(prompt)) {
      // 正向已有 nsfw：从负面词移除，避免自我冲突
      effective = NovelAiPromptText.removeNsfwTag(effective);
    } else if (ucPresetKey != 'None') {
      // 官方 UC 预设启用时在负面词最开头前置 nsfw 压制；
      // 用户词里已有 nsfw 也照加不误 (官网不去重)，None 时不前置
      effective = 'nsfw, $effective';
    }
    return effective;
  }

  /// 官方质量预设字符串 ID (params_version 4 用字符串而非旧版布尔开关)
  String get _qualityPresetId {
    if (!qualityToggle) return 'none';
    final hasLight = model.isV5;
    return (qualityPreset == 'Light' && hasLight) ? 'light' : 'standard';
  }

  /// 官方 UC 预设字符串 ID
  String get _ucPresetId => switch (ucPresetKey) {
    'Heavy' => 'heavy',
    'Light' => 'light',
    'Human Focus' => 'humanFocus',
    'Furry Focus' => 'furryFocus',
    _ => 'none',
  };

  /// 官网随请求下发的质量预设数字提示 (0=none 1=standard 3=light)
  int get _qualityTagHint {
    if (!qualityToggle) return 0;
    return (qualityPreset == 'Light' && model.isV5) ? 3 : 1;
  }

  /// 官网随请求下发的 UC 预设数字提示 (0=none 2=heavy 3=light 4=humanFocus 5=furryFocus)
  int get _ucPresetTagHint => switch (ucPresetKey) {
    'Heavy' => 2,
    'Light' => 3,
    'Human Focus' => 4,
    'Furry Focus' => 5,
    _ => 0,
  };

  /// 判定是否符合 Opus 免点数条件 (像素数 <= 1048576 且 步数 <= 28 且 样本数 = 1)
  bool get isOpusFree =>
      width * height <= 1048576 && steps <= 28 && nSamples == 1;

  /// 构建发送给 NovelAI 官方的 JSON 请求体
  Map<String, dynamic> toApiPayload() {
    final apiPrompt = effectivePrompt;
    final apiNegative = effectiveNegativePrompt;
    final isV4OrAbove = model.isV4OrAbove;
    // 官网对 Euler Ancestral + 非 Native 噪声调度固定开启布朗尼修正，保持一致
    final usesBrownianEulerAncestral =
        sampler == NaiSampler.kEulerAncestral &&
        noiseSchedule != NoiseSchedule.native;

    final baseParameters = <String, dynamic>{
      'width': width,
      'height': height,
      'scale': scale,
      'cfg_rescale': cfgRescale,
      'sampler': sampler.id,
      'noise_schedule': noiseSchedule.id,
      'steps': steps,
      'n_samples': nSamples,
      'ucPresetId': _ucPresetId,
      'qualityPresetId': _qualityPresetId,
      'tag_hint_uc_preset': _ucPresetTagHint,
      'tag_hint_qt': _qualityTagHint,
      'dynamic_thresholding': false,
      'controlnet_strength': 1,
      'legacy': false,
      'add_original_image': false,
      'image_format': 'png',
      // 官网在负面词为空时改发 uc 空串
      if (apiNegative.isEmpty) 'uc': '' else 'negative_prompt': apiNegative,
      'seed': seed,
      if (usesBrownianEulerAncestral) ...{
        'deliberate_euler_ancestral_bug': false,
        'prefer_brownian': true,
      },
    };

    if (isV4OrAbove) {
      return {
        'input': apiPrompt,
        'model': model.id,
        'action': 'generate',
        'parameters': {
          ...baseParameters,
          'params_version': 4,
          'use_coords': false,
          'legacy_v3_extend': false,
          'legacy_uc': false,
          'characterPrompts': [],
          'v4_prompt': {
            'caption': {'base_caption': apiPrompt, 'char_captions': []},
            'use_coords': false,
            'use_order': true,
          },
          'v4_negative_prompt': {
            'caption': {'base_caption': apiNegative, 'char_captions': []},
            'legacy_uc': false,
          },
        },
      };
    }

    // v3 时代模型才下发 SMEA 开关
    return {
      'input': apiPrompt,
      'model': model.id,
      'action': 'generate',
      'parameters': {...baseParameters, 'sm': false, 'sm_dyn': false},
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
    String? qualityPreset,
    int? ucPreset,
    String? ucPresetKey,
    bool? transparentBg,
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
      qualityPreset: qualityPreset ?? this.qualityPreset,
      ucPreset: ucPreset ?? this.ucPreset,
      ucPresetKey: ucPresetKey ?? this.ucPresetKey,
      transparentBg: transparentBg ?? this.transparentBg,
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

  /// 缓存并获取 Uint8List 引用 (避免每次重绘创建新对象导致图片重复解码闪烁)
  Uint8List get uint8Bytes =>
      bytes is Uint8List ? (bytes as Uint8List) : Uint8List.fromList(bytes);
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

/// NovelAI 官方质量词预设助手 (按模型映射官方最新标准)
class NovelAiQualityTagsHelper {
  static List<String> getAvailablePresets(NaiModel model) {
    // 官方 Light 质量档仅 V5 提供，其余模型仅 Standard
    if (model.isV5) return const ['Standard', 'Light', 'None'];
    return const ['Standard', 'None'];
  }

  static String getQualityTags(NaiModel model, String preset) {
    if (preset == 'None') return '';

    // 官方仅 V5 提供 Light 档，其余模型任何非 None 档均按 Standard 处理
    final isLight = preset == 'Light' && model.isV5;
    return switch (model) {
      NaiModel.v5Full || NaiModel.v5Curated =>
        isLight
            ? 'very aesthetic, amazing quality, no text'
            : 'very aesthetic, masterpiece, no text',
      NaiModel.v45Full => 'location, very aesthetic, masterpiece, no text',
      NaiModel.v45Curated =>
        'location, masterpiece, no text, -0.8::feet::, rating:general',
      NaiModel.v4Full => 'no text, best quality, very aesthetic, absurdres',
      NaiModel.v4Curated =>
        'rating:general, amazing quality, very aesthetic, absurdres',
      NaiModel.v3 => 'best quality, amazing quality, very aesthetic, absurdres',
      NaiModel.v3Furry => '{best quality}, {amazing quality}',
    };
  }
}

/// NovelAI 官方负面排除词 (Undesired Content) 预设助手 (按模型映射官方最新标准)
class NovelAiUndesiredContentHelper {
  static List<String> getAvailablePresets(NaiModel model) {
    // 官方所有模型均提供全部 UC 预设 (含 Furry Focus)
    return const ['Heavy', 'Light', 'Human Focus', 'Furry Focus', 'None'];
  }

  static String getUndesiredContent(NaiModel model, String preset) {
    // 官网 v3 模型选 None 时仍固定追加 lowres
    if (preset == 'None') return model == NaiModel.v3 ? 'lowres' : '';

    return switch (model) {
      NaiModel.v5Full || NaiModel.v5Curated => switch (preset) {
        'Heavy' =>
          'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page',
        'Light' =>
          'lowres, bad hands, bad anatomy, artistic error, sepia, white haze, worst quality, very displeasing, jpeg artifacts, 0::ai-generated::',
        'Human Focus' =>
          'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page, @_@, mismatched pupils, glowing eyes, bad anatomy',
        'Furry Focus' =>
          '{worst quality}, distracting watermark, unfinished, bad quality, {widescreen}, upscale, {sequence}, {{grandfathered content}}, blurred foreground, chromatic aberration, sketch, everyone, [sketch background], simple, [flat colors], ych (character), outline, multiple scenes, [[horror (theme)]], comic',
        _ => '',
      },
      NaiModel.v45Full => switch (preset) {
        'Heavy' =>
          'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page',
        'Light' =>
          'lowres, artistic error, scan artifacts, worst quality, bad quality, jpeg artifacts, multiple views, very displeasing, too many watermarks, negative space, blank page',
        'Human Focus' =>
          'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page, @_@, mismatched pupils, glowing eyes, bad anatomy',
        'Furry Focus' =>
          '{worst quality}, distracting watermark, unfinished, bad quality, {widescreen}, upscale, {sequence}, {{grandfathered content}}, blurred foreground, chromatic aberration, sketch, everyone, [sketch background], simple, [flat colors], ych (character), outline, multiple scenes, [[horror (theme)]], comic',
        _ => '',
      },
      NaiModel.v45Curated => switch (preset) {
        'Heavy' =>
          'blurry, lowres, upscaled, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, halftone, multiple views, logo, too many watermarks, negative space, blank page',
        'Light' =>
          'blurry, lowres, upscaled, artistic error, scan artifacts, jpeg artifacts, logo, too many watermarks, negative space, blank page',
        'Human Focus' =>
          'blurry, lowres, upscaled, artistic error, film grain, scan artifacts, bad anatomy, bad hands, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, halftone, multiple views, logo, too many watermarks, @_@, mismatched pupils, glowing eyes, negative space, blank page',
        _ => '',
      },
      NaiModel.v4Full => switch (preset) {
        'Heavy' =>
          'blurry, lowres, error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, multiple views, logo, too many watermarks',
        'Light' =>
          'blurry, lowres, error, worst quality, bad quality, jpeg artifacts, very displeasing',
        'Human Focus' =>
          'blurry, lowres, error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, multiple views, logo, too many watermarks, bad anatomy, bad hands',
        'Furry Focus' =>
          '{{worst quality}}, [displeasing], {unusual pupils}, guide lines, {{unfinished}}, {bad}, url, artist name, {{tall image}}, mosaic, {sketch page}, comic panel, impact (font), [dated], {logo}, ych, {what}, {where is your god now}, {distorted text}, repeated text, {floating head}, {1994}, {widescreen}, absolutely everyone, sequence, {compression artifacts}, hard translated, {cropped}, {commissioner name}, unknown text, high contrast',
        _ => '',
      },
      NaiModel.v4Curated => switch (preset) {
        'Heavy' =>
          'blurry, lowres, error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, logo, dated, signature, multiple views, gigantic breasts',
        'Light' =>
          'blurry, lowres, error, worst quality, bad quality, jpeg artifacts, very displeasing, logo, dated, signature',
        'Human Focus' =>
          'blurry, lowres, error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, logo, dated, signature, multiple views, gigantic breasts, bad anatomy, bad hands',
        'Furry Focus' =>
          '{{worst quality}}, [displeasing], {unusual pupils}, guide lines, {{unfinished}}, {bad}, url, artist name, {{tall image}}, mosaic, {sketch page}, comic panel, impact (font), [dated], {logo}, ych, {what}, {where is your god now}, {distorted text}, repeated text, {floating head}, {1994}, {widescreen}, absolutely everyone, sequence, {compression artifacts}, hard translated, {cropped}, {commissioner name}, unknown text, high contrast',
        _ => '',
      },
      NaiModel.v3 => switch (preset) {
        'Heavy' =>
          'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg artifacts, bad quality, watermark, unfinished, displeasing, chromatic aberration, signature, extra digits, artistic error, username, scan, [abstract]',
        'Light' =>
          'lowres, jpeg artifacts, worst quality, watermark, blurry, very displeasing',
        'Human Focus' =>
          'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg artifacts, bad quality, watermark, unfinished, displeasing, chromatic aberration, signature, extra digits, artistic error, username, scan, [abstract], bad anatomy, bad hands, @_@, mismatched pupils, heart-shaped pupils, glowing eyes',
        'Furry Focus' =>
          '{{worst quality}}, [displeasing], {unusual pupils}, guide lines, {{unfinished}}, {bad}, url, artist name, {{tall image}}, mosaic, {sketch page}, comic panel, impact (font), [dated], {logo}, ych, {what}, {where is your god now}, {distorted text}, repeated text, {floating head}, {1994}, {widescreen}, absolutely everyone, sequence, {compression artifacts}, hard translated, {cropped}, {commissioner name}, unknown text, high contrast',
        _ => '',
      },
      NaiModel.v3Furry => switch (preset) {
        'Heavy' =>
          '{{worst quality}}, [displeasing], {unusual pupils}, guide lines, {{unfinished}}, {bad}, url, artist name, {{tall image}}, mosaic, {sketch page}, comic panel, impact (font), [dated], {logo}, ych, {what}, {where is your god now}, {distorted text}, repeated text, {floating head}, {1994}, {widescreen}, absolutely everyone, sequence, {compression artifacts}, hard translated, {cropped}, {commissioner name}, unknown text, high contrast',
        'Light' =>
          '{worst quality}, guide lines, unfinished, bad, url, tall image, widescreen, compression artifacts, unknown text',
        'Human Focus' =>
          '{{worst quality}}, [displeasing], {unusual pupils}, guide lines, {{unfinished}}, {bad}, url, artist name, {{tall image}}, mosaic, {sketch page}, comic panel, impact (font), [dated], {logo}, ych, {what}, {where is your god now}, {distorted text}, repeated text, {floating head}, {1994}, {widescreen}, absolutely everyone, sequence, {compression artifacts}, hard translated, {cropped}, {commissioner name}, unknown text, high contrast',
        'Furry Focus' =>
          '{{worst quality}}, [displeasing], {unusual pupils}, guide lines, {{unfinished}}, {bad}, url, artist name, {{tall image}}, mosaic, {sketch page}, comic panel, impact (font), [dated], {logo}, ych, {what}, {where is your god now}, {distorted text}, repeated text, {floating head}, {1994}, {widescreen}, absolutely everyone, sequence, {compression artifacts}, hard translated, {cropped}, {commissioner name}, unknown text, high contrast',
        _ => '',
      },
    };
  }
}

/// 提示词文本后处理工具 (官网行为对齐)。
///
/// - `text:` 文字渲染段感知：V4+ 质量词等自动追加内容必须留在 `text:` 标记
///   之前，否则会被模型当成要画进图里的文字。转义写法 `text::` 不算标记，
///   `||…||` 随机区间内的标记不参与分派。
/// - nsfw 互斥：正向词包含 nsfw 时，官网会自动从负面词中移除 nsfw 及其
///   花括号修饰变体。
class NovelAiPromptText {
  NovelAiPromptText._();

  /// V4 起支持的 `text:` 文字渲染标记。
  ///
  /// 正则与官网一致：标记前的分隔符也算在匹配内，`text::` 是转义写法不算标记。
  static final RegExp _textRenderMarker = RegExp(
    r'(?:^|\s|[,.:\[\]{}、。])text:(?!:)',
    caseSensitive: false,
  );

  /// 提示词混合（prompt mix）的分隔符：`|` 为分段，`||…||` 为随机区间。
  static const String _promptMixSeparator = '|';

  /// nsfw 标签 (支持 `{nsfw}`/`{{nsfw}}`/`[nsfw]` 等修饰变体)
  static final RegExp _nsfwPattern = RegExp(
    r'[\{\[]*nsfw[\}\]]*',
    caseSensitive: false,
  );

  /// nsfw 标签及后续分隔符 (用于移除)
  static final RegExp _nsfwPatternWithSeparator = RegExp(
    r'[\{\[]*nsfw[\}\]]*\s*,?\s*',
    caseSensitive: false,
  );

  /// 找到第一个不在 `||…||` 随机区间内的 `text:` 标记。
  static RegExpMatch? _firstTextMarkerOutsideRandomizer(String prompt) {
    var randomizerOpen = false;
    var cursor = 0;

    for (final match in _textRenderMarker.allMatches(prompt)) {
      while (cursor < match.start) {
        if (prompt[cursor] == _promptMixSeparator &&
            cursor + 1 < prompt.length &&
            prompt[cursor + 1] == _promptMixSeparator) {
          randomizerOpen = !randomizerOpen;
          cursor += 2;
          continue;
        }
        cursor++;
      }
      if (!randomizerOpen) return match;
    }
    return null;
  }

  /// 把 suffix 追加到提示词末尾；模型支持文字渲染且存在 `text:` 标记时，
  /// 改为插到第一个标记之前 (官网行为：质量词落进渲染段会被画成文字)。
  static String appendSuffixWithTextAwareness(
    String prompt,
    String suffix, {
    required bool supportsTextRendering,
  }) {
    final trimmedPrompt = prompt.trim();
    if (suffix.trim().isEmpty) return trimmedPrompt;
    if (trimmedPrompt.isEmpty) return suffix.trim();

    final match = supportsTextRendering
        ? _firstTextMarkerOutsideRandomizer(trimmedPrompt)
        : null;
    if (match == null) {
      // 常规追加：保留既有尾逗号，否则以 ", " 连接
      if (trimmedPrompt.endsWith(',')) return '$trimmedPrompt ${suffix.trim()}';
      return '$trimmedPrompt, ${suffix.trim()}';
    }

    // 标记前的分隔符包含在匹配内；标记裸露在段首时补一个空格
    final markerAndText = trimmedPrompt.substring(match.start);
    final needsSeparator = match.group(0)!.toLowerCase() == 'text:';
    return '${appendSuffixWithTextAwareness(trimmedPrompt.substring(0, match.start), suffix, supportsTextRendering: false)}${needsSeparator ? ' ' : ''}$markerAndText';
  }

  /// 检查提示词是否包含 nsfw 标签 (含花括号/方括号修饰变体，大小写不敏感)
  static bool containsNsfwTag(String prompt) => _nsfwPattern.hasMatch(prompt);

  /// 从提示词中移除 nsfw 标签及其变体，并清理残留的多余逗号与空格
  static String removeNsfwTag(String prompt) {
    if (prompt.isEmpty) return prompt;

    var result = prompt.replaceAll(_nsfwPatternWithSeparator, '');
    result = result.replaceAll(RegExp(r',\s*,'), ',');
    result = result.replaceAll(RegExp(r'^\s*,\s*'), '');
    result = result.replaceAll(RegExp(r'\s*,\s*$'), '');
    return result.trim();
  }
}

/// LLM 接口协议类型
enum LlmProtocol {
  openAiChat('openai', 'OpenAI 兼容 (/chat/completions)', '/chat/completions'),
  openAiResponses('responses', 'Response (/responses)', '/responses'),
  anthropicMessages('messages', 'Message (/messages)', '/messages');

  final String id;
  final String label;
  final String defaultPath;
  const LlmProtocol(this.id, this.label, this.defaultPath);

  static LlmProtocol fromId(String id) {
    return LlmProtocol.values.firstWhere(
      (p) => p.id == id,
      orElse: () => LlmProtocol.openAiChat,
    );
  }
}

/// LLM 思考强度等级 (Reasoning / Thinking Effort)
enum ThinkingEffort {
  off('off', '关闭'),
  low('low', '低 (Low)'),
  medium('medium', '中 (Medium)'),
  high('high', '高 (High)');

  final String id;
  final String label;
  const ThinkingEffort(this.id, this.label);

  static ThinkingEffort fromId(String? id) {
    return ThinkingEffort.values.firstWhere(
      (e) => e.id == id,
      orElse: () => ThinkingEffort.medium,
    );
  }
}

/// 单个 LLM 模型元数据与配置项 (对标 pi-ai ModelCatalog 规范)
class LlmModelConfig {
  final String id;
  final String name;
  final bool reasoning;
  final List<String> input; // ['text'] 或 ['text', 'image'] (多模态视觉)
  final List<ThinkingEffort> supportedThinkingLevels; // 支持的思考等级梯度
  final int contextWindow; // 上下文窗口大小 (tokens)
  final int maxTokens; // 最大输出 tokens
  final double temperature;

  const LlmModelConfig({
    required this.id,
    required this.name,
    this.reasoning = false,
    this.input = const ['text'],
    this.supportedThinkingLevels = const [],
    this.contextWindow = 128000,
    this.maxTokens = 8192,
    this.temperature = 0.7,
  });

  /// 是否具备多模态 / 图像视觉理解能力
  bool get isMultimodal => input.contains('image');

  /// 是否支持深度思考 / 推理扩展
  bool get supportsThinking => reasoning || supportedThinkingLevels.isNotEmpty;

  /// 快捷思考梯度 (若支持思考且无细分梯度，默认返回 high)
  ThinkingEffort get defaultThinkingEffort {
    if (supportedThinkingLevels.isNotEmpty) {
      return supportedThinkingLevels.contains(ThinkingEffort.medium)
          ? ThinkingEffort.medium
          : supportedThinkingLevels.last;
    }
    return reasoning ? ThinkingEffort.high : ThinkingEffort.off;
  }

  // 向后兼容
  ThinkingEffort get thinkingEffort => defaultThinkingEffort;

  LlmModelConfig copyWith({
    String? id,
    String? name,
    bool? reasoning,
    List<String>? input,
    List<ThinkingEffort>? supportedThinkingLevels,
    int? contextWindow,
    int? maxTokens,
    double? temperature,
    ThinkingEffort? thinkingEffort,
  }) {
    return LlmModelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      reasoning: reasoning ?? this.reasoning,
      input: input ?? this.input,
      supportedThinkingLevels: supportedThinkingLevels ??
          (thinkingEffort != null && thinkingEffort != ThinkingEffort.off
              ? [thinkingEffort]
              : this.supportedThinkingLevels),
      contextWindow: contextWindow ?? this.contextWindow,
      maxTokens: maxTokens ?? this.maxTokens,
      temperature: temperature ?? this.temperature,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'reasoning': reasoning,
    'input': input,
    'supportedThinkingLevels':
        supportedThinkingLevels.map((e) => e.id).toList(),
    'contextWindow': contextWindow,
    'maxTokens': maxTokens,
    'temperature': temperature,
  };

  factory LlmModelConfig.fromJson(Map<String, dynamic> json) {
    List<ThinkingEffort> levels = [];
    if (json['supportedThinkingLevels'] is List) {
      levels = (json['supportedThinkingLevels'] as List<dynamic>)
          .map((e) => ThinkingEffort.fromId(e as String?))
          .toList();
    } else if (json['thinkingEffort'] != null) {
      levels = [ThinkingEffort.fromId(json['thinkingEffort'] as String?)];
    }

    List<String> inputs = const ['text'];
    if (json['input'] is List) {
      inputs = (json['input'] as List<dynamic>).map((e) => e.toString()).toList();
    }

    final isReasoning = json['reasoning'] as bool? ?? levels.isNotEmpty;

    return LlmModelConfig(
      id: json['id'] as String? ?? 'deepseek-chat',
      name: json['name'] as String? ?? (json['id'] as String? ?? 'Custom Model'),
      reasoning: isReasoning,
      input: inputs,
      supportedThinkingLevels: levels,
      contextWindow: (json['contextWindow'] as num?)?.toInt() ?? 128000,
      maxTokens: (json['maxTokens'] as num?)?.toInt() ?? 8192,
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0.7,
    );
  }
}

/// LLM 供应商配置模型
class LlmProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  final LlmProtocol protocol;
  final String apiKey;
  final List<LlmModelConfig> models;
  final String activeModelId;

  const LlmProviderConfig({
    required this.id,
    required this.name,
    this.baseUrl = 'https://api.deepseek.com/v1',
    this.protocol = LlmProtocol.openAiChat,
    this.apiKey = '',
    this.models = const [],
    this.activeModelId = '',
  });

  /// 获取当前激活的模型配置
  LlmModelConfig get activeModel {
    if (models.isEmpty) {
      return const LlmModelConfig(id: 'default', name: '默认模型');
    }
    return models.firstWhere(
      (m) => m.id == activeModelId,
      orElse: () => models.first,
    );
  }

  // 向后兼容快捷属性
  String get model => activeModel.id;
  double get temperature => activeModel.temperature;
  bool get reasoning => activeModel.reasoning;
  ThinkingEffort get thinkingEffort => activeModel.thinkingEffort;

  /// 动态计算最终完整的请求 API URL
  String get fullEndpointUrl {
    var base = baseUrl.trim();
    if (base.isEmpty) return '';
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final path = protocol.defaultPath;
    if (base.endsWith(path)) return base;
    return '$base$path';
  }

  LlmProviderConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    LlmProtocol? protocol,
    String? apiKey,
    List<LlmModelConfig>? models,
    String? activeModelId,
    String? model,
    double? temperature,
  }) {
    var updatedModels = models ?? this.models;
    var targetActiveModelId = activeModelId ?? this.activeModelId;

    if (model != null || temperature != null) {
      final list = (updatedModels.isNotEmpty ? updatedModels : [activeModel]).toList();
      final idx = list.indexWhere((m) => m.id == targetActiveModelId);
      if (idx >= 0) {
        list[idx] = list[idx].copyWith(
          id: model,
          temperature: temperature,
        );
      }
      updatedModels = list;
    }

    return LlmProviderConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      protocol: protocol ?? this.protocol,
      apiKey: apiKey ?? this.apiKey,
      models: updatedModels,
      activeModelId: targetActiveModelId,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'baseUrl': baseUrl,
    'protocol': protocol.id,
    'apiKey': apiKey,
    'models': models.map((m) => m.toJson()).toList(),
    'activeModelId': activeModelId.isNotEmpty
        ? activeModelId
        : (models.isNotEmpty ? models.first.id : ''),
  };

  factory LlmProviderConfig.fromJson(Map<String, dynamic> json) {
    List<LlmModelConfig> parsedModels = [];
    if (json['models'] is List) {
      parsedModels = (json['models'] as List<dynamic>)
          .map((e) => LlmModelConfig.fromJson(e as Map<String, dynamic>))
          .toList();
    }

    // 兼容旧配置无 models 的情况
    if (parsedModels.isEmpty) {
      final oldModel = json['model'] as String? ?? 'deepseek-chat';
      final oldTemp = (json['temperature'] as num?)?.toDouble() ?? 0.7;
      parsedModels = [
        LlmModelConfig(
          id: oldModel,
          name: oldModel,
          temperature: oldTemp,
        ),
      ];
    }

    final activeId = json['activeModelId'] as String? ??
        (json['model'] as String? ?? parsedModels.first.id);

    return LlmProviderConfig(
      id: json['id'] as String? ??
          'provider_${DateTime.now().millisecondsSinceEpoch}',
      name: json['name'] as String? ?? 'Custom Provider',
      baseUrl: json['baseUrl'] as String? ?? 'https://api.deepseek.com/v1',
      protocol: LlmProtocol.fromId(json['protocol'] as String? ?? 'openai'),
      apiKey: json['apiKey'] as String? ?? '',
      models: parsedModels,
      activeModelId: activeId,
    );
  }

  /// 对标 pi-ai 的权威内置出厂预设供应商与模型目录
  static List<LlmProviderConfig> get defaultProviders => [
    // 1. DeepSeek 官方
    const LlmProviderConfig(
      id: 'deepseek',
      name: 'DeepSeek',
      baseUrl: 'https://api.deepseek.com/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'deepseek-chat',
      models: [
        LlmModelConfig(
          id: 'deepseek-chat',
          name: 'DeepSeek V3',
          reasoning: false,
          input: ['text'],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'deepseek-reasoner',
          name: 'DeepSeek R1',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [ThinkingEffort.high],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.6,
        ),
      ],
    ),

    // 2. OpenAI 官方
    const LlmProviderConfig(
      id: 'openai',
      name: 'OpenAI',
      baseUrl: 'https://api.openai.com/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'gpt-4o',
      models: [
        LlmModelConfig(
          id: 'gpt-4o',
          name: 'GPT-4o',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 128000,
          maxTokens: 16384,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'gpt-4o-mini',
          name: 'GPT-4o Mini',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 128000,
          maxTokens: 16384,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'o3-mini',
          name: 'o3-mini',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 200000,
          maxTokens: 100000,
          temperature: 1.0,
        ),
        LlmModelConfig(
          id: 'o1',
          name: 'o1',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 200000,
          maxTokens: 100000,
          temperature: 1.0,
        ),
      ],
    ),

    // 3. Anthropic 官方
    const LlmProviderConfig(
      id: 'anthropic',
      name: 'Anthropic',
      baseUrl: 'https://api.anthropic.com/v1',
      protocol: LlmProtocol.anthropicMessages,
      apiKey: '',
      activeModelId: 'claude-3-7-sonnet-20250219',
      models: [
        LlmModelConfig(
          id: 'claude-3-7-sonnet-20250219',
          name: 'Claude 3.7 Sonnet',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 200000,
          maxTokens: 64000,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'claude-3-5-sonnet-20241022',
          name: 'Claude 3.5 Sonnet',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 200000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'claude-3-5-haiku-20241022',
          name: 'Claude 3.5 Haiku',
          reasoning: false,
          input: ['text', 'image'],
          contextWindow: 200000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
      ],
    ),

    // 4. Google (Gemini)
    const LlmProviderConfig(
      id: 'google',
      name: 'Google Gemini',
      baseUrl: 'https://generativelanguage.googleapis.com/v1beta/openai',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'gemini-2.5-flash',
      models: [
        LlmModelConfig(
          id: 'gemini-2.5-flash',
          name: 'Gemini 2.5 Flash',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 1000000,
          maxTokens: 65536,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'gemini-2.5-pro',
          name: 'Gemini 2.5 Pro',
          reasoning: true,
          input: ['text', 'image'],
          supportedThinkingLevels: [
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ],
          contextWindow: 2000000,
          maxTokens: 65536,
          temperature: 0.7,
        ),
      ],
    ),

    // 5. SiliconFlow (硅基流动)
    const LlmProviderConfig(
      id: 'siliconflow',
      name: 'SiliconFlow',
      baseUrl: 'https://api.siliconflow.cn/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'deepseek-ai/DeepSeek-V3',
      models: [
        LlmModelConfig(
          id: 'deepseek-ai/DeepSeek-V3',
          name: 'DeepSeek V3 (SiliconFlow)',
          reasoning: false,
          input: ['text'],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'deepseek-ai/DeepSeek-R1',
          name: 'DeepSeek R1 (SiliconFlow)',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [ThinkingEffort.high],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.6,
        ),
        LlmModelConfig(
          id: 'Qwen/Qwen2.5-Coder-32B-Instruct',
          name: 'Qwen 2.5 Coder 32B',
          reasoning: false,
          input: ['text'],
          contextWindow: 128000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
      ],
    ),

    // 6. Ollama 本地模型
    const LlmProviderConfig(
      id: 'ollama',
      name: 'Ollama (Local)',
      baseUrl: 'http://localhost:11434/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'llama3.3',
      models: [
        LlmModelConfig(
          id: 'llama3.3',
          name: 'Llama 3.3 70B',
          reasoning: false,
          input: ['text'],
          contextWindow: 128000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
        LlmModelConfig(
          id: 'deepseek-r1:14b',
          name: 'DeepSeek R1 14B',
          reasoning: true,
          input: ['text'],
          supportedThinkingLevels: [ThinkingEffort.high],
          contextWindow: 64000,
          maxTokens: 8192,
          temperature: 0.6,
        ),
        LlmModelConfig(
          id: 'qwen2.5:7b',
          name: 'Qwen 2.5 7B',
          reasoning: false,
          input: ['text'],
          contextWindow: 32000,
          maxTokens: 8192,
          temperature: 0.7,
        ),
      ],
    ),
  ];
}
