import 'package:flutter/material.dart';
import '../../../../core/harness/tools/ask_user_tool.dart';
import '../../../core/theme/app_theme.dart';

/// 内嵌于 Agent 对话流中的交互提问卡片
class InlineAgentQuestionCard extends StatefulWidget {
  final AgentQuestionPrompt prompt;

  const InlineAgentQuestionCard({super.key, required this.prompt});

  @override
  State<InlineAgentQuestionCard> createState() =>
      _InlineAgentQuestionCardState();
}

class _InlineAgentQuestionCardState extends State<InlineAgentQuestionCard> {
  late final List<Set<int>> _selectedIndices;
  late final List<TextEditingController> _customControllers;

  @override
  void initState() {
    super.initState();
    _selectedIndices =
        List.generate(widget.prompt.questions.length, (_) => <int>{});
    _customControllers = List.generate(
      widget.prompt.questions.length,
      (_) => TextEditingController(),
    );
  }

  @override
  void dispose() {
    for (final c in _customControllers) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _isAllAnswered {
    for (var i = 0; i < widget.prompt.questions.length; i++) {
      final q = widget.prompt.questions[i];
      final hasSelected = _selectedIndices[i].isNotEmpty;
      final hasCustom =
          q.allowCustomInput && _customControllers[i].text.trim().isNotEmpty;
      if (!hasSelected && !hasCustom) return false;
    }
    return true;
  }

  void _submit() {
    if (!_isAllAnswered) return;
    final answers = <String>[];
    for (var i = 0; i < widget.prompt.questions.length; i++) {
      final q = widget.prompt.questions[i];
      final custom = q.allowCustomInput ? _customControllers[i].text.trim() : '';
      if (custom.isNotEmpty) {
        answers.add(custom);
      } else {
        final labels = _selectedIndices[i]
            .map((idx) => q.options[idx].label)
            .toList()
          ..sort();
        answers.add(labels.join('、'));
      }
    }
    widget.prompt.submit(answers);
  }

  @override
  Widget build(BuildContext context) {
    final questions = widget.prompt.questions;
    final isSingleBinaryConfirm = questions.length == 1 &&
        questions.first.options.length == 2 &&
        !questions.first.allowCustomInput;

    final headerText = questions.first.header ?? '向用户提问';
    final isPaymentHeader = headerText.contains('点数') || headerText.contains('付费');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(
          color: isPaymentHeader
              ? AppTheme.warning.withValues(alpha: 0.6)
              : AppTheme.notionBlue.withValues(alpha: 0.5),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 头部标题条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: (isPaymentHeader ? AppTheme.warning : AppTheme.notionBlue)
                  .withValues(alpha: 0.08),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppTheme.radiusCard - 1),
              ),
              border: Border(
                bottom: BorderSide(
                  color: (isPaymentHeader
                          ? AppTheme.warning
                          : AppTheme.notionBlue)
                      .withValues(alpha: 0.2),
                ),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  isPaymentHeader
                      ? Icons.monetization_on_outlined
                      : Icons.help_outline_rounded,
                  size: 16,
                  color: isPaymentHeader
                      ? AppTheme.warning
                      : AppTheme.notionBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  headerText,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: isPaymentHeader
                        ? AppTheme.warning
                        : AppTheme.notionBlue,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '待确认',
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.stone,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 问题列表
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < questions.length; i++) ...[
                  if (i > 0) const Divider(height: 20, color: AppTheme.border),
                  _buildQuestionItem(i, questions[i], isSingleBinaryConfirm),
                ],
              ],
            ),
          ),

          // 底部操作栏 (若是单问题二元直选则不需要额外提交栏，直接在选项按钮完成点击)
          if (!isSingleBinaryConfirm) ...[
            const Divider(height: 1, color: AppTheme.border),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => widget.prompt.cancel(),
                    style: TextButton.styleFrom(
                      foregroundColor: AppTheme.stone,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.notionBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: _isAllAnswered ? _submit : null,
                    child: const Text('提交回答'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildQuestionItem(
    int qIndex,
    AgentQuestion question,
    bool isSingleBinaryConfirm,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          question.question,
          style: const TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: 10),

        // 如果是二元直选确认 (如：确认生成 vs 取消生图)
        if (isSingleBinaryConfirm)
          Row(
            children: [
              for (var optIdx = 0; optIdx < question.options.length; optIdx++) ...[
                if (optIdx > 0) const SizedBox(width: 10),
                Expanded(
                  child: _buildBinaryActionTile(
                    question.options[optIdx],
                    isPrimary: optIdx == 0,
                    onTap: () {
                      if (optIdx == 0) {
                        widget.prompt.submit([question.options[0].label]);
                      } else {
                        widget.prompt.cancel();
                      }
                    },
                  ),
                ),
              ],
            ],
          )
        else
          // 常规选项列表
          Column(
            children: [
              for (var optIdx = 0;
                  optIdx < question.options.length;
                  optIdx++) ...[
                _buildOptionTile(
                  qIndex,
                  optIdx,
                  question.options[optIdx],
                  question.multiSelect,
                ),
                const SizedBox(height: 6),
              ],
            ],
          ),

        // 自定义回答输入框 (仅在 allowCustomInput 为 true 且非二元直选时显示)
        if (question.allowCustomInput && !isSingleBinaryConfirm) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _customControllers[qIndex],
            style: const TextStyle(fontSize: 13),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: '输入自定义回答...',
              isDense: true,
              filled: true,
              fillColor: AppTheme.paperWarmth,
              hoverColor: AppTheme.paperWarmth,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(6),
                borderSide: const BorderSide(color: AppTheme.border),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildBinaryActionTile(
    AgentQuestionOption option, {
    required bool isPrimary,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isPrimary
              ? AppTheme.warning.withValues(alpha: 0.12)
              : AppTheme.surfaceVariant,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isPrimary
                ? AppTheme.warning
                : AppTheme.border,
            width: isPrimary ? 1.4 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              option.label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: isPrimary ? AppTheme.warning : AppTheme.textPrimary,
              ),
            ),
            if (option.description != null && option.description!.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(
                option.description!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.stone,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOptionTile(
    int qIndex,
    int optIdx,
    AgentQuestionOption option,
    bool multiSelect,
  ) {
    final isSelected = _selectedIndices[qIndex].contains(optIdx);

    return InkWell(
      onTap: () {
        setState(() {
          if (multiSelect) {
            if (isSelected) {
              _selectedIndices[qIndex].remove(optIdx);
            } else {
              _selectedIndices[qIndex].add(optIdx);
            }
          } else {
            _selectedIndices[qIndex] = {optIdx};
          }
          // 若选择了预设项，清空自定义输入
          _customControllers[qIndex].clear();
        });
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.notionBlue.withValues(alpha: 0.08)
              : AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppTheme.notionBlue : AppTheme.border,
            width: isSelected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Icon(
              multiSelect
                  ? (isSelected
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded)
                  : (isSelected
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded),
              size: 16,
              color: isSelected ? AppTheme.notionBlue : AppTheme.stone,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight:
                          isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected
                          ? AppTheme.notionBlue
                          : AppTheme.textPrimary,
                    ),
                  ),
                  if (option.description != null &&
                      option.description!.isNotEmpty)
                    Text(
                      option.description!,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.stone,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
