import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../../data/services/prompt_library_mention.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_async_icon_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/overlay_anchor.dart';
import '../../../core/widgets/stable_edge_selection.dart';
import 'character_mention_overlay.dart';
import 'chat_context_status.dart';
import 'chat_image_attachment.dart';
import 'slash_command_overlay.dart';
import '../view_models/studio_view_model.dart';

/// 思考等级档位本地化展示名
String _localizedEffortLabel(AppLocalizations l10n, ThinkingEffort effort) =>
    switch (effort) {
      ThinkingEffort.none => l10n.chatThinkingEffortNone,
      ThinkingEffort.low => l10n.chatThinkingEffortLow,
      ThinkingEffort.medium => l10n.chatThinkingEffortMedium,
      ThinkingEffort.high => l10n.chatThinkingEffortHigh,
      ThinkingEffort.xhigh => l10n.chatThinkingEffortXHigh,
      ThinkingEffort.max => l10n.chatThinkingEffortMax,
    };

/// Agent 对话卡底部一体化输入与控制区 (桌面/移动端统一):
/// 图片附件预览 + 多行文本输入框 + 底部内嵌工具栏 (附件 / 模型与思考选择器 / 上下文 / 发送停止)
class AgentChatInputBar extends StatefulWidget {
  final StudioViewModel viewModel;
  final bool compact;

  /// 发送成功后的回调 (用于滚动到消息流底部)
  final VoidCallback? onSent;

  const AgentChatInputBar({
    super.key,
    required this.viewModel,
    this.onSent,
    this.compact = false,
  });

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
  final ScrollController _inputScrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  final GlobalKey _inputFieldKey = GlobalKey();
  final LayerLink _layerLink = LayerLink();
  final OverlayPortalController _overlayController = OverlayPortalController();

  /// 待发送图片附件 (粘贴/选择文件后暂存)
  final List<_PendingAttachment> _pendingAttachments = [];

  /// 图片归一化进行中 (缩略图栏显示处理指示)
  bool _processingImage = false;

  /// 当前展示的斜杠指令或 `@` 角色补全建议与面板开关态（支持关闭退场动效）
  List<SlashSuggestion> _suggestions = const [];
  List<PromptComboEntry> _mentionSuggestions = const [];
  ActiveCharacterMention? _activeMention;
  bool _suggestionsVisible = false;
  int _selectedIndex = 0;

  /// 模型与思考档位浮层是否打开（用于驱动触发器箭头翻转）
  bool _pickerOpen = false;

  /// 按 Esc 后记录当前输入，避免同类补全立即重新弹出
  String _dismissedToken = '';

  /// 输入框实测宽度 (帧后回调中缓存，禁止在 build/layout 阶段读 size)
  double _fieldWidth = 320.0;

  /// 已套用的回溯草稿代数，避免同一轮恢复被重复写进输入框。
  int _appliedRestoreEpoch = 0;

  /// 已排进帧后回调、尚未写入输入框的回溯代数。
  int? _scheduledRestoreEpoch;

  /// 已套用的词库角色插入代数，避免重复插入。
  int _appliedInsertionEpoch = 0;

  /// 已排进帧后回调的词库角色插入代数。
  int? _scheduledInsertionEpoch;

  @override
  void initState() {
    super.initState();
    final restore = widget.viewModel.composerRestore;
    if (restore != null) {
      _appliedRestoreEpoch = restore.epoch;
      _inputController.value = TextEditingValue(
        text: restore.text,
        selection: TextSelection.collapsed(offset: restore.text.length),
      );
      _pendingAttachments.addAll(_attachmentsFrom(restore.images));
      widget.viewModel.acknowledgeComposerRestore(restore.epoch);
      _scheduleComposerFocus();
    } else {
      final draft = widget.viewModel.chatDraft;
      _inputController.value = TextEditingValue(
        text: draft,
        selection: TextSelection.collapsed(offset: draft.length),
      );
      final insertion = widget.viewModel.composerInsertion;
      if (insertion != null) {
        _appliedInsertionEpoch = insertion.epoch;
        widget.viewModel.acknowledgeComposerInsertion(insertion.epoch);
        if (insertion.focus) {
          _scheduleComposerFocus();
          _scheduleRevealCaret();
        }
      }
    }
    _inputController.addListener(_handleDraftChanged);
    _inputController.addListener(_updateComposerSuggestions);
    _inputFocusNode.addListener(_handleInputFocusChanged);
    widget.viewModel.promptLibraryNotifier.addListener(_onPromptLibraryChanged);
    // 焦点节点自身拦截 Ctrl+V：剪贴板无文本时尝试读取图片附件。
    // 挂在焦点节点 (冒泡链最内层) 保证先于 TextField 默认粘贴快捷键生效。
    _inputFocusNode.onKeyEvent = _handleInputNodeKeyEvent;
  }

  @override
  void didUpdateWidget(covariant AgentChatInputBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    final restore = widget.viewModel.composerRestore;
    if (restore != null && restore.epoch != _appliedRestoreEpoch) {
      // 回溯发生在本栏已挂载时 (例如 /undo)：等本帧布局结束后再改控制器，
      // 避免在 build 期间改文本触发补全 setState。
      if (_scheduledRestoreEpoch != restore.epoch) {
        final epoch = restore.epoch;
        _scheduledRestoreEpoch = epoch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scheduledRestoreEpoch = null;
          final current = widget.viewModel.composerRestore;
          if (current == null || current.epoch != epoch) return;
          _appliedRestoreEpoch = epoch;
          _applyComposerRestore(current);
        });
      }
      return;
    }

    final insertion = widget.viewModel.composerInsertion;
    if (insertion != null && insertion.epoch != _appliedInsertionEpoch) {
      if (_scheduledInsertionEpoch != insertion.epoch) {
        final epoch = insertion.epoch;
        _scheduledInsertionEpoch = epoch;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _scheduledInsertionEpoch = null;
          final current = widget.viewModel.composerInsertion;
          if (current == null || current.epoch != epoch) return;
          _appliedInsertionEpoch = epoch;
          _applyComposerInsertion(current);
        });
      }
      return;
    }

    if (widget.viewModel.chatDraft != oldWidget.viewModel.chatDraft &&
        widget.viewModel.chatDraft != _inputController.text) {
      _inputController.text = widget.viewModel.chatDraft;
    }
  }

  void _applyComposerInsertion(ComposerInsertion insertion) {
    final currentText = _inputController.text;
    final draft = widget.viewModel.chatDraft;
    final nextText = currentText == draft
        ? currentText
        : (draft.endsWith(insertion.text)
              ? draft
              : '$currentText${insertion.text}');
    _inputController.value = TextEditingValue(
      text: nextText,
      selection: TextSelection.collapsed(offset: nextText.length),
    );
    widget.viewModel.acknowledgeComposerInsertion(insertion.epoch);
    if (insertion.focus) {
      _scheduleComposerFocus();
    }
    _scheduleRevealCaret();
  }

  void _onPromptLibraryChanged() {
    if (!mounted) return;
    _updateComposerSuggestions();
  }

  void _applyComposerRestore(ComposerRestore restore) {
    _inputController.value = TextEditingValue(
      text: restore.text,
      selection: TextSelection.collapsed(offset: restore.text.length),
    );
    setState(() {
      _pendingAttachments
        ..clear()
        ..addAll(_attachmentsFrom(restore.images));
    });
    widget.viewModel.acknowledgeComposerRestore(restore.epoch);
    _scheduleComposerFocus();
    _scheduleRevealCaret();
  }

  List<_PendingAttachment> _attachmentsFrom(List<AgentMessageImage> images) {
    final result = <_PendingAttachment>[];
    for (final image in images) {
      if (image.base64.isEmpty) continue;
      if (result.length >= kMaxChatImageAttachments) break;
      result.add(_PendingAttachment(bytes: image.bytes, image: image));
    }
    return result;
  }

  void _scheduleComposerFocus() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _inputFocusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _inputController.removeListener(_handleDraftChanged);
    _inputController.removeListener(_updateComposerSuggestions);
    _inputFocusNode.removeListener(_handleInputFocusChanged);
    widget.viewModel.promptLibraryNotifier.removeListener(
      _onPromptLibraryChanged,
    );
    _inputController.dispose();
    _inputScrollController.dispose();
    _inputFocusNode.dispose();
    super.dispose();
  }

  void _handleDraftChanged() {
    widget.viewModel.updateChatDraft(_inputController.text);
  }

  /// 失焦时收起补全面板，重新聚焦时按当前文本重算
  void _handleInputFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      _updateComposerSuggestions();
    } else {
      _hideSuggestions();
    }
  }

  bool get _isComposing {
    final range = _inputController.value.composing;
    return range.isValid && !range.isCollapsed;
  }

  KeyEventResult _handleMessageKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.enter ||
        _isComposing) {
      return KeyEventResult.ignored;
    }
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    if (keyboard.isShiftPressed) {
      _insertTextAtSelection('\n');
      return KeyEventResult.handled;
    }
    // 生成中 Enter 仍表示发送，但不把草稿发出去，也不当成停止。
    // 停止用原发送键位置上的停止按钮，或 Esc。
    if (widget.viewModel.isChatStreaming) {
      return KeyEventResult.handled;
    }
    _handleSend();
    return KeyEventResult.handled;
  }

  void _handleSend() {
    if (_isComposing) return;
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
    showAppToast(
      context,
      message: message,
      tone: AppToastTone.warning,
      duration: const Duration(seconds: 2),
      enableBlur: false,
    );
  }

  // ------------------ 图片附件 (粘贴 / 选择文件) ------------------

  /// 焦点节点按键拦截：仅拦截 Ctrl+V，其余交给默认链路
  KeyEventResult _handleInputNodeKeyEvent(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.keyV &&
        (Theme.of(context).platform == TargetPlatform.macOS
            ? HardwareKeyboard.instance.isMetaPressed
            : HardwareKeyboard.instance.isControlPressed)) {
      _handlePaste();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  EditableTextState? _findEditableText() {
    final root = _inputFieldKey.currentContext;
    if (root is! Element) return null;
    EditableTextState? found;
    void visit(Element element) {
      if (found != null) return;
      if (element is StatefulElement && element.state is EditableTextState) {
        found = element.state as EditableTextState;
        return;
      }
      element.visitChildren(visit);
    }

    visit(root);
    return found;
  }

  void _scheduleRevealCaret() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_inputScrollController.hasClients) return;
      final editable = _findEditableText();
      final selection = _inputController.selection;
      if (editable == null || !editable.mounted || !selection.isValid) return;
      editable.bringIntoView(selection.extent);
    });
  }

  void _insertTextAtSelection(String text) {
    final value = _inputController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextValue = TextEditingValue(
      text: value.text.replaceRange(start, end, text),
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    final editable = _findEditableText();
    if (editable != null && editable.mounted) {
      editable.userUpdateTextEditingValue(
        nextValue,
        SelectionChangedCause.keyboard,
      );
    } else {
      _inputController.value = nextValue;
    }
    _scheduleRevealCaret();
  }

  /// 粘贴：剪贴板有文本时按默认行为插入光标处；
  /// 无文本时读取剪贴板图片并加入待发送附件 (截图/网页图片直接 Ctrl+V)
  Future<void> _handlePaste() async {
    final textData = await Clipboard.getData('text/plain');
    if (!mounted) return;
    final text = textData?.text;
    if (text != null && text.isNotEmpty) {
      _insertTextAtSelection(text);
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

  /// 待发送附件缩略图栏 (输入框内部顶部，有附件或处理中时平滑展开)
  Widget _buildAttachmentPreview() {
    final colors = context.colors;
    final hasContent = _pendingAttachments.isNotEmpty || _processingImage;
    return AppPanelReveal(
      visible: hasContent,
      openDuration: AppMotionDurations.fast,
      closeDuration: AppMotionDurations.quick,
      slideOffset: AppMotionDistances.base,
      enableBlur: false,
      animateSize: true,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.md,
          AppSpacing.sm,
          AppSpacing.md,
          AppSpacing.xs,
        ),
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
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Center(
                    child: AppMatrixDotLoader(
                      variant: AppMatrixDotVariant.pulse,
                      rounded: true,
                      dotSize: 2.5,
                      gap: 2.0,
                      baseColor: colors.primary.withValues(alpha: 0.25),
                      activeColor: colors.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------ 斜杠指令与 @ 角色自动补全 ------------------

  /// 文本或光标变化时重算补全建议 (支持 `/` 斜杠指令与 `@` 词库角色)
  void _updateComposerSuggestions() {
    if (!mounted) return;
    final text = _inputController.text;
    final selection = _inputController.selection;
    final cursor = selection.isValid && selection.isCollapsed
        ? selection.baseOffset
        : -1;

    if (text == _dismissedToken) {
      _hideSuggestions();
      return;
    }

    // 1. 斜杠指令补全 (仅光标位于末尾时展示)
    if (text.startsWith('/') && cursor == text.length) {
      final suggestions = buildSlashSuggestions(
        text: text,
        skills: widget.viewModel.availableSkills,
        presets: widget.viewModel.presets,
        l10n: context.maybeL10n,
      );
      if (suggestions.isNotEmpty) {
        final width = _inputFieldKey.currentContext?.size?.width;
        setState(() {
          _suggestions = suggestions;
          _mentionSuggestions = const [];
          _activeMention = null;
          _suggestionsVisible = true;
          if (width != null && width > 0) {
            _fieldWidth = width;
          }
          if (_selectedIndex >= suggestions.length) _selectedIndex = 0;
        });
        _measureFieldWidth();
        if (!_overlayController.isShowing) _overlayController.show();
        return;
      }
    }

    // 2. `@` 词库角色补全
    if (cursor >= 1) {
      final mention = extractActiveCharacterMention(text, cursor);
      if (mention != null) {
        final matched = matchCharacterMentionSuggestions(
          mention.query,
          widget.viewModel.promptLibraryEntries,
        );
        if (matched.isNotEmpty) {
          final width = _inputFieldKey.currentContext?.size?.width;
          setState(() {
            _suggestions = const [];
            _mentionSuggestions = matched;
            _activeMention = mention;
            _suggestionsVisible = true;
            if (width != null && width > 0) {
              _fieldWidth = width;
            }
            if (_selectedIndex >= matched.length) _selectedIndex = 0;
          });
          _measureFieldWidth();
          if (!_overlayController.isShowing) _overlayController.show();
          return;
        }
      }
    }

    _hideSuggestions();
  }

  /// 帧后回调里测量输入框宽度并缓存 (size 只能在布局完成后读取)
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
    if (!_suggestionsVisible && !_overlayController.isShowing) return;
    if (AppMotion.shouldReduceMotion(context) || !_overlayController.isShowing) {
      if (_overlayController.isShowing) _overlayController.hide();
      if (_suggestions.isNotEmpty ||
          _mentionSuggestions.isNotEmpty ||
          _suggestionsVisible) {
        setState(() {
          _suggestions = const [];
          _mentionSuggestions = const [];
          _activeMention = null;
          _suggestionsVisible = false;
          _selectedIndex = 0;
        });
      }
      return;
    }
    setState(() => _suggestionsVisible = false);
  }

  void _handleSlashOverlayDismissed() {
    if (!mounted || _suggestionsVisible) return;
    if (_overlayController.isShowing) _overlayController.hide();
    if (_suggestions.isNotEmpty || _mentionSuggestions.isNotEmpty) {
      setState(() {
        _suggestions = const [];
        _mentionSuggestions = const [];
        _activeMention = null;
        _selectedIndex = 0;
      });
    }
  }

  /// 补全面板打开时拦截方向键/Tab/Enter/Esc
  KeyEventResult _handleComposerSuggestionKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || _isComposing) return KeyEventResult.ignored;
    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isShiftPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final activeCount = _suggestions.isNotEmpty
        ? _suggestions.length
        : _mentionSuggestions.length;
    if (activeCount == 0) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      setState(() {
        _selectedIndex = (_selectedIndex + 1) % activeCount;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      setState(() {
        _selectedIndex = (_selectedIndex - 1 + activeCount) % activeCount;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.tab || key == LogicalKeyboardKey.enter) {
      if (_suggestions.isNotEmpty) {
        _applySuggestion(_suggestions[_selectedIndex]);
      } else if (_mentionSuggestions.isNotEmpty) {
        _applyCharacterMention(_mentionSuggestions[_selectedIndex]);
      }
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.escape) {
      _dismissedToken = _inputController.text;
      _hideSuggestions();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// 应用斜杠补全: 替换指令名或第一个参数，并在末尾追加空格
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
    _scheduleRevealCaret();
  }

  /// 应用 `@` 词库角色补全: 将 `@查询` 替换为 `@[标题] `
  void _applyCharacterMention(PromptComboEntry entry) {
    final text = _inputController.text;
    final cursor = _inputController.selection.isValid
        ? _inputController.selection.baseOffset
        : text.length;
    final mention =
        _activeMention ?? extractActiveCharacterMention(text, cursor);
    if (mention == null) return;

    final inserted = '${formatCharacterMention(entry.title)} ';
    final newText = text.replaceRange(
      mention.atIndex,
      mention.cursorOffset,
      inserted,
    );
    final newOffset = mention.atIndex + inserted.length;
    _inputController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newOffset),
    );
    _dismissedToken = '';
    _hideSuggestions();
    _inputFocusNode.requestFocus();
    _scheduleRevealCaret();
  }

  /// 悬浮于输入框上方的补全面板 (Overlay + Follower 锚定)
  Widget _buildSlashOverlay(BuildContext overlayContext) {
    if (_suggestions.isEmpty && _mentionSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    final Widget panel = _suggestions.isNotEmpty
        ? SlashSuggestionPanel(
            suggestions: _suggestions,
            selectedIndex: _selectedIndex,
            onSelected: (index) => _applySuggestion(_suggestions[index]),
            onHovered: (index) {
              if (index != _selectedIndex) {
                setState(() => _selectedIndex = index);
              }
            },
          )
        : CharacterMentionPanel(
            entries: _mentionSuggestions,
            selectedIndex: _selectedIndex,
            onSelected: (index) =>
                _applyCharacterMention(_mentionSuggestions[index]),
            onHovered: (index) {
              if (index != _selectedIndex) {
                setState(() => _selectedIndex = index);
              }
            },
          );

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
          child: SlashCommandOverlayShell(
            visible: _suggestionsVisible,
            onDismissComplete: _handleSlashOverlayDismissed,
            child: panel,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activeProvider = widget.viewModel.config.activeLlmProvider;
    final activeModel = activeProvider.activeModel;
    final currentEffort = widget.viewModel.currentThinkingEffort;
    final contextStatus = ChatContextStatus(
      usage: widget.viewModel.contextUsage,
      modelName: '${activeProvider.name} · ${activeModel.name}',
      sessionUsage: _buildSessionUsageTooltip(context.l10n),
      compact: widget.compact,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 斜杠指令补全悬浮层 (渲染到根 Overlay，锚定在输入框上方)
          OverlayPortal(
            controller: _overlayController,
            overlayChildBuilder: _buildSlashOverlay,
          ),
          _buildMessageComposer(
            activeProvider: activeProvider,
            activeModel: activeModel,
            currentEffort: currentEffort,
            contextStatus: contextStatus,
          ),
        ],
      ),
    );
  }

  /// 一体化现代聊天输入容器 (桌面/移动端统一): 附件预览 + 多行文本域 + 底部单一聚合工具栏
  /// (附件、合并模型/思考选择器、上下文、发送/停止)。
  Widget _buildMessageComposer({
    required LlmProviderConfig activeProvider,
    required LlmModelConfig activeModel,
    required ThinkingEffort currentEffort,
    required Widget contextStatus,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;
    final field = _buildMessageField();
    final attachment = AppAsyncIconButton(
      isLoading: _processingImage,
      icon: Icons.attach_file_rounded,
      size: 28,
      iconSize: 16,
      tooltip: l10n.chatAddAttachmentTooltip,
      loadingTooltip: l10n.chatAddAttachmentTooltip,
      variant: AppIconButtonVariant.ghost,
      onPressed: _pickImageFiles,
    );
    // 生成中发送键原位变成停止键；仅保留单个激活按钮实例并在状态切换时形变弹入。
    final Widget send = _ComposerActionMorph(
      isStreaming: widget.viewModel.isChatStreaming,
      child: widget.viewModel.isChatStreaming
          ? AppIconButton(
              key: const ValueKey('chat_stop_button'),
              icon: Icons.stop_rounded,
              size: 28,
              iconSize: 15,
              tooltip: widget.compact
                  ? l10n.chatStopOutputMobile
                  : l10n.chatStopOutput,
              iconColor: colors.error,
              variant: AppIconButtonVariant.outlined,
              onPressed: widget.viewModel.abortChat,
            )
          : AppAsyncIconButton(
              key: const ValueKey('chat_send_button'),
              isLoading: false,
              icon: Icons.send_rounded,
              size: 28,
              iconSize: 15,
              tooltip: l10n.chatSendTooltip,
              loadingTooltip: l10n.chatSendingTooltip,
              variant: AppIconButtonVariant.primary,
              onPressed: _handleSend,
            ),
    );

    return ListenableBuilder(
      listenable: _inputFocusNode,
      builder: (context, child) => AppCard(
        radius: AppRadius.lg,
        backgroundColor: colors.elevatedBackground,
        borderColor: _inputFocusNode.hasFocus
            ? colors.primary.withValues(alpha: 0.65)
            : colors.borderDefault,
        child: child!,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAttachmentPreview(),
          _buildLinkedCharactersBar(),
          field,
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 2, 6, 6),
            child: Row(
              children: [
                attachment,
                const SizedBox(width: 4),
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: _buildModelThinkingTrigger(
                      activeModel,
                      currentEffort,
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                contextStatus,
                const SizedBox(width: 4),
                send,
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 已显式关联的词库角色芯片栏（输入栏顶部，有 `@[角色]` 引用时平滑展开）
  Widget _buildLinkedCharactersBar() {
    return ListenableBuilder(
      listenable: Listenable.merge([
        _inputController,
        widget.viewModel.promptLibraryNotifier,
      ]),
      builder: (context, _) {
        final linked = extractLinkedCharacters(
          _inputController.text,
          widget.viewModel.promptLibraryEntries,
        );
        final colors = context.colors;
        final l10n = context.l10n;
        return AppPanelReveal(
          visible: linked.isNotEmpty,
          openDuration: AppMotionDurations.fast,
          closeDuration: AppMotionDurations.quick,
          slideOffset: AppMotionDistances.base,
          enableBlur: false,
          animateSize: true,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in linked)
                  Tooltip(
                    message: entry.prompt,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(7, 3, 4, 3),
                      decoration: BoxDecoration(
                        color: colors.errorSurface,
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.person_outline_rounded,
                            size: 12,
                            color: colors.error,
                          ),
                          const SizedBox(width: 4),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 160),
                            child: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colors.error,
                              ),
                            ),
                          ),
                          const SizedBox(width: 2),
                          Tooltip(
                            message: l10n.chatLinkedCharacterRemoveTooltip,
                            child: GestureDetector(
                              onTap: () {
                                final updated = removeCharacterMention(
                                  _inputController.text,
                                  entry,
                                );
                                _inputController.value = TextEditingValue(
                                  text: updated,
                                  selection: TextSelection.collapsed(
                                    offset: updated.length,
                                  ),
                                );
                              },
                              behavior: HitTestBehavior.opaque,
                              child: Icon(
                                Icons.close_rounded,
                                size: 13,
                                color: colors.error.withValues(alpha: 0.8),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMessageField() {
    final colors = context.colors;
    return CompositedTransformTarget(
      link: _layerLink,
      child: Focus(
        onKeyEvent: _handleMessageKeyEvent,
        // 焦点冒泡先处理补全，避免 Enter 被外层发送快捷键抢走。
        child: Focus(
          onKeyEvent: _handleComposerSuggestionKey,
          child: StableEdgeSelection(
            controller: _inputScrollController,
            child: TextField(
              key: _inputFieldKey,
              controller: _inputController,
              focusNode: _inputFocusNode,
              scrollController: _inputScrollController,
              scrollPadding: EdgeInsets.zero,
              minLines: 2,
              maxLines: 5,
              style: TextStyle(
                fontSize: 13.5,
                height: 1.5,
                color: colors.textPrimary,
              ),
              decoration: InputDecoration(
                hintText: context.l10n.chatInputHint,
                hintStyle: TextStyle(fontSize: 13, color: colors.textMuted),
                isDense: true,
                filled: false,
                contentPadding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 合并模型与思考档位触发胶囊；点击弹出带搜索框的模型与思考切换面板
  Widget _buildModelThinkingTrigger(
    LlmModelConfig activeModel,
    ThinkingEffort currentEffort,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;
    final thinkingColor = currentEffort == ThinkingEffort.none
        ? colors.textMuted
        : colors.primary;

    return Tooltip(
      message: _buildSessionUsageTooltip(l10n),
      child: Builder(
        builder: (triggerContext) => InkWell(
          key: const ValueKey('chat_model_selector'),
          onTap: () => _openModelThinkingPicker(triggerContext),
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 28),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: AppTextSwap(
                      text: activeModel.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      enableBlur: false,
                      duration: AppMotionDurations.quick,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  if (activeModel.supportsThinking) ...[
                    const SizedBox(width: 6),
                    Icon(
                      Icons.psychology_outlined,
                      size: 13,
                      color: thinkingColor,
                    ),
                    const SizedBox(width: 2),
                    AppTextSwap(
                      text: _localizedEffortLabel(l10n, currentEffort),
                      maxLines: 1,
                      enableBlur: false,
                      duration: AppMotionDurations.quick,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: thinkingColor,
                      ),
                    ),
                  ],
                  const SizedBox(width: 2),
                  TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: _pickerOpen ? -1.0 : 1.0),
                    duration: AppMotion.resolveDuration(
                      context,
                      AppMotionDurations.fast,
                    ),
                    curve: AppMotionCurves.smoothOut,
                    builder: (context, scaleY, child) => Transform.scale(
                      scaleX: 1.0,
                      scaleY: scaleY,
                      child: child,
                    ),
                    child: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 15,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openModelThinkingPicker(BuildContext anchorContext) async {
    if (!mounted) return;
    setState(() => _pickerOpen = true);
    try {
      await showAnchoredPopover<void>(
        context: anchorContext,
        preferAbove: true,
        maxWidth: 340,
        maxHeight: 420,
        builder: (_) => _ModelThinkingPickerSheet(viewModel: widget.viewModel),
      );
    } finally {
      if (mounted) {
        setState(() => _pickerOpen = false);
      }
    }
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
          UsageLedgerService.formatTokens(u.totalInput),
          UsageLedgerService.formatTokens(u.output),
          UsageLedgerService.formatTokens(u.total),
        ),
      );
      if (u.cacheRead > 0 || u.cacheReadReported) {
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
      if (!u.cacheReadReported) {
        detail.write(
          ' · ${u.cacheRead > 0 ? l10n.cacheUsagePartial : l10n.cacheUsageUnreported}',
        );
      }
      buffer.write('\n${entry.key}\n${detail.toString()}');
    }
    return buffer.toString();
  }
}

/// 合并的模型与思考档位选择弹窗：含实时搜索框、思考强度分段控制与模型列表
class _ModelThinkingPickerSheet extends StatefulWidget {
  final StudioViewModel viewModel;

  const _ModelThinkingPickerSheet({required this.viewModel});

  @override
  State<_ModelThinkingPickerSheet> createState() =>
      _ModelThinkingPickerSheetState();
}

class _ModelThinkingPickerSheetState extends State<_ModelThinkingPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final activeProvider = widget.viewModel.config.activeLlmProvider;
        final activeModel = activeProvider.activeModel;
        final currentEffort = widget.viewModel.currentThinkingEffort;
        final availableLevels = activeModel.availableThinkingLevels;
        final filteredModels = _query.isEmpty
            ? activeProvider.models
            : activeProvider.models
                  .where(
                    (m) =>
                        m.name.toLowerCase().contains(_query) ||
                        m.id.toLowerCase().contains(_query),
                  )
                  .toList();

        return Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: AppSearchField(
                      key: const ValueKey('chat_model_search_field'),
                      hintText: l10n.settingsSearchModelHint,
                      debounceDuration: Duration.zero,
                      onChanged: (q) =>
                          setState(() => _query = q.trim().toLowerCase()),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AppIconButton(
                    icon: Icons.close_rounded,
                    size: 32,
                    iconSize: 16,
                    variant: AppIconButtonVariant.ghost,
                    tooltip: l10n.close,
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              if (activeModel.supportsThinking &&
                  availableLevels.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  key: const ValueKey('chat_thinking_selector'),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(color: colors.borderSubtle),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.psychology_outlined,
                        size: 15,
                        color: colors.primary,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: AppSegmentedCardBar<ThinkingEffort>(
                          items: [
                            for (final effort in availableLevels)
                              AppSegmentedItem<ThinkingEffort>(
                                value: effort,
                                label: _localizedEffortLabel(l10n, effort),
                              ),
                          ],
                          selectedValue: currentEffort,
                          expand: true,
                          itemPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          onValueChanged: widget.viewModel.setThinkingEffort,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Flexible(
                child: filteredModels.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.symmetric(vertical: 28),
                        child: Center(
                          child: Icon(
                            Icons.search_off_rounded,
                            size: 22,
                            color: colors.textMuted,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: filteredModels.length,
                        itemBuilder: (context, index) {
                          final model = filteredModels[index];
                          final isSelected = model.id == activeModel.id;
                          return InkWell(
                            key: ValueKey('chat_model_option_${model.id}'),
                            // 选定模型后不立即关闭浮层，便于连续调整思考强度
                            onTap: () =>
                                widget.viewModel.switchActiveModel(model.id),
                            borderRadius: BorderRadius.circular(AppRadius.md),
                            child: AnimatedContainer(
                              duration: AppMotion.resolveDuration(
                                context,
                                AppMotionDurations.quick,
                              ),
                              curve: AppMotionCurves.smoothOut,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 9,
                              ),
                              decoration: BoxDecoration(
                                color: isSelected ? colors.primaryTint : null,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      model.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: isSelected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: isSelected
                                            ? colors.primary
                                            : colors.textPrimary,
                                      ),
                                    ),
                                  ),
                                  if (model.isMultimodal) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.visibility_outlined,
                                      size: 13,
                                      color: colors.success,
                                    ),
                                  ],
                                  if (model.supportsThinking) ...[
                                    const SizedBox(width: 6),
                                    Icon(
                                      Icons.psychology_outlined,
                                      size: 13,
                                      color: colors.primary,
                                    ),
                                  ],
                                  const SizedBox(width: 8),
                                  AppIconSwap(
                                    swapKey: isSelected,
                                    enableBlur: false,
                                    duration: AppMotionDurations.quick,
                                    child: isSelected
                                        ? Icon(
                                            Icons.check_rounded,
                                            key: const ValueKey(true),
                                            size: 16,
                                            color: colors.primary,
                                          )
                                        : const SizedBox(
                                            key: ValueKey(false),
                                            width: 16,
                                            height: 16,
                                          ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 发送/停止主按钮单实例形变容器：状态切换时触发微缩放弹入，
/// 全程不共存两个按钮 Key，保证测试与辅助功能语义即时一致。
class _ComposerActionMorph extends StatefulWidget {
  final bool isStreaming;
  final Widget child;

  const _ComposerActionMorph({
    required this.isStreaming,
    required this.child,
  });

  @override
  State<_ComposerActionMorph> createState() => _ComposerActionMorphState();
}

class _ComposerActionMorphState extends State<_ComposerActionMorph>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final CurvedAnimation _scaleCurve;
  late final CurvedAnimation _turnsCurve;
  late final Animation<double> _scale;
  late final Animation<double> _turns;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.quick,
      value: 1.0,
    );
    _scaleCurve = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.bounce,
    );
    _turnsCurve = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.smoothOut,
    );
    _scale = Tween<double>(begin: 0.78, end: 1.0).animate(_scaleCurve);
    _turns = Tween<double>(begin: -0.05, end: 0.0).animate(_turnsCurve);
  }

  @override
  void didUpdateWidget(_ComposerActionMorph oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isStreaming != widget.isStreaming) {
      if (AppMotion.shouldReduceMotion(context)) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _scaleCurve.dispose();
    _turnsCurve.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.isCompleted) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => Transform.rotate(
        angle: _turns.value * 6.283185307179586,
        child: Transform.scale(scale: _scale.value, child: child),
      ),
    );
  }
}
