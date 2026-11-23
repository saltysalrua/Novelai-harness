import 'package:flutter/material.dart';

import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_library_mention.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';

/// 行内词库角色提及小卡片（输入框与已发送用户消息气泡共用）
class CharacterMentionChip extends StatelessWidget {
  final String title;
  final String? tooltip;
  final String? removeTooltip;
  final VoidCallback? onRemove;

  const CharacterMentionChip({
    super.key,
    required this.title,
    this.tooltip,
    this.removeTooltip,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasRemove = onRemove != null;

    Widget chip = Container(
      margin: const EdgeInsets.symmetric(horizontal: 1.5),
      padding: hasRemove
          ? const EdgeInsets.fromLTRB(5, 2.5, 3, 2.5)
          : const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.5),
      decoration: BoxDecoration(
        color: colors.primaryTint,
        borderRadius: BorderRadius.circular(AppRadius.sm + 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.person_outline_rounded,
            size: 12,
            color: colors.primary,
          ),
          const SizedBox(width: 2.5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 160),
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              strutStyle: const StrutStyle(
                fontSize: 12,
                height: 1.05,
                forceStrutHeight: true,
                leadingDistribution: TextLeadingDistribution.even,
              ),
              style: TextStyle(
                fontSize: 12,
                height: 1.05,
                fontWeight: FontWeight.w500,
                color: colors.primary,
              ),
            ),
          ),
          if (hasRemove) ...[
            const SizedBox(width: 2),
            MouseRegion(
              cursor: SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: Tooltip(
                  message: removeTooltip ?? '',
                  child: Padding(
                    padding: const EdgeInsets.all(0.5),
                    child: Icon(
                      Icons.close_rounded,
                      size: 12,
                      color: colors.primary.withValues(alpha: 0.72),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );

    final tip = tooltip?.trim();
    if (tip != null && tip.isNotEmpty) {
      chip = Tooltip(message: tip, child: chip);
    }
    return chip;
  }
}

/// 支持行内原子 `@[角色]` 卡片的对话输入控制器。
///
/// 内部使用 Unicode 私有区单码位 (`0xE000..0xF8FF`) 映射每个插入实例，
/// 使 `WidgetSpan` 与 `TextEditingValue.text` 保持严格 1:1 长度同构：
/// - Backspace / 方向键天然按整张卡片原子移动与删除；
/// - 唯一码位映射在 Undo / Redo 时依然可无损找回对应角色；
/// - 对外序列化/反序列化完全兼容既有 `@[标题]` 纯文本协议。
class ChatMentionTextController extends TextEditingController {
  static const int _puaStart = 0xE000;
  static const int _puaEnd = 0xF8FF;

  final List<PromptComboEntry> Function() entriesProvider;

  /// 点击行内卡片移除按钮后的可选回调（用于保持焦点等）
  final VoidCallback? onChipRemoved;

  final Map<int, String> _tokenTitles = {};
  int _nextCodeUnit = _puaStart;

  ChatMentionTextController({
    required this.entriesProvider,
    this.onChipRemoved,
    String? initialSerializedText,
  }) {
    if (initialSerializedText != null && initialSerializedText.isNotEmpty) {
      final encoded = encodeSerializedText(initialSerializedText);
      value = TextEditingValue(
        text: encoded,
        selection: TextSelection.collapsed(offset: encoded.length),
      );
    }
  }

  /// 判断码位是否属于本控制器分配的角色占位符
  bool isMentionCodeUnit(int codeUnit) => _tokenTitles.containsKey(codeUnit);

  /// 选区范围内是否包含任意行内角色卡片占位符
  bool containsMentionInRange(int start, int end) {
    final raw = text;
    final clampedStart = start.clamp(0, raw.length);
    final clampedEnd = end.clamp(clampedStart, raw.length);
    for (var i = clampedStart; i < clampedEnd; i++) {
      if (_tokenTitles.containsKey(raw.codeUnitAt(i))) return true;
    }
    return false;
  }

  /// 分配一个单字符 PUA 占位符并绑定角色标题
  String _allocateToken(String title) {
    final safeTitle = title.trim().replaceAll('[', '(').replaceAll(']', ')');
    if (_nextCodeUnit > _puaEnd) {
      final activeUnits = <int>{};
      final raw = text;
      for (var i = 0; i < raw.length; i++) {
        final unit = raw.codeUnitAt(i);
        if (_tokenTitles.containsKey(unit)) {
          activeUnits.add(unit);
        }
      }
      _tokenTitles.removeWhere((unit, _) => !activeUnits.contains(unit));
      var candidate = _puaStart;
      while (candidate <= _puaEnd && _tokenTitles.containsKey(candidate)) {
        candidate++;
      }
      if (candidate > _puaEnd) {
        return formatCharacterMention(safeTitle);
      }
      _tokenTitles[candidate] = safeTitle;
      return String.fromCharCode(candidate);
    }
    final unit = _nextCodeUnit++;
    _tokenTitles[unit] = safeTitle;
    return String.fromCharCode(unit);
  }

  /// 将文本中的已知词库角色 `@[标题]` 编码为单字符内联占位符
  String encodeSerializedText(String serialized) {
    if (serialized.isEmpty || !serialized.contains('@[')) return serialized;
    final entries = entriesProvider();
    if (entries.isEmpty) return serialized;
    return serialized.replaceAllMapped(bracketMentionRegex, (match) {
      final rawToken = match.group(1);
      if (rawToken == null) return match.group(0)!;
      final matched = findCharacterByMentionToken(rawToken, entries);
      if (matched == null) return match.group(0)!;
      return _allocateToken(matched.title);
    });
  }

  /// 将包含占位符的编辑文本无损还原为标准 `@[标题]` 协议文本
  String toSerializedText([String? source]) {
    final raw = source ?? text;
    if (_tokenTitles.isEmpty || raw.isEmpty) return raw;
    final buffer = StringBuffer();
    var segmentStart = 0;
    for (var i = 0; i < raw.length; i++) {
      final title = _tokenTitles[raw.codeUnitAt(i)];
      if (title == null) continue;
      if (i > segmentStart) {
        buffer.write(raw.substring(segmentStart, i));
      }
      buffer.write(formatCharacterMention(title));
      segmentStart = i + 1;
    }
    if (segmentStart == 0) return raw;
    if (segmentStart < raw.length) {
      buffer.write(raw.substring(segmentStart));
    }
    return buffer.toString();
  }

  /// 序列化指定字符区间（供复制/剪切写回剪贴板使用）
  String serializeRange(int start, int end) {
    final raw = text;
    final clampedStart = start.clamp(0, raw.length);
    final clampedEnd = end.clamp(clampedStart, raw.length);
    return toSerializedText(raw.substring(clampedStart, clampedEnd));
  }

  /// 以 `@[标题]` 序列化文本整体重置输入框内容
  void setSerializedText(String serialized, {bool collapseAtEnd = true}) {
    final encoded = encodeSerializedText(serialized);
    final nextOffset = collapseAtEnd
        ? encoded.length
        : selection.extentOffset.clamp(0, encoded.length);
    value = TextEditingValue(
      text: encoded,
      selection: TextSelection.collapsed(offset: nextOffset),
    );
  }

  /// 清空输入框并重置占位符映射表（发送完成后调用）
  void clearAll() {
    _tokenTitles.clear();
    _nextCodeUnit = _puaStart;
    clear();
  }

  /// 在指定区间插入一个行内角色卡片，并在末尾可选追加空格
  void insertMention(
    String title, {
    required int replaceStart,
    required int replaceEnd,
    bool appendTrailingSpace = true,
  }) {
    final raw = text;
    final start = replaceStart.clamp(0, raw.length);
    final end = replaceEnd.clamp(start, raw.length);
    final token = _allocateToken(title);
    final inserted = appendTrailingSpace ? '$token ' : token;
    final nextText = raw.replaceRange(start, end, inserted);
    value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + inserted.length),
    );
  }

  /// 删除位于 [index] 的行内角色卡片，并顺手清理紧随其后的冗余空格
  void removeTokenAt(int index) {
    final raw = text;
    if (index < 0 || index >= raw.length) return;
    if (!_tokenTitles.containsKey(raw.codeUnitAt(index))) return;

    var removeEnd = index + 1;
    if (removeEnd < raw.length &&
        raw[removeEnd] == ' ' &&
        (index == 0 || raw[index - 1] == ' ' || raw[index - 1] == '\n')) {
      removeEnd++;
    }
    final nextText = raw.replaceRange(index, removeEnd, '');
    value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: index.clamp(0, nextText.length)),
    );
    onChipRemoved?.call();
  }

  /// 词库异步加载完成或更新后，将正文中已存在的裸 `@[标题]` 升级为行内卡片
  void upgradeRawMentions() {
    final raw = text;
    if (raw.isEmpty || !raw.contains('@[')) return;
    if (value.composing.isValid && !value.composing.isCollapsed) return;
    final entries = entriesProvider();
    if (entries.isEmpty) return;

    final matches = bracketMentionRegex.allMatches(raw).toList(growable: false);
    if (matches.isEmpty) return;

    final buffer = StringBuffer();
    var lastEnd = 0;
    var changed = false;
    var baseOffset = selection.isValid ? selection.baseOffset : raw.length;
    var extentOffset = selection.isValid ? selection.extentOffset : raw.length;
    var deltaBeforeBase = 0;
    var deltaBeforeExtent = 0;

    for (final match in matches) {
      final tokenText = match.group(1);
      final matched = tokenText == null
          ? null
          : findCharacterByMentionToken(tokenText, entries);
      if (matched == null) continue;

      if (match.start > lastEnd) {
        buffer.write(raw.substring(lastEnd, match.start));
      }
      final placeholder = _allocateToken(matched.title);
      buffer.write(placeholder);
      lastEnd = match.end;
      changed = true;

      final diff = placeholder.length - (match.end - match.start);
      if (baseOffset >= match.end) {
        deltaBeforeBase += diff;
      } else if (baseOffset > match.start) {
        deltaBeforeBase += placeholder.length - (baseOffset - match.start);
      }
      if (extentOffset >= match.end) {
        deltaBeforeExtent += diff;
      } else if (extentOffset > match.start) {
        deltaBeforeExtent += placeholder.length - (extentOffset - match.start);
      }
    }

    if (!changed) return;
    if (lastEnd < raw.length) {
      buffer.write(raw.substring(lastEnd));
    }
    final nextText = buffer.toString();
    final nextBase = (baseOffset + deltaBeforeBase).clamp(0, nextText.length);
    final nextExtent = (extentOffset + deltaBeforeExtent).clamp(
      0,
      nextText.length,
    );
    value = TextEditingValue(
      text: nextText,
      selection: TextSelection(baseOffset: nextBase, extentOffset: nextExtent),
    );
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (_tokenTitles.isEmpty || text.isEmpty) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    final raw = text;
    final entries = entriesProvider();
    final removeTooltip = context.maybeL10n?.chatLinkedCharacterRemoveTooltip;
    final composing = withComposing && value.isComposingRangeValid
        ? value.composing
        : TextRange.empty;
    final composingStyle = style?.merge(
      const TextStyle(decoration: TextDecoration.underline),
    );

    final spans = <InlineSpan>[];
    var segmentStart = 0;

    void appendPlainSegment(int start, int end) {
      if (end <= start) return;
      if (!composing.isValid ||
          composing.isCollapsed ||
          composing.end <= start ||
          composing.start >= end) {
        spans.add(TextSpan(text: raw.substring(start, end)));
        return;
      }
      final compStart = composing.start.clamp(start, end);
      final compEnd = composing.end.clamp(start, end);
      if (compStart > start) {
        spans.add(TextSpan(text: raw.substring(start, compStart)));
      }
      if (compEnd > compStart) {
        spans.add(
          TextSpan(
            text: raw.substring(compStart, compEnd),
            style: composingStyle,
          ),
        );
      }
      if (end > compEnd) {
        spans.add(TextSpan(text: raw.substring(compEnd, end)));
      }
    }

    for (var i = 0; i < raw.length; i++) {
      final title = _tokenTitles[raw.codeUnitAt(i)];
      if (title == null) continue;
      appendPlainSegment(segmentStart, i);
      final matched = findCharacterByMentionToken(title, entries);
      final tokenIndex = i;
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: CharacterMentionChip(
            title: matched?.title ?? title,
            tooltip: matched?.prompt,
            removeTooltip: removeTooltip,
            onRemove: () => removeTokenAt(tokenIndex),
          ),
        ),
      );
      segmentStart = i + 1;
    }

    if (segmentStart == 0) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }

    appendPlainSegment(segmentStart, raw.length);
    return TextSpan(style: style, children: spans);
  }
}
