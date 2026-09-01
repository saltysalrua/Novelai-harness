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

  /// prompt-mix 混合段分隔符 `|` 与随机区间转义 `||`
  static const String promptMixSeparator = '|';
  static const String promptMixEscape = '||';

  /// 官网 prompt-mix 分段上限 (官网常量 jB)
  static const int maxPromptMixChunks = 6;

  /// 按 `|` 切分 prompt-mix 段：`||…||` 随机区间内的 `|` 不算分隔，
  /// 超过 6 段时剩余段原样合并 (官网常量 zg/jB 对应逻辑)。
  static List<String> splitPromptMixChunks(String prompt) {
    final chunks = <String>[];
    final buffer = StringBuffer();
    var escaped = false;

    for (var i = 0; i < prompt.length; i++) {
      final char = prompt[i];
      if (char == promptMixSeparator &&
          i + 1 < prompt.length &&
          prompt[i + 1] == promptMixSeparator) {
        escaped = !escaped;
        buffer.write(promptMixEscape);
        i++;
        continue;
      }
      if (char == promptMixSeparator && !escaped) {
        chunks.add(buffer.toString());
        buffer.clear();
        continue;
      }
      buffer.write(char);
    }
    chunks.add(buffer.toString());

    if (chunks.length <= maxPromptMixChunks) return chunks;
    return [
      ...chunks.take(maxPromptMixChunks - 1),
      chunks.skip(maxPromptMixChunks - 1).join(promptMixSeparator),
    ];
  }

  /// 官网两层追加逻辑 (2026-09 前端 bundle 反混淆确认)：
  /// 1. 按 `|` 切 prompt-mix——V4+ 只往第 0 段追加 (角色是独立字段，
  ///    仅第 0 段是基础提示词)；V3 每段都追加并保留段尾 `:权重`。
  /// 2. 段内按 `text:` 标记切分，只往标记之前追加。
  static String applySuffix(
    String prompt,
    String suffix, {
    required bool isV4OrAbove,
    required bool supportsTextRendering,
  }) {
    if (suffix.trim().isEmpty) return prompt.trim();

    if (isV4OrAbove) {
      final chunks = splitPromptMixChunks(prompt);
      // 保留第 0 段原有首尾空白，避免追加时吃掉用户输入的分段格式
      final raw = chunks[0];
      final leading = raw.substring(0, raw.length - raw.trimLeft().length);
      final trailing = raw.substring(raw.trimRight().length);
      chunks[0] =
          leading +
          appendSuffixWithTextAwareness(
            raw.trim(),
            suffix,
            supportsTextRendering: supportsTextRendering,
          ) +
          trailing;
      return chunks.join(promptMixSeparator);
    }

    // V3 及更早：官网直接按 `|` 切 (不做 || 转义、不设上限)，每段都加
    final weightPattern = RegExp(r':[\d.]+$');
    return prompt
        .split(promptMixSeparator)
        .map((chunk) {
          final weight = weightPattern.firstMatch(chunk)?.group(0) ?? '';
          final base = weight.isEmpty
              ? chunk
              : chunk.substring(0, chunk.length - weight.length);
          return appendSuffixWithTextAwareness(
                base,
                suffix,
                supportsTextRendering: false,
              ) +
              weight;
        })
        .join(promptMixSeparator);
  }

  /// 检查提示词是否包含 nsfw 标签 (含花括号/方括号修饰变体，大小写不敏感)
  static bool containsNsfwTag(String prompt) => _nsfwPattern.hasMatch(prompt);

  /// 按逗号分段 (去空白、去空段)
  static List<String> _splitTagSegments(String text) =>
      text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// 按逗号分段精确剥离提示词**末尾**与 [tags] 逐段一致的片段。
  ///
  /// 用于从元数据 Comment 还原基础提示词：只做末尾整段精确匹配，
  /// 匹配失败原样返回，不误伤中段自定义词。
  static String stripTrailingTagSegments(String prompt, String tags) {
    final trailing = _splitTagSegments(tags);
    if (trailing.isEmpty) return prompt;
    final segments = _splitTagSegments(prompt);
    if (segments.length < trailing.length) return prompt;
    for (var i = 0; i < trailing.length; i++) {
      if (segments[segments.length - trailing.length + i] != trailing[i]) {
        return prompt;
      }
    }
    return segments.sublist(0, segments.length - trailing.length).join(', ');
  }

  /// 按逗号分段精确剥离提示词**开头**与 [tags] 逐段一致的片段。
  static String stripLeadingTagSegments(String prompt, String tags) {
    final leading = _splitTagSegments(tags);
    if (leading.isEmpty) return prompt;
    final segments = _splitTagSegments(prompt);
    if (segments.length < leading.length) return prompt;
    for (var i = 0; i < leading.length; i++) {
      if (segments[i] != leading[i]) return prompt;
    }
    return segments.sublist(leading.length).join(', ');
  }

  /// stripTrailingTagSegments 的 text: 标记感知版：末尾匹配失败且模型支持
  /// 文字渲染时，尝试剥离第一个 text: 标记之前紧贴的质量词片段
  /// (appendSuffixWithTextAwareness 把质量词插在标记前，剥离必须对称)。
  static String stripTrailingTagSegmentsTextAware(
    String prompt,
    String tags, {
    required bool supportsTextRendering,
  }) {
    final direct = stripTrailingTagSegments(prompt, tags);
    if (direct != prompt) return direct;
    if (!supportsTextRendering) return prompt;
    final match = _firstTextMarkerOutsideRandomizer(prompt);
    if (match == null) return prompt;

    final before = prompt.substring(0, match.start);
    final stripped = stripTrailingTagSegments(before, tags);
    if (stripped == before) return prompt;
    return stripped + prompt.substring(match.start);
  }

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

/// Auto Text 注入用的角色信息 (提示词 + 画布坐标)
typedef NaiAutoTextCharacter = ({
  String prompt,
  double centerX,
  double centerY,
});

/// NovelAI 官网 V5 的 Auto Text (引号文字自动注入 `teXt:` 渲染段)。
///
/// 2026-09 官网前端 bundle 反混淆确认：官网在质量词追加之后，把基础提示词
/// 与各角色提示词中**引号包住的文字**提取出来，合成 `teXt: 文本1\n\n文本2`
/// 段追加到 prompt-mix 第 0 段末尾——因此生效提示词里质量词永远落在
/// `teXt:` 之前。标记固定写作 `teXt:` (大小写敏感) 是为了与用户手写的
/// `text:` 区分，剥离时只认 `teXt:` 且要求内容与引号提取完全一致，避免
/// 误删用户手写内容。仅 V5 系列模型启用 (Aaalice supportsAutoText=V5 only)。
abstract final class NovelAiAutoText {
  NovelAiAutoText._();

  static const String marker = 'teXt:';

  /// 官网生成的 `teXt:` 标记 (大小写敏感，区别于用户手写的 text:)
  static final RegExp _generatedMarker = RegExp(
    r'(?:^|\s|[,.:\[\]{}、。])teXt:(?!:)',
  );

  static final RegExp _singleQuoteBoundary = RegExp(r'[\s,.]');
  static final RegExp _letterOrNumber = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static final RegExp _cjkCharacter = RegExp(
    r'[\u3000-\u303F\u3040-\u309F\u30A0-\u30FF'
    r'\uFF00-\uFF9F\u4E00-\u9FAF\u3400-\u4DBF]',
    unicode: true,
  );

  /// 官网引号配对表 (直引号、中文双引号、日文方头引号、单引号对)
  static const Map<String, String> _quotePairs = {
    '"': '"',
    '“': '”',
    '「': '」',
    "'": "'",
    '‘': '’',
  };

  /// 提示词或任一启用角色已有 `text:` 标记 (大小写不敏感) 时官网跳过注入
  static bool shouldSkip(String prompt, List<NaiAutoTextCharacter> characters) {
    final marker = RegExp(
      r'(?:^|\s|[,.:\[\]{}、。])text:(?!:)',
      caseSensitive: false,
    );
    return marker.hasMatch(prompt) ||
        characters.any((c) => marker.hasMatch(c.prompt));
  }

  /// 合成官网会注入的 `teXt:` 文本块；无引号文字或已有 text: 标记时返回 null
  static String? buildBlock(
    String prompt, {
    List<NaiAutoTextCharacter> characters = const [],
    bool useCoords = false,
  }) {
    final enabled = characters
        .where((c) => c.prompt.isNotEmpty)
        .toList(growable: false);
    if (shouldSkip(prompt, enabled)) return null;

    final chunks = NovelAiPromptText.splitPromptMixChunks(prompt);
    final quotedTexts = _collectQuotedTexts(
      chunks.first,
      enabled,
      useCoords: useCoords,
    );
    if (quotedTexts.isEmpty) return null;
    return '$marker ${quotedTexts.join('\n\n')}';
  }

  /// 把生成的 `teXt:` 文本块追加到 prompt-mix 第 0 段末尾 (官网 _ 函数)
  static String apply(
    String prompt, {
    List<NaiAutoTextCharacter> characters = const [],
    bool useCoords = false,
  }) {
    final block = buildBlock(
      prompt,
      characters: characters,
      useCoords: useCoords,
    );
    if (block == null) return prompt;

    final chunks = NovelAiPromptText.splitPromptMixChunks(prompt);
    final base = chunks.first.replaceFirst(RegExp(r'[\s,]+$'), '');
    chunks[0] = base.isEmpty ? block : '$base, $block';
    return chunks.join(NovelAiPromptText.promptMixSeparator);
  }

  /// 剥离自动注入的 `teXt:` 段 (官网 C 函数同款校验)：仅当标记后的内容
  /// 与剩余提示词的引号提取完全一致时才剥离，用户手写内容原样保留。
  static String stripGeneratedBlock(
    String prompt, {
    List<NaiAutoTextCharacter> characters = const [],
    bool useCoords = false,
  }) {
    final chunks = NovelAiPromptText.splitPromptMixChunks(prompt);
    final stripped = chunks.map((chunk) {
      final match = _generatedMarker.firstMatch(chunk);
      if (match == null) return chunk;

      final prefix = chunk.substring(0, match.start);
      final expected = _collectQuotedTexts(
        prefix,
        characters,
        useCoords: useCoords,
      ).join('\n\n');
      final actual = chunk.substring(match.end).trim();
      if (actual != expected) return chunk;
      return prefix.replaceFirst(RegExp(r'[\s,]+$'), '');
    });
    return stripped.join(NovelAiPromptText.promptMixSeparator);
  }

  /// 收集基础提示词与各角色提示词中的引号文字；日文占比 > 30% 时每组倒序
  static List<String> _collectQuotedTexts(
    String basePrompt,
    List<NaiAutoTextCharacter> characters, {
    required bool useCoords,
  }) {
    final ordered = useCoords
        ? _sortCharactersByReadingOrder(characters)
        : characters;
    final groups = <List<String>>[
      _extractQuotedTexts(basePrompt),
      for (final character in ordered) _extractQuotedTexts(character.prompt),
    ];

    final combined = groups.expand((group) => group).join();
    final cjkCount = _cjkCharacter.allMatches(combined).length;
    if (combined.isNotEmpty && cjkCount / combined.length > 0.3) {
      for (final group in groups) {
        final reversed = group.reversed.toList(growable: false);
        group.setAll(0, reversed);
      }
    }
    return groups.expand((group) => group).toList(growable: false);
  }

  /// 提取提示词中引号包住的文字 (官网 g 函数：配对引号 + 缩写保护)
  static List<String> _extractQuotedTexts(String prompt) {
    final result = <String>[];
    var cursor = 0;
    while (cursor < prompt.length) {
      final opening = prompt[cursor];
      final closing = _quotePairs[opening];
      final acceptsOpening =
          closing != null &&
          (opening != "'" || _isSingleQuoteBoundary(prompt, cursor - 1));
      if (!acceptsOpening) {
        cursor++;
        continue;
      }

      final apostropheStyle = closing == "'" || closing == '’';
      var end = cursor + 1;
      while (end < prompt.length &&
          (prompt[end] != closing ||
              (apostropheStyle && _isLetterOrNumber(prompt, end + 1)))) {
        end++;
      }
      if (end >= prompt.length) {
        cursor++;
        continue;
      }

      final value = prompt.substring(cursor + 1, end).trim();
      if (value.isNotEmpty) result.add(value);
      cursor = end + 1;
    }
    return result;
  }

  static bool _isSingleQuoteBoundary(String text, int index) {
    if (index < 0 || index >= text.length) return true;
    return _singleQuoteBoundary.hasMatch(text[index]);
  }

  static bool _isLetterOrNumber(String text, int index) {
    if (index < 0 || index >= text.length) return false;
    return _letterOrNumber.hasMatch(text[index]);
  }

  /// 按阅读顺序 (先 y 分行、行内按 x) 排序角色 (官网 b/y 函数)
  static List<NaiAutoTextCharacter> _sortCharactersByReadingOrder(
    List<NaiAutoTextCharacter> characters,
  ) {
    final byY = _stableSort(
      characters,
      (a, b) => a.centerY.compareTo(b.centerY),
    );
    return _splitRows(byY)
        .expand(
          (row) => _stableSort(row, (a, b) => a.centerX.compareTo(b.centerX)),
        )
        .toList(growable: false);
  }

  static List<List<NaiAutoTextCharacter>> _splitRows(
    List<NaiAutoTextCharacter> characters,
  ) {
    if (characters.length <= 1) return [characters];

    final totalSpan = characters.last.centerY - characters.first.centerY;
    var splitIndex = 1;
    var largestGap = -1.0;
    for (var index = 1; index < characters.length; index++) {
      final gap = characters[index].centerY - characters[index - 1].centerY;
      if (gap > largestGap) {
        largestGap = gap;
        splitIndex = index;
      }
    }
    if (totalSpan <= 0.15 && largestGap <= 0.1) return [characters];

    return [
      ..._splitRows(characters.sublist(0, splitIndex)),
      ..._splitRows(characters.sublist(splitIndex)),
    ];
  }

  static List<T> _stableSort<T>(
    List<T> values,
    int Function(T a, T b) compare,
  ) {
    final indexed = <({int index, T value})>[
      for (var index = 0; index < values.length; index++)
        (index: index, value: values[index]),
    ];
    indexed.sort((left, right) {
      final result = compare(left.value, right.value);
      return result != 0 ? result : left.index.compareTo(right.index);
    });
    return indexed.map((entry) => entry.value).toList(growable: false);
  }
}
