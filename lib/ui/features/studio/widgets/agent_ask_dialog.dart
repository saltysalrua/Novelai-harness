import 'package:flutter/material.dart';
import '../../../../core/harness/tools/ask_user_tool.dart';
import '../../../core/theme/app_theme.dart';

/// Agent 向用户提出结构化问题的对话框 (参考 Pi 的 ask_user_question 交互)。
///
/// 每个问题提供候选项 + 自定义输入；全部回答后才能提交，取消则返回 null。
class AgentAskDialog extends StatefulWidget {
  final List<AgentQuestion> questions;

  const AgentAskDialog({super.key, required this.questions});

  static Future<List<String>?> show(
    BuildContext context,
    List<AgentQuestion> questions,
  ) {
    return showDialog<List<String>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AgentAskDialog(questions: questions),
    );
  }

  @override
  State<AgentAskDialog> createState() => _AgentAskDialogState();
}

class _AgentAskDialogState extends State<AgentAskDialog> {
  late final List<Set<int>> _selected;
  late final List<TextEditingController> _customControllers;

  @override
  void initState() {
    super.initState();
    _selected = List.generate(widget.questions.length, (_) => <int>{});
    _customControllers = List.generate(
      widget.questions.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final controller in _customControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  bool get _allAnswered {
    for (var i = 0; i < widget.questions.length; i++) {
      if (_selected[i].isEmpty && _customControllers[i].text.trim().isEmpty) {
        return false;
      }
    }
    return true;
  }

  void _submit() {
    if (!_allAnswered) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请回答所有问题后再提交 (选择选项或输入自定义回答)'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    final answers = <String>[];
    for (var i = 0; i < widget.questions.length; i++) {
      final custom = _customControllers[i].text.trim();
      if (custom.isNotEmpty) {
        answers.add(custom);
      } else {
        final labels =
            _selected[i]
                .map((idx) => widget.questions[i].options[idx].label)
                .toList()
              ..sort();
        answers.add(labels.join('、'));
      }
    }
    Navigator.of(context).pop(answers);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 4),
              child: Row(
                children: [
                  const Icon(
                    Icons.help_outline_rounded,
                    size: 18,
                    color: AppTheme.notionBlue,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    'AI 助手提问',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    color: AppTheme.stone,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppTheme.border),

            // 问题列表
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 0; i < widget.questions.length; i++)
                      _buildQuestion(i),
                  ],
                ),
              ),
            ),

            // 操作按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.notionBlue,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(
                          AppTheme.radiusButton,
                        ),
                      ),
                    ),
                    onPressed: _submit,
                    child: const Text('提交回答', style: TextStyle(fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuestion(int index) {
    final question = widget.questions[index];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 问题头: 标签 + 问题文本
          if (question.header != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: AppTheme.skyTint,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: Text(
                question.header!,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.notionBlue,
                ),
              ),
            ),
            const SizedBox(height: 6),
          ],
          Text(
            question.question,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
              height: 1.4,
            ),
          ),
          if (question.multiSelect) ...[
            const SizedBox(height: 3),
            const Text(
              '可多选',
              style: TextStyle(fontSize: 10.5, color: AppTheme.textMuted),
            ),
          ],
          const SizedBox(height: 8),

          // 选项列表
          for (var o = 0; o < question.options.length; o++)
            _buildOptionTile(index, o),

          // 自定义回答输入
          const SizedBox(height: 8),
          TextField(
            controller: _customControllers[index],
            onChanged: (_) => setState(() {}),
            style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              hintText: '自定义回答 (优先于选项)...',
              hintStyle: const TextStyle(
                fontSize: 11.5,
                color: AppTheme.textMuted,
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                borderSide: const BorderSide(
                  color: AppTheme.notionBlue,
                  width: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOptionTile(int questionIndex, int optionIndex) {
    final question = widget.questions[questionIndex];
    final option = question.options[optionIndex];
    final isSelected = _selected[questionIndex].contains(optionIndex);

    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: InkWell(
        onTap: () => setState(() {
          if (question.multiSelect) {
            isSelected
                ? _selected[questionIndex].remove(optionIndex)
                : _selected[questionIndex].add(optionIndex);
          } else {
            _selected[questionIndex].clear();
            _selected[questionIndex].add(optionIndex);
          }
        }),
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.skyTint : AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            border: Border.all(
              color: isSelected
                  ? AppTheme.notionBlue.withValues(alpha: 0.5)
                  : AppTheme.border,
            ),
          ),
          child: Row(
            children: [
              Icon(
                question.multiSelect
                    ? (isSelected
                          ? Icons.check_box_rounded
                          : Icons.check_box_outline_blank_rounded)
                    : (isSelected
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_off_rounded),
                size: 15,
                color: isSelected ? AppTheme.notionBlue : AppTheme.textMuted,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      option.label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.w500,
                        color: isSelected
                            ? AppTheme.textPrimary
                            : AppTheme.textSecondary,
                      ),
                    ),
                    if (option.description != null) ...[
                      const SizedBox(height: 1),
                      Text(
                        option.description!,
                        style: const TextStyle(
                          fontSize: 10.5,
                          color: AppTheme.textMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
