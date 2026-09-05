part of 'studio_view_model.dart';

/// 词组合预设库分部 (Prompt Combo Library)
mixin _StudioLibraryMixin on _StudioCore {
  /// 当前词组合条目列表
  @override
  List<PromptComboEntry> get promptLibraryEntries =>
      List.unmodifiable(_promptLibraryEntries);

  /// 加载词组合列表
  Future<void> loadPromptLibrary() async {
    try {
      _promptLibraryEntries = await _promptLibraryService.loadEntries();
      notifyListeners();
    } catch (_) {}
  }

  /// 词库内容变更后同步刷新内存与自动补全缓存
  Future<List<PromptComboEntry>> _reloadPromptLibrary() async {
    final entries = await _promptLibraryService.loadEntries();
    _promptLibraryEntries = entries;
    // 词组合会注入标签自动补全建议，清掉查询缓存避免陈旧条目残留
    TagDictionaryService.instance.clearQueryCache();
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

  /// 将词组合应用到工作台
  ///
  /// - [replace]: 为 true 时替换主提示词，为 false 时在末尾追加
  /// - [asCharacter]: 为 true 且当分类为角色时，将词组合直接追加为一个新的多角色卡片
  void applyPromptCombo(
    PromptComboEntry combo, {
    bool replace = false,
    bool asCharacter = false,
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

    String nextPrompt = _params.prompt;
    String nextNegativePrompt = _params.negativePrompt;

    // 2. 正向提示词应用
    final incomingPrompt = combo.prompt.trim();
    if (incomingPrompt.isNotEmpty) {
      if (replace || nextPrompt.trim().isEmpty) {
        nextPrompt = incomingPrompt;
      } else {
        final currentPrompt = nextPrompt.trim();
        nextPrompt = currentPrompt.endsWith(',') || currentPrompt.endsWith('，')
            ? '$currentPrompt $incomingPrompt'
            : '$currentPrompt, $incomingPrompt';
      }
    }

    // 3. 负面提示词应用 (只当分类为角色且负面词不为空时生效)
    if (combo.isCharacter && combo.negativePrompt.trim().isNotEmpty) {
      final incomingUc = combo.negativePrompt.trim();
      if (replace || nextNegativePrompt.trim().isEmpty) {
        nextNegativePrompt = incomingUc;
      } else {
        final currentUc = nextNegativePrompt.trim();
        nextNegativePrompt = currentUc.endsWith(',') || currentUc.endsWith('，')
            ? '$currentUc $incomingUc'
            : '$currentUc, $incomingUc';
      }
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
}
