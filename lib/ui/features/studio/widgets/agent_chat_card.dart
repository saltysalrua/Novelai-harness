import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show
        RenderObject,
        RenderSliverMultiBoxAdaptor,
        ScrollCacheExtent,
        SliverMultiBoxAdaptorParentData;
import 'package:flutter/services.dart';
import '../../../core/context_l10n.dart';
import '../../../../core/harness/tools/ask_user_tool.dart';
import '../../../../core/harness/types.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../../core/widgets/stable_scrollbar.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../view_models/studio_view_model.dart';
import 'agent_chat_input_bar.dart';
import 'agent_chat_messages.dart';
import 'agent_rewind_view.dart';
import 'agent_session_list_view.dart';
import 'inline_agent_question_card.dart';

/// Agent 对话卡主壳: 三视图切换 (对话/会话管理/历史回溯) + 布局组装
///
/// 消息渲染块在 agent_chat_messages.dart，
/// 折叠/思考通用块在 agent_chat_blocks.dart，
/// 底部模型/思考/输入区在 agent_chat_input_bar.dart。
enum _AgentCardView { chat, sessions, rewind }

class AgentChatCard extends StatefulWidget {
  final StudioViewModel viewModel;
  final VoidCallback? onEscape;

  /// 覆盖视图 (会话抽屉 / 历史回溯) 开合通知：宿主据此刷新系统返回键判态
  final VoidCallback? onOverlayViewChanged;

  const AgentChatCard({
    super.key,
    required this.viewModel,
    this.onEscape,
    this.onOverlayViewChanged,
  });

  @override
  State<AgentChatCard> createState() => AgentChatCardState();
}

/// 公开 State：供根级全局 ESC (StudioView) 通过 GlobalKey 调起回溯视图
class AgentChatCardState extends State<AgentChatCard> {
  /// 平滑滚轮控制器：鼠标滚轮逐格瞬移改为短滑动，消除"一卡一卡"手感
  final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();
  final FocusNode _cardFocusNode = FocusNode();
  _AgentCardView _currentView = _AgentCardView.chat;
  DateTime? _lastEscPressTime;

  /// 消息 Widget 缓存 (key = messageId)：
  /// 消息一旦定稿不可变，滚动回视口时复用同一 Widget 实例，
  /// 配合近期消息 Element 保活，避免 Markdown 离屏后重新解析。
  final Map<String, AgentChatMessageItem> _messageWidgetCache = {};

  static const int _maxKeptAliveMessages = 120;
  String? _renderedSessionId;
  int _followEpoch = 0;
  bool _followSuspended = false;

  /// 消息 Widget 配置缓存上限，逐条淘汰，避免清空整批缓存造成重建尖峰。
  static const int _maxCachedMessages = 600;

  /// 用户最近一次主动滚动 (滚轮信号 / 拖拽) 的时间戳。
  /// 流式底部跟随在此后的 [_followCooldown] 内保持沉默，
  /// 防止跟随跳转与用户刚发起的滚轮滑行互相打架把视口强拽回底部。
  DateTime? _lastUserScrollIntentAt;
  static const Duration _followCooldown = Duration(milliseconds: 350);

  /// 上一帧的是否在流式输出标志 (用于收尾瞬间的高度落差结算)
  bool _wasStreaming = false;

  /// 上一帧的思考块全局展开状态 (Ctrl+O 切换检测)
  bool _lastThinkingExpanded = false;

  /// 程序化补偿跳转进行中标记：跳转产生的 ScrollUpdateNotification
  /// 不得被误判为用户上翻意图 (同步派发, 标志随调用栈生效)
  bool _suppressScrollIntentNote = false;

  /// 当前按下的指针计数 (握把按住/多点触控)。指针未松开时
  /// ScrollEndNotification 的贴底恢复一律延迟，防止按住握把瞬间
  /// hold → didEndScroll 伪装的“回到底部”误恢复底部跟随。
  int _pressedPointers = 0;

  /// 拖拽期间冻结消息列表渲染数据源：Flutter 滚动条握把位移经
  /// ``_getPrimaryDelta`` 做「拖拽起点握把位置 × 当前内容高度」的绝对映射，
  /// 拖拽途中内容高度变化 (流式增长 / 流式结束气泡消失) 会污染映射基准，
  /// 下一次握把移动立刻瞬移 (方向冲突增量兜底只覆盖一半组合)。
  /// 手势期间冻结实时内容，手势结束恢复；注意 SliverList 的总高度估算
  /// 仍会随懒加载窗口变化，握把映射由 StableScrollbar 独立稳定。
  bool _thumbHeld = false;
  bool _listDragActive = false;
  List<AgentMessage>? _frozenMessages;
  bool _frozenStreamingActive = false;
  AgentQuestionPrompt? _frozenQuestion;
  bool _frozenThinkingExpanded = false;
  Widget? _frozenStreamingBubble;

  /// 消息列表区域定位键 (判定指针是否落在右侧滚动条握把热区)
  final GlobalKey _messageListAreaKey = GlobalKey();

  bool get _extentFrozen =>
      _frozenMessages != null && (_thumbHeld || _listDragActive);

  /// 高度突变补偿锚点: (item 下标, 重建前布局偏移)
  (double, int)? _pendingAnchor;

  /// 锚点捕获瞬间的滚动位置 (绝对定位补偿的基准)
  double? _anchorOriginPixels;

  /// 补偿捕获时的整窗旧偏移快照 (index -> 旧 layoutOffset)，
  /// 供年轻布局窗口外锚点的插值估算使用
  Map<int, double>? _anchorOldOffsets;

  @override
  void dispose() {
    _scrollController.dispose();
    _cardFocusNode.dispose();
    _messageWidgetCache.clear();
    super.dispose();
  }

  void _scrollToBottom({bool animate = true}) {
    _followSuspended = false;
    _lastUserScrollIntentAt = null;
    _scrollToBottomAfterFrames(
      animate: animate,
      remainingFrames: 3,
      epoch: ++_followEpoch,
    );
  }

  /// 退后一帧跳到底部。SliverList 的 maxScrollExtent 对新内容可能是估算值
  /// (尤其是被 Widget 缓存跳过重建的那一帧，extent 可能晚一帧才结算)，
  /// 因此跳完后再链式校验最多 [remainingFrames] 帧，直到估算稳定。
  void _scrollToBottomAfterFrames({
    required bool animate,
    required int remainingFrames,
    required int epoch,
  }) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          epoch != _followEpoch ||
          _currentView != _AgentCardView.chat ||
          !_scrollController.hasClients) {
        return;
      }
      final pos = _scrollController.position;
      if (pos.pixels < pos.maxScrollExtent) {
        if (animate) {
          _scrollController.animateTo(
            pos.maxScrollExtent,
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
          );
        } else {
          _scrollController.jumpTo(pos.maxScrollExtent);
        }
        // 静默跳转同样链式校验后续帧的估算修正：动画模式只发一次 animateTo
        // (连续每帧重启动画会反复以 easeOut 最大初速度起步，造成抽搐抖动)，
        // 后续的尺寸增量由流式跟随逻辑接管
        if (!animate && remainingFrames > 0) {
          _scrollToBottomAfterFrames(
            animate: false,
            remainingFrames: remainingFrames - 1,
            epoch: epoch,
          );
        }
      }
    });
  }

  /// 上次跟随跳转的目标像素 (链式校验期间判断用户是否主动上翻)
  double? _lastFollowTarget;

  /// 底部跟随是否被用户滚动意图静默：主动滚动冷却期内，或用户已明确
  /// 暂停跟随 (上翻查看历史) 时，任何程序化跳转一律不发。
  bool get _followMutedByUser {
    if (_followSuspended) return true;
    final last = _lastUserScrollIntentAt;
    return last != null && DateTime.now().difference(last) < _followCooldown;
  }

  /// 记录一次用户主动滚动意图 (滚轮信号 / 指针按下 / 拖拽开始)
  void _noteUserScrollIntent() {
    _lastUserScrollIntentAt = DateTime.now();
    _pauseFollowing();
  }

  /// 滚轮信号意图判定：
  /// 已经贴在底部时继续向下拨滚轮没有任何位移意图 (会被边界钳制成原地空转，
  /// 且不产生 ScrollActivity/ScrollEndNotification)，若此时照常挂起跟随，
  /// _followSuspended 将没有任何事件能复位，自动跟随彻底冻结 (死锁)。
  /// 故「触底继续向下」的信号直接忽略，不挂起不冷却。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent &&
        event.scrollDelta.dy > 0 &&
        _scrollController.hasClients &&
        _scrollController.position.hasContentDimensions &&
        _scrollController.position.extentAfter <= 1.0) {
      return;
    }
    _noteUserScrollIntent();
  }

  /// 仅在 Agent 正在流式输出时生效：
  /// - 若当前视口已在底部 (距底部 64px 以内)，随新内容输出自动跟随保持在底部；
  /// - 若用户向上滚动翻看历史或刚发起过滚动 (冷却期)，保持原地绝不强拉。
  ///   跟随跳转后链式校验最多 4 帧，兜底 maxScrollExtent 估算延迟结算。
  void _autoScrollOnStream() {
    if (_followMutedByUser || !widget.viewModel.isChatStreaming) return;
    if (!_scrollController.hasClients ||
        !_scrollController.position.hasContentDimensions) {
      return;
    }
    // 估算 maxScrollExtent 结算滞后一到两帧，“跳到底”后可能仍差几十像素，
    // 此时阈值放宽到 64px；链内用户上翻判定仍按 32px 严格把关
    final isAtBottom = _scrollController.position.extentAfter <= 64.0;
    if (!isAtBottom) return;

    // 跳底时记录基准：后续帧里像素显著低于它即为用户主动上翻
    _lastFollowTarget = _scrollController.position.pixels;
    _followStreamBottom(remainingFrames: 4, epoch: ++_followEpoch);
  }

  /// 流式底部跟随的链式校验：双向夹到 maxScrollExtent
  /// (既补上晚结算的增量，也纠正跳到过高估算值后的回落)；
  /// 用户滚动冷却期 / 显式暂停期间保持沉默，绝不打断用户手势滑行。
  void _followStreamBottom({required int remainingFrames, required int epoch}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          epoch != _followEpoch ||
          _currentView != _AgentCardView.chat ||
          _followMutedByUser ||
          !widget.viewModel.isChatStreaming ||
          !_scrollController.hasClients) {
        return;
      }
      final pos = _scrollController.position;
      // 用户主动向上滚离 (低于上次跟随目标 32px 以上) 则停止跟随，绝不强拉
      final last = _lastFollowTarget;
      if (last != null && pos.pixels < last - 32.0) return;
      final target = pos.maxScrollExtent;
      if ((pos.pixels - target).abs() > 0.5) {
        _lastFollowTarget = target;
        // 程序化跳转，排除出用户意图侦测
        _suppressScrollIntentNote = true;
        _scrollController.jumpTo(target);
        _suppressScrollIntentNote = false;
      }
      // 只要还在流式且预算未尽就继续校验：估算可能晚一帧才结算，
      // “本轮无需跳转”不代表下一帧不需要
      if (remainingFrames > 0) {
        _followStreamBottom(remainingFrames: remainingFrames - 1, epoch: epoch);
      }
    });
  }

  void _pauseFollowing() {
    _followSuspended = true;
    _followEpoch++;
  }

  /// 指针是否落在消息流右侧滚动条握把热区 (厚度 6px + 悬停余量)
  bool _isScrollbarZonePress(PointerDownEvent event) {
    final render = _messageListAreaKey.currentContext?.findRenderObject();
    if (render is! RenderBox || !render.hasSize) return false;
    return event.localPosition.dx >= render.size.width - 20;
  }

  /// 冻结开始：以当前实时数据拍快照 (重复调用幂等，不覆盖旧快照)
  void _engageExtentFreeze() {
    if (_frozenMessages != null) return;
    _frozenMessages = List<AgentMessage>.of(widget.viewModel.messages);
    _frozenStreamingActive = widget.viewModel.isChatStreaming;
    _frozenQuestion = widget.viewModel.activeQuestionPrompt;
    _frozenThinkingExpanded = widget.viewModel.isThinkingExpanded;
  }

  /// 冻结解除：恢复实时数据渲染；若手势结束在底部 (跟随已恢复)，
  /// 静默贴底一次把冻结期内增长的内容收进视口
  void _maybeUnfreezeExtent() {
    if (_thumbHeld || _listDragActive) return;
    if (_frozenMessages == null) return;
    _frozenMessages = null;
    _frozenQuestion = null;
    _frozenStreamingBubble = null;
    final backAtBottom = !_followSuspended;
    setState(() {});
    if (backAtBottom) _scrollToBottom(animate: false);
  }

  /// 无条件清理冻结状态 (视图切换 / 会话切换时陈旧快照保护)
  void _clearExtentFreeze() {
    _thumbHeld = false;
    _listDragActive = false;
    _frozenMessages = null;
    _frozenQuestion = null;
    _frozenStreamingBubble = null;
  }

  void _resumeFollowingAtBottom() {
    if (_scrollController.hasClients &&
        !_scrollController.position.isScrollingNotifier.value &&
        _scrollController.position.extentAfter <= 1.0) {
      _followSuspended = false;
      _lastUserScrollIntentAt = null;
    }
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null) {
      _noteUserScrollIntent();
      // 触控拖内容 / 握把起手双通路：内容拖拽走这里冻结
      // (握把按下已由指针热区提前冻结，此处幂等)
      if (!_listDragActive) {
        _listDragActive = true;
        _engageExtentFreeze();
      }
    }
    // 任何非拖拽来源的向上位移都视为用户上翻意图 (键盘方向键/PgUp、触控板等
    // 没有指针事件的滚动方式全靠这里兜底侦测)。程序化跟随只会向下跳底，
    // 补偿性跳转由 [_suppressScrollIntentNote] 排除；其余向上位移记为意图
    if (notification is ScrollUpdateNotification &&
        !_suppressScrollIntentNote &&
        notification.dragDetails == null &&
        (notification.scrollDelta ?? 0) < -1.0) {
      _noteUserScrollIntent();
    }
    if (notification is ScrollEndNotification &&
        _pressedPointers == 0 &&
        notification.metrics.extentAfter <= 1.0) {
      // 严格贴底 (extentAfter≈0) 即视为回到流式跟随场景：
      // 清冷却与暂停，随新输出继续跟随；微小上滚后的位置保持粘性。
      // 指尖/握把仍按着时 (hold → didEndScroll 会伪装出 ScrollEnd)
      // 不得恢复跟随，冻结结束后的真实滚落由 _maybeUnfreezeExtent 补贴底。
      _followSuspended = false;
      _lastUserScrollIntentAt = null;
    }
    if (notification is ScrollEndNotification) {
      // 必须在贴底恢复判定之后解冻：拖拽结束恰在底部时，先让跟随恢复，
      // 解冻补贴底才能把冻结期内增长的内容收进视口
      _listDragActive = false;
      _maybeUnfreezeExtent();
    }
    return false;
  }

  /// 定位消息流 ListView 的 Sliver 渲染对象 (自 Scrollable 渲染树向下搜索)
  RenderSliverMultiBoxAdaptor? _findMessageListSliver() {
    if (!_scrollController.hasClients) return null;
    final scrollContext = _scrollController.position.context;
    if (scrollContext is! ScrollableState) return null;
    final render = scrollContext.context.findRenderObject();
    if (render == null) return null;
    RenderSliverMultiBoxAdaptor? found;
    void visit(RenderObject obj) {
      if (found != null) return;
      if (obj is RenderSliverMultiBoxAdaptor) {
        found = obj;
        return;
      }
      obj.visitChildren(visit);
    }

    visit(render);
    return found;
  }

  /// 捕获重建前整窗可布局子项的旧偏移快照，并返回视口顶部锚点 (偏移, 下标)
  (Map<int, double> snapshot, (double, int) anchor)? _captureTopAnchor() {
    final sliver = _findMessageListSliver();
    if (sliver == null) return null;
    final topEdge = _scrollController.position.pixels;
    final snapshot = <int, double>{};
    (double, int)? anchor;
    // 只遍历活动布局盒链 (firstChild..childAfter)；keepAlive 陈旧桶条目
    // 不在盒链里 (visitChildren 会额外吐出它们，绝不可混入计算)
    RenderBox? node = sliver.firstChild;
    while (node != null) {
      final data = node.parentData;
      if (data is! SliverMultiBoxAdaptorParentData) continue;
      final layoutOffset = data.layoutOffset;
      final index = data.index;
      if (layoutOffset == null || index == null) continue;
      snapshot[index] = layoutOffset;
      if (anchor == null && layoutOffset + node.size.height > topEdge) {
        anchor = (layoutOffset, index);
      }
      node = sliver.childAfter(node);
    }
    final resolvedAnchor = anchor;
    if (resolvedAnchor == null) return null;
    return (snapshot, resolvedAnchor);
  }

  /// 全局高度突变 (Ctrl+O 展开/折叠全部思考块) 的视口补偿：
  /// 重建前捕获整窗旧偏移快照与视口顶部锚点；重建后新写入的子项若已铲到
  /// 视口内则按锚点新偏移差值直接精准补偿；若批量高度剧变把锚点推到了
  /// 缓存窗口之外 (懒加载列表根本没重新布局它)，则用最近的新鲜子项
  /// 插值估算锚点新偏移先跳过去，随后锚点必然进入布局窗口再做精准
  /// 校正。一次性 O(可见+缓存) 遍历，无高频监听，零持续性能开销。
  void _preserveTopAnchorAcrossRebuild() {
    if (!_scrollController.hasClients) return;
    final capture = _captureTopAnchor();
    if (capture == null) return;
    _pendingAnchor = capture.$2;
    _anchorOriginPixels = _scrollController.position.pixels;
    _anchorOldOffsets = capture.$1;
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _applyPendingAnchor(chains: 6),
    );
  }

  /// 应用锚点补偿：链式最多 [chains] 次续帧，直至锚点收敛或预算耗尽
  void _applyPendingAnchor({required int chains}) {
    if (!mounted || !_scrollController.hasClients) return _pendingAnchor = null;
    final anchor = _pendingAnchor;
    if (anchor == null) return;
    final sliver = _findMessageListSliver();
    if (sliver == null) return _pendingAnchor = null;
    // 新鲜盒链查找锚点；盒链不含 keepAlive 陈旧条目，offset 全部可信
    double? newOffset;
    double? nearestLagDelta;
    int? nearestDistance;
    RenderBox? node = sliver.firstChild;
    while (node != null) {
      final data = node.parentData;
      if (data is! SliverMultiBoxAdaptorParentData) continue;
      final index = data.index;
      final layoutOffset = data.layoutOffset;
      if (index == null || layoutOffset == null) continue;
      final oldOffset = _anchorOldOffsets?[index];
      if (oldOffset != null) {
        final distance = (index - anchor.$2).abs();
        if (nearestDistance == null || distance < nearestDistance) {
          nearestDistance = distance;
          nearestLagDelta = layoutOffset - oldOffset;
        }
      }
      if (index == anchor.$2) newOffset = layoutOffset;
      node = sliver.childAfter(node);
    }
    final offset = newOffset;
    if (offset == null) {
      // 锚点尚未被重新布局 (高度剧变一次性把它推出缓存窗口)：
      // 用最近的新鲜子项的偏移增量插值估算先跳过去，令锚点在下一帧
      // 进入布局窗口，随后再做精准补偿；keepAlive 陈旧条目不参与
      if (chains > 0) {
        final delta = nearestLagDelta;
        final origin = _anchorOriginPixels;
        if (delta != null && origin != null && delta.abs() > 1.0) {
          final pos = _scrollController.position;
          final target = (origin + delta)
              .clamp(pos.minScrollExtent, pos.maxScrollExtent)
              .toDouble();
          _suppressScrollIntentNote = true;
          _scrollController.jumpTo(target);
          _suppressScrollIntentNote = false;
        }
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _applyPendingAnchor(chains: chains - 1),
        );
      } else {
        _pendingAnchor = null;
      }
      return;
    }
    final origin = _anchorOriginPixels;
    if (origin == null) return _pendingAnchor = null;
    // 绝对定位式补偿：视口顶边到锚点顶部的相对距离 (anchor.$1 - origin)
    // 在展开前后必须保持不变，与当前 pixels 无关
    final desired = offset - (anchor.$1 - origin);
    final pos = _scrollController.position;
    if ((pos.pixels - desired).abs() <= 0.5) {
      _pendingAnchor = null; // 已收敛
      return;
    }
    final target = desired
        .clamp(pos.minScrollExtent, pos.maxScrollExtent)
        .toDouble();
    _suppressScrollIntentNote = true;
    _scrollController.jumpTo(target);
    _suppressScrollIntentNote = false;
    // 以新偏移为基准续链，结算剩余晚到布局
    _pendingAnchor = (offset, anchor.$2);
    if (chains > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyPendingAnchor(chains: chains - 1),
      );
    } else {
      _pendingAnchor = null;
    }
  }

  /// 切换至历史时刻回溯视图 (流式中则先中断)
  void openRewindView() {
    if (widget.viewModel.isChatStreaming) {
      widget.viewModel.abortChat();
    }
    _switchView(_AgentCardView.rewind);
  }

  /// 是否处于覆盖视图 (会话抽屉 / 历史回溯) —— 供宿主判断系统返回键是否有层内动作
  bool get hasOverlayView => _currentView != _AgentCardView.chat;

  /// 关闭覆盖视图回到对话主视图；返回是否确有覆盖视图被关闭
  bool dismissOverlayView() {
    if (!hasOverlayView) return false;
    _switchView(_AgentCardView.chat);
    return true;
  }

  /// 三视图切换单一入口：回对话主视图时同步贴底
  void _switchView(_AgentCardView view) {
    if (_currentView == view) return;
    setState(() => _currentView = view);
    if (view == _AgentCardView.chat) {
      _scrollToBottom(animate: false);
    }
    widget.onOverlayViewChanged?.call();
  }

  void _handleEscKey() {
    final now = DateTime.now();
    if (_lastEscPressTime != null &&
        now.difference(_lastEscPressTime!) <=
            const Duration(milliseconds: 400)) {
      _lastEscPressTime = null;
      // 连续按两次 ESC：全屏覆盖切换至历史时刻回溯视图
      openRewindView();
      return;
    }

    _lastEscPressTime = now;
    if (widget.viewModel.isEditingCharacterPositions) {
      widget.viewModel.setEditingCharacterPositions(false);
      return;
    }
    if (widget.viewModel.isChatStreaming) {
      widget.viewModel.abortChat();
    }
  }

  @override
  Widget build(BuildContext context) {
    // ViewModel 就地变更，不能比较 oldWidget.viewModel（它是同一个实例）。
    final sessionId = widget.viewModel.currentSessionId;
    if (_renderedSessionId != sessionId) {
      _renderedSessionId = sessionId;
      _clearExtentFreeze();
      _messageWidgetCache.clear();
      _scrollToBottom(animate: false);
    }
    // 非对话视图 (会话抽屉/回溯) 期间不得持陈旧冻结快照
    if (_currentView != _AgentCardView.chat) {
      _clearExtentFreeze();
    }
    switch (_currentView) {
      case _AgentCardView.sessions:
        return AgentSessionListView(
          viewModel: widget.viewModel,
          onBack: () => _switchView(_AgentCardView.chat),
        );
      case _AgentCardView.rewind:
        return AgentRewindView(
          viewModel: widget.viewModel,
          onBack: () => _switchView(_AgentCardView.chat),
        );
      case _AgentCardView.chat:
        break;
    }

    if (_currentView == _AgentCardView.chat) {
      // 流式收尾瞬间：流式气泡被定稿消息替换 (Element 换型 + 进度条剥离)，
      // 末尾高度可能瞬态落差几到几十像素；未暂停跟随时静默贴底结算
      final streamingNow = widget.viewModel.isChatStreaming;
      if (_wasStreaming && !streamingNow && !_followSuspended) {
        _lastUserScrollIntentAt = null;
        _scrollToBottom(animate: false);
      }
      _wasStreaming = streamingNow;
      // 思考块全局展开/折叠 (Ctrl+O/状态切换): 所有思考块同时改变高度，
      // 视口内容会被整个推走——捕获顶部锚点并在重建后静默补偿。
      // 拖拽冻结期间判定走冻结值，Ctrl+O 补偿随之推迟到手势解除冻结时生效
      final thinkingNow = _extentFrozen
          ? _frozenThinkingExpanded
          : widget.viewModel.isThinkingExpanded;
      if (thinkingNow != _lastThinkingExpanded) {
        _lastThinkingExpanded = thinkingNow;
        _preserveTopAnchorAcrossRebuild();
      }
      // 结构性通知 (消息入列/工具结果等) 不一定伴随流式文本增量，
      // build 里与 ListenableBuilder 的增量回调双路驱动跟随判断
      _autoScrollOnStream();
    }

    return Focus(
      focusNode: _cardFocusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          (widget.onEscape ?? _handleEscKey)();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 顶部预设选择栏与会话管理按钮
            _buildPresetHeaderBar(),

            // 对话消息流展示区域
            Expanded(
              child: Listener(
                key: _messageListAreaKey,
                onPointerDown: (event) {
                  _noteUserScrollIntent();
                  _pressedPointers++;
                  // 落在右侧滚动条握把热区：立即冻结渲染内容，
                  // 冻结期内任何流式增长/收缩都不改内容高度，
                  // 这里只隔离实时内容变化，懒加载估算变化由 StableScrollbar 处理
                  if (_isScrollbarZonePress(event) && !_thumbHeld) {
                    _thumbHeld = true;
                    _engageExtentFreeze();
                  }
                },
                onPointerUp: (_) {
                  _pressedPointers = _pressedPointers > 0
                      ? _pressedPointers - 1
                      : 0;
                  _thumbHeld = false;
                  _maybeUnfreezeExtent();
                  _resumeFollowingAtBottom();
                },
                onPointerCancel: (_) {
                  _pressedPointers = _pressedPointers > 0
                      ? _pressedPointers - 1
                      : 0;
                  _thumbHeld = false;
                  _maybeUnfreezeExtent();
                  _resumeFollowingAtBottom();
                },
                onPointerSignal: _onPointerSignal,
                child: NotificationListener<ScrollNotification>(
                  onNotification: _onScrollNotification,
                  child: _buildMessageList(),
                ),
              ),
            ),

            // 底部控制与消息输入区 (单一底栏，高度与左侧生成坞对齐)
            AgentChatInputBar(
              viewModel: widget.viewModel,
              onSent: _scrollToBottom,
            ),
          ],
        ),
      ),
    );
  }

  /// 顶部预设切换栏 + 会话管理入口
  Widget _buildPresetHeaderBar() {
    final colors = context.colors;
    final currentPreset = widget.viewModel.currentPreset;
    final presets = widget.viewModel.presets;
    final currentPresetId = presets.any((p) => p.id == currentPreset.id)
        ? currentPreset.id
        : (presets.isNotEmpty ? presets.first.id : null);

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        border: Border(bottom: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 预设选择框 (与模型选择框统一的圆角边框胶囊样式)
          Expanded(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: colors.cardBackground,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.borderDefault),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: currentPresetId,
                  isDense: true,
                  isExpanded: true,
                  dropdownColor: colors.cardBackground,
                  icon: Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 18,
                    color: colors.textSecondary,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  menuMaxHeight: 400.0,
                  selectedItemBuilder: (context) {
                    return presets.map((preset) {
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.psychology_outlined,
                            size: 15,
                            color: colors.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              preset.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList();
                  },
                  items: presets.map((preset) {
                    final isSelected = preset.id == currentPresetId;
                    return DropdownMenuItem<String>(
                      value: preset.id,
                      child: Tooltip(
                        message: preset.description,
                        waitDuration: const Duration(milliseconds: 500),
                        child: Row(
                          children: [
                            Icon(
                              Icons.psychology_outlined,
                              size: 15,
                              color: isSelected
                                  ? colors.primary
                                  : colors.textMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                preset.name,
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? colors.primary
                                      : colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (presetId) {
                    if (presetId != null) {
                      final p = presets.firstWhere((e) => e.id == presetId);
                      widget.viewModel.selectPreset(p);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          if (widget.viewModel.isChatStreaming)
            AppIconButton(
              icon: Icons.stop_rounded,
              tooltip: context.l10n.chatStopOutput,
              iconColor: colors.error,
              variant: AppIconButtonVariant.ghost,
              onPressed: widget.viewModel.abortChat,
            ),
          AppIconButton(
            icon: Icons.add_comment_outlined,
            tooltip: context.l10n.sessionNew,
            variant: AppIconButtonVariant.ghost,
            onPressed: widget.viewModel.isChatStreaming
                ? null
                : () async {
                    await widget.viewModel.createNewSession();
                    if (mounted) _scrollToBottom(animate: false);
                  },
          ),
          IconButton(
            icon: Icon(Icons.forum_outlined, size: 16, color: colors.textMuted),
            tooltip: context.l10n.chatSessionManagementTooltip,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () => _switchView(_AgentCardView.sessions),
            visualDensity: VisualDensity.compact,
          ),
        ],
      ),
    );
  }

  /// 消息流: 历史消息 + 流式输出占位 + 内嵌提问卡片
  Widget _buildMessageList() {
    // 握把/触控拖拽手势期间以冻结快照渲染，延后实时内容增删
    final frozen = _extentFrozen;
    final messages = frozen ? _frozenMessages! : widget.viewModel.messages;
    final isStreaming = frozen
        ? _frozenStreamingActive
        : widget.viewModel.isChatStreaming;
    final activePrompt = frozen
        ? _frozenQuestion
        : widget.viewModel.activeQuestionPrompt;
    final thinkingExpanded = frozen
        ? _frozenThinkingExpanded
        : widget.viewModel.isThinkingExpanded;

    final liveIds = messages.map((message) => message.id).toSet();
    _messageWidgetCache.removeWhere((id, _) => !liveIds.contains(id));

    final list = ListView.builder(
      key: ValueKey(widget.viewModel.currentSessionId),
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      // 提高预渲染视口，配合 Widget 缓存让快速滚动不逐帧解析 Markdown
      scrollCacheExtent: const ScrollCacheExtent.pixels(600),
      addAutomaticKeepAlives: true,
      itemCount:
          messages.length +
          (isStreaming ? 1 : 0) +
          (activePrompt != null ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == messages.length && isStreaming) {
          // 流式增量局部刷新：只重建气泡子树，主工作台与参数面板零重绘；
          // 气泡内容增长时顺带驱动底部跟随滚动判定。
          // 拖拽冻结期间返回最近一次构建的气泡实体，内容高度不动
          return ListenableBuilder(
            listenable: widget.viewModel.streamingText,
            builder: (context, _) {
              final frozenBubble = _frozenStreamingBubble;
              if (_extentFrozen && frozenBubble != null) {
                return frozenBubble;
              }
              _autoScrollOnStream();
              final bubble = StreamingMessageBubble(
                thoughts: widget.viewModel.streamingText.thoughts,
                content: widget.viewModel.streamingText.content,
                thinkingExpanded: thinkingExpanded,
                notice: widget.viewModel.streamingText.notice,
              );
              _frozenStreamingBubble = bubble;
              return bubble;
            },
          );
        }
        if (activePrompt != null &&
            index == messages.length + (isStreaming ? 1 : 0)) {
          return InlineAgentQuestionCard(prompt: activePrompt);
        }

        final message = messages[index];
        final keepAlive = index >= messages.length - _maxKeptAliveMessages;
        final cached = _messageWidgetCache[message.id];
        if (cached != null &&
            identical(cached.message, message) &&
            cached.keepAlive == keepAlive &&
            cached.thinkingExpanded == thinkingExpanded) {
          return cached;
        }

        final built = AgentChatMessageItem(
          key: ValueKey(message.id),
          message: message,
          thinkingExpanded: thinkingExpanded,
          keepAlive: keepAlive,
        );
        if (_messageWidgetCache.length >= _maxCachedMessages &&
            !_messageWidgetCache.containsKey(message.id)) {
          _messageWidgetCache.remove(_messageWidgetCache.keys.first);
        }
        _messageWidgetCache[message.id] = built;
        return built;
      },
    );
    final theme = ScrollbarTheme.of(context);
    return StableScrollbar(
      controller: _scrollController,
      thumbColor: theme.thumbColor?.resolve({}),
      thickness: theme.thickness?.resolve({}),
      radius: theme.radius,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: list,
      ),
    );
  }
}
