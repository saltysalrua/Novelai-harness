import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/nai_catalog.dart';
import '../models/nai_generation_params.dart';
import '../models/nai_prompt_presets.dart';
import 'tokenizers/qwen_prompt_token_encoder.dart';
import 'tokenizers/t5_prompt_token_encoder.dart';

export 'tokenizers/prompt_token_encoder.dart';

/// 提示词 token 预算档位：
/// - [normal]：未超过任何阈值；
/// - [featureLimited]：超过黄档 (V5 文字渲染支持上限，文字渲染功能受限)；
/// - [overLimit]：超过模型 token 硬上限 (超出部分被截断)。
enum PromptTokenBudgetLevel { normal, featureLimited, overLimit }

/// token 计数明细条目种类 (UI 层负责本地化文案)
enum PromptTokenBreakdownKind {
  prompt,
  fixedAffixes,
  qualityTags,
  characters,
  negativePrompt,
  ucPreset,
  characterNegatives,
}

class PromptTokenBreakdownEntry {
  const PromptTokenBreakdownEntry({required this.kind, required this.tokens});

  final PromptTokenBreakdownKind kind;
  final int tokens;
}

/// 一次计数的结果：用量 + 硬上限 + 黄档 (可空) + 明细。
class PromptTokenUsage {
  const PromptTokenUsage({
    required this.used,
    required this.hardLimit,
    this.softLimit,
    this.estimated = false,
    this.breakdown = const [],
  });

  final int used;
  final int hardLimit;

  /// 黄档阈值 (仅 V5 有：官方文字渲染 token 支持上限)，null 表示无黄档。
  final int? softLimit;

  /// 是否为启发式估算 (V3 CLIP 无词表资产 / 分词器尚未加载完成)。
  final bool estimated;

  final List<PromptTokenBreakdownEntry> breakdown;

  bool get isOverLimit => used > hardLimit;

  PromptTokenBudgetLevel get level {
    if (used > hardLimit) return PromptTokenBudgetLevel.overLimit;
    final soft = softLimit;
    if (soft != null && used > soft) {
      return PromptTokenBudgetLevel.featureLimited;
    }
    return PromptTokenBudgetLevel.normal;
  }
}

/// 提示词 token 计数服务 (移植自 Aaalice_NAI_Launcher 的
/// PromptTokenCounterService，计数口径与 NovelAI 官网计数条一致)。
///
/// - V4 / V4.5：T5 SentencePiece 真分词；官网计数条把 encode 附带的 EOS
///   算进去，因此对非零结果 +1 校准；
/// - V5：Qwen 3.5 byte-level BPE 真分词；BPE encode 不带 EOS，不校准；
/// - V3 及更早：CLIP，无词表资产，回退启发式估算 ([estimated] = true)；
/// - 正向计数 = 生效正向词 (固定词缀 + 核心词 + 质量词 + 透明背景 +
///   V5 Auto Text) + 全部启用角色的正向词；
/// - 负向计数 = 生效负面词 (UC 预设 + nsfw 前置 + 用户词) + 角色负面词。
class PromptTokenCounterService {
  PromptTokenCounterService._();

  static final PromptTokenCounterService instance =
      PromptTokenCounterService._();

  static const String t5AssetPath = 'assets/tokenizers/t5_spiece.model';
  static const String qwenAssetPath = 'assets/tokenizers/qwen35_bpe.txt.gz';

  T5PromptTokenEncoder? _t5;
  QwenPromptTokenEncoder? _qwen;
  Future<void>? _t5Loading;
  Future<void>? _qwenLoading;

  /// 分词器是否已就绪 (CLIP 恒就绪：走启发式估算)。
  bool isReady(NaiModel model) => switch (model.tokenizerKind) {
    NaiTokenizerKind.clip => true,
    NaiTokenizerKind.t5 => _t5 != null,
    NaiTokenizerKind.qwen35 => _qwen != null,
  };

  /// 预加载模型所需的分词器 (幂等；按需在应用启动与切模型时调用)。
  Future<void> precache(NaiModel model) {
    return switch (model.tokenizerKind) {
      NaiTokenizerKind.clip => Future<void>.value(),
      NaiTokenizerKind.t5 => _t5Loading ??= T5PromptTokenEncoder.load(
        assetPath: t5AssetPath,
      ).then((encoder) => _t5 = encoder),
      NaiTokenizerKind.qwen35 => _qwenLoading ??= QwenPromptTokenEncoder.load(
        assetPath: qwenAssetPath,
      ).then((encoder) => _qwen = encoder),
    };
  }

  /// 测试注入已构造的分词器 (绕过 rootBundle 资产加载)。
  @visibleForTesting
  void debugInstallEncoders({
    T5PromptTokenEncoder? t5,
    QwenPromptTokenEncoder? qwen,
  }) {
    if (t5 != null) {
      _t5 = t5;
      _t5Loading = Future<void>.value();
    }
    if (qwen != null) {
      _qwen = qwen;
      _qwenLoading = Future<void>.value();
    }
  }

  /// 按 NovelAI CLIP 分词规则粗略估算提示词 Token 数 (V3 兜底)。
  static int estimatePromptTokens(String text, {int limit = 225}) {
    if (text.trim().isEmpty) return 0;
    final parts = text.split(RegExp(r'[,，\s\n]+')).where((s) => s.isNotEmpty);
    return (parts.length * 1.35).round().clamp(0, limit);
  }

  /// 正向提示词计数 (主提示词 + 全部启用角色)。
  PromptTokenUsage countPositive(NaiGenerationParams params) {
    final model = params.model;
    final characters = params.enabledCharacterPrompts;
    final mainText = params.effectivePrompt;

    final texts = <String>[
      if (mainText.trim().isNotEmpty) mainText,
      for (final character in characters) character.prompt,
    ];
    final used = _countTexts(model, texts);

    // 明细：固定词缀 / 质量词 (含透明背景) / 角色，基准差值折入提示词条目。
    final fixedAffixes = <String>[
      if (params.applyFixedPrompts) ...[
        if (params.prefixPrompt?.trim().isNotEmpty ?? false)
          params.prefixPrompt!.trim(),
        if (params.suffixPrompt?.trim().isNotEmpty ?? false)
          params.suffixPrompt!.trim(),
      ],
    ];
    final qualityParts = <String>[
      if (params.qualityToggle)
        NovelAiQualityTagsHelper.getQualityTags(model, params.qualityPreset),
      if (params.transparentBg) 'transparent background',
    ];
    final characterTexts = [for (final c in characters) c.prompt];

    final breakdown = _buildBreakdown(
      model,
      base: PromptTokenBreakdownKind.prompt,
      baseText: params.prompt,
      groups: [
        (
          PromptTokenBreakdownKind.fixedAffixes,
          fixedAffixes.where((t) => t.trim().isNotEmpty),
        ),
        (
          PromptTokenBreakdownKind.qualityTags,
          qualityParts.where((t) => t.trim().isNotEmpty),
        ),
        (
          PromptTokenBreakdownKind.characters,
          characterTexts.where((t) => t.trim().isNotEmpty),
        ),
      ],
      total: used,
    );

    return PromptTokenUsage(
      used: used,
      hardLimit: model.tokenLimit,
      softLimit: model.textRenderTokenLimit,
      estimated: _isEstimated(model),
      breakdown: breakdown,
    );
  }

  /// 负面提示词计数 (生效负面词 + 角色负面)。
  PromptTokenUsage countNegative(NaiGenerationParams params) {
    final model = params.model;
    final characters = params.enabledCharacterPrompts;
    final mainText = params.effectiveNegativePrompt;

    final characterNegatives = [
      for (final c in characters)
        if (c.negativePrompt.trim().isNotEmpty) c.negativePrompt,
    ];
    final texts = <String>[
      if (mainText.trim().isNotEmpty) mainText,
      ...characterNegatives,
    ];
    final used = _countTexts(model, texts);

    // 明细：UC 预设 (含 nsfw 前置时的标记) / 角色负面，差值折入负面词条目。
    final ucText = NovelAiUndesiredContentHelper.getUndesiredContent(
      model,
      params.ucPresetKey,
    );
    final nsfwPrepended =
        params.ucPresetKey != 'None' &&
        !NovelAiPromptText.containsNsfwTag(params.prompt);
    final ucParts = <String>[
      if (nsfwPrepended) 'nsfw',
      if (ucText.trim().isNotEmpty) ucText,
    ];

    final breakdown = _buildBreakdown(
      model,
      base: PromptTokenBreakdownKind.negativePrompt,
      baseText: params.negativePrompt,
      groups: [
        (
          PromptTokenBreakdownKind.ucPreset,
          ucParts.where((t) => t.trim().isNotEmpty),
        ),
        (
          PromptTokenBreakdownKind.characterNegatives,
          characterNegatives.where((t) => t.trim().isNotEmpty),
        ),
      ],
      total: used,
    );

    return PromptTokenUsage(
      used: used,
      hardLimit: model.tokenLimit,
      softLimit: model.textRenderTokenLimit,
      estimated: _isEstimated(model),
      breakdown: breakdown,
    );
  }

  bool _isEstimated(NaiModel model) => switch (model.tokenizerKind) {
    NaiTokenizerKind.clip => true,
    NaiTokenizerKind.t5 => _t5 == null,
    NaiTokenizerKind.qwen35 => _qwen == null,
  };

  /// 汇总一组文本的 token 数 (空文本跳过；T5 对非零总量 +1 EOS 校准)。
  int _countTexts(NaiModel model, Iterable<String> texts) {
    var total = 0;
    for (final text in texts) {
      if (text.trim().isEmpty) continue;
      total += _countSingle(model, text);
    }
    if (total > 0 && model.tokenizerKind == NaiTokenizerKind.t5) {
      total += 1;
    }
    return total;
  }

  int _countSingle(NaiModel model, String text) {
    switch (model.tokenizerKind) {
      case NaiTokenizerKind.t5:
        final encoder = _t5;
        if (encoder == null) {
          return estimatePromptTokens(text, limit: 1 << 30);
        }
        // T5 词表会把 {}/:: 语法字符当未知字符忽略，剥离只为避免干扰
        // 逗号分段，结果与不剥相同 (对齐 Aaalice 实测)。
        return encoder.countTokens(_normalizePromptForCounting(text));
      case NaiTokenizerKind.qwen35:
        final encoder = _qwen;
        if (encoder == null) {
          return estimatePromptTokens(text, limit: 1 << 30);
        }
        // Qwen 会把语法字符与首尾空白真实编码进 token，官网原样计数。
        return encoder.countTokens(text);
      case NaiTokenizerKind.clip:
        return estimatePromptTokens(text, limit: 1 << 30);
    }
  }

  List<PromptTokenBreakdownEntry> _buildBreakdown(
    NaiModel model, {
    required PromptTokenBreakdownKind base,
    required String baseText,
    required List<(PromptTokenBreakdownKind, Iterable<String>)> groups,
    required int total,
  }) {
    final entries = <PromptTokenBreakdownEntry>[];
    var breakdownTotal = 0;

    void add(PromptTokenBreakdownKind kind, Iterable<String> texts) {
      final tokens = _countTexts(model, texts);
      // T5 的 EOS 校准只对总量生效一次，明细里跳过空组避免虚增。
      if (tokens <= 0) return;
      entries.add(PromptTokenBreakdownEntry(kind: kind, tokens: tokens));
      breakdownTotal += tokens;
    }

    add(base, [baseText]);
    for (final (kind, texts) in groups) {
      add(kind, texts);
    }

    // 分段计数与整段计数存在 BPE 跨界差异，差值折入首个条目保证明细分和=总量。
    final adjustment = total - breakdownTotal;
    if (entries.isNotEmpty && adjustment != 0) {
      final first = entries.first;
      entries[0] = PromptTokenBreakdownEntry(
        kind: first.kind,
        tokens: first.tokens + adjustment,
      );
    }
    return entries;
  }

  /// T5 计数前剥离 NAI 权重语法 (移植自 Aaalice NaiPromptParser 语义)：
  /// 按深度 0 的逗号分段，段内剥离 `num::text::`、残留 `::` 与外层 `{}`/`[]`，
  /// 保留首尾空白，避免剥离改变逗号分段结构。
  static String _normalizePromptForCounting(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final normalizedBuffer = StringBuffer();
    final segmentBuffer = StringBuffer();
    var braceDepth = 0;
    var bracketDepth = 0;
    var parenDepth = 0;
    var inPipe = false;

    void flushSegment() {
      if (segmentBuffer.length == 0) {
        return;
      }
      normalizedBuffer.write(
        _stripSegmentWeightSyntax(segmentBuffer.toString()),
      );
      segmentBuffer.clear();
    }

    for (var i = 0; i < trimmed.length; i++) {
      final char = trimmed[i];

      if (char == '{') {
        braceDepth++;
      } else if (char == '}') {
        braceDepth--;
      } else if (char == '[') {
        bracketDepth++;
      } else if (char == ']') {
        bracketDepth--;
      } else if (char == '(') {
        parenDepth++;
      } else if (char == ')') {
        parenDepth--;
      }

      if (char == '|' && i + 1 < trimmed.length && trimmed[i + 1] == '|') {
        inPipe = !inPipe;
        segmentBuffer.write('||');
        i++;
        continue;
      }

      if (char == ',' &&
          braceDepth == 0 &&
          bracketDepth == 0 &&
          parenDepth == 0 &&
          !inPipe) {
        flushSegment();
        normalizedBuffer.write(',');
        continue;
      }

      segmentBuffer.write(char);
    }

    flushSegment();

    final normalized = normalizedBuffer.toString().trim();
    return normalized.isEmpty ? trimmed : normalized;
  }

  static String _stripSegmentWeightSyntax(String segment) {
    final leadingWhitespaceLength = segment.length - segment.trimLeft().length;
    final trailingWhitespaceLength =
        segment.length - segment.trimRight().length;
    final leadingWhitespace = segment.substring(0, leadingWhitespaceLength);
    final trailingWhitespace = segment.substring(
      segment.length - trailingWhitespaceLength,
    );
    final core = segment.trim();
    if (core.isEmpty) {
      return segment;
    }

    final strippedCore = _stripWeightSyntax(core);
    return '$leadingWhitespace$strippedCore$trailingWhitespace';
  }

  /// 剥离单段权重语法：`1.5::text::` → `text`、结尾残留 `::`、
  /// 外层成对 `{}`/`[]` 层数。
  static String _stripWeightSyntax(String segment) {
    var text = segment;

    // 1. NAI 数值权重: num::text:: (或缺失右侧 ::)
    final naiWeightMatch = RegExp(
      r'^(-?\d+\.?\d*)::(.+?)(?:::)?$',
    ).firstMatch(text);
    if (naiWeightMatch != null) {
      return naiWeightMatch.group(2)!.trim();
    }

    // 2. 结尾残留 ::
    if (text.endsWith('::')) {
      final stripped = text.substring(0, text.length - 2).trim();
      if (stripped.isNotEmpty) return stripped;
    }

    // 3. 外层连续大括号/方括号成对层数
    var openIndex = 0;
    var braceCount = 0;
    var bracketCount = 0;
    while (openIndex < text.length) {
      if (text[openIndex] == '{') {
        braceCount++;
      } else if (text[openIndex] == '[') {
        bracketCount++;
      } else {
        break;
      }
      openIndex++;
    }

    var closeIndex = text.length - 1;
    var closeBraceCount = 0;
    var closeBracketCount = 0;
    while (closeIndex >= openIndex) {
      if (text[closeIndex] == '}') {
        closeBraceCount++;
      } else if (text[closeIndex] == ']') {
        closeBracketCount++;
      } else {
        break;
      }
      closeIndex--;
    }

    final effectiveBraces = braceCount < closeBraceCount
        ? braceCount
        : closeBraceCount;
    final effectiveBrackets = bracketCount < closeBracketCount
        ? bracketCount
        : closeBracketCount;

    if (effectiveBraces > 0) {
      return text
          .substring(effectiveBraces, text.length - effectiveBraces)
          .trim();
    }
    if (effectiveBrackets > 0) {
      return text
          .substring(effectiveBrackets, text.length - effectiveBrackets)
          .trim();
    }
    return text;
  }
}
