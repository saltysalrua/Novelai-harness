import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// Toast 与堆叠横幅的语义色调
enum AppToastTone {
  /// 常规信息提示
  info,

  /// 成功完成反馈
  success,

  /// 警告提醒
  warning,

  /// 错误阻断提示
  error,
}

/// 统一的轻量化 Toast / Banner 卡片外观组件
class AppToastCard extends StatelessWidget {
  /// 主提示文案
  final String message;

  /// 可选标题 (多用于堆叠横幅)
  final String? title;

  /// 语义色调，默认 [AppToastTone.info]
  final AppToastTone tone;

  /// 自定义图标；为空时按 [tone] 自动选取
  final IconData? icon;

  /// 可选右侧操作按钮文案
  final String? actionLabel;

  /// 操作按钮回调
  final VoidCallback? onAction;

  /// 关闭按钮回调；非空时显示关闭按钮
  final VoidCallback? onDismiss;

  /// 最大宽度限制
  final double maxWidth;

  const AppToastCard({
    super.key,
    required this.message,
    this.title,
    this.tone = AppToastTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
    this.onDismiss,
    this.maxWidth = 420,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final (Color accentColor, IconData defaultIcon) = switch (tone) {
      AppToastTone.info => (colors.info, Icons.info_outline_rounded),
      AppToastTone.success => (colors.success, Icons.check_circle_outline_rounded),
      AppToastTone.warning => (colors.warning, Icons.warning_amber_rounded),
      AppToastTone.error => (colors.error, Icons.error_outline_rounded),
    };

    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm + 2,
          ),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: colors.borderDefault),
            boxShadow: context.shadowElevated,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: title != null
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: title != null ? 1 : 0),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.sm + 2),
                  ),
                  child: Icon(
                    icon ?? defaultIcon,
                    size: 15,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (title != null && title!.isNotEmpty) ...[
                      Text(
                        title!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                    ],
                    Text(
                      message,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: title != null
                            ? colors.textSecondary
                            : colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: onAction,
                  style: TextButton.styleFrom(
                    foregroundColor: colors.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Text(
                    actionLabel!,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
              if (onDismiss != null) ...[
                const SizedBox(width: AppSpacing.xs),
                InkWell(
                  onTap: onDismiss,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  child: Padding(
                    padding: const EdgeInsets.all(2),
                    child: Icon(
                      Icons.close_rounded,
                      size: 15,
                      color: colors.textMuted,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

VoidCallback? _activeToastDismiss;

/// 弹出非阻塞底部浮层 Toast (`22-toast`)
///
/// 动画特征：
/// - 打开：350ms `smoothOut`，自下方 16px 升起 + `0.97 -> 1.0` 缩放 + 淡入 + 可选 2px 轻模糊；
/// - 关闭：250ms `smoothOut` 反向收起；
/// - 减弱动态效果开启时即时切换；自动替换上一条仍在显示的 Toast。
///
/// 返回手动关闭回调，调用方也可忽略返回值。
VoidCallback showAppToast(
  BuildContext context, {
  required String message,
  String? title,
  AppToastTone tone = AppToastTone.info,
  IconData? icon,
  Duration duration = const Duration(seconds: 3),
  String? actionLabel,
  VoidCallback? onAction,
  Alignment alignment = Alignment.bottomCenter,
  EdgeInsetsGeometry margin = const EdgeInsets.all(AppSpacing.xxl),
  bool enableBlur = true,
}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return () {};

  _activeToastDismiss?.call();

  late OverlayEntry entry;
  var removed = false;
  final toastKey = GlobalKey<_AppToastOverlayState>();

  void removeEntry() {
    if (removed) return;
    removed = true;
    if (entry.mounted) {
      entry.remove();
    }
  }

  void dismiss() {
    if (removed) return;
    final state = toastKey.currentState;
    if (state != null) {
      state.dismiss();
    } else {
      removeEntry();
    }
  }

  _activeToastDismiss = dismiss;

  entry = OverlayEntry(
    builder: (overlayContext) => _AppToastOverlay(
      key: toastKey,
      message: message,
      title: title,
      tone: tone,
      icon: icon,
      duration: duration,
      actionLabel: actionLabel,
      onAction: onAction,
      alignment: alignment,
      margin: margin,
      enableBlur: enableBlur,
      onDismissed: () {
        if (identical(_activeToastDismiss, dismiss)) {
          _activeToastDismiss = null;
        }
        removeEntry();
      },
    ),
  );

  overlay.insert(entry);
  return dismiss;
}

class _AppToastOverlay extends StatefulWidget {
  final String message;
  final String? title;
  final AppToastTone tone;
  final IconData? icon;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Alignment alignment;
  final EdgeInsetsGeometry margin;
  final bool enableBlur;
  final VoidCallback onDismissed;

  const _AppToastOverlay({
    super.key,
    required this.message,
    this.title,
    required this.tone,
    this.icon,
    required this.duration,
    this.actionLabel,
    this.onAction,
    required this.alignment,
    required this.margin,
    required this.enableBlur,
    required this.onDismissed,
  });

  @override
  State<_AppToastOverlay> createState() => _AppToastOverlayState();
}

class _AppToastOverlayState extends State<_AppToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  Timer? _autoDismissTimer;
  bool _reduceMotion = false;
  bool _dismissing = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.toastOpen,
      reverseDuration: AppMotionDurations.toastClose,
    );
    _controller.addStatusListener(_handleStatus);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward();
      }
      _startAutoTimer();
    });
  }

  void _startAutoTimer() {
    _autoDismissTimer?.cancel();
    if (widget.duration > Duration.zero) {
      _autoDismissTimer = Timer(widget.duration, dismiss);
    }
  }

  void _handleStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && _dismissing) {
      widget.onDismissed();
    }
  }

  void dismiss() {
    if (_dismissing || !mounted) return;
    _dismissing = true;
    _autoDismissTimer?.cancel();
    if (_reduceMotion) {
      widget.onDismissed();
      return;
    }
    if (_controller.value <= 0.0) {
      widget.onDismissed();
    } else {
      _controller.reverse();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion && !_dismissing) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _autoDismissTimer?.cancel();
    _controller.removeStatusListener(_handleStatus);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final card = AppToastCard(
      message: widget.message,
      title: widget.title,
      tone: widget.tone,
      icon: widget.icon,
      actionLabel: widget.actionLabel,
      onAction: widget.onAction == null
          ? null
          : () {
              widget.onAction!();
              dismiss();
            },
      onDismiss: dismiss,
    );

    final Widget animatedCard = _reduceMotion
        ? card
        : AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final t = AppMotionCurves.smoothOut
                  .transform(_controller.value)
                  .clamp(0.0, 1.0);
              final dy = AppMotionDistances.toast * (1.0 - t);
              final scale =
                  AppMotionScales.dropdown +
                  (1.0 - AppMotionScales.dropdown) * t;
              final sigma = AppMotionBlurs.small * (1.0 - t);
              Widget res = Opacity(
                opacity: t,
                child: Transform.translate(
                  offset: Offset(0, dy),
                  child: Transform.scale(scale: scale, child: child),
                ),
              );
              if (widget.enableBlur && sigma > 0.05) {
                res = ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
                  child: res,
                );
              }
              return res;
            },
            child: card,
          );

    return SafeArea(
      child: IgnorePointer(
        ignoring: false,
        child: Align(
          alignment: widget.alignment,
          child: Padding(padding: widget.margin, child: animatedCard),
        ),
      ),
    );
  }
}

/// 堆叠横幅条目的数据模型 (`32-banner-stacking`)
class AppBannerItem {
  /// 唯一标识
  final String id;

  /// 主内容文本
  final String message;

  /// 可选标题
  final String? title;

  /// 语义色调
  final AppToastTone tone;

  /// 可选图标
  final IconData? icon;

  /// 可选操作按钮
  final String? actionLabel;

  /// 操作按钮回调
  final VoidCallback? onAction;

  const AppBannerItem({
    required this.id,
    required this.message,
    this.title,
    this.tone = AppToastTone.info,
    this.icon,
    this.actionLabel,
    this.onAction,
  });
}

/// 堆叠横幅队列控制器 (`32-banner-stacking`)
///
/// 按最新优先排序；支持自动定时关闭与手动关闭。
class AppBannerController extends ChangeNotifier {
  final List<AppBannerItem> _items = [];
  final Map<String, Timer> _timers = {};
  int _seq = 0;

  /// 当前可见队列 (最新条目位于索引 0)
  List<AppBannerItem> get items => List.unmodifiable(_items);

  /// 推入一条新横幅到栈顶，返回生成的唯一 ID
  String push({
    String? id,
    required String message,
    String? title,
    AppToastTone tone = AppToastTone.info,
    IconData? icon,
    String? actionLabel,
    VoidCallback? onAction,
    Duration? autoDismiss = const Duration(seconds: 4),
  }) {
    final resolvedId = id ?? 'banner_${++_seq}';
    _timers.remove(resolvedId)?.cancel();
    _items.removeWhere((item) => item.id == resolvedId);
    _items.insert(
      0,
      AppBannerItem(
        id: resolvedId,
        message: message,
        title: title,
        tone: tone,
        icon: icon,
        actionLabel: actionLabel,
        onAction: onAction,
      ),
    );
    if (autoDismiss != null && autoDismiss > Duration.zero && hasListeners) {
      _timers[resolvedId] = Timer(autoDismiss, () => dismiss(resolvedId));
    }
    notifyListeners();
    return resolvedId;
  }

  /// 移除指定 ID 的横幅
  void dismiss(String id) {
    _timers.remove(id)?.cancel();
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length != before) {
      notifyListeners();
    }
  }

  /// 清空全部横幅
  void clear() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    if (_items.isNotEmpty) {
      _items.clear();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    for (final timer in _timers.values) {
      timer.cancel();
    }
    _timers.clear();
    super.dispose();
  }
}

/// 多条通知叠加与悬停展开容器 (`32-banner-stacking`)
///
/// - 新条目从下方升起 (`350ms smoothOut`) 占据 depth 0；
/// - 历史条目依次后退缩小、透明化 (默认最多叠放 3 条，超出自动淘汰最旧条目)；
/// - 鼠标悬停时平滑展开为清晰可读的垂直列表，移出后收拢叠放。
class AppBannerStack extends StatefulWidget {
  /// 可选外部控制器 (与 [items] 二选一)
  final AppBannerController? controller;

  /// 声明式传入横幅列表 (最新条目在索引 0)
  final List<AppBannerItem>? items;

  /// 用户点击关闭时的回调 (使用 [controller] 时默认自动调用 `controller.dismiss`)
  final ValueChanged<String>? onDismiss;

  /// 最多同时展示的叠放层数，默认 3
  final int maxVisible;

  /// 叠放态下相邻层露出的纵向窥视偏移，默认 12.0
  final double peekOffset;

  /// 悬停展开态下条目间距，默认 8.0
  final double spreadGap;

  /// 每一层递减的缩放步长，默认 0.06
  final double depthScaleStep;

  /// 每一层递减的不透明度步长，默认 0.4
  final double depthFadeStep;

  /// 横幅宽度，默认 360.0
  final double width;

  /// 单条卡片预估高度 (用于叠放与展开高度计算)，默认 64.0
  final double itemExtent;

  /// 是否从顶部向下堆叠展开（用于右上角等顶栏下方悬浮场景），默认 false（从底部向上）
  final bool stackFromTop;

  const AppBannerStack({
    super.key,
    this.controller,
    this.items,
    this.onDismiss,
    this.maxVisible = 3,
    this.peekOffset = 12.0,
    this.spreadGap = 8.0,
    this.depthScaleStep = 0.06,
    this.depthFadeStep = 0.4,
    this.width = 360.0,
    this.itemExtent = 64.0,
    this.stackFromTop = false,
  });

  @override
  State<AppBannerStack> createState() => _AppBannerStackState();
}

class _AppBannerStackState extends State<AppBannerStack> {
  bool _isSpread = false;

  @override
  void initState() {
    super.initState();
    widget.controller?.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant AppBannerStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller?.removeListener(_onControllerChanged);
      widget.controller?.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _handleDismiss(String id) {
    if (widget.onDismiss != null) {
      widget.onDismiss!(id);
    } else {
      widget.controller?.dismiss(id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.controller?.items ?? widget.items ?? const [];
    final visible = source.take(widget.maxVisible.clamp(1, 5)).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    final reduceMotion = AppMotion.shouldReduceMotion(context);
    final animDuration = reduceMotion
        ? Duration.zero
        : AppMotionDurations.toastOpen;

    final int count = visible.length;
    final double stackHeight = _isSpread
        ? count * widget.itemExtent + (count - 1) * widget.spreadGap
        : widget.itemExtent + (count - 1) * widget.peekOffset;

    return MouseRegion(
      onEnter: (_) => setState(() => _isSpread = true),
      onExit: (_) => setState(() => _isSpread = false),
      child: AnimatedContainer(
        duration: animDuration,
        curve: AppMotionCurves.smoothOut,
        width: widget.width,
        height: stackHeight,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: widget.stackFromTop
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          children: [
            // 先绘深层，再绘浅层，保证 depth 0 永远位于最前
            for (var depth = count - 1; depth >= 0; depth--)
              _buildStackedBanner(
                item: visible[depth],
                depth: depth,
                animDuration: animDuration,
                reduceMotion: reduceMotion,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStackedBanner({
    required AppBannerItem item,
    required int depth,
    required Duration animDuration,
    required bool reduceMotion,
  }) {
    final double offset = _isSpread
        ? depth * (widget.itemExtent + widget.spreadGap)
        : depth * widget.peekOffset;
    final double scale = _isSpread
        ? 1.0
        : (1.0 - depth * widget.depthScaleStep).clamp(0.7, 1.0);
    final double opacity = _isSpread
        ? 1.0
        : (1.0 - depth * widget.depthFadeStep * (depth >= 2 ? 1.2 : 1.0)).clamp(
            0.2,
            1.0,
          );

    return AnimatedPositioned(
      key: ValueKey<String>(item.id),
      duration: animDuration,
      curve: AppMotionCurves.smoothOut,
      left: 0,
      right: 0,
      top: widget.stackFromTop ? offset : null,
      bottom: widget.stackFromTop ? null : offset,
      child: AnimatedOpacity(
        duration: animDuration,
        curve: AppMotionCurves.smoothOut,
        opacity: opacity,
        child: AnimatedScale(
          duration: animDuration,
          curve: AppMotionCurves.smoothOut,
          scale: scale,
          alignment: widget.stackFromTop
              ? Alignment.topCenter
              : Alignment.bottomCenter,
          child: _BannerArrivalWrapper(
            reduceMotion: reduceMotion,
            fromTop: widget.stackFromTop,
            child: AppToastCard(
              title: item.title,
              message: item.message,
              tone: item.tone,
              icon: item.icon,
              actionLabel: item.actionLabel,
              onAction: item.onAction,
              onDismiss: () => _handleDismiss(item.id),
              maxWidth: widget.width,
            ),
          ),
        ),
      ),
    );
  }
}

class _BannerArrivalWrapper extends StatefulWidget {
  final Widget child;
  final bool reduceMotion;
  final bool fromTop;

  const _BannerArrivalWrapper({
    required this.child,
    required this.reduceMotion,
    this.fromTop = false,
  });

  @override
  State<_BannerArrivalWrapper> createState() => _BannerArrivalWrapperState();
}

class _BannerArrivalWrapperState extends State<_BannerArrivalWrapper>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.toastOpen,
      value: widget.reduceMotion ? 1.0 : 0.0,
    );
    if (!widget.reduceMotion) {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant _BannerArrivalWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion && _controller.value < 1.0) {
      _controller.value = 1.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.reduceMotion) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, innerChild) {
        final t = AppMotionCurves.smoothOut
            .transform(_controller.value)
            .clamp(0.0, 1.0);
        final dy =
            (widget.fromTop
                ? -AppMotionDistances.toast
                : AppMotionDistances.toast) *
            (1.0 - t);
        final scale =
            AppMotionScales.dropdown + (1.0 - AppMotionScales.dropdown) * t;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, dy),
            child: Transform.scale(scale: scale, child: innerChild),
          ),
        );
      },
      child: widget.child,
    );
  }
}
