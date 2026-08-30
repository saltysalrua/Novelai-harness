/// NovelAI 官方质量词 / 负面排除词预设与提示词文本后处理。
library;

import 'nai_catalog.dart';

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
  /// V5 / V4.5 全系共用的 Furry Focus 负面词
  static const String _furryFocusUc =
      '{worst quality}, distracting watermark, unfinished, bad quality, {widescreen}, upscale, {sequence}, {{grandfathered content}}, blurred foreground, chromatic aberration, sketch, everyone, [sketch background], simple, [flat colors], ych (character), outline, multiple scenes, [[horror (theme)]], comic';

  /// V4 / V3 全系共用的 Furry Focus 负面词
  static const String _furryFocusUcV4 =
      '{{worst quality}}, [displeasing], {unusual pupils}, guide lines, {{unfinished}}, {bad}, url, artist name, {{tall image}}, mosaic, {sketch page}, comic panel, impact (font), [dated], {logo}, ych, {what}, {where is your god now}, {distorted text}, repeated text, {floating head}, {1994}, {widescreen}, absolutely everyone, sequence, {compression artifacts}, hard translated, {cropped}, {commissioner name}, unknown text, high contrast';

  /// V5 / V4.5 Full 共用的 Heavy 档负面词
  static const String _heavyUcV5 =
      'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page';

  /// V5 / V4.5 Full 共用的 Human Focus 档负面词
  static const String _humanFocusUcV5 =
      'lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page, @_@, mismatched pupils, glowing eyes, bad anatomy';

  /// 官方所有模型均提供全部 UC 预设 (含 Furry Focus)
  static const List<String> availablePresets = [
    'Heavy',
    'Light',
    'Human Focus',
    'Furry Focus',
    'None',
  ];

  static String getUndesiredContent(NaiModel model, String preset) {
    // 官网 v3 模型选 None 时仍固定追加 lowres
    if (preset == 'None') return model == NaiModel.v3 ? 'lowres' : '';

    return switch (model) {
      NaiModel.v5Full || NaiModel.v5Curated => switch (preset) {
        'Heavy' => _heavyUcV5,
        'Light' =>
          'lowres, bad hands, bad anatomy, artistic error, sepia, white haze, worst quality, very displeasing, jpeg artifacts, 0::ai-generated::',
        'Human Focus' => _humanFocusUcV5,
        'Furry Focus' => _furryFocusUc,
        _ => '',
      },
      NaiModel.v45Full => switch (preset) {
        'Heavy' => _heavyUcV5,
        'Light' =>
          'lowres, artistic error, scan artifacts, worst quality, bad quality, jpeg artifacts, multiple views, very displeasing, too many watermarks, negative space, blank page',
        'Human Focus' => _humanFocusUcV5,
        'Furry Focus' => _furryFocusUc,
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
        'Furry Focus' => _furryFocusUcV4,
        _ => '',
      },
      NaiModel.v4Curated => switch (preset) {
        'Heavy' =>
          'blurry, lowres, error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, logo, dated, signature, multiple views, gigantic breasts',
        'Light' =>
          'blurry, lowres, error, worst quality, bad quality, jpeg artifacts, very displeasing, logo, dated, signature',
        'Human Focus' =>
          'blurry, lowres, error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, logo, dated, signature, multiple views, gigantic breasts, bad anatomy, bad hands',
        'Furry Focus' => _furryFocusUcV4,
        _ => '',
      },
      NaiModel.v3 => switch (preset) {
        'Heavy' =>
          'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg artifacts, bad quality, watermark, unfinished, displeasing, chromatic aberration, signature, extra digits, artistic error, username, scan, [abstract]',
        'Light' =>
          'lowres, jpeg artifacts, worst quality, watermark, blurry, very displeasing',
        'Human Focus' =>
          'lowres, {bad}, error, fewer, extra, missing, worst quality, jpeg artifacts, bad quality, watermark, unfinished, displeasing, chromatic aberration, signature, extra digits, artistic error, username, scan, [abstract], bad anatomy, bad hands, @_@, mismatched pupils, heart-shaped pupils, glowing eyes',
        'Furry Focus' => _furryFocusUcV4,
        _ => '',
      },
      NaiModel.v3Furry => switch (preset) {
        'Heavy' => _furryFocusUcV4,
        'Light' =>
          '{worst quality}, guide lines, unfinished, bad, url, tall image, widescreen, compression artifacts, unknown text',
        'Human Focus' => _furryFocusUcV4,
        'Furry Focus' => _furryFocusUcV4,
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
