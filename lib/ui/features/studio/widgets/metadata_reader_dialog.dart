import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/watermark_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_key_value_row.dart';
import '../view_models/studio_view_model.dart';

/// 拖入图片元数据读取与查看弹窗 (Notion 极简纯净风格)
class MetadataReaderDialog extends StatefulWidget {
  final ImageMetadataResult metadata;
  final Uint8List? imageBytes;
  final String? fileName;
  final StudioViewModel viewModel;

  const MetadataReaderDialog({
    super.key,
    required this.metadata,
    this.imageBytes,
    this.fileName,
    required this.viewModel,
  });

  /// 静态便捷展示方法
  static Future<void> show(
    BuildContext context, {
    required ImageMetadataResult metadata,
    Uint8List? imageBytes,
    String? fileName,
    required StudioViewModel viewModel,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => MetadataReaderDialog(
        metadata: metadata,
        imageBytes: imageBytes,
        fileName: fileName,
        viewModel: viewModel,
      ),
    );
  }

  @override
  State<MetadataReaderDialog> createState() => _MetadataReaderDialogState();
}

class _MetadataReaderDialogState extends State<MetadataReaderDialog> {
  // 盲水印提取结果 (null=未提取，空串=无水印，非空=提取到的文本)
  String? _blindResult;
  bool _blindExtracting = false;

  Future<void> _extractBlindWatermark() async {
    final bytes = widget.imageBytes;
    if (bytes == null) return;
    setState(() => _blindExtracting = true);
    try {
      // 服务端 null (无水印) 与 未提取 需区分：空串表示已提取但无水印
      final text = await WatermarkService.extractBlindWatermarkAsync(bytes);
      if (mounted) {
        setState(() {
          _blindResult = text ?? '';
          _blindExtracting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _blindResult = '';
          _blindExtracting = false;
        });
      }
    }
  }

  Widget _buildBlindWatermarkSection(BuildContext context) {
    if (_blindResult == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final hasWatermark = _blindResult!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasWatermark ? colors.primaryTint : colors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: hasWatermark
              ? colors.primary.withValues(alpha: 0.3)
              : colors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasWatermark
                    ? Icons.verified_user_outlined
                    : Icons.visibility_off_outlined,
                size: 13,
                color: hasWatermark ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                hasWatermark
                    ? context.l10n.metadataBlindWatermarkContent
                    : context.l10n.metadataBlindWatermarkNotFound,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasWatermark ? colors.primary : colors.textSecondary,
                ),
              ),
            ],
          ),
          if (hasWatermark) ...[
            const SizedBox(height: 6),
            SelectableText(
              _blindResult!,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _copyText(String text, String successMsg) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMsg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.metadata;
    final l10n = context.l10n;

    return AppDialogScaffold(
      title: widget.fileName ?? l10n.metadataDialogTitle,
      width: 720,
      maxHeight: 760,
      actions: _buildBottomActionButtons(context, meta),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 来源软件胶囊
            if (meta.software.isNotEmpty) ...[
              AppBadge(label: meta.software, variant: AppBadgeVariant.primary),
              const SizedBox(height: 14),
            ],

            // 图片缩略图预览与基础摘要
            if (widget.imageBytes != null) ...[
              _buildImagePreviewRow(context, meta),
              const SizedBox(height: 16),
            ],

            // 正向提示词
            if (meta.prompt.isNotEmpty) ...[
              _buildNotionSection(
                context: context,
                title: l10n.metadataPromptTitle,
                icon: Icons.text_fields_rounded,
                content: meta.prompt,
                onCopy: () => _copyText(meta.prompt, l10n.metadataCopiedPrompt),
              ),
              const SizedBox(height: 14),
            ],

            // 负向提示词
            if (meta.negativePrompt.isNotEmpty) ...[
              _buildNotionSection(
                context: context,
                title: l10n.metadataNegativePromptTitle,
                icon: Icons.remove_circle_outline_rounded,
                content: meta.negativePrompt,
                onCopy: () => _copyText(
                  meta.negativePrompt,
                  l10n.metadataCopiedNegativePrompt,
                ),
              ),
              const SizedBox(height: 14),
            ],

            // 多角色提示词 (若存在)
            if (meta.characterPrompts.isNotEmpty) ...[
              _buildCharacterPromptsSection(context, meta),
              const SizedBox(height: 14),
            ],

            // 生成参数网格
            _buildParametersGrid(context, meta),
            const SizedBox(height: 16),

            // 原始 JSON 折叠面板
            if (meta.rawJson.isNotEmpty) ...[
              _buildRawJsonCollapsible(context, meta.rawJson),
            ],

            // 盲水印提取结果
            _buildBlindWatermarkSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreviewRow(BuildContext context, ImageMetadataResult meta) {
    final colors = context.colors;
    final l10n = context.l10n;
    final widthStr = meta.width != null
        ? '${meta.width}'
        : l10n.metadataDimensionAuto;
    final heightStr = meta.height != null
        ? '${meta.height}'
        : l10n.metadataDimensionAuto;
    final modelStr = meta.model ?? l10n.metadataModelUnknown;
    final samplerStr = meta.sampler ?? l10n.metadataSamplerDefault;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.memory(
              widget.imageBytes!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.metadataDimensions(widthStr, heightStr),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.metadataModelAndSampler(modelStr, samplerStr),
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                if (meta.seed != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    l10n.metadataSeedLabel('${meta.seed}'),
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotionSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required String content,
    required VoidCallback onCopy,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: colors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 12, color: colors.primary),
                    const SizedBox(width: 4),
                    Text(
                      context.l10n.copy,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.mutedBackground,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: colors.borderDefault),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterPromptsSection(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              l10n.metadataCharacterPromptsTitle,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...List.generate(meta.characterPrompts.length, (idx) {
          final prompt = meta.characterPrompts[idx];
          final neg = idx < meta.characterNegativePrompts.length
              ? meta.characterNegativePrompts[idx]
              : '';
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.mutedBackground,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBadge(
                  label: l10n.metadataCharacterIndex(idx + 1),
                  variant: AppBadgeVariant.primary,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  prompt,
                  style: TextStyle(fontSize: 12, color: colors.textPrimary),
                ),
                if (neg.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    l10n.metadataNegativePrefix(neg),
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildParametersGrid(BuildContext context, ImageMetadataResult meta) {
    final colors = context.colors;
    final l10n = context.l10n;
    final items = <_ParamItem>[
      _ParamItem(
        l10n.metadataParamModel,
        meta.model ?? l10n.metadataParamUnknown,
      ),
      _ParamItem(
        l10n.metadataParamSampler,
        meta.sampler ?? l10n.metadataParamDefault,
      ),
      _ParamItem(
        l10n.metadataParamSteps,
        meta.steps != null ? '${meta.steps}' : '28',
      ),
      _ParamItem(
        'CFG Scale',
        meta.scale != null ? '${meta.scale}' : '5.0',
        isMonospace: true,
      ),
      if (meta.cfgRescale != null && meta.cfgRescale! > 0)
        _ParamItem('CFG Rescale', '${meta.cfgRescale}', isMonospace: true),
      _ParamItem(
        l10n.metadataParamSeed,
        meta.seed != null ? '${meta.seed}' : l10n.metadataParamSeedRandom,
        isMonospace: true,
      ),
      if (meta.noiseSchedule != null)
        _ParamItem(l10n.metadataParamNoiseSchedule, meta.noiseSchedule!),
      if (meta.qualityPreset != null)
        _ParamItem(l10n.metadataParamQualityPreset, meta.qualityPreset!),
      if (meta.ucPreset != null)
        _ParamItem(l10n.metadataParamUcPreset, meta.ucPreset!),
      if (meta.transparentBackground == true)
        _ParamItem(l10n.metadataParamTransparentBg, l10n.metadataParamEnabled),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.metadataParametersTitle,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.mutedBackground,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: colors.borderDefault),
          ),
          child: Column(
            children: items.map((item) {
              return AppKeyValueRow(
                label: item.label,
                value: item.value,
                isMonospace: item.isMonospace,
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRawJsonCollapsible(BuildContext context, String rawJson) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AppCollapsibleSection(
      title: l10n.metadataRawJsonTitle,
      initiallyExpanded: false,
      trailing: IconButton(
        icon: const Icon(Icons.copy_rounded, size: 14),
        visualDensity: VisualDensity.compact,
        tooltip: l10n.metadataCopyRawTooltip,
        onPressed: () => _copyText(rawJson, l10n.metadataCopiedRaw),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: Container(
          color: colors.mutedBackground,
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            child: SelectableText(
              rawJson,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBottomActionButtons(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
        child: Text(l10n.close),
      ),
      const SizedBox(width: 8),
      if (widget.imageBytes != null) ...[
        OutlinedButton.icon(
          icon: _blindExtracting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.visibility_off_outlined, size: 16),
          label: Text(l10n.metadataExtractBlindWatermark),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.textPrimary,
            backgroundColor: colors.cardBackground,
            side: BorderSide(color: colors.borderDefault),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          onPressed: _blindExtracting ? null : _extractBlindWatermark,
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: Text(l10n.metadataImportAsReference),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.textPrimary,
            backgroundColor: colors.cardBackground,
            side: BorderSide(color: colors.borderDefault),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          onPressed: () {
            widget.viewModel.importReferenceImageFromBytes(
              widget.imageBytes!,
              fileName: widget.fileName,
            );
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.metadataImportedReference)),
            );
          },
        ),
        const SizedBox(width: 8),
      ],
      ElevatedButton.icon(
        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
        label: Text(l10n.metadataApplyToWorkbench),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        onPressed: () {
          widget.viewModel.applyMetadataToWorkbench(meta);
          Navigator.of(context).pop();
        },
      ),
    ];
  }
}

class _ParamItem {
  final String label;
  final String value;
  final bool isMonospace;
  const _ParamItem(this.label, this.value, {this.isMonospace = false});
}
