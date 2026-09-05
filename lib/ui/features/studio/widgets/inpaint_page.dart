import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_key_value_row.dart';
import '../../../core/widgets/app_number_slider.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../view_models/studio_view_model.dart';
import 'prompt_editor_card.dart';
import 'rich_prompt_text_controller.dart';
import 'studio_shared.dart';

const _aiEditAspectRatios = [
  '',
  '1:1',
  '2:3',
  '3:2',
  '3:4',
  '4:3',
  '4:5',
  '5:4',
  '9:16',
  '16:9',
  '21:9',
];

const _aiEditResolutions = ['', '1K', '2K', '4K'];

/// 侧边栏页面三：局部修复与焦点特写配置页 (Notion 极简风格)
class InpaintPage extends StatefulWidget {
  final StudioViewModel viewModel;

  const InpaintPage({super.key, required this.viewModel});

  @override
  State<InpaintPage> createState() => _InpaintPageState();
}

class _InpaintPageState extends State<InpaintPage> {
  late final RichPromptTextController _promptController;
  late final RichPromptTextController _negativeController;

  @override
  void initState() {
    super.initState();
    _promptController = RichPromptTextController(
      text: widget.viewModel.inpaintParams.customPrompt,
    );
    _negativeController = RichPromptTextController(
      text: widget.viewModel.inpaintParams.customNegativePrompt,
    );
  }

  @override
  void didUpdateWidget(InpaintPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.inpaintParams.customPrompt != _promptController.text) {
      _promptController.text = widget.viewModel.inpaintParams.customPrompt;
    }
    if (widget.viewModel.inpaintParams.customNegativePrompt !=
        _negativeController.text) {
      _negativeController.text =
          widget.viewModel.inpaintParams.customNegativePrompt;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final vm = widget.viewModel;
        final inpaint = vm.inpaintParams;
        final geometry = vm.inpaintGeometry;
        final isFocus = inpaint.mode == InpaintMode.focus;
        final isAiEdit = inpaint.mode == InpaintMode.aiEdit;

        if (_promptController.text != inpaint.customPrompt) {
          _promptController.text = inpaint.customPrompt;
        }
        if (_negativeController.text != inpaint.customNegativePrompt) {
          _negativeController.text = inpaint.customNegativePrompt;
        }

        final showCategoryColors = vm.config.showTagCategoryColors;
        _promptController.setHighlightOptions(
          categoryColors: showCategoryColors,
          highlightEnabled: !isAiEdit,
        );
        _negativeController.setHighlightOptions(
          categoryColors: showCategoryColors,
        );

        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.lg,
            vertical: AppSpacing.md,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PageHeader(
                title: l10n.inpaintPageTitle,
                subtitle: l10n.inpaintPageSubtitle,
              ),
              const SizedBox(height: AppSpacing.lg),

              // 1. 修复模式切换 (AppOptionCard 选项)
              SectionHeader(l10n.inpaintSectionMode),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AppOptionCard<InpaintMode>(
                      value: InpaintMode.focus,
                      title: l10n.inpaintModeFocus,
                      subtitle: l10n.inpaintModeFocusSubtitle,
                      isSelected: isFocus,
                      onTap: () => vm.setInpaintMode(InpaintMode.focus),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppOptionCard<InpaintMode>(
                      value: InpaintMode.standard,
                      title: l10n.inpaintModeStandard,
                      subtitle: l10n.inpaintModeStandardSubtitle,
                      isSelected: inpaint.mode == InpaintMode.standard,
                      onTap: () => vm.setInpaintMode(InpaintMode.standard),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppOptionCard<InpaintMode>(
                      value: InpaintMode.aiEdit,
                      title: l10n.inpaintModeAiEdit,
                      subtitle: l10n.inpaintModeAiEditSubtitle,
                      isSelected: isAiEdit,
                      onTap: () => vm.setInpaintMode(InpaintMode.aiEdit),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),

              // 2. 焦点几何信息卡 (AppCollapsibleSection + AppBadge + AppKeyValueRow)
              if (isFocus) ...[
                _buildGeometryCard(context, geometry),
                const SizedBox(height: AppSpacing.lg),
              ],

              // 2b. AI 整图编辑绘图模型信息卡
              if (isAiEdit) ...[
                _buildAiEditCard(context, vm.imageEditModelInfo),
                const SizedBox(height: AppSpacing.lg),
              ],

              // 2c. AI 整图编辑生成设置
              if (isAiEdit) ...[
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(l10n.inpaintAiEditAspectRatio),
                          const SizedBox(height: AppSpacing.sm),
                          AppDropdown<String>.simple(
                            value:
                                _aiEditAspectRatios.contains(
                                  inpaint.aiEditAspectRatio,
                                )
                                ? inpaint.aiEditAspectRatio
                                : '',
                            items: _aiEditAspectRatios,
                            labelOf: (v) =>
                                v.isEmpty ? l10n.inpaintAiEditFollowSource : v,
                            iconOf: (_) => Icons.aspect_ratio_rounded,
                            onChanged: vm.setInpaintAiEditAspectRatio,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SectionHeader(l10n.inpaintAiEditResolution),
                          const SizedBox(height: AppSpacing.sm),
                          AppDropdown<String>.simple(
                            value:
                                _aiEditResolutions.contains(
                                  inpaint.aiEditResolution,
                                )
                                ? inpaint.aiEditResolution
                                : '',
                            items: _aiEditResolutions,
                            labelOf: (v) => v.isEmpty
                                ? l10n.inpaintAiEditDefaultResolution
                                : v,
                            iconOf: (_) =>
                                Icons.photo_size_select_actual_outlined,
                            onChanged: vm.setInpaintAiEditResolution,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],

              // 3. 数值滑块调节 (NovelAI 重绘专属，AI 整图编辑不需要)
              if (isFocus && !isAiEdit) ...[
                AppNumberSlider.integer(
                  title: l10n.inpaintContextPadding,
                  value: inpaint.contextPadding.round(),
                  min: 16,
                  max: 192,
                  onChanged: (v) => vm.setInpaintContextPadding(v.toDouble()),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              if (!isAiEdit) ...[
                AppNumberSlider(
                  title: l10n.inpaintStrength,
                  value: inpaint.strength,
                  min: 0.0,
                  max: 1.0,
                  fractionDigits: 2,
                  onChanged: vm.setInpaintStrength,
                ),
                const SizedBox(height: AppSpacing.md),

                AppNumberSlider(
                  title: l10n.inpaintNoise,
                  value: inpaint.noise,
                  min: 0.0,
                  max: 1.0,
                  fractionDigits: 2,
                  onChanged: vm.setInpaintNoise,
                ),
                const SizedBox(height: AppSpacing.lg),
              ] else
                const SizedBox(height: AppSpacing.xs),

              // 4. 提示词与指令选项 (复用 / 自定义卡片设计)
              SectionHeader(
                isAiEdit
                    ? l10n.inpaintSectionInstruction
                    : l10n.inpaintSectionPrompt,
              ),
              const SizedBox(height: AppSpacing.sm),

              _buildToggleRow(
                context: context,
                label: isAiEdit
                    ? l10n.inpaintReuseMainPromptAsInstruction
                    : l10n.inpaintReuseMainPrompt,
                value: inpaint.useMainPrompt,
                onChanged: vm.setInpaintUseMainPrompt,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!inpaint.useMainPrompt) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isAiEdit
                          ? l10n.inpaintCustomInstruction
                          : l10n.inpaintCustomPrompt,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (_promptController.text.trim().isNotEmpty)
                      ClearTextLink(
                        onTap: () {
                          _promptController.clear();
                          vm.setInpaintCustomPrompt('');
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                PromptEditorCard(
                  controller: _promptController,
                  onChanged: vm.setInpaintCustomPrompt,
                  hintText: isAiEdit
                      ? l10n.inpaintInstructionHint
                      : l10n.inpaintPromptHint,
                  minLines: 3,
                  maxLines: 8,
                  minHeight: 80.0,
                  showQuickActions: !isAiEdit,
                  enableAutocomplete:
                      !isAiEdit && vm.config.enableTagAutocomplete,
                  showTranslation: vm.config.showTagTranslations,
                  tokenEstimate: estimatePromptTokens(
                    _promptController.text,
                    limit: vm.params.model.tokenLimit,
                  ),
                  tokenLimit: vm.params.model.tokenLimit,
                ),
              ] else ...[
                _buildReusedPromptPreview(
                  context: context,
                  label: l10n.inpaintMainPrompt,
                  text: vm.params.prompt,
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              if (!isAiEdit) ...[
                _buildToggleRow(
                  context: context,
                  label: l10n.inpaintReuseMainNegative,
                  value: inpaint.useMainNegative,
                  onChanged: vm.setInpaintUseMainNegative,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (!inpaint.useMainNegative) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.inpaintCustomNegative,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      if (_negativeController.text.trim().isNotEmpty)
                        ClearTextLink(
                          onTap: () {
                            _negativeController.clear();
                            vm.setInpaintCustomNegativePrompt('');
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  PromptEditorCard(
                    controller: _negativeController,
                    onChanged: vm.setInpaintCustomNegativePrompt,
                    hintText: l10n.inpaintNegativePromptHint,
                    minLines: 3,
                    maxLines: 8,
                    minHeight: 80.0,
                    showQuickActions: true,
                    enableAutocomplete: vm.config.enableTagAutocomplete,
                    showTranslation: vm.config.showTagTranslations,
                    tokenEstimate: estimatePromptTokens(
                      _negativeController.text,
                      limit: vm.params.model.tokenLimit,
                    ),
                    tokenLimit: vm.params.model.tokenLimit,
                  ),
                ] else ...[
                  _buildReusedPromptPreview(
                    context: context,
                    label: l10n.inpaintMainNegativePrompt,
                    text: vm.params.negativePrompt,
                  ),
                ],
                const SizedBox(height: AppSpacing.xl),
              ] else
                const SizedBox(height: AppSpacing.sm),
            ],
          ),
        );
      },
    );
  }

  /// AI 整图编辑绘图模型信息卡 (未配置时给出引导提示)
  Widget _buildAiEditCard(
    BuildContext context,
    ({String providerName, String modelName, String modelId})? info,
  ) {
    final colors = context.colors;
    final l10n = context.l10n;
    final configured = info != null;
    return AppCollapsibleSection(
      initiallyExpanded: true,
      headerPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      headerWidget: Row(
        children: [
          Icon(Icons.auto_awesome, size: 14, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            l10n.inpaintImageModel,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      trailing: AppBadge(
        label: l10n.inpaintConsumeQuota,
        variant: AppBadgeVariant.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (configured) ...[
            AppKeyValueRow(
              label: l10n.inpaintProvider,
              value: info.providerName,
            ),
            AppKeyValueRow(label: l10n.inpaintModel, value: info.modelName),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                info.modelId,
                style: TextStyle(
                  fontSize: 11,
                  fontFamily: 'monospace',
                  color: colors.textSecondary,
                ),
              ),
            ),
          ] else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
              child: Text(
                l10n.inpaintNoModelConfigured,
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGeometryCard(BuildContext context, InpaintGeometry geometry) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AppCollapsibleSection(
      initiallyExpanded: true,
      headerPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      headerWidget: Row(
        children: [
          Icon(
            Icons.aspect_ratio_outlined,
            size: 14,
            color: colors.textSecondary,
          ),
          const SizedBox(width: 6),
          Text(
            l10n.inpaintLatentFocusGeometry,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      trailing: AppBadge(
        label: geometry.isOpusFree ? l10n.opusFree : l10n.inpaintRequiresPoints,
        variant: geometry.isOpusFree
            ? AppBadgeVariant.success
            : AppBadgeVariant.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppKeyValueRow(
            label: l10n.inpaintTargetSelection,
            value:
                '${geometry.focusBounds.width.round()} × ${geometry.focusBounds.height.round()} px',
          ),
          AppKeyValueRow(
            label: l10n.inpaintContextCrop,
            value:
                '${geometry.contextCrop.width.round()} × ${geometry.contextCrop.height.round()} px',
          ),
          AppKeyValueRow(
            label: l10n.inpaintRequestResolution,
            value:
                '${geometry.requestWidth} × ${geometry.requestHeight} (${l10n.inpaintSupersample(geometry.scale.toStringAsFixed(2))})',
          ),
        ],
      ),
    );
  }

  Widget _buildToggleRow({
    required BuildContext context,
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final colors = context.colors;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(fontSize: 12, color: colors.textPrimary)),
        Switch(
          value: value,
          onChanged: onChanged,
          activeTrackColor: colors.primary,
          activeThumbColor: Colors.white,
          inactiveTrackColor: colors.mutedBackground,
          inactiveThumbColor: colors.textMuted,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildReusedPromptPreview({
    required BuildContext context,
    required String label,
    required String text,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isEmpty = text.trim().isEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm + 2,
        vertical: AppSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.mutedBackground.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderSubtle),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.link_rounded, size: 14, color: colors.primary),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.inpaintReusedLabel(label),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEmpty ? l10n.inpaintReusedPromptEmpty : text.trim(),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: isEmpty ? colors.textMuted : colors.textSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
