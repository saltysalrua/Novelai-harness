import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
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
  final l10n = context.l10n;
  final label = raw ? l10n.canvasCopiedRawImage : l10n.canvasCopiedImage;
  showCanvasSnackBar(context, success ? label : l10n.canvasCopyImageFailed);
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
    showCanvasSnackBar(
      context,
      context.l10n.canvasImportedReference(file.name),
    );
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
  final l10n = context.l10n;

  showStudioContextMenu(
    context,
    position: position,
    actions: [
      ContextMenuItem(
        icon: Icons.edit_note_rounded,
        label: image.annotations.isEmpty
            ? l10n.canvasActionAddAnnotation
            : l10n.canvasActionViewAnnotation(image.annotations.length),
        onTap: () =>
            viewModel.setAnnotatingImage(true, targetImageId: image.id),
      ),
      ContextMenuItem(
        icon: Icons.auto_fix_high_outlined,
        label: l10n.canvasActionSendToInpaint,
        onTap: () => viewModel.sendImageToInpaint(image),
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.zoom_in_rounded,
        label: l10n.canvasActionUpscale,
        onTap: isGenerating ? null : () => viewModel.upscaleSelected(),
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.content_copy_rounded,
        label: l10n.canvasActionCopyImage,
        onTap: () =>
            copyImageToClipboard(context, viewModel, image, raw: false),
      ),
      if (showCopyRaw)
        ContextMenuItem(
          icon: Icons.image_outlined,
          label: l10n.canvasActionCopyRawImage,
          onTap: () =>
              copyImageToClipboard(context, viewModel, image, raw: true),
        ),
      ContextMenuItem(
        icon: Icons.copy_rounded,
        label: l10n.canvasActionCopyPrompt,
        onTap: () => copyTextWithSnackBar(
          context,
          image.params.finalPrompt,
          l10n.canvasCopiedPrompt,
        ),
      ),
      ContextMenuItem(
        icon: Icons.sync_rounded,
        label: l10n.canvasActionReuseParams,
        onTap: () {
          viewModel.updateParams(image.params);
          showCanvasSnackBar(context, l10n.canvasAppliedParams);
        },
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.fullscreen_rounded,
        label: l10n.canvasActionViewLightbox,
        onTap: () => showImageLightbox(context, image),
      ),
      const ContextMenuDivider(),
      ContextMenuItem(
        icon: Icons.delete_outline_rounded,
        label: l10n.canvasActionDeleteFromHistory,
        isDestructive: true,
        onTap: () async {
          await viewModel.deleteImageFromHistory(image.id);
          if (context.mounted) {
            showCanvasSnackBar(context, l10n.canvasDeletedFromHistory);
          }
        },
      ),
      ContextMenuItem(
        icon: Icons.delete_sweep_outlined,
        label: l10n.canvasActionClearHistory,
        isDestructive: true,
        onTap: () async {
          final ok = await _confirmClearHistory(context, viewModel);
          if (ok != true) return;
          await viewModel.clearImageHistory();
          if (context.mounted) {
            showCanvasSnackBar(context, l10n.canvasClearedHistory);
          }
        },
      ),
    ],
  );
}

/// 清空全部历史前的确认弹窗 (删除本地文件且无法撤销)
Future<bool?> _confirmClearHistory(
  BuildContext context,
  StudioViewModel viewModel,
) {
  final l10n = context.l10n;
  return showAppConfirmDialog(
    context,
    title: l10n.canvasActionClearHistory,
    message: viewModel.autoSaveImages
        ? l10n.canvasClearHistoryAutoSaveMessage(viewModel.gallery.length)
        : l10n.canvasClearHistoryManualSaveMessage(viewModel.gallery.length),
    confirmLabel: l10n.clear,
    cancelLabel: l10n.cancel,
    isDestructive: true,
  );
}
