import 'package:flutter/material.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../studio/view_models/studio_view_model.dart';

/// Bill 页：按周期统计各模型的 Token 用量账单 (只读)
///
/// 阶段 3 垂直切片：周期胶囊组 → AppSegmentedPillBar，
/// 空状态 → AppEmptyState，表格取色 → context.colors 语义色。
class BillSettingsTab extends StatefulWidget {
  final StudioViewModel viewModel;

  const BillSettingsTab({super.key, required this.viewModel});

  @override
  State<BillSettingsTab> createState() => _BillSettingsTabState();
}

class _BillSettingsTabState extends State<BillSettingsTab> {
  BillPeriod _billPeriod = BillPeriod.today;

  /// 缓存命中率单元格文案 (无数据时显示 -)
  String _hitRateLabel(TokenUsage usage) {
    final rate = usage.cacheHitRate;
    return rate == null ? '-' : '${(rate * 100).toStringAsFixed(1)}%';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final summary = widget.viewModel.buildBillSummary(_billPeriod);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(title: 'Usage Bill'),

          // 周期切换胶囊组
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Row(
              children: [
                AppSegmentedPillBar<BillPeriod>(
                  items: [
                    for (final period in BillPeriod.values)
                      AppSegmentedItem(value: period, label: period.label),
                  ],
                  selectedValue: _billPeriod,
                  onValueChanged: (period) =>
                      setState(() => _billPeriod = period),
                ),
                const Spacer(),
                Text(
                  '${summary.requests} 次请求 · 总计 ${UsageLedgerService.formatTokens(summary.usage.total)} tokens',
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ),
          ),

          // 账单表格
          if (summary.models.isEmpty)
            const AppEmptyState(
              icon: Icons.receipt_long_rounded,
              title: '该周期内暂无用量记录',
              isCompact: true,
            )
          else
            _buildBillTable(summary),
        ],
      ),
    );
  }

  /// 账单表格 (对齐 pi-bill 的列: Model / Reqs / Input / Output / Cache R / Total)
  Widget _buildBillTable(BillSummary summary) {
    final colors = context.colors;

    TextStyle headerStyle() => TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: colors.textMuted,
    );
    TextStyle cellStyle() => TextStyle(fontSize: 12, color: colors.textPrimary);
    TextStyle totalStyle() => TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: colors.textPrimary,
    );

    String fmt(int v) => UsageLedgerService.formatTokens(v);

    TableRow buildRow(
      List<String> cells, {
      TextStyle Function()? style,
      Color? background,
      bool topBorder = false,
    }) {
      return TableRow(
        decoration: BoxDecoration(
          color: background,
          border: topBorder
              ? Border(top: BorderSide(color: colors.borderDefault))
              : null,
        ),
        children: cells
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Text(c, style: style?.call() ?? cellStyle()),
              ),
            )
            .toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: colors.borderDefault),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.6),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1.1),
          3: FlexColumnWidth(1.1),
          4: FlexColumnWidth(1.1),
          5: FlexColumnWidth(1.1),
          6: FlexColumnWidth(1),
        },
        children: [
          buildRow(
            const ['模型', '请求数', '输入', '输出', '缓存读', '命中率', '总计'],
            style: headerStyle,
            background: colors.mutedBackground,
          ),
          for (final model in summary.models)
            buildRow([
              model.name,
              model.requests.toString(),
              fmt(model.usage.input),
              fmt(model.usage.output),
              fmt(model.usage.cacheRead),
              _hitRateLabel(model.usage),
              fmt(model.usage.total),
            ]),
          buildRow(
            [
              'Total',
              summary.requests.toString(),
              fmt(summary.usage.input),
              fmt(summary.usage.output),
              fmt(summary.usage.cacheRead),
              _hitRateLabel(summary.usage),
              fmt(summary.usage.total),
            ],
            style: totalStyle,
            background: colors.mutedBackground,
            topBorder: true,
          ),
        ],
      ),
    );
  }
}
