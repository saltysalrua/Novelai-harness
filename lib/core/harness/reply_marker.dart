/// 回复编号标记 (`[回复 #N]`) 的协议单一事实源。
///
/// 请求侧由 [AgentHarness] 临时注入：每条助手回复发给模型前前缀一层稳定
/// 编号，便于 `context_memory` 按编号读取或释放旧回复。
/// 正文侧一律剥离：模型回显回来的标记既不该出现在 UI 上，也不该入库累积
/// (只剥「正文开头」会漏掉段落之间/行尾的回显，下一轮请求再叠一层 →
/// 历史里越滚越多)，因此这里提供全量剥离与流式增量剥离两套入口。
library;

/// 去掉正文中任意位置被模型回显的 `[回复 #N]` 标记与标记残渣
/// (标记位于正文最前时，剥离后残留的首部空白一并清掉)。
abstract final class ReplyMarker {
  /// 完整标记：必须带右括号。
  ///
  /// 流式期间只有这种形态能当即剥离：若把「[回复 #7」当成完整标记先剥掉，
  /// 晚一两个 token 才到的「]」就会变成孤立残渣漏到 UI 与正文里。
  static final RegExp closed = RegExp(
    r'(?:\*\*)?[ \t\u3000]*[\[［]?[ \t\u3000]*回复[ \t\u3000]*[#＃][ \t\u3000]*'
    r'[0-9０-９]+[ \t\u3000]*[\]］][ \t\u3000]*(?:\*\*)?',
  );

  /// 宽松标记 token：右括号可缺 (仅用于整段文本 / 流结束时的收尾剥离)。
  ///
  /// 只认「回复 + #编号」这一保留记号，容忍回显变体
  /// (全角括号 / Markdown 加粗 / 缺半个括号 / 空格差异)。
  /// 例: `[回复 #7]` / `[回复#7]` / `**[回复 #7]**` / `回复 #7` / `[回复 #7`
  static final RegExp token = RegExp(
    r'(?:\*\*)?[ \t\u3000]*[\[［]?[ \t\u3000]*回复[ \t\u3000]*[#＃][ \t\u3000]*'
    r'[0-9０-９]+[ \t\u3000]*[\]］]?[ \t\u3000]*(?:\*\*)?',
  );

  /// 标记残渣：回显标记被网络分块切碎时可能只剩一个孤立右括号
  /// (例: 「]\n正文」「正文]」「]** 正文」)。
  static final RegExp _leadingDebris = RegExp(
    r'^(?:\*\*)?[ \t\u3000]*[\]］][ \t\u3000]*(?:\*\*)?[ \t\u3000]*(?:\r?\n)?',
  );

  static final RegExp _trailingDebris = RegExp(
    r'(?:\r?\n)?[ \t\u3000]*(?:\*\*)?[ \t\u3000]*[\]］][ \t\u3000]*(?:\*\*)?$',
  );

  /// 全量剥离标记与残渣
  static String strip(String text) {
    if (text.isEmpty) return text;
    final first = token.firstMatch(text);
    if (first == null &&
        !_leadingDebris.hasMatch(text) &&
        !_hasUnmatchedCloseBracket(text)) {
      return text;
    }
    var cleaned = text.replaceAll(token, '');
    // 残渣清理：首部孤立右括号直接去掉；尾部只在括号数失衡时才去除，
    // 保证正常成对括号 (参考 [3]、Markdown 链接) 不受影响
    cleaned = cleaned.replaceFirst(_leadingDebris, '');
    if (_hasUnmatchedCloseBracket(cleaned)) {
      cleaned = cleaned.replaceFirst(_trailingDebris, '');
    }
    cleaned = cleaned
        .replaceAll(RegExp(r'^[ \t\u3000]+$', multiLine: true), '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');
    // 标记就位于正文最前时，剥离后残留的首部空白一并清掉
    return first != null && first.start == 0
        ? cleaned.replaceFirst(RegExp(r'^\s+'), '')
        : cleaned;
  }

  /// 右括号是否多于左括号 (半角与全角一起统计)
  static bool _hasUnmatchedCloseBracket(String text) {
    final (open, close) = _bracketCounts(text);
    return close > open;
  }

  static (int, int) _bracketCounts(String text) {
    var open = 0;
    var close = 0;
    for (final unit in text.codeUnits) {
      if (unit == 0x5B || unit == 0xFF3B) {
        open++;
      } else if (unit == 0x5D || unit == 0xFF3D) {
        close++;
      }
    }
    return (open, close);
  }
}

/// 流式正文/思考的回复标记过滤器。
///
/// 模型偶尔会回显系统注入的 `[回复 #N]` 标记。若直接透传增量：
/// UI 会先闪出标记再被剥离，而且标记可能被网络分块切断，
/// 事后一次性剥离也治不了「非行首」的标记。
///
/// 两条规则：
/// 1. 完整标记 (带右括号) 随时可剥；
/// 2. 「可能是半个标记」的尾巴必须扣住 —— 它可能马上被下一块补完，
///    而尾巴之前的部分已不可能再长成标记，可安全地按宽松形态剥离。
/// 流结束时把残缺尾巴丢弃。
class ReplyMarkerStreamFilter {
  String _pending = '';
  bool _started = false;

  /// 本条消息是否剥过标记 (用于清掉标记之后残留的首部空白)
  bool _stripped = false;

  /// 已输出文本的括号计数 (流结束时判定尾部孤立右括号是否为残渣)
  int _openBrackets = 0;
  int _closeBrackets = 0;

  /// 可能是「半个标记」的形状 (全部字符都是标记自身会用到的字符)
  static final RegExp _partial = RegExp(
    r'^\**[ \t\u3000]*[\[［]?[ \t\u3000]*(?:回(?:复)?)?[ \t\u3000]*'
    r'[#＃]?[ \t\u3000]*[0-9０-９]*[ \t\u3000]*[\]］]?[ \t\u3000]*\**$',
  );

  /// 标记签名字符：尾部只要含这些字符才可能是被截断的标记
  static final RegExp _markerSignature = RegExp(r'[回\[［#＃]');

  /// 首部无意义空白 (标记剥除后残留在正文最前的部分)
  static final RegExp _leadingBlank = RegExp(r'^[ \t\u3000\r\n]+');

  /// 最长保留的尾部长度 (标记本身最多 20 余字符，32 足够)
  static const int _maxHold = 32;

  /// 追加一个增量，返回可以安全展示/入库的正文片段 (可能为空)
  String add(String delta) {
    if (delta.isEmpty) return '';
    _pending += delta;
    // 1) 完整标记 (带右括号) 无论落在哪里都能立刻剥掉
    _pending = _stripClosed(_pending);
    // 2) 尾部可能是「半个标记」，先切出来等下一块；
    //    它之前的部分已不可能再长成标记，残缺形态也可安全剥离
    final hold = _holdbackLength(_pending);
    final cut = _pending.length - hold;
    var head = _stripLoose(_pending.substring(0, cut));
    _pending = _pending.substring(cut);
    if (!_started && _stripped) {
      head = head.replaceFirst(_leadingBlank, '');
    }
    if (head.isNotEmpty) {
      _started = true;
      _countBrackets(head);
    }
    return head;
  }

  /// 流结束：冲刷残留。
  /// - 被截断的半个标记直接丢弃；
  /// - 尾部孤立右括号残渣仅在全文括号失衡时丢弃 (正常成对的 `[3]` 必须保留)；
  /// - `**` / 纯数字这类尾字是无害正文，原样归还。
  String flush() {
    var safe = _stripLoose(_pending);
    _pending = '';
    if (!_started && _stripped) safe = safe.replaceFirst(_leadingBlank, '');
    final hold = _holdbackLength(safe);
    if (hold > 0) {
      final tail = safe.substring(safe.length - hold);
      if (_markerSignature.hasMatch(tail) ||
          _isResidueTail(tail, safe, _openBrackets, _closeBrackets)) {
        safe = safe.substring(0, safe.length - hold);
      }
    }
    _countBrackets(safe);
    return safe;
  }

  /// 尾部残渣判定：`safe` 自身的括号计数加上已输出部分的计数后失衡
  static bool _isResidueTail(
    String tail,
    String safe,
    int emittedOpen,
    int emittedClose,
  ) {
    if (!ReplyMarker._trailingDebris.hasMatch(tail)) return false;
    final (open, close) = ReplyMarker._bracketCounts(safe);
    return emittedClose + close > emittedOpen + open;
  }

  void _countBrackets(String text) {
    final (open, close) = ReplyMarker._bracketCounts(text);
    _openBrackets += open;
    _closeBrackets += close;
  }

  String _stripClosed(String text) {
    final stripped = text.replaceAll(ReplyMarker.closed, '');
    if (stripped.length != text.length) _stripped = true;
    return stripped;
  }

  String _stripLoose(String text) {
    final stripped = text.replaceAll(ReplyMarker.token, '');
    if (stripped.length != text.length) _stripped = true;
    return stripped;
  }

  /// 取最长的「可能是标记一部分」的尾长 (取最大，确保整个标记都被扣住)
  static int _holdbackLength(String text) {
    final max = text.length < _maxHold ? text.length : _maxHold;
    var hold = 0;
    for (var k = 1; k <= max; k++) {
      if (_partial.hasMatch(text.substring(text.length - k))) hold = k;
    }
    return hold;
  }
}
