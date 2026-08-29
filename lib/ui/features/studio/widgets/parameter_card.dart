import 'dart:math';
import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'resolution_pad_picker.dart';
import 'studio_sidebar.dart';

class ParameterCard extends StatefulWidget {
  final StudioViewModel viewModel;
  final StudioSidebarTab activeTab;

  const ParameterCard({
    super.key,
    required this.viewModel,
    this.activeTab = StudioSidebarTab.parameters,
  });

  @override
  State<ParameterCard> createState() => _ParameterCardState();
}

class _ParameterCardState extends State<ParameterCard> {
  late TextEditingController _prefixController;
  late TextEditingController _suffixController;
  late TextEditingController _negativeController;
  late TextEditingController _seedController;

  @override
  void initState() {
    super.initState();
    final params = widget.viewModel.params;
    _prefixController = TextEditingController(text: params.prefixPrompt);
    _suffixController = TextEditingController(text: params.suffixPrompt);
    _negativeController = TextEditingController(text: params.negativePrompt);
    _seedController = TextEditingController(text: params.seed < 0 ? '' : '${params.seed}');
  }

  @override
  void didUpdateWidget(covariant ParameterCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final params = widget.viewModel.params;
    if (_prefixController.text != (params.prefixPrompt ?? '')) {
      _prefixController.text = params.prefixPrompt ?? '';
    }
    if (_suffixController.text != (params.suffixPrompt ?? '')) {
      _suffixController.text = params.suffixPrompt ?? '';
    }
    if (_negativeController.text != params.negativePrompt) {
      _negativeController.text = params.negativePrompt;
    }
    final seedStr = params.seed < 0 ? '' : '${params.seed}';
    if (_seedController.text != seedStr) {
      _seedController.text = seedStr;
    }
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _suffixController.dispose();
    _negativeController.dispose();
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final params = viewModel.params;

    return ExcludeSemantics(
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 主体可滚动区域 (根据当前 activeTab 切换展示)
            Expanded(
              child: widget.activeTab == StudioSidebarTab.parameters
                  ? _buildParametersPage(viewModel, params)
                  : _buildPromptsPage(viewModel, params),
            ),

            // 底部常驻合并操作面板 (账号/体力/免点/刷新 + 生成图片)
            _buildBottomDock(viewModel, params),
          ],
        ),
      ),
    );
  }

  // --- 1. 参数设置分页 ---
  Widget _buildParametersPage(StudioViewModel viewModel, NaiGenerationParams params) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 页标题
        const Text(
          '参数设置',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 3),
        const Text(
          '模型、分辨率与采样属性调节',
          style: TextStyle(fontSize: 11.5, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 16),

        // 1. 模型选择
        _buildSectionHeader('模型'),
        const SizedBox(height: 8),
        Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(AppTheme.radiusButton),
            border: Border.all(color: AppTheme.border),
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<NaiModel>(
              value: params.model,
              isExpanded: true,
              dropdownColor: AppTheme.pureWhite,
              items: NaiModel.values.map((m) {
                return DropdownMenuItem(
                  value: m,
                  child: Text(m.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
                );
              }).toList(),
              onChanged: (m) {
                if (m != null) {
                  viewModel.updateParams(params.copyWith(model: m));
                }
              },
            ),
          ),
        ),
        const SizedBox(height: 16),

        // 2. 官方标准分辨率预设与 2D 可视化画板
        _buildResolutionSection(viewModel, params),
        const SizedBox(height: 18),

        // 3. Steps - 官方纯正标签：左侧输入框 + 右侧大尺寸滑块
        _buildSliderWithBoxInt(
          title: 'Steps',
          value: params.steps,
          min: 1,
          max: 50,
          onChanged: (val) => viewModel.updateParams(params.copyWith(steps: val)),
        ),
        const SizedBox(height: 16),

        // 4. Prompt Guidance - 官方纯正标签：左侧输入框 + 右侧大尺寸滑块
        _buildSliderWithBoxDouble(
          title: 'Prompt Guidance',
          value: params.scale,
          min: 1.0,
          max: 15.0,
          fractionDigits: 1,
          onChanged: (val) => viewModel.updateParams(params.copyWith(scale: val)),
        ),
        const SizedBox(height: 18),

        // 5. Seed & Sampler - 官方纯正两栏排版 (高度 40)
        _buildSeedAndSamplerRow(viewModel, params),
        const SizedBox(height: 14),

        // 6. Advanced Settings - 官方高级折叠面板
        _buildAdvancedSettingsSection(viewModel, params),
      ],
    );
  }

  // --- 2. 提示词管理分页 ---
  Widget _buildPromptsPage(StudioViewModel viewModel, NaiGenerationParams params) {
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        // 页标题
        const Text(
          '提示词管理',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        const Text(
          '配置全局固定前置词、后置词与负面词',
          style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        const SizedBox(height: 14),

        // 1. 固定前置词
        _buildSectionHeader('固定前置词 (Prefix)'),
        const SizedBox(height: 4),
        const Text(
          '自动拼接在每次提示词的最前方 (如画风、质量修饰)',
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _prefixController,
          decoration: const InputDecoration(
            hintText: '如: masterpiece, best quality, aesthetic...',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
          maxLines: 4,
          onChanged: (val) {
            viewModel.updateParams(params.copyWith(prefixPrompt: val));
          },
        ),
        const SizedBox(height: 14),

        // 2. 固定后置词
        _buildSectionHeader('固定后置词 (Suffix)'),
        const SizedBox(height: 4),
        const Text(
          '自动拼接在每次提示词的最后方 (如全局环境、镜头修饰)',
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _suffixController,
          decoration: const InputDecoration(
            hintText: '如: cinematic lighting, dynamic angle, highres...',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
          maxLines: 4,
          onChanged: (val) {
            viewModel.updateParams(params.copyWith(suffixPrompt: val));
          },
        ),
        const SizedBox(height: 14),

        // 3. 负面提示词
        _buildSectionHeader('负面提示词 (Negative Prompt)'),
        const SizedBox(height: 4),
        const Text(
          '排除不需要的特征、缺陷与质量抑制词',
          style: TextStyle(fontSize: 10, color: AppTheme.textMuted),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _negativeController,
          decoration: const InputDecoration(
            hintText: '如: lowres, bad anatomy, bad hands, text, error...',
          ),
          style: const TextStyle(fontSize: 12, height: 1.4),
          maxLines: 6,
          onChanged: (val) {
            viewModel.updateParams(params.copyWith(negativePrompt: val));
          },
        ),
      ],
    );
  }

  // --- 3. 底部常驻合并操作面板 (账号/体力/免点/刷新 + 生成按钮) ---
  Widget _buildBottomDock(StudioViewModel viewModel, NaiGenerationParams params) {
    final info = viewModel.accountInfo;
    final isLoading = viewModel.isLoadingAccount;
    final isOpusFree = params.isOpusFree;

    final percent = info != null ? (info.staminaPercent / 100.0).clamp(0.0, 1.0) : 0.0;
    final staminaColor = (info?.staminaPercent ?? 0) >= 80
        ? AppTheme.success
        : (info?.staminaPercent ?? 0) >= 30
            ? AppTheme.warning
            : AppTheme.error;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppTheme.pureWhite,
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 账号信息与体力状态条
          if (info == null)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '未获取账号信息 (请检查 API Key)',
                    style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                _buildOpusBadge(isOpusFree),
                const SizedBox(width: 4),
                _buildRefreshButton(isLoading, viewModel),
              ],
            )
          else ...[
            // 等级、点数、免点胶囊与刷新
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppTheme.skyTint,
                    borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                    border: Border.all(color: AppTheme.notionBlue.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    info.tierName,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.notionBlue,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${info.totalAnlas} Anlas',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                  ),
                ),
                const SizedBox(width: 6),
                _buildOpusBadge(isOpusFree),
                const Spacer(),
                _buildRefreshButton(isLoading, viewModel),
              ],
            ),
            const SizedBox(height: 6),

            // 体力进度条
            Row(
              children: [
                const Text(
                  'V5 体力',
                  style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppTheme.radiusSmall),
                    child: LinearProgressIndicator(
                      value: percent,
                      backgroundColor: const Color(0xFFEFEFEF),
                      valueColor: AlwaysStoppedAnimation<Color>(staminaColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${info.staminaPercent.toStringAsFixed(0)}%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: staminaColor,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  info.timeUntilNextPercent > 0
                      ? '(${info.timeUntilNextPercent}s)'
                      : (info.staminaPercent >= 100 ? '(满)' : ''),
                  style: const TextStyle(fontSize: 9, color: AppTheme.textMuted),
                ),
              ],
            ),
          ],

          const SizedBox(height: 10),

          // 生成按钮 (Notion Blue Primary CTA)
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 11),
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
            ),
            onPressed: viewModel.isGenerating ? null : () => viewModel.generateImage(),
            icon: viewModel.isGenerating
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.auto_awesome, size: 15),
            label: Text(
              viewModel.isGenerating ? '生成中...' : '生成图片',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOpusBadge(bool isOpusFree) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        color: isOpusFree
            ? AppTheme.success.withValues(alpha: 0.12)
            : AppTheme.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
        border: Border.all(
          color: isOpusFree
              ? AppTheme.success.withValues(alpha: 0.4)
              : AppTheme.warning.withValues(alpha: 0.4),
        ),
      ),
      child: Text(
        isOpusFree ? 'Opus 免费' : '需点数',
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: isOpusFree ? AppTheme.success : AppTheme.warning,
        ),
      ),
    );
  }

  Widget _buildRefreshButton(bool isLoading, StudioViewModel viewModel) {
    return IconButton(
      icon: isLoading
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(AppTheme.notionBlue),
              ),
            )
          : const Icon(Icons.refresh, size: 15, color: AppTheme.textSecondary),
      tooltip: '刷新体力与点数',
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(2),
      constraints: const BoxConstraints(),
      onPressed: isLoading ? null : () => viewModel.refreshAccountInfo(),
    );
  }

  Widget _buildResolutionSection(StudioViewModel viewModel, NaiGenerationParams params) {
    return ResolutionPadPicker(
      width: params.width,
      height: params.height,
      isOpusFree: params.isOpusFree,
      onChanged: (dims) {
        viewModel.updateParams(params.copyWith(
          width: dims.width,
          height: dims.height,
        ));
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: AppTheme.textPrimary,
      ),
    );
  }

  /// 官方风格：左侧可直接输入数字的输入框 + 右侧大尺寸滑块 (整型)
  Widget _buildSliderWithBoxInt({
    required String title,
    required int value,
    required int min,
    required int max,
    required ValueChanged<int> onChanged,
  }) {
    return _EditableSliderInt(
      title: title,
      value: value,
      min: min,
      max: max,
      onChanged: onChanged,
    );
  }

  /// 官方风格：左侧可直接输入数字的输入框 + 右侧大尺寸滑块 (浮点型)
  Widget _buildSliderWithBoxDouble({
    required String title,
    required double value,
    required double min,
    required double max,
    required int fractionDigits,
    required ValueChanged<double> onChanged,
  }) {
    return _EditableSliderDouble(
      title: title,
      value: value,
      min: min,
      max: max,
      fractionDigits: fractionDigits,
      onChanged: onChanged,
    );
  }

  /// 官方风格：Seed 与 Sampler 并排组件 (高度 40，单层平整无多余内框)
  Widget _buildSeedAndSamplerRow(StudioViewModel viewModel, NaiGenerationParams params) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Seed (随机种子输入 + 幼苗/骰子按钮，绝对单层无内边框)
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Seed'),
              const SizedBox(height: 8),
              Container(
                height: 40,
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  border: Border.all(color: AppTheme.border),
                ),
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _seedController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Enter a seed',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: AppTheme.textMuted,
                            fontWeight: FontWeight.normal,
                          ),
                          contentPadding: EdgeInsets.zero,
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                        onSubmitted: (val) {
                          final parsed = int.tryParse(val);
                          viewModel.updateParams(params.copyWith(seed: parsed ?? -1));
                        },
                      ),
                    ),
                    Tooltip(
                      message: 'Randomize Seed',
                      child: InkWell(
                        onTap: () {
                          final newSeed = Random().nextInt(4294967295);
                          viewModel.updateParams(params.copyWith(seed: newSeed));
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: params.seed < 0 ? AppTheme.skyTint : AppTheme.paperWarmth,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.eco_rounded,
                            size: 16,
                            color: params.seed < 0 ? AppTheme.notionBlue : AppTheme.graphite,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 10),

        // 2. Sampler (采样算法下拉框)
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Sampler'),
              const SizedBox(height: 8),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<NaiSampler>(
                    value: params.sampler,
                    isExpanded: true,
                    dropdownColor: AppTheme.pureWhite,
                    items: NaiSampler.values.map((s) {
                      return DropdownMenuItem(
                        value: s,
                        child: Text(
                          s.label,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      );
                    }).toList(),
                    onChanged: (s) {
                      if (s != null) {
                        viewModel.updateParams(params.copyWith(sampler: s));
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// 官方风格：Advanced Settings 折叠面板 (CFG Rescale + Noise Schedule)
  Widget _buildAdvancedSettingsSection(StudioViewModel viewModel, NaiGenerationParams params) {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(top: 6, bottom: 8),
        title: const Text(
          'Advanced Settings',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        initiallyExpanded: false,
        children: [
          // Prompt Guidance Rescale (CFG Rescale)
          _buildSliderWithBoxDouble(
            title: 'Prompt Guidance Rescale',
            value: params.cfgRescale,
            min: 0.0,
            max: 1.0,
            fractionDigits: 2,
            onChanged: (val) => viewModel.updateParams(params.copyWith(cfgRescale: val)),
          ),
          const SizedBox(height: 12),

          // Noise Schedule (噪声调度)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader('Noise Schedule'),
              const SizedBox(height: 8),
              Container(
                height: 40,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<NoiseSchedule>(
                    value: params.noiseSchedule,
                    isExpanded: true,
                    dropdownColor: AppTheme.pureWhite,
                    items: NoiseSchedule.values.map((n) {
                      return DropdownMenuItem(
                        value: n,
                        child: Text(
                          n.label,
                          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
                        ),
                      );
                    }).toList(),
                    onChanged: (n) {
                      if (n != null) {
                        viewModel.updateParams(params.copyWith(noiseSchedule: n));
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 支持键盘直接输入与滑块双向实时联动的整型数值微调组件 (单层干净无双边框)
class _EditableSliderInt extends StatefulWidget {
  final String title;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _EditableSliderInt({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  State<_EditableSliderInt> createState() => _EditableSliderIntState();
}

class _EditableSliderIntState extends State<_EditableSliderInt> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
  }

  @override
  void didUpdateWidget(_EditableSliderInt oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final parsed = int.tryParse(_controller.text);
      if (parsed != widget.value) {
        _controller.text = '${widget.value}';
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String val) {
    final parsed = int.tryParse(val);
    if (parsed != null) {
      final clamped = parsed.clamp(widget.min, widget.max);
      _controller.text = '$clamped';
      widget.onChanged(clamped);
    } else {
      _controller.text = '${widget.value}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // 左侧单层平整输入框 (宽度 60，高度 36)
            Container(
              width: 60,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.pureWhite,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                border: Border.all(color: AppTheme.border),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: 12),
            // 右侧大尺寸滑块
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5.0,
                  activeTrackColor: AppTheme.notionBlue,
                  inactiveTrackColor: AppTheme.border,
                  thumbColor: AppTheme.pureWhite,
                  overlayColor: AppTheme.notionBlue.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8.0,
                    elevation: 2.0,
                  ),
                ),
                child: Slider(
                  value: widget.value.toDouble().clamp(widget.min.toDouble(), widget.max.toDouble()),
                  min: widget.min.toDouble(),
                  max: widget.max.toDouble(),
                  divisions: widget.max - widget.min,
                  onChanged: (v) {
                    final rounded = v.round();
                    _controller.text = '$rounded';
                    widget.onChanged(rounded);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// 支持键盘直接输入与滑块双向实时联动的浮点型数值微调组件 (单层干净无双边框)
class _EditableSliderDouble extends StatefulWidget {
  final String title;
  final double value;
  final double min;
  final double max;
  final int fractionDigits;
  final ValueChanged<double> onChanged;

  const _EditableSliderDouble({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.fractionDigits,
    required this.onChanged,
  });

  @override
  State<_EditableSliderDouble> createState() => _EditableSliderDoubleState();
}

class _EditableSliderDoubleState extends State<_EditableSliderDouble> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value.toStringAsFixed(widget.fractionDigits));
  }

  @override
  void didUpdateWidget(_EditableSliderDouble oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      final parsed = double.tryParse(_controller.text);
      if (parsed != widget.value) {
        _controller.text = widget.value.toStringAsFixed(widget.fractionDigits);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit(String val) {
    final parsed = double.tryParse(val);
    if (parsed != null) {
      final clamped = double.parse(parsed.clamp(widget.min, widget.max).toStringAsFixed(widget.fractionDigits));
      _controller.text = clamped.toStringAsFixed(widget.fractionDigits);
      widget.onChanged(clamped);
    } else {
      _controller.text = widget.value.toStringAsFixed(widget.fractionDigits);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: AppTheme.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            // 左侧单层平整输入框 (宽度 60，高度 36)
            Container(
              width: 60,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.pureWhite,
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                border: Border.all(color: AppTheme.border),
              ),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: TextField(
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  color: AppTheme.textPrimary,
                ),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                ),
                onSubmitted: _submit,
              ),
            ),
            const SizedBox(width: 12),
            // 右侧大尺寸滑块
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 5.0,
                  activeTrackColor: AppTheme.notionBlue,
                  inactiveTrackColor: AppTheme.border,
                  thumbColor: AppTheme.pureWhite,
                  overlayColor: AppTheme.notionBlue.withValues(alpha: 0.12),
                  thumbShape: const RoundSliderThumbShape(
                    enabledThumbRadius: 8.0,
                    elevation: 2.0,
                  ),
                ),
                child: Slider(
                  value: widget.value.clamp(widget.min, widget.max),
                  min: widget.min,
                  max: widget.max,
                  onChanged: (v) {
                    final rounded = double.parse(v.toStringAsFixed(widget.fractionDigits));
                    _controller.text = rounded.toStringAsFixed(widget.fractionDigits);
                    widget.onChanged(rounded);
                  },
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

