part of 'studio_view_model.dart';

/// 页面布局持久化 (分割线宽度防抖落盘，页签状态即时落盘)
mixin _StudioLayoutMixin on _StudioCore {
  double get splitLeftWidth => _splitLeftWidth;
  double get splitRightWidth => _splitRightWidth;
  StudioSidebarTab get activeSidebarTab => _activeSidebarTab;
  bool get promptTabbedMode => _promptTabbedMode;
  int get promptActiveTab => _promptActiveTab;
  int get deckActiveTab => _deckActiveTab;
  bool get canvasHistoryOpen => _canvasHistoryOpen;

  /// 拖动分割线时指针每个帧都会回调：内存值即时更新，落盘防抖 300ms 节流，
  /// 避免一次拖拽触发几十次 SharedPreferences 写盘
  void updateSplitWidths(double left, double right) {
    if ((_splitLeftWidth - left).abs() < 0.5 &&
        (_splitRightWidth - right).abs() < 0.5) {
      return;
    }
    _splitLeftWidth = left;
    _splitRightWidth = right;
    _splitWidthSaveTimer?.cancel();
    _splitWidthSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _configService.saveSplitWidths(_splitLeftWidth, _splitRightWidth);
    });
  }

  /// 立即落盘尚未到期的防抖保存 (测试与收尾共用)
  Future<void> flushPendingLayoutSave() async {
    final timer = _splitWidthSaveTimer;
    if (timer != null && timer.isActive) {
      timer.cancel();
      await _configService.saveSplitWidths(_splitLeftWidth, _splitRightWidth);
    }
  }

  void setActiveSidebarTab(StudioSidebarTab tab) {
    if (_activeSidebarTab == tab) return;
    _activeSidebarTab = tab;
    _configService.saveSidebarActiveTab(tab.name);
    notifyListeners();
  }

  void setPromptTabbedMode(bool isTabbed) {
    if (_promptTabbedMode == isTabbed) return;
    _promptTabbedMode = isTabbed;
    _configService.savePromptTabbedMode(isTabbed);
    notifyListeners();
  }

  void setPromptActiveTab(int tab) {
    if (_promptActiveTab == tab) return;
    _promptActiveTab = tab;
    _configService.savePromptActiveTab(tab);
    notifyListeners();
  }

  void setDeckActiveTab(int tab) {
    if (_deckActiveTab == tab) return;
    _deckActiveTab = tab;
    _configService.saveDeckActiveTab(tab);
    notifyListeners();
  }

  void setCanvasHistoryOpen(bool isOpen) {
    if (_canvasHistoryOpen == isOpen) return;
    _canvasHistoryOpen = isOpen;
    _configService.saveCanvasHistoryOpen(isOpen);
    notifyListeners();
  }
}
