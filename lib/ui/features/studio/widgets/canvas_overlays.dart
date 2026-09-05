import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_colors_extension.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../view_models/studio_view_model.dart';
import 'image_canvas_actions.dart';

/// 画板浮层通用白底徽章装饰 (Notion 蓝白卡片，支持 context 语义色与无参回退)
BoxDecoration canvasBadgeDecoration([BuildContext? context]) {
  final bg = context != null
      ? context.colors.cardBackground
      : AppColorsExtension.light.cardBackground;
  final border = context != null
      ? context.colors.borderDefault
      : AppColorsExtension.light.borderDefault;
  final shadows = context != null
      ? context.shadowSubtle
      : [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ];

  return BoxDecoration(
    color: bg,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: border),
    boxShadow: shadows,
  );
}

/// 左下角悬浮参数徽章：尺寸 + 种子 (种子点击复制) + 批注按钮
class CanvasParamBadges extends StatelessWidget {
  final NaiGeneratedImage image;
  final StudioViewModel? viewModel;

  const CanvasParamBadges({super.key, required this.image, this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 尺寸徽章
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: canvasBadgeDecoration(context),
          alignment: Alignment.center,
          child: Text(
            '${image.params.width}  ×  ${image.params.height}',
            style: TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: colors.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 种子徽章 (点击可直接复制，非导入参考图时展示)
        if (!image.isImportedReference) ...[
          Tooltip(
            message: '点击复制随机种子',
            child: InkWell(
              onTap: () =>
                  copyTextWithSnackBar(context, '${image.seed}', '已复制种子到剪贴板'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: canvasBadgeDecoration(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.eco_rounded, size: 16, color: colors.primary),
                    const SizedBox(width: 6),
                    Text(
                      '${image.seed}',
                      style: TextStyle(
                        fontSize: 13,
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],

        // 批注快捷按键
        if (viewModel != null)
          Tooltip(
            message: '进入画板批注模式 (圈选/锚点/整图)',
            child: InkWell(
              onTap: () =>
                  viewModel!.setAnnotatingImage(true, targetImageId: image.id),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Container(
                height: 38,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: canvasBadgeDecoration(context),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 17,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      image.annotations.isEmpty
                          ? '批注'
                          : '批注 (${image.annotations.length})',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 右下角手动保存按钮 (自动保存关闭且当前图为未保存缓存图时展示)
class CanvasSaveButton extends StatelessWidget {
  final StudioViewModel viewModel;

  const CanvasSaveButton({super.key, required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Tooltip(
      message: '保存当前图片到本地存储目录 (按导出设置处理元数据与水印)',
      child: InkWell(
        onTap: () async {
          final ok = await viewModel.saveCurrentImageToDisk();
          if (!context.mounted) return;
          showCanvasSnackBar(
            context,
            ok
                ? '已保存: ${viewModel.selectedImage?.localFilePath ?? ''}'
                : (viewModel.errorMessage ?? '保存失败，请检查存储目录设置'),
          );
        },
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: canvasBadgeDecoration(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.save_rounded, size: 17, color: colors.primary),
              const SizedBox(width: 6),
              Text(
                '保存图片',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 顶部浮动提示：有新图片生成且用户正在浏览历史时显示，点击回到最新
class UnseenLatestBanner extends StatelessWidget {
  final VoidCallback onViewLatest;
  final VoidCallback onDismiss;

  const UnseenLatestBanner({
    super.key,
    required this.onViewLatest,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onViewLatest,
        borderRadius: BorderRadius.circular(AppRadius.pill),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: colors.cardBackground,
            borderRadius: BorderRadius.circular(AppRadius.pill),
            border: Border.all(
              color: colors.primary.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.12),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: colors.primaryTint,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.arrow_upward_rounded,
                  size: 13,
                  color: colors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '已生成新图片 · 点击查看最新',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(2.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 右上角浮动 History 展开按键 (仅在侧边栏收回状态时显示)
class HistoryToggleButton extends StatelessWidget {
  final VoidCallback onTap;

  const HistoryToggleButton({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '展开历史记录',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          width: 38,
          height: 38,
          decoration: canvasBadgeDecoration(context),
          child: Icon(
            Icons.history_rounded,
            size: 20,
            color: context.colors.textPrimary,
          ),
        ),
      ),
    );
  }
}

/// 画板空状态占位 (无历史图且未在生成时展示)
class CanvasEmptyState extends StatelessWidget {
  const CanvasEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    return const AppEmptyState(
      icon: Icons.palette_outlined,
      title: '画板暂无图像',
      description: '可在左侧配置参数后生成图片，历史记录将以垂直图像流展示',
      iconSize: 54,
    );
  }
}
