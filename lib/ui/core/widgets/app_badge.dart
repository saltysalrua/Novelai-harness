import 'package:flutter/material.dart';
import '../theme/app_motion.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 徽章语义视觉变体
enum AppBadgeVariant {
  /// 主色强调 (浅蓝底 + 品牌蓝文字)
  primary,

  /// 成功语义 (浅绿底 + 绿字)
  success,

  /// 警告语义 (浅橙底 + 橙字)
  warning,

  /// 错误语义 (浅红底 + 红字)
  error,

  /// 中性次级 (灰底 + 次级深灰字)
  neutral,

  /// 画面角标沉浸式暗黑遮罩 (半透明黑底 + 白字，适合图片覆盖角标)
  dark,
}

/// 徽章外观形状
enum AppBadgeShape {
  /// 微圆角形状 (4px，用于序号、状态方块、Prefix/Suffix 标签)
  rounded,

  /// 胶囊药丸形状 (9999px，用于 V5、等级、分类标签)
  pill,
}

/// 统一状态徽章与胶囊组件 (`AppBadge`, `03-notification-badge`)
///
/// 代码证据出处：
/// - `inpaint_canvas_overlay.dart:800` & `inpaint_page.dart:524` (Opus 免费/需消耗点数胶囊)
/// - `studio_shared.dart:90-108` (V5 蓝底药丸)
/// - `generate_dock.dart:93-113` (订阅等级 Tier 徽章)
/// - `canvas_history_sidebar.dart:230-245` (缩略图来源角标)
/// - `prompt_combo_card.dart:180-195` (分类标签 Tag)
/// - `tag_suggestion_tile.dart:6-30` (TagCategoryPill 分类胶囊)
/// - `metadata_reader_dialog.dart:238` (来源软件胶囊)
/// - `inline_agent_question_card.dart:143` (待确认胶囊)
/// - `character_card_item.dart:191` (角色序号角标)
/// - `fixed_affixes_panel.dart:125` (PREFIX/SUFFIX 徽标)
/// - `skill_card.dart:83` & `tool_card.dart:87` (内置/自定义徽标)
/// - `model_card.dart:181` (_CapabilityChip 思考/多模态能力胶囊)
///
/// 核心职责：
/// 统一全应用 12+ 处手写的状态胶囊与标签外观，收拢背景透明度、字号 (9.5~11.5px)、边框及圆角规范；
/// 在初次出现或标签数值变化时呈现轻巧的对角滑入与回弹弹出 (`03-notification-badge`)，并安全适配减弱动画。
class AppBadge extends StatefulWidget {
  /// 徽标显示文本
  final String label;

  /// 前缀小图标 (可选)
  final IconData? icon;

  /// 尾部微控件 (如关闭叉号、删除等，可选)
  final Widget? trailing;

  /// 语义变体，默认 [AppBadgeVariant.primary]
  final AppBadgeVariant variant;

  /// 外观形状，默认 [AppBadgeShape.rounded]
  final AppBadgeShape shape;

  /// 文字字号，默认 11.0
  final double fontSize;

  /// 图标大小，默认 11.0
  final double iconSize;

  /// 自定义背景色 (覆盖变体预设)
  final Color? customBackgroundColor;

  /// 自定义前景色 (覆盖变体预设)
  final Color? customForegroundColor;

  /// 自定义边框颜色
  final Color? customBorderColor;

  /// 自定义内边距；若未指定则依据形状与字号自适应
  final EdgeInsetsGeometry? padding;

  const AppBadge({
    super.key,
    required this.label,
    this.icon,
    this.trailing,
    this.variant = AppBadgeVariant.primary,
    this.shape = AppBadgeShape.rounded,
    this.fontSize = 11.0,
    this.iconSize = 11.0,
    this.customBackgroundColor,
    this.customForegroundColor,
    this.customBorderColor,
    this.padding,
  });

  /// 极简便捷工厂：药丸形态
  factory AppBadge.pill({
    Key? key,
    required String label,
    IconData? icon,
    Widget? trailing,
    AppBadgeVariant variant = AppBadgeVariant.primary,
    double fontSize = 11.0,
    Color? customBackgroundColor,
    Color? customForegroundColor,
    Color? customBorderColor,
  }) {
    return AppBadge(
      key: key,
      label: label,
      icon: icon,
      trailing: trailing,
      variant: variant,
      shape: AppBadgeShape.pill,
      fontSize: fontSize,
      customBackgroundColor: customBackgroundColor,
      customForegroundColor: customForegroundColor,
      customBorderColor: customBorderColor,
    );
  }

  @override
  State<AppBadge> createState() => _AppBadgeState();
}

class _AppBadgeState extends State<AppBadge>
    with SingleTickerProviderStateMixin {
  static const Offset _appearOffset = Offset(-4.0, 6.0);

  late final AnimationController _controller;
  bool _reduceMotion = false;
  bool _initialized = false;
  bool _isCountUpdate = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.verySlow,
      value: 0.0,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = AppMotion.shouldReduceMotion(context);
    if (_reduceMotion) {
      _controller.value = 1.0;
      _initialized = true;
    } else if (!_initialized) {
      _initialized = true;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void didUpdateWidget(covariant AppBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.label != widget.label) {
      _isCountUpdate = true;
      if (_reduceMotion) {
        _controller.value = 1.0;
      } else {
        _controller.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    final (Color bg, Color fg, Color? border) = switch (widget.variant) {
      AppBadgeVariant.primary => (
        colors.primaryTint,
        colors.primary,
        colors.primary.withValues(alpha: 0.25),
      ),
      AppBadgeVariant.success => (
        colors.success.withValues(alpha: 0.12),
        colors.success,
        colors.success.withValues(alpha: 0.25),
      ),
      AppBadgeVariant.warning => (
        colors.warning.withValues(alpha: 0.12),
        colors.warning,
        colors.warning.withValues(alpha: 0.25),
      ),
      AppBadgeVariant.error => (
        colors.errorSurface,
        colors.error,
        colors.error.withValues(alpha: 0.25),
      ),
      AppBadgeVariant.neutral => (
        colors.mutedBackground,
        colors.textSecondary,
        colors.borderSubtle,
      ),
      AppBadgeVariant.dark => (
        Colors.black.withValues(alpha: 0.65),
        Colors.white,
        null,
      ),
    };

    final effectiveBg = widget.customBackgroundColor ?? bg;
    final effectiveFg = widget.customForegroundColor ?? fg;
    final effectiveBorder = widget.customBorderColor ?? border;

    final double borderRadiusVal = switch (widget.shape) {
      AppBadgeShape.rounded => AppRadius.sm,
      AppBadgeShape.pill => AppRadius.pill,
    };

    final effectivePadding =
        widget.padding ??
        (widget.shape == AppBadgeShape.pill
            ? const EdgeInsets.symmetric(horizontal: 7.5, vertical: 2.5)
            : const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2.0));

    final badgeBody = AnimatedContainer(
      duration: AppMotion.resolveDuration(context, AppMotionDurations.quick),
      curve: AppMotionCurves.smoothOut,
      padding: effectivePadding,
      decoration: BoxDecoration(
        color: effectiveBg.a == 0 ? null : effectiveBg,
        borderRadius: BorderRadius.circular(borderRadiusVal),
        border: effectiveBorder != null
            ? Border.all(color: effectiveBorder)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.icon != null) ...[
            Icon(widget.icon, size: widget.iconSize, color: effectiveFg),
            const SizedBox(width: 3.5),
          ],
          Text(
            widget.label,
            style: TextStyle(
              fontSize: widget.fontSize,
              fontWeight: FontWeight.w700,
              color: effectiveFg,
              height: 1.15,
            ),
          ),
          if (widget.trailing != null) ...[
            const SizedBox(width: 3.5),
            widget.trailing!,
          ],
        ],
      ),
    );

    if (_reduceMotion) {
      return badgeBody;
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final v = _controller.value;
        if (v >= 1.0) return child!;

        // 03-notification-badge: 250ms 位移、500ms 弹性缩放 (仅空间变换)、400ms 安全淡入
        final slideFrac = (v / 0.52).clamp(0.0, 1.0);
        final fadeFrac = (v / 0.80).clamp(0.0, 1.0);
        final slideT = AppMotionCurves.smoothOut
            .transform(slideFrac)
            .clamp(0.0, 1.0);
        final popT = AppMotionCurves.bounce.transform(v);
        final fadeT = AppMotionCurves.smoothOut
            .transform(fadeFrac)
            .clamp(0.0, 1.0);

        final startScale = _isCountUpdate ? 0.72 : 0.0;
        final startOffset = _isCountUpdate
            ? const Offset(-2.0, 3.0)
            : _appearOffset;
        final startOpacity = _isCountUpdate ? 0.5 : 0.0;

        final scale = startScale + (1.0 - startScale) * popT;
        final offset = Offset(
          startOffset.dx * (1.0 - slideT),
          startOffset.dy * (1.0 - slideT),
        );
        final opacity = (startOpacity + (1.0 - startOpacity) * fadeT).clamp(
          0.0,
          1.0,
        );

        return Opacity(
          opacity: opacity,
          child: Transform.translate(
            offset: offset,
            child: Transform.scale(scale: scale, child: child),
          ),
        );
      },
      child: badgeBody,
    );
  }
}
