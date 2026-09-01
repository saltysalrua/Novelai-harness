import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/services/image_metadata_service.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_history_sidebar.dart';
import 'canvas_overlays.dart';
import 'character_position_canvas_view.dart';
import 'freeform_annotation_board.dart';
import 'image_canvas_actions.dart';
import 'image_stream_view.dart';
import 'inpaint_canvas_overlay.dart';
import 'metadata_reader_dialog.dart';

/// 中间画板卡片：垂直图像流 + 可收起历史侧边栏 + 浮动徽章/横幅 + 角色位置交互画板 + 外部图片拖拽与粘贴导入
class ImageCanvasCard extends StatefulWidget {
  final StudioViewModel viewModel;

  const ImageCanvasCard({super.key, required this.viewModel});

  @override
  State<ImageCanvasCard> createState() => _ImageCanvasCardState();
}

class _ImageCanvasCardState extends State<ImageCanvasCard> {
  bool _isHistoryOpen = false;
  bool _isDraggingOver = false;
  late final CanvasStreamController _stream = CanvasStreamController();

  @override
  void initState() {
    super.initState();
    _isHistoryOpen = widget.viewModel.canvasHistoryOpen;
  }

  @override
  void didUpdateWidget(covariant ImageCanvasCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isHistoryOpen != widget.viewModel.canvasHistoryOpen) {
      _isHistoryOpen = widget.viewModel.canvasHistoryOpen;
    }
  }

  @override
  void dispose() {
    _stream.dispose();
    super.dispose();
  }

  void _viewLatest() {
    widget.viewModel.selectLatestImage();
    _stream.scrollToTop();
  }

  /// 有 AI 元数据则弹窗检查，无元数据则回退导入为参考图
  Future<void> _inspectOrImportImage(Uint8List bytes, String fileName) async {
    final metadata = await ImageMetadataService.parseMetadataAsync(bytes);
    if (metadata != null && metadata.hasData && mounted) {
      await MetadataReaderDialog.show(
        context,
        metadata: metadata,
        imageBytes: bytes,
        fileName: fileName,
        viewModel: widget.viewModel,
      );
    } else if (mounted) {
      await widget.viewModel.importReferenceImageFromBytes(
        bytes,
        fileName: fileName,
      );
      if (mounted) {
        showCanvasSnackBar(context, '已导入参考图: $fileName');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final gallery = viewModel.gallery;
    final isGenerating = viewModel.isGenerating;
    final isEditingPositions =
        viewModel.isEditingCharacterPositions ||
        viewModel.isEditingWatermarkPosition;
    final isAnnotating = viewModel.isAnnotatingImage;
    final isInpaintTab =
        viewModel.activeSidebarTab == StudioSidebarTab.inpaint &&
        !isEditingPositions;
    final selectedImage =
        viewModel.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);

    final showEmptyState =
        gallery.isEmpty &&
        !isGenerating &&
        !isEditingPositions &&
        !isAnnotating;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingOver = true),
      onDragExited: (_) => setState(() => _isDraggingOver = false),
      onDragDone: (details) async {
        setState(() => _isDraggingOver = false);
        for (final file in details.files) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            if (context.mounted) {
              await _inspectOrImportImage(bytes, file.name);
            }
            break;
          }
        }
      },
      // 注：全局 Ctrl+V 粘贴由 StudioView 的 HardwareKeyboard 处理器接管
      // (全局处理器先于焦点系统执行，此处不再挂 CallbackShortcuts，避免不可达死代码)
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: Container(
          color: AppTheme.paperWarmth, // Notion 统一暖纸本底色
          child: Stack(
            children: [
              // 1. 中间核心：上下滑动的垂直图像瀑布流 (单图居中 / 多图平滑瀑布流 / 临时位置占位卡片)
              Positioned.fill(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 1.1 主画布：批注模式下为自由大画布，修复页签下为独立修复
                    //     画板 (无滚动干扰、选区与源图严格对齐)，普通模式下为垂直图像流
                    Expanded(
                      child: isAnnotating
                          ? FreeformAnnotationBoard(viewModel: viewModel)
                          : (isInpaintTab
                                ? InpaintRepairCanvas(viewModel: viewModel)
                                : (showEmptyState
                                      ? const CanvasEmptyState()
                                      : ImageStreamView(
                                          viewModel: viewModel,
                                          controller: _stream,
                                        ))),
                    ),

                    // 1.2 右侧垂直 History 缩略图侧边栏 (Notion 蓝白纯净卡片；
                    //     修复页签下隐藏——修复画板底图不与历史侧栏联动，
                    //     换底图走图片右键「发送到修复」)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width:
                          (_isHistoryOpen &&
                              !isEditingPositions &&
                              !isAnnotating &&
                              !isInpaintTab)
                          ? 120
                          : 0,
                      curve: Curves.easeInOut,
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(
                        color: AppTheme.pureWhite,
                        border: Border(
                          left: BorderSide(color: AppTheme.border),
                        ),
                      ),
                      child: OverflowBox(
                        minWidth: 120,
                        maxWidth: 120,
                        alignment: Alignment.topRight,
                        child: CanvasHistorySidebar(
                          viewModel: viewModel,
                          selectedImage: selectedImage,
                          stream: _stream,
                          onClose: () {
                            setState(() => _isHistoryOpen = false);
                            viewModel.setCanvasHistoryOpen(false);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. 外部拖入高亮指示层
              if (_isDraggingOver)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppTheme.notionBlue.withValues(alpha: 0.12),
                      border: Border.all(
                        color: AppTheme.notionBlue,
                        width: 2.5,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppTheme.pureWhite,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: const [
                            BoxShadow(
                              color: Colors.black12,
                              blurRadius: 12,
                              offset: Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.file_download_outlined,
                              size: 20,
                              color: AppTheme.notionBlue,
                            ),
                            SizedBox(width: 8),
                            Text(
                              '松开鼠标导入图片 (自动识别生成元数据)',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

              // 3. 角色位置编辑模式下的悬浮浮动操作层
              if (isEditingPositions)
                Positioned.fill(
                  child: CanvasPositionFloatingControls(viewModel: viewModel),
                ),

              // 4. 左下角浮动参数徽章 (非编辑与非批注模式且选中图片时展示)
              if (selectedImage != null && !isEditingPositions && !isAnnotating)
                Positioned(
                  bottom: 18,
                  left: 18,
                  child: CanvasParamBadges(
                    image: selectedImage,
                    viewModel: viewModel,
                  ),
                ),

              // 4.5 右下角手动保存按钮 (当前图为未保存缓存图时展示；
              //     含自动保存开启后残留的旧未保存图，避免无处可存)
              if (selectedImage != null &&
                  selectedImage.isUnsaved &&
                  !isEditingPositions &&
                  !isAnnotating)
                Positioned(
                  bottom: 18,
                  right: 18,
                  child: CanvasSaveButton(viewModel: viewModel),
                ),

              // 5. 右上角浮动 History 展开按键 (仅在收回状态且非编辑/非批注/非修复页签时显示)
              if (!_isHistoryOpen &&
                  !isEditingPositions &&
                  !isAnnotating &&
                  !isInpaintTab)
                Positioned(
                  top: 14,
                  right: 14,
                  child: HistoryToggleButton(
                    onTap: () {
                      setState(() => _isHistoryOpen = true);
                      viewModel.setCanvasHistoryOpen(true);
                    },
                  ),
                ),

              // 6. 顶部浮动：新图片生成提示气泡
              if (viewModel.hasUnseenLatest &&
                  gallery.isNotEmpty &&
                  !isEditingPositions &&
                  !isAnnotating)
                Positioned(
                  top: 14,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: UnseenLatestBanner(
                      onViewLatest: _viewLatest,
                      onDismiss: viewModel.dismissUnseenBanner,
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
