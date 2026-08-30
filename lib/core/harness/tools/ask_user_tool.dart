import 'dart:async';
import '../types.dart';
import 'agent_tool.dart';

/// ask_user 工具的选项定义
class AgentQuestionOption {
  final String label;
  final String? description;

  const AgentQuestionOption({required this.label, this.description});
}

/// ask_user 工具的单个问题定义
class AgentQuestion {
  final String question;
  final String? header;
  final bool multiSelect;
  final bool allowCustomInput;
  final List<AgentQuestionOption> options;

  const AgentQuestion({
    required this.question,
    this.header,
    this.multiSelect = false,
    this.allowCustomInput = true,
    required this.options,
  });
}

/// 当前待用户回答的交互式问题提示对象
class AgentQuestionPrompt {
  final List<AgentQuestion> questions;
  final Completer<List<String>?> completer;

  AgentQuestionPrompt({
    required this.questions,
    required this.completer,
  });

  bool get isCompleted => completer.isCompleted;

  void submit(List<String> answers) {
    if (!completer.isCompleted) {
      completer.complete(answers);
    }
  }

  void cancel() {
    if (!completer.isCompleted) {
      completer.complete(null);
    }
  }
}

/// 向用户提出结构化问题的 Agent 工具 (参考 Pi 的 ask_user_question)。
///
/// LLM 一次最多提出 4 个问题，每个问题 2-4 个选项；用户也可输入自定义回答。
/// 工具会阻塞直到用户提交或取消，回答以文本形式返回给 LLM 继续对话。
class AskUserTool extends AgentTool {
  /// 由 UI 层注入的提问回调，返回与问题等长的回答列表；用户取消时返回 null
  final Future<List<String>?> Function(List<AgentQuestion> questions) onAsk;

  AskUserTool({required this.onAsk})
    : super(
        name: 'ask_user',
        label: '向用户提问',
        description:
            '向用户提出结构化问题以澄清需求或收集偏好。适合在关键决策点使用，'
            '例如确认画面主题、风格方向、构图取舍等。一次最多 4 个问题，'
            '每个问题提供 2-4 个互斥选项 (multiSelect 为 true 时可多选)，'
            '用户也可以输入自定义回答。不要在每轮对话都用，只在信息不足以继续时使用。',
        parameters: {
          'type': 'object',
          'properties': {
            'questions': {
              'type': 'array',
              'minItems': 1,
              'maxItems': 4,
              'description': '要提出的问题列表',
              'items': {
                'type': 'object',
                'properties': {
                  'question': {
                    'type': 'string',
                    'description': '完整的问题描述，以问号结尾',
                  },
                  'header': {
                    'type': 'string',
                    'description': '问题的简短标签，最多 16 个字符',
                  },
                  'multiSelect': {
                    'type': 'boolean',
                    'description': '是否允许多选，默认 false',
                  },
                  'options': {
                    'type': 'array',
                    'minItems': 2,
                    'maxItems': 4,
                    'description': '问题的候选项',
                    'items': {
                      'type': 'object',
                      'properties': {
                        'label': {
                          'type': 'string',
                          'description': '选项名称，简洁明确 (1-5 个词)',
                        },
                        'description': {
                          'type': 'string',
                          'description': '选项的补充说明或取舍提示',
                        },
                      },
                      'required': ['label'],
                    },
                  },
                },
                'required': ['question', 'options'],
              },
            },
          },
          'required': ['questions'],
        },
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final questions = parseQuestions(args);
    if (questions == null) {
      return ToolResult(
        toolCallId: toolCallId,
        toolName: name,
        content:
            '参数不合法: questions 必须是 1-4 个问题，每个问题包含 question 字段和 2-4 个带 label 的选项。',
        isError: true,
      );
    }

    final answers = await onAsk(questions);
    if (answers == null) {
      return ToolResult(
        toolCallId: toolCallId,
        toolName: name,
        content: '用户取消了本次问询，未提供回答。请基于现有信息继续，或稍后重新询问。',
        isError: true,
      );
    }

    final buffer = StringBuffer();
    for (var i = 0; i < questions.length; i++) {
      if (i > 0) buffer.write('\n\n');
      buffer.write('问题: ${questions[i].question}\n回答: ${answers[i]}');
    }
    return ToolResult(
      toolCallId: toolCallId,
      toolName: name,
      content: buffer.toString(),
    );
  }

  /// 解析并校验 LLM 给出的问题参数，不合法时返回 null
  static List<AgentQuestion>? parseQuestions(Map<String, dynamic> args) {
    final raw = args['questions'];
    if (raw is! List || raw.isEmpty || raw.length > 4) return null;

    final questions = <AgentQuestion>[];
    for (final item in raw) {
      if (item is! Map) return null;
      final question = item['question'];
      if (question is! String || question.trim().isEmpty) return null;

      final rawOptions = item['options'];
      if (rawOptions is! List ||
          rawOptions.length < 2 ||
          rawOptions.length > 4) {
        return null;
      }

      final options = <AgentQuestionOption>[];
      for (final rawOption in rawOptions) {
        if (rawOption is! Map) return null;
        final label = rawOption['label'];
        if (label is! String || label.trim().isEmpty) return null;
        options.add(
          AgentQuestionOption(
            label: label.trim(),
            description: rawOption['description'] is String
                ? rawOption['description'] as String
                : null,
          ),
        );
      }

      final header = item['header'];
      questions.add(
        AgentQuestion(
          question: question.trim(),
          header: header is String && header.trim().isNotEmpty
              ? header.trim()
              : null,
          multiSelect: item['multiSelect'] == true,
          allowCustomInput: item['allowCustomInput'] != false,
          options: options,
        ),
      );
    }
    return questions;
  }
}
