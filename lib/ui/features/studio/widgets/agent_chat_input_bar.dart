import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import 'chat_image_attachment.dart';
import 'slash_command_overlay.dart';
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

/// 输入栏待发送图片附件：归一化后的 PNG 字节 (缩略图用) + 消息模型
class _PendingAttachment {
  final Uint8List bytes;
  final AgentMessageImage image;
  const _PendingAttachment({required this.bytes, required this.image});
}

class _AgentChatInputBarState extends State<AgentChatInputBar> {
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final GlobalKey _inputFieldKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayController = OverlayPortalController();

  /// 待发送图片附件 (粘贴/选择文件后暂存)
  final List<_PendingAttachment> _pendingAttachments = [];

  /// 图片归一化进行中 (缩略图栏显示处理指示)
  bool _processingImage = false;

  /// 当前展示的斜杠指令补全建议
  List<SlashSuggestion> _suggestions = const [];
  int _selectedIndex = 0;

  /// 按 Esc 后记录当前输入，避免同类补全立即重新弹出
  String _dismissedToken = '';

  /// 输入框实测宽度 (帧后回调中缓存，禁止在 build/layout 阶段读 size)
  double _fieldWidth = 320.0;

  @override
  void initState() {
    super.initState();
    _inputController.text = widget.viewModel.chatDraft;
    _inputController.addListener(_handleDraftChanged);
    _inputController.addListener(_updateSlashSuggestions);
    _inputFocusNode.addListener(_handleInputFocusChanged);
    // 焦点节点自身拦截 Ctrl+V：剪贴板无文本时尝试读取图片附件。
    // 挂在焦点节点 (冒泡链最内层) 保证先于 TextField 默认粘贴快捷键生效。
    _inputFocusNode.onKeyEvent = _handleInputNodeKeyEvent;
  }

  @override
  void didUpdateWidget(covariant AgentChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.chatDraft != oldWidget.viewModel.chatDraft &&
        widget.viewModel.chatDraft != _inputController.text) {
      _inputController.text = widget.viewModel.chatDraft;
    }
  }

  @override
  void dispose() {
    _inputController.removeListener(_handleDraftChanged);
    _inputController.removeListener(_updateSlashSuggestions);
    _inputFocusNode.removeListener(_handleInputFocusChanged);
    _inputController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    widget.viewModel.updateChatDraft(_inputController.text);
  }

  /// 失焦时收起补全面板，重新聚焦时按当前文本重算
  void _handleInputFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      _updateSlashSuggestions();
    } else {
      _hideSuggestions();
    }
  }

  void _handleSend() {
    // 流式生成中不重复发送，避免双监听把同一缓冲写出重复文本
    if (widget.viewModel.isChatStreaming) return;
    final text = _inputController.text.trim();
    final attachments = List<_PendingAttachment>.of(_pendingAttachments);
    if (text.isEmpty && attachments.isEmpty) return;

    // 图片附件需要当前模型具备视觉能力
    if (attachments.isNotEmpty && !_isActiveModelMultimodal()) {
      _showNotice(context.l10n.chatModelNoVisionNotice);
      return;
    }

    _inputController.clear();
    widget.viewModel.updateChatDraft('');
    setState(() => _pendingAttachments.clear());
    widget.viewModel.sendChatMessage(
      text,
      images: attachments.isEmpty
          ? null
          : [for (final a in attachments) a.image],
    );
    widget.onSent?.call();
  }

  /// 当前激活模型是否支持图片输入
  bool _isActiveModelMultimodal() =>
      widget.viewModel.config.activeLlmProvider.activeModel.isMultimodal;

  void _showNotice(String message) {
    final colors = context.colors;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
            style: TextStyle(fontSize: 13, color: colors.cardBackground),
          ),
          backgroundColor: colors.textPrimary,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  // ------------------ 图片附件 (粘贴 / 选择文件) ------------------

  /// 焦点节点按键拦截：仅拦截 Ctrl+V，其余交给默认链路
  KeyEventResult _handleInputNodeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        HardwareKeyboard.instance.isControlPressed) {
      _handlePaste();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 粘贴：剪贴板有文本时按默认行为插入光标处；
  /// 无文本时读取剪贴板图片并加入待发送附件 (截图/网页图片直接 Ctrl+V)
  Future<void> _handlePaste() async {
    final textData = await Clipboard.getData('text/plain');
    final text = textData?.text;
    if (text != null && text.isNotEmpty) {
      final value = _inputController.value;
      final sel = value.selection;
      String newText;
      int cursor;
      if (sel.isValid && !sel.isCollapsed) {
        newText = value.text.replaceRange(sel.start, sel.end, text);
        cursor = sel.start + text.length;
      } else {
        final offset = sel.isValid ? sel.baseOffset : value.text.length;
        newText = value.text.replaceRange(offset, offset, text);
        cursor = offset + text.length;
      }
      _inputController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: cursor),
      );
      return;
    }

    final imageBytes = await Pasteboard.image;
    if (imageBytes == null || imageBytes.isEmpty) return;
    await _addImageAttachment(imageBytes);
  }

  /// 📎 按钮选择本地图片文件
  Future<void> _pickImageFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      allowMultiple: true,
      withData: true,
    );
    if (result == null) return;
    for (final file in result.files) {
      final bytes = file.bytes;
      if (bytes == null || bytes.isEmpty) continue;
      await _addImageAttachment(bytes);
    }
  }

  /// 归一化并加入待发送附件；超上限或解码失败时提示
  Future<void> _addImageAttachment(Uint8List rawBytes) async {
    if (_pendingAttachments.length >= kMaxChatImageAttachments) {
      _showNotice(
        context.l10n.chatMaxAttachmentsNotice(kMaxChatImageAttachments),
      );
      return;
    }

    setState(() => _processingImage = true);
    final image = await processImageAttachment(rawBytes);
    if (!mounted) return;
    setState(() => _processingImage = false);

    if (image == null) {
      _showNotice(context.l10n.chatImageParseFailedNotice);
      return;
    }
    setState(() {
      _pendingAttachments.add(
        _PendingAttachment(bytes: image.bytes, image: image),
      );
    });
    if (!_isActiveModelMultimodal()) {
      _showNotice(context.l10n.chatModelNoVisionBeforeSendNotice);
    }
  }

  /// 待发送附件缩略图栏 (输入框上方，有附件或处理中才显示)
  Widget _buildAttachmentPreview() {
    if (_pendingAttachments.isEmpty && !_processingImage) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: SizedBox(
        height: 72,
        child: ListView(
          scrollDirection: Axis.horizontal,
          children: [
            for (final attachment in _pendingAttachments)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: ChatImageThumbnail(
                  bytes: attachment.bytes,
                  onRemove: () {
                    setState(() => _pendingAttachments.remove(attachment));
                  },
                ),
              ),
            if (_processingImage)
              const SizedBox(
                width: 64,
                height: 64,
                child: Center(
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ------------------ 斜杠指令自动补全 ------------------

  /// 文本或光标变化时重算补全建议 (仅光标位于末尾时展示，避免编辑中段干扰)
  void _updateSlashSuggestions() {
    if (!mounted) return;
    final text = _inputController.text;
    final cursor = _inputController.selection.baseOffset;
    if (!text.startsWith('/') || cursor != text.length) {
      _hideSuggestions();
      return;
    }

    final suggestions = buildSlashSuggestions(
      text: text,
      skills: widget.viewModel.availableSkills,
      presets: widget.viewModel.presets,
      l10n: context.maybeL10n,
    );
    if (suggestions.isEmpty || text == _dismissedToken) {
      _hideSuggestions();
      return;
    }

    final width = _inputFieldKey.currentContext?.size?.width;
    setState(() {
      _suggestions = suggestions;
      if (width != null && width > 0) {
        _fieldWidth = width;
      }
      if (_selectedIndex >= suggestions.length) _selectedIndex = 0;
    });
    _measureFieldWidth();
    if (!_overlayController.isShowing) _overlayController.show();
  }

  /// 帖后回调里测量输入框宽度并缓存 (size 只能在布局完成后读取)
  void _measureFieldWidth() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final width = _inputFieldKey.currentContext?.size?.width;
      if (width != null && width > 0 && width != _fieldWidth) {
        setState(() => _fieldWidth = width);
      }
    });
  }

  void _hideSuggestions() {
    if (!mounted) return;
    if (_overlayController.isShowing) _overlayController.hide();
    if (_suggestions.isEmpty) return;
    setState(() {
      _suggestions = const [];
      _selectedIndex = 0;
    });
  }

  /// 补全面板打开时拦截方向键/Tab/Enter/Esc
  KeyEventResult _handleSlashKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (_suggestions.isEmpty) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % _suggestions.length;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex =
            (_selectedIndex - 1 + _suggestions.length) % _suggestions.length;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter) {
      _applySuggestion(_suggestions[_selectedIndex]);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _dismissedToken = _inputController.text;
      _hideSuggestions();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 应用补全: 替换指令名或第一个参数，并在末尾追加空格
  void _applySuggestion(SlashSuggestion suggestion) {
    final text = _inputController.text;
    final spaceIdx = text.indexOf(' ');
    final newText = spaceIdx == -1
        ? '${suggestion.completion} '
        : '${text.substring(0, spaceIdx)} ${suggestion.completion} ';
    _inputController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newText.length),
    );
    _dismissedToken = '';
    _hideSuggestions();
    _inputFocusNode.requestFocus();
  }

  /// 悬浮于输入框上方的补全面板 (Overlay + Follower 锚定)
  Widget _buildSlashOverlay(BuildContext overlayContext) {
    if (_suggestions.isEmpty) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topLeft,
      child: CompositedTransformFollower(
        link: _layerLink,
        targetAnchor: Alignment.topLeft,
        followerAnchor: Alignment.bottomLeft,
        offset: const Offset(0, -6),
        showWhenUnlinked: false,
        child: SizedBox(
          width: _fieldWidth,
          child: SlashSuggestionPanel(
            suggestions: _suggestions,
            selectedIndex: _selectedIndex,
            onSelected: (index) => _applySuggestion(_suggestions[index]),
            onHovered: (index) {
              if (index != _selectedIndex) {
                setState(() => _selectedIndex = index);
              }
            },
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final isStreaming = widget.viewModel.isChatStreaming;
    final activeProvider = widget.viewModel.config.activeLlmProvider;
    final activeModel = activeProvider.activeModel;
    final currentEffort = widget.viewModel.currentThinkingEffort;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(top: BorderSide(color: colors.borderDefault)),
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

          // 斜杠指令补全悬浮层 (渲染到根 Overlay，锚定在输入框上方)
          OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: _buildSlashOverlay,
          ),

          // 待发送图片附件缩略图栏 (粘贴/选择文件后显示)
          _buildAttachmentPreview(),

          // 2. 消息输入框与发送按钮 (IntrinsicHeight + stretch 像素级高度对齐)
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: CompositedTransformTarget(
                    link: _layerLink,
                    child: Focus(
                      onKeyEvent: _handleSlashKey,
                      child: CallbackShortcuts(
                        bindings: {
                          const SingleActivator(LogicalKeyboardKey.enter):
                              _handleSend,
                        },
                        child: TextField(
                          key: _inputFieldKey,
                          controller: _inputController,
                          focusNode: _inputFocusNode,
                          minLines: 1,
                          maxLines: 4,
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText: context.l10n.chatInputHint,
                            hintStyle: TextStyle(
                              fontSize: 13,
                              color: colors.textMuted,
                            ),
                            fillColor: colors.canvasBackground,
                            hoverColor: colors.canvasBackground,
                            filled: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: BorderSide(
                                color: colors.borderDefault,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: BorderSide(
                                color: colors.borderDefault,
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(AppRadius.md),
                              borderSide: BorderSide(
                                color: colors.primary,
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // 📎 选择本地图片文件 (多模态参考图)
                AspectRatio(
                  aspectRatio: 1.0,
                  child: Tooltip(
                    message: context.l10n.chatAddAttachmentTooltip,
                    child: Material(
                      color: colors.cardBackground,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: InkWell(
                        onTap: _pickImageFiles,
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: Center(
                          child: Icon(
                            Icons.attach_file_rounded,
                            size: 17,
                            color: colors.textSecondary,
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
                        ? colors.textMuted.withValues(alpha: 0.5)
                        : colors.primary,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    child: InkWell(
                      onTap: isStreaming ? null : _handleSend,
                      borderRadius: BorderRadius.circular(AppRadius.md),
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
    final colors = context.colors;
    final models = activeProvider.models;
    final currentModelId = models.any((m) => m.id == activeModel.id)
        ? activeModel.id
        : (models.isNotEmpty ? models.first.id : null);

    return Container(
      height: 38,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        children: [
          // 1. 模型选择区 (Expanded 弹性自适应，长文本自动省略；悬停显示会话用量)
          Expanded(
            child: Tooltip(
              message: _buildSessionUsageTooltip(context.l10n),
              waitDuration: const Duration(milliseconds: 400),
              textStyle: TextStyle(
                fontSize: 11,
                color: colors.textPrimary,
                height: 1.5,
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentModelId,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: colors.cardBackground,
                  icon: Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  selectedItemBuilder: (context) {
                    return models.map((m) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.smart_toy_outlined,
                            size: 15,
                            color: colors.textMuted,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              m.name,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                          if (m.isMultimodal) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.visibility_outlined,
                              size: 13,
                              color: colors.success,
                            ),
                          ],
                          if (m.supportsThinking) ...[
                            const SizedBox(width: 4),
                            Icon(
                              Icons.psychology_outlined,
                              size: 13,
                              color: colors.primary,
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
                            Icon(
                              Icons.smart_toy_outlined,
                              size: 15,
                              color: colors.textMuted,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                m.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                            if (m.isMultimodal) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.visibility_outlined,
                                size: 13,
                                color: colors.success,
                              ),
                            ],
                            if (m.supportsThinking) ...[
                              const SizedBox(width: 4),
                              Icon(
                                Icons.psychology_outlined,
                                size: 13,
                                color: colors.primary,
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
              color: colors.borderDefault,
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
        Icon(
          Icons.psychology_outlined,
          size: 14,
          color: context.colors.primary,
        ),
        const SizedBox(width: 4),
        Text(
          context.l10n.chatThinkingLabel,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.colors.textPrimary,
          ),
        ),
        const SizedBox(width: 3),
        ...availableLevels.map((effort) {
          final isSelected = currentEffort == effort;
          return InkWell(
            onTap: () => widget.viewModel.setThinkingEffort(effort),
            borderRadius: BorderRadius.circular(AppRadius.pill),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 1.5),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
              decoration: BoxDecoration(
                color: isSelected ? context.colors.primary : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.pill),
              ),
              child: Text(
                switch (effort) {
                  ThinkingEffort.off => context.l10n.chatThinkingEffortOff,
                  ThinkingEffort.low => context.l10n.chatThinkingEffortLow,
                  ThinkingEffort.medium =>
                    context.l10n.chatThinkingEffortMedium,
                  ThinkingEffort.high => context.l10n.chatThinkingEffortHigh,
                },
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  color: isSelected
                      ? Colors.white
                      : context.colors.textSecondary,
                ),
              ),
            ),
          );
        }),
      ],
    );
  }

  /// 悬停模型选择器时展示的当前会话用量摘要
  String _buildSessionUsageTooltip(AppLocalizations l10n) {
    final usage = widget.viewModel.sessionModelUsage;
    if (usage.isEmpty) return l10n.chatSessionUsageEmpty;

    final entries = usage.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    final buffer = StringBuffer(l10n.chatSessionUsageTitle);
    for (final entry in entries) {
      final u = entry.value;
      final detail = StringBuffer(
        l10n.chatSessionUsageDetail(
          UsageLedgerService.formatTokens(u.input),
          UsageLedgerService.formatTokens(u.output),
          UsageLedgerService.formatTokens(u.total),
        ),
      );
      if (u.cacheRead > 0) {
        final rate = u.cacheHitRate;
        if (rate != null) {
          detail.write(
            l10n.chatSessionUsageCacheReadWithRate(
              UsageLedgerService.formatTokens(u.cacheRead),
              (rate * 100).toStringAsFixed(1),
            ),
          );
        } else {
          detail.write(
            l10n.chatSessionUsageCacheRead(
              UsageLedgerService.formatTokens(u.cacheRead),
            ),
          );
        }
      }
      buffer.write('\n${entry.key}\n${detail.toString()}');
    }
    return buffer.toString();
  }
}
