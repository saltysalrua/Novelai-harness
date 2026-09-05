import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
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
              const PageHeader(title: '修复设置', subtitle: '局部重绘与高精度潜空间焦点特写'),
              const SizedBox(height: AppSpacing.lg),

              // 1. 修复模式切换 (AppOptionCard 选项)
              const SectionHeader('修复模式'),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: AppOptionCard<InpaintMode>(
                      value: InpaintMode.focus,
                      title: '焦点特写',
                      subtitle: '超采样无损回贴',
                      isSelected: isFocus,
                      onTap: () => vm.setInpaintMode(InpaintMode.focus),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppOptionCard<InpaintMode>(
                      value: InpaintMode.standard,
                      title: '常规重绘',
                      subtitle: '整图尺度重绘',
                      isSelected: inpaint.mode == InpaintMode.standard,
                      onTap: () => vm.setInpaintMode(InpaintMode.standard),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: AppOptionCard<InpaintMode>(
                      value: InpaintMode.aiEdit,
                      title: 'AI 整图编辑',
                      subtitle: '外部绘图模型重绘',
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
                          const SectionHeader('生图比例'),
                          const SizedBox(height: AppSpacing.sm),
                          AppDropdown<String>.simple(
                            value:
                                _aiEditAspectRatios.contains(
                                  inpaint.aiEditAspectRatio,
                                )
                                ? inpaint.aiEditAspectRatio
                                : '',
                            items: _aiEditAspectRatios,
                            labelOf: (v) => v.isEmpty ? '跟随原图' : v,
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
                          const SectionHeader('生图分辨率'),
                          const SizedBox(height: AppSpacing.sm),
                          AppDropdown<String>.simple(
                            value:
                                _aiEditResolutions.contains(
                                  inpaint.aiEditResolution,
                                )
                                ? inpaint.aiEditResolution
                                : '',
                            items: _aiEditResolutions,
                            labelOf: (v) => v.isEmpty ? '默认' : v,
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
                  title: '外延上下文 (px)',
                  value: inpaint.contextPadding.round(),
                  min: 16,
                  max: 192,
                  onChanged: (v) => vm.setInpaintContextPadding(v.toDouble()),
                ),
                const SizedBox(height: AppSpacing.md),
              ],

              if (!isAiEdit) ...[
                AppNumberSlider(
                  title: '重绘强度',
                  value: inpaint.strength,
                  min: 0.0,
                  max: 1.0,
                  fractionDigits: 2,
                  onChanged: vm.setInpaintStrength,
                ),
                const SizedBox(height: AppSpacing.md),

                AppNumberSlider(
                  title: '附加噪声',
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
              SectionHeader(isAiEdit ? '修改指令设置' : '提示词设置'),
              const SizedBox(height: AppSpacing.sm),

              _buildToggleRow(
                context: context,
                label: isAiEdit ? '复用主工作台正向词作为指令' : '复用主工作台正向词',
                value: inpaint.useMainPrompt,
                onChanged: vm.setInpaintUseMainPrompt,
              ),
              const SizedBox(height: AppSpacing.sm),
              if (!inpaint.useMainPrompt) ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      isAiEdit ? '自定义修改指令' : '修复专属正向词',
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
                      ? '输入自然语言修改指令，如: 把背景换成夕阳下的海滩...'
                      : '输入修复专属正向提示词...',
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
                  label: '主工作台正向词',
                  text: vm.params.prompt,
                ),
              ],
              const SizedBox(height: AppSpacing.md),

              if (!isAiEdit) ...[
                _buildToggleRow(
                  context: context,
                  label: '复用主工作台负向词',
                  value: inpaint.useMainNegative,
                  onChanged: vm.setInpaintUseMainNegative,
                ),
                const SizedBox(height: AppSpacing.sm),
                if (!inpaint.useMainNegative) ...[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '修复专属负向词',
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
                    hintText: '输入修复专属负向提示词...',
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
                    label: '主工作台负向词',
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
            '绘图模型',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      trailing: const AppBadge(
        label: '消耗绘图模型额度',
        variant: AppBadgeVariant.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (configured) ...[
            AppKeyValueRow(label: '供应商', value: info.providerName),
            AppKeyValueRow(label: '模型', value: info.modelName),
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
                '未配置绘图模型。请到设置 → Models 页「AI 整图编辑」选择具备图像输出能力的模型供应商与模型 (如 nano banana / gpt-image)。',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGeometryCard(BuildContext context, InpaintGeometry geometry) {
    final colors = context.colors;
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
            '潜空间焦点几何',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      trailing: AppBadge(
        label: geometry.isOpusFree ? 'Opus 免费' : '需消耗点数',
        variant: geometry.isOpusFree
            ? AppBadgeVariant.success
            : AppBadgeVariant.warning,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppKeyValueRow(
            label: '目标选区',
            value:
                '${geometry.focusBounds.width.round()} × ${geometry.focusBounds.height.round()} px',
          ),
          AppKeyValueRow(
            label: '上下文外延',
            value:
                '${geometry.contextCrop.width.round()} × ${geometry.contextCrop.height.round()} px',
          ),
          AppKeyValueRow(
            label: '请求分辨率',
            value:
                '${geometry.requestWidth} × ${geometry.requestHeight} (${geometry.scale.toStringAsFixed(2)}x 超采样)',
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
                  '已复用 $label',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isEmpty ? '（内容为空，可至提示词管理页配置）' : text.trim(),
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
