import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:unorm_dart/unorm_dart.dart' as unorm;

import '../isolated_compute.dart';
import 'prompt_token_encoder.dart';

class _ParsedQwenData {
  const _ParsedQwenData({
    required this.splitRegex,
    required this.ranks,
    required this.specialTokens,
    required this.normalizeNfc,
  });

  final String splitRegex;
  final Map<String, int> ranks;
  final List<String> specialTokens;
  final bool normalizeNfc;
}

_ParsedQwenData _parseQwenBytes(IsolateBytes payload) {
  final text = utf8.decode(GZipCodec().decode(payload.materialize()));
  return _parseQwenText(text);
}

_ParsedQwenData _parseQwenText(String assetText) {
  final lines = const LineSplitter().convert(assetText);
  if (lines.isEmpty) {
    throw StateError('Qwen tokenizer asset is empty');
  }

  final header = jsonDecode(lines.first) as Map<String, dynamic>;
  final ranks = <String, int>{};
  for (var index = 1; index < lines.length; index++) {
    final line = lines[index];
    if (line.isEmpty) continue;
    // 键直接用整行 "left right"，查询时拼接同样的格式，省一次拆分。
    ranks[line] = ranks.length;
  }

  final specialTokens =
      (header['specialTokens'] as List<dynamic>? ?? const [])
          .cast<String>()
          .toList()
        // 长的优先，避免前缀较短的特殊标记先匹配。
        ..sort((a, b) => b.length.compareTo(a.length));

  return _ParsedQwenData(
    splitRegex: header['splitRegex'] as String,
    ranks: ranks,
    specialTokens: specialTokens,
    normalizeNfc: header['normalization'] == 'NFC',
  );
}

/// NovelAI V5 使用的 Qwen 3.5 分词器 (byte-level BPE)。
///
/// 资产移植自 Aaalice_NAI_Launcher 参考实现 (由官方词表生成)：
/// gzip 文本，第一行是 JSON 头，其余每行一条 merge。只保留 merge 顺序，
/// 因为计数不需要 token id。
///
/// 分词过程与官方前端一致：NFC 归一化 → 按 splitRegex 切段 →
/// 每段转 UTF-8 字节并映射成可见字符 → 在字节字符上做 BPE 合并。
class QwenPromptTokenEncoder implements PromptTokenEncoder {
  QwenPromptTokenEncoder._({
    required this._splitPattern,
    required this._ranks,
    required this._specialPattern,
    required this._normalizeNfc,
  });

  final RegExp _splitPattern;
  final Map<String, int> _ranks;
  final RegExp? _specialPattern;
  final bool _normalizeNfc;

  static const int _maxPieceCacheEntries = 4096;
  final Map<String, int> _pieceCountCache = <String, int>{};

  static final List<String> _byteEncoder = _buildByteEncoder();

  /// 按资产路径缓存实例，词表解析只做一次。
  static Future<QwenPromptTokenEncoder> load({required String assetPath}) {
    final existing = _instances[assetPath];
    if (existing != null) return existing;
    late final Future<QwenPromptTokenEncoder> future;
    future = _loadFromAsset(assetPath).catchError((Object e, StackTrace st) {
      if (identical(_instances[assetPath], future)) {
        _instances.remove(assetPath);
      }
      Error.throwWithStackTrace(e, st);
    });
    _instances[assetPath] = future;
    return future;
  }

  static final Map<String, Future<QwenPromptTokenEncoder>> _instances =
      <String, Future<QwenPromptTokenEncoder>>{};

  static Future<QwenPromptTokenEncoder> _loadFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final compressed = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final parsed = await runIsolated(_parseQwenBytes, IsolateBytes(compressed));
    return _fromParsed(parsed);
  }

  /// 用已经解压的资产文本构造 (测试与离线校验使用)。
  static QwenPromptTokenEncoder fromAssetText(String assetText) =>
      _parse(assetText);

  /// 用 gzip 压缩的资产字节构造 (测试与离线校验使用，绕过 rootBundle)。
  static QwenPromptTokenEncoder fromBytes(List<int> compressedBytes) {
    final text = utf8.decode(GZipCodec().decode(compressedBytes));
    return _parse(text);
  }

  static QwenPromptTokenEncoder _parse(String assetText) =>
      _fromParsed(_parseQwenText(assetText));

  static QwenPromptTokenEncoder _fromParsed(_ParsedQwenData data) {
    return QwenPromptTokenEncoder._(
      splitPattern: RegExp(data.splitRegex, unicode: true),
      ranks: data.ranks,
      specialPattern: data.specialTokens.isEmpty
          ? null
          : RegExp(data.specialTokens.map(RegExp.escape).join('|')),
      normalizeNfc: data.normalizeNfc,
    );
  }

  @override
  int countTokens(String text) {
    if (text.isEmpty) return 0;

    final normalized = _normalizeNfc ? unorm.nfc(text) : text;
    var total = 0;
    for (final segment in _splitOnSpecialTokens(normalized)) {
      if (segment.isSpecial) {
        total += 1;
        continue;
      }
      // splitRegex 带捕获组，必须取整段匹配而不是组内容。
      for (final match in _splitPattern.allMatches(segment.text)) {
        final piece = match.group(0);
        if (piece == null || piece.isEmpty) continue;
        total += _countPiece(piece);
      }
    }
    return total;
  }

  int _countPiece(String piece) {
    final cached = _pieceCountCache.remove(piece);
    if (cached != null) {
      _pieceCountCache[piece] = cached;
      return cached;
    }

    final count = _mergeCount(_toByteLevel(piece));
    if (_pieceCountCache.length >= _maxPieceCacheEntries) {
      _pieceCountCache.remove(_pieceCountCache.keys.first);
    }
    _pieceCountCache[piece] = count;
    return count;
  }

  String _toByteLevel(String piece) {
    final buffer = StringBuffer();
    for (final byte in utf8.encode(piece)) {
      buffer.write(_byteEncoder[byte]);
    }
    return buffer.toString();
  }

  int _mergeCount(String word) {
    var parts = word.split('');
    while (parts.length > 1) {
      var bestRank = -1;
      var bestIndex = -1;
      for (var index = 0; index < parts.length - 1; index++) {
        final rank = _ranks['${parts[index]} ${parts[index + 1]}'];
        if (rank != null && (bestIndex < 0 || rank < bestRank)) {
          bestRank = rank;
          bestIndex = index;
        }
      }
      if (bestIndex < 0) break;

      final first = parts[bestIndex];
      final second = parts[bestIndex + 1];
      final merged = <String>[];
      var index = 0;
      while (index < parts.length) {
        if (index < parts.length - 1 &&
            parts[index] == first &&
            parts[index + 1] == second) {
          merged.add(first + second);
          index += 2;
        } else {
          merged.add(parts[index]);
          index += 1;
        }
      }
      parts = merged;
    }
    return parts.length;
  }

  Iterable<_QwenTextSegment> _splitOnSpecialTokens(String text) sync* {
    final pattern = _specialPattern;
    if (pattern == null) {
      yield _QwenTextSegment(text, false);
      return;
    }

    var cursor = 0;
    for (final match in pattern.allMatches(text)) {
      if (match.start > cursor) {
        yield _QwenTextSegment(text.substring(cursor, match.start), false);
      }
      yield _QwenTextSegment(match.group(0)!, true);
      cursor = match.end;
    }
    if (cursor < text.length) {
      yield _QwenTextSegment(text.substring(cursor), false);
    }
  }

  /// GPT-2 系列的字节到可见字符映射：先占用本身可打印的字节，
  /// 其余（空格、控制字符等）顺序映射到 U+0100 之后。
  static List<String> _buildByteEncoder() {
    final table = List<String?>.filled(256, null);
    void markDirect(int from, int to) {
      for (var byte = from; byte <= to; byte++) {
        table[byte] = String.fromCharCode(byte);
      }
    }

    markDirect(0x21, 0x7E);
    markDirect(0xA1, 0xAC);
    markDirect(0xAE, 0xFF);

    var next = 256;
    for (var byte = 0; byte < 256; byte++) {
      if (table[byte] == null) {
        table[byte] = String.fromCharCode(next);
        next++;
      }
    }
    return table.cast<String>();
  }
}

class _QwenTextSegment {
  const _QwenTextSegment(this.text, this.isSpecial);

  final String text;
  final bool isSpecial;
}
