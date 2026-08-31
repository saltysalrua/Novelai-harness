import 'dart:math';

import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'editable_slider.dart';
import 'resolution_pad_picker.dart';
import 'studio_shared.dart';
import 'watermark_pad_picker.dart';

/// 侧边栏页面一：参数设置 (模型 / 分辨率 / 采样属性 / 高级选项)
class ParametersPage extends StatefulWidget {
  final StudioViewModel viewModel;

  const ParametersPage({super.key, required this.viewModel});

  @override
  State<ParametersPage> createState() => _ParametersPageState();
}

class _ParametersPageState extends State<ParametersPage> {
  late final TextEditingController _seedController;

  @override
  void initState() {
    super.initState();
    final seed = widget.viewModel.params.seed;
    _seedController = TextEditingController(text: seed < 0 ? '' : '$seed');
  }

  @override
  void didUpdateWidget(covariant ParametersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final seed = widget.viewModel.params.seed;
    final seedStr = seed < 0 ? '' : '$seed';
    if (_seedController.text != seedStr) {
      _seedController.text = seedStr;
    }
  }

  @override
  void dispose() {
    _seedController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.viewModel,
      builder: (context, _) {
        final viewModel = widget.viewModel;
        final params = viewModel.params;

        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const PageHeader(title: '参数设置', subtitle: '模型、分辨率与采样属性调节'),
            const SizedBox(height: 16),

            // 1. 模型选择
            const SectionHeader('模型'),
            const SizedBox(height: 8),
            DropdownField<NaiModel>(
              value: params.model,
              items: NaiModel.values,
              labelOf: (m) => m.label,
              onChanged: viewModel.selectModel,
            ),
            const SizedBox(height: 16),

            // 2. 官方标准分辨率预设与 2D 可视化画板
            ResolutionPadPicker(
              width: params.width,
              height: params.height,
              isOpusFree: params.isOpusFree,
              onChanged: (dims) => viewModel.updateParams(
                params.copyWith(width: dims.width, height: dims.height),
              ),
            ),
            const SizedBox(height: 18),

            // 3. Steps
            EditableSliderInt(
              title: 'Steps',
              value: params.steps,
              min: 1,
              max: 50,
              onChanged: (v) =>
                  viewModel.updateParams(params.copyWith(steps: v)),
            ),
            const SizedBox(height: 16),

            // 4. Prompt Guidance
            EditableSliderDouble(
              title: 'Prompt Guidance',
              value: params.scale,
              min: 1.0,
              max: 15.0,
              fractionDigits: 1,
              onChanged: (v) =>
                  viewModel.updateParams(params.copyWith(scale: v)),
            ),
            const SizedBox(height: 18),

            // 5. Seed & Sampler 两栏
            _SeedAndSamplerRow(
              viewModel: viewModel,
              seedController: _seedController,
            ),
            const SizedBox(height: 14),

            // 6. Advanced Settings 折叠面板
            _AdvancedSettingsSection(viewModel: viewModel),
          ],
        );
      },
    );
  }
}

/// Seed 输入框与 Sampler 下拉并排 (官方两栏排版，高度 40)
class _SeedAndSamplerRow extends StatelessWidget {
  final StudioViewModel viewModel;
  final TextEditingController seedController;

  const _SeedAndSamplerRow({
    required this.viewModel,
    required this.seedController,
  });

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          flex: 5,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Seed'),
              const SizedBox(height: 8),
              Container(
                height: 40,
                padding: const EdgeInsets.only(left: 10, right: 4),
                decoration: BoxDecoration(
                  color: AppTheme.pureWhite,
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                  border: Border.all(color: AppTheme.border),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: seedController,
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
                          filled: false,
                          hoverColor: Colors.transparent,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          errorBorder: InputBorder.none,
                          disabledBorder: InputBorder.none,
                        ),
                        onSubmitted: (val) {
                          final parsed = int.tryParse(val);
                          viewModel.updateParams(
                            params.copyWith(seed: parsed ?? -1),
                          );
                        },
                      ),
                    ),
                    // 随机种子按钮 (幼苗图标，随机模式高亮)
                    Tooltip(
                      message: 'Randomize Seed',
                      child: InkWell(
                        onTap: () {
                          final newSeed = Random().nextInt(4294967295);
                          viewModel.updateParams(
                            params.copyWith(seed: newSeed),
                          );
                        },
                        borderRadius: BorderRadius.circular(4),
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: params.seed < 0
                                ? AppTheme.skyTint
                                : AppTheme.paperWarmth,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Icon(
                            Icons.eco_rounded,
                            size: 16,
                            color: params.seed < 0
                                ? AppTheme.notionBlue
                                : AppTheme.graphite,
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
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionHeader('Sampler'),
              const SizedBox(height: 8),
              DropdownField<NaiSampler>(
                value: params.sampler,
                items: NaiSampler.values,
                labelOf: (s) => s.label,
                fontSize: 12.5,
                onChanged: (s) =>
                    viewModel.updateParams(params.copyWith(sampler: s)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Advanced Settings 折叠面板 (CFG Rescale + Noise Schedule + 元数据/水印)
class _AdvancedSettingsSection extends StatelessWidget {
  final StudioViewModel viewModel;

  const _AdvancedSettingsSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final params = viewModel.params;
    final showKeepOriginal =
        viewModel.stripMetadata || viewModel.enableWatermark;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        expandedCrossAxisAlignment: CrossAxisAlignment.start,
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
          EditableSliderDouble(
            title: 'Prompt Guidance Rescale',
            value: params.cfgRescale,
            min: 0.0,
            max: 1.0,
            fractionDigits: 2,
            onChanged: (v) =>
                viewModel.updateParams(params.copyWith(cfgRescale: v)),
          ),
          const SizedBox(height: 12),
          const SectionHeader('Noise Schedule'),
          const SizedBox(height: 8),
          DropdownField<NoiseSchedule>(
            value: params.noiseSchedule,
            items: NoiseSchedule.values,
            labelOf: (n) => n.label,
            fontSize: 12.5,
            onChanged: (n) =>
                viewModel.updateParams(params.copyWith(noiseSchedule: n)),
          ),
          const SizedBox(height: 14),
          const Divider(height: 1, color: AppTheme.border),
          const SizedBox(height: 12),

          // 1. 删除元数据开关
          SettingsToggleRow(
            title: '删除元数据',
            subtitle: '导出与复制时抹除所有生成参数与隐写',
            value: viewModel.stripMetadata,
            onChanged: (val) => viewModel.setStripMetadata(val),
          ),
          const SizedBox(height: 10),

          // 2. 添加水印开关
          SettingsToggleRow(
            title: '添加水印',
            subtitle: '仅在复制/下载时生效，UI 画板不显示',
            value: viewModel.enableWatermark,
            onChanged: (val) => viewModel.setEnableWatermark(val),
          ),

          // 水印 2D 调节面板 (开启时展开)
          if (viewModel.enableWatermark) ...[
            const SizedBox(height: 10),
            WatermarkPadPicker(
              config: viewModel.watermarkConfig,
              onChanged: (newCfg) => viewModel.updateWatermarkConfig(newCfg),
              viewModel: viewModel,
            ),
          ],

          // 3. 保持原图像开关 (当开启删除元数据或添加水印之一时展示)
          if (showKeepOriginal) ...[
            const SizedBox(height: 10),
            SettingsToggleRow(
              title: '保持原图像',
              subtitle: '生图落盘时额外保存一份纯净原图 (_raw.png)',
              value: viewModel.keepOriginalImage,
              onChanged: (val) => viewModel.setKeepOriginalImage(val),
            ),
          ],
        ],
      ),
    );
  }
}
