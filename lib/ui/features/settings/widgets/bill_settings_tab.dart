import 'package:flutter/material.dart';
import '../../../../core/harness/types.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../studio/view_models/studio_view_model.dart';
import 'settings_shared.dart';

/// Bill 页：按周期统计各模型的 Token 用量账单 (只读)
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
    final summary = widget.viewModel.buildBillSummary(_billPeriod);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsGroupTitle('Usage Bill'),

        // 周期切换胶囊组
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              for (final period in BillPeriod.values) ...[
                InkWell(
                  onTap: () => setState(() => _billPeriod = period),
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _billPeriod == period
                          ? AppTheme.notionBlue
                          : AppTheme.pureWhite,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(
                        color: _billPeriod == period
                            ? AppTheme.notionBlue
                            : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      period.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _billPeriod == period
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Text(
                '${summary.requests} 次请求 · 总计 ${UsageLedgerService.formatTokens(summary.usage.total)} tokens',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),

        // 账单表格
        if (summary.models.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: const Center(
              child: Text(
                '该周期内暂无用量记录',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              ),
            ),
          )
        else
          _buildBillTable(summary),
      ],
    );
  }

  /// 账单表格 (对齐 pi-bill 的列: Model / Reqs / Input / Output / Cache R / Total)
  Widget _buildBillTable(BillSummary summary) {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.textMuted,
    );
    const cellStyle = TextStyle(fontSize: 11.5, color: AppTheme.textPrimary);
    const totalStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppTheme.textPrimary,
    );

    String fmt(int v) => UsageLedgerService.formatTokens(v);

    TableRow buildRow(
      List<String> cells, {
      TextStyle style = cellStyle,
      Color? background,
      bool topBorder = false,
    }) {
      return TableRow(
        decoration: BoxDecoration(
          color: background,
          border: topBorder
              ? const Border(top: BorderSide(color: AppTheme.border))
              : null,
        ),
        children: cells
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Text(c, style: style),
              ),
            )
            .toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
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
            background: AppTheme.paperWarmth,
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
            background: AppTheme.paperWarmth,
            topBorder: true,
          ),
        ],
      ),
    );
  }
}
