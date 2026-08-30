import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

/// Agent 对话卡底部控制与输入区:
/// 模型/思考强度一体化胶囊卡片 + 消息输入框与发送按钮
class AgentChatInputBar extends StatefulWidget {
  final StudioViewModel viewModel;

  /// 发送成功后的回调 (用于滚动到消息流底部)
  final VoidCallback? onSent;

  const AgentChatInputBar({super.key, required this.viewModel, this.onSent});

  @override
  State<AgentChatInputBar> createState() => _AgentChatInputBarState();
}

class _AgentChatInputBarState extends State<AgentChatInputBar> {
  final TextEditingController _inputController = TextEditingController();

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  void _handleSend() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    widget.viewModel.sendChatMessage(text);
    widget.onSent?.call();
  }

  @override
  Widget build(BuildContext context) {
    final isStreaming = widget.viewModel.isChatStreaming;
    final activeProvider = widget.viewModel.config.activeLlmProvider;
    final activeModel = activeProvider.activeModel;
    final currentEffort = widget.viewModel.currentThinkingEffort;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: const BoxDecoration(
        color: AppTheme.pureWhite,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. 模型切换与思考强度控制栏 (扩大版一体化胶囊卡片，自适应防溢出)
          _buildCombinedModelThinkingCard(
            activeProvider,
            activeModel,
            currentEffort,
          ),
          const SizedBox(height: 12),

          // 2. 消息输入框与发送按钮 (IntrinsicHeight + stretch 像素级高度对齐)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.enter):
                          _handleSend,
                    },
                    child: TextField(
                      controller: _inputController,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppTheme.textPrimary,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入绘画构思，或输入 /nai <词> 快速生图...',
                        fillColor: AppTheme.paperWarmth,
                        filled: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          borderSide: const BorderSide(color: AppTheme.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(
                            AppTheme.radiusButton,
                          ),
                          borderSide: const BorderSide(
                            color: AppTheme.notionBlue,
                            width: 1.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Material(
                    color: isStreaming
                        ? AppTheme.stone.withValues(alpha: 0.5)
                        : AppTheme.notionBlue,
                    borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    child: InkWell(
                      onTap: isStreaming ? null : _handleSend,
                      borderRadius: BorderRadius.circular(
                        AppTheme.radiusButton,
                      ),
                      child: Center(
                        child: isStreaming
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white,
                                  ),
                                ),
                              )
                            : const Icon(
                                Icons.send_rounded,
                                size: 17,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 一体化模型与思考强度控制卡片 (单卡片容器 + 自适应弹性宽度 + 防溢出截断)
  Widget _buildCombinedModelThinkingCard(
    LlmProviderConfig activeProvider,
    LlmModelConfig activeModel,
    ThinkingEffort currentEffort,
  ) {
    final models = activeProvider.models;
    final currentModelId = models.any((m) => m.id == activeModel.id)
        ? activeModel.id
        : (models.isNotEmpty ? models.first.id : null);

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          // 1. 模型选择区 (Expanded 弹性自适应，长文本自动省略；悬停显示会话用量)
          Expanded(
            child: Tooltip(
              message: _buildSessionUsageTooltip(),
              waitDuration: const Duration(milliseconds: 400),
              textStyle: const TextStyle(
                fontSize: 11,
                color: AppTheme.textPrimary,
                height: 1.5,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentModelId,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: AppTheme.pureWhite,
                  icon: const Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: AppTheme.textSecondary,
                  ),
                  selectedItemBuilder: (context) {
                    return models.map((m) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.smart_toy_outlined,
                            size: 14.5,
                            color: AppTheme.stone,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                          if (m.isMultimodal) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.visibility_outlined,
                              size: 12.5,
                              color: AppTheme.success,
                            ),
                          ],
                          if (m.supportsThinking) ...[
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.psychology_outlined,
                              size: 12.5,
                              color: AppTheme.notionBlue,
                            ),
                          ],
                        ],
                      );
                    }).toList();
                  },
                  menuMaxHeight: 400.0,
                  borderRadius: BorderRadius.circular(8),
                  items: models.map((m) {
                    return DropdownMenuItem(
                      value: m.id,
                      child: Tooltip(
                        message: m.name,
                        waitDuration: const Duration(milliseconds: 500),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.smart_toy_outlined,
                              size: 14.5,
                              color: AppTheme.stone,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                m.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                            if (m.isMultimodal) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.visibility_outlined,
                                size: 12.5,
                                color: AppTheme.success,
                              ),
                            ],
                            if (m.supportsThinking) ...[
                              const SizedBox(width: 4),
                              const Icon(
                                Icons.psychology_outlined,
                                size: 12.5,
                                color: AppTheme.notionBlue,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (modelId) {
                    if (modelId != null) {
                      widget.viewModel.switchActiveModel(modelId);
                    }
                  },
                ),
              ),
            ),
          ),

          // 2. 思考强度控制区 (同在一个卡片内，以垂直细线分隔)
          if (activeModel.supportsThinking) ...[
            Container(
              width: 1,
              height: 18,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              color: AppTheme.border,
            ),
            _buildInlineThinkingButtons(activeModel, currentEffort),
          ],
        ],
      ),
    );
  }

  /// 一体化卡片内部的思考强度切换按钮组
  Widget _buildInlineThinkingButtons(
    LlmModelConfig model,
    ThinkingEffort currentEffort,
  ) {
    final availableLevels = model.supportedThinkingLevels.isNotEmpty
        ? [ThinkingEffort.off, ...model.supportedThinkingLevels]
        : [
            ThinkingEffort.off,
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
          ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(
          Icons.psychology_outlined,
          size: 13.5,
          color: AppTheme.notionBlue,
        ),
        const SizedBox(width: 4),
        const Text(
          '思考:',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(width: 3),
        ...availableLevels.map((effort) {
          final isSelected = currentEffort == effort;
          return InkWell(
            onTap: () => widget.viewModel.setThinkingEffort(effort),
            borderRadius: BorderRadius.circular(AppTheme.radiusPill),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? AppTheme.notionBlue : Colors.transparent,
                borderRadius: BorderRadius.circular(AppTheme.radiusPill),
              ),
              child: Text(
                effort == ThinkingEffort.off
                    ? '关'
                    : effort == ThinkingEffort.low
                    ? '低'
                    : effort == ThinkingEffort.medium
                    ? '中'
                    : '高',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected ? Colors.white : AppTheme.textSecondary,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// 悬停模型选择器时展示的当前会话用量摘要
  String _buildSessionUsageTooltip() {
    final usage = widget.viewModel.sessionModelUsage;
    if (usage.isEmpty) return '当前会话暂无 Token 用量记录';

    final entries = usage.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final buffer = StringBuffer('当前会话 Token 用量');
    for (final entry in entries) {
      final u = entry.value;
      final detail = StringBuffer(
        '输入 ${UsageLedgerService.formatTokens(u.input)} · '
        '输出 ${UsageLedgerService.formatTokens(u.output)} · '
        '总计 ${UsageLedgerService.formatTokens(u.total)}',
      );
      if (u.cacheRead > 0) {
        final rate = u.cacheHitRate;
        detail.write(
          ' · 缓存读 ${UsageLedgerService.formatTokens(u.cacheRead)}'
          '${rate != null ? ' (${(rate * 100).toStringAsFixed(1)}%)' : ''}',
        );
      }
      buffer.write('\n${entry.key}\n${detail.toString()}');
    }
    return buffer.toString();
  }
}
