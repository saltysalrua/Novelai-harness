import 'dart:convert';

import 'package:intl/intl.dart';

import '../models/nai_generation_params.dart';
import '../models/nai_image_result.dart';

/// 命名只使用图片生成时的快照，不读取当前工作台或保存时的时钟。
class ImageSaveContext {
  final NaiGenerationParams params;
  final DateTime createdAt;
  final int seed;
  final String prefix;
  final String? outputModel;

  const ImageSaveContext({
    required this.params,
    required this.createdAt,
    required this.seed,
    this.prefix = 'nai',
    this.outputModel,
  });

  factory ImageSaveContext.fromImage(NaiGeneratedImage image) =>
      ImageSaveContext(
        params: image.params,
        outputModel: image.outputModel,
        createdAt: image.createdAt,
        seed: image.seed,
        prefix: image.isUpscaled
            ? 'nai_upscaled'
            : image.isInpainted
            ? 'nai_inpaint'
            : image.isAiEdited
            ? 'nai_ai_edit'
            : image.id.startsWith('comfy_')
            ? 'comfyui'
            : 'nai',
      );

  String get type => switch (prefix) {
    'nai_upscaled' => 'upscale',
    'nai_inpaint' => 'inpaint',
    'nai_ai_edit' => 'ai_edit',
    'comfyui' => 'comfyui',
    _ => 'generate',
  };
}

enum ImageSaveTemplateError { invalidMacro, invalidPath, tooLong }

/// 文件名/目录宏的唯一解析器；无 IO，设置预览与真实导出共用。
abstract final class ImageSavePathService {
  static const defaultTemplate = '{prefix}_{date}_{time}_{seed}';
  static const macroNames = [
    'prefix',
    'type',
    'date',
    'time',
    'year',
    'month',
    'day',
    'seed',
    'model',
    'width',
    'height',
    'resolution',
    'steps',
    'cfg',
    'sampler',
    'scheduler',
    'prompt',
  ];
  static const reservedDirectories = {'cache', 'board_refs'};
  static final _macro = RegExp(r'\{([^{}]+)\}');
  static final _datePattern = RegExp(r'^[yMdHmsS_. -]{1,64}$');
  static final _invalidChars = RegExp(r'[<>:"/\\|?*\x00-\x1f\x7f]');
  static final _devices = RegExp(
    r'^(con|prn|aux|nul|com[1-9¹²³]|lpt[1-9¹²³])(?:\.|$)',
    caseSensitive: false,
  );

  static String normalizeTemplate(String template) =>
      template.trim().isEmpty ? defaultTemplate : template.trim();

  static bool _validMacro(String macro) =>
      macroNames.contains(macro) ||
      (macro.startsWith('date:') && _datePattern.hasMatch(macro.substring(5)));

  static ImageSaveTemplateError? validate(String template) {
    final source = normalizeTemplate(template);
    if (source.length > 512) return ImageSaveTemplateError.tooLong;
    for (final match in _macro.allMatches(source)) {
      if (!_validMacro(match[1]!)) return ImageSaveTemplateError.invalidMacro;
    }
    final literal = source.replaceAll(_macro, 'macro');
    if (literal.contains('{') || literal.contains('}')) {
      return ImageSaveTemplateError.invalidMacro;
    }
    final parts = literal.replaceAll('\\', '/').split('/');
    if (parts.length > 8) return ImageSaveTemplateError.tooLong;
    if (parts.any(
      (part) =>
          part.trim().isEmpty ||
          part.trim() == '.' ||
          part.trim() == '..' ||
          _invalidChars.hasMatch(part),
    )) {
      return ImageSaveTemplateError.invalidPath;
    }
    if (parts.length > 1 &&
        reservedDirectories.contains(parts.first.toLowerCase())) {
      return ImageSaveTemplateError.invalidPath;
    }
    return null;
  }

  /// 返回以 / 分隔的安全相对 PNG 路径；无效外部配置回退默认模板。
  /// 宏值先净化再拼接，prompt 内的斜杠永远不能制造子目录。
  static String resolve(String template, ImageSaveContext context) {
    final source = validate(template) == null
        ? normalizeTemplate(template)
        : defaultTemplate;
    final parts = source.replaceAll('\\', '/').split('/');
    final values = _values(context);
    final resolved = <String>[];
    for (var i = 0; i < parts.length; i++) {
      var expanded = parts[i].replaceAllMapped(_macro, (match) {
        final key = match[1]!;
        final value = key.startsWith('date:')
            ? DateFormat(key.substring(5), 'en_US').format(context.createdAt)
            : values[key]!;
        return sanitizeSegment(value, maxBytes: 80);
      });
      if (i == parts.length - 1 && expanded.toLowerCase().endsWith('.png')) {
        expanded = expanded.substring(0, expanded.length - 4);
      }
      // 全部相对路径不超过 180 UTF-8 bytes (含后续 .png)，深目录均分预算。
      resolved.add(
        sanitizeSegment(expanded, maxBytes: 176 ~/ parts.length - 1),
      );
    }
    if (resolved.length > 1 &&
        reservedDirectories.contains(resolved.first.toLowerCase())) {
      resolved[0] = '_${resolved.first}';
    }
    return '${resolved.join('/')}.png';
  }

  static Map<String, String> _values(ImageSaveContext context) {
    final params = context.params;
    String date(String pattern) =>
        DateFormat(pattern, 'en_US').format(context.createdAt);
    return {
      'prefix': context.prefix,
      'type': context.type,
      'date': date('yyyyMMdd'),
      'time': date('HHmmss'),
      'year': date('yyyy'),
      'month': date('MM'),
      'day': date('dd'),
      'seed': '${context.seed}',
      'model': context.outputModel ?? params.model.id,
      'width': '${params.width}',
      'height': '${params.height}',
      'resolution': '${params.width}x${params.height}',
      'steps': '${params.steps}',
      'cfg': '${params.scale}',
      'sampler': params.sampler.id,
      'scheduler': params.noiseSchedule.id,
      'prompt': params.prompt,
    };
  }

  /// 跨平台净化：Windows 保留名/尾随点空格、控制字符与 Unicode 字节上限。
  static String sanitizeSegment(String text, {int maxBytes = 80}) {
    var result = text
        .replaceAll(_invalidChars, '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    final buffer = StringBuffer();
    var size = 0;
    for (final rune in result.runes) {
      final char = String.fromCharCode(rune);
      size += utf8.encode(char).length;
      if (size > maxBytes - 1) break;
      buffer.write(char);
    }
    result = buffer.toString().replaceAll(RegExp(r'[. ]+$'), '');
    if (result.isEmpty || result == '.' || result == '..') result = '_';
    if (_devices.hasMatch(result)) result = '_$result';
    return result;
  }
}
