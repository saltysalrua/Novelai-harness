import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// 可拖拽三栏自适应分割容器
class ResizableThreeSplitView extends StatefulWidget {
  final Widget leftChild;
  final Widget centerChild;
  final Widget rightChild;
  final double initialLeftWidth;
  final double initialRightWidth;
  final double minLeftWidth;
  final double maxLeftWidth;
  final double minCenterWidth;
  final double minRightWidth;
  final double maxRightWidth;

  const ResizableThreeSplitView({
    super.key,
    required this.leftChild,
    required this.centerChild,
    required this.rightChild,
    this.initialLeftWidth = 320.0,
    this.initialRightWidth = 380.0,
    this.minLeftWidth = 240.0,
    this.maxLeftWidth = 480.0,
    this.minCenterWidth = 300.0,
    this.minRightWidth = 280.0,
    this.maxRightWidth = 560.0,
  });

  @override
  State<ResizableThreeSplitView> createState() =>
      _ResizableThreeSplitViewState();
}

class _ResizableThreeSplitViewState extends State<ResizableThreeSplitView> {
  late double _leftWidth;
  late double _rightWidth;
  bool _isDraggingLeft = false;
  bool _isDraggingRight = false;

  @override
  void initState() {
    super.initState();
    _leftWidth = widget.initialLeftWidth;
    _rightWidth = widget.initialRightWidth;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;

        // 小屏幕自适应处理（宽度低于 800 时，降级为卡片自适应平铺或 Tab）
        if (totalWidth < 768) {
          return DefaultTabController(
            length: 3,
            child: Scaffold(
              backgroundColor: AppTheme.background,
              appBar: AppBar(
                backgroundColor: AppTheme.surface,
                toolbarHeight: 0,
                bottom: const TabBar(
                  tabs: [
                    Tab(text: '参数设置'),
                    Tab(text: '图片画板'),
                    Tab(text: 'AI 对话'),
                  ],
                  indicatorColor: AppTheme.primary,
                  labelColor: AppTheme.textPrimary,
                  unselectedLabelColor: AppTheme.textSecondary,
                ),
              ),
              body: TabBarView(
                children: [
                  Padding(padding: const EdgeInsets.all(8.0), child: widget.leftChild),
                  Padding(padding: const EdgeInsets.all(8.0), child: widget.centerChild),
                  Padding(padding: const EdgeInsets.all(8.0), child: widget.rightChild),
                ],
              ),
            ),
          );
        }

        // 桌面大屏：三栏自由拖拽分割模式
        // 计算中央区域可用宽度
        double availableCenter = totalWidth - _leftWidth - _rightWidth - 16; // 16 为两个分割条的宽度
        if (availableCenter < widget.minCenterWidth) {
          // 动态按比例压缩左右两栏
          final excess = widget.minCenterWidth - availableCenter;
          _leftWidth = (_leftWidth - excess / 2).clamp(widget.minLeftWidth, widget.maxLeftWidth);
          _rightWidth = (_rightWidth - excess / 2).clamp(widget.minRightWidth, widget.maxRightWidth);
          availableCenter = (totalWidth - _leftWidth - _rightWidth - 16).clamp(0.0, totalWidth);
        }

        return Container(
          color: AppTheme.background,
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 左侧面板 (参数设置)
              SizedBox(
                width: _leftWidth,
                child: widget.leftChild,
              ),

              // 左侧拖拽分割条
              _buildDivider(
                isDragging: _isDraggingLeft,
                onHorizontalDragStart: () => setState(() => _isDraggingLeft = true),
                onHorizontalDragEnd: () => setState(() => _isDraggingLeft = false),
                onHorizontalDragUpdate: (delta) {
                  setState(() {
                    _leftWidth = (_leftWidth + delta).clamp(
                      widget.minLeftWidth,
                      (totalWidth - _rightWidth - widget.minCenterWidth - 16).clamp(widget.minLeftWidth, widget.maxLeftWidth),
                    );
                  });
                },
              ),

              // 2. 中间面板 (图片画板)
              Expanded(
                child: widget.centerChild,
              ),

              // 右侧拖拽分割条
              _buildDivider(
                isDragging: _isDraggingRight,
                onHorizontalDragStart: () => setState(() => _isDraggingRight = true),
                onHorizontalDragEnd: () => setState(() => _isDraggingRight = false),
                onHorizontalDragUpdate: (delta) {
                  setState(() {
                    _rightWidth = (_rightWidth - delta).clamp(
                      widget.minRightWidth,
                      (totalWidth - _leftWidth - widget.minCenterWidth - 16).clamp(widget.minRightWidth, widget.maxRightWidth),
                    );
                  });
                },
              ),

              // 3. 右侧面板 (AI 对话框)
              SizedBox(
                width: _rightWidth,
                child: widget.rightChild,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDivider({
    required bool isDragging,
    required VoidCallback onHorizontalDragStart,
    required VoidCallback onHorizontalDragEnd,
    required ValueChanged<double> onHorizontalDragUpdate,
  }) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: (_) => onHorizontalDragStart(),
        onHorizontalDragEnd: (_) => onHorizontalDragEnd(),
        onHorizontalDragUpdate: (details) =>
            onHorizontalDragUpdate(details.primaryDelta ?? 0),
        child: Container(
          width: 8,
          alignment: Alignment.center,
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: isDragging ? 2 : 0,
            height: double.infinity,
            color: isDragging ? AppTheme.primary : Colors.transparent,
          ),
        ),
      ),
    );
  }
}
