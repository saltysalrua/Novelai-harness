/// 用户违禁词列表的解析与提示词剥离。
///
/// 生成请求组装前调用：从固定前后缀、主提示词、负面词、质量词、
/// UC 预设和角色提示词里去掉用户列出的词，避免这些词进入模型请求。
/// 编辑框里的原文不改，关闭开关后原词仍会送出。
abstract final class BannedWordSanitizer {
  BannedWordSanitizer._();

  static final RegExp _listSeparator = RegExp(r'[\n,，;；]+');
  static final RegExp _asciiTerm = RegExp(r"^[A-Za-z0-9][A-Za-z0-9 _'\-]*$");
  static final RegExp _emptyWeight = RegExp(r'-?\d+(?:\.\d+)?\s*::\s*::');
  static final RegExp _orphanColons = RegExp(
    r'(?<![\p{L}\p{N}_])::+(?![\p{L}\p{N}_])',
    unicode: true,
  );
  static final RegExp _emptyBraces = RegExp(r'\{\s*\}|\[\s*\]|\(\s*\)');
  static final RegExp _repeatedCommas = RegExp(r'(?:\s*[,，]\s*){2,}');
  static final RegExp _edgeCommas = RegExp(r'^[\s,，]+|[\s,，]+$');
  static final RegExp _commaBeforeRandomizer = RegExp(r'\s*,\s*(?=\|\|)');
  static final RegExp _commaAfterRandomizer = RegExp(r'(?<=\|\|)\s*,\s*');
  static final RegExp _emptyPipeChunk = RegExp(r'(?<!\|)\|\s+\|(?!\|)');
  static final RegExp _repeatedSpaces = RegExp(r'[ \t]{2,}');

  /// 按换行、英文逗号、中文逗号或分号拆开，去掉空白并按大小写去重。
  static List<String> parseList(String raw) {
    final seen = <String>{};
    final words = <String>[];
    for (final part in raw.split(_listSeparator)) {
      final word = part.trim();
      if (word.isEmpty) continue;
      if (seen.add(word.toLowerCase())) words.add(word);
    }
    return words;
  }

  /// 从 [text] 中去掉 [wordList] 里的词。列表为空或没有命中时原样返回。
  ///
  /// 英文、数字和下划线按完整词匹配，避免 `art` 误伤 `artist`。
  /// 含中文或其他符号的词按子串去掉。匹配不区分大小写。
  static String strip(String text, String wordList) {
    final words = parseList(wordList);
    if (text.isEmpty || words.isEmpty) return text;
    final pattern = _patternFor(words);
    if (!pattern.hasMatch(text)) return text;
    return _cleanup(text.replaceAll(pattern, ''));
  }

  static RegExp _patternFor(List<String> words) {
    final ordered = [...words]..sort((a, b) => b.length.compareTo(a.length));
    final alternatives = ordered.map((word) {
      final body = RegExp.escape(word);
      if (_asciiTerm.hasMatch(word)) {
        return '(?<![\\p{L}\\p{N}_])$body(?![\\p{L}\\p{N}_])';
      }
      return body;
    });
    return RegExp(
      '(?:${alternatives.join('|')})',
      caseSensitive: false,
      unicode: true,
    );
  }

  /// 去掉词之后清掉空权重、空括号和多余逗号，避免留下 `1.2::::` 这类残段。
  static String _cleanup(String text) {
    var result = text;
    for (var i = 0; i < 4; i++) {
      final next = result
          .replaceAll(_emptyWeight, '')
          .replaceAll(_orphanColons, '')
          .replaceAll(_emptyBraces, '')
          .replaceAll(_repeatedCommas, ', ')
          .replaceAll(_commaBeforeRandomizer, '')
          .replaceAll(_commaAfterRandomizer, '')
          .replaceAll(_emptyPipeChunk, '|')
          .replaceAll(_repeatedSpaces, ' ');
      if (next == result) break;
      result = next;
    }
    return result.replaceAll(_edgeCommas, '').trim();
  }
}
