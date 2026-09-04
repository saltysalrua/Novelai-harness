import 'package:flutter/material.dart';
import '../theme/app_tokens.dart';
import '../theme/theme_context_extensions.dart';

/// 统一空状态占位展示组件 (Empty State)
///
/// 代码证据出处：
/// - `prompt_library_view.dart:709-745` (提示词库空数据占位)
/// - `models_settings_tab.dart:1020-1034` (模型列表暂无可用模型)
/// - `agent_session_list_view.dart:315-325` (历史对话记录为空)
/// - `agent_rewind_view.dart:180-190` (暂无可回溯轮次)
/// - `canvas_overlays.dart:293-315` (`CanvasEmptyState` 画板暂无图像)
/// - `bill_settings_tab.dart:93-105` (用量账单周期内无记录)
///
/// 核心职责：
/// 统一列表、表格或画板无数据时的图标规格 (24~44px)、主标题与副标题对齐排版，
/// 支持可选动作操作按钮 (新建/刷新/清空筛选)，提供标准与紧凑 (compact) 两种排版规格。
class AppEmptyState extends StatelessWidget {
  /// 主占位大图标
  final IconData icon;

  /// 主标题文字
  final String title;

  /// 副提示与操作指引说明 (可选)
  final String? description;

  /// 自定义底部操作按钮组件 (优先级高于 [actionLabel])
  final Widget? action;

  /// 快速操作按钮文案 (如 "新建词组合"、"拉取模型")
  final String? actionLabel;

  /// 快速操作按钮图标
  final IconData? actionIcon;

  /// 快速操作按钮点击回调
  final VoidCallback? onActionPressed;

  /// 是否为紧凑微型形态 (适用于侧栏短列表或弹窗内小区域)
  final bool isCompact;

  /// 内边距，默认为宽松居中边距
  final EdgeInsetsGeometry? padding;

  /// 图标大小覆盖 (默认标准 44px，紧凑 28px)
  final double? iconSize;

  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.description,
    this.action,
    this.actionLabel,
    this.actionIcon,
    this.onActionPressed,
    this.isCompact = false,
    this.padding,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final effectiveIconSize = iconSize ?? (isCompact ? 28.0 : 44.0);
    final effectivePadding = padding ??
        (isCompact
            ? const EdgeInsets.symmetric(horizontal: 16, vertical: 20)
            : const EdgeInsets.symmetric(horizontal: 24, vertical: 36));

    Widget? actionWidget = action;
    if (actionWidget == null && actionLabel != null && onActionPressed != null) {
      actionWidget = OutlinedButton.icon(
        onPressed: onActionPressed,
        icon: actionIcon != null ? Icon(actionIcon, size: 14) : const SizedBox.shrink(),
        label: Text(actionLabel!),
        style: OutlinedButton.styleFrom(
          foregroundColor: colors.textPrimary,
          side: BorderSide(color: colors.borderDefault),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: effectivePadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: effectiveIconSize,
              color: colors.textMuted.withValues(alpha: 0.5),
            ),
            SizedBox(height: isCompact ? AppSpacing.sm : AppSpacing.md),
            Text(
              title,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: isCompact ? 13.0 : 14.5,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
            if (description != null && description!.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: isCompact ? 11.0 : 12.0,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
            ],
            if (actionWidget != null) ...[
              SizedBox(height: isCompact ? AppSpacing.md : AppSpacing.lg),
              actionWidget,
            ],
          ],
        ),
      ),
    );
  }
}
