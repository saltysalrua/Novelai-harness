import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/widgets/context_menu.dart';
import '../view_models/studio_view_model.dart';
import 'image_lightbox.dart';

/// 画板图片的安全纵横比 (宽高非法时回退 1:1)
double imageAspectRatioOf(NaiGenerationParams params) =>
    (params.width > 0 && params.height > 0)
    ? params.width / params.height
    : 1.0;

/// 画板统一的 1 秒轻提示
void showCanvasSnackBar(BuildContext context, String message) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: kCanvasSnackBarDuration),
  );
}

/// 复制文本到剪贴板并弹 1 秒轻提示
void copyTextWithSnackBar(BuildContext context, String text, String message) {
  Clipboard.setData(ClipboardData(text: text));
  showCanvasSnackBar(context, message);
}

const Duration kCanvasSnackBarDuration = Duration(seconds: 1);

/// 复制图像位图到系统剪贴板 (可直接粘贴到聊天窗、画图等应用)
Future<void> copyImageToClipboard(
  BuildContext context,
  NaiGeneratedImage image,
) async {
  var success = false;
  try {
    await Pasteboard.writeImage(image.uint8Bytes);
    success = true;
  } catch (_) {
    success = false;
  }
  if (!context.mounted) return;
  showCanvasSnackBar(context, success ? '已复制图像到剪贴板' : '复制图像失败');
}

/// 图片右键菜单：超分放大 (2x / 4x)、复制图像、复制提示词、复用参数与查看大图
void showImageContextMenu(
  BuildContext context, {
  required Offset position,
  required StudioViewModel viewModel,
  required NaiGeneratedImage image,
}) {
  if (viewModel.selectedImage?.id != image.id) {
    viewModel.selectImage(image);
  }

  final isGenerating = viewModel.isGenerating;

  showStudioContextMenu(
    context,
    position: position,
    actions: [
      ContextMenuItem(
        icon: Icons.zoom_in_rounded,
        label: '2x 放大',
        onTap: isGenerating ? null : () => viewModel.upscaleSelected(scale: 2),
      ),
      ContextMenuItem(
        icon: Icons.zoom_out_map_rounded,
        label: '4x 放大',
        onTap: isGenerating ? null : () => viewModel.upscaleSelected(scale: 4),
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.content_copy_rounded,
        label: '复制图像',
        onTap: () => copyImageToClipboard(context, image),
      ),
      ContextMenuItem(
        icon: Icons.copy_rounded,
        label: '复制提示词',
        onTap: () => copyTextWithSnackBar(
          context,
          image.params.finalPrompt,
          '已复制提示词到剪贴板',
        ),
      ),
      ContextMenuItem(
        icon: Icons.sync_rounded,
        label: '复用参数',
        onTap: () {
          viewModel.updateParams(image.params);
          showCanvasSnackBar(context, '已应用该图参数至左侧面板');
        },
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.fullscreen_rounded,
        label: '查看大图',
        onTap: () => showImageLightbox(context, image),
      ),
    ],
  );
}
