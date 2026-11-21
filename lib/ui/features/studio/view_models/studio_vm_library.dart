part of 'studio_view_model.dart';

/// 词组合预设库分部 (Prompt Combo Library)
mixin _StudioLibraryMixin on _StudioCore {
  /// 当前词组合条目列表 (返回已冻结快照，避免每次读取分配新列表)
  @override
  List<PromptComboEntry> get promptLibraryEntries => _promptLibraryEntries;

  /// 云同步状态与配置
  bool get isSyncingPromptLibrary => _isSyncingPromptLibrary;
  String? get promptSyncStage => _promptSyncStage;
  DateTime? get lastPromptSyncAt => _lastPromptSyncAt;
  PromptLibrarySyncResult? get lastPromptSyncResult => _lastPromptSyncResult;
  PromptLibrarySyncConfig get promptLibrarySyncConfig => PromptLibrarySyncConfig(
    endpoint: _config.promptSyncEndpoint,
    token: _config.promptSyncToken,
    namespace: _config.promptSyncNamespace,
  );

  /// 加载词组合列表
  Future<void> loadPromptLibrary() async {
    try {
      final entries = await _promptLibraryService.loadEntries();
      final syncState = await _promptLibraryService.loadSyncState();
      _promptLibraryEntries = List.unmodifiable(entries);
      _lastPromptSyncAt = syncState.lastSyncAt;
      promptLibraryNotifier.value++;
      notifyListeners();
    } catch (_) {}
  }

  /// 词库内容变更后同步刷新内存与自动补全缓存
  Future<List<PromptComboEntry>> _reloadPromptLibrary() async {
    final entries = await _promptLibraryService.loadEntries();
    _promptLibraryEntries = List.unmodifiable(entries);
    // 词组合会注入标签自动补全建议，清掉查询缓存避免陈旧条目残留
    TagDictionaryService.instance.clearQueryCache();
    promptLibraryNotifier.value++;
    notifyListeners();
    return entries;
  }

  /// 添加新词组合条目
  @override
  Future<PromptComboEntry> addPromptCombo(PromptComboEntry entry) async {
    final created = await _promptLibraryService.addEntry(entry);
    await _reloadPromptLibrary();
    return created;
  }

  /// 更新词组合条目
  @override
  Future<void> updatePromptCombo(PromptComboEntry entry) async {
    await _promptLibraryService.updateEntry(entry);
    await _reloadPromptLibrary();
  }

  /// 删除词组合条目
  @override
  Future<void> deletePromptCombo(String id) async {
    await _promptLibraryService.deleteEntry(id);
    await _reloadPromptLibrary();
  }

  /// 保存本地预览图片并返回路径
  @override
  Future<String?> savePromptPreviewFromBytes(
    Uint8List bytes, {
    String extension = 'png',
  }) async {
    return await _promptLibraryService.savePreviewImageBytes(
      bytes,
      extension: extension,
    );
  }

  /// 从本地路径复制预览图片并返回持久化路径
  @override
  Future<String?> savePromptPreviewFromPath(String path) async {
    return await _promptLibraryService.copyPreviewImageFromPath(path);
  }

  /// 获取当前画板图片字节用于预览图 (若存在)
  Uint8List? getCurrentCanvasImageBytes() {
    final img = _selectedImage;
    if (img != null) {
      final b = getImageBytes(img);
      if (b != null && b.isNotEmpty) return b;
    }
    return _liveProgressController.previewBytes;
  }

  static String _appendCommaSeparated(String base, String addition) {
    final trimmedAdd = addition.trim();
    if (trimmedAdd.isEmpty) return base;
    final trimmedBase = base.trim();
    if (trimmedBase.isEmpty) return trimmedAdd;
    return trimmedBase.endsWith(',') || trimmedBase.endsWith('，')
        ? '$trimmedBase $trimmedAdd'
        : '$trimmedBase, $trimmedAdd';
  }

  /// 将词组合应用到工作台
  ///
  /// - [replace]: 为 true 时替换目标字段，为 false 时在末尾追加
  /// - [asCharacter]: 为 true 且当分类为角色时，将词组合直接追加为一个新的多角色卡片
  /// - [asStyle]: 为 true 且当分类为风格时，将前置/后置词写入固定词缀并开启固定词缀开关，同时写入负面提示词
  void applyPromptCombo(
    PromptComboEntry combo, {
    bool replace = false,
    bool asCharacter = false,
    bool asStyle = false,
  }) {
    // 1. 若选择作为独立多角色添加 (仅角色分类有效)
    if (asCharacter && combo.isCharacter) {
      final currentList = List<NaiCharacterPrompt>.from(
        _params.characterPrompts,
      );
      currentList.add(
        NaiCharacterPrompt.create(
          name: combo.title.trim().isNotEmpty
              ? combo.title.trim()
              : vmL10n.vmNewCharacterName,
          prompt: combo.prompt.trim(),
          negativePrompt: combo.negativePrompt.trim(),
        ),
      );
      _setCharacterPrompts(currentList);
      notifyListeners();
      return;
    }

    // 2. 若选择作为画风应用到固定词缀与负面词 (仅风格分类有效)
    if (asStyle && combo.isStyle) {
      final incomingPrefix = combo.effectiveStylePrefix;
      final incomingSuffix = combo.suffixPrompt.trim();
      final incomingNegative = combo.negativePrompt.trim();

      var nextPrefix = _params.prefixPrompt ?? '';
      var nextSuffix = _params.suffixPrompt ?? '';
      var nextApplyFixed = _params.applyFixedPrompts;
      var nextNegative = _params.negativePrompt;

      if (incomingPrefix.isNotEmpty || incomingSuffix.isNotEmpty) {
        if (replace) {
          nextPrefix = incomingPrefix;
          nextSuffix = incomingSuffix;
        } else {
          if (incomingPrefix.isNotEmpty) {
            nextPrefix = _appendCommaSeparated(nextPrefix, incomingPrefix);
          }
          if (incomingSuffix.isNotEmpty) {
            nextSuffix = _appendCommaSeparated(nextSuffix, incomingSuffix);
          }
        }
        nextApplyFixed = true;
      }

      if (incomingNegative.isNotEmpty) {
        nextNegative = replace
            ? incomingNegative
            : _appendCommaSeparated(nextNegative, incomingNegative);
      }

      updateParams(
        _params.copyWith(
          prefixPrompt: nextPrefix,
          suffixPrompt: nextSuffix,
          applyFixedPrompts: nextApplyFixed,
          negativePrompt: nextNegative,
        ),
      );
      return;
    }

    var nextPrompt = _params.prompt;
    var nextNegativePrompt = _params.negativePrompt;

    // 3. 正向提示词应用 (风格条目未填写主提示词时合并前后缀)
    final incomingPrompt = combo.prompt.trim().isNotEmpty
        ? combo.prompt.trim()
        : (combo.isStyle
              ? [
                  combo.prefixPrompt.trim(),
                  combo.suffixPrompt.trim(),
                ].where((s) => s.isNotEmpty).join(', ')
              : '');
    if (incomingPrompt.isNotEmpty) {
      nextPrompt = replace
          ? incomingPrompt
          : _appendCommaSeparated(nextPrompt, incomingPrompt);
    }

    // 4. 负面提示词应用 (角色或风格分类且负面词不为空时生效)
    if (combo.supportsNegative && combo.negativePrompt.trim().isNotEmpty) {
      final incomingUc = combo.negativePrompt.trim();
      nextNegativePrompt = replace
          ? incomingUc
          : _appendCommaSeparated(nextNegativePrompt, incomingUc);
    }

    updateParams(
      _params.copyWith(prompt: nextPrompt, negativePrompt: nextNegativePrompt),
    );
  }

  /// 导出全部词组合为 JSON
  Future<String> exportPromptLibraryJson() async {
    return await _promptLibraryService.exportToJson();
  }

  /// 从 JSON 导入词组合
  Future<int> importPromptLibraryJson(
    String jsonStr, {
    bool replaceAll = false,
  }) async {
    final count = await _promptLibraryService.importFromJson(
      jsonStr,
      replaceAll: replaceAll,
    );
    await _reloadPromptLibrary();
    return count;
  }

  /// 保存词库云同步配置
  Future<void> savePromptSyncConfig(PromptLibrarySyncConfig syncConfig) async {
    final nextNs = syncConfig.normalizedNamespace;
    await updateConfig(
      _config.copyWith(
        promptSyncEndpoint: syncConfig.endpoint.trim(),
        promptSyncToken: syncConfig.token.trim(),
        promptSyncNamespace: nextNs,
      ),
    );
    promptLibraryNotifier.value++;
  }

  /// 测试 Cloudflare 词库云同步连接
  Future<PromptLibrarySyncHealth> testPromptLibrarySyncConnection([
    PromptLibrarySyncConfig? overrideConfig,
  ]) {
    return _promptLibrarySyncService.testConnection(
      overrideConfig ?? promptLibrarySyncConfig,
    );
  }

  /// 执行词库云同步 (支持双向增量合并 / 强制上传覆盖 / 强制拉取覆盖)
  Future<PromptLibrarySyncResult> syncPromptLibrary({
    PromptLibrarySyncMode mode = PromptLibrarySyncMode.merge,
    PromptLibrarySyncConfig? overrideConfig,
  }) async {
    final targetConfig = overrideConfig ?? promptLibrarySyncConfig;
    _isSyncingPromptLibrary = true;
    _promptSyncStage = null;
    promptLibraryNotifier.value++;
    notifyListeners();

    try {
      final result = await _promptLibrarySyncService.sync(
        targetConfig,
        mode: mode,
        onStatus: (stage) {
          if (_disposed) return;
          _promptSyncStage = stage;
          promptLibraryNotifier.value++;
        },
      );
      _lastPromptSyncAt = result.syncedAt;
      _lastPromptSyncResult = result;
      await _reloadPromptLibrary();
      return result;
    } finally {
      if (!_disposed) {
        _isSyncingPromptLibrary = false;
        _promptSyncStage = null;
        promptLibraryNotifier.value++;
        notifyListeners();
      }
    }
  }
}
