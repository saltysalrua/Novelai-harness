import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/prompt_image_probe.dart';
import '../../../../data/services/watermark_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_copyable_box.dart';
import '../../../core/widgets/app_key_value_row.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../view_models/studio_view_model.dart';

/// 图片元数据读取与查看弹窗：
/// Notion 极简一体布局，零内部分割线、零图像空边框、少框低噪。
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
    return showAppModalDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
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
  String? _blindResult;
  bool _blindExtracting = false;
  late final Set<MetadataImportField> _selectedFields = widget.metadata.hasData
      ? widget.metadata.importableFields
      : <MetadataImportField>{};
  late final double? _imageAspectRatio = widget.imageBytes != null
      ? PromptImageProbe.probeBytes(widget.imageBytes!)
      : null;
  late final SmoothWheelScrollController _detailsScrollController =
      SmoothWheelScrollController();

  @override
  void dispose() {
    _detailsScrollController.dispose();
    super.dispose();
  }

  Future<void> _extractBlindWatermark() async {
    final bytes = widget.imageBytes;
    if (bytes == null) return;
    setState(() => _blindExtracting = true);
    try {
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

  void _copyText(String text, String successMsg) {
    Clipboard.setData(ClipboardData(text: text));
    showAppToast(
      context,
      message: successMsg,
      tone: AppToastTone.success,
      duration: const Duration(seconds: 2),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final meta = widget.metadata;
    final hasImage =
        widget.imageBytes != null && widget.imageBytes!.isNotEmpty;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = hasImage
        ? (screenSize.width * 0.76).clamp(620.0, 1060.0)
        : (screenSize.width * 0.56).clamp(420.0, 680.0);
    final dialogHeight = (screenSize.height * 0.84).clamp(460.0, 740.0);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event.logicalKey != LogicalKeyboardKey.escape) {
          return KeyEventResult.ignored;
        }
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
          return KeyEventResult.ignored;
        }
        Navigator.of(context).pop();
        return KeyEventResult.handled;
      },
      child: Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: dialogWidth,
            height: dialogHeight,
            constraints: BoxConstraints(
              maxWidth: screenSize.width - 32,
              maxHeight: screenSize.height - 40,
            ),
            decoration: BoxDecoration(
              color: colors.cardBackground,
              borderRadius: BorderRadius.circular(AppRadius.lg),
              border: Border.all(color: colors.borderDefault),
              boxShadow: context.shadowDialog,
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isNarrow = constraints.maxWidth < 720;

                if (!hasImage) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(22, 16, 22, 18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopHeader(context),
                        Expanded(child: _buildDetailsScroll(context, meta)),
                        const SizedBox(height: 12),
                        _buildBottomActionButtons(context, meta),
                      ],
                    ),
                  );
                }

                if (isNarrow) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildTopHeader(context),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: _detailsScrollController,
                            padding: const EdgeInsets.only(top: 6, bottom: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ConstrainedBox(
                                  constraints: BoxConstraints(
                                    maxHeight: (constraints.maxHeight * 0.34)
                                        .clamp(150.0, 240.0),
                                  ),
                                  child: _buildPreviewImage(context),
                                ),
                                const SizedBox(height: 10),
                                _buildImageActions(context),
                                AppPanelReveal(
                                  visible: _blindResult != null,
                                  enableBlur: false,
                                  child: _buildBlindWatermarkSection(context),
                                ),
                                const SizedBox(height: 14),
                                ..._buildDetailSections(context, meta),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        _buildBottomActionButtons(context, meta),
                      ],
                    ),
                  );
                }

                return Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 左侧完整大图与图像操作 (无灰底空边框、无分割线)
                    Expanded(
                      flex: 9,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(22, 22, 10, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _buildPreviewImage(context)),
                            const SizedBox(height: 10),
                            _buildImageActions(context),
                            AppPanelReveal(
                              visible: _blindResult != null,
                              enableBlur: false,
                              child: _buildBlindWatermarkSection(context),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // 右侧一体式参数详情与选择回填
                    Expanded(
                      flex: 11,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(14, 16, 20, 18),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildTopHeader(context),
                            Expanded(child: _buildDetailsScroll(context, meta)),
                            const SizedBox(height: 10),
                            _buildBottomActionButtons(context, meta),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTopHeader(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final hasFileName =
        widget.fileName != null && widget.fileName!.trim().isNotEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.metadataDialogTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
              if (hasFileName) ...[
                const SizedBox(height: 2),
                Text(
                  widget.fileName!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: colors.textMuted),
                ),
              ],
            ],
          ),
        ),
        IconButton(
          icon: Icon(
            Icons.close_rounded,
            size: 18,
            color: colors.textSecondary,
          ),
          splashRadius: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }

  Widget _buildPreviewImage(BuildContext context) {
    final image = MemoryImage(widget.imageBytes!);
    final imgWidget = Image(image: image, fit: BoxFit.contain);
    final ratio = _imageAspectRatio;
    final framed = ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: ratio != null
          ? AspectRatio(aspectRatio: ratio, child: imgWidget)
          : imgWidget,
    );

    return InteractiveViewer(
      key: ValueKey(image),
      minScale: 1,
      maxScale: 5,
      child: Center(child: framed),
    );
  }

  Widget _buildDetailsScroll(BuildContext context, ImageMetadataResult meta) {
    return SingleChildScrollView(
      controller: _detailsScrollController,
      padding: const EdgeInsets.only(top: 10, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: _buildDetailSections(context, meta),
      ),
    );
  }

  List<Widget> _buildDetailSections(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
    final l10n = context.l10n;
    final colors = context.colors;

    return [
      // 1. 来源软件 + 尺寸摘要 (无边框轻量行)
      _buildSummaryRow(context, meta),
      const SizedBox(height: 12),

      if (!meta.hasData) ...[
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: colors.elevatedBackground,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline_rounded, size: 16, color: colors.textMuted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.metadataNoParamsNotice,
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],

      // 2. 可选回填字段 (去外框，保留简洁交互胶囊)
      if (meta.hasData && meta.importableFields.isNotEmpty) ...[
        _buildImportSelection(context, meta),
        const SizedBox(height: 14),
      ],

      // 3. 正向提示词
      if (meta.prompt.isNotEmpty) ...[
        AppCopyableBox(
          copyLabel: l10n.copy,
          title: l10n.metadataPromptTitle,
          icon: Icons.text_fields_rounded,
          content: meta.prompt,
          backgroundColor: colors.elevatedBackground,
          borderColor: Colors.transparent,
          onCopy: () => _copyText(meta.prompt, l10n.metadataCopiedPrompt),
        ),
        const SizedBox(height: 12),
      ],

      // 4. 负向提示词
      if (meta.negativePrompt.isNotEmpty) ...[
        AppCopyableBox(
          copyLabel: l10n.copy,
          title: l10n.metadataNegativePromptTitle,
          icon: Icons.remove_circle_outline_rounded,
          content: meta.negativePrompt,
          backgroundColor: colors.elevatedBackground,
          borderColor: Colors.transparent,
          onCopy: () => _copyText(
            meta.negativePrompt,
            l10n.metadataCopiedNegativePrompt,
          ),
        ),
        const SizedBox(height: 12),
      ],

      // 5. 多角色提示词
      if (meta.characterPrompts.isNotEmpty) ...[
        _buildCharacterPromptsSection(context, meta),
        const SizedBox(height: 12),
      ],

      // 6. 生成参数网格 (有生成数据时展示)
      if (meta.hasData) ...[
        _buildParametersSection(context, meta),
        const SizedBox(height: 12),
      ],

      // 7. 原始 JSON 折叠面板
      if (meta.rawJson.isNotEmpty)
        _buildRawJsonCollapsible(context, meta.rawJson),
    ];
  }

  Widget _buildSummaryRow(BuildContext context, ImageMetadataResult meta) {
    final colors = context.colors;
    final l10n = context.l10n;
    final widthStr = meta.width != null
        ? '${meta.width}'
        : l10n.metadataDimensionAuto;
    final heightStr = meta.height != null
        ? '${meta.height}'
        : l10n.metadataDimensionAuto;

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (meta.software.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.primaryTint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Text(
              meta.software,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colors.primary,
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: colors.elevatedBackground,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            l10n.metadataDimensions(widthStr, heightStr),
            style: TextStyle(
              fontSize: 11.5,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildImportSelection(BuildContext context, ImageMetadataResult meta) {
    final colors = context.colors;
    final l10n = context.l10n;
    String labelOf(MetadataImportField field) => switch (field) {
      MetadataImportField.prompt => l10n.metadataPromptTitle,
      MetadataImportField.negativePrompt => l10n.metadataNegativePromptTitle,
      MetadataImportField.characters => l10n.metadataCharacterPromptsTitle,
      MetadataImportField.model => l10n.metadataParamModel,
      MetadataImportField.resolution => l10n.resolutionTitle,
      MetadataImportField.sampler => l10n.metadataParamSampler,
      MetadataImportField.steps => l10n.metadataParamSteps,
      MetadataImportField.scale => 'CFG Scale',
      MetadataImportField.cfgRescale => 'CFG Rescale',
      MetadataImportField.seed => l10n.metadataParamSeed,
      MetadataImportField.noiseSchedule => l10n.metadataParamNoiseSchedule,
      MetadataImportField.quality => l10n.metadataImportQuality,
      MetadataImportField.ucPreset => l10n.metadataParamUcPreset,
      MetadataImportField.transparentBackground =>
        l10n.metadataParamTransparentBg,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: double.infinity,
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              _SectionTitle(text: l10n.metadataImportSelection),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _InlineTextLink(
                    label: l10n.metadataImportSelectAll,
                    onTap: () => setState(
                      () => _selectedFields.addAll(meta.importableFields),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _InlineTextLink(
                    label: l10n.metadataImportSelectNone,
                    onTap: () => setState(_selectedFields.clear),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final field in meta.importableFields)
              AppToolChip(
                key: ValueKey(field),
                label: labelOf(field),
                icon: _selectedFields.contains(field)
                    ? Icons.check_box_outlined
                    : Icons.check_box_outline_blank,
                isSelected: _selectedFields.contains(field),
                variant: AppToolChipVariant.tinted,
                unselectedBackgroundColor: colors.elevatedBackground,
                onTap: () => setState(() {
                  if (!_selectedFields.remove(field)) {
                    _selectedFields.add(field);
                  }
                }),
              ),
          ],
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text: l10n.metadataCharacterPromptsTitle),
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
              color: colors.elevatedBackground,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.metadataCharacterIndex(idx + 1),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 4),
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

  Widget _buildParametersSection(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
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
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SectionTitle(text: l10n.metadataParametersTitle),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.elevatedBackground,
            borderRadius: BorderRadius.circular(AppRadius.md),
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
      isCard: false,
      headerPadding: const EdgeInsets.symmetric(vertical: 6),
      contentPadding: const EdgeInsets.only(top: 4),
      trailing: IconButton(
        icon: const Icon(Icons.copy_rounded, size: 14),
        visualDensity: VisualDensity.compact,
        tooltip: l10n.metadataCopyRawTooltip,
        onPressed: () => _copyText(rawJson, l10n.metadataCopiedRaw),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 160),
        child: Container(
          decoration: BoxDecoration(
            color: colors.elevatedBackground,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
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

  Widget _buildBlindWatermarkSection(BuildContext context) {
    if (_blindResult == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final hasWatermark = _blindResult!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: hasWatermark ? colors.primaryTint : colors.elevatedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
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
                fontSize: 12.5,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImageActions(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (_blindExtracting)
          AppMatrixDotLoader(
            dotSize: 2.2,
            gap: 1.8,
            variant: AppMatrixDotVariant.pulse,
            activeColor: colors.primary,
          ),
        AppToolChip(
          icon: Icons.visibility_off_outlined,
          label: l10n.metadataExtractBlindWatermark,
          variant: AppToolChipVariant.tinted,
          unselectedBackgroundColor: colors.elevatedBackground,
          onTap: _blindExtracting ? null : _extractBlindWatermark,
        ),
        AppToolChip(
          icon: Icons.photo_library_outlined,
          label: l10n.metadataImportAsReference,
          variant: AppToolChipVariant.tinted,
          unselectedBackgroundColor: colors.elevatedBackground,
          onTap: () {
            widget.viewModel.board.importReferenceImageFromBytes(
              widget.imageBytes!,
              fileName: widget.fileName,
            );
            showAppToast(
              context,
              message: l10n.metadataImportedReference,
              tone: AppToastTone.success,
            );
            Navigator.of(context).pop();
          },
        ),
      ],
    );
  }

  Widget _buildBottomActionButtons(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
    final l10n = context.l10n;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        AppActionButton(
          label: l10n.close,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AppActionButton(
          icon: Icons.auto_fix_high_rounded,
          label: l10n.metadataApplyToWorkbench,
          variant: AppActionButtonVariant.primary,
          onPressed: _selectedFields.isEmpty
              ? null
              : () {
                  widget.viewModel.applyMetadataToWorkbench(
                    meta,
                    fields: _selectedFields,
                  );
                  Navigator.of(context).pop();
                },
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w600,
        color: context.colors.textMuted,
      ),
    );
  }
}

class _InlineTextLink extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _InlineTextLink({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w500,
            color: context.colors.primary,
          ),
        ),
      ),
    );
  }
}

class _ParamItem {
  final String label;
  final String value;
  final bool isMonospace;
  const _ParamItem(this.label, this.value, {this.isMonospace = false});
}
