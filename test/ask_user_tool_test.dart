import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/ask_user_tool.dart';

void main() {
  group('AskUserTool.parseQuestions', () {
    test('parses valid single question with options', () {
      final questions = AskUserTool.parseQuestions({
        'questions': [
          {
            'question': '想要什么画风？',
            'header': '画风',
            'options': [
              {'label': '水彩', 'description': '柔和淡雅'},
              {'label': '赛璐璐'},
            ],
          },
        ],
      });

      expect(questions, isNotNull);
      expect(questions!.length, equals(1));
      expect(questions.first.question, equals('想要什么画风？'));
      expect(questions.first.header, equals('画风'));
      expect(questions.first.multiSelect, isFalse);
      expect(questions.first.options.length, equals(2));
      expect(questions.first.options.first.label, equals('水彩'));
      expect(questions.first.options.first.description, equals('柔和淡雅'));
      expect(questions.first.options.last.description, isNull);
    });

    test('parses multiSelect and multiple questions', () {
      final questions = AskUserTool.parseQuestions({
        'questions': [
          {
            'question': 'Q1?',
            'multiSelect': true,
            'allowCustomInput': false,
            'options': [
              {'label': 'A'},
              {'label': 'B'},
              {'label': 'C'},
            ],
          },
          {
            'question': 'Q2?',
            'options': [
              {'label': 'X'},
              {'label': 'Y'},
            ],
          },
        ],
      });

      expect(questions!.length, equals(2));
      expect(questions.first.multiSelect, isTrue);
      expect(questions.first.allowCustomInput, isFalse);
      expect(questions.last.multiSelect, isFalse);
      expect(questions.last.allowCustomInput, isTrue);
    });

    test('rejects empty questions list', () {
      expect(AskUserTool.parseQuestions({'questions': []}), isNull);
      expect(AskUserTool.parseQuestions({'questions': 'not a list'}), isNull);
      expect(AskUserTool.parseQuestions({}), isNull);
    });

    test('rejects more than 4 questions', () {
      final questions = List.generate(
        5,
        (_) => {
          'question': 'Q?',
          'options': [
            {'label': 'A'},
            {'label': 'B'},
          ],
        },
      );
      expect(AskUserTool.parseQuestions({'questions': questions}), isNull);
    });

    test('rejects question without options or with fewer than 2 options', () {
      expect(
        AskUserTool.parseQuestions({
          'questions': [
            {
              'question': 'Q?',
              'options': [
                {'label': 'A'},
              ],
            },
          ],
        }),
        isNull,
      );
      expect(
        AskUserTool.parseQuestions({
          'questions': [
            {'question': 'Q?'},
          ],
        }),
        isNull,
      );
    });

    test('rejects options without label', () {
      expect(
        AskUserTool.parseQuestions({
          'questions': [
            {
              'question': 'Q?',
              'options': [
                {'description': 'no label'},
                {'label': 'B'},
              ],
            },
          ],
        }),
        isNull,
      );
    });
  });

  group('AskUserTool.execute', () {
    test('formats answers back to the LLM', () async {
      List<AgentQuestion>? captured;
      final tool = AskUserTool(
        onAsk: (questions) async {
          captured = questions;
          return ['水彩', 'A、B'];
        },
      );

      final result = await tool.execute('call_1', {
        'questions': [
          {
            'question': '想要什么画风？',
            'options': [
              {'label': '水彩'},
              {'label': '厚涂'},
            ],
          },
          {
            'question': '包含哪些元素？',
            'multiSelect': true,
            'options': [
              {'label': 'A'},
              {'label': 'B'},
            ],
          },
        ],
      });

      expect(result.isError, isFalse);
      expect(result.toolName, equals('ask_user'));
      expect(
        result.content,
        equals('问题: 想要什么画风？\n回答: 水彩\n\n问题: 包含哪些元素？\n回答: A、B'),
      );
      expect(captured!.length, equals(2));
    });

    test('user cancel returns error result', () async {
      final tool = AskUserTool(onAsk: (questions) async => null);

      final result = await tool.execute('call_2', {
        'questions': [
          {
            'question': 'Q?',
            'options': [
              {'label': 'A'},
              {'label': 'B'},
            ],
          },
        ],
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('用户取消了本次问询'));
    });

    test('invalid arguments return error result without invoking UI', () async {
      var invoked = false;
      final tool = AskUserTool(
        onAsk: (questions) async {
          invoked = true;
          return ['x'];
        },
      );

      final result = await tool.execute('call_3', {'questions': 'bad'});

      expect(result.isError, isTrue);
      expect(result.content, contains('参数不合法'));
      expect(invoked, isFalse);
    });
  });
}
