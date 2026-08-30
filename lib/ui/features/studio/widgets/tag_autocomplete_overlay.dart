import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/tag_models.dart';
import '../../../../data/services/danbooru_search_service.dart';
import '../../../../data/services/prompt_ast_engine.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import 'tag_autocomplete_card.dart';

/// 标签自动补全悬浮锚点组件
///
/// 挂载在任何提示词输入框周围，监听光标与文本变化，智能在右侧图片栏左侧边缘弹出浮动补全建议卡片。
/// Y 轴精准对齐当前输入光标指针行，上下键带边界阻尼与滚动置顶 (alignment: 0.0)，支持全键盘导航与鼠标精准点击。
class TagAutocompleteAnchor extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String>? onChanged;
  final Widget child;
  final bool enabled;

  /// 是否在建议项中显示中文释义 (设置项控制)
  final bool showTranslation;

  /// 在线语义搜索服务 (可注入 mock；默认 DanbooruSearch 单例)
  final DanbooruSearchService? searchService;

  const TagAutocompleteAnchor({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onChanged,
    required this.child,
    this.enabled = true,
    this.showTranslation = true,
    this.searchService,
  });

  @override
  State<TagAutocompleteAnchor> createState() => _TagAutocompleteAnchorState();
}

class _TagAutocompleteAnchorState extends State<TagAutocompleteAnchor> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;

  List<TagSuggestion> _suggestions = [];
  int _selectedIndex = 0;
  String _activeQuery = '';
  int _replaceStart = 0;
  int _replaceEnd = 0;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    widget.focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant TagAutocompleteAnchor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onTextChanged);
      widget.controller.addListener(_onTextChanged);
    }
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_onFocusChanged);
      widget.focusNode.addListener(_onFocusChanged);
    }
    if (oldWidget.showTranslation != widget.showTranslation &&
        _overlayEntry != null) {
      _overlayEntry?.markNeedsBuild();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _hideOverlay();
    widget.controller.removeListener(_onTextChanged);
    widget.focusNode.removeListener(_onFocusChanged);
    super.dispose();
  }

  void _onFocusChanged() {
    // 延迟 100ms 检查失焦，避免鼠标点击建议项瞬间被隐藏阻断
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted && !widget.focusNode.hasFocus && _overlayEntry != null) {
        _hideOverlay();
      }
    });
  }

  void _onTextChanged() {
    if (!widget.enabled || !widget.focusNode.hasFocus) {
      _hideOverlay();
      return;
    }

    final text = widget.controller.text;
    final selection = widget.controller.selection;
    if (!selection.isValid || selection.start != selection.end) {
      _hideOverlay();
      return;
    }

    final queryData = PromptAstEngine.extractActiveQuery(text, selection.start);
    if (queryData == null || queryData.query.isEmpty) {
      _hideOverlay();
      return;
    }

    final q = queryData.query;
    _replaceStart = queryData.replaceStart;
    _replaceEnd = queryData.replaceEnd;

    if (q == _activeQuery && _overlayEntry != null) {
      _overlayEntry?.markNeedsBuild();
      return;
    }

    _activeQuery = q;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 100), () {
      _searchAndShow(q);
    });
  }

  Future<void> _searchAndShow(String query) async {
    if (!mounted || !widget.focusNode.hasFocus) return;
    final onlineService =
        widget.searchService ?? DanbooruSearchService.instance;

    // 1) 离线词库立即可用：前缀/别名/中文释义匹配
    final offline = await TagDictionaryService.instance.search(query, limit: 8);
    if (!mounted || _activeQuery != query) return;

    // 2) 判断是否需要在线语义增强 (DanbooruSearch HF Space，10~30s 慢路径)：
    //    - 中文查询：语义搜词能把模糊描述映射到标准标签，是主增强场景
    //    - 英文查询：离线结果不足 3 条时用语义搜词兜底 (拼写容错)
    final isCjk = onlineService.isCjkQuery(query);
    final wantsOnline =
        (isCjk && query.trim().length >= 2) ||
        (!isCjk && query.trim().length >= 4 && offline.length < 3);

    if (offline.isEmpty) {
      if (!wantsOnline) {
        _hideOverlay();
        return;
      }
      // 无离线结果但在线检索中：先收起旧查询的悬浮卡，
      // 避免旧建议在 10~30s 的慢路径期间悬挂不更新
      _dismissOverlayOnly();
      setState(() {
        _suggestions = const [];
        _selectedIndex = 0;
      });
    } else {
      setState(() {
        _suggestions = List.of(offline);
        _selectedIndex = 0;
      });
      _showOverlay();
    }

    if (!wantsOnline) return;

    // 在线慢路径防抖：等用户停止输入 400ms 再发请求，
    // 避免连续古键时每个中间态都打一发 10~30s 的语义检索
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!mounted || _activeQuery != query) return;

    // 3) 在线语义搜索：结果到达后与离线合并去重 (在线优先)
    try {
      final online = await onlineService.searchTags(
        query,
        limit: 8,
        useSegmentation: false,
      );
      if (!mounted || _activeQuery != query) return;

      if (online.isEmpty) {
        if (_suggestions.isEmpty) _hideOverlay();
        return;
      }

      final merged = <TagSuggestion>[
        for (final r in online) r.toTagSuggestion(),
      ];
      final seen = <String>{for (final s in merged) s.tag.toLowerCase()};
      for (final s in _suggestions) {
        if (seen.add(s.tag.toLowerCase())) merged.add(s);
      }

      setState(() {
        _suggestions = merged.take(12).toList();
        _selectedIndex = 0;
      });
      _showOverlay();
    } catch (_) {
      // 在线服务不可用：保留离线结果，静默降级
      if (_suggestions.isEmpty) _hideOverlay();
    }
  }

  void _showOverlay() {
    if (_overlayEntry == null) {
      _overlayEntry = _createOverlayEntry();
      Overlay.of(context).insert(_overlayEntry!);
    } else {
      _overlayEntry?.markNeedsBuild();
    }
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _activeQuery = '';
  }

  /// 仅移除悬浮卡片但保留当前查询词 (在线慢路径检索期间先收起旧结果，
  /// 结果落地后由 [show] 路径重新弹出，且不干扰 _activeQuery 过期校验)
  void _dismissOverlayOnly() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  RenderEditable? _findRenderEditable(RenderObject? root) {
    if (root == null) return null;
    if (root is RenderEditable) return root;
    RenderEditable? result;
    root.visitChildren((child) {
      result ??= _findRenderEditable(child);
    });
    return result;
  }

  double _getCaretLocalY() {
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return 0.0;

    final selection = widget.controller.selection;
    final offset = selection.isValid ? selection.baseOffset : 0;
    final renderEditable = _findRenderEditable(renderBox);

    if (renderEditable != null && renderEditable.hasSize) {
      try {
        final caretRect = renderEditable.getLocalRectForCaret(
          TextPosition(offset: offset),
        );
        final caretGlobal = renderEditable.localToGlobal(caretRect.topLeft);
        final anchorGlobal = renderBox.localToGlobal(Offset.zero);
        final localY = caretGlobal.dy - anchorGlobal.dy;
        return localY.clamp(0.0, renderBox.size.height);
      } catch (_) {
        return 0.0;
      }
    }
    return 0.0;
  }

  OverlayEntry _createOverlayEntry() {
    return OverlayEntry(
      builder: (context) {
        final renderBox = this.context.findRenderObject() as RenderBox?;
        final screenSize = MediaQuery.sizeOf(context);
        bool placeOnRight = true;
        double caretY = _getCaretLocalY();

        if (renderBox != null && renderBox.hasSize) {
          final globalOffset = renderBox.localToGlobal(Offset.zero);
          final rightEdge = globalOffset.dx + renderBox.size.width;
          if (rightEdge + 340 > screenSize.width ||
              renderBox.size.width > screenSize.width * 0.6) {
            placeOnRight = false;
          }

          // 屏幕底部防溢出保护：若光标处弹出卡片会超出屏幕底边缘，适度上移
          final globalCaretY = globalOffset.dy + caretY;
          const estimatedCardHeight = 280.0;
          if (globalCaretY + estimatedCardHeight > screenSize.height - 20) {
            final overflow =
                (globalCaretY + estimatedCardHeight) - (screenSize.height - 20);
            caretY = (caretY - overflow).clamp(0.0, double.infinity);
          }
        }

        return Positioned(
          width: 320,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            targetAnchor: placeOnRight
                ? Alignment.topRight
                : Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: placeOnRight ? Offset(12, caretY) : Offset(0, caretY + 24),
            child: TagAutocompleteCard(
              suggestions: _suggestions,
              selectedIndex: _selectedIndex,
              query: _activeQuery,
              showTranslation: widget.showTranslation,
              onSelect: _applySuggestion,
              onHover: (idx) {
                if (_selectedIndex != idx) {
                  setState(() => _selectedIndex = idx);
                  _overlayEntry?.markNeedsBuild();
                }
              },
            ),
          ),
        );
      },
    );
  }

  void _applySuggestion(TagSuggestion suggestion) {
    final text = widget.controller.text;
    final tag = suggestion.tag;

    // 智能上屏：替换当前词段，并自动追加逗号与空格
    final before = text.substring(0, _replaceStart);
    final after = text.substring(_replaceEnd.clamp(0, text.length));

    // 检查 after 是否已有逗号
    final needsComma = !after.trimLeft().startsWith(',');
    final insertion = needsComma ? '$tag, ' : tag;

    final newText = '$before$insertion$after';
    final newCursorPos = _replaceStart + insertion.length;

    widget.controller.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newCursorPos),
    );

    widget.onChanged?.call(newText);
    _hideOverlay();

    // 保持焦点在输入框
    widget.focusNode.requestFocus();
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (_overlayEntry == null || _suggestions.isEmpty) {
      return KeyEventResult.ignored;
    }

    if (event is KeyDownEvent || event is KeyRepeatEvent) {
      // 下方向键：有边界阻尼 (到底停止，不循环)
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        if (_selectedIndex < _suggestions.length - 1) {
          setState(() {
            _selectedIndex++;
          });
          _overlayEntry?.markNeedsBuild();
        }
        return KeyEventResult.handled;
      }
      // 上方向键：有边界阻尼 (到头停止，不循环)
      else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        if (_selectedIndex > 0) {
          setState(() {
            _selectedIndex--;
          });
          _overlayEntry?.markNeedsBuild();
        }
        return KeyEventResult.handled;
      }
      // Tab / Enter：确认选中当前选中的项目
      else if (event.logicalKey == LogicalKeyboardKey.tab ||
          event.logicalKey == LogicalKeyboardKey.enter) {
        if (_selectedIndex >= 0 && _selectedIndex < _suggestions.length) {
          _applySuggestion(_suggestions[_selectedIndex]);
          return KeyEventResult.handled;
        }
      }
      // ESC：收起悬浮窗
      else if (event.logicalKey == LogicalKeyboardKey.escape) {
        _hideOverlay();
        return KeyEventResult.handled;
      }
    }

    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      onKeyEvent: _handleKeyEvent,
      child: CompositedTransformTarget(link: _layerLink, child: widget.child),
    );
  }
}
