import 'package:flutter/material.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_control_flow.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
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
  late final SmoothWheelScrollController _scrollController =
      SmoothWheelScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// 缓存命中率单元格文案 (无数据时显示 -)
  String _hitRateLabel(TokenUsage usage) {
    final rate = usage.cacheHitRate;
    if (rate != null) return '${(rate * 100).toStringAsFixed(1)}%';
    if (usage.totalInput == 0) return '-';
    return usage.cacheRead > 0
        ? context.l10n.cacheUsagePartial
        : context.l10n.cacheUsageUnreported;
  }

  String _periodLabel(AppLocalizations l10n, BillPeriod period) =>
      switch (period) {
        BillPeriod.today => l10n.billPeriodToday,
        BillPeriod.last7d => l10n.billPeriodLast7Days,
        BillPeriod.last30d => l10n.billPeriodLast30Days,
        BillPeriod.all => l10n.billPeriodAll,
      };

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final summary = widget.viewModel.buildBillSummary(_billPeriod);

    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = constraints.maxWidth < 560 ? 16.0 : 28.0;
        return SingleChildScrollView(
          controller: _scrollController,
          padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 20),
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSectionHeader(title: l10n.settingsSectionUsageBill),

          // 周期切换胶囊组 (宽屏首尾分居，窄屏自动折行)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: SizedBox(
              width: double.infinity,
              child: AppControlFlow(
                spacing: AppSpacing.md,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  AppSegmentedCardBar<BillPeriod>(
                    scrollable: true,
                    items: [
                      for (final period in BillPeriod.values)
                        AppSegmentedItem(
                          value: period,
                          label: _periodLabel(l10n, period),
                        ),
                    ],
                    selectedValue: _billPeriod,
                    onValueChanged: (period) =>
                        setState(() => _billPeriod = period),
                  ),
                  Text(
                    l10n.billSummaryRequestsAndTokens(
                      summary.requests,
                      UsageLedgerService.formatTokens(summary.usage.total),
                    ),
                    style: TextStyle(fontSize: 12, color: colors.textMuted),
                  ),
                ],
              ),
            ),
          ),

          // 账单表格
          AnimatedSwitcher(
            duration: AppMotion.resolveDuration(
              context,
              AppMotionDurations.quick,
            ),
            switchInCurve: AppMotionCurves.inOut,
            switchOutCurve: AppMotionCurves.inOut,
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: Alignment.topCenter,
                children: [...previousChildren, ?currentChild],
              );
            },
            child: summary.models.isEmpty
                ? KeyedSubtree(
                    key: const ValueKey<String>('empty'),
                    child: AppEmptyState(
                      icon: Icons.receipt_long_rounded,
                      title: l10n.billEmptyRecords,
                      isCompact: true,
                    ),
                  )
                : KeyedSubtree(
                    key: const ValueKey<String>('table'),
                    child: _buildBillTable(summary),
                  ),
          ),
        ],
      ),
    );
      },
    );
  }

  /// 账单表格 (对齐 pi-bill 的列: Model / Reqs / Input / Output / Cache R / Total)
  Widget _buildBillTable(BillSummary summary) {
    final colors = context.colors;
    final l10n = context.l10n;

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
            [
              l10n.billTableHeaderModel,
              l10n.billTableHeaderRequests,
              l10n.cacheUsageInputUncached,
              l10n.billTableHeaderOutput,
              l10n.billTableHeaderCacheRead,
              l10n.billTableHeaderHitRate,
              l10n.billTableHeaderTotal,
            ],
            style: headerStyle,
            background: colors.mutedBackground,
          ),
          for (final model in summary.models)
            buildRow([
              model.name,
              model.requests.toString(),
              fmt(model.usage.input),
              fmt(model.usage.output),
              model.usage.cacheReadReported || model.usage.cacheRead > 0
                  ? fmt(model.usage.cacheRead)
                  : '-',
              _hitRateLabel(model.usage),
              fmt(model.usage.total),
            ]),
          buildRow(
            [
              l10n.billTableTotalRow,
              summary.requests.toString(),
              fmt(summary.usage.input),
              fmt(summary.usage.output),
              summary.usage.cacheReadReported || summary.usage.cacheRead > 0
                  ? fmt(summary.usage.cacheRead)
                  : '-',
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
