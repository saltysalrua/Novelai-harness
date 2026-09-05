import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_number_slider.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../view_models/studio_view_model.dart';

/// 水印设置面板 (Notion 极简风格：侧栏仅展示水印图像、位置胶囊与属性微调，画板联动 2D 交互定位)
///
/// 支持能力：
/// - 手动 2D 画板拖拽定位 / 缩放；
/// - 智能选位 (基于图像内容挑选信息量最低区域，可一键应用或每次导出自动重选)；
/// - 自动对比度 (按背景亮度自动加深/提亮水印)；
/// - 盲水印设置 (DCT 频域隐形水印，肉眼不可见，可在元数据弹窗中提取)。
class WatermarkPadPicker extends StatelessWidget {
  final WatermarkConfig config;
  final ValueChanged<WatermarkConfig> onChanged;
  final StudioViewModel? viewModel;

  const WatermarkPadPicker({
    super.key,
    required this.config,
    required this.onChanged,
    this.viewModel,
  });

  Future<void> _pickImage(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
      );
      if (result != null && result.files.single.path != null) {
        final path = result.files.single.path!;
        final bytes = await File(path).readAsBytes();
        onChanged(config.copyWith(imagePath: path, imageBytes: bytes));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(content: Text(context.l10n.watermarkPickImageFailed(e.toString()))),
        );
      }
    }
  }

  String _positionLabel(AppLocalizations l10n, double x, double y) {
    if ((x - 0.0).abs() < 0.05 && (y - 0.0).abs() < 0.05) return l10n.watermarkPositionTopLeft;
    if ((x - 1.0).abs() < 0.05 && (y - 0.0).abs() < 0.05) return l10n.watermarkPositionTopRight;
    if ((x - 0.5).abs() < 0.05 && (y - 0.5).abs() < 0.05) return l10n.watermarkPositionCenter;
    if ((x - 0.0).abs() < 0.05 && (y - 1.0).abs() < 0.05) return l10n.watermarkPositionBottomLeft;
    if ((x - 1.0).abs() < 0.05 && (y - 1.0).abs() < 0.05) return l10n.watermarkPositionBottomRight;
    return '${(x * 100).toInt()}%, ${(y * 100).toInt()}%';
  }

  Future<void> _applySmartPosition(BuildContext context) async {
    if (viewModel == null) return;
    final ok = await viewModel!.applySmartWatermarkPosition();
    if (context.mounted) {
      final l10n = context.l10n;
      showWatermarkSnackBar(
        context,
        ok ? l10n.watermarkSmartPositionApplied : l10n.watermarkSmartPositionNoImage,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isEditingOnCanvas = viewModel?.isEditingWatermarkPosition ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. 水印图片选择区 (侧边栏只显示水印图像卡片)
          _buildImagePickerRow(context),
          const SizedBox(height: 12),

          // 2. 位置设置 (手动 2D 画板定位 + 一键智能选位)
          Row(
            children: [
              Text(
                l10n.watermarkPositionTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              AppIconButton(
                icon: Icons.auto_awesome,
                tooltip: l10n.watermarkSmartPositionTooltip,
                variant: AppIconButtonVariant.ghost,
                size: 22,
                iconSize: 13,
                iconColor: colors.primary,
                radius: 4,
                onPressed: () => _applySmartPosition(context),
              ),
              const Spacer(),
              // 位置胶囊：点击开启/关闭画板 2D 交互定位
              _WatermarkPositionPill(
                label: _positionLabel(l10n, config.posX, config.posY),
                isSelected: isEditingOnCanvas,
                onTap: () {
                  if (viewModel != null) {
                    viewModel!.setEditingWatermarkPosition(!isEditingOnCanvas);
                  }
                },
              ),
            ],
          ),
          const SizedBox(height: 10),

          // 3. 智能选位模式 (每次导出时按图像内容自动重选位置)
          AppSettingTile.switchTile(
            title: l10n.watermarkAutoPosition,
            subtitle: l10n.watermarkAutoPositionSubtitle,
            value: config.autoPosition,
            margin: EdgeInsets.zero,
            onChanged: (v) => onChanged(config.copyWith(autoPosition: v)),
          ),
          const SizedBox(height: 8),

          // 4. 自动对比度
          AppSettingTile.switchTile(
            title: l10n.watermarkAutoContrast,
            subtitle: l10n.watermarkAutoContrastSubtitle,
            value: config.autoContrast,
            margin: EdgeInsets.zero,
            onChanged: (v) => onChanged(config.copyWith(autoContrast: v)),
          ),
          const SizedBox(height: 12),

          // 5. 属性微调滑块 (缩放 / 不透明度 / 边距)
          AppNumberSlider(
            title: l10n.watermarkScalePercent,
            value: config.scalePercent,
            min: 1.0,
            max: 50.0,
            fractionDigits: 1,
            onChanged: (v) => onChanged(config.copyWith(scalePercent: v)),
          ),
          const SizedBox(height: 6),
          AppNumberSlider(
            title: l10n.watermarkOpacityPercent,
            value: config.opacity * 100.0,
            min: 10.0,
            max: 100.0,
            fractionDigits: 0,
            onChanged: (v) => onChanged(config.copyWith(opacity: v / 100.0)),
          ),
          const SizedBox(height: 6),
          AppNumberSlider(
            title: l10n.watermarkMarginPercent,
            value: config.marginPercent,
            min: 0.0,
            max: 20.0,
            fractionDigits: 1,
            onChanged: (v) => onChanged(config.copyWith(marginPercent: v)),
          ),
          const SizedBox(height: 12),

          // 6. 盲水印 (DCT 频域隐形水印)
          _buildBlindWatermarkSection(context),
        ],
      ),
    );
  }

  Widget _buildBlindWatermarkSection(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 13,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                l10n.watermarkBlindTitle,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            l10n.watermarkBlindSubtitle,
            style: TextStyle(fontSize: 10, color: colors.textSecondary),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                l10n.watermarkBlindEnable,
                style: TextStyle(fontSize: 12, color: colors.textPrimary),
              ),
              const Spacer(),
              Switch(
                value: config.blindEnabled,
                activeTrackColor: colors.primary,
                activeThumbColor: Colors.white,
                inactiveTrackColor: colors.mutedBackground,
                inactiveThumbColor: colors.textMuted,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => onChanged(config.copyWith(blindEnabled: v)),
              ),
            ],
          ),
          if (config.blindEnabled) ...[
            const SizedBox(height: 4),
            TextFormField(
              initialValue: config.blindText,
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: l10n.watermarkBlindTextHint,
                hintStyle: TextStyle(fontSize: 11, color: colors.textSecondary),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 7,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: colors.borderDefault),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: const BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: colors.primary),
                ),
              ),
              onChanged: (v) => onChanged(config.copyWith(blindText: v)),
            ),
            const SizedBox(height: 8),
            AppNumberSlider.integer(
              title: l10n.watermarkBlindStrength,
              value: config.blindStrength,
              min: 1,
              max: 5,
              onChanged: (v) => onChanged(config.copyWith(blindStrength: v)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildImagePickerRow(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    if (config.imageBytes != null && config.imageBytes!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Image.memory(
                config.imageBytes!,
                width: 42,
                height: 42,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    config.imagePath != null
                        ? config.imagePath!.split(Platform.pathSeparator).last
                        : l10n.watermarkLoadedImage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    l10n.watermarkEffectiveOnExport,
                    style: TextStyle(fontSize: 10, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            AppIconButton(
              icon: Icons.file_upload_outlined,
              tooltip: l10n.watermarkChangeImageTooltip,
              size: 30,
              iconSize: 18,
              onPressed: () => _pickImage(context),
            ),
            AppIconButton(
              icon: Icons.close_rounded,
              tooltip: l10n.watermarkClearImageTooltip,
              size: 30,
              iconSize: 18,
              iconColor: colors.error,
              onPressed: () => onChanged(config.copyWith(clearImage: true)),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _pickImage(context),
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: colors.cardBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: colors.borderDefault),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 18,
              color: colors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              l10n.watermarkSelectLocalImage,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 水印面板轻提示
void showWatermarkSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 2),
      behavior: SnackBarBehavior.floating,
    ),
  );
}

/// 水印位置胶囊 (复用角色位置设定中的胶囊视觉与交互)
class _WatermarkPositionPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _WatermarkPositionPill({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: context.l10n.watermarkPositionPillTooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? colors.primary : colors.cardBackground,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? colors.primary : colors.borderDefault,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_with_rounded,
                size: 12,
                color: isSelected ? Colors.white : colors.primary,
              ),
              const SizedBox(width: 4),
              Text(
                context.l10n.watermarkPositionPillLabel(label),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : colors.primary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
