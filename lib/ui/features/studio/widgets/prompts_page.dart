import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'character_prompts_section.dart';
import 'fixed_affixes_panel.dart';
import 'pill_widgets.dart';
import 'prompt_editor_card.dart';
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
  late final TextEditingController _promptController;
  late final TextEditingController _negativeController;
  late final TextEditingController _prefixController;
  late final TextEditingController _suffixController;

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
    _promptController = TextEditingController(text: params.prompt);
    _prefixController = TextEditingController(text: params.prefixPrompt);
    _suffixController = TextEditingController(text: params.suffixPrompt);
    _negativeController = TextEditingController(text: params.negativePrompt);
  }

  @override
  void didUpdateWidget(covariant PromptsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final params = widget.viewModel.params;
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
    final ucInt = switch (presetKey) {
      'Heavy' => 0,
      'Light' => 1,
      'Human Focus' => 2,
      'Furry Focus' => 7,
      _ => 3, // None
    };
    final viewModel = widget.viewModel;
    viewModel.updateParams(
      viewModel.params.copyWith(ucPresetKey: presetKey, ucPreset: ucInt),
    );
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

  /// 正向提示词底部工具条：左 Transparent BG (仅 V5 模型)，右 Quality Tags 预设对齐 (自适应防溢出)
  Widget _promptToolbar(NaiGenerationParams params) {
    return Row(
      children: [
        if (params.model.isV5) ...[
          ToggleChip(
            isActive: params.transparentBg,
            icon: params.transparentBg
                ? Icons.check_rounded
                : Icons.close_rounded,
            label: 'Transparent BG',
            onTap: _toggleTransparentBg,
          ),
          const SizedBox(width: 8),
        ],
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: PillDropdown<String>(
              value: _currentQualityPreset(params),
              items: NovelAiQualityTagsHelper.getAvailablePresets(params.model),
              labelOf: (p) => 'Quality Tags: $p',
              onChanged: _applyQualityPreset,
            ),
          ),
        ),
      ],
    );
  }

  /// 负面提示词底部工具条：UC Preset 下拉 (与正向卡 Quality Tags 严格右对齐，自适应防溢出)
  Widget _negativeToolbar(NaiGenerationParams params) {
    final presets = NovelAiUndesiredContentHelper.getAvailablePresets(
      params.model,
    );
    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            reverse: true,
            child: PillDropdown<String>(
              value: presets.contains(_ucPreset) ? _ucPreset : presets.first,
              items: presets,
              labelOf: (p) => 'UC Preset: $p',
              onChanged: _applyUcPreset,
            ),
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
    final viewModel = widget.viewModel;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PageHeader(title: '提示词管理', subtitle: '正向提示词、负面排除词与全局固定词缀'),
        const SizedBox(height: 16),
        if (_isTabbedMode) _buildTabbedSection() else _buildStackedSection(),

        // 多角色提示词区块 (两种模式共用，仅 V4+ 模型生效)
        const SizedBox(height: 18),
        CharacterPromptsSection(viewModel: viewModel),

        // 全局固定词缀开关与编辑面板 (两种模式共用，常驻页底)
        const SizedBox(height: 18),
        FixedAffixesPanel(
          viewModel: viewModel,
          prefixController: _prefixController,
          suffixController: _suffixController,
        ),
      ],
    );
  }

  /// 垂直堆叠模式：Prompt 卡与 Undesired Content 卡上下排列
  Widget _buildStackedSection() {
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
          hintText:
              '输入核心提示词或自然语言散文描述，如: 1girl, solo, silver hair, masterpiece...',
          minLines: 4,
          maxLines: 10,
          headerTags: _promptHeaderTags(params),
          footerTags: _promptFooterTags(params),
          toolbar: _promptToolbar(params),
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
                _ModeToggleIcon(
                  icon: Icons.splitscreen_rounded,
                  tooltip: '切换为标签页模式',
                  onTap: () => setState(() {
                    _isTabbedMode = true;
                    _activeTab = 1;
                  }),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 8),
        PromptEditorCard(
          controller: _negativeController,
          onChanged: _updateNegative,
          hintText: '输入自定义排除词，如: bad hands, blurry, extra limbs...',
          minLines: 3,
          maxLines: 8,
          footerTags: _negativeFooterTags(params),
          toolbar: _negativeToolbar(params),
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
  Widget _buildTabbedSection() {
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
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _TabHeaderPill(
                  label: 'Prompt',
                  isActive: isPromptTab,
                  onTap: () => setState(() => _activeTab = 0),
                ),
                const SizedBox(width: 6),
                _TabHeaderPill(
                  label: 'Undesired Content',
                  isActive: !isPromptTab,
                  onTap: () => setState(() => _activeTab = 1),
                ),
              ],
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
                _ModeToggleIcon(
                  icon: Icons.view_agenda_outlined,
                  tooltip: '切换为垂直并排模式',
                  onTap: () => setState(() => _isTabbedMode = false),
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
            hintText: '输入核心提示词或自然语言散文描述，如: 1girl, solo, silver hair...',
            minLines: 8,
            maxLines: 16,
            headerTags: _promptHeaderTags(params),
            footerTags: _promptFooterTags(params),
            toolbar: _promptToolbar(params),
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
            hintText: '排除不需要的特征与缺陷，如: lowres, bad anatomy, bad hands...',
            minLines: 8,
            maxLines: 16,
            footerTags: _negativeFooterTags(params),
            toolbar: _negativeToolbar(params),
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

/// 标签页切换胶囊
class _TabHeaderPill extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _TabHeaderPill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? AppTheme.notionBlue : Colors.transparent,
          borderRadius: BorderRadius.circular(AppTheme.radiusPill),
          border: Border.all(
            color: isActive ? AppTheme.notionBlue : AppTheme.border,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w700,
            color: isActive ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 布局模式切换图标按钮
class _ModeToggleIcon extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _ModeToggleIcon({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.border),
          ),
          child: Icon(icon, size: 15, color: AppTheme.textPrimary),
        ),
      ),
    );
  }
}
