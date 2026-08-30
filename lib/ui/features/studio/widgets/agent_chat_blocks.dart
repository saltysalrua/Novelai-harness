import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// 通用折叠块: 头部行 + 可展开主体 (Pi 风格，默认折叠)
class CollapsibleTile extends StatefulWidget {
  final Widget header;
  final Widget? body;
  final EdgeInsetsGeometry margin;

  const CollapsibleTile({
    super.key,
    required this.header,
    this.body,
    this.margin = const EdgeInsets.only(bottom: 4),
  });

  @override
  State<CollapsibleTile> createState() => _CollapsibleTileState();
}

class _CollapsibleTileState extends State<CollapsibleTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final hasBody = widget.body != null;
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
            onTap: hasBody
                ? () => setState(() => _expanded = !_expanded)
                : null,
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
                      turns: _expanded ? 0.5 : 0,
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
          if (hasBody && _expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              child: widget.body,
            ),
        ],
      ),
    );
  }
}

/// 思考过程块: 暗色斜体，默认折叠，头部带首行预览
class ThinkingBlock extends StatelessWidget {
  final String thoughts;

  const ThinkingBlock({super.key, required this.thoughts});

  @override
  Widget build(BuildContext context) {
    final preview = thoughts
        .split('\n')
        .map((l) => l.trim())
        .firstWhere((l) => l.isNotEmpty, orElse: () => '');

    return CollapsibleTile(
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
                overflow: TextOverflow.ellipsis,
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
          thoughts,
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
