import '../models/prompt_library_models.dart';

/// 正在输入中的 `@` 角色提及片段
class ActiveCharacterMention {
  final int atIndex;
  final int cursorOffset;
  final String query;

  const ActiveCharacterMention({
    required this.atIndex,
    required this.cursorOffset,
    required this.query,
  });
}

/// 将角色标题格式化为标准提及标记 `@[标题]`（规避中括号冲突）
String formatCharacterMention(String title) {
  final safe = title.trim().replaceAll('[', '(').replaceAll(']', ')');
  return '@[$safe]';
}

String _normalizedMentionKey(String title) =>
    title.trim().replaceAll('[', '(').replaceAll(']', ')').toLowerCase();

/// 从光标位置提取正在输入中的 `@查询`（无命中或光标前在邮箱/空格后则返回 null）
ActiveCharacterMention? extractActiveCharacterMention(
  String text,
  int cursor,
) {
  if (cursor < 1 || cursor > text.length) return null;

  var atIndex = -1;
  for (var i = cursor - 1; i >= 0; i--) {
    final ch = text[i];
    if (ch == '@') {
      atIndex = i;
      break;
    }
    if (ch == ' ' ||
        ch == '\n' ||
        ch == '\t' ||
        ch == '\r' ||
        ch == '[' ||
        ch == ']' ||
        (ch.codeUnitAt(0) >= 0xE000 && ch.codeUnitAt(0) <= 0xF8FF)) {
      return null;
    }
  }

  if (atIndex == -1) return null;
  if (atIndex > 0) {
    final prev = text[atIndex - 1];
    if (RegExp(r'[A-Za-z0-9_.]').hasMatch(prev)) {
      return null;
    }
  }

  return ActiveCharacterMention(
    atIndex: atIndex,
    cursorOffset: cursor,
    query: text.substring(atIndex + 1, cursor),
  );
}

/// 按关键词过滤并排序词库中的角色条目（供输入框 `@` 浮层使用）
List<PromptComboEntry> matchCharacterMentionSuggestions(
  String query,
  List<PromptComboEntry> entries, {
  int limit = 12,
}) {
  final chars = entries.where((e) => e.isCharacter).toList(growable: false);
  if (chars.isEmpty) return const [];

  final q = query.trim().toLowerCase();
  if (q.isEmpty) {
    final sorted = List<PromptComboEntry>.from(chars)
      ..sort((a, b) {
        if (a.isFavorite != b.isFavorite) {
          return a.isFavorite ? -1 : 1;
        }
        return 0;
      });
    return sorted.length > limit ? sorted.sublist(0, limit) : sorted;
  }

  final scored = <(PromptComboEntry entry, int score, int order)>[];
  for (var i = 0; i < chars.length; i++) {
    final e = chars[i];
    final titleLower = e.title.toLowerCase();
    final promptLower = e.prompt.toLowerCase();
    var score = 0;
    if (titleLower == q) {
      score = 1000;
    } else if (titleLower.startsWith(q)) {
      score = 800;
    } else if (e.tags.any((t) => t.toLowerCase() == q)) {
      score = 700;
    } else if (e.tags.any((t) => t.toLowerCase().startsWith(q))) {
      score = 600;
    } else if (titleLower.contains(q)) {
      score = 500;
    } else if (e.tags.any((t) => t.toLowerCase().contains(q))) {
      score = 400;
    } else if (promptLower.contains(q)) {
      score = 200;
    }

    if (score > 0) {
      scored.add((e, score, i));
    }
  }

  scored.sort((a, b) {
    final scoreCmp = b.$2.compareTo(a.$2);
    if (scoreCmp != 0) return scoreCmp;
    if (a.$1.isFavorite != b.$1.isFavorite) {
      return a.$1.isFavorite ? -1 : 1;
    }
    return a.$3.compareTo(b.$3);
  });

  final result = scored.map((item) => item.$1).toList(growable: false);
  return result.length > limit ? result.sublist(0, limit) : result;
}

PromptComboEntry? _findCharacterByMentionToken(
  String token,
  List<PromptComboEntry> characters,
) {
  final trimmed = token.trim();
  if (trimmed.isEmpty) return null;

  for (final c in characters) {
    if (c.title.trim() == trimmed) return c;
  }
  final lower = trimmed.toLowerCase();
  for (final c in characters) {
    if (c.title.trim().toLowerCase() == lower) return c;
  }
  final norm = _normalizedMentionKey(trimmed);
  for (final c in characters) {
    if (_normalizedMentionKey(c.title) == norm) return c;
  }
  return null;
}

/// 匹配显式 `@[标题]` 角色提及的正则表达式
final RegExp bracketMentionRegex = RegExp(r'@\[([^\[\]\r\n]+)\]');
final RegExp _bareMentionRegex = RegExp(
  r'(?<![A-Za-z0-9_.])@([^\s@,\[\]，。！？；：]+)',
);

/// 根据提及标题在词库条目中查找对应角色（精确 -> 忽略大小写 -> 归一化匹配）
PromptComboEntry? findCharacterByMentionToken(
  String token,
  List<PromptComboEntry> entries,
) {
  final characters = entries.where((e) => e.isCharacter).toList(growable: false);
  if (characters.isEmpty) return null;
  return _findCharacterByMentionToken(token, characters);
}

/// 提取消息中已显式 `@[标题]` 引用的词库角色列表（按出现顺序去重）
List<PromptComboEntry> extractLinkedCharacters(
  String text,
  List<PromptComboEntry> entries,
) {
  if (text.isEmpty || entries.isEmpty) return const [];
  final characters = entries.where((e) => e.isCharacter).toList(growable: false);
  if (characters.isEmpty) return const [];

  final result = <PromptComboEntry>[];
  final seenIds = <String>{};
  for (final match in bracketMentionRegex.allMatches(text)) {
    final token = match.group(1);
    if (token == null) continue;
    final matched = _findCharacterByMentionToken(token, characters);
    if (matched != null && seenIds.add(matched.id)) {
      result.add(matched);
    }
  }
  return result;
}

/// 从输入文本中移除指定角色的 `@[标题]` 引用并清理多余空白
String removeCharacterMention(String text, PromptComboEntry entry) {
  final targetKey = _normalizedMentionKey(entry.title);
  var updated = text.replaceAllMapped(bracketMentionRegex, (match) {
    final token = match.group(1) ?? '';
    return _normalizedMentionKey(token) == targetKey ? '' : match.group(0)!;
  });
  updated = updated
      .replaceAll(RegExp(r' {2,}'), ' ')
      .replaceAll(RegExp(r'^ +| +$', multiLine: true), '')
      .trim();
  return updated;
}

Iterable<String> _candidateAliasesForTitle(String title) sync* {
  final trimmed = title.trim();
  if (trimmed.isEmpty) return;
  yield trimmed;

  final parenIdx = trimmed.indexOf(RegExp(r'[（(]'));
  if (parenIdx > 0) {
    final mainName = trimmed.substring(0, parenIdx).trim();
    if (mainName.isNotEmpty) yield mainName;

    final closeIdx = trimmed.indexOf(RegExp(r'[）)]'), parenIdx + 1);
    if (closeIdx > parenIdx + 1) {
      final inner = trimmed.substring(parenIdx + 1, closeIdx).trim();
      if (inner.isNotEmpty) yield inner;
    }
  }
}

bool _isAsciiOnly(String s) {
  for (final unit in s.codeUnits) {
    if (unit >= 128) return false;
  }
  return true;
}

bool _matchesImplicitAlias(String lowerText, String alias) {
  final trimmed = alias.trim();
  if (trimmed.isEmpty) return false;
  final ascii = _isAsciiOnly(trimmed);
  if (ascii && trimmed.length < 3) return false;
  if (!ascii && trimmed.length < 2) return false;

  final lowerAlias = trimmed.toLowerCase();
  if (!ascii) {
    return lowerText.contains(lowerAlias);
  }
  final escaped = RegExp.escape(lowerAlias);
  return RegExp(
    '(?<![a-z0-9_])$escaped(?![a-z0-9_])',
    caseSensitive: false,
  ).hasMatch(lowerText);
}

/// 自动解析用户消息中提及的词库角色（显式 `@[标题]` / 裸 `@标题` + 隐式名称匹配），
/// 生成注入 LLM 请求上下文的 `<library_characters>` 块。未命中时返回 null。
String? resolveLibraryCharactersForMessage(
  String text,
  List<PromptComboEntry> entries, {
  String Function(String)? sanitizeText,
}) {
  final trimmedText = text.trim();
  if (trimmedText.isEmpty || entries.isEmpty) return null;

  final characters = entries.where((e) => e.isCharacter).toList(growable: false);
  if (characters.isEmpty) return null;

  final matched = <({PromptComboEntry entry, String via})>[];
  final seenIds = <String>{};

  // 1. 显式 @[标题] 引用
  for (final match in bracketMentionRegex.allMatches(trimmedText)) {
    final token = match.group(1);
    if (token == null) continue;
    final found = _findCharacterByMentionToken(token, characters);
    if (found != null && seenIds.add(found.id)) {
      matched.add((entry: found, via: '@引用'));
    }
  }

  // 2. 裸 @标题 引用
  for (final match in _bareMentionRegex.allMatches(trimmedText)) {
    final token = match.group(1);
    if (token == null) continue;
    final found = _findCharacterByMentionToken(token, characters);
    if (found != null && seenIds.add(found.id)) {
      matched.add((entry: found, via: '@引用'));
    }
  }

  // 3. 隐式名称匹配（未打 @ 但正文直接提及角色名或括号别名，最多 5 条）
  final aliasPairs = <({String alias, PromptComboEntry entry})>[];
  for (final c in characters) {
    if (seenIds.contains(c.id)) continue;
    for (final alias in _candidateAliasesForTitle(c.title)) {
      aliasPairs.add((alias: alias, entry: c));
    }
  }
  aliasPairs.sort((a, b) => b.alias.length.compareTo(a.alias.length));

  final lowerText = trimmedText.toLowerCase();
  var implicitCount = 0;
  for (final pair in aliasPairs) {
    if (implicitCount >= 5) break;
    if (seenIds.contains(pair.entry.id)) continue;
    if (_matchesImplicitAlias(lowerText, pair.alias)) {
      seenIds.add(pair.entry.id);
      matched.add((entry: pair.entry, via: '名称自动关联'));
      implicitCount++;
    }
  }

  if (matched.isEmpty) return null;

  final sanitize = sanitizeText ?? (s) => s;
  final buffer = StringBuffer()
    ..writeln('<library_characters>')
    ..writeln(
      '已自动关联本地词库中的以下角色条目，请直接采用其提示词设定（多角色构图优先写入角色卡，单角色可按需写入主提示词或角色卡），无需让用户提醒去查词库：',
    );

  for (final item in matched) {
    final e = item.entry;
    final positive = sanitize(e.prompt).trim();
    final negative = sanitize(e.negativePrompt).trim();
    buffer.writeln('- 标题: ${e.title} [id: ${e.id}] [方式: ${item.via}]');
    buffer.writeln('  正向提示词: $positive');
    if (negative.isNotEmpty) {
      buffer.writeln('  负面提示词: $negative');
    }
    if (e.tags.isNotEmpty) {
      buffer.writeln('  标签: ${e.tags.join(', ')}');
    }
  }

  buffer.write('</library_characters>');
  return buffer.toString();
}
