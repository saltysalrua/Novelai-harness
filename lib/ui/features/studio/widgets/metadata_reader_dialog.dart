import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/watermark_service.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_key_value_row.dart';
import '../view_models/studio_view_model.dart';

/// 拖入图片元数据读取与查看弹窗 (Notion 极简纯净风格)
class MetadataReaderDialog extends StatefulWidget {
  final ImageMetadataResult metadata;
  final Uint8List? imageBytes;
  final String? fileName;
  final StudioViewModel viewModel;

  const MetadataReaderDialog({
    super.key,
    required this.metadata,
    this.imageBytes,
    this.fileName,
    required this.viewModel,
  });

  /// 静态便捷展示方法
  static Future<void> show(
    BuildContext context, {
    required ImageMetadataResult metadata,
    Uint8List? imageBytes,
    String? fileName,
    required StudioViewModel viewModel,
  }) {
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.65),
      builder: (ctx) => MetadataReaderDialog(
        metadata: metadata,
        imageBytes: imageBytes,
        fileName: fileName,
        viewModel: viewModel,
      ),
    );
  }

  @override
  State<MetadataReaderDialog> createState() => _MetadataReaderDialogState();
}

class _MetadataReaderDialogState extends State<MetadataReaderDialog> {
  // 盲水印提取结果 (null=未提取，空串=无水印，非空=提取到的文本)
  String? _blindResult;
  bool _blindExtracting = false;

  Future<void> _extractBlindWatermark() async {
    final bytes = widget.imageBytes;
    if (bytes == null) return;
    setState(() => _blindExtracting = true);
    try {
      // 服务端 null (无水印) 与 未提取 需区分：空串表示已提取但无水印
      final text = await WatermarkService.extractBlindWatermarkAsync(bytes);
      if (mounted) {
        setState(() {
          _blindResult = text ?? '';
          _blindExtracting = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _blindResult = '';
          _blindExtracting = false;
        });
      }
    }
  }

  Widget _buildBlindWatermarkSection(BuildContext context) {
    if (_blindResult == null) {
      return const SizedBox.shrink();
    }
    final colors = context.colors;
    final hasWatermark = _blindResult!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasWatermark ? colors.primaryTint : colors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(
          color: hasWatermark
              ? colors.primary.withValues(alpha: 0.3)
              : colors.borderDefault,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasWatermark
                    ? Icons.verified_user_outlined
                    : Icons.visibility_off_outlined,
                size: 13,
                color: hasWatermark ? colors.primary : colors.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                hasWatermark ? '盲水印内容' : '未检测到盲水印',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: hasWatermark ? colors.primary : colors.textSecondary,
                ),
              ),
            ],
          ),
          if (hasWatermark) ...[
            const SizedBox(height: 6),
            SelectableText(
              _blindResult!,
              style: TextStyle(
                fontSize: 13,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _copyText(String text, String successMsg) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(successMsg),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = widget.metadata;

    return AppDialogScaffold(
      title: widget.fileName ?? '图像元数据读取',
      width: 720,
      maxHeight: 760,
      actions: _buildBottomActionButtons(context, meta),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 来源软件胶囊
            if (meta.software.isNotEmpty) ...[
              AppBadge(label: meta.software, variant: AppBadgeVariant.primary),
              const SizedBox(height: 14),
            ],

            // 图片缩略图预览与基础摘要
            if (widget.imageBytes != null) ...[
              _buildImagePreviewRow(context, meta),
              const SizedBox(height: 16),
            ],

            // 正向提示词
            if (meta.prompt.isNotEmpty) ...[
              _buildNotionSection(
                context: context,
                title: '正向提示词 (Prompt)',
                icon: Icons.text_fields_rounded,
                content: meta.prompt,
                onCopy: () => _copyText(meta.prompt, '已复制正向提示词'),
              ),
              const SizedBox(height: 14),
            ],

            // 负向提示词
            if (meta.negativePrompt.isNotEmpty) ...[
              _buildNotionSection(
                context: context,
                title: '负向提示词 (Negative Prompt)',
                icon: Icons.remove_circle_outline_rounded,
                content: meta.negativePrompt,
                onCopy: () => _copyText(meta.negativePrompt, '已复制负向提示词'),
              ),
              const SizedBox(height: 14),
            ],

            // 多角色提示词 (若存在)
            if (meta.characterPrompts.isNotEmpty) ...[
              _buildCharacterPromptsSection(context, meta),
              const SizedBox(height: 14),
            ],

            // 生成参数网格
            _buildParametersGrid(context, meta),
            const SizedBox(height: 16),

            // 原始 JSON 折叠面板
            if (meta.rawJson.isNotEmpty) ...[
              _buildRawJsonCollapsible(context, meta.rawJson),
            ],

            // 盲水印提取结果
            _buildBlindWatermarkSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePreviewRow(BuildContext context, ImageMetadataResult meta) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.mutedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: colors.borderDefault),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Image.memory(
              widget.imageBytes!,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '尺寸: ${meta.width ?? '自动'} x ${meta.height ?? '自动'}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '模型: ${meta.model ?? '未知模型'}  ·  采样: ${meta.sampler ?? '默认'}',
                  style: TextStyle(fontSize: 11, color: colors.textSecondary),
                ),
                if (meta.seed != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '种子: ${meta.seed}',
                    style: TextStyle(
                      fontSize: 11,
                      color: colors.textSecondary,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotionSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required String content,
    required VoidCallback onCopy,
  }) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: colors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  children: [
                    Icon(Icons.copy_rounded, size: 12, color: colors.primary),
                    const SizedBox(width: 4),
                    Text(
                      '复制',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colors.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.mutedBackground,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: colors.borderDefault),
          ),
          child: SelectableText(
            content,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterPromptsSection(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.people_alt_outlined,
              size: 14,
              color: colors.textSecondary,
            ),
            const SizedBox(width: 6),
            Text(
              '多角色提示词 (Character Prompts)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ...List.generate(meta.characterPrompts.length, (idx) {
          final prompt = meta.characterPrompts[idx];
          final neg = idx < meta.characterNegativePrompts.length
              ? meta.characterNegativePrompts[idx]
              : '';
          return Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colors.mutedBackground,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: colors.borderDefault),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppBadge(
                  label: '角色 ${idx + 1}',
                  variant: AppBadgeVariant.primary,
                ),
                const SizedBox(height: 6),
                SelectableText(
                  prompt,
                  style: TextStyle(fontSize: 12, color: colors.textPrimary),
                ),
                if (neg.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    '负向: $neg',
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildParametersGrid(BuildContext context, ImageMetadataResult meta) {
    final colors = context.colors;
    final items = <_ParamItem>[
      _ParamItem('模型', meta.model ?? '未知'),
      _ParamItem('采样算法', meta.sampler ?? '默认'),
      _ParamItem('步数', meta.steps != null ? '${meta.steps}' : '28'),
      _ParamItem('CFG Scale', meta.scale != null ? '${meta.scale}' : '5.0'),
      if (meta.cfgRescale != null && meta.cfgRescale! > 0)
        _ParamItem('CFG Rescale', '${meta.cfgRescale}'),
      _ParamItem('种子 (Seed)', meta.seed != null ? '${meta.seed}' : '随机'),
      if (meta.noiseSchedule != null) _ParamItem('噪声调度', meta.noiseSchedule!),
      if (meta.qualityPreset != null) _ParamItem('质量预设', meta.qualityPreset!),
      if (meta.ucPreset != null) _ParamItem('UC 预设', meta.ucPreset!),
      if (meta.transparentBackground == true) _ParamItem('透明背景', '开启'),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '生成参数',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colors.mutedBackground,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: colors.borderDefault),
          ),
          child: Column(
            children: items.map((item) {
              return AppKeyValueRow(
                label: item.label,
                value: item.value,
                isMonospace:
                    item.label.contains('种子') || item.label.contains('CFG'),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRawJsonCollapsible(BuildContext context, String rawJson) {
    final colors = context.colors;
    return AppCollapsibleSection(
      title: '原始元数据 (Raw JSON / Text)',
      initiallyExpanded: false,
      trailing: IconButton(
        icon: const Icon(Icons.copy_rounded, size: 14),
        visualDensity: VisualDensity.compact,
        tooltip: '复制原始文本',
        onPressed: () => _copyText(rawJson, '已复制原始元数据'),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: Container(
          color: colors.mutedBackground,
          padding: const EdgeInsets.all(10),
          child: SingleChildScrollView(
            child: SelectableText(
              rawJson,
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildBottomActionButtons(
    BuildContext context,
    ImageMetadataResult meta,
  ) {
    final colors = context.colors;
    return [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        style: TextButton.styleFrom(foregroundColor: colors.textSecondary),
        child: const Text('关闭'),
      ),
      const SizedBox(width: 8),
      if (widget.imageBytes != null) ...[
        OutlinedButton.icon(
          icon: _blindExtracting
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.visibility_off_outlined, size: 16),
          label: const Text('提取盲水印'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.textPrimary,
            backgroundColor: colors.cardBackground,
            side: BorderSide(color: colors.borderDefault),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          onPressed: _blindExtracting ? null : _extractBlindWatermark,
        ),
        const SizedBox(width: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: const Text('作为参考图导入'),
          style: OutlinedButton.styleFrom(
            foregroundColor: colors.textPrimary,
            backgroundColor: colors.cardBackground,
            side: BorderSide(color: colors.borderDefault),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
          ),
          onPressed: () {
            widget.viewModel.importReferenceImageFromBytes(
              widget.imageBytes!,
              fileName: widget.fileName,
            );
            Navigator.of(context).pop();
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已导入参考图')));
          },
        ),
        const SizedBox(width: 8),
      ],
      ElevatedButton.icon(
        icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
        label: const Text('应用全部参数到工作台'),
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
        onPressed: () {
          widget.viewModel.applyMetadataToWorkbench(meta);
          Navigator.of(context).pop();
        },
      ),
    ];
  }
}

class _ParamItem {
  final String label;
  final String value;
  const _ParamItem(this.label, this.value);
}
