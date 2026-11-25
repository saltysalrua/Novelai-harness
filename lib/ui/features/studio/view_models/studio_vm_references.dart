part of 'studio_view_model.dart';

/// 精准参考 (Precise Reference) 与 Vibe Transfer 统一管理分部
mixin _StudioReferencesMixin on _StudioCore {
  int _preciseRefSeq = 0;
  int _vibeRefSeq = 0;

  /// 侧边栏「参考」页当前子页签：0 = 精准参考，1 = Vibe Transfer
  int _referenceSubTab = 0;
  final Set<String> _encodingVibeIds = <String>{};

  int get referenceSubTab => _referenceSubTab;

  void setReferenceSubTab(int index) {
    final normalized = index == 1 ? 1 : 0;
    if (_referenceSubTab == normalized) return;
    _referenceSubTab = normalized;
    notifyListeners();
  }

  // ==================== 精准参考 (Precise Reference) ====================

  /// 当前工作台挂载的全部精准参考图 (含已禁用项)
  List<NaiPreciseReference> get preciseReferences => _params.preciseReferences;

  /// 当前模型下实际生效的精准参考图列表
  List<NaiPreciseReference> get effectivePreciseReferences =>
      _params.effectivePreciseReferences();

  /// 当前生效精准参考图数量 (用于侧栏圆点与费用展示)
  int get effectivePreciseReferenceCount => effectivePreciseReferences.length;

  /// V5 Full 是否因挂载精准参考而被强制切回通常档 (High effort)
  bool get isEffortForcedByPreciseReference =>
      _params.isEffortForcedByPreciseReference;

  /// 从原始图片字节添加一张精准参考图 (文件选择 / 拖拽 / 剪贴板粘贴共用)
  void addPreciseReferenceFromBytes(
    Uint8List bytes, {
    String? fileName,
    NaiPreciseRefType? type,
    bool switchToTab = false,
  }) {
    if (bytes.isEmpty) return;
    final resolvedType = type ?? NaiPreciseRefType.characterAndStyle;
    final ref = NaiPreciseReference(
      id: 'pref_${DateTime.now().microsecondsSinceEpoch}_${++_preciseRefSeq}',
      imageBytes: bytes,
      fileName: fileName,
      type: resolvedType,
      preferSameOutfit: resolvedType == NaiPreciseRefType.characterAndStyle,
      strength: 1.0,
      fidelity: 1.0,
      informationExtracted: 1.0,
      enabled: true,
    );
    _params = _params.copyWith(
      preciseReferences: [..._params.preciseReferences, ref],
    );
    if (switchToTab) {
      _referenceSubTab = 0;
      setActiveSidebarTab(StudioSidebarTab.reference);
    }
    notifyListeners();
  }

  /// 将画板/历史中的生成图设为精准参考图并切换到参考页签
  Future<bool> sendImageToPreciseReference(
    NaiGeneratedImage image, {
    NaiPreciseRefType? type,
  }) async {
    await ensureImageLoaded(image);
    final bytes = image.bytes;
    if (bytes.isEmpty) return false;
    addPreciseReferenceFromBytes(
      bytes,
      fileName: image.localFilePath != null
          ? p.basename(image.localFilePath!)
          : '${image.id}.png',
      type: type,
      switchToTab: true,
    );
    return true;
  }

  /// 更新单张精准参考图的配置 (类型 / 倾向相同服装 / 强度 / 保真度 / 启停)
  void updatePreciseReference(
    String id, {
    NaiPreciseRefType? type,
    bool? preferSameOutfit,
    double? strength,
    double? fidelity,
    bool? enabled,
  }) {
    var changed = false;
    final updated = _params.preciseReferences.map((ref) {
      if (ref.id != id) return ref;
      changed = true;
      // 切换参考类型时按官网交互约定同步 preferSameOutfit 默认态：
      // 切到 character&style 默认开启，切到 character 默认关闭。
      final nextPreferSameOutfit =
          preferSameOutfit ??
          (type != null && type != ref.type
              ? type == NaiPreciseRefType.characterAndStyle
              : ref.preferSameOutfit);
      return ref.copyWith(
        type: type ?? ref.type,
        preferSameOutfit: nextPreferSameOutfit,
        strength: strength ?? ref.strength,
        fidelity: fidelity ?? ref.fidelity,
        enabled: enabled ?? ref.enabled,
      );
    }).toList();

    if (!changed) return;
    _params = _params.copyWith(preciseReferences: updated);
    notifyListeners();
  }

  /// 移除单张精准参考图
  void removePreciseReference(String id) {
    final next = _params.preciseReferences.where((r) => r.id != id).toList();
    if (next.length == _params.preciseReferences.length) return;
    _params = _params.copyWith(preciseReferences: next);
    notifyListeners();
  }

  /// 清空全部精准参考图
  void clearPreciseReferences() {
    if (_params.preciseReferences.isEmpty) return;
    _params = _params.copyWith(preciseReferences: const []);
    notifyListeners();
  }

  // ==================== Vibe Transfer ====================

  /// 当前工作台挂载的全部 Vibe Transfer 参考 (含已禁用项)
  List<NaiVibeReference> get vibeReferences => _params.vibeReferences;

  /// 当前模型下实际生效的 Vibe Transfer 列表
  List<NaiVibeReference> get effectiveVibeReferences =>
      _params.effectiveVibeReferences();

  /// 当前生效 Vibe Transfer 数量
  int get effectiveVibeReferenceCount => effectiveVibeReferences.length;

  /// 是否存在任一激活的参考引导 (精准参考或 Vibe Transfer，用于侧栏状态圆点)
  bool get hasActiveReferenceGuide =>
      effectivePreciseReferenceCount > 0 || effectiveVibeReferenceCount > 0;

  /// 多张编码式 Vibe 是否归一化强度
  bool get normalizeVibeStrength => _params.normalizeVibeStrength;

  /// 指定 Vibe 条目是否正在调用 `/ai/encode-vibe`
  bool isEncodingVibe(String id) => _encodingVibeIds.contains(id);

  /// 切换 Vibe 强度归一化开关
  void setNormalizeVibeStrength(bool value) {
    if (_params.normalizeVibeStrength == value) return;
    _params = _params.copyWith(normalizeVibeStrength: value);
    notifyListeners();
    _scheduleParameterSave();
  }

  /// 从任意文件字节导入 Vibe Transfer (支持 `.naiv4vibe` / `.naiv4vibebundle` / 嵌入 PNG / 普通图片)
  Future<int> importVibeReferencesFromFile({
    required String fileName,
    required Uint8List bytes,
    bool switchToTab = false,
  }) async {
    if (bytes.isEmpty) return 0;
    final parsed = await VibeTransferService.parseImportedFile(
      fileName: fileName,
      bytes: bytes,
      activeModel: _params.model,
    );
    if (parsed.isEmpty) return 0;

    final created = parsed
        .map(
          (item) => item.toReference(
            'vibe_${DateTime.now().microsecondsSinceEpoch}_${++_vibeRefSeq}',
          ),
        )
        .toList();

    _params = _params.copyWith(
      vibeReferences: [..._params.vibeReferences, ...created],
    );
    if (switchToTab) {
      _referenceSubTab = 1;
      setActiveSidebarTab(StudioSidebarTab.reference);
    }
    notifyListeners();
    return created.length;
  }

  /// 将画板/历史中的生成图添加到 Vibe Transfer 并切到对应子页
  Future<bool> sendImageToVibeTransfer(NaiGeneratedImage image) async {
    await ensureImageLoaded(image);
    final bytes = image.bytes;
    if (bytes.isEmpty) return false;
    final fileName = image.localFilePath != null
        ? p.basename(image.localFilePath!)
        : '${image.id}.png';
    final count = await importVibeReferencesFromFile(
      fileName: fileName,
      bytes: bytes,
      switchToTab: true,
    );
    return count > 0;
  }

  /// 更新单条 Vibe 配置
  void updateVibeReference(
    String id, {
    double? strength,
    double? informationExtracted,
    bool? enabled,
  }) {
    var changed = false;
    final updated = _params.vibeReferences.map((vibe) {
      if (vibe.id != id) return vibe;
      changed = true;
      return vibe.copyWith(
        strength: strength ?? vibe.strength,
        informationExtracted: informationExtracted != null
            ? informationExtracted.clamp(0.01, 1.0).toDouble()
            : vibe.informationExtracted,
        enabled: enabled ?? vibe.enabled,
      );
    }).toList();

    if (!changed) return;
    _params = _params.copyWith(vibeReferences: updated);
    notifyListeners();
  }

  /// 写回某条 Vibe 在指定模型下的编码缓存 (手动预编码与生图自动编码共用)
  void cacheVibeEncoding({
    required String vibeId,
    required NaiModel model,
    required String encoding,
    required double informationExtracted,
  }) {
    if (encoding.isEmpty) return;
    var changed = false;
    final updated = _params.vibeReferences.map((vibe) {
      if (vibe.id != vibeId) return vibe;
      changed = true;
      return vibe.withEncodingForModel(
        model: model,
        encoding: encoding,
        informationExtracted: informationExtracted,
      );
    }).toList();
    if (!changed) return;
    _params = _params.copyWith(vibeReferences: updated);
    notifyListeners();
  }

  /// 手动立即编码单条 Vibe (调用 `/ai/encode-vibe`，消耗 2 Anlas 并缓存复用)
  Future<bool> encodeVibeReference(String id) async {
    if (_encodingVibeIds.contains(id)) return false;
    final model = _params.model;
    if (!model.usesEncodedVibeTransfer) return false;
    if (_config.novelAiKey.trim().isEmpty) {
      reportError(vmL10n.vmGenNoApiKey, source: AppNoticeSource.generation);
      return false;
    }

    NaiVibeReference? target;
    for (final v in _params.vibeReferences) {
      if (v.id == id) {
        target = v;
        break;
      }
    }
    if (target == null || !target.hasRawImage) return false;

    _encodingVibeIds.add(id);
    notifyListeners();
    try {
      final info = target.informationExtracted;
      final encoding = await _repository.encodeVibe(
        apiKey: _config.novelAiKey,
        imageBytes: target.rawImageBytes!,
        model: model,
        informationExtracted: info,
      );
      cacheVibeEncoding(
        vibeId: id,
        model: model,
        encoding: encoding,
        informationExtracted: info,
      );
      unawaited(refreshAccountInfo());
      return true;
    } catch (e) {
      reportError('$e', source: AppNoticeSource.generation);
      return false;
    } finally {
      _encodingVibeIds.remove(id);
      notifyListeners();
    }
  }

  /// 在生图前为当前模型下尚未缓存编码的 V4/V4.5 Vibe 预先编码并写回缓存，
  /// 避免每次生成重复扣费。任一条编码失败返回 false。
  @override
  Future<bool> ensurePendingVibesEncoded() async {
    final model = _params.model;
    if (!model.usesEncodedVibeTransfer) return true;
    final pendingIds = _params
        .effectiveVibeReferences()
        .where((v) => v.needsServerEncodingFor(model))
        .map((v) => v.id)
        .toList();
    for (final id in pendingIds) {
      final ok = await encodeVibeReference(id);
      if (!ok) return false;
    }
    return true;
  }

  /// 移除单条 Vibe
  void removeVibeReference(String id) {
    final next = _params.vibeReferences.where((v) => v.id != id).toList();
    if (next.length == _params.vibeReferences.length) return;
    _encodingVibeIds.remove(id);
    _params = _params.copyWith(vibeReferences: next);
    notifyListeners();
  }

  /// 清空全部 Vibe
  void clearVibeReferences() {
    if (_params.vibeReferences.isEmpty) return;
    _encodingVibeIds.clear();
    _params = _params.copyWith(vibeReferences: const []);
    notifyListeners();
  }
}
