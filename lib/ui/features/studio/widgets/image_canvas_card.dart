import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'canvas_history_sidebar.dart';
import 'canvas_overlays.dart';
import 'character_position_canvas_view.dart';
import 'freeform_annotation_board.dart';
import 'image_canvas_actions.dart';
import 'image_stream_view.dart';

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

  Future<void> _handleCanvasPaste() async {
    final imageBytes = await Pasteboard.image;
    if (imageBytes != null && imageBytes.isNotEmpty) {
      await widget.viewModel.importReferenceImageFromBytes(imageBytes);
      if (mounted) showCanvasSnackBar(context, '已粘贴导入参考图并进入批注模式');
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    final gallery = viewModel.gallery;
    final isGenerating = viewModel.isGenerating;
    final isEditingPositions = viewModel.isEditingCharacterPositions;
    final isAnnotating = viewModel.isAnnotatingImage;
    final selectedImage =
        viewModel.selectedImage ?? (gallery.isNotEmpty ? gallery.first : null);

    final showEmptyState =
        gallery.isEmpty && !isGenerating && !isEditingPositions && !isAnnotating;

    return DropTarget(
      onDragEntered: (_) => setState(() => _isDraggingOver = true),
      onDragExited: (_) => setState(() => _isDraggingOver = false),
      onDragDone: (details) async {
        setState(() => _isDraggingOver = false);
        for (final file in details.files) {
          final bytes = await file.readAsBytes();
          if (bytes.isNotEmpty) {
            await viewModel.importReferenceImageFromBytes(
              bytes,
              fileName: file.name,
            );
            if (context.mounted) {
              showCanvasSnackBar(context, '已导入参考图: ${file.name}');
            }
            break;
          }
        }
      },
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyV, control: true):
              _handleCanvasPaste,
        },
        child: Focus(
          autofocus: false,
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
                        // 1.1 主画布：批注模式下为自由大画布 (Freeform Infinite Board)，普通模式下为垂直图像流
                        Expanded(
                          child: isAnnotating
                              ? FreeformAnnotationBoard(viewModel: viewModel)
                              : (showEmptyState
                                  ? const CanvasEmptyState()
                                  : ImageStreamView(
                                      viewModel: viewModel,
                                      controller: _stream,
                                    )),
                        ),

                        // 1.2 右侧垂直 History 缩略图侧边栏 (Notion 蓝白纯净卡片，非批注模式下展示)
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: (_isHistoryOpen && !isEditingPositions && !isAnnotating)
                              ? 120
                              : 0,
                          curve: Curves.easeInOut,
                          clipBehavior: Clip.antiAlias,
                          decoration: const BoxDecoration(
                            color: AppTheme.pureWhite,
                            border:
                                Border(left: BorderSide(color: AppTheme.border)),
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
                                  '松开鼠标导入为参考图并进行批注',
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
                      child:
                          CanvasPositionFloatingControls(viewModel: viewModel),
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

                  // 5. 右上角浮动 History 展开按键 (仅在收回状态且非编辑/非批注模式时显示)
                  if (!_isHistoryOpen && !isEditingPositions && !isAnnotating)
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
        ),
      ),
    );
  }
}
