import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'account_stamina_card.dart';

class ParameterCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const ParameterCard({super.key, required this.viewModel});

  @override
  State<ParameterCard> createState() => _ParameterCardState();
}

class _ParameterCardState extends State<ParameterCard> {
  late TextEditingController _prefixController;
  late TextEditingController _suffixController;
  late TextEditingController _negativeController;

  @override
  void initState() {
    super.initState();
    final params = widget.viewModel.params;
    _prefixController = TextEditingController(text: params.prefixPrompt);
    _suffixController = TextEditingController(text: params.suffixPrompt);
    _negativeController = TextEditingController(text: params.negativePrompt);
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
  }

  @override
  void dispose() {
    _prefixController.dispose();
    _suffixController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final params = viewModel.params;
    final isOpusFree = params.isOpusFree;

    return ExcludeSemantics(
      child: Card(
        margin: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.tune, size: 16, color: AppTheme.primaryLight),
                      SizedBox(width: 6),
                      Text(
                        '参数设置',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: isOpusFree
                          ? AppTheme.success.withValues(alpha: 0.2)
                          : AppTheme.warning.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: isOpusFree
                            ? AppTheme.success.withValues(alpha: 0.6)
                            : AppTheme.warning.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      isOpusFree ? 'Opus 免费' : '需点数',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isOpusFree ? AppTheme.success : AppTheme.warning,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // 参数表单内容 (可滚动)
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  // 1. 账号与体力信息
                  AccountStaminaCard(viewModel: viewModel),
                  const SizedBox(height: 14),

                  // 2. 模型选择
                  _buildSectionHeader('模型'),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: AppTheme.border),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<NaiModel>(
                        value: params.model,
                        isExpanded: true,
                        dropdownColor: AppTheme.surfaceElevated,
                        items: NaiModel.values.map((m) {
                          return DropdownMenuItem(
                            value: m,
                            child: Text(m.label, style: const TextStyle(fontSize: 12)),
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
                  const SizedBox(height: 14),

                  // 3. 分辨率预设与尺寸
                  _buildSectionHeader('分辨率 (${params.width}x${params.height})'),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: ResolutionPreset.values.map((preset) {
                      final isSelected = params.width == preset.width &&
                          params.height == preset.height;
                      return _buildPresetChip(
                        preset: preset,
                        isSelected: isSelected,
                        onTap: () => viewModel.selectResolutionPreset(preset),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 10),

                  // 自定义宽与高滑动条 (64 对齐)
                  Row(
                    children: [
                      Expanded(
                        child: _buildSliderField(
                          label: '宽度: ${params.width}',
                          value: params.width.toDouble(),
                          min: 64,
                          max: 2048,
                          divisions: 31,
                          onChanged: (val) {
                            final w = ((val / 64).round() * 64).clamp(64, 2048);
                            viewModel.updateParams(params.copyWith(width: w));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSliderField(
                          label: '高度: ${params.height}',
                          value: params.height.toDouble(),
                          min: 64,
                          max: 2048,
                          divisions: 31,
                          onChanged: (val) {
                            final h = ((val / 64).round() * 64).clamp(64, 2048);
                            viewModel.updateParams(params.copyWith(height: h));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 4. 采样步数与 CFG
                  _buildSliderField(
                    label: '步数: ${params.steps}',
                    value: params.steps.toDouble(),
                    min: 1,
                    max: 50,
                    divisions: 49,
                    onChanged: (val) {
                      viewModel.updateParams(params.copyWith(steps: val.toInt()));
                    },
                  ),
                  const SizedBox(height: 8),

                  Row(
                    children: [
                      Expanded(
                        child: _buildSliderField(
                          label: 'CFG: ${params.scale.toStringAsFixed(1)}',
                          value: params.scale,
                          min: 1.0,
                          max: 15.0,
                          divisions: 28,
                          onChanged: (val) {
                            viewModel.updateParams(params.copyWith(scale: val));
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _buildSliderField(
                          label: 'CFG Rescale: ${params.cfgRescale.toStringAsFixed(2)}',
                          value: params.cfgRescale,
                          min: 0.0,
                          max: 1.0,
                          divisions: 20,
                          onChanged: (val) {
                            viewModel.updateParams(params.copyWith(cfgRescale: val));
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 5. 采样算法与噪声计划
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('采样算法'),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<NaiSampler>(
                                  value: params.sampler,
                                  isExpanded: true,
                                  dropdownColor: AppTheme.surfaceElevated,
                                  items: NaiSampler.values.map((s) {
                                    return DropdownMenuItem(
                                      value: s,
                                      child: Text(s.label, style: const TextStyle(fontSize: 11)),
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
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSectionHeader('噪声调度'),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                color: AppTheme.surfaceElevated,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: AppTheme.border),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<NoiseSchedule>(
                                  value: params.noiseSchedule,
                                  isExpanded: true,
                                  dropdownColor: AppTheme.surfaceElevated,
                                  items: NoiseSchedule.values.map((n) {
                                    return DropdownMenuItem(
                                      value: n,
                                      child: Text(n.label, style: const TextStyle(fontSize: 11)),
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
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 6. 随机种子
                  _buildSectionHeader('随机种子'),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          params.seed < 0 ? '每次随机生成' : '${params.seed}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textPrimary,
                            fontFamily: 'monospace',
                          ),
                        ),
                      ),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: () {
                          viewModel.updateParams(params.copyWith(seed: -1));
                        },
                        child: const Text('随机', style: TextStyle(fontSize: 11)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),

                  // 7. 正向与负面词展开区域
                  ExpansionTile(
                    title: const Text('固定前置/后置与负面词', style: TextStyle(fontSize: 12)),
                    tilePadding: EdgeInsets.zero,
                    childrenPadding: const EdgeInsets.only(top: 8),
                    children: [
                      TextField(
                        controller: _prefixController,
                        decoration: const InputDecoration(
                          labelText: '固定前置词 (Prefix)',
                          labelStyle: TextStyle(fontSize: 11),
                        ),
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        onChanged: (val) {
                          viewModel.updateParams(params.copyWith(prefixPrompt: val));
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _suffixController,
                        decoration: const InputDecoration(
                          labelText: '固定后置词 (Suffix)',
                          labelStyle: TextStyle(fontSize: 11),
                        ),
                        style: const TextStyle(fontSize: 11),
                        maxLines: 2,
                        onChanged: (val) {
                          viewModel.updateParams(params.copyWith(suffixPrompt: val));
                        },
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _negativeController,
                        decoration: const InputDecoration(
                          labelText: '负面提示词 (Negative Prompt)',
                          labelStyle: TextStyle(fontSize: 11),
                        ),
                        style: const TextStyle(fontSize: 11),
                        maxLines: 3,
                        onChanged: (val) {
                          viewModel.updateParams(params.copyWith(negativePrompt: val));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // 底部生成按钮
            Container(
              padding: const EdgeInsets.all(12),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                onPressed: viewModel.isGenerating ? null : () => viewModel.generateImage(),
                icon: viewModel.isGenerating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.auto_awesome, size: 18),
                label: Text(
                  viewModel.isGenerating ? '生成中...' : '生成图片',
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetChip({
    required ResolutionPreset preset,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.primaryDark : AppTheme.surfaceElevated,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? AppTheme.primaryLight : AppTheme.border,
              width: 1,
            ),
          ),
          child: Text(
            preset.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              color: isSelected ? Colors.white : AppTheme.textSecondary,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textSecondary,
      ),
    );
  }

  Widget _buildSliderField({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required ValueChanged<double> onChanged,
  }) {
    final clampedValue = value.clamp(min, max);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppTheme.primary,
            inactiveTrackColor: AppTheme.surfaceElevated,
            thumbColor: AppTheme.primaryLight,
            overlayColor: AppTheme.primary.withValues(alpha: 0.2),
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
          ),
          child: Slider(
            value: clampedValue,
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}
