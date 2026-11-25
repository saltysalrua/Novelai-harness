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

  /// 保存本地预览/参考图片并返回路径
  @override
  Future<String?> savePromptPreviewFromBytes(
    Uint8List bytes, {
    String extension = 'png',
    String prefix = 'preview',
  }) async {
    return await _promptLibraryService.savePreviewImageBytes(
      bytes,
      extension: extension,
      prefix: prefix,
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

  /// 将当前工作台挂载的精准参考图落盘为词库托管条目列表
  @override
  Future<List<PromptLibraryPreciseRef>> snapshotWorkspacePreciseReferences() async {
    final result = <PromptLibraryPreciseRef>[];
    var seq = 0;
    for (final ref in _params.preciseReferences) {
      if (ref.imageBytes.isEmpty) continue;
      final savedPath = await _promptLibraryService.savePreviewImageBytes(
        ref.imageBytes,
        extension: _detectRefImageExt(ref.imageBytes, ref.fileName),
        prefix: 'ref',
      );
      if (savedPath == null || savedPath.isEmpty) continue;
      result.add(
        PromptLibraryPreciseRef(
          id: 'lib_pref_${DateTime.now().microsecondsSinceEpoch}_${++seq}',
          imagePath: savedPath,
          fileName: ref.fileName,
          type: ref.type,
          preferSameOutfit: ref.preferSameOutfit,
          strength: ref.strength,
          fidelity: ref.fidelity,
          informationExtracted: ref.informationExtracted,
          enabled: ref.enabled,
        ),
      );
    }
    return result;
  }

  /// 将当前工作台挂载的 Vibe Transfer 落盘为词库托管条目列表（完整保留编码缓存）
  @override
  Future<List<PromptLibraryVibeRef>> snapshotWorkspaceVibeReferences() async {
    final result = <PromptLibraryVibeRef>[];
    var seq = 0;
    for (final vibe in _params.vibeReferences) {
      String? rawPath;
      if (vibe.rawImageBytes != null && vibe.rawImageBytes!.isNotEmpty) {
        rawPath = await _promptLibraryService.savePreviewImageBytes(
          vibe.rawImageBytes!,
          extension: _detectRefImageExt(vibe.rawImageBytes!, vibe.displayName),
          prefix: 'vibe',
        );
      }
      String? thumbPath;
      if (vibe.thumbnailBytes != null &&
          vibe.thumbnailBytes!.isNotEmpty &&
          !identical(vibe.thumbnailBytes, vibe.rawImageBytes)) {
        thumbPath = await _promptLibraryService.savePreviewImageBytes(
          vibe.thumbnailBytes!,
          extension: _detectRefImageExt(vibe.thumbnailBytes!, null),
          prefix: 'vthumb',
        );
      }
      if ((rawPath == null || rawPath.isEmpty) && vibe.encodingsByModel.isEmpty) {
        continue;
      }
      result.add(
        PromptLibraryVibeRef(
          id: 'lib_vibe_${DateTime.now().microsecondsSinceEpoch}_${++seq}',
          displayName: vibe.displayName,
          sourceType: vibe.sourceType,
          rawImagePath: rawPath,
          thumbnailPath: thumbPath,
          encodingsByModel: Map<String, String>.from(vibe.encodingsByModel),
          encodedInfoExtractedByModel: Map<String, double>.from(
            vibe.encodedInfoExtractedByModel,
          ),
          strength: vibe.strength,
          informationExtracted: vibe.informationExtracted,
          enabled: vibe.enabled,
        ),
      );
    }
    return result;
  }

  String _detectRefImageExt(Uint8List bytes, String? fileName) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (fileName != null) {
      final ext = p.extension(fileName).replaceAll('.', '').toLowerCase();
      if (ext == 'jpeg') return 'jpg';
      if (ext == 'png' || ext == 'jpg' || ext == 'webp') return ext;
    }
    return 'png';
  }

  /// 选择性将词库条目的提示词、精准参考图与 Vibe Transfer 应用到工作台
  @override
  Future<({bool appliedPrompt, int appliedPreciseCount, int appliedVibeCount})>
  applyPromptComboSelective(
    PromptComboEntry combo, {
    bool applyPrompt = true,
    bool replacePrompt = false,
    bool asCharacter = false,
    bool asStyle = false,
    bool applyPreciseReferences = false,
    bool applyVibeReferences = false,
    bool replaceReferences = false,
    Set<String>? selectedPreciseRefIds,
    Set<String>? selectedVibeRefIds,
    bool switchToReferenceTab = false,
  }) async {
    var didApplyPrompt = false;
    if (applyPrompt && combo.hasPromptText) {
      applyPromptCombo(
        combo,
        replace: replacePrompt,
        asCharacter: asCharacter,
        asStyle: asStyle,
      );
      didApplyPrompt = true;
    }

    var appliedPreciseCount = 0;
    if (applyPreciseReferences && combo.preciseReferences.isNotEmpty) {
      final mounted = <NaiPreciseReference>[];
      for (final ref in combo.preciseReferences) {
        if (selectedPreciseRefIds != null &&
            !selectedPreciseRefIds.contains(ref.id)) {
          continue;
        }
        final path = ref.imagePath.trim();
        if (path.isEmpty) continue;
        final file = File(path);
        if (!file.existsSync()) continue;
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) continue;
          mounted.add(
            NaiPreciseReference(
              id: ref.id,
              imageBytes: bytes,
              fileName: ref.fileName ?? p.basename(path),
              type: ref.type,
              preferSameOutfit: ref.preferSameOutfit,
              strength: ref.strength,
              fidelity: ref.fidelity,
              informationExtracted: ref.informationExtracted,
              enabled: ref.enabled,
            ),
          );
        } catch (_) {}
      }
      if (mounted.isNotEmpty) {
        mountPreciseReferences(
          mounted,
          replace: replaceReferences,
          switchToTab: switchToReferenceTab && !applyVibeReferences,
        );
        appliedPreciseCount = mounted.length;
      }
    }

    var appliedVibeCount = 0;
    if (applyVibeReferences && combo.vibeReferences.isNotEmpty) {
      final mounted = <NaiVibeReference>[];
      for (final vibe in combo.vibeReferences) {
        if (selectedVibeRefIds != null &&
            !selectedVibeRefIds.contains(vibe.id)) {
          continue;
        }
        Uint8List? rawBytes;
        final rawPath = vibe.rawImagePath?.trim();
        if (rawPath != null && rawPath.isNotEmpty) {
          final file = File(rawPath);
          if (file.existsSync()) {
            try {
              final data = await file.readAsBytes();
              if (data.isNotEmpty) rawBytes = data;
            } catch (_) {}
          }
        }
        Uint8List? thumbBytes;
        final thumbPath = vibe.thumbnailPath?.trim();
        if (thumbPath != null && thumbPath.isNotEmpty) {
          final file = File(thumbPath);
          if (file.existsSync()) {
            try {
              final data = await file.readAsBytes();
              if (data.isNotEmpty) thumbBytes = data;
            } catch (_) {}
          }
        }
        if ((rawBytes == null || rawBytes.isEmpty) &&
            vibe.encodingsByModel.isEmpty) {
          continue;
        }
        mounted.add(
          NaiVibeReference(
            id: vibe.id,
            displayName: vibe.displayName,
            sourceType: vibe.sourceType,
            rawImageBytes: rawBytes,
            thumbnailBytes: thumbBytes,
            encodingsByModel: Map<String, String>.from(vibe.encodingsByModel),
            encodedInfoExtractedByModel: Map<String, double>.from(
              vibe.encodedInfoExtractedByModel,
            ),
            strength: vibe.strength,
            informationExtracted: vibe.informationExtracted,
            enabled: vibe.enabled,
          ),
        );
      }
      if (mounted.isNotEmpty) {
        mountVibeReferences(
          mounted,
          replace: replaceReferences,
          switchToTab: switchToReferenceTab && appliedPreciseCount == 0,
        );
        appliedVibeCount = mounted.length;
      }
    }

    return (
      appliedPrompt: didApplyPrompt,
      appliedPreciseCount: appliedPreciseCount,
      appliedVibeCount: appliedVibeCount,
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
