/// NovelAI 图像生成请求参数与官方 payload 构建。
library;

import 'dart:convert';
import 'dart:typed_data';
import 'nai_catalog.dart';
import 'nai_character_prompt.dart';
import 'nai_prompt_presets.dart';

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
  final NaiSeedMode seedMode;
  final NaiSeedTiming seedTiming;
  final int nSamples;
  final bool qualityToggle;
  final String qualityPreset;
  final String ucPresetKey;
  final bool transparentBg;
  final String? prefixPrompt;
  final String? suffixPrompt;
  final bool applyFixedPrompts;

  /// 多角色提示词列表 (仅 V4+ 模型生效，V5 最多 22 个、V4/V4.5 最多 6 个)
  final List<NaiCharacterPrompt> characterPrompts;

  /// 全局角色位置模式：true = AI 自动布局 (官方 AI's Choice，不发送任何位置参数)，
  /// false = 自定义定位 (发送 use_coords=true 与各角色 center)
  final bool characterAiPosition;

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
    this.seedMode = NaiSeedMode.random,
    this.seedTiming = NaiSeedTiming.before,
    this.nSamples = 1,
    this.qualityToggle = true,
    this.qualityPreset = 'Standard',
    this.ucPresetKey = 'Heavy',
    this.transparentBg = false,
    this.prefixPrompt,
    this.suffixPrompt,
    this.applyFixedPrompts = true,
    this.characterPrompts = const [],
    this.characterAiPosition = true,
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

  /// 组合实际发送的正向词：
  /// 1. 质量词后缀 (官网两层追加：prompt-mix 分段 + text: 标记前置)；
  /// 2. V5 系列模型的 Auto Text——把引号包住的文字注入 `teXt:` 渲染段
  ///    (官网在质量词之后追加，因此质量词永远落在 teXt: 之前)。
  String get effectivePrompt {
    final qualityTags = qualityToggle
        ? NovelAiQualityTagsHelper.getQualityTags(model, qualityPreset)
        : '';
    final withQuality = qualityTags.trim().isEmpty
        ? finalPrompt
        : NovelAiPromptText.applySuffix(
            finalPrompt,
            qualityTags,
            isV4OrAbove: model.isV4OrAbove,
            supportsTextRendering: model.supportsTextRendering,
          );

    if (!model.isV5) return withQuality;
    final enabled = enabledCharacterPrompts;
    final characters = <NaiAutoTextCharacter>[
      for (var i = 0; i < enabled.length; i++)
        () {
          final center = enabled[i].resolveCenter(i, enabled.length);
          return (
            prompt: enabled[i].prompt,
            centerX: center.x,
            centerY: center.y,
          );
        }(),
    ];
    return NovelAiAutoText.apply(
      withQuality,
      characters: characters,
      useCoords: useCoords,
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

  /// 参与生成的角色列表 (启用且提示词非空)
  List<NaiCharacterPrompt> get enabledCharacterPrompts => characterPrompts
      .where((c) => c.enabled && c.prompt.trim().isNotEmpty)
      .toList();

  /// 是否下发自定义坐标：关闭全局 AI 自动布局且存在启用角色时才为 true。
  /// 官方 AI's Choice (characterAiPosition=true) 下不发任何位置参数，由模型自行安排。
  bool get useCoords =>
      !characterAiPosition && enabledCharacterPrompts.isNotEmpty;

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
  /// [streaming] 为 true 时附带 stream=msgpack 参数，请求流式中间帧 (仅 V4+ 模型支持)
  Map<String, dynamic> toApiPayload({bool streaming = false}) {
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
      // 流式端点必须显式声明 msgpack 分帧，否则服务端不会输出 intermediate 中间帧
      if (streaming) 'stream': 'msgpack',
      // 官网在负面词为空时改发 uc 空串
      if (apiNegative.isEmpty) 'uc': '' else 'negative_prompt': apiNegative,
      'seed': seed,
      if (usesBrownianEulerAncestral) ...{
        'deliberate_euler_ancestral_bug': false,
        'prefer_brownian': true,
      },
    };

    if (isV4OrAbove) {
      // 多角色隔离: characterPrompts + v4_prompt 的 char_captions (仅启用角色)。
      // 官方 AI's Choice (characterAiPosition=true) 不发送任何位置参数；
      // 自定义定位时发送 use_coords=true 与各角色 center——手动指定过的角色
      // 用其坐标，未指定的按启用顺序自动布局；V4/V4.5 官方限制 5x5 网格，
      // 坐标量化到 1/4 步长，V5 为自由连续小数坐标。
      final parts = _buildCharacterPayloadParts();
      final useCoords = this.useCoords;

      return {
        'input': apiPrompt,
        'model': model.id,
        'action': 'generate',
        'parameters': {
          ...baseParameters,
          'params_version': 4,
          'use_coords': useCoords,
          'legacy_v3_extend': false,
          'legacy_uc': false,
          'characterPrompts': parts.characterPrompts,
          'v4_prompt': {
            'caption': {
              'base_caption': apiPrompt,
              'char_captions': parts.charCaptions,
            },
            'use_coords': useCoords,
            'use_order': true,
          },
          'v4_negative_prompt': {
            'caption': {
              'base_caption': apiNegative,
              'char_captions': parts.negativeCharCaptions,
            },
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

  /// 构建发送给 NovelAI 官方的 Inpainting (局部重绘 / Infill) 请求体
  Map<String, dynamic> toInfillApiPayload({
    required Uint8List sourceBytes,
    required Uint8List maskBytes,
    required int requestWidth,
    required int requestHeight,
    double strength = 0.70,
    double noise = 0.00,
    bool streaming = false,
  }) {
    final apiPrompt = effectivePrompt;
    final apiNegative = effectiveNegativePrompt;
    final inpaintModel = model.inpaintModelId;
    final isV4OrAbove = model.isV4OrAbove;

    final usesBrownianEulerAncestral =
        sampler == NaiSampler.kEulerAncestral &&
        noiseSchedule != NoiseSchedule.native;

    final baseParameters = <String, dynamic>{
      'width': requestWidth,
      'height': requestHeight,
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
      'image': base64Encode(sourceBytes),
      'mask': base64Encode(maskBytes),
      'strength': strength,
      'noise': noise,
      'extra_noise_seed': seed - 1,
      if (streaming) 'stream': 'msgpack',
      if (apiNegative.isEmpty) 'uc': '' else 'negative_prompt': apiNegative,
      'seed': seed,
      if (usesBrownianEulerAncestral) ...{
        'deliberate_euler_ancestral_bug': false,
        'prefer_brownian': true,
      },
    };

    if (isV4OrAbove) {
      final parts = _buildCharacterPayloadParts();
      final useCoords = this.useCoords;

      return {
        'input': apiPrompt,
        'model': inpaintModel,
        'action': 'infill',
        'parameters': {
          ...baseParameters,
          'params_version': 4,
          'use_coords': useCoords,
          'legacy_v3_extend': false,
          'legacy_uc': false,
          'characterPrompts': parts.characterPrompts,
          'v4_prompt': {
            'caption': {
              'base_caption': apiPrompt,
              'char_captions': parts.charCaptions,
            },
            'use_coords': useCoords,
            'use_order': true,
          },
          'v4_negative_prompt': {
            'caption': {
              'base_caption': apiNegative,
              'char_captions': parts.negativeCharCaptions,
            },
            'legacy_uc': false,
          },
        },
      };
    }

    return {
      'input': apiPrompt,
      'model': inpaintModel,
      'action': 'infill',
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
    NaiSeedMode? seedMode,
    NaiSeedTiming? seedTiming,
    int? nSamples,
    bool? qualityToggle,
    String? qualityPreset,
    String? ucPresetKey,
    bool? transparentBg,
    String? prefixPrompt,
    String? suffixPrompt,
    bool? applyFixedPrompts,
    List<NaiCharacterPrompt>? characterPrompts,
    bool? characterAiPosition,
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
      seedMode: seedMode ?? this.seedMode,
      seedTiming: seedTiming ?? this.seedTiming,
      nSamples: nSamples ?? this.nSamples,
      qualityToggle: qualityToggle ?? this.qualityToggle,
      qualityPreset: qualityPreset ?? this.qualityPreset,
      ucPresetKey: ucPresetKey ?? this.ucPresetKey,
      transparentBg: transparentBg ?? this.transparentBg,
      prefixPrompt: prefixPrompt ?? this.prefixPrompt,
      suffixPrompt: suffixPrompt ?? this.suffixPrompt,
      applyFixedPrompts: applyFixedPrompts ?? this.applyFixedPrompts,
      characterPrompts: characterPrompts ?? this.characterPrompts,
      characterAiPosition: characterAiPosition ?? this.characterAiPosition,
    );
  }

  Map<String, dynamic> toJson() => {
    'prompt': prompt,
    'negativePrompt': negativePrompt,
    'model': model.id,
    'width': width,
    'height': height,
    'steps': steps,
    'scale': scale,
    'cfgRescale': cfgRescale,
    'sampler': sampler.id,
    'noiseSchedule': noiseSchedule.id,
    'seed': seed,
    'seedMode': seedMode.id,
    'seedTiming': seedTiming.id,
    'nSamples': nSamples,
    'qualityToggle': qualityToggle,
    'qualityPreset': qualityPreset,
    'ucPresetKey': ucPresetKey,
    'transparentBg': transparentBg,
    'prefixPrompt': prefixPrompt,
    'suffixPrompt': suffixPrompt,
    'applyFixedPrompts': applyFixedPrompts,
    'characterPrompts': characterPrompts.map((c) => c.toJson()).toList(),
    'characterAiPosition': characterAiPosition,
  };

  factory NaiGenerationParams.fromJson(Map<String, dynamic> json) {
    double parseDouble(String key, double fallback) {
      final raw = json[key];
      return raw is num ? raw.toDouble() : fallback;
    }

    int parseInt(String key, int fallback) {
      final raw = json[key];
      return raw is num ? raw.toInt() : fallback;
    }

    List<NaiCharacterPrompt> characters = const [];
    if (json['characterPrompts'] is List) {
      characters = (json['characterPrompts'] as List)
          .whereType<Map<String, dynamic>>()
          .map(NaiCharacterPrompt.fromJson)
          .toList();
    }

    return NaiGenerationParams(
      prompt: json['prompt'] as String? ?? '',
      negativePrompt: json['negativePrompt'] as String? ?? '',
      model: json['model'] is String
          ? NaiModel.fromId(json['model'] as String)
          : NaiModel.v5Full,
      width: parseInt('width', 832),
      height: parseInt('height', 1216),
      steps: parseInt('steps', 28),
      scale: parseDouble('scale', 5.0),
      cfgRescale: parseDouble('cfgRescale', 0.0),
      sampler: json['sampler'] is String
          ? NaiSampler.fromId(json['sampler'] as String)
          : NaiSampler.kEuler,
      noiseSchedule: json['noiseSchedule'] is String
          ? NoiseSchedule.fromId(json['noiseSchedule'] as String)
          : NoiseSchedule.karras,
      seed: parseInt('seed', -1),
      seedMode: NaiSeedMode.fromId(json['seedMode'] as String?),
      seedTiming: NaiSeedTiming.fromId(json['seedTiming'] as String?),
      nSamples: parseInt('nSamples', 1),
      qualityToggle: json['qualityToggle'] as bool? ?? true,
      qualityPreset: json['qualityPreset'] as String? ?? 'Standard',
      ucPresetKey: json['ucPresetKey'] as String? ?? 'Heavy',
      transparentBg: json['transparentBg'] as bool? ?? false,
      prefixPrompt: json['prefixPrompt'] as String?,
      suffixPrompt: json['suffixPrompt'] as String?,
      applyFixedPrompts: json['applyFixedPrompts'] as bool? ?? true,
      characterPrompts: characters,
      characterAiPosition: json['characterAiPosition'] as bool? ?? true,
    );
  }

  /// 构建 V4+ 多角色的三套官方协议结构 (正向/负向 char_captions 与
  /// characterPrompts 条目)，toApiPayload 与 toMetadataComment 共用，
  /// 保证请求与嵌入 PNG 的元数据完全同构。
  _NaiCharacterPayloadParts _buildCharacterPayloadParts() {
    final enabledCharacters = enabledCharacterPrompts;
    final useCoords = this.useCoords;
    final quantize = model.isV5
        ? (double v) => v.clamp(0.0, 1.0)
        : NaiCharacterPositionLayout.gridQuantize;

    final charCaptions = <Map<String, dynamic>>[];
    final negativeCharCaptions = <Map<String, dynamic>>[];
    final characterPromptEntries = <Map<String, dynamic>>[];
    for (var i = 0; i < enabledCharacters.length; i++) {
      final character = enabledCharacters[i];
      if (useCoords) {
        final raw = character.resolveCenter(i, enabledCharacters.length);
        final center = (x: quantize(raw.x), y: quantize(raw.y));
        charCaptions.add({
          'centers': [
            {'x': center.x, 'y': center.y},
          ],
          'char_caption': character.prompt,
        });
        negativeCharCaptions.add({
          'centers': [
            {'x': center.x, 'y': center.y},
          ],
          'char_caption': character.negativePrompt,
        });
        characterPromptEntries.add({
          'center': {'x': center.x, 'y': center.y},
          'prompt': character.prompt,
          'uc': character.negativePrompt,
          'enabled': true,
        });
      } else {
        charCaptions.add({'char_caption': character.prompt});
        negativeCharCaptions.add({'char_caption': character.negativePrompt});
        characterPromptEntries.add({
          'prompt': character.prompt,
          'uc': character.negativePrompt,
          'enabled': true,
        });
      }
    }
    return _NaiCharacterPayloadParts(
      charCaptions: charCaptions,
      negativeCharCaptions: negativeCharCaptions,
      characterPrompts: characterPromptEntries,
    );
  }

  /// 构造嵌入 PNG Comment 文本块的标准 NovelAI 元数据 Map
  /// (2026-12 对齐官网实测格式: prompt/uc 携带完整生效文本)。
  ///
  /// 官网生成的 PNG 在 Comment 中写入的就是拼好质量词 / UC 预设 / nsfw
  /// 互斥与 text: 标记处理的**完整生效提示词**，与实际请求完全一致；本方法
  /// 同样使用 effectivePrompt / effectiveNegativePrompt，第三方工具 (官网、
  /// Aaalice 等) 可直接识别。读回时的反向剥离见 ImageMetadataService。
  Map<String, dynamic> toMetadataComment({required int seed}) {
    final apiPrompt = effectivePrompt;
    final apiNegative = effectiveNegativePrompt;
    final isV4OrAbove = model.isV4OrAbove;
    // 官网对 Euler Ancestral + 非 Native 噪声调度固定开启布朗尼修正，保持一致
    final usesBrownianEulerAncestral =
        sampler == NaiSampler.kEulerAncestral &&
        noiseSchedule != NoiseSchedule.native;

    final comment = <String, dynamic>{
      'prompt': apiPrompt,
      'uc': apiNegative,
      'steps': steps,
      'height': height,
      'width': width,
      'scale': scale,
      'uncond_scale': 0.0,
      'cfg_rescale': cfgRescale,
      'seed': seed,
      'n_samples': nSamples,
      'noise_schedule': noiseSchedule.id,
      'sampler': sampler.id,
      'sm': false,
      'sm_dyn': false,
      'model': model.id,
      'version': isV4OrAbove ? 1 : 'v3',
      'legacy_v3_extend': false,
      'legacy_uc': false,
      // 结构化预设提示：qualityToggle/qualityPreset/ucPreset 供本程序回读还原，
      // tag_hint_* 为官网 V5 起随请求回显的数字提示 (qt: 0/1/3，uc: 0/2/3/4/5)
      'qualityToggle': qualityToggle,
      'qualityPreset': qualityPreset,
      'ucPreset': ucPresetKey,
      'tag_hint_qt': _qualityTagHint,
      'tag_hint_uc_preset': _ucPresetTagHint,
      if (transparentBg) 'tag_hint_transparent_background': true,
      if (usesBrownianEulerAncestral) ...{
        'deliberate_euler_ancestral_bug': false,
        'prefer_brownian': true,
      },
    };

    if (isV4OrAbove) {
      final parts = _buildCharacterPayloadParts();
      comment['v4_prompt'] = {
        'caption': {
          'base_caption': apiPrompt,
          'char_captions': parts.charCaptions,
        },
        'use_coords': useCoords,
        'use_order': true,
        'legacy_uc': false,
      };
      comment['v4_negative_prompt'] = {
        'caption': {
          'base_caption': apiNegative,
          'char_captions': parts.negativeCharCaptions,
        },
        'use_coords': false,
        'use_order': false,
        'legacy_uc': false,
      };
    }
    return comment;
  }
}

/// toMetadataComment 与 toApiPayload 共用的多角色 payload 结构
class _NaiCharacterPayloadParts {
  final List<Map<String, dynamic>> charCaptions;
  final List<Map<String, dynamic>> negativeCharCaptions;
  final List<Map<String, dynamic>> characterPrompts;

  const _NaiCharacterPayloadParts({
    required this.charCaptions,
    required this.negativeCharCaptions,
    required this.characterPrompts,
  });
}
