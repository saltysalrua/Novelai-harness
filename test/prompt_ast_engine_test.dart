import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/prompt_ast_engine.dart';

void main() {
  group('PromptAstEngine tokenization and parsing tests', () {
    test('parses simple comma separated tags accurately', () {
      const text = '1girl, solo, long hair, blue eyes';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      expect(tokens.length, 4);
      expect(tokens[0].name, '1girl');
      expect(tokens[1].name, 'solo');
      expect(tokens[2].name, 'long hair');
      expect(tokens[3].name, 'blue eyes');
      expect(tokens[0].braceLevel, 0);
      expect(tokens[0].numMult, 1.0);
      expect(tokens[0].disabled, false);
      expect(tokens[0].effectiveMultiplier, 1.0);
    });

    test('parses brace and bracket weights accurately', () {
      const text = '{masterpiece}, {{best quality}}, [bad anatomy], [[blurry]]';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      expect(tokens.length, 4);
      expect(tokens[0].name, 'masterpiece');
      expect(tokens[0].braceLevel, 1);
      expect(tokens[0].effectiveMultiplier, closeTo(1.05, 0.001));

      expect(tokens[1].name, 'best quality');
      expect(tokens[1].braceLevel, 2);
      expect(tokens[1].effectiveMultiplier, closeTo(1.1025, 0.001));

      expect(tokens[2].name, 'bad anatomy');
      expect(tokens[2].braceLevel, -1);
      expect(tokens[2].effectiveMultiplier, closeTo(1.0 / 1.05, 0.001));

      expect(tokens[3].name, 'blurry');
      expect(tokens[3].braceLevel, -2);
      expect(
        tokens[3].effectiveMultiplier,
        closeTo(1.0 / (1.05 * 1.05), 0.001),
      );
    });

    test('parses numeric weights N::tag:: accurately', () {
      const text = '1.2::silver hair::, 0.7::artist_name::, -0.5::bad hands::';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      expect(tokens.length, 3);
      expect(tokens[0].name, 'silver hair');
      expect(tokens[0].numMult, 1.2);
      expect(tokens[0].effectiveMultiplier, closeTo(1.2, 0.001));

      expect(tokens[1].name, 'artist_name');
      expect(tokens[1].numMult, 0.7);
      expect(tokens[1].effectiveMultiplier, closeTo(0.7, 0.001));

      expect(tokens[2].name, 'bad hands');
      expect(tokens[2].numMult, -0.5);
      expect(tokens[2].effectiveMultiplier, closeTo(-0.5, 0.001));
    });

    test('parses disabled tags ~tag~ accurately', () {
      const text = '~1girl~, ~{smile}~, solo';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      expect(tokens.length, 3);
      expect(tokens[0].name, '1girl');
      expect(tokens[0].disabled, true);

      expect(tokens[1].name, 'smile');
      expect(tokens[1].braceLevel, 1);
      expect(tokens[1].disabled, true);

      expect(tokens[2].name, 'solo');
      expect(tokens[2].disabled, false);
    });

    test('parses multi-character pipe delimiters and newlines', () {
      const text = 'scenery | 1girl, solo | 1boy\nnight sky';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      expect(tokens.length, 5);
      expect(tokens[0].name, 'scenery');
      expect(tokens[1].name, '1girl');
      expect(tokens[2].name, 'solo');
      expect(tokens[3].name, '1boy');
      expect(tokens[4].name, 'night sky');
    });
  });

  group('PromptAstEngine manipulation methods', () {
    test('wrapBracket increments and decrements brace layers', () {
      const text = '1girl, solo';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      // Up wrap
      final up1 = PromptAstEngine.wrapBracket(text, tokens[0], up: true);
      expect(up1, '{1girl}, solo');

      // Up wrap again
      final tokensUp1 = PromptAstEngine.parsePromptTokens(up1);
      final up2 = PromptAstEngine.wrapBracket(up1, tokensUp1[0], up: true);
      expect(up2, '{{1girl}}, solo');

      // Down wrap
      final down = PromptAstEngine.wrapBracket(text, tokens[1], up: false);
      expect(down, '1girl, [solo]');
    });

    test(
      'adjustNumericWeight increments and decrements in x.x::tag:: format',
      () {
        const text = '1girl, solo';
        final tokens = PromptAstEngine.parsePromptTokens(text);

        // 1.0 -> 1.1::1girl::
        final (up1, _) = PromptAstEngine.adjustNumericWeight(
          text,
          tokens[0],
          up: true,
        );
        expect(up1, '1.1::1girl::, solo');

        // 1.1 -> 1.2::1girl::
        final tokensUp1 = PromptAstEngine.parsePromptTokens(up1);
        final (up2, _) = PromptAstEngine.adjustNumericWeight(
          up1,
          tokensUp1[0],
          up: true,
        );
        expect(up2, '1.2::1girl::, solo');

        // 1.2 -> 1.1::1girl::
        final tokensUp2 = PromptAstEngine.parsePromptTokens(up2);
        final (down1, _) = PromptAstEngine.adjustNumericWeight(
          up2,
          tokensUp2[0],
          up: false,
        );
        expect(down1, '1.1::1girl::, solo');

        // 1.1 -> 1girl (normalizes to default 1.0)
        final tokensDown1 = PromptAstEngine.parsePromptTokens(down1);
        final (down2, _) = PromptAstEngine.adjustNumericWeight(
          down1,
          tokensDown1[0],
          up: false,
        );
        expect(down2, '1girl, solo');

        // 1.0 -> 0.9::1girl::
        final tokensDown2 = PromptAstEngine.parsePromptTokens(down2);
        final (down3, _) = PromptAstEngine.adjustNumericWeight(
          down2,
          tokensDown2[0],
          up: false,
        );
        expect(down3, '0.9::1girl::, solo');

        // 0.1 -> 0 -> -0.1::1girl:: (supports negative weights)
        final (negZero, _) = PromptAstEngine.adjustNumericWeight(
          '0.1::1girl::',
          PromptAstEngine.parsePromptTokens('0.1::1girl::')[0],
          up: false,
        );
        expect(negZero, '0::1girl::');

        final (negOne, _) = PromptAstEngine.adjustNumericWeight(
          negZero,
          PromptAstEngine.parsePromptTokens(negZero)[0],
          up: false,
        );
        expect(negOne, '-0.1::1girl::');

        final (negTwo, _) = PromptAstEngine.adjustNumericWeight(
          negOne,
          PromptAstEngine.parsePromptTokens(negOne)[0],
          up: false,
        );
        expect(negTwo, '-0.2::1girl::');
      },
    );

    test('parses negative numeric multipliers correctly', () {
      const text = '-0.5::bad anatomy::, -1.2::lowres::';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      expect(tokens.length, 2);
      expect(tokens[0].name, 'bad anatomy');
      expect(tokens[0].numMult, -0.5);
      expect(tokens[0].effectiveMultiplier, -0.5);

      expect(tokens[1].name, 'lowres');
      expect(tokens[1].numMult, -1.2);
    });

    test('setNumericMultiplier changes inner weight', () {
      const text = '1girl, solo';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      final weighted = PromptAstEngine.setNumericMultiplier(
        text,
        tokens[0],
        1.25,
      );
      expect(weighted, '1.25::1girl::, solo');

      final tokensW = PromptAstEngine.parsePromptTokens(weighted);
      final reset = PromptAstEngine.setNumericMultiplier(
        weighted,
        tokensW[0],
        1.0,
      );
      expect(reset, '1girl, solo');
    });

    test('toggleDisabled toggles ~ markers', () {
      const text = '1girl, solo';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      final disabled = PromptAstEngine.toggleDisabled(text, tokens[0]);
      expect(disabled, '~1girl~, solo');

      final tokensD = PromptAstEngine.parsePromptTokens(disabled);
      final enabled = PromptAstEngine.toggleDisabled(disabled, tokensD[0]);
      expect(enabled, '1girl, solo');
    });

    test('deleteToken cleanly removes token and comma', () {
      const text = '1girl, solo, long hair';
      final tokens = PromptAstEngine.parsePromptTokens(text);

      final (deletedMiddle, _) = PromptAstEngine.deleteToken(text, tokens[1]);
      expect(deletedMiddle, '1girl, long hair');

      final tokens2 = PromptAstEngine.parsePromptTokens(deletedMiddle);
      final (deletedFirst, _) = PromptAstEngine.deleteToken(
        deletedMiddle,
        tokens2[0],
      );
      expect(deletedFirst, 'long hair');
    });
  });

  group('PromptAstEngine autocomplete query extraction', () {
    test('extracts active query from cursor position', () {
      const text = '1girl, long h';
      final q = PromptAstEngine.extractActiveQuery(text, text.length);

      expect(q, isNotNull);
      expect(q!.query, 'long h');
      expect(q.replaceStart, 7);
      expect(q.replaceEnd, 13);
      expect(q.syntaxPrefix, '');
      expect(q.syntaxSuffix, '');
      expect(q.fullSegmentEnd, 13);
    });

    test('extracts query within single and multi-level braces', () {
      const text = '1girl, {blu}';
      final q = PromptAstEngine.extractActiveQuery(text, 11);

      expect(q, isNotNull);
      expect(q!.query, 'blu');
      expect(q.replaceStart, 8);
      expect(q.replaceEnd, 11);
      expect(q.syntaxPrefix, '{');
      expect(q.syntaxSuffix, '}');
      expect(q.fullSegmentEnd, 12);

      const nestedText = '1girl, {{master}}';
      // 光标在中间 (mast 后面)
      final q2 = PromptAstEngine.extractActiveQuery(nestedText, 13);
      expect(q2, isNotNull);
      expect(q2!.query, 'mast');
      expect(q2.replaceStart, 9);
      expect(q2.replaceEnd, 15);
      expect(q2.syntaxPrefix, '{{');
      expect(q2.syntaxSuffix, '}}');
      expect(q2.fullSegmentEnd, 17);

      // 光标在整个词末尾
      final q3 = PromptAstEngine.extractActiveQuery(nestedText, 15);
      expect(q3, isNotNull);
      expect(q3!.query, 'master');
    });

    test('extracts query within brackets and disabled tildes', () {
      const bracketText = '1girl, [blurry]';
      // 光标在词尾
      final q = PromptAstEngine.extractActiveQuery(bracketText, 14);
      expect(q, isNotNull);
      expect(q!.query, 'blurry');
      expect(q.syntaxPrefix, '[');
      expect(q.syntaxSuffix, ']');

      const disabledText = '1girl, ~bad hands~';
      final q2 = PromptAstEngine.extractActiveQuery(disabledText, 17);
      expect(q2, isNotNull);
      expect(q2!.query, 'bad hands');
      expect(q2.syntaxPrefix, '~');
      expect(q2.syntaxSuffix, '~');
    });

    test('extracts query within NAI numeric weights', () {
      const text = '1girl, 1.2::silver hair::';
      // 光标在词尾
      final q = PromptAstEngine.extractActiveQuery(text, 23);

      expect(q, isNotNull);
      expect(q!.query, 'silver hair');
      expect(q.replaceStart, 12);
      expect(q.replaceEnd, 23);
      expect(q.syntaxPrefix, '1.2::');
      expect(q.syntaxSuffix, '::');
      expect(q.fullSegmentEnd, 25);

      // 正在输入中 (未闭合 ::)
      const typingText = '1girl, 1.2::silv';
      final q2 = PromptAstEngine.extractActiveQuery(
        typingText,
        typingText.length,
      );
      expect(q2, isNotNull);
      expect(q2!.query, 'silv');
      expect(q2.syntaxPrefix, '1.2::');
      expect(q2.replaceStart, 12);
      expect(q2.replaceEnd, 16);
    });

    test('extracts query within SD colon weights', () {
      const text = '1girl, (masterpiece:1.2)';
      // 光标在 masterpiece 词尾
      final q = PromptAstEngine.extractActiveQuery(text, 19);

      expect(q, isNotNull);
      expect(q!.query, 'masterpiece');
      expect(q.syntaxPrefix, '(');
      expect(q.syntaxSuffix, ':1.2)');
      expect(q.replaceStart, 8);
      expect(q.replaceEnd, 19);
      expect(q.fullSegmentEnd, 24);
    });

    test('returns null when cursor is at empty space after comma', () {
      const text = '1girl, ';
      final q = PromptAstEngine.extractActiveQuery(text, text.length);
      expect(q, isNull);
    });

    test('replaceEnd stops at current word boundary keeping trailing text', () {
      // 光标在 h 后面 (偏移 13)，后面还有同段落内的其余单词 blue eyes
      const text = '1girl, blue hair blue eyes';
      final q = PromptAstEngine.extractActiveQuery(text, 13);

      expect(q, isNotNull);
      expect(q!.query, 'blue h');
      expect(q.replaceStart, 7);
      // 只替换到当前单词 hair 的词尾，不再吞掉后面的 blue eyes
      expect(q.replaceEnd, 16);
      expect(q.coreEnd, 26);
      expect(q.fullSegmentEnd, 26);
    });

    test(
      'replaceEnd consumes whole word when cursor mid-word at segment end',
      () {
        // 光标在 h 后面 (偏移 13)，单词剩余部分 air 后面紧跟逗号
        const text = '1girl, long hair, smile';
        final q = PromptAstEngine.extractActiveQuery(text, 13);

        expect(q, isNotNull);
        expect(q!.query, 'long h');
        expect(q.replaceStart, 7);
        expect(q.replaceEnd, 16);
        expect(q.coreEnd, 16);
      },
    );

    test('falls back to whole core when cursor at core start', () {
      const text = '1girl, blue hair';
      final q = PromptAstEngine.extractActiveQuery(text, 7);

      expect(q, isNotNull);
      expect(q!.query, 'blue hair');
      expect(q.replaceStart, 7);
      expect(q.replaceEnd, 16);
      expect(q.coreEnd, 16);
    });

    test('CJK-Latin script transition is a word boundary', () {
      // 中英混排无空格：光标在 过曝 后，后面紧接英文 high complexity
      const text = '1girl, 过曝high complexity';
      final q = PromptAstEngine.extractActiveQuery(text, 9);

      expect(q, isNotNull);
      expect(q!.query, '过曝');
      expect(q.replaceStart, 7);
      // replaceEnd 停在书写体系切换处，不再吞掉后续英文单词 high
      expect(q.replaceEnd, 9);
      expect(q.coreEnd, 24);
    });

    test('Latin-CJK script transition is a word boundary', () {
      // 反向：光标在英文词 long 后，后面紧接中文
      const text = '1girl, long过曝效果';
      final q = PromptAstEngine.extractActiveQuery(text, 11);

      expect(q, isNotNull);
      expect(q!.query, 'long');
      expect(q.replaceStart, 7);
      expect(q.replaceEnd, 11);
    });
  });

  group('PromptAstEngine SD format and beautify', () {
    test('converts SD WebUI weights to NovelAI syntax', () {
      const sdPrompt = '(masterpiece:1.2), (best quality), ((highres))';
      final naiPrompt = PromptAstEngine.sdToNaiPrompt(sdPrompt);

      expect(naiPrompt, '1.2::masterpiece::, {best quality}, {{highres}}');
    });

    test(
      'formatAndBeautify normalizes full-width commas and removes duplicate commas',
      () {
        const messy = '1girl， solo,,  (masterpiece:1.2) ； long hair, ';
        final clean = PromptAstEngine.formatAndBeautify(messy);

        expect(clean, '1girl, solo, 1.2::masterpiece::, long hair');
      },
    );

    test('formatAndBeautify preserves multi-character pipe separators', () {
      const multiRole = 'masterpiece，| 1girl, smile | solo,,';
      final clean = PromptAstEngine.formatAndBeautify(multiRole);

      expect(clean, 'masterpiece | 1girl, smile | solo');
    });
  });
}
