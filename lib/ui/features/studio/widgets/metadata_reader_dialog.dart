import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/watermark_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_copyable_box.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_image_detail_layout.dart';
import '../../../core/widgets/app_section_header.dart';
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
    return AppDialogScaffold.show<void>(
      context: context,
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

    final screenSize = MediaQuery.sizeOf(context);
    final details = _buildDetails(context, meta);
    return AppDialogScaffold(
      title: l10n.metadataDialogTitle,
      subtitle: widget.fileName,
      width: widget.imageBytes == null ? 760 : 1440,
      height: (screenSize.height - 64).clamp(0.0, 1040.0),
      maxHeight: screenSize.height - 48,
      actions: _buildBottomActionButtons(context, meta),
      body: widget.imageBytes == null
          ? details
          : AppImageDetailLayout(
              image: MemoryImage(widget.imageBytes!),
              placeholder: AppEmptyState(
                icon: Icons.broken_image_outlined,
                title: l10n.libraryCardNoPreview,
                isCompact: true,
              ),
              previewFooter: _buildImageActions(context),
              details: details,
            ),
    );
  }

  Widget _buildDetails(BuildContext context, ImageMetadataResult meta) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 来源软件胶囊
          if (meta.software.isNotEmpty) ...[
            AppBadge(label: meta.software, variant: AppBadgeVariant.primary),
            const SizedBox(height: 14),
          ],

          // 基础摘要仅在信息区呈现，图片区域不放文字或徽章。
          _buildImageSummary(context, meta),
          const SizedBox(height: 16),

          // 正向提示词
          if (meta.prompt.isNotEmpty) ...[
            AppCopyableBox(
              copyLabel: l10n.copy,
              title: l10n.metadataPromptTitle,
              icon: Icons.text_fields_rounded,
              content: meta.prompt,
              onCopy: () => _copyText(meta.prompt, l10n.metadataCopiedPrompt),
            ),
            const SizedBox(height: 14),
          ],

          // 负向提示词
          if (meta.negativePrompt.isNotEmpty) ...[
            AppCopyableBox(
              copyLabel: l10n.copy,
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
    );
  }

  Widget _buildImageSummary(BuildContext context, ImageMetadataResult meta) {
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

    return AppCard(
      padding: const EdgeInsets.all(12),
      backgroundColor: colors.mutedBackground,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.metadataDimensions(widthStr, heightStr),
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            l10n.metadataModelAndSampler(modelStr, samplerStr),
            style: TextStyle(fontSize: 12, color: colors.textSecondary),
          ),
        ],
      ),
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
        AppSectionHeader(title: l10n.metadataCharacterPromptsTitle),
        ...List.generate(meta.characterPrompts.length, (idx) {
          final prompt = meta.characterPrompts[idx];
          final neg = idx < meta.characterNegativePrompts.length
              ? meta.characterNegativePrompts[idx]
              : '';
          return AppCard(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            backgroundColor: colors.mutedBackground,
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
        AppSectionHeader(title: l10n.metadataParametersTitle),
        AppCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          backgroundColor: colors.mutedBackground,
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

  Widget _buildImageActions(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_blindExtracting)
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        AppActionButton(
          icon: Icons.visibility_off_outlined,
          label: l10n.metadataExtractBlindWatermark,
          onPressed: _blindExtracting ? null : _extractBlindWatermark,
        ),
        AppActionButton(
          icon: Icons.photo_library_outlined,
          label: l10n.metadataImportAsReference,
          onPressed: () {
            widget.viewModel.board.importReferenceImageFromBytes(
              widget.imageBytes!,
              fileName: widget.fileName,
            );
            Navigator.of(context).pop();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.metadataImportedReference)),
            );
          },
        ),
      ],
    );
  }

  List<Widget> _buildBottomActionButtons(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
    final l10n = context.l10n;
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: Text(l10n.close),
      ),
      const SizedBox(width: 8),
      AppActionButton(
        icon: Icons.auto_fix_high_rounded,
        label: l10n.metadataApplyToWorkbench,
        variant: AppActionButtonVariant.primary,
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
