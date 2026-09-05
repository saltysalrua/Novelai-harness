import '../models/tag_models.dart';

/// NovelAI 提示词 AST 分词与语法变换引擎
class PromptAstEngine {
  static const Set<String> separators = {',', '，', '\n', '|'};

  static bool _isSpace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';

  static int _trimL(String text, int a, int b) {
    while (a < b && _isSpace(text[a])) {
      a++;
    }
    return a;
  }

  static int _trimR(String text, int a, int b) {
    while (b > a && _isSpace(text[b - 1])) {
      b--;
    }
    return b;
  }

  /// 是否为 CJK 书写体系字符 (汉字/假名/谚文/全角符号)
  /// 中英混排时书写体系切换处视为单词边界 (如 `过曝high` → `过曝 | high`)
  static bool _isCjkScript(String c) {
    final r = c.runes.first;
    return (r >= 0x2E80 && r <= 0x9FFF) || // CJK 部首/假名/汉字
        (r >= 0xAC00 && r <= 0xD7AF) || // 谚文音节
        (r >= 0xF900 && r <= 0xFAFF) || // CJK 兼容表意
        (r >= 0xFF00 && r <= 0xFFEF); // 全角形式
  }

  /// 解析整段文本为 `NaiPromptToken` 列表
  static List<NaiPromptToken> parsePromptTokens(
    String text, {
    String? Function(String tagName)? translationLookup,
    DanbooruTagCategory? Function(String tagName)? categoryLookup,
  }) {
    if (text.isEmpty) return const [];

    final tokens = <NaiPromptToken>[];
    var start = 0;

    void processSegment(int rawStart, int rawEnd) {
      var a = _trimL(text, rawStart, rawEnd);
      var b = _trimR(text, a, rawEnd);
      if (b <= a) return;

      final segS = a;
      final segE = b;

      // 1. 剥除禁用符 ~
      var disabled = false;
      if (text[a] == '~') {
        disabled = true;
        a++;
        if (b > a && text[b - 1] == '~') b--;
        a = _trimL(text, a, b);
        b = _trimR(text, a, b);
      }
      final coreS = a;
      final coreE = b;

      // 2. 剥除外层括号 (统计净档数: {} 为正, [] 为负)
      var braceLevel = 0;
      var ia = a;
      var ib = b;
      while (ib - ia >= 2) {
        if (text[ia] == '{' && text[ib - 1] == '}') {
          braceLevel++;
        } else if (text[ia] == '[' && text[ib - 1] == ']') {
          braceLevel--;
        } else {
          break;
        }
        ia++;
        ib--;
        ia = _trimL(text, ia, ib);
        ib = _trimR(text, ia, ib);
      }
      final innerS = ia;
      final innerE = ib;

      // 3. 剥除内层数值 N::name::
      var numMult = 1.0;
      var nameS = ia;
      var nameE = ib;
      final inner = text.substring(ia, ib);
      final di = inner.indexOf('::');
      final dj = inner.lastIndexOf('::');

      if (di > 0 && dj > di && dj == inner.length - 2) {
        final num = double.tryParse(inner.substring(0, di));
        if (num != null) {
          numMult = num;
          nameS = _trimL(text, ia + di + 2, ib);
          nameE = _trimR(text, nameS, ia + dj);
        }
      } else if (di > 0 && dj == di) {
        // 单个 :: 开头未闭合 (如 1.5::tag)
        final num = double.tryParse(inner.substring(0, di));
        if (num != null) {
          numMult = num;
          nameS = _trimL(text, ia + di + 2, ib);
          nameE = ib;
        }
      }

      final name = text.substring(nameS, nameE);
      final normalizedName = name.replaceAll('_', ' ').trim().toLowerCase();

      final token = NaiPromptToken(
        segStart: segS,
        segEnd: segE,
        coreStart: coreS,
        coreEnd: coreE,
        innerStart: innerS,
        innerEnd: innerE,
        nameStart: nameS,
        nameEnd: nameE,
        name: name,
        braceLevel: braceLevel,
        numMult: numMult,
        disabled: disabled,
        translation: translationLookup?.call(normalizedName),
        category: categoryLookup?.call(normalizedName),
      );

      tokens.add(token);
    }

    for (var k = 0; k < text.length; k++) {
      final c = text[k];
      if (separators.contains(c)) {
        processSegment(start, k);
        start = k + 1;
      }
    }
    processSegment(start, text.length);

    return tokens;
  }

  /// 获取光标所在位置的 Token 索引 (无则返回 -1)
  static int tokIndexAt(
    String text,
    int offset, [
    List<NaiPromptToken>? tokens,
  ]) {
    final toks = tokens ?? parsePromptTokens(text);
    for (var i = 0; i < toks.length; i++) {
      if (offset >= toks[i].segStart && offset <= toks[i].segEnd) {
        return i;
      }
    }
    return -1;
  }

  /// 倍率格式化 (去除末尾多余的 0，如 1.30 -> "1.3", 1.00 -> "1", -0.50 -> "-0.5")
  static String formatMultiplier(double m) {
    if (m.abs() < 0.0001) return '0';
    var s = m.toStringAsFixed(2);
    if (s.contains('.')) {
      s = s.replaceFirst(RegExp(r'0+$'), '');
      s = s.replaceFirst(RegExp(r'\.$'), '');
    }
    return s;
  }

  /// 括号包裹操作：给 core 外套一层 `{}` (up: true) 或 `[]` (up: false)
  static String wrapBracket(String text, NaiPromptToken t, {required bool up}) {
    final core = text.substring(t.coreStart, t.coreEnd);
    final s = up ? '{$core}' : '[$core]';
    return text.replaceRange(t.coreStart, t.coreEnd, s);
  }

  /// 步进调整数值权重 (格式为 `x.x::tag::`，步长 step 默认 0.1) -> (新文本, 推荐光标位置)
  ///
  /// 例如：
  /// - `1girl` -> `1.1::1girl::` -> `1.2::1girl::`
  /// - `1.1::1girl::` (down) -> `1girl` (归一化为 1.0) -> `0.9::1girl::`
  /// - `{masterpiece}` (up) -> `1.1::masterpiece::`
  static (String, int) adjustNumericWeight(
    String text,
    NaiPromptToken t, {
    required bool up,
    double step = 0.1,
    int cursorOffset = -1,
  }) {
    var currentMult = t.numMult;
    if (t.numMult == 1.0 && t.braceLevel != 0) {
      currentMult = t.effectiveMultiplier;
    }

    var newMult = up ? currentMult + step : currentMult - step;
    newMult = (newMult * 10).roundToDouble() / 10;
    newMult = newMult.clamp(-5.0, 5.0);

    final isDefault = (newMult - 1.0).abs() < 0.005;
    final replacement = isDefault
        ? t.name
        : '${formatMultiplier(newMult)}::${t.name}::';

    final newText = text.replaceRange(t.coreStart, t.coreEnd, replacement);
    final delta = replacement.length - (t.coreEnd - t.coreStart);
    final newCursor = cursorOffset >= 0
        ? (cursorOffset + delta).clamp(0, newText.length)
        : (t.coreStart + replacement.length).clamp(0, newText.length);

    return (newText, newCursor);
  }

  /// 修改数值倍率：只修改内层 `N::name::`
  static String setNumericMultiplier(
    String text,
    NaiPromptToken t,
    double newMult,
  ) {
    final m = (newMult * 100).roundToDouble() / 100;
    final inner = (m - 1.0).abs() < 0.005
        ? t.name
        : '${formatMultiplier(m)}::${t.name}::';
    return text.replaceRange(t.innerStart, t.innerEnd, inner);
  }

  /// 清除全部权重：剥离所有括号与数值，回归纯 tag 名
  static String clearWeight(String text, NaiPromptToken t) {
    return text.replaceRange(t.coreStart, t.coreEnd, t.name);
  }

  /// 切换标签禁用状态：整枚套/剥 `~`
  static String toggleDisabled(String text, NaiPromptToken t) {
    return t.disabled
        ? text.replaceRange(
            t.segStart,
            t.segEnd,
            text.substring(t.coreStart, t.coreEnd),
          )
        : text.replaceRange(
            t.segStart,
            t.segEnd,
            '~${text.substring(t.segStart, t.segEnd)}~',
          );
  }

  /// 删除单个标签 (智能清理相邻的逗号与空格) -> (新文本, 推荐光标位置)
  static (String, int) deleteToken(String text, NaiPromptToken t) {
    var a = t.segStart;
    var b = t.segEnd;
    var e = b;

    // 优先吞掉右侧逗号
    while (e < text.length && (text[e] == ' ' || text[e] == '\t')) {
      e++;
    }
    if (e < text.length && (text[e] == ',' || text[e] == '，')) {
      e++;
      while (e < text.length && text[e] == ' ') {
        e++;
      }
      b = e;
    } else {
      // 否则吞掉左侧逗号
      var st = a;
      while (st > 0 && text[st - 1] == ' ') {
        st--;
      }
      if (st > 0 && (text[st - 1] == ',' || text[st - 1] == '，')) {
        st--;
        while (st > 0 && text[st - 1] == ' ') {
          st--;
        }
        a = st;
      }
    }

    final newText = text.replaceRange(a, b, '');
    return (newText, a.clamp(0, newText.length));
  }

  /// 从当前光标位置提取正在编辑的查询词与替换范围 (支持所有括号权重、数值权重与禁用标记)
  ///
  /// 例如：
  /// - `1girl, long h|` -> query: `long h`, replaceStart: 7, replaceEnd: 13, fullSegmentEnd: 13
  /// - `1girl, {1gi|}` -> query: `1gi`, replaceStart: 8, replaceEnd: 11, syntaxPrefix: '{', syntaxSuffix: '}', fullSegmentEnd: 12
  /// - `1.2::silv|::` -> query: `silv`, replaceStart: 5, replaceEnd: 9, syntaxPrefix: '1.2::', syntaxSuffix: '::', fullSegmentEnd: 11
  /// - `(masterpiece:1.2)` -> query: `masterpiece`, replaceStart: 1, replaceEnd: 12, syntaxPrefix: '(', syntaxSuffix: ':1.2)', fullSegmentEnd: 17
  ///
  /// 替换终点只延伸到光标所在单词的边界 (下一个空格、CJK↔拉丁书写体系切换处或核心末尾)，
  /// 不会吞掉光标之后直到分隔符的其余文本：
  /// - `blue h|air blue eyes` -> replaceEnd 停在 `hair` 词尾，`blue eyes` 保留
  /// - `过曝|high complexity` -> replaceEnd 停在 `过曝` 词尾，`high complexity` 保留
  static ({
    String query,
    int replaceStart,
    int replaceEnd,
    int coreEnd,
    String syntaxPrefix,
    String syntaxSuffix,
    int fullSegmentEnd,
  })?
  extractActiveQuery(String text, int cursorOffset) {
    if (text.isEmpty || cursorOffset < 0 || cursorOffset > text.length) {
      return null;
    }

    // 1. 寻找逗号、分号、换行或竖线分隔符界限
    var segStart = cursorOffset;
    while (segStart > 0) {
      final prev = text[segStart - 1];
      if (separators.contains(prev)) break;
      segStart--;
    }

    var segEnd = cursorOffset;
    while (segEnd < text.length) {
      final next = text[segEnd];
      if (separators.contains(next)) break;
      segEnd++;
    }

    // 2. 剥离段落外层空白
    final tokenStart = _trimL(text, segStart, segEnd);
    final tokenEnd = _trimR(text, tokenStart, segEnd);

    if (tokenStart >= tokenEnd) {
      return null;
    }

    // 如果光标在开头的空白区之前，或者段落有效范围之外
    if (cursorOffset < tokenStart || cursorOffset > segEnd) {
      return null;
    }

    // 3. 循环剥离语法前缀与语法后缀
    var curStart = tokenStart;
    var curEnd = tokenEnd;
    var changed = true;

    while (changed && curStart < curEnd) {
      changed = false;
      final currentChunk = text.substring(curStart, curEnd);

      // 3.1 NAI 官方数值权重前缀 (如 1.2::, -0.5::)
      final weightPrefixMatch = RegExp(
        r'^-?\d+(?:\.\d+)?::',
      ).firstMatch(currentChunk);
      if (weightPrefixMatch != null) {
        final len = weightPrefixMatch.group(0)!.length;
        curStart += len;
        changed = true;
        continue;
      }

      // 3.2 开括号与波浪线前缀
      if (curStart < curEnd) {
        final firstChar = text[curStart];
        if (firstChar == '{' ||
            firstChar == '[' ||
            firstChar == '(' ||
            firstChar == '~') {
          curStart += 1;
          changed = true;
          continue;
        }
      }

      // 3.3 NAI 官方数值权重后缀 (末尾 ::)
      if (curEnd - curStart >= 2 &&
          text.substring(curEnd - 2, curEnd) == '::') {
        curEnd -= 2;
        changed = true;
        continue;
      }

      // 3.4 SD 冒号权重后缀 (如 :1.2, :1.2))
      final sdWeightMatch = RegExp(
        r':-?\d+(?:\.\d+)?\)?$',
      ).firstMatch(currentChunk);
      if (sdWeightMatch != null && sdWeightMatch.start > 0) {
        curEnd = curStart + sdWeightMatch.start;
        changed = true;
        continue;
      }

      // 3.5 闭括号与波浪线后缀
      if (curEnd > curStart) {
        final lastChar = text[curEnd - 1];
        if (lastChar == '}' ||
            lastChar == ']' ||
            lastChar == ')' ||
            lastChar == '~') {
          curEnd -= 1;
          changed = true;
          continue;
        }
      }
    }

    final syntaxPrefix = text.substring(tokenStart, curStart);
    final syntaxSuffix = text.substring(curEnd, tokenEnd);

    // 4. 剥离核心区域两端的空格
    final coreStart = _trimL(text, curStart, curEnd);
    final coreEnd = _trimR(text, coreStart, curEnd);

    if (coreStart >= coreEnd) {
      return null;
    }

    // 5. 提取当前正在编辑的 query 文本
    final wholeCore = text.substring(coreStart, coreEnd);

    // 计算有效 query
    final queryEnd = cursorOffset.clamp(coreStart, coreEnd);
    var query = text.substring(coreStart, queryEnd).trim();

    // 若光标在词首或 query 为空，则以整个核心词为 query
    var wholeCoreAsQuery = false;
    if (query.isEmpty) {
      query = wholeCore.trim();
      wholeCoreAsQuery = true;
    }

    if (query.isEmpty) {
      return null;
    }

    // 替换终点：默认到核心末尾；光标位于核心内部时只延伸到当前单词边界
    // (下一个空格、CJK↔拉丁书写体系切换处或核心末尾)，
    // 避免吞掉光标之后属于后续内容的文本 (如 `过曝|high complexity` 只替换 `过曝`)
    var replaceEnd = coreEnd;
    if (!wholeCoreAsQuery && queryEnd < coreEnd) {
      replaceEnd = queryEnd;
      while (replaceEnd < coreEnd) {
        final ch = text[replaceEnd];
        if (_isSpace(ch)) break;
        if (_isCjkScript(ch) != _isCjkScript(text[replaceEnd - 1])) break;
        replaceEnd++;
      }
    }

    return (
      query: query,
      replaceStart: coreStart,
      replaceEnd: replaceEnd,
      coreEnd: coreEnd,
      syntaxPrefix: syntaxPrefix,
      syntaxSuffix: syntaxSuffix,
      fullSegmentEnd: tokenEnd,
    );
  }

  /// 将 SD WebUI 权重语法转换为 NovelAI 官方标准语法
  ///
  /// `(tag:1.2)` -> `1.2::tag::`
  /// `(tag)` -> `{tag}`
  /// `((tag))` -> `{{tag}}`
  /// `[tag]` -> `[tag]`
  static String sdToNaiPrompt(String text) {
    var result = text;

    // 1. (tag:weight) -> weight::tag::
    result = result.replaceAllMapped(
      RegExp(r'\(([^():]+):(-?\d+(?:\.\d+)?)\)'),
      (m) {
        final tag = m.group(1)!.trim().replaceAll('_', ' ');
        final w = double.tryParse(m.group(2)!) ?? 1.0;
        if ((w - 1.0).abs() < 0.01) return tag;
        return '${formatMultiplier(w)}::$tag::';
      },
    );

    // 2. 连续外括号 (tag) -> {tag} (循环处理多层嵌套)
    while (result.contains(RegExp(r'\(([^():]+)\)'))) {
      result = result.replaceAllMapped(
        RegExp(r'\(([^():]+)\)'),
        (m) => '{${m.group(1)!.trim().replaceAll('_', ' ')}}',
      );
    }

    return result;
  }

  /// 格式化与美化提示词：
  /// - 中文逗号 `，` 归一化为 `, `
  /// - 多重逗号合并为单个 `, `
  /// - 清理首尾空格与多余逗号
  /// - 多角色隔离竖线 `|` 原样保留
  /// - 自动执行 SD -> NAI 语法转换
  static String formatAndBeautify(String text) {
    if (text.trim().isEmpty) return '';

    var out = sdToNaiPrompt(text);

    // 中文逗号与分号归一化
    out = out.replaceAll('，', ',');
    out = out.replaceAll('；', ',');
    out = out.replaceAll(';', ',');

    // 逐段重组：普通分隔符归一为 ", "，竖线分隔符保留为 " | "
    final tokens = parsePromptTokens(out);
    if (tokens.isEmpty) return '';

    final buf = StringBuffer();
    var lastEnd = 0;
    for (final t in tokens) {
      final gap = out.substring(lastEnd, t.segStart);
      if (buf.isEmpty) {
        // 首个词条：保留前导分隔符中可能存在的竖线 (多角色布局以 | 开头时)
        if (gap.contains('|')) buf.write('| ');
      } else {
        buf.write(gap.contains('|') ? ' | ' : ', ');
      }
      buf.write(out.substring(t.segStart, t.segEnd).trim());
      lastEnd = t.segEnd;
    }

    // 尾部残余分隔符：仅保留其中的竖线
    final tail = out.substring(lastEnd);
    if (tail.contains('|')) buf.write(' |');

    return buf.toString().trim();
  }
}
