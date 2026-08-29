import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/types.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

class AgentChatCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const AgentChatCard({super.key, required this.viewModel});

  @override
  State<AgentChatCard> createState() => _AgentChatCardState();
}

class _AgentChatCardState extends State<AgentChatCard> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    widget.viewModel.sendChatMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final messages = widget.viewModel.messages;
    final isStreaming = widget.viewModel.isChatStreaming;
    final currentSkill = widget.viewModel.currentSkill;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部技能选择栏与清空按钮
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.psychology_outlined, size: 16, color: AppTheme.notionBlue),
                    const SizedBox(width: 6),
                    DropdownButtonHideUnderline(
                      child: DropdownButton<Skill>(
                        value: currentSkill,
                        dropdownColor: AppTheme.pureWhite,
                        items: BuiltinSkills.all.map((skill) {
                          return DropdownMenuItem(
                            value: skill,
                            child: Text(
                              skill.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          );
                        }).toList(),
                        onChanged: (skill) {
                          if (skill != null) {
                            widget.viewModel.selectSkill(skill);
                          }
                        },
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: AppTheme.textMuted),
                  tooltip: '清空对话历史',
                  onPressed: () => widget.viewModel.sendChatMessage('/clear'),
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),

          // 对话消息流展示区域
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(12),
              itemCount: messages.length + (isStreaming ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == messages.length && isStreaming) {
                  return _buildStreamingBubble();
                }

                final msg = messages[index];
                return _buildMessageBubble(msg);
              },
            ),
          ),

          // 底部快捷指令栏
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: const BoxDecoration(
              color: AppTheme.pureWhite,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCommandChip('/help', '帮助'),
                  const SizedBox(width: 6),
                  _buildCommandChip('/nai ', '生图'),
                  const SizedBox(width: 6),
                  _buildCommandChip('/tag ', '查标签'),
                  const SizedBox(width: 6),
                  _buildCommandChip('/upscale 4', '放大'),
                  const SizedBox(width: 6),
                  _buildCommandChip('/account', '查体力'),
                ],
              ),
            ),
          ),

          // 底部消息输入框
          Container(
            padding: const EdgeInsets.all(10),
            decoration: const BoxDecoration(
              color: AppTheme.pureWhite,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter): _handleSend,
                    },
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                      decoration: InputDecoration(
                        hintText: '输入绘画构思，或输入 /nai <词> 快速生图...',
                        fillColor: AppTheme.paperWarmth,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                          borderSide: const BorderSide(color: AppTheme.notionBlue, width: 1.5),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.notionBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    ),
                  ),
                  icon: isStreaming
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.send, size: 16),
                  onPressed: isStreaming ? null : _handleSend,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(AgentMessage msg) {
    final isUser = msg.role == AgentRole.user;
    final isTool = msg.role == AgentRole.tool;

    if (isTool) {
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: Border.all(color: AppTheme.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.build_circle_outlined, size: 14, color: AppTheme.notionBlue),
                SizedBox(width: 4),
                Text(
                  '工具执行输出',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.notionBlue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            SelectableText(
              msg.content,
              style: const TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
                height: 1.35,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.8,
        ),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isUser ? AppTheme.skyTint : AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: Border.all(
            color: isUser ? AppTheme.notionBlue.withValues(alpha: 0.25) : AppTheme.border,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 思考过程 (如有)
            if (msg.thoughts.isNotEmpty) ...[
              Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(top: 4, bottom: 6),
                  title: const Row(
                    children: [
                      Icon(Icons.lightbulb_outline, size: 14, color: AppTheme.warning),
                      SizedBox(width: 4),
                      Text(
                        '思考过程',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.warning),
                      ),
                    ],
                  ),
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppTheme.pureWhite,
                        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                        border: Border.all(color: AppTheme.border),
                      ),
                      child: SelectableText(
                        msg.thoughts,
                        style: const TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: AppTheme.textMuted,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 消息正文
            SelectableText(
              msg.content,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textPrimary,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStreamingBubble() {
    final thoughts = widget.viewModel.currentStreamingThoughts;
    final content = widget.viewModel.currentStreamingContent;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: Border.all(color: AppTheme.notionBlue.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (thoughts.isNotEmpty) ...[
              const Row(
                children: [
                  SizedBox(
                    width: 10,
                    height: 10,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: AppTheme.warning),
                  ),
                  SizedBox(width: 6),
                  Text(
                    '正在思考...',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.warning),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Text(
                  thoughts,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textMuted, fontFamily: 'monospace'),
                ),
              ),
              const SizedBox(height: 6),
            ],
            SelectableText(
              content.isEmpty ? '构思中...' : content,
              style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommandChip(String command, String label) {
    return InkWell(
      onTap: () {
        _inputController.text = command;
        _inputController.selection = TextSelection.fromPosition(
          TextPosition(offset: _inputController.text.length),
        );
      },
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(color: AppTheme.border),
        ),
        child: Text(
          '$command ($label)',
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
