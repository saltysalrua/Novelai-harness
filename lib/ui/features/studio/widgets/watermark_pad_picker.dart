import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'editable_slider.dart';
import 'studio_shared.dart';

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
        ).showSnackBar(SnackBar(content: Text('选择图片失败: $e')));
      }
    }
  }

  String _positionLabel(double x, double y) {
    if ((x - 0.0).abs() < 0.05 && (y - 0.0).abs() < 0.05) return '左上';
    if ((x - 1.0).abs() < 0.05 && (y - 0.0).abs() < 0.05) return '右上';
    if ((x - 0.5).abs() < 0.05 && (y - 0.5).abs() < 0.05) return '居中';
    if ((x - 0.0).abs() < 0.05 && (y - 1.0).abs() < 0.05) return '左下';
    if ((x - 1.0).abs() < 0.05 && (y - 1.0).abs() < 0.05) return '右下';
    return '${(x * 100).toInt()}%, ${(y * 100).toInt()}%';
  }

  Future<void> _applySmartPosition(BuildContext context) async {
    if (viewModel == null) return;
    final ok = await viewModel!.applySmartWatermarkPosition();
    if (context.mounted) {
      showWatermarkSnackBar(context, ok ? '已按低信息区域智能选位' : '画板暂无图片，无法智能选位');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditingOnCanvas = viewModel?.isEditingWatermarkPosition ?? false;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
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
              const Text(
                '水印位置',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoal,
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: '智能选位：分析当前画板图像，把水印放到细节最少的区域',
                child: InkWell(
                  onTap: () => _applySmartPosition(context),
                  borderRadius: BorderRadius.circular(4),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5, vertical: 3),
                    child: Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: AppTheme.notionBlue,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              // 位置胶囊：点击开启/关闭画板 2D 交互定位
              _WatermarkPositionPill(
                label: _positionLabel(config.posX, config.posY),
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
          SettingsToggleRow(
            title: '自动选位',
            subtitle: '每次合成时分析图像，自动放入信息量最低的区域',
            value: config.autoPosition,
            onChanged: (v) => onChanged(config.copyWith(autoPosition: v)),
          ),
          const SizedBox(height: 8),

          // 4. 自动对比度
          SettingsToggleRow(
            title: '自动对比度',
            subtitle: '按水印下方背景亮度自动加深或提亮，保证可见',
            value: config.autoContrast,
            onChanged: (v) => onChanged(config.copyWith(autoContrast: v)),
          ),
          const SizedBox(height: 12),

          // 5. 属性微调滑块 (缩放 / 不透明度 / 边距)
          EditableSliderDouble(
            title: '水印缩放 (%)',
            value: config.scalePercent,
            min: 1.0,
            max: 50.0,
            fractionDigits: 1,
            onChanged: (v) => onChanged(config.copyWith(scalePercent: v)),
          ),
          const SizedBox(height: 6),
          EditableSliderDouble(
            title: '不透明度 (%)',
            value: config.opacity * 100.0,
            min: 10.0,
            max: 100.0,
            fractionDigits: 0,
            onChanged: (v) => onChanged(config.copyWith(opacity: v / 100.0)),
          ),
          const SizedBox(height: 6),
          EditableSliderDouble(
            title: '边距比例 (%)',
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
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.visibility_off_outlined,
                size: 13,
                color: AppTheme.graphite,
              ),
              SizedBox(width: 6),
              Text(
                '盲水印',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.charcoal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          const Text(
            '频域隐形水印，肉眼不可见；粘贴图片到元数据弹窗可提取',
            style: TextStyle(fontSize: 10, color: AppTheme.graphite),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                '启用',
                style: TextStyle(fontSize: 11.5, color: AppTheme.charcoal),
              ),
              const Spacer(),
              Switch(
                value: config.blindEnabled,
                activeTrackColor: AppTheme.notionBlue,
                activeThumbColor: Colors.white,
                inactiveTrackColor: AppTheme.surfaceMuted,
                inactiveThumbColor: AppTheme.graphite,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                onChanged: (v) => onChanged(config.copyWith(blindEnabled: v)),
              ),
            ],
          ),
          if (config.blindEnabled) ...[
            const SizedBox(height: 4),
            TextFormField(
              initialValue: config.blindText,
              style: const TextStyle(fontSize: 12, color: AppTheme.charcoal),
              decoration: const InputDecoration(
                isDense: true,
                hintText: '签名 / 版权信息文本',
                hintStyle: TextStyle(fontSize: 11, color: AppTheme.graphite),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 7,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: AppTheme.border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.all(Radius.circular(6)),
                  borderSide: BorderSide(color: AppTheme.notionBlue),
                ),
              ),
              onChanged: (v) => onChanged(config.copyWith(blindText: v)),
            ),
            const SizedBox(height: 8),
            EditableSliderInt(
              title: '盲水印强度',
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
    if (config.imageBytes != null && config.imageBytes!.isNotEmpty) {
      return Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: Border.all(color: AppTheme.border),
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
                        : '已加载水印图片',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoal,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  const Text(
                    '仅在复制/下载时合成生效',
                    style: TextStyle(fontSize: 10, color: AppTheme.graphite),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: '更换图片',
              icon: const Icon(Icons.file_upload_outlined, size: 18),
              color: AppTheme.graphite,
              visualDensity: VisualDensity.compact,
              onPressed: () => _pickImage(context),
            ),
            IconButton(
              tooltip: '清除水印图片',
              icon: const Icon(
                Icons.close_rounded,
                size: 18,
                color: AppTheme.coral,
              ),
              visualDensity: VisualDensity.compact,
              onPressed: () => onChanged(config.copyWith(clearImage: true)),
            ),
          ],
        ),
      );
    }

    return InkWell(
      onTap: () => _pickImage(context),
      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(AppTheme.radiusButton),
          border: Border.all(color: AppTheme.border),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.add_photo_alternate_outlined,
              size: 18,
              color: AppTheme.notionBlue,
            ),
            SizedBox(width: 8),
            Text(
              '点击选择本地水印图片 (PNG/JPG)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: AppTheme.charcoal,
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
    return Tooltip(
      message: '在画板上拖动定位水印 (或按 ESC 退出)',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.notionBlue : AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
              color: isSelected ? AppTheme.notionBlue : AppTheme.border,
              width: 1.0,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.open_with_rounded,
                size: 11.5,
                color: isSelected ? Colors.white : AppTheme.notionBlue,
              ),
              const SizedBox(width: 4),
              Text(
                '位置: $label',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : AppTheme.notionBlue,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
