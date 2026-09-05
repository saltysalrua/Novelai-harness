import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../view_models/studio_view_model.dart';
import 'prompt_editor_card.dart';
import 'prompt_extension_deck.dart';
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
  String _qualityPreset = 'Standard';
  String _ucPreset = 'Heavy';

  @override
  void initState() {
    super.initState();
    final params = widget.viewModel.params;
    _qualityPreset = params.qualityPreset;
    _ucPreset = params.ucPresetKey;
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
    final params = widget.viewModel.params;
    if (_isTabbedMode != widget.viewModel.promptTabbedMode) {
      _isTabbedMode = widget.viewModel.promptTabbedMode;
    }
    if (_activeTab != widget.viewModel.promptActiveTab) {
      _activeTab = widget.viewModel.promptActiveTab;
    }
    if (_qualityPreset != params.qualityPreset) {
      _qualityPreset = params.qualityPreset;
    }
    if (_ucPreset != params.ucPresetKey) {
      _ucPreset = params.ucPresetKey;
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

  // --- 预设与开关操作 ---

  void _applyQualityPreset(String presetKey) {
    setState(() => _qualityPreset = presetKey);
    final viewModel = widget.viewModel;
    viewModel.updateParams(
      viewModel.params.copyWith(
        qualityPreset: presetKey,
        qualityToggle: presetKey != 'None',
      ),
    );
  }

  void _applyUcPreset(String presetKey) {
    setState(() => _ucPreset = presetKey);
    final viewModel = widget.viewModel;
    viewModel.updateParams(viewModel.params.copyWith(ucPresetKey: presetKey));
  }

  /// 切换透明背景，并清理输入框中残留的 transparent / simple background 字样
  void _toggleTransparentBg() {
    final viewModel = widget.viewModel;
    final params = viewModel.params;
    var p = _promptController.text;
    if (p.contains('transparent background') ||
        p.contains('simple background')) {
      p = p.replaceAll(
        RegExp(r',?\s*transparent background', caseSensitive: false),
        '',
      );
      p = p.replaceAll(
        RegExp(r',?\s*simple background', caseSensitive: false),
        '',
      );
      p = p.replaceAll(RegExp(r',\s*,\s*'), ', ');
      p = p.replaceAll(RegExp(r',\s*$'), '').trim();
      _promptController.text = p;
    }
    viewModel.updateParams(
      params.copyWith(prompt: p, transparentBg: !params.transparentBg),
    );
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

  List<GrayTag> _promptHeaderTags(NaiGenerationParams params) {
    final hasPrefix =
        params.applyFixedPrompts &&
        (params.prefixPrompt?.trim().isNotEmpty ?? false);
    return [if (hasPrefix) GrayTag('PREFIX', params.prefixPrompt!.trim())];
  }

  List<GrayTag> _promptFooterTags(NaiGenerationParams params) {
    final hasSuffix =
        params.applyFixedPrompts &&
        (params.suffixPrompt?.trim().isNotEmpty ?? false);
    final qualityTags = NovelAiQualityTagsHelper.getQualityTags(
      params.model,
      _qualityPreset,
    );
    return [
      if (hasSuffix) GrayTag('SUFFIX', params.suffixPrompt!.trim()),
      if (qualityTags.isNotEmpty) GrayTag('QUALITY', qualityTags),
      if (params.transparentBg) const GrayTag('BG', 'transparent background'),
    ];
  }

  List<GrayTag> _negativeFooterTags(NaiGenerationParams params) {
    final ucPresetStr = NovelAiUndesiredContentHelper.getUndesiredContent(
      params.model,
      _ucPreset,
    );
    return [
      if (ucPresetStr.isNotEmpty)
        GrayTag('UC: ${params.ucPresetKey.toUpperCase()}', ucPresetStr),
    ];
  }

  /// 正向提示词底部工具条：左 Transparent BG (仅 V5 模型)，右 Quality Tags 预设胶囊 (全宽自适应省略)
  Widget _promptToolbar(NaiGenerationParams params) {
    return Row(
      children: [
        if (params.model.isV5) ...[
          AppToolChip(
            isSelected: params.transparentBg,
            icon: params.transparentBg
                ? Icons.check_rounded
                : Icons.close_rounded,
            label: 'Transparent BG',
            onTap: _toggleTransparentBg,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: AppDropdown<String>.simple(
            value: _currentQualityPreset(params),
            items: NovelAiQualityTagsHelper.getAvailablePresets(params.model),
            labelOf: (p) => 'Quality Tags: $p',
            variant: AppDropdownVariant.pill,
            onChanged: _applyQualityPreset,
          ),
        ),
      ],
    );
  }

  /// 负面提示词底部工具条：UC Preset 下拉 (胶囊全宽右对齐，超长标签自动省略)
  Widget _negativeToolbar(NaiGenerationParams params) {
    final presets = NovelAiUndesiredContentHelper.availablePresets;
    return Row(
      children: [
        Expanded(
          child: AppDropdown<String>.simple(
            value: presets.contains(_ucPreset) ? _ucPreset : presets.first,
            items: presets,
            labelOf: (p) => 'UC Preset: $p',
            variant: AppDropdownVariant.pill,
            onChanged: _applyUcPreset,
          ),
        ),
      ],
    );
  }

  String _currentQualityPreset(NaiGenerationParams params) {
    final presets = NovelAiQualityTagsHelper.getAvailablePresets(params.model);
    return presets.contains(_qualityPreset) ? _qualityPreset : 'Standard';
  }

  // --- 布局 ---

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final viewModel = widget.viewModel;

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
        PageHeader(
          title: l10n.promptsPageTitle,
          subtitle: l10n.promptsPageSubtitle,
        ),
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
      ],
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
            const SectionHeader('Prompt'),
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
          toolbar: _promptToolbar(params),
          enableAutocomplete: viewModel.config.enableTagAutocomplete,
          showTranslation: viewModel.config.showTagTranslations,
          tokenEstimate: estimatePromptTokens(
            _promptController.text,
            limit: params.model.tokenLimit,
          ),
          tokenLimit: params.model.tokenLimit,
        ),

        const SizedBox(height: 16),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const SectionHeader('Undesired Content'),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (params.negativePrompt.trim().isNotEmpty)
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
          hintText: l10n.promptsCustomUndesiredHint,
          minLines: 3,
          maxLines: 8,
          initialHeight: viewModel.negativePromptHeightStacked,
          onHeightChanged: viewModel.updateNegativePromptHeightStacked,
          footerTags: _negativeFooterTags(params),
          toolbar: _negativeToolbar(params),
          enableAutocomplete: viewModel.config.enableTagAutocomplete,
          showTranslation: viewModel.config.showTagTranslations,
          tokenEstimate: estimatePromptTokens(
            _negativeController.text,
            limit: params.model.tokenLimit,
          ),
          tokenLimit: params.model.tokenLimit,
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
            AppSegmentedPillBar<String>(
              items: const [
                AppSegmentedItem(value: 'prompt', label: 'Prompt'),
                AppSegmentedItem(
                  value: 'undesired',
                  label: 'Undesired Content',
                ),
              ],
              selectedValue: isPromptTab ? 'prompt' : 'undesired',
              onValueChanged: (v) {
                final tab = v == 'prompt' ? 0 : 1;
                setState(() => _activeTab = tab);
                viewModel.setPromptActiveTab(tab);
              },
            ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if ((isPromptTab && params.prompt.trim().isNotEmpty) ||
                    (!isPromptTab && params.negativePrompt.trim().isNotEmpty))
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

        if (isPromptTab)
          PromptEditorCard(
            controller: _promptController,
            onChanged: _updatePrompt,
            hintText: l10n.promptsTabbedPromptHint,
            minLines: 8,
            maxLines: 16,
            initialHeight: viewModel.promptHeightTabbed,
            onHeightChanged: viewModel.updatePromptHeightTabbed,
            headerTags: _promptHeaderTags(params),
            footerTags: _promptFooterTags(params),
            toolbar: _promptToolbar(params),
            enableAutocomplete: viewModel.config.enableTagAutocomplete,
            showTranslation: viewModel.config.showTagTranslations,
            tokenEstimate: estimatePromptTokens(
              _promptController.text,
              limit: params.model.tokenLimit,
            ),
            tokenLimit: params.model.tokenLimit,
          )
        else
          PromptEditorCard(
            controller: _negativeController,
            onChanged: _updateNegative,
            hintText: l10n.promptsTabbedUndesiredHint,
            minLines: 8,
            maxLines: 16,
            initialHeight: viewModel.negativePromptHeightTabbed,
            onHeightChanged: viewModel.updateNegativePromptHeightTabbed,
            footerTags: _negativeFooterTags(params),
            toolbar: _negativeToolbar(params),
            enableAutocomplete: viewModel.config.enableTagAutocomplete,
            showTranslation: viewModel.config.showTagTranslations,
            tokenEstimate: estimatePromptTokens(
              _negativeController.text,
              limit: params.model.tokenLimit,
            ),
            tokenLimit: params.model.tokenLimit,
          ),
      ],
    );
  }
}
