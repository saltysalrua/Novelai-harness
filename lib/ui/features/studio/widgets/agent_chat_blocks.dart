import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 通用折叠块: 头部行 + 可展开主体 (Pi 风格，默认折叠)
class CollapsibleTile extends StatefulWidget {
  final Widget header;
  final Widget? body;
  final EdgeInsetsGeometry margin;

  /// 外部受控展开状态 (为 null 时使用内部自持状态)
  final bool? isExpanded;

  /// 外部展开切换回调 (为 null 时点击切换内部状态)
  final VoidCallback? onToggle;

  const CollapsibleTile({
    super.key,
    required this.header,
    this.body,
    this.margin = const EdgeInsets.only(bottom: 4),
    this.isExpanded,
    this.onToggle,
  });

  @override
  State<CollapsibleTile> createState() => _CollapsibleTileState();
}

class _CollapsibleTileState extends State<CollapsibleTile> {
  bool _expanded = false;

  bool get _effectiveExpanded => widget.isExpanded ?? _expanded;

  void _handleToggle() {
    if (widget.onToggle != null) {
      widget.onToggle!();
    } else {
      setState(() => _expanded = !_expanded);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasBody = widget.body != null;
    final expanded = _effectiveExpanded;
    return Container(
      margin: widget.margin,
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: hasBody ? _handleToggle : null,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(AppTheme.radiusSmall),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
              child: Row(
                children: [
                  Expanded(child: widget.header),
                  if (hasBody)
                    AnimatedRotation(
                      turns: expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: const Icon(
                        Icons.expand_more,
                        size: 14,
                        color: AppTheme.textMuted,
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (hasBody && expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: widget.body,
            ),
        ],
      ),
    );
  }
}

/// 思考过程块: 暗色斜体，默认折叠只显示单行预览；点击或 Ctrl+O 全局展开
///
/// [forceExpanded] 为 ViewModel 的 Ctrl+O 全局开关，开启时叠加本地展开状态
/// 直接展开全文，关闭后恢复各自的折叠状态。
class ThinkingBlock extends StatefulWidget {
  final String thoughts;
  final bool forceExpanded;

  const ThinkingBlock({
    super.key,
    required this.thoughts,
    this.forceExpanded = false,
  });

  @override
  State<ThinkingBlock> createState() => _ThinkingBlockState();
}

class _ThinkingBlockState extends State<ThinkingBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final expanded = _expanded || widget.forceExpanded;
    final preview = widget.thoughts
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');

    return CollapsibleTile(
      isExpanded: expanded,
      onToggle: () => setState(() => _expanded = !_expanded),
      header: Row(
        children: [
          const Icon(
            Icons.psychology_outlined,
            size: 13,
            color: AppTheme.textMuted,
          ),
          const SizedBox(width: 4),
          const Text(
            '思考过程',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              fontStyle: FontStyle.italic,
              color: AppTheme.textMuted,
            ),
          ),
          if (preview.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                preview,
                maxLines: 1,
                overflow: expanded ? null : TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                  color: AppTheme.textMuted,
                ),
              ),
            ),
          ],
        ],
      ),
      body: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
        ),
        child: SelectableText(
          widget.thoughts,
          style: const TextStyle(
            fontSize: 11,
            fontStyle: FontStyle.italic,
            color: AppTheme.textMuted,
            height: 1.45,
          ),
        ),
      ),
    );
  }
}
