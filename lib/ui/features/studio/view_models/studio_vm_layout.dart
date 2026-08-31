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

  // 提示词输入框高度 Getters
  double get promptHeightStacked => _promptHeightStacked;
  double get negativePromptHeightStacked => _negativePromptHeightStacked;
  double get promptHeightTabbed => _promptHeightTabbed;
  double get negativePromptHeightTabbed => _negativePromptHeightTabbed;
  double get prefixPromptHeight => _prefixPromptHeight;
  double get suffixPromptHeight => _suffixPromptHeight;
  double get characterPromptHeight => _characterPromptHeight;
  double get characterNegativePromptHeight => _characterNegativePromptHeight;

  /// 提示词输入框高度防抖落盘
  void _schedulePromptHeightsSave() {
    _promptHeightsSaveTimer?.cancel();
    _promptHeightsSaveTimer = Timer(const Duration(milliseconds: 300), () {
      _configService.savePromptFieldHeights(
        promptStacked: _promptHeightStacked,
        negativeStacked: _negativePromptHeightStacked,
        promptTabbed: _promptHeightTabbed,
        negativeTabbed: _negativePromptHeightTabbed,
        prefix: _prefixPromptHeight,
        suffix: _suffixPromptHeight,
        characterPrompt: _characterPromptHeight,
        characterNegative: _characterNegativePromptHeight,
      );
    });
  }

  void updatePromptHeightStacked(double height) {
    if ((_promptHeightStacked - height).abs() < 0.5) return;
    _promptHeightStacked = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

  void updateNegativePromptHeightStacked(double height) {
    if ((_negativePromptHeightStacked - height).abs() < 0.5) return;
    _negativePromptHeightStacked = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

  void updatePromptHeightTabbed(double height) {
    if ((_promptHeightTabbed - height).abs() < 0.5) return;
    _promptHeightTabbed = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

  void updateNegativePromptHeightTabbed(double height) {
    if ((_negativePromptHeightTabbed - height).abs() < 0.5) return;
    _negativePromptHeightTabbed = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

  void updatePrefixPromptHeight(double height) {
    if ((_prefixPromptHeight - height).abs() < 0.5) return;
    _prefixPromptHeight = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

  void updateSuffixPromptHeight(double height) {
    if ((_suffixPromptHeight - height).abs() < 0.5) return;
    _suffixPromptHeight = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

  void updateCharacterPromptHeight(double height) {
    if ((_characterPromptHeight - height).abs() < 0.5) return;
    _characterPromptHeight = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

  void updateCharacterNegativePromptHeight(double height) {
    if ((_characterNegativePromptHeight - height).abs() < 0.5) return;
    _characterNegativePromptHeight = height;
    _schedulePromptHeightsSave();
    notifyListeners();
  }

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
    final heightsTimer = _promptHeightsSaveTimer;
    if (heightsTimer != null && heightsTimer.isActive) {
      heightsTimer.cancel();
      await _configService.savePromptFieldHeights(
        promptStacked: _promptHeightStacked,
        negativeStacked: _negativePromptHeightStacked,
        promptTabbed: _promptHeightTabbed,
        negativeTabbed: _negativePromptHeightTabbed,
        prefix: _prefixPromptHeight,
        suffix: _suffixPromptHeight,
        characterPrompt: _characterPromptHeight,
        characterNegative: _characterNegativePromptHeight,
      );
    }
    final draftTimer = _chatDraftSaveTimer;
    if (draftTimer != null && draftTimer.isActive) {
      draftTimer.cancel();
      await _configService.saveChatDraft(_chatDraft);
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
