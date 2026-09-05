/// NovelAI 官方模型、采样器、噪声调度与分辨率预设目录。
library;

import 'dart:math';
import 'nai_character_prompt.dart';

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
    final normalized = id
        .toLowerCase()
        .replaceAll('.', '-')
        .replaceAll('_', '-');
    for (final m in NaiModel.values) {
      if (m.id == id ||
          m.id == normalized ||
          m.label.toLowerCase() == normalized) {
        return m;
      }
    }
    if (normalized.contains('5')) return NaiModel.v5Full;
    if (normalized.contains('4-5') || normalized.contains('4.5')) {
      return NaiModel.v45Full;
    }
    if (normalized.contains('4')) return NaiModel.v4Full;
    if (normalized.contains('furry')) return NaiModel.v3Furry;
    if (normalized.contains('3')) return NaiModel.v3;
    return NaiModel.v5Full;
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

  /// 多角色提示词数量上限 (官方文档: V5 为 22、V4/V4.5 为 6，v3 不支持)
  int get maxCharacterPrompts => isV5 ? 22 : (isV4OrAbove ? 6 : 0);

  /// 自定义角色定位是否为自由连续坐标 (V5 画布自由拖动，V4/V4.5 限制 5x5 网格)
  bool get supportsFreeCharacterPositioning => isV5;

  /// 官方三预设 (女/男/其他) 添加角色时的初始正向提示词：
  /// 统一为 Danbooru 标签开头 (不带数字的人数标签写在角色提示词，
  /// 总人数如 2girls 写在主提示词)，v3 不支持角色提示词，返回空串。
  String initialCharacterPrompt(NaiCharacterGender gender) {
    if (!isV4OrAbove) return '';
    return switch (gender) {
      NaiCharacterGender.female => 'girl, ',
      NaiCharacterGender.male => 'boy, ',
      NaiCharacterGender.other => '',
    };
  }

  /// 是否支持 `text:` 原生文字渲染段 (官网能力位 `text`，V4 起为 true)。
  /// 质量词等自动追加的内容必须留在 `text:` 之前，否则会被画进图里的文字。
  bool get supportsTextRendering => isV4OrAbove;

  /// Anlas 基础价倍率 (V5 正式版在现代公式之上乘 1.5，其余模型为 1.0)
  double get anlasMultiplier => isV5 ? 1.5 : 1.0;

  /// Opus 免费生成是否受 V5 体力配额池限制 (透支后不再抵扣，按正常价扣点)
  bool get hasOpusUsageLimit => isV5;

  /// 对应的 NovelAI 官方 Inpainting 重绘模型 ID
  String get inpaintModelId => switch (this) {
    NaiModel.v5Full => 'nai-diffusion-5-full-inpainting',
    NaiModel.v5Curated => 'nai-diffusion-4-5-curated-inpainting',
    NaiModel.v45Full => 'nai-diffusion-4-5-full-inpainting',
    NaiModel.v45Curated => 'nai-diffusion-4-5-curated-inpainting',
    NaiModel.v4Full => 'nai-diffusion-4-full-inpainting',
    NaiModel.v4Curated => 'nai-diffusion-4-curated-inpainting',
    NaiModel.v3 => 'nai-diffusion-3-inpainting',
    NaiModel.v3Furry => 'nai-diffusion-furry-3-inpainting',
  };
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

/// 分辨率方向 (横屏、竖屏、正方形)。纯结构化枚举，UI 文案由 l10n 接管。
enum ResolutionOrientation {
  landscape('landscape'),
  portrait('portrait'),
  square('square');

  final String key;
  const ResolutionOrientation(this.key);

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

/// 种子模式 (Seed Mode)。UI 文案由 l10n 接管，label 仅为英文术语标识。
enum NaiSeedMode {
  random('random', 'Random'),
  increase('increase', 'Increase'),
  fixed('fixed', 'Fixed');

  final String id;
  final String label;

  const NaiSeedMode(this.id, this.label);

  static NaiSeedMode fromId(String? id) {
    if (id == null) return NaiSeedMode.random;
    for (final mode in NaiSeedMode.values) {
      if (mode.id == id || mode.name == id) return mode;
    }
    return NaiSeedMode.random;
  }
}

/// 种子生成控制 / 变更时机 (Generation Timing)。UI 文案由 l10n 接管。
enum NaiSeedTiming {
  before('before'),
  after('after');

  final String id;

  const NaiSeedTiming(this.id);

  static NaiSeedTiming fromId(String? id) {
    if (id == null) return NaiSeedTiming.before;
    for (final t in NaiSeedTiming.values) {
      if (t.id == id || t.name == id) return t;
    }
    return NaiSeedTiming.before;
  }
}

/// 生成均匀真随机 32 位无符号整数种子 (0 ~ 4294967295)
int generateRandomSeed() {
  try {
    return Random.secure().nextInt(1 << 32);
  } catch (_) {
    return Random().nextInt(4294967295);
  }
}
