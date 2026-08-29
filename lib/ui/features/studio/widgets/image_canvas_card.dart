import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';

class ImageCanvasCard extends StatelessWidget {
  final StudioViewModel viewModel;

  const ImageCanvasCard({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final selectedImage = viewModel.selectedImage;
    final gallery = viewModel.gallery;

    return Card(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部标题与元数据条
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: AppTheme.border)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.image_outlined, size: 16, color: AppTheme.primaryLight),
                    const SizedBox(width: 6),
                    const Text(
                      '图像画板',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (selectedImage != null) ...[
                      const SizedBox(width: 10),
                      Text(
                        '${selectedImage.params.width}x${selectedImage.params.height} · ${selectedImage.params.model.label} · 种子: ${selectedImage.seed}',
                        style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                      ),
                    ],
                  ],
                ),
                if (selectedImage != null)
                  Text(
                    DateFormat('HH:mm:ss').format(selectedImage.createdAt),
                    style: const TextStyle(fontSize: 11, color: AppTheme.textMuted),
                  ),
              ],
            ),
          ),

          // 主图像画板显示区域
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                    child: selectedImage != null
                        ? InteractiveViewer(
                            minScale: 0.2,
                            maxScale: 5.0,
                            child: Center(
                              child: Image.memory(
                                Uint8List.fromList(selectedImage.bytes),
                                fit: BoxFit.contain,
                              ),
                            ),
                          )
                        : _buildEmptyState(),
                  ),
                ),

                // 悬浮工具栏 (放大 / 复制 / 复用)
                if (selectedImage != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppTheme.surface.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppTheme.border),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildActionButton(
                            icon: Icons.zoom_in,
                            label: '2x 放大',
                            tooltip: '超分放大 2 倍',
                            onTap: viewModel.isGenerating
                                ? null
                                : () => viewModel.upscaleSelected(scale: 2),
                          ),
                          const SizedBox(width: 4),
                          _buildActionButton(
                            icon: Icons.zoom_out_map,
                            label: '4x 放大',
                            tooltip: '超分放大 4 倍',
                            onTap: viewModel.isGenerating
                                ? null
                                : () => viewModel.upscaleSelected(scale: 4),
                          ),
                          const SizedBox(width: 4),
                          _buildActionButton(
                            icon: Icons.copy,
                            label: '复制词',
                            tooltip: '复制完整正向提示词',
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: selectedImage.params.finalPrompt),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已复制提示词到剪贴板'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                          const SizedBox(width: 4),
                          _buildActionButton(
                            icon: Icons.sync,
                            label: '复用参数',
                            tooltip: '将此图参数同步到左侧设置面板',
                            onTap: () {
                              viewModel.updateParams(selectedImage.params);
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('已将该图参数应用至左侧面板'),
                                  duration: Duration(seconds: 1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                  ),

                // 正在生图遮罩
                if (viewModel.isGenerating)
                  Positioned.fill(
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.6),
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primary),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              viewModel.statusMessage ?? '正在生成中...',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // 底部历史图片轮播卷轴
          Container(
            height: 90,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: const BoxDecoration(
              color: AppTheme.surfaceElevated,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: gallery.isEmpty
                ? const Center(
                    child: Text(
                      '生成历史记录将展示在此处',
                      style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: gallery.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final item = gallery[index];
                      final isSelected = selectedImage?.id == item.id;
                      return GestureDetector(
                        onTap: () => viewModel.selectImage(item),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          width: 74,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                              color: isSelected ? AppTheme.primary : AppTheme.border,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.memory(
                                Uint8List.fromList(item.bytes),
                                fit: BoxFit.cover,
                              ),
                              Positioned(
                                bottom: 0,
                                left: 0,
                                right: 0,
                                child: Container(
                                  color: Colors.black.withValues(alpha: 0.6),
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  child: Text(
                                    '${item.params.width}x${item.params.height}',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.palette_outlined, size: 48, color: AppTheme.textMuted.withValues(alpha: 0.6)),
          const SizedBox(height: 12),
          const Text(
            '画板暂无图像',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '可在右侧与 AI 对话协助构思，或在左侧设置后点击直接生图',
            style: TextStyle(fontSize: 12, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required String tooltip,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: AppTheme.textPrimary),
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: AppTheme.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}
