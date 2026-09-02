import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:pasteboard/pasteboard.dart';
import '../models/novelai_models.dart';

/// 图像元数据提取、剔除与水印合成服务
class ImageMetadataService {
  static const String _magicStealth = 'stealth_pngcomp';
  static const int _maxStealthDecodePixels = 0x1000000;
  static const List<int> _pngSignature = [
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ];

  /// 从系统剪贴板读取图片字节 (优先读取文件路径以保留完整 PNG Chunks 与隐写元数据，其次读取纯位图)
  static Future<(Uint8List?, String?)> readClipboardImageAsync() async {
    try {
      // 1. 优先检查文件路径 (保留 100% 原始 PNG 文本块与 Alpha LSB 元数据)
      final files = await Pasteboard.files();
      if (files.isNotEmpty) {
        final filePath = files.first;
        final file = File(filePath);
        if (await file.exists()) {
          final ext = filePath.toLowerCase();
          if (ext.endsWith('.png') ||
              ext.endsWith('.jpg') ||
              ext.endsWith('.jpeg') ||
              ext.endsWith('.webp')) {
            final bytes = await file.readAsBytes();
            if (bytes.isNotEmpty) {
              final fileName = filePath.split(Platform.pathSeparator).last;
              return (bytes, fileName);
            }
          }
        }
      }

      // 2. 其次读取剪贴板纯位图数据
      final imgBytes = await Pasteboard.image;
      if (imgBytes != null && imgBytes.isNotEmpty) {
        return (imgBytes, '剪贴板图片.png');
      }
    } catch (_) {}
    return (null, null);
  }

  /// 检查是否为有效的 PNG 文件头
  static bool isPngHeader(Uint8List bytes) {
    if (bytes.length < 8) return false;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != _pngSignature[i]) return false;
    }
    return true;
  }

  // ==================== 1. 元数据提取 ====================

  /// 从图像字节中解析元数据 (PNG Chunks + Alpha LSB Stealth)
  static Future<ImageMetadataResult?> parseMetadataAsync(
    Uint8List bytes,
  ) async {
    return compute(parseMetadata, bytes);
  }

  /// 同步从图像字节中解析元数据
  static ImageMetadataResult? parseMetadata(Uint8List bytes) {
    if (!isPngHeader(bytes)) {
      // 尝试使用通用图片解码读取文本标签
      return _tryParseNonPng(bytes);
    }

    final textData = extractPngTextData(bytes);

    // 1. 优先尝试解析 PNG 文本块中的元数据
    final fromText = _decodeFromTextData(textData);
    if (fromText != null && fromText.hasData) {
      return fromText;
    }

    // 2. 尝试从 NovelAI stealth_pngcomp (Alpha 通道 LSB 隐写数据) 中提取
    final stealthText = extractStealthMetadataText(bytes);
    if (stealthText != null && stealthText.isNotEmpty) {
      final fromStealth = _decodeFromSingleJson(stealthText);
      if (fromStealth != null && fromStealth.hasData) {
        return fromStealth;
      }
    }

    return null;
  }

  static ImageMetadataResult? _tryParseNonPng(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded != null && decoded.textData != null) {
        return _decodeFromTextData(decoded.textData!);
      }
    } catch (_) {}
    return null;
  }

  /// 提取 PNG 文本块数据，同时支持 Latin-1 tEXt、UTF-8 iTXt 与 zTXt
  static Map<String, String> extractPngTextData(Uint8List bytes) {
    if (!isPngHeader(bytes)) return const {};
    final chunks = _parsePngChunks(bytes);
    final result = <String, String>{};

    for (final chunk in chunks) {
      final entry = switch (chunk.type) {
        'tEXt' => _decodeTextChunk(chunk.data),
        'iTXt' => _decodeInternationalTextChunk(chunk.data),
        'zTXt' => _decodeCompressedTextChunk(chunk.data),
        _ => null,
      };
      if (entry != null) {
        result[entry.$1] = entry.$2;
      }
    }
    return result;
  }

  /// 从 NovelAI stealth_pngcomp alpha LSB 数据中提取元数据 JSON
  static String? extractStealthMetadataText(Uint8List imageBytes) {
    try {
      final image = img.decodeImage(imageBytes);
      if (image == null ||
          image.width * image.height > _maxStealthDecodePixels) {
        return null;
      }

      final magicBytes = utf8.encode(_magicStealth);
      final headerBytes = _readAlphaLsbBytes(image, magicBytes.length + 4);
      if (headerBytes == null || headerBytes.length < magicBytes.length + 4) {
        return null;
      }

      for (var i = 0; i < magicBytes.length; i++) {
        if (headerBytes[i] != magicBytes[i]) {
          return null;
        }
      }

      final lengthData = ByteData.sublistView(
        Uint8List.fromList(headerBytes.sublist(magicBytes.length)),
      );
      final bitLength = lengthData.getInt32(0);
      if (bitLength <= 0 || bitLength > image.width * image.height) return null;

      final byteLength = (bitLength + 7) ~/ 8;
      final payload = _readAlphaLsbBytes(
        image,
        byteLength,
        bitOffset: (magicBytes.length + 4) * 8,
      );
      if (payload == null) return null;

      final decoded = GZipCodec().decode(payload);
      return utf8.decode(decoded);
    } catch (_) {
      return null;
    }
  }

  static List<int>? _readAlphaLsbBytes(
    img.Image image,
    int byteCount, {
    int bitOffset = 0,
  }) {
    final totalBits = byteCount * 8;
    final capacityBits = image.width * image.height;
    if (bitOffset < 0 || bitOffset + totalBits > capacityBits) {
      return null;
    }

    final output = List<int>.filled(byteCount, 0);
    for (var bitIndex = 0; bitIndex < totalBits; bitIndex++) {
      final absoluteBit = bitOffset + bitIndex;
      final x = absoluteBit ~/ image.height;
      final y = absoluteBit % image.height;
      if (x >= image.width) return null;

      final bit = image.getPixel(x, y).a.toInt() & 1;
      output[bitIndex ~/ 8] |= bit << (7 - (bitIndex % 8));
    }
    return output;
  }

  // ==================== 2. 元数据格式解码器 ====================

  static ImageMetadataResult? _decodeFromTextData(
    Map<String, String> textData,
  ) {
    // 1. NovelAI parser
    final naiResult = _parseNovelAi(textData);
    if (naiResult != null) return naiResult;

    // 2. WebUI / A1111 parser
    final webUiResult = _parseWebUi(textData);
    if (webUiResult != null) return webUiResult;

    // 3. ComfyUI parser
    final comfyResult = _parseComfyUi(textData);
    if (comfyResult != null) return comfyResult;

    // 4. InvokeAI parser
    final invokeResult = _parseInvokeAi(textData);
    if (invokeResult != null) return invokeResult;

    // 5. Generic JSON
    for (final entry in textData.entries) {
      if (entry.value.trim().startsWith('{')) {
        final parsed = _decodeFromSingleJson(entry.value);
        if (parsed != null) return parsed;
      }
    }

    return null;
  }

  static ImageMetadataResult? _parseNovelAi(Map<String, String> textData) {
    final fieldsToTry = [
      'Comment',
      'parameters',
      'nai',
      'novelai',
      'Description',
    ];
    for (final field in fieldsToTry) {
      final text = textData[field];
      if (text == null || text.isEmpty) continue;
      final parsed = _decodeFromSingleJson(
        text,
        softwareFallback: textData['Software'] ?? 'NovelAI',
        sourceFallback: textData['Source'],
      );
      if (parsed != null && parsed.hasData) return parsed;
    }

    // 处理纯文本 Description / prompt 场景 (非 JSON 格式的导出)
    if (textData.containsKey('Software') ||
        textData.containsKey('Source') ||
        textData.containsKey('Title') ||
        textData.containsKey('Description')) {
      final prompt = textData['Description'] ?? textData['prompt'] ?? '';
      if (prompt.isNotEmpty) {
        return ImageMetadataResult(
          prompt: prompt,
          software: textData['Software'] ?? 'NovelAI',
          source: textData['Source'],
          model: textData['Source'],
          rawJson: jsonEncode(textData),
        );
      }
    }

    return null;
  }

  static ImageMetadataResult? _decodeFromSingleJson(
    String text, {
    String softwareFallback = 'NovelAI',
    String? sourceFallback,
  }) {
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);

      // 处理嵌套 Comment 字段
      if (map.containsKey('Comment') && map['Comment'] is String) {
        final nested = _decodeFromSingleJson(
          map['Comment'] as String,
          softwareFallback: map['Software'] as String? ?? softwareFallback,
          sourceFallback: map['Source'] as String? ?? sourceFallback,
        );
        if (nested != null) return nested;
      }

      var prompt = map['prompt'] as String? ?? '';
      var negativePrompt =
          map['uc'] as String? ?? map['negative_prompt'] as String? ?? '';
      final seed =
          (map['seed'] as num?)?.toInt() ??
          (map['noise_seed'] as num?)?.toInt();
      final sampler = map['sampler'] as String?;
      final steps = (map['steps'] as num?)?.toInt();
      final scale =
          (map['scale'] as num?)?.toDouble() ??
          (map['cfg_scale'] as num?)?.toDouble();
      final cfgRescale = (map['cfg_rescale'] as num?)?.toDouble();
      final width = (map['width'] as num?)?.toInt();
      final height = (map['height'] as num?)?.toInt();
      final noiseSchedule = map['noise_schedule'] as String?;

      // ---- 结构化预设提示解析 (本程序字段 + 官方 V5 数字提示双兼容) ----
      // tag_hint_qt: 0=关 1=Standard 3=Light；tag_hint_uc_preset: 0=None
      // 2=Heavy 3=Light 4=Human Focus 5=Furry Focus (官网新数字提示)
      final tagHintQt = (map['tag_hint_qt'] as num?)?.toInt();
      final tagHintUc = (map['tag_hint_uc_preset'] as num?)?.toInt();
      final qualityToggle =
          (map['qualityToggle'] as bool?) ??
          (map['quality_toggle'] as bool?) ??
          (tagHintQt != null ? tagHintQt != 0 : null);
      final qualityPreset =
          map['qualityPreset'] as String? ??
          switch (tagHintQt) {
            1 => 'Standard',
            3 => 'Light',
            _ => null,
          };
      // 旧版官方 uc_preset 是请求 int 字段 (0=Heavy 1=Light 2=Human Focus
      // 3=None 7=Furry Focus)，与 tag_hint 数字提示是两套编码，优先新提示
      final ucPreset =
          map['ucPreset'] as String? ??
          switch (tagHintUc) {
            0 => 'None',
            2 => 'Heavy',
            3 => 'Light',
            4 => 'Human Focus',
            5 => 'Furry Focus',
            _ => switch ((map['uc_preset'] as num?)?.toInt()) {
              0 => 'Heavy',
              1 => 'Light',
              2 => 'Human Focus',
              3 => 'None',
              7 => 'Furry Focus',
              _ => null,
            },
          };
      final transparentBg =
          map['tag_hint_transparent_background'] as bool? ??
          map['transparent_background'] as bool?;

      // 解析多角色提示词 (本程序 characterPrompts / 官方 v4_prompt 正负向 char_captions)
      final characterPrompts = <String>[];
      final characterNegativePrompts = <String>[];
      if (map['characterPrompts'] is List) {
        for (final item in map['characterPrompts'] as List) {
          if (item is Map) {
            final p = item['prompt'] as String? ?? '';
            final uc = item['uc'] as String? ?? '';
            if (p.isNotEmpty) characterPrompts.add(p);
            if (uc.isNotEmpty) characterNegativePrompts.add(uc);
          }
        }
      } else if (map['v4_prompt'] is Map) {
        final v4 = map['v4_prompt'] as Map;
        final caption = v4['caption'] as Map?;
        if (caption != null && caption['char_captions'] is List) {
          for (final item in caption['char_captions'] as List) {
            if (item is Map) {
              final p = item['char_caption'] as String? ?? '';
              if (p.isNotEmpty) characterPrompts.add(p);
            }
          }
        }
        final v4Neg = map['v4_negative_prompt'] as Map?;
        final negCaption = v4Neg?['caption'] as Map?;
        if (negCaption != null && negCaption['char_captions'] is List) {
          for (final item in negCaption['char_captions'] as List) {
            if (item is Map) {
              final uc = item['char_caption'] as String? ?? '';
              if (uc.isNotEmpty) characterNegativePrompts.add(uc);
            }
          }
        }
      }

      // 模型来源解析
      final source =
          sourceFallback ??
          map['Source'] as String? ??
          map['source'] as String?;
      String? model = map['model'] as String?;
      if (model == null || model.isEmpty) {
        if (source != null && source.isNotEmpty) {
          final sLower = source.toLowerCase();
          if (sLower.contains('v5') || sLower.contains('5')) {
            model = 'nai-diffusion-5-full';
          } else if (sLower.contains('v4.5') ||
              sLower.contains('4.5') ||
              sLower.contains('4-5')) {
            model = 'nai-diffusion-4.5-full';
          } else if (sLower.contains('v4') || sLower.contains('4')) {
            model = 'nai-diffusion-4-full';
          } else if (sLower.contains('furry')) {
            model = 'nai-diffusion-furry-3';
          } else if (sLower.contains('v3') || sLower.contains('3')) {
            model = 'nai-diffusion-3';
          } else {
            model = source;
          }
        }
      }

      // ---- 反向剥离质量词 / UC 预设 / nsfw 前置，还原基础提示词 ----
      // Comment 携带的是完整生效文本 (本程序与官网一致)，一键填入前必须
      // 还原为工作台的基础文本，否则会与质量词开关叠加重复。
      final naiModel = model != null ? NaiModel.fromId(model) : null;
      if (naiModel != null) {
        // 官网 V5 Auto Text：先剥离自动注入的 teXt: 段 (内容与引号提取一致才剥)，
        // 再剥质量词后缀；顺序与官网注入顺序 (质量词 → teXt:) 相反。
        // stripGeneratedBlock 自带 teXt: 标记校验，无标记时原样返回。
        prompt = NovelAiAutoText.stripGeneratedBlock(
          prompt,
          characters: [
            for (final p in characterPrompts)
              (prompt: p, centerX: 0.5, centerY: 0.5),
          ],
        );
        if (qualityToggle == true && qualityPreset != null) {
          final qualityTags = NovelAiQualityTagsHelper.getQualityTags(
            naiModel,
            qualityPreset,
          );
          prompt = NovelAiPromptText.stripTrailingTagSegmentsTextAware(
            prompt,
            qualityTags,
            supportsTextRendering: naiModel.isV4OrAbove,
          );
        }
        if (transparentBg == true) {
          prompt = NovelAiPromptText.stripTrailingTagSegments(
            prompt,
            'transparent background',
          );
        }
        if (ucPreset != null) {
          // 官方 UC 预设启用且正向词无 nsfw 时会前置 'nsfw, '，先剥掉再剥预设文本
          if (ucPreset != 'None' &&
              !NovelAiPromptText.containsNsfwTag(prompt)) {
            negativePrompt = NovelAiPromptText.stripLeadingTagSegments(
              negativePrompt,
              'nsfw',
            );
          }
          final ucText = NovelAiUndesiredContentHelper.getUndesiredContent(
            naiModel,
            ucPreset,
          );
          negativePrompt = NovelAiPromptText.stripLeadingTagSegments(
            negativePrompt,
            ucText,
          );
        }
      }

      return ImageMetadataResult(
        prompt: prompt,
        negativePrompt: negativePrompt,
        seed: seed,
        sampler: sampler,
        steps: steps,
        scale: scale,
        cfgRescale: cfgRescale,
        width: width,
        height: height,
        model: model,
        noiseSchedule: noiseSchedule,
        qualityToggle: qualityToggle,
        qualityPreset: qualityPreset,
        ucPreset: ucPreset,
        transparentBackground: transparentBg,
        software: map['Software'] as String? ?? softwareFallback,
        source: source,
        characterPrompts: characterPrompts,
        characterNegativePrompts: characterNegativePrompts,
        rawJson: text,
      );
    } catch (_) {
      return null;
    }
  }

  static ImageMetadataResult? _parseWebUi(Map<String, String> textData) {
    final fields = [
      'parameters',
      'SD:parameters',
      'Description',
      'description',
    ];
    for (final field in fields) {
      final text = textData[field];
      if (text == null || text.isEmpty) continue;
      if (!text.contains('Steps:') && !text.contains('Sampler:')) continue;

      String? prompt;
      String? negativePrompt;

      final negIndex = text.indexOf('Negative prompt:');
      if (negIndex != -1) {
        prompt = text.substring(0, negIndex).trim();
        final remaining = text.substring(negIndex + 'Negative prompt:'.length);
        final stepsIndex = remaining.indexOf('Steps:');
        if (stepsIndex != -1) {
          negativePrompt = remaining.substring(0, stepsIndex).trim();
        }
      } else {
        final stepsIndex = text.indexOf('Steps:');
        if (stepsIndex != -1) {
          prompt = text.substring(0, stepsIndex).trim();
        }
      }

      final params = _parsePlainTextKeyValues(text);
      return ImageMetadataResult(
        prompt: prompt ?? '',
        negativePrompt: negativePrompt ?? '',
        seed: params['seed'] as int?,
        sampler: params['sampler'] as String?,
        steps: params['steps'] as int?,
        scale: params['cfg_scale'] as double?,
        width: params['width'] as int?,
        height: params['height'] as int?,
        model: params['model'] as String?,
        software: 'Stable Diffusion WebUI',
        rawJson: text,
      );
    }
    return null;
  }

  static ImageMetadataResult? _parseComfyUi(Map<String, String> textData) {
    final promptJson = textData['prompt'];
    if (promptJson == null || promptJson.isEmpty) return null;

    try {
      final decoded = jsonDecode(promptJson);
      if (decoded is! Map) return null;

      String? positive;
      String? negative;
      String? sampler;
      int? steps;
      double? cfg;
      int? seed;

      for (final value in decoded.values) {
        if (value is! Map) continue;
        final classType = value['class_type'] as String?;
        final inputs = value['inputs'] as Map?;

        if (classType?.contains('KSampler') == true && inputs != null) {
          sampler = inputs['sampler_name'] as String?;
          steps = (inputs['steps'] as num?)?.toInt();
          cfg = (inputs['cfg'] as num?)?.toDouble();
          seed =
              (inputs['seed'] as num?)?.toInt() ??
              (inputs['noise_seed'] as num?)?.toInt();
        }

        if (classType?.contains('CLIPTextEncode') == true && inputs != null) {
          final text = inputs['text'] as String?;
          if (text != null && text.isNotEmpty) {
            if (positive == null) {
              positive = text;
            } else {
              negative = text;
            }
          }
        }
      }

      if (positive != null || sampler != null || steps != null) {
        return ImageMetadataResult(
          prompt: positive ?? '',
          negativePrompt: negative ?? '',
          seed: seed,
          sampler: sampler,
          steps: steps,
          scale: cfg,
          software: 'ComfyUI',
          rawJson: promptJson,
        );
      }
    } catch (_) {}
    return null;
  }

  static ImageMetadataResult? _parseInvokeAi(Map<String, String> textData) {
    final sd = textData['sd-metadata'];
    if (sd == null || sd.isEmpty) return null;

    try {
      final decoded = jsonDecode(sd);
      if (decoded is! Map) return null;
      final image = decoded['image'] as Map?;
      if (image == null) return null;

      final promptList = image['prompt'] as List?;
      final pos =
          promptList?.map((p) => p['prompt'] as String?).join(', ') ?? '';
      final neg = image['negative_prompt']?['prompt'] as String? ?? '';

      return ImageMetadataResult(
        prompt: pos,
        negativePrompt: neg,
        seed: image['seed'] as int?,
        sampler: image['sampler'] as String?,
        steps: image['steps'] as int?,
        scale: (image['cfg_scale'] as num?)?.toDouble(),
        width: image['width'] as int?,
        height: image['height'] as int?,
        model: image['model'] as String?,
        software: 'InvokeAI',
        rawJson: sd,
      );
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic> _parsePlainTextKeyValues(String text) {
    final result = <String, dynamic>{};
    final stepsIdx = text.indexOf('Steps:');
    final paramsSection = stepsIdx != -1 ? text.substring(stepsIdx) : text;

    final regex = RegExp(r'(?:^|[,\n])\s*([^:\n]+?)\s*:\s*([^,\n]+)');
    for (final m in regex.allMatches(paramsSection)) {
      final key = m.group(1)?.trim().toLowerCase();
      final val = m.group(2)?.trim();
      if (key == null || val == null) continue;

      if (key == 'steps') result['steps'] = int.tryParse(val);
      if (key == 'sampler') result['sampler'] = val;
      if (key == 'cfg scale' || key == 'cfg') {
        result['cfg_scale'] = double.tryParse(val);
      }
      if (key == 'seed') result['seed'] = int.tryParse(val);
      if (key == 'size') {
        final parts = val.split('x');
        if (parts.length == 2) {
          result['width'] = int.tryParse(parts[0].trim());
          result['height'] = int.tryParse(parts[1].trim());
        }
      }
      if (key == 'model') result['model'] = val;
    }
    return result;
  }

  // ==================== 2.5 嵌入 NovelAI 生成元数据 ====================

  /// 将标准的 NovelAI 元数据文本块 (Title, Software, Source, Description, Comment) 嵌入到 PNG 中
  static Uint8List embedNovelAiMetadata({
    required Uint8List pngBytes,
    required NaiGenerationParams params,
    required int seed,
  }) {
    if (!isPngHeader(pngBytes)) return pngBytes;

    try {
      final commentJson = jsonEncode(params.toMetadataComment(seed: seed));
      final chunks = _parsePngChunks(pngBytes);
      final output = BytesBuilder();
      output.add(pngBytes.sublist(0, 8)); // PNG 签名

      var inserted = false;
      for (final chunk in chunks) {
        // 在 IHDR 之后立即插入元数据块
        if (!inserted && chunk.type != 'IHDR') {
          inserted = true;
          _writeTextChunk(output, 'Title', 'AI generated image');
          _writeTextChunk(output, 'Software', 'NovelAI');
          _writeTextChunk(output, 'Source', params.model.label);
          _writeTextChunk(output, 'Description', params.effectivePrompt);
          _writeTextChunk(output, 'Comment', commentJson);
        }
        // 过滤旧的重名文本块，避免重复
        if (chunk.type == 'tEXt' ||
            chunk.type == 'iTXt' ||
            chunk.type == 'zTXt') {
          final entry =
              _decodeTextChunk(chunk.data) ??
              _decodeInternationalTextChunk(chunk.data) ??
              _decodeCompressedTextChunk(chunk.data);
          if (entry != null &&
              {
                'Title',
                'Software',
                'Source',
                'Description',
                'Comment',
              }.contains(entry.$1)) {
            continue;
          }
        }
        _writeChunk(output, chunk.type, chunk.data);
      }

      if (!inserted) {
        _writeTextChunk(output, 'Title', 'AI generated image');
        _writeTextChunk(output, 'Software', 'NovelAI');
        _writeTextChunk(output, 'Source', params.model.label);
        _writeTextChunk(output, 'Description', params.effectivePrompt);
        _writeTextChunk(output, 'Comment', commentJson);
      }

      return output.toBytes();
    } catch (_) {
      return pngBytes;
    }
  }

  /// 判断文本是否可完整映射到 Latin-1 (PNG tEXt 块规范编码)。
  static bool _isLatin1Text(String text) => text.runes.every((r) => r <= 0xFF);

  /// 写入 PNG 文本块，遵循 PNG 规范保证官方读取器不乱码：
  /// - 文本可映射 Latin-1 时写 tEXt (规范规定 tEXt 为 Latin-1 字节)；
  /// - 含中文等非 Latin-1 字符时改写未压缩 iTXt (规范规定的 UTF-8 国际文本块)。
  /// 修复前直接把 UTF-8 字节塞进 tEXt，官方读取器按 Latin-1 解码出乱码。
  static void _writeTextChunk(
    BytesBuilder builder,
    String keyword,
    String text,
  ) {
    final keywordBytes = latin1.encode(keyword);
    if (_isLatin1Text(text)) {
      final textBytes = latin1.encode(text);
      final data = Uint8List(keywordBytes.length + 1 + textBytes.length);
      data.setAll(0, keywordBytes);
      data[keywordBytes.length] = 0; // null 分隔符
      data.setAll(keywordBytes.length + 1, textBytes);
      _writeChunk(builder, 'tEXt', data);
    } else {
      final textBytes = utf8.encode(text);
      // keyword 终止符 + 压缩标志 0 (未压缩) + 压缩方法 0 + 空语言标签 + 空翻译关键词，共 5 个零字节
      final data = Uint8List(keywordBytes.length + 5 + textBytes.length);
      data.setAll(0, keywordBytes);
      data.setAll(keywordBytes.length + 5, textBytes);
      _writeChunk(builder, 'iTXt', data);
    }
  }

  // ==================== 3. 元数据删除 / 抹除 (Strip Metadata) ====================

  /// 抹除 PNG 图片的所有元数据文本块和 Alpha LSB 隐写数据
  static Future<Uint8List> stripPngMetadataAsync(Uint8List bytes) async {
    return compute(stripPngMetadata, bytes);
  }

  /// 同步抹除 PNG 图片元数据
  static Uint8List stripPngMetadata(Uint8List bytes) {
    if (!isPngHeader(bytes)) {
      // 非 PNG 图片通过解码/重新编码抹除元数据
      try {
        final decoded = img.decodeImage(bytes);
        if (decoded != null) {
          decoded.textData = null;
          decoded.iccProfile = null;
          return Uint8List.fromList(img.encodePng(decoded));
        }
      } catch (_) {}
      return bytes;
    }

    try {
      // 1. 解析并过滤 PNG chunks，剔除 tEXt, iTXt, zTXt, eXIf, dSIG, XML
      final chunks = _parsePngChunks(bytes);
      final metadataChunkTypes = {
        'tEXt',
        'iTXt',
        'zTXt',
        'eXIf',
        'dSIG',
        'prWm',
      };

      final output = BytesBuilder();
      output.add(bytes.sublist(0, 8)); // PNG 签名

      for (final chunk in chunks) {
        if (!metadataChunkTypes.contains(chunk.type)) {
          _writeChunk(output, chunk.type, chunk.data);
        }
      }

      final filteredBytes = output.toBytes();

      // 2. 清除 Alpha 通道 LSB 隐写位 (彻底防止隐写数据残留)
      final decoded = img.decodePng(filteredBytes);
      if (decoded != null && decoded.hasAlpha) {
        for (var x = 0; x < decoded.width; x++) {
          for (var y = 0; y < decoded.height; y++) {
            final p = decoded.getPixel(x, y);
            p.a = p.a.toInt() & 0xFE;
          }
        }
        return Uint8List.fromList(img.encodePng(decoded));
      }

      return filteredBytes;
    } catch (_) {
      return bytes;
    }
  }

  // ==================== 4. 统一导出处理管道 ====================
  // (可见水印合成 / 盲水印 / 元数据抹除统一管道已迁至 WatermarkService.processExportImage)

  // ==================== 私有辅助方法 ====================

  static List<_PngChunk> _parsePngChunks(Uint8List bytes) {
    final chunks = <_PngChunk>[];
    var offset = 8;

    while (offset < bytes.length) {
      if (offset + 12 > bytes.length) break;

      final length = ByteData.sublistView(
        bytes,
        offset,
        offset + 4,
      ).getUint32(0);

      final type = latin1.decode(bytes.sublist(offset + 4, offset + 8));
      if (offset + 12 + length > bytes.length) break;

      final data = bytes.sublist(offset + 8, offset + 8 + length);
      chunks.add(_PngChunk(type, data));
      offset += 12 + length;
    }

    return chunks;
  }

  /// PNG tEXt/zTXt 正文解码：优先按 UTF-8 解码 (官方网页可能把 UTF-8 字节写入
  /// tEXt 块)，字节序列不是合法 UTF-8 时回退 Latin-1 以兼容老图。
  /// 纯 ASCII 内容两种编码结果一致，不受探测影响。
  static String _decodeTextChunkValue(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  static (String, String)? _decodeTextChunk(Uint8List data) {
    final separator = data.indexOf(0);
    if (separator <= 0) return null;
    return (
      latin1.decode(data.sublist(0, separator)),
      _decodeTextChunkValue(data.sublist(separator + 1)),
    );
  }

  static (String, String)? _decodeInternationalTextChunk(Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0 || keywordEnd + 5 > data.length) return null;

    var cursor = keywordEnd + 1;
    final compressionFlag = data[cursor++];
    final compressionMethod = data[cursor++];
    final languageEnd = data.indexOf(0, cursor);
    if (languageEnd < 0) return null;
    cursor = languageEnd + 1;
    final translatedKeywordEnd = data.indexOf(0, cursor);
    if (translatedKeywordEnd < 0) return null;
    cursor = translatedKeywordEnd + 1;

    List<int> textBytes = data.sublist(cursor);
    if (compressionFlag == 1) {
      if (compressionMethod != 0) return null;
      textBytes = ZLibCodec().decode(textBytes);
    } else if (compressionFlag != 0) {
      return null;
    }

    return (latin1.decode(data.sublist(0, keywordEnd)), utf8.decode(textBytes));
  }

  static (String, String)? _decodeCompressedTextChunk(Uint8List data) {
    final keywordEnd = data.indexOf(0);
    if (keywordEnd <= 0 || keywordEnd + 2 > data.length) return null;
    final compressionMethod = data[keywordEnd + 1];
    if (compressionMethod != 0) return null;
    final decoded = ZLibCodec().decode(data.sublist(keywordEnd + 2));
    return (
      latin1.decode(data.sublist(0, keywordEnd)),
      _decodeTextChunkValue(decoded),
    );
  }

  static void _writeChunk(BytesBuilder builder, String type, Uint8List data) {
    final lengthBytes = ByteData(4)..setUint32(0, data.length);
    builder.add(lengthBytes.buffer.asUint8List());

    final typeBytes = latin1.encode(type);
    builder.add(typeBytes);
    builder.add(data);

    final crcInput = Uint8List(typeBytes.length + data.length);
    crcInput.setAll(0, typeBytes);
    crcInput.setAll(typeBytes.length, data);
    final crc = _crc32(crcInput);
    final crcBytes = ByteData(4)..setUint32(0, crc);
    builder.add(crcBytes.buffer.asUint8List());
  }

  static int _crc32(Uint8List data) {
    const table = [
      0x00000000,
      0x77073096,
      0xee0e612c,
      0x990951ba,
      0x076dc419,
      0x706af48f,
      0xe963a535,
      0x9e6495a3,
      0x0edb8832,
      0x79dcb8a4,
      0xe0d5e91e,
      0x97d2d988,
      0x09b64c2b,
      0x7eb17cbd,
      0xe7b82d07,
      0x90bf1d91,
      0x1db71064,
      0x6ab020f2,
      0xf3b97148,
      0x84be41de,
      0x1adad47d,
      0x6ddde4eb,
      0xf4d4b551,
      0x83d385c7,
      0x136c9856,
      0x646ba8c0,
      0xfd62f97a,
      0x8a65c9ec,
      0x14015c4f,
      0x63066cd9,
      0xfa0f3d63,
      0x8d080df5,
      0x3b6e20c8,
      0x4c69105e,
      0xd56041e4,
      0xa2677172,
      0x3c03e4d1,
      0x4b04d447,
      0xd20d85fd,
      0xa50ab56b,
      0x35b5a8fa,
      0x42b2986c,
      0xdbbbc9d6,
      0xacbcf940,
      0x32d86ce3,
      0x45df5c75,
      0xdcd60dcf,
      0xabd13d59,
      0x26d930ac,
      0x51de003a,
      0xc8d75180,
      0xbfd06116,
      0x21b4f4b5,
      0x56b3c423,
      0xcfba9599,
      0xb8bda50f,
      0x2802b89e,
      0x5f058808,
      0xc60cd9b2,
      0xb10be924,
      0x2f6f7c87,
      0x58684c11,
      0xc1611dab,
      0xb6662d3d,
      0x76dc4190,
      0x01db7106,
      0x98d220bc,
      0xefd5102a,
      0x71b18589,
      0x06b6b51f,
      0x9fbfe4a5,
      0xe8b8d433,
      0x7807c9a2,
      0x0f00f934,
      0x9609a88e,
      0xe10e9818,
      0x7f6a0dbb,
      0x086d3d2d,
      0x91646c97,
      0xe6635c01,
      0x6b6b51f4,
      0x1c6c6162,
      0x856530d8,
      0xf262004e,
      0x6c0695ed,
      0x1b01a57b,
      0x8208f4c1,
      0xf50fc457,
      0x65b0d9c6,
      0x12b7e950,
      0x8bbeb8ea,
      0xfcb9887c,
      0x62dd1ddf,
      0x15da2d49,
      0x8cd37cf3,
      0xfbd44c65,
      0x4db26158,
      0x3ab551ce,
      0xa3bc0074,
      0xd4bb30e2,
      0x4adfa541,
      0x3dd895d7,
      0xa4d1c46d,
      0xd3d6f4fb,
      0x4369e96a,
      0x346ed9fc,
      0xad678846,
      0xda60b8d0,
      0x44042d73,
      0x33031de5,
      0xaa0a4c5f,
      0xdd0d7cc9,
      0x5005713c,
      0x270241aa,
      0xbe0b1010,
      0xc90c2086,
      0x5768b525,
      0x206f85b3,
      0xb966d409,
      0xce61e49f,
      0x5edef90e,
      0x29d9c998,
      0xb0d09822,
      0xc7d7a8b4,
      0x59b33d17,
      0x2eb40d81,
      0xb7bd5c3b,
      0xc0ba6cad,
      0xedb88320,
      0x9abfb3b6,
      0x03b6e20c,
      0x74b1d29a,
      0xead54739,
      0x9dd277af,
      0x04db2615,
      0x73dc1683,
      0xe3630b12,
      0x94643b84,
      0x0d6d6a3e,
      0x7a6a5aa8,
      0xe40ecf0b,
      0x9309ff9d,
      0x0a00ae27,
      0x7d079eb1,
      0xf00f9344,
      0x8708a3d2,
      0x1e01f268,
      0x6906c2fe,
      0xf762575d,
      0x806567cb,
      0x196c3671,
      0x6e6b06e7,
      0xfed41b76,
      0x89d32be0,
      0x10da7a5a,
      0x67dd4acc,
      0xf9b9df6f,
      0x8ebeeff9,
      0x17b7be43,
      0x60b08ed5,
      0xd6d6a3e8,
      0xa1d1937e,
      0x38d8c2c4,
      0x4fdff252,
      0xd1bb67f1,
      0xa6bc5767,
      0x3fb506dd,
      0x48b2364b,
      0xd80d2bda,
      0xaf0a1b4c,
      0x36034af6,
      0x41047a60,
      0xdf60efc3,
      0xa867df55,
      0x316e8eef,
      0x4669be79,
      0xcb61b38c,
      0xbc66831a,
      0x256fd2a0,
      0x5268e236,
      0xcc0c7795,
      0xbb0b4703,
      0x220216b9,
      0x5505262f,
      0xc5ba3bbe,
      0xb2bd0b28,
      0x2bb45a92,
      0x5cb36a04,
      0xc2d7ffa7,
      0xb5d0cf31,
      0x2cd99e8b,
      0x5bdeae1d,
      0x9b64c2b0,
      0xec63f226,
      0x756aa39c,
      0x026d930a,
      0x9c0906a9,
      0xeb0e363f,
      0x72076785,
      0x05005713,
      0x95bf4a82,
      0xe2b87a14,
      0x7bb12bae,
      0x0cb61b38,
      0x92d28e9b,
      0xe5d5be0d,
      0x7cdcefb7,
      0x0bdbdf21,
      0x86d3d2d4,
      0xf1d4e242,
      0x68ddb3f8,
      0x1fda836e,
      0x81be16cd,
      0xf6b9265b,
      0x6fb077e1,
      0x18b74777,
      0x88085ae6,
      0xff0f6a70,
      0x66063bca,
      0x11010b5c,
      0x8f659eff,
      0xf862ae69,
      0x616bffd3,
      0x166ccf45,
      0xa00ae278,
      0xd70dd2ee,
      0x4e048354,
      0x3903b3c2,
      0xa7672661,
      0xd06016f7,
      0x4969474d,
      0x3e6e77db,
      0xaed16a4a,
      0xd9d65adc,
      0x40df0b66,
      0x37d83bf0,
      0xa9bcae53,
      0xdebb9ec5,
      0x47b2cf7f,
      0x30b5ffe9,
      0xbdbdf21c,
      0xcabac28a,
      0x53b39330,
      0x24b4a3a6,
      0xbad03605,
      0xcdd70693,
      0x54de5729,
      0x23d967bf,
      0xb3667a2e,
      0xc4614ab8,
      0x5d681b02,
      0x2a6f2b94,
      0xb40bbe37,
      0xc30c8ea1,
      0x5a05df1b,
      0x2d02ef8d,
    ];

    var crc = 0xffffffff;
    for (final byte in data) {
      crc = (crc >>> 8) ^ table[(crc ^ byte) & 0xff];
    }
    return crc ^ 0xffffffff;
  }
}

class _PngChunk {
  const _PngChunk(this.type, this.data);
  final String type;
  final Uint8List data;
}
