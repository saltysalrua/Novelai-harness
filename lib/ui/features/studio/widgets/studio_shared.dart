import 'package:flutter/material.dart';

import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/context_l10n.dart';

/// 侧边栏页面标题与可选副标题 (参数设置 / 提示词管理页首复用)
class PageHeader extends StatelessWidget {
  final String title;
  final String? subtitle;

  const PageHeader({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ],
    );
  }
}

/// 参数小节标题 (模型 / Seed / Sampler 等)
class SectionHeader extends StatelessWidget {
  final String title;

  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: context.colors.textPrimary,
      ),
    );
  }
}

/// 轻量"清空"文字按钮 (提示词输入框右上角复用)
class ClearTextLink extends StatelessWidget {
  final VoidCallback onTap;

  const ClearTextLink({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          context.l10n.clear,
          style: TextStyle(fontSize: 11, color: context.colors.textMuted),
        ),
      ),
    );
  }
}

/// 侧栏与主卡片无缝拼接专用的圆角边框形状：
/// 支持仅左端圆角（供 [StudioSidebar] 与右侧卡片紧贴）或仅右端圆角（供 [ParameterCard]、
/// [PromptLibraryView] 与左侧边栏无缝衔接），并在需要时在右侧接缝绘制 1px 细分割线，
/// 避免直接给非均匀 `Border` 传 `borderRadius` 触发 Flutter 断言错误。
class StudioPanelShapeBorder extends ShapeBorder {
  final BorderSide outerSide;
  final BorderSide? rightDividerSide;
  final double radius;
  final bool roundLeft;
  final bool roundRight;

  const StudioPanelShapeBorder({
    required this.outerSide,
    this.rightDividerSide,
    this.radius = AppRadius.lg,
    this.roundLeft = true,
    this.roundRight = true,
  });

  double get _w => outerSide.width;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.fromLTRB(
    roundLeft ? _w : 0.0,
    _w,
    roundRight ? _w : (rightDividerSide?.width ?? 0.0),
    _w,
  );

  @override
  ShapeBorder scale(double t) => StudioPanelShapeBorder(
    outerSide: outerSide.scale(t),
    rightDividerSide: rightDividerSide?.scale(t),
    radius: radius * t,
    roundLeft: roundLeft,
    roundRight: roundRight,
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final leftRadius = roundLeft ? Radius.circular(radius) : Radius.zero;
    final rightRadius = roundRight ? Radius.circular(radius) : Radius.zero;
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: leftRadius,
        bottomLeft: leftRadius,
        topRight: rightRadius,
        bottomRight: rightRadius,
      ),
    );
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final inner = dimensions.resolve(textDirection).deflateRect(rect);
    final innerRadius = (radius - _w).clamp(0.0, radius);
    final leftRadius = roundLeft ? Radius.circular(innerRadius) : Radius.zero;
    final rightRadius = roundRight
        ? Radius.circular(innerRadius)
        : Radius.zero;
    return Path()..addRRect(
      RRect.fromRectAndCorners(
        inner,
        topLeft: leftRadius,
        bottomLeft: leftRadius,
        topRight: rightRadius,
        bottomRight: rightRadius,
      ),
    );
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (outerSide.style == BorderStyle.none || rect.isEmpty) return;

    final half = _w / 2;
    final strokeRadius = (radius - half).clamp(0.0, radius);
    final paint = outerSide.toPaint()..style = PaintingStyle.stroke;

    if (roundLeft && roundRight) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect.deflate(half), Radius.circular(strokeRadius)),
        paint,
      );
      return;
    }

    final path = Path();
    if (roundLeft) {
      // 上边从右端接缝向左绘制到左圆角 -> 左边 -> 下边回右端接缝
      path
        ..moveTo(rect.right, rect.top + half)
        ..lineTo(rect.left + radius, rect.top + half)
        ..arcToPoint(
          Offset(rect.left + half, rect.top + radius),
          radius: Radius.circular(strokeRadius),
          clockwise: false,
        )
        ..lineTo(rect.left + half, rect.bottom - radius)
        ..arcToPoint(
          Offset(rect.left + radius, rect.bottom - half),
          radius: Radius.circular(strokeRadius),
          clockwise: false,
        )
        ..lineTo(rect.right, rect.bottom - half);
    } else if (roundRight) {
      // 上边从左端接缝向右绘制到右圆角 -> 右边 -> 下边回左端接缝
      path
        ..moveTo(rect.left, rect.top + half)
        ..lineTo(rect.right - radius, rect.top + half)
        ..arcToPoint(
          Offset(rect.right - half, rect.top + radius),
          radius: Radius.circular(strokeRadius),
          clockwise: true,
        )
        ..lineTo(rect.right - half, rect.bottom - radius)
        ..arcToPoint(
          Offset(rect.right - radius, rect.bottom - half),
          radius: Radius.circular(strokeRadius),
          clockwise: true,
        )
        ..lineTo(rect.left, rect.bottom - half);
    } else {
      path
        ..moveTo(rect.left, rect.top + half)
        ..lineTo(rect.right, rect.top + half)
        ..moveTo(rect.left, rect.bottom - half)
        ..lineTo(rect.right, rect.bottom - half);
    }
    canvas.drawPath(path, paint);

    final divider = rightDividerSide;
    if (!roundRight &&
        divider != null &&
        divider.style != BorderStyle.none) {
      final dividerX = rect.right - divider.width / 2;
      canvas.drawLine(
        Offset(dividerX, rect.top + _w),
        Offset(dividerX, rect.bottom - _w),
        divider.toPaint(),
      );
    }
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StudioPanelShapeBorder &&
        other.outerSide == outerSide &&
        other.rightDividerSide == rightDividerSide &&
        other.radius == radius &&
        other.roundLeft == roundLeft &&
        other.roundRight == roundRight;
  }

  @override
  int get hashCode =>
      Object.hash(outerSide, rightDividerSide, radius, roundLeft, roundRight);
}

/// 将标签按逗号规范追加到提示词末尾 (提示词编辑器与画板快捷标签库共用)
String appendTagToPromptText(String current, String tag) {
  final trimmed = current.trim();
  if (trimmed.isEmpty) return tag;
  return trimmed.endsWith(',') ? '$trimmed $tag' : '$trimmed, $tag';
}

/// 统一生成操作按钮文案 (GenerateDock 与画板快捷生成按钮共用)
String resolveGenerateActionLabel(
  BuildContext context, {
  required bool isGenerating,
  required int currentStep,
  required int totalSteps,
  required int estimatedCost,
  bool compact = false,
}) {
  final l10n = context.l10n;
  if (isGenerating) {
    if (totalSteps > 0 && currentStep > 0) {
      return compact
          ? '$currentStep/$totalSteps'
          : l10n.dockAbortWithSteps(currentStep, totalSteps);
    }
    return compact ? l10n.canvasQuickAbort : l10n.abortGeneration;
  }
  if (compact) {
    return estimatedCost > 0
        ? '${l10n.canvasQuickGenerate} ($estimatedCost)'
        : l10n.canvasQuickGenerate;
  }
  if (estimatedCost > 0) {
    return l10n.dockGenerateWithCost(estimatedCost);
  }
  if (estimatedCost < 0) {
    return l10n.dockGenerateNeedPoints;
  }
  return l10n.generateImage;
}

/// 统一生成操作按钮主色 (GenerateDock 与画板快捷生成按钮共用)
Color resolveGenerateActionColor(
  BuildContext context, {
  required bool isGenerating,
  required int estimatedCost,
}) {
  final colors = context.colors;
  if (isGenerating) return colors.error;
  if (estimatedCost != 0) return colors.warning;
  return colors.primary;
}

