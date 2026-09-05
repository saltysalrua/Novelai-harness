import 'dart:async';

import 'package:flutter/foundation.dart';

/// 流式对话瞬态文本控制器 (阶段 2 性能治理)。
///
/// 思考链 / 正文增量与重试提示寄生在此独立轻量控制器上，由视图
/// (对话流式气泡) 通过 ListenableBuilder 局部监听刷新：
/// 流式期间 StudioViewModel 不再为每个增量执行 notifyListeners()，
/// 主工作台、参数面板与画板零重绘。阶段 4 拆解领域 Controller 时
/// 可直接整体迁移，无 ViewModel 寄生成本。
class StreamingTextController extends ChangeNotifier {
  String _thoughts = '';
  String _content = '';
  String? _notice;

  /// 增量批量刷新计时器 (40ms 窗口合并连续 token 增量)
  Timer? _flushTimer;
  bool _dirty = false;

  /// 当前思考链累积文本
  String get thoughts => _thoughts;

  /// 当前正文累积文本
  String get content => _content;

  /// 流式请求自动重试提示 (null 或空串表示不展示)
  String? get notice => _notice;

  /// 是否存在待展示的重试提示
  bool get hasNotice => _notice != null && _notice!.isNotEmpty;

  /// 追加思考链增量 (并入 40ms 批量刷新窗口)
  void appendThoughts(String delta) {
    if (delta.isEmpty) return;
    _thoughts += delta;
    _dirty = true;
    _scheduleFlush();
  }

  /// 追加正文增量 (并入 40ms 批量刷新窗口)
  void appendContent(String delta) {
    if (delta.isEmpty) return;
    _content += delta;
    _dirty = true;
    _scheduleFlush();
  }

  /// 设置/清除重试提示 (低频但需即时可见，立即刷新局部监听者)
  void setNotice(String? notice) {
    _notice = notice;
    _notifyNow();
  }

  /// 清空全部流式文本并立即刷新 (新一轮开始 / 流结束 / 强制中止)
  void reset() {
    _thoughts = '';
    _content = '';
    _notice = null;
    _notifyNow();
  }

  void _scheduleFlush() {
    final timer = _flushTimer;
    if (timer != null && timer.isActive) return;
    _flushTimer = Timer(const Duration(milliseconds: 40), _onFlush);
  }

  void _onFlush() {
    _flushTimer = null;
    if (!_dirty) return;
    _dirty = false;
    notifyListeners();
  }

  /// 取消挂起的批量刷新，立即通知局部监听者
  void _notifyNow() {
    _flushTimer?.cancel();
    _flushTimer = null;
    _dirty = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _flushTimer?.cancel();
    _flushTimer = null;
    super.dispose();
  }
}

/// 生图 / 修复实时进度控制器 (阶段 2 性能治理)。
///
/// 去噪预览帧与步数进度只通知局部监听者 (画板占位卡、历史缩略图、
/// 生成坞按钮文案)，中间帧不触发 StudioViewModel.notifyListeners()。
/// 生成开始/结束等结构变化仍由 ViewModel 全局通知。
class LiveProgressController extends ChangeNotifier {
  Uint8List? _previewBytes;
  int _currentStep = 0;
  int _totalSteps = 28;
  double _progress = 0.0;
  DateTime? _startTime;

  /// 当前去噪预览帧字节 (null 表示尚无预览，展示转圈占位)
  Uint8List? get previewBytes => _previewBytes;

  /// 当前已完成步数
  int get currentStep => _currentStep;

  /// 总步数
  int get totalSteps => _totalSteps;

  /// 总进度 0.0 ~ 1.0
  double get progress => _progress;

  /// 本次生成的发起时刻
  DateTime? get startTime => _startTime;

  /// 生成开始：重置进度状态 (结构变化，调用方需自行 notifyListeners)
  void begin(int totalSteps, DateTime startTime) {
    _previewBytes = null;
    _currentStep = 0;
    _totalSteps = totalSteps;
    _progress = 0.0;
    _startTime = startTime;
    notifyListeners();
  }

  /// 中间去噪帧：仅通知局部监听者，绝不触碰 ViewModel
  void updateFrame({
    Uint8List? previewBytes,
    required int currentStep,
    required int totalSteps,
    double? progress,
  }) {
    _previewBytes = previewBytes;
    _currentStep = currentStep;
    _totalSteps = totalSteps;
    _progress =
        progress ??
        (totalSteps > 0 ? (currentStep / totalSteps).clamp(0.0, 0.99) : 0.0);
    notifyListeners();
  }

  /// 正常完成：清空预览并置满进度 (结构变化，调用方需自行 notifyListeners)
  void complete() {
    _previewBytes = null;
    _progress = 1.0;
    notifyListeners();
  }

  /// 终止/收尾：清空预览与步数 (结构变化，调用方需自行 notifyListeners)
  void clear() {
    _previewBytes = null;
    _currentStep = 0;
    _progress = 0.0;
    notifyListeners();
  }
}
