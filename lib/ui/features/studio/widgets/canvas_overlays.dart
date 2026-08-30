import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import 'image_canvas_actions.dart';

/// 画板浮层通用白底徽章装饰 (Notion 蓝白卡片)
BoxDecoration canvasBadgeDecoration() => BoxDecoration(
  color: AppTheme.pureWhite,
  borderRadius: BorderRadius.circular(8),
  border: Border.all(color: AppTheme.border),
  boxShadow: [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.05),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ],
);

/// 左下角悬浮参数徽章：尺寸 + 种子 (种子点击复制)
class CanvasParamBadges extends StatelessWidget {
  final NaiGeneratedImage image;

  const CanvasParamBadges({super.key, required this.image});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 尺寸徽章
        Container(
          height: 38,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: canvasBadgeDecoration(),
          alignment: Alignment.center,
          child: Text(
            '${image.params.width}  ×  ${image.params.height}',
            style: const TextStyle(
              fontSize: 13,
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
        ),
        const SizedBox(width: 8),

        // 种子徽章 (点击可直接复制)
        Tooltip(
          message: '点击复制随机种子',
          child: InkWell(
            onTap: () =>
                copyTextWithSnackBar(context, '${image.seed}', '已复制种子到剪贴板'),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: canvasBadgeDecoration(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.eco_rounded,
                    size: 16,
                    color: AppTheme.notionBlue,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${image.seed}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onViewLatest,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: AppTheme.notionBlue.withValues(alpha: 0.5),
              width: 1.2,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.notionBlue.withValues(alpha: 0.12),
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
                decoration: const BoxDecoration(
                  color: AppTheme.skyTint,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_upward_rounded,
                  size: 13,
                  color: AppTheme.notionBlue,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '已生成新图片 · 点击查看最新',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              InkWell(
                onTap: onDismiss,
                borderRadius: BorderRadius.circular(10),
                child: const Padding(
                  padding: EdgeInsets.all(2.0),
                  child: Icon(
                    Icons.close_rounded,
                    size: 14,
                    color: AppTheme.graphite,
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
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          decoration: canvasBadgeDecoration(),
          child: const Icon(
            Icons.history_rounded,
            size: 20,
            color: AppTheme.textPrimary,
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.palette_outlined,
            size: 54,
            color: AppTheme.stone.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 14),
          const Text(
            '画板暂无图像',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            '可在左侧配置参数后生成图片，历史记录将以垂直图像流展示',
            style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}
