import 'package:dart_sentencepiece_tokenizer/dart_sentencepiece_tokenizer.dart';
import 'package:flutter/services.dart';

import '../isolated_compute.dart';
import 'prompt_token_encoder.dart';

SentencePieceTokenizer _parseT5Tokenizer(IsolateBytes payload) {
  return SentencePieceTokenizer.fromBytes(
    payload.materialize(),
    config: const SentencePieceConfig(),
  );
}

/// NovelAI V4 / V4.5 使用的 T5 分词器 (SentencePiece)。
///
/// 词表资产移植自 Aaalice_NAI_Launcher 参考实现 (官方 t5_spiece.model)，
/// 依赖包 dart_sentencepiece_tokenizer 纯 Dart 实现，桌面端可用。
class T5PromptTokenEncoder implements PromptTokenEncoder {
  T5PromptTokenEncoder._(this._tokenizer);

  /// 按资产路径缓存实例，词表解析只做一次。
  static final Map<String, Future<T5PromptTokenEncoder>> _instances =
      <String, Future<T5PromptTokenEncoder>>{};

  final SentencePieceTokenizer _tokenizer;

  static Future<T5PromptTokenEncoder> load({required String assetPath}) {
    final existing = _instances[assetPath];
    if (existing != null) return existing;
    late final Future<T5PromptTokenEncoder> future;
    future = _loadFromAsset(assetPath).catchError((Object e, StackTrace st) {
      if (identical(_instances[assetPath], future)) {
        _instances.remove(assetPath);
      }
      Error.throwWithStackTrace(e, st);
    });
    _instances[assetPath] = future;
    return future;
  }

  /// 用原始词表字节构造 (测试与离线校验使用，绕过 rootBundle)。
  static T5PromptTokenEncoder fromBytes(List<int> bytes) {
    final tokenizer = SentencePieceTokenizer.fromBytes(
      bytes,
      config: const SentencePieceConfig(),
    );
    return T5PromptTokenEncoder._(tokenizer);
  }

  static Future<T5PromptTokenEncoder> _loadFromAsset(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    final bytes = data.buffer.asUint8List(
      data.offsetInBytes,
      data.lengthInBytes,
    );
    final tokenizer = await runIsolated(
      _parseT5Tokenizer,
      IsolateBytes(bytes),
    );
    return T5PromptTokenEncoder._(tokenizer);
  }

  @override
  int countTokens(String text) {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return 0;
    }

    final encoding = _tokenizer.encode(normalized, addSpecialTokens: false);
    return encoding.ids.length;
  }
}
