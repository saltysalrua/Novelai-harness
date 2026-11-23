import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../data/models/image_palette.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/config_service.dart'
    show AppAccentVariant, seedColorText;
import '../../../../data/services/palette_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_accent_controller.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/md3_accent.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_color_picker_dialog.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_transitions.dart';
import '../view_models/studio_view_model.dart';
import 'image_canvas_actions.dart';

/// 图片调色盘弹窗：MD3 官方算法提取主色 + 一键设为主题强调色
///
/// - 色块网格：Score 排序主色 (占比标注)，点击设为手动主题强调色，
///   右键复制十六进制色值；
/// - MD3 方案预览：种子色按当前取色方案推导的亮/暗主题令牌即时预览。
class PaletteInspectorDialog extends StatefulWidget {
  final StudioViewModel viewModel;
  final NaiGeneratedImage image;

  const PaletteInspectorDialog({
    super.key,
    required this.viewModel,
    required this.image,
  });

  static Future<void> show(
    BuildContext context, {
    required StudioViewModel viewModel,
    required NaiGeneratedImage image,
  }) {
    return AppDialogScaffold.show(
      context: context,
      builder: (ctx) =>
          PaletteInspectorDialog(viewModel: viewModel, image: image),
    );
  }

  @override
  State<PaletteInspectorDialog> createState() => _PaletteInspectorDialogState();
}

class _PaletteInspectorDialogState extends State<PaletteInspectorDialog> {
  ImagePalette? _palette;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _extract();
  }

  Future<void> _extract() async {
    final image = widget.image;
    final bytes =
        await widget.viewModel.ensureImageLoaded(image) ?? image.bytes;
    if (!mounted) return;
    if (bytes.isEmpty) {
      setState(() {
        _loading = false;
        _error = context.l10n.paletteExtractFailed;
      });
      return;
    }
    final palette = await PaletteService.instance.extract(
      bytes,
      cacheKey: image.id,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _palette = palette;
      _error = palette == null ? context.l10n.paletteExtractFailed : null;
    });
  }

  void _applySeed(int argb) {
    widget.viewModel.setManualAccentSeed(Color(argb));
    if (mounted) {
      showCanvasSnackBar(context, context.l10n.paletteAppliedAccent);
    }
  }

  void _copyHex(int argb) {
    Clipboard.setData(ClipboardData(text: seedColorText(argb) ?? ''));
    if (mounted) {
      showCanvasSnackBar(context, context.l10n.paletteCopiedHex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final accentState = AppAccentController.instance.state.value;

    return AppDialogScaffold(
      title: l10n.paletteDialogTitle,
      width: 560,
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(_error!, style: context.typography.bodySmall),
              ),
            )
          : AppSkeletonReveal(
              isLoaded: !_loading && _palette != null,
              enableBlur: false,
              skeleton: _buildLoadingSkeleton(context),
              child: _palette == null
                  ? const SizedBox.shrink()
                  : SingleChildScrollView(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildSwatchGrid(context),
                            const SizedBox(height: AppSpacing.lg),
                            AppActionButton(
                              label: l10n.paletteCustomColor,
                              icon: Icons.colorize,
                              onPressed: () async {
                                final picked = await AppColorPickerDialog.show(
                                  context,
                                  initialColor: Color(
                                    _palette?.seed ?? 0xFF0075DE,
                                  ),
                                );
                                if (picked == null) return;
                                _applySeed(picked.toARGB32());
                              },
                            ),
                            const SizedBox(height: AppSpacing.xl),
                            _buildM3Preview(
                              context,
                              _palette!,
                              accentState.variant,
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: List.generate(
              5,
              (_) => const AppSkeletonBox(
                width: 92,
                height: 82,
                radius: AppRadius.md,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Center(
            child: AppMatrixDotLoader(
              dotSize: 3.5,
              gap: 3.0,
              variant: AppMatrixDotVariant.orbit,
              activeColor: context.colors.primary,
            ),
          ),
        ],
      ),
    );
  }

  /// 主色色块网格
  Widget _buildSwatchGrid(BuildContext context) {
    final palette = _palette;
    if (palette == null) return const SizedBox.shrink();
    return Wrap(
      spacing: AppSpacing.md,
      runSpacing: AppSpacing.md,
      children: [
        for (final color in palette.colors)
          _PaletteSwatchTile(
            color: color,
            onTap: () => _applySeed(color.argb),
            onSecondaryTap: () => _copyHex(color.argb),
          ),
      ],
    );
  }

  /// MD3 取色方案预览 (亮/暗两套令牌)
  Widget _buildM3Preview(
    BuildContext context,
    ImagePalette palette,
    AppAccentVariant variant,
  ) {
    final l10n = context.l10n;
    final colors = context.colors;
    final seed = Color(palette.seed);
    final light = buildM3AccentTokens(
      seed: seed,
      brightness: Brightness.light,
      variant: variant,
    );
    final dark = buildM3AccentTokens(
      seed: seed,
      brightness: Brightness.dark,
      variant: variant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.paletteM3PreviewTitle,
          style: context.typography.titleMedium?.copyWith(
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        _M3PreviewRow(label: l10n.paletteM3PreviewLight, tokens: light),
        const SizedBox(height: AppSpacing.sm),
        _M3PreviewRow(label: l10n.paletteM3PreviewDark, tokens: dark),
      ],
    );
  }
}

/// 单个主色色块 (点击设为主题强调色，右键复制色值)
class _PaletteSwatchTile extends StatefulWidget {
  final PaletteColor color;
  final VoidCallback onTap;
  final VoidCallback onSecondaryTap;

  const _PaletteSwatchTile({
    required this.color,
    required this.onTap,
    required this.onSecondaryTap,
  });

  @override
  State<_PaletteSwatchTile> createState() => _PaletteSwatchTileState();
}

class _PaletteSwatchTileState extends State<_PaletteSwatchTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final reduceMotion = AppMotion.shouldReduceMotion(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        onSecondaryTap: widget.onSecondaryTap,
        onLongPress: widget.onSecondaryTap,
        child: AppHoverLift(
          lift: -2.0,
          hoverScale: 1.0,
          duration: AppMotionDurations.quick,
          child: AnimatedContainer(
            duration: reduceMotion ? Duration.zero : AppMotionDurations.quick,
            curve: AppMotionCurves.smoothOut,
            width: 92,
            padding: const EdgeInsets.all(1.0),
            decoration: BoxDecoration(
              color: colors.mutedBackground,
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            foregroundDecoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _hovered
                    ? colors.primary.withValues(alpha: 0.55)
                    : colors.borderDefault,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md - 1.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 44,
                    decoration: BoxDecoration(color: Color(widget.color.argb)),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                      vertical: AppSpacing.xs,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          seedColorText(widget.color.argb) ?? '',
                          style: context.typography.bodySmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${(widget.color.share * 100).toStringAsFixed(1)}%',
                          style: context.typography.bodySmall?.copyWith(
                            color: colors.textMuted,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// MD3 令牌预览行 (主色/亮档/深档/底色)
class _M3PreviewRow extends StatelessWidget {
  final String label;
  final M3AccentTokens tokens;

  const _M3PreviewRow({required this.label, required this.tokens});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Row(
      children: [
        SizedBox(
          width: 40,
          child: Text(
            label,
            style: context.typography.bodySmall?.copyWith(
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: Row(
            children: [
              _tokenChip(
                l10n.paletteM3TokenPrimary,
                tokens.primary,
                foreground: tokens.onPrimary,
              ),
              _tokenChip(l10n.paletteM3TokenLight, tokens.primaryLight),
              _tokenChip(l10n.paletteM3TokenDark, tokens.primaryDark),
              _tokenChip(l10n.paletteM3TokenTint, tokens.primaryTint),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tokenChip(String label, Color color, {Color? foreground}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: Column(
          children: [
            Container(
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: foreground == null
                  ? null
                  : Text(
                      'Aa',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Builder(
              builder: (context) => Text(
                label,
                style: context.typography.bodySmall?.copyWith(
                  color: context.colors.textMuted,
                  fontSize: 10,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
