import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_number_slider.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../../core/widgets/overlay_anchor.dart';
import '../view_models/studio_view_model.dart';
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
    widget.viewModel.addListener(_syncSeedFromViewModel);
  }

  void _syncSeedFromViewModel() {
    final seed = widget.viewModel.params.seed;
    final seedStr = seed < 0 ? '' : '$seed';
    if (_seedController.text != seedStr) {
      _seedController.value = TextEditingValue(
        text: seedStr,
        selection: TextSelection.collapsed(offset: seedStr.length),
      );
    }
  }

  @override
  void didUpdateWidget(covariant ParametersPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel != widget.viewModel) {
      oldWidget.viewModel.removeListener(_syncSeedFromViewModel);
      widget.viewModel.addListener(_syncSeedFromViewModel);
      _syncSeedFromViewModel();
    }
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_syncSeedFromViewModel);
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
            AppDropdown<NaiModel>.simple(
              value: params.model,
              items: NaiModel.values,
              labelOf: (m) => m.label,
              iconOf: (m) => Icons.auto_awesome_outlined,
              trailingOf: (m, _) =>
                  m.isV5 ? AppBadge.pill(label: 'V5', fontSize: 10) : null,
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
            AppNumberSlider.integer(
              title: 'Steps',
              value: params.steps,
              min: 1,
              max: 50,
              onChanged: (v) =>
                  viewModel.updateParams(params.copyWith(steps: v)),
            ),
            const SizedBox(height: 16),

            // 4. Prompt Guidance
            AppNumberSlider(
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
class _SeedAndSamplerRow extends StatefulWidget {
  final StudioViewModel viewModel;
  final TextEditingController seedController;

  const _SeedAndSamplerRow({
    required this.viewModel,
    required this.seedController,
  });

  @override
  State<_SeedAndSamplerRow> createState() => _SeedAndSamplerRowState();
}

class _SeedAndSamplerRowState extends State<_SeedAndSamplerRow> {
  final GlobalKey _buttonKey = GlobalKey();

  IconData _modeIcon(NaiSeedMode mode) {
    return switch (mode) {
      NaiSeedMode.random => Icons.eco_rounded,
      NaiSeedMode.increase => Icons.trending_up_rounded,
      NaiSeedMode.fixed => Icons.lock_outline_rounded,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final params = widget.viewModel.params;

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
                  color: colors.cardBackground,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.borderDefault),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: widget.seedController,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                          fontSize: 13,
                          fontFamily: 'monospace',
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                        decoration: InputDecoration(
                          hintText: 'Enter a seed',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
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
                        onChanged: (val) {
                          final trimmed = val.trim();
                          if (trimmed.isEmpty) {
                            if (params.seed != -1) {
                              widget.viewModel.updateParams(
                                params.copyWith(seed: -1),
                              );
                            }
                          } else {
                            final parsed = int.tryParse(trimmed);
                            if (parsed != null && parsed != params.seed) {
                              widget.viewModel.updateParams(
                                params.copyWith(seed: parsed),
                              );
                            }
                          }
                        },
                        onSubmitted: (val) {
                          final parsed = int.tryParse(val.trim());
                          widget.viewModel.updateParams(
                            params.copyWith(seed: parsed ?? -1),
                          );
                        },
                      ),
                    ),
                    // 种子模式与生成控制按钮 (弹出小选择框)
                    Tooltip(
                      message:
                          '种子设置 (${params.seedMode.chineseLabel} · ${params.seedTiming.label})',
                      child: InkWell(
                        key: _buttonKey,
                        onTap: () => _showSeedSettingsMenu(
                          context,
                          widget.viewModel,
                          _buttonKey,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        child: Container(
                          width: 32,
                          height: 32,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: params.seedMode == NaiSeedMode.fixed
                                ? colors.mutedBackground
                                : colors.primaryTint,
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: Icon(
                            _modeIcon(params.seedMode),
                            size: 16,
                            color: params.seedMode == NaiSeedMode.fixed
                                ? colors.textSecondary
                                : colors.primary,
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
              AppDropdown<NaiSampler>.simple(
                value: params.sampler,
                items: NaiSampler.values,
                labelOf: (s) => s.label,
                iconOf: (s) => Icons.tune_rounded,
                onChanged: (s) =>
                    widget.viewModel.updateParams(params.copyWith(sampler: s)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 在 Seed 按钮下方弹出种子模式与生成控制小选择框
void _showSeedSettingsMenu(
  BuildContext context,
  StudioViewModel viewModel,
  GlobalKey buttonKey,
) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;

  final renderBox = buttonKey.currentContext?.findRenderObject() as RenderBox?;
  if (renderBox == null) return;

  // 按钮窗口全局坐标 → 根 Overlay 布局坐标 (UI 缩放感知，zoom=1 时恒等)
  final buttonTopLeft = globalToOverlayPosition(
    overlay,
    renderBox.localToGlobal(Offset.zero),
  );
  final position = Offset(
    buttonTopLeft.dx,
    buttonTopLeft.dy + renderBox.size.height + 4,
  );

  late final OverlayEntry entry;
  var removed = false;
  void dismiss() {
    if (removed) return;
    removed = true;
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _SeedSettingsOverlay(
      position: position,
      buttonWidth: renderBox.size.width,
      viewModel: viewModel,
      onDismiss: dismiss,
    ),
  );
  overlay.insert(entry);
}

class _SeedSettingsOverlay extends StatefulWidget {
  final Offset position;
  final double buttonWidth;
  final StudioViewModel viewModel;
  final VoidCallback onDismiss;

  const _SeedSettingsOverlay({
    required this.position,
    required this.buttonWidth,
    required this.viewModel,
    required this.onDismiss,
  });

  @override
  State<_SeedSettingsOverlay> createState() => _SeedSettingsOverlayState();
}

class _SeedSettingsOverlayState extends State<_SeedSettingsOverlay> {
  bool _visible = false;
  static const double _menuWidth = 248.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _visible = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final screenSize = MediaQuery.sizeOf(context);
    final left = (widget.position.dx + widget.buttonWidth - _menuWidth).clamp(
      8.0,
      (screenSize.width - _menuWidth - 8.0).clamp(8.0, double.infinity),
    );
    final top = widget.position.dy.clamp(
      8.0,
      (screenSize.height - 380.0 - 8.0).clamp(8.0, double.infinity),
    );

    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
      },
      child: Actions(
        actions: <Type, Action<Intent>>{
          DismissIntent: CallbackAction<DismissIntent>(
            onInvoke: (_) {
              widget.onDismiss();
              return null;
            },
          ),
        },
        child: FocusScope(
          autofocus: true,
          child: Stack(
            children: [
              // 点击背景关闭
              Positioned.fill(
                child: Listener(
                  onPointerSignal: (_) => widget.onDismiss(),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => widget.onDismiss(),
                    onSecondaryTapDown: (_) => widget.onDismiss(),
                  ),
                ),
              ),

              // 浮层卡片本体
              Positioned(
                left: left,
                top: top,
                child: AnimatedOpacity(
                  opacity: _visible ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 100),
                  curve: Curves.easeOut,
                  child: Material(
                    color: Colors.transparent,
                    child: Container(
                      width: _menuWidth,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: colors.elevatedBackground,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colors.borderDefault),
                        boxShadow: context.shadowElevated,
                      ),
                      child: ListenableBuilder(
                        listenable: widget.viewModel,
                        builder: (context, _) {
                          final params = widget.viewModel.params;

                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // 1. 种子模式
                              _overlayGroupLabel('种子模式'),
                              _buildModeOption(
                                mode: NaiSeedMode.random,
                                icon: Icons.eco_rounded,
                                title: '1. Random (随机)',
                                subtitle: '生图时自动生成全新随机种子',
                                isSelected:
                                    params.seedMode == NaiSeedMode.random,
                              ),
                              const SizedBox(height: 2),
                              _buildModeOption(
                                mode: NaiSeedMode.increase,
                                icon: Icons.trending_up_rounded,
                                title: '2. Increase (递增)',
                                subtitle: '生图时种子数值自动 +1',
                                isSelected:
                                    params.seedMode == NaiSeedMode.increase,
                              ),
                              const SizedBox(height: 2),
                              _buildModeOption(
                                mode: NaiSeedMode.fixed,
                                icon: Icons.lock_outline_rounded,
                                title: '3. Fixed (固定)',
                                subtitle: '保持当前设置的种子数值不变',
                                isSelected:
                                    params.seedMode == NaiSeedMode.fixed,
                              ),

                              _overlayDivider(),

                              // 2. 生成控制
                              _overlayGroupLabel('生成控制'),
                              AppSegmentedPillBar<NaiSeedTiming>(
                                items: const [
                                  AppSegmentedItem(
                                    value: NaiSeedTiming.before,
                                    label: '生成前',
                                  ),
                                  AppSegmentedItem(
                                    value: NaiSeedTiming.after,
                                    label: '生成后',
                                  ),
                                ],
                                selectedValue: params.seedTiming,
                                variant: AppPillVariant.soft,
                                expand: true,
                                onValueChanged: widget.viewModel.setSeedTiming,
                              ),

                              _overlayDivider(),

                              // 3. 原功能与快捷操作
                              _buildActionRow(
                                icon: Icons.casino_outlined,
                                title: '立即随机种子',
                                onTap: () {
                                  final newSeed = generateRandomSeed();
                                  widget.viewModel.updateParams(
                                    params.copyWith(seed: newSeed),
                                  );
                                },
                              ),

                              if (params.seed >= 0) ...[
                                const SizedBox(height: 2),
                                _buildActionRow(
                                  icon: Icons.restart_alt_rounded,
                                  title: '清空重置为随机 (-1)',
                                  onTap: () {
                                    widget.viewModel.updateParams(
                                      params.copyWith(seed: -1),
                                    );
                                  },
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _overlayGroupLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: context.colors.textMuted,
        ),
      ),
    );
  }

  Widget _overlayDivider() {
    return Container(
      height: 1,
      color: context.colors.borderSubtle,
      margin: const EdgeInsets.symmetric(vertical: 6),
    );
  }

  Widget _buildModeOption({
    required NaiSeedMode mode,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isSelected,
  }) {
    return AppOptionCard<NaiSeedMode>(
      value: mode,
      isSelected: isSelected,
      title: title,
      subtitle: subtitle,
      icon: icon,
      radius: 6,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      onTap: () => widget.viewModel.setSeedMode(mode),
    );
  }

  Widget _buildActionRow({
    required IconData icon,
    required String title,
    required VoidCallback onTap,
  }) {
    final colors = context.colors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
        child: Row(
          children: [
            Icon(icon, size: 15, color: colors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Advanced Settings 折叠面板 (CFG Rescale + Noise Schedule + 元数据/水印)
class _AdvancedSettingsSection extends StatelessWidget {
  final StudioViewModel viewModel;

  const _AdvancedSettingsSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final params = viewModel.params;
    final showKeepOriginal =
        viewModel.stripMetadata || viewModel.enableWatermark;

    return AppCollapsibleSection(
      title: 'Advanced Settings',
      isCard: false,
      headerPadding: EdgeInsets.zero,
      contentPadding: const EdgeInsets.only(top: 6, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppNumberSlider(
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
          AppDropdown<NoiseSchedule>.simple(
            value: params.noiseSchedule,
            items: NoiseSchedule.values,
            labelOf: (n) => n.label,
            iconOf: (n) => Icons.waves_rounded,
            onChanged: (n) =>
                viewModel.updateParams(params.copyWith(noiseSchedule: n)),
          ),
          const SizedBox(height: 14),
          Divider(height: 1, color: colors.borderSubtle),
          const SizedBox(height: 12),

          // 1. 删除元数据开关
          AppSettingTile.switchTile(
            title: '删除元数据',
            subtitle: '导出与复制时抹除所有生成参数与隐写',
            value: viewModel.stripMetadata,
            onChanged: (val) => viewModel.setStripMetadata(val),
          ),
          const SizedBox(height: 10),

          // 2. 添加水印开关
          AppSettingTile.switchTile(
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
            AppSettingTile.switchTile(
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
