import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一浮动自动补全面板容器 (AppAutocompletePanel)
///
/// 代码证据出处：
/// - `tag_autocomplete_card.dart:7-120` (Danbooru 标签自动补全浮窗面板)
/// - `slash_command_overlay.dart:93-160` (智能体斜杠指令建议面板)
///
/// 核心职责：
/// 提供通用泛型浮动补全面板外壳，
/// 内置 Notion 投影、键盘方向键平滑滚动跟随、光标静止位移防误触机制 (250ms 冷却与 2.5px 容差)
/// 以及参数化驱动的条目构建器。
class AppAutocompletePanel<T> extends StatefulWidget {
  /// 建议条目列表
  final List<T> items;

  /// 当前高亮选中的条目下标
  final int selectedIndex;

  /// 单项构建器
  final Widget Function(
    BuildContext context,
    T item,
    int index,
    bool isSelected,
  )
  itemBuilder;

  /// 选中某项回调
  final ValueChanged<T> onSelect;

  /// 鼠标悬停高亮某项回调 (可选)
  final ValueChanged<int>? onHover;

  /// 是否为键盘按键导航触发 (为 true 时自动平滑滚动对应项至可视区域)
  final bool isKeyboardNavigated;

  /// 面板最大高度约束，默认 240.0
  final double maxHeight;

  /// 面板宽度；未指定时自适应外层约束
  final double? width;

  /// 列表内边距，默认上下 4.0
  final EdgeInsetsGeometry padding;

  /// 空列表时的自定义组件 (可选)
  final WidgetBuilder? emptyBuilder;

  const AppAutocompletePanel({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.itemBuilder,
    required this.onSelect,
    this.onHover,
    this.isKeyboardNavigated = false,
    this.maxHeight = 240.0,
    this.width,
    this.padding = const EdgeInsets.symmetric(vertical: 4.0),
    this.emptyBuilder,
  });

  @override
  State<AppAutocompletePanel<T>> createState() =>
      _AppAutocompletePanelState<T>();
}

class _AppAutocompletePanelState<T> extends State<AppAutocompletePanel<T>> {
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = [];
  Offset? _lastPointerPos;
  DateTime? _lastKeyboardNavTime;

  @override
  void initState() {
    super.initState();
    _updateKeys();
  }

  @override
  void didUpdateWidget(covariant AppAutocompletePanel<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _updateKeys();
    }
    // 仅在键盘导航状态下选中下标变更时平滑滚动入视野，防止鼠标滑动冲突
    if (oldWidget.selectedIndex != widget.selectedIndex &&
        widget.isKeyboardNavigated) {
      _lastKeyboardNavTime = DateTime.now();
      _scrollToIndex(widget.selectedIndex);
    }
  }

  void _updateKeys() {
    _itemKeys.clear();
    for (int i = 0; i < widget.items.length; i++) {
      _itemKeys.add(GlobalKey());
    }
  }

  void _scrollToIndex(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (index >= 0 && index < _itemKeys.length) {
        final keyContext = _itemKeys[index].currentContext;
        if (keyContext != null) {
          Scrollable.ensureVisible(
            keyContext,
            duration: const Duration(milliseconds: 60),
            curve: Curves.easeOut,
          );
        }
      }
    });
  }

  void _handlePointerHover(PointerHoverEvent event, int index) {
    // 1. 若最近 250ms 内刚发生过键盘方向键导航，忽略列表滚动引起的被动 hover
    if (_lastKeyboardNavTime != null &&
        DateTime.now().difference(_lastKeyboardNavTime!).inMilliseconds < 250) {
      _lastPointerPos = event.position;
      return;
    }

    // 2. 检查鼠标是否真的在屏幕上有物理位移 (防止列表被动滚动时静止光标产生伪 Hover)
    if (_lastPointerPos != null) {
      final delta = (event.position - _lastPointerPos!).distance;
      if (delta < 2.5) {
        return;
      }
    }

    _lastPointerPos = event.position;
    widget.onHover?.call(index);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    if (widget.items.isEmpty) {
      if (widget.emptyBuilder != null) {
        return widget.emptyBuilder!(context);
      }
      return const SizedBox.shrink();
    }

    Widget list = ListView.builder(
      controller: _scrollController,
      shrinkWrap: true,
      padding: widget.padding,
      itemCount: widget.items.length,
      itemBuilder: (ctx, index) {
        final item = widget.items[index];
        final isSelected = index == widget.selectedIndex;

        return MouseRegion(
          key: index < _itemKeys.length ? _itemKeys[index] : null,
          onHover: (event) => _handlePointerHover(event, index),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onSelect(item),
            child: widget.itemBuilder(ctx, item, index, isSelected),
          ),
        );
      },
    );

    return Material(
      color: Colors.transparent,
      child: Container(
        width: widget.width,
        constraints: BoxConstraints(maxHeight: widget.maxHeight),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: colors.borderDefault),
          boxShadow: context.shadowElevated,
        ),
        clipBehavior: Clip.antiAlias,
        child: list,
      ),
    );
  }
}
