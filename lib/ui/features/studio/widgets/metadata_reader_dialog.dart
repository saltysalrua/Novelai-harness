import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/watermark_service.dart';
import '../../../core/theme/app_theme.dart';
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
  bool _showRawJson = false;

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

  Widget _buildBlindWatermarkSection() {
    if (_blindResult == null) {
      return const SizedBox.shrink();
    }
    final hasWatermark = _blindResult!.isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: hasWatermark ? AppTheme.skyTint : AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: hasWatermark
              ? AppTheme.notionBlue.withValues(alpha: 0.3)
              : AppTheme.border,
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
                color: hasWatermark ? AppTheme.notionBlue : AppTheme.graphite,
              ),
              const SizedBox(width: 6),
              Text(
                hasWatermark ? '盲水印内容' : '未检测到盲水印',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: hasWatermark ? AppTheme.notionBlue : AppTheme.graphite,
                ),
              ),
            ],
          ),
          if (hasWatermark) ...[
            const SizedBox(height: 6),
            SelectableText(
              _blindResult!,
              style: const TextStyle(
                fontSize: 12.5,
                fontFamily: 'monospace',
                color: AppTheme.charcoal,
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

    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.border),
      ),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. Notion 风格顶栏 (来源徽章 + 文件名 + 关闭按钮)
            _buildHeader(meta),
            const Divider(height: 1, color: AppTheme.border),

            // 2. 核心内容区域 (滚动)
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 图片缩略图预览与基础摘要
                    if (widget.imageBytes != null) ...[
                      _buildImagePreviewRow(meta),
                      const SizedBox(height: 16),
                    ],

                    // 正向提示词
                    if (meta.prompt.isNotEmpty) ...[
                      _buildNotionSection(
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
                        title: '负向提示词 (Negative Prompt)',
                        icon: Icons.remove_circle_outline_rounded,
                        content: meta.negativePrompt,
                        onCopy: () =>
                            _copyText(meta.negativePrompt, '已复制负向提示词'),
                      ),
                      const SizedBox(height: 14),
                    ],

                    // 多角色提示词 (若存在)
                    if (meta.characterPrompts.isNotEmpty) ...[
                      _buildCharacterPromptsSection(meta),
                      const SizedBox(height: 14),
                    ],

                    // 生成参数网格
                    _buildParametersGrid(meta),
                    const SizedBox(height: 16),

                    // 原始 JSON 折叠面板
                    if (meta.rawJson.isNotEmpty) ...[
                      _buildRawJsonCollapsible(meta.rawJson),
                    ],

                    // 盲水印提取结果
                    _buildBlindWatermarkSection(),
                  ],
                ),
              ),
            ),

            const Divider(height: 1, color: AppTheme.border),

            // 3. 底部操作栏 (应用到工作台 / 导入参考图 / 关闭)
            _buildBottomActionBar(meta),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ImageMetadataResult meta) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          // 来源软件胶囊
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: AppTheme.skyTint,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: AppTheme.notionBlue.withValues(alpha: 0.25),
              ),
            ),
            child: Text(
              meta.software,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: AppTheme.notionBlue,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              widget.fileName ?? '图像元数据读取',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoal,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 20),
            color: AppTheme.graphite,
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildImagePreviewRow(ImageMetadataResult meta) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
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
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoal,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '模型: ${meta.model ?? '未知模型'}  ·  采样: ${meta.sampler ?? '默认'}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppTheme.graphite,
                  ),
                ),
                if (meta.seed != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    '种子: ${meta.seed}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.graphite,
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
    required String title,
    required IconData icon,
    required String content,
    required VoidCallback onCopy,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Icon(icon, size: 14, color: AppTheme.graphite),
                const SizedBox(width: 6),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.charcoal,
                  ),
                ),
              ],
            ),
            InkWell(
              onTap: onCopy,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppTheme.skyTint,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.copy_rounded,
                      size: 12,
                      color: AppTheme.notionBlue,
                    ),
                    SizedBox(width: 4),
                    Text(
                      '复制',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.notionBlue,
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
            color: AppTheme.surfaceMuted,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: AppTheme.border),
          ),
          child: SelectableText(
            content,
            style: const TextStyle(
              fontSize: 12,
              height: 1.45,
              color: AppTheme.charcoal,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCharacterPromptsSection(ImageMetadataResult meta) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(
          children: [
            Icon(Icons.people_alt_outlined, size: 14, color: AppTheme.graphite),
            SizedBox(width: 6),
            Text(
              '多角色提示词 (Character Prompts)',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.charcoal,
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
              color: AppTheme.surfaceMuted,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.skyTint,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: Text(
                    '角色 ${idx + 1}',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.notionBlue,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  prompt,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTheme.charcoal,
                  ),
                ),
                if (neg.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(
                    '负向: $neg',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: AppTheme.graphite,
                    ),
                  ),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildParametersGrid(ImageMetadataResult meta) {
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
        const Text(
          '生成参数',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: AppTheme.charcoal,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: items.map((item) {
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppTheme.surfaceMuted,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: AppTheme.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.label,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.graphite,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.value,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.charcoal,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildRawJsonCollapsible(String rawJson) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _showRawJson = !_showRawJson),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _showRawJson ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: AppTheme.graphite,
                  ),
                  const SizedBox(width: 6),
                  const Text(
                    '原始元数据 (Raw JSON / Text)',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.graphite,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 14),
                    visualDensity: VisualDensity.compact,
                    tooltip: '复制原始文本',
                    onPressed: () => _copyText(rawJson, '已复制原始元数据'),
                  ),
                ],
              ),
            ),
          ),
          if (_showRawJson) ...[
            const Divider(height: 1, color: AppTheme.border),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Container(
                color: AppTheme.surfaceMuted,
                padding: const EdgeInsets.all(10),
                child: SingleChildScrollView(
                  child: SelectableText(
                    rawJson,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: AppTheme.charcoal,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBottomActionBar(ImageMetadataResult meta) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            style: TextButton.styleFrom(foregroundColor: AppTheme.graphite),
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
                foregroundColor: AppTheme.charcoal,
                backgroundColor: AppTheme.pureWhite,
                side: const BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                ),
              ),
              onPressed: _blindExtracting ? null : _extractBlindWatermark,
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: const Text('作为参考图导入'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.charcoal,
                backgroundColor: AppTheme.pureWhite,
                side: const BorderSide(color: AppTheme.border),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(AppTheme.radiusButton),
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
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppTheme.radiusButton),
              ),
            ),
            onPressed: () {
              widget.viewModel.applyMetadataToWorkbench(meta);
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
    );
  }
}

class _ParamItem {
  final String label;
  final String value;
  const _ParamItem(this.label, this.value);
}
