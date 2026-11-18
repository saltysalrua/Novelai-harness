import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/prompt_token_counter_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_transitions.dart';
import '../view_models/studio_view_model.dart';
import 'fixed_affixes_panel.dart';
import 'prompt_editor_card.dart';
import 'prompt_extension_deck.dart';
import 'prompt_panel_shared.dart';
import 'rich_prompt_text_controller.dart';
import 'studio_shared.dart';

/// 侧边栏页面二：提示词管理
/// 支持官方双模式：垂直堆叠模式与标签页切换模式，共用同一套编辑卡。
class PromptsPage extends StatefulWidget {
  final StudioViewModel viewModel;

  const PromptsPage({super.key, required this.viewModel});

  @override
  State<PromptsPage> createState() => _PromptsPageState();
}

class _PromptsPageState extends State<PromptsPage> {
  late final RichPromptTextController _promptController;
  late final RichPromptTextController _negativeController;
  late final RichPromptTextController _prefixController;
  late final RichPromptTextController _suffixController;

  bool _isTabbedMode = false;
  int _activeTab = 0; // 0: Prompt, 1: Undesired Content

  @override
  void initState() {
    super.initState();
    final params = widget.viewModel.params;
    _isTabbedMode = widget.viewModel.promptTabbedMode;
    _activeTab = widget.viewModel.promptActiveTab;
    _promptController = RichPromptTextController(text: params.prompt);
    _prefixController = RichPromptTextController(
      text: params.prefixPrompt ?? '',
    );
    _suffixController = RichPromptTextController(
      text: params.suffixPrompt ?? '',
    );
    _negativeController = RichPromptTextController(text: params.negativePrompt);
  }

  @override
  void didUpdateWidget(covariant PromptsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromViewModel();
  }

  void _syncFromViewModel() {
    final params = widget.viewModel.params;
    if (_isTabbedMode != widget.viewModel.promptTabbedMode) {
      _isTabbedMode = widget.viewModel.promptTabbedMode;
    }
    if (_activeTab != widget.viewModel.promptActiveTab) {
      _activeTab = widget.viewModel.promptActiveTab;
    }
    if (_promptController.text != params.prompt) {
      _promptController.text = params.prompt;
    }
    if (_prefixController.text != (params.prefixPrompt ?? '')) {
      _prefixController.text = params.prefixPrompt ?? '';
    }
    if (_suffixController.text != (params.suffixPrompt ?? '')) {
      _suffixController.text = params.suffixPrompt ?? '';
    }
    if (_negativeController.text != params.negativePrompt) {
      _negativeController.text = params.negativePrompt;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    _prefixController.dispose();
    _suffixController.dispose();
    super.dispose();
  }

  void _updatePrompt(String value) {
    widget.viewModel.updateParams(
      widget.viewModel.params.copyWith(prompt: value),
    );
  }

  void _updateNegative(String value) {
    widget.viewModel.updateParams(
      widget.viewModel.params.copyWith(negativePrompt: value),
    );
  }

  // --- 只读灰色标签与工具条组装 (堆叠 / 标签页两种模式共用) ---

  /// 当前是否处于 ComfyUI 模式 (质量词/UC 预设与 Token 上限不生效)
  bool get viewModelIsComfyUi => widget.viewModel.isComfyUiMode;

  List<GrayTag> _promptHeaderTags(NaiGenerationParams params) {
    final hasPrefix =
        params.applyFixedPrompts &&
        (params.prefixPrompt?.trim().isNotEmpty ?? false);
    return [
      if (hasPrefix)
        GrayTag(context.l10n.promptsPrefixBadge, params.prefixPrompt!.trim()),
    ];
  }

  List<GrayTag> _promptFooterTags(NaiGenerationParams params) {
    final hasSuffix =
        params.applyFixedPrompts &&
        (params.suffixPrompt?.trim().isNotEmpty ?? false);
    final qualityTags = viewModelIsComfyUi
        ? ''
        : NovelAiQualityTagsHelper.getQualityTags(
            params.model,
            resolveQualityPreset(params),
          );
    return [
      if (hasSuffix)
        GrayTag(context.l10n.promptsSuffixBadge, params.suffixPrompt!.trim()),
      if (qualityTags.isNotEmpty)
        GrayTag(context.l10n.promptsQualityTags, qualityTags),
      // 透明背景为 NovelAI 专属标签，ComfyUI 模式不拼接也不展示
      if (params.transparentBg && !viewModelIsComfyUi)
        GrayTag(
          context.l10n.promptsTransparentBackground,
          'transparent background',
        ),
    ];
  }

  List<GrayTag> _negativeFooterTags(NaiGenerationParams params) {
    if (viewModelIsComfyUi || params.isMediumEffort) return const [];
    final ucPresetStr = NovelAiUndesiredContentHelper.getUndesiredContent(
      params.model,
      params.ucPresetKey,
    );
    return [
      if (ucPresetStr.isNotEmpty)
        GrayTag(
          '${context.l10n.promptsUcPreset}: ${promptPresetLabel(context, params.ucPresetKey)}',
          ucPresetStr,
        ),
    ];
  }

  Widget? _promptToolbar() => buildPositivePromptToolbar(
    context,
    widget.viewModel,
    _promptController,
  );

  Widget? _negativeToolbar() =>
      buildNegativePromptToolbar(context, widget.viewModel);

  // --- 布局 ---

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      // 保活隐藏页暂停订阅；切回提示词页时自动读取最新参数。
      listenable: Listenable.merge([
        if (TickerMode.valuesOf(context).enabled) widget.viewModel,
      ]),
      builder: (context, _) {
        final l10n = context.l10n;
        final viewModel = widget.viewModel;
        _syncFromViewModel();

        // 同步设置项：标签分类着色开关 (设置弹窗保存后 viewModel 通知重建)
        final showCategoryColors = viewModel.config.showTagCategoryColors;
        for (final c in [
          _promptController,
          _negativeController,
          _prefixController,
          _suffixController,
        ]) {
          c.setHighlightOptions(categoryColors: showCategoryColors);
        }

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            PageHeader(title: l10n.promptsPageTitle),
            const SizedBox(height: 16),
            if (_isTabbedMode)
              _buildTabbedSection(l10n)
            else
              _buildStackedSection(l10n),

            // 提示词扩展甲板：多角色提示词 ↔ 固定词缀左右滑动切换
            const SizedBox(height: 18),
            PromptExtensionDeck(
              viewModel: viewModel,
              prefixController: _prefixController,
              suffixController: _suffixController,
            ),

            // 排除违禁词：作用于全部提示词的助手读取脱敏，独立置于页尾
            const SizedBox(height: 14),
            BannedWordsCard(viewModel: viewModel),
          ],
        );
      },
    );
  }

  /// 垂直堆叠模式：Prompt 卡与 Undesired Content 卡上下排列
  Widget _buildStackedSection(AppLocalizations l10n) {
    final viewModel = widget.viewModel;
    final params = viewModel.params;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: SectionHeader(l10n.promptsPositiveTitle)),
            if (params.prompt.trim().isNotEmpty)
              ClearTextLink(
                onTap: () {
                  _promptController.clear();
                  _updatePrompt('');
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        PromptEditorCard(
          controller: _promptController,
          onChanged: _updatePrompt,
          hintText: l10n.promptsCorePromptHint,
          minLines: 4,
          maxLines: 10,
          initialHeight: viewModel.promptHeightStacked,
          onHeightChanged: viewModel.updatePromptHeightStacked,
          headerTags: _promptHeaderTags(params),
          footerTags: _promptFooterTags(params),
          toolbar: _promptToolbar(),
          enableAutocomplete: viewModel.config.enableTagAutocomplete,
          showTranslation: viewModel.config.showTagTranslations,
          tokenUsage: viewModelIsComfyUi
              ? null
              : PromptTokenCounterService.instance.countPositive(params),
        ),

        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: SectionHeader(l10n.promptsNegativeTitle)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!params.isMediumEffort &&
                    params.negativePrompt.trim().isNotEmpty)
                  ClearTextLink(
                    onTap: () {
                      _negativeController.clear();
                      _updateNegative('');
                    },
                  ),
                const SizedBox(width: 6),
                AppIconButton(
                  icon: Icons.splitscreen_rounded,
                  tooltip: l10n.promptsSwitchToTabbedMode,
                  size: 26,
                  iconSize: 15,
                  radius: 6,
                  onPressed: () {
                    setState(() {
                      _isTabbedMode = true;
                      _activeTab = 1;
                    });
                    viewModel.setPromptTabbedMode(true);
                    viewModel.setPromptActiveTab(1);
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        PromptEditorCard(
          controller: _negativeController,
          onChanged: _updateNegative,
          readOnly: params.isMediumEffort,
          hintText: params.isMediumEffort
              ? l10n.promptsMediumUcLocked
              : l10n.promptsCustomUndesiredHint,
          minLines: 3,
          maxLines: 8,
          initialHeight: viewModel.negativePromptHeightStacked,
          onHeightChanged: viewModel.updateNegativePromptHeightStacked,
          footerTags: _negativeFooterTags(params),
          toolbar: _negativeToolbar(),
          enableAutocomplete: viewModel.config.enableTagAutocomplete,
          showTranslation: viewModel.config.showTagTranslations,
          tokenUsage: viewModelIsComfyUi
              ? null
              : PromptTokenCounterService.instance.countNegative(params),
        ),
      ],
    );
  }

  /// 标签页模式：Prompt 与 Undesired Content 胶囊切换，单卡高空间输入
  Widget _buildTabbedSection(AppLocalizations l10n) {
    final viewModel = widget.viewModel;
    final params = viewModel.params;
    final activeTab = _activeTab == 1 ? 1 : 0;
    final isPromptTab = activeTab == 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(
              child: AppSegmentedCardBar<String>(
                scrollable: true,
                items: [
                  AppSegmentedItem(
                    value: 'prompt',
                    label: l10n.promptsPositiveTitle,
                  ),
                  AppSegmentedItem(
                    value: 'undesired',
                    label: l10n.promptsNegativeTitle,
                  ),
                ],
                selectedValue: isPromptTab ? 'prompt' : 'undesired',
                onValueChanged: (v) {
                  final tab = v == 'prompt' ? 0 : 1;
                  setState(() => _activeTab = tab);
                  viewModel.setPromptActiveTab(tab);
                },
              ),
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((isPromptTab && params.prompt.trim().isNotEmpty) ||
                    (!isPromptTab &&
                        !params.isMediumEffort &&
                        params.negativePrompt.trim().isNotEmpty))
                  ClearTextLink(
                    onTap: () {
                      if (isPromptTab) {
                        _promptController.clear();
                        _updatePrompt('');
                      } else {
                        _negativeController.clear();
                        _updateNegative('');
                      }
                    },
                  ),
                const SizedBox(width: 4),
                AppIconButton(
                  icon: Icons.view_agenda_outlined,
                  tooltip: l10n.promptsSwitchToStackedMode,
                  size: 26,
                  iconSize: 15,
                  radius: 6,
                  onPressed: () {
                    setState(() => _isTabbedMode = false);
                    viewModel.setPromptTabbedMode(false);
                  },
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),

        AppPageSideBySide(
          index: activeTab,
          enableBlur: false,
          child: isPromptTab
              ? PromptEditorCard(
                  controller: _promptController,
                  onChanged: _updatePrompt,
                  hintText: l10n.promptsTabbedPromptHint,
                  minLines: 8,
                  maxLines: 16,
                  initialHeight: viewModel.promptHeightTabbed,
                  onHeightChanged: viewModel.updatePromptHeightTabbed,
                  headerTags: _promptHeaderTags(params),
                  footerTags: _promptFooterTags(params),
                  toolbar: _promptToolbar(),
                  enableAutocomplete: viewModel.config.enableTagAutocomplete,
                  showTranslation: viewModel.config.showTagTranslations,
                  tokenUsage: viewModelIsComfyUi
                      ? null
                      : PromptTokenCounterService.instance.countPositive(
                          params,
                        ),
                )
              : PromptEditorCard(
                  controller: _negativeController,
                  onChanged: _updateNegative,
                  readOnly: params.isMediumEffort,
                  hintText: params.isMediumEffort
                      ? l10n.promptsMediumUcLocked
                      : l10n.promptsTabbedUndesiredHint,
                  minLines: 8,
                  maxLines: 16,
                  initialHeight: viewModel.negativePromptHeightTabbed,
                  onHeightChanged: viewModel.updateNegativePromptHeightTabbed,
                  footerTags: _negativeFooterTags(params),
                  toolbar: _negativeToolbar(),
                  enableAutocomplete: viewModel.config.enableTagAutocomplete,
                  showTranslation: viewModel.config.showTagTranslations,
                  tokenUsage: viewModelIsComfyUi
                      ? null
                      : PromptTokenCounterService.instance.countNegative(
                          params,
                        ),
                ),
        ),
      ],
    );
  }
}
