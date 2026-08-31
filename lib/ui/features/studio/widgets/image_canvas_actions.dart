import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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

/// 复制图像位图到系统剪贴板 (根据全局设置决定是否去元数据/加水印，raw=true 时强制复制纯净原图)
Future<void> copyImageToClipboard(
  BuildContext context,
  StudioViewModel viewModel,
  NaiGeneratedImage image, {
  bool raw = false,
}) async {
  var success = false;
  try {
    final bytes = await viewModel.getExportImageBytes(image, raw: raw);

    if (raw) {
      // 原图复制走临时文件路径，保留完整 PNG Chunks 元数据 (位图化会丢失元数据)
      final tempDir = await getTemporaryDirectory();
      final tempFile = File(
        p.join(
          tempDir.path,
          'nai_clipboard_raw_${DateTime.now().millisecondsSinceEpoch}.png',
        ),
      );
      await tempFile.writeAsBytes(bytes);
      await Pasteboard.writeFiles([tempFile.path]);
    } else {
      await Pasteboard.writeImage(bytes);
    }
    success = true;
  } catch (_) {
    success = false;
  }
  if (!context.mounted) return;
  final label = raw ? '已复制原图像到剪贴板' : '已复制图像到剪贴板';
  showCanvasSnackBar(context, success ? label : '复制图像失败');
}

/// 弹出文件选择器导入外部参考图到大画布 (画板、批注画布、批注历史条共用)
Future<void> pickAndImportReferenceImage(
  BuildContext context,
  StudioViewModel viewModel, {
  Offset? dropPosition,
}) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return;
  final file = result.files.first;
  final bytes = file.bytes;
  if (bytes == null || bytes.isEmpty) return;

  await viewModel.importReferenceImageFromBytes(
    bytes,
    fileName: file.name,
    dropPosition: dropPosition,
  );
  if (context.mounted) {
    showCanvasSnackBar(context, '已导入参考图: ${file.name}');
  }
}

/// 图片右键菜单：超分放大、复制图像、复制原图像、复制提示词、复用参数与查看大图
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
  final showCopyRaw = viewModel.stripMetadata || viewModel.enableWatermark;

  showStudioContextMenu(
    context,
    position: position,
    actions: [
      ContextMenuItem(
        icon: Icons.edit_note_rounded,
        label: image.annotations.isEmpty
            ? '添加批注'
            : '查看批注 (${image.annotations.length})',
        onTap: () =>
            viewModel.setAnnotatingImage(true, targetImageId: image.id),
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.zoom_in_rounded,
        label: '超分放大',
        onTap: isGenerating ? null : () => viewModel.upscaleSelected(),
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.content_copy_rounded,
        label: '复制图像',
        onTap: () =>
            copyImageToClipboard(context, viewModel, image, raw: false),
      ),
      if (showCopyRaw)
        ContextMenuItem(
          icon: Icons.image_outlined,
          label: '复制原图像',
          onTap: () =>
              copyImageToClipboard(context, viewModel, image, raw: true),
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
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.delete_outline_rounded,
        label: '从历史记录删除',
        isDestructive: true,
        onTap: () async {
          await viewModel.deleteImageFromHistory(image.id);
          if (context.mounted) {
            showCanvasSnackBar(context, '已从历史记录删除图片');
          }
        },
      ),
    ],
  );
}
