part of 'studio_view_model.dart';

/// ComfyUI 模式分部：经 PromptToolkit AI Bridge 驱动 ComfyUI 生图。
///
/// 流程：连接探测 → 解析目标节点 → 推送提示词/分辨率/采样参数 →
/// 请求排队 → 轮询 AI Image Output 发布的成品图 → 登记进历史并落图。
/// 此模式下质量词 / UC 预设拼接与 Token 上限计数全部旁路 (UI 层隐藏入口)。
mixin _StudioComfyMixin on _StudioCore {
  ComfyUiService? _comfyService;
  ComfyUiBridgeState? _comfyBridgeState;
  ComfyUiConnectionStatus _comfyStatus = ComfyUiConnectionStatus.disconnected;
  String? _comfyLastError;
  ComfyUiOptionCatalog? _comfyOptions;
  bool _comfyAbortRequested = false;

  /// 出图轮询间隔 (Bridge 图片注册是执行完成时一次性的，秒级足够)
  static const Duration _comfyPollInterval = Duration(seconds: 2);

  /// 出图等待上限：大工作流 (高步数/多批) 可能很慢，给足 15 分钟
  static const Duration _comfyWaitTimeout = Duration(minutes: 15);

  @override
  ComfyUiConnectionStatus get comfyConnectionStatus => _comfyStatus;

  @override
  ComfyUiBridgeState? get comfyBridgeState => _comfyBridgeState;

  @override
  String? get comfyLastError => _comfyLastError;

  @override
  ComfyUiOptionCatalog? get comfyOptionCatalog => _comfyOptions;

  @override
  String get comfySampler => _config.comfyUiSampler;

  @override
  String get comfyScheduler => _config.comfyUiScheduler;

  @override
  Future<void> setComfySampler(String value) =>
      updateConfig(_config.copyWith(comfyUiSampler: value));

  @override
  Future<void> setComfyScheduler(String value) =>
      updateConfig(_config.copyWith(comfyUiScheduler: value));

  /// 解析本次驱动的目标节点 id (显式配置优先，缺省取注册表第一个)
  ({String promptNodeId, String? resolutionNodeId, String? paramsNodeId})
  _resolveComfyNodeTargets(ComfyUiBridgeState state) {
    String? pick(String configured, List<String> registered) {
      final trimmed = configured.trim();
      if (trimmed.isNotEmpty) return trimmed;
      return registered.isEmpty ? null : registered.first;
    }

    final promptNodeId = pick(_config.comfyUiPromptNodeId, state.promptNodeIds);
    return (
      promptNodeId: promptNodeId ?? '',
      resolutionNodeId: pick(
        _config.comfyUiResolutionNodeId,
        state.resolutionNodeIds,
      ),
      paramsNodeId: pick(_config.comfyUiParamsNodeId, state.paramsNodeIds),
    );
  }

  /// 重建/复用 ComfyUI 服务实例 (baseUrl 变化时自动重建)
  ComfyUiService _ensureComfyService() {
    final url = _config.comfyUiBaseUrl.trim();
    final effective = url.isEmpty ? 'http://127.0.0.1:8188' : url;
    final existing = _comfyService;
    if (existing != null && existing.baseUrl == effective) return existing;
    return _comfyService = ComfyUiService(baseUrl: effective);
  }

  /// 刷新 ComfyUI Bridge 连接状态与节点注册快照
  @override
  Future<void> refreshComfyUiStatus() async {
    if (!_config.comfyUiEnabled) {
      _comfyStatus = ComfyUiConnectionStatus.disconnected;
      _comfyBridgeState = null;
      notifyListeners();
      return;
    }
    _comfyStatus = ComfyUiConnectionStatus.connecting;
    notifyListeners();
    try {
      _comfyBridgeState = await _ensureComfyService().fetchBridgeState();
      _comfyStatus = ComfyUiConnectionStatus.connected;
      _comfyLastError = null;
      // 连接成功后顺带刷新可用采样器/调度器清单；失败静默保持旧值
      await refreshComfyUiOptions();
    } on ComfyUiBridgeException catch (e) {
      _comfyBridgeState = null;
      _comfyStatus = ComfyUiConnectionStatus.disconnected;
      _comfyLastError = e.message;
    } finally {
      notifyListeners();
    }
  }

  /// 重新拉取 ComfyUI 可用采样器/调度器清单 (失败静默保持旧值)
  @override
  Future<void> refreshComfyUiOptions() async {
    if (!_config.comfyUiEnabled) return;
    try {
      _comfyOptions = await _ensureComfyService().fetchOptionCatalog();
    } on ComfyUiBridgeException {
      // 旧版插件无 /object_info 或节点未注册时保持 null，不阻断主流程
    }
  }

  /// 测试钩子：直接注入模拟的采样器/调度器清单 (绕过网络)
  @override
  void setComfyOptionCatalogForTesting(ComfyUiOptionCatalog? catalog) {
    _comfyOptions = catalog;
    notifyListeners();
  }

  /// 切换 ComfyUI 模式开关 (经 updateConfig 统一持久化)
  @override
  Future<void> setComfyUiMode(bool enabled) async {
    if (_config.comfyUiEnabled == enabled) return;
    await updateConfig(_config.copyWith(comfyUiEnabled: enabled));
    if (enabled) {
      unawaited(refreshComfyUiStatus());
    }
  }

  /// 标记中止当前 ComfyUI 出图等待 (由 [abortGeneration] 触发)
  @override
  void _requestComfyAbort() {
    _comfyAbortRequested = true;
  }

  /// ComfyUI 模式生图主流程
  @override
  Future<void> generateImageViaComfyUi() async {
    if (_params.prompt.trim().isEmpty) {
      _errorMessage = vmL10n.vmGenEmptyPrompt;
      notifyListeners();
      return;
    }

    final wasViewingLatest = isViewingLatest;
    _comfyAbortRequested = false;
    _isGenerating = true;
    _errorMessage = null;
    _statusMessage = vmL10n.vmComfyPushing;
    notifyListeners();

    try {
      final service = _ensureComfyService();

      // 1. 探测 Bridge 并解析目标节点
      final ComfyUiBridgeState state;
      try {
        state = await service.fetchBridgeState();
      } on ComfyUiBridgeException catch (e) {
        _errorMessage = vmL10n.vmComfyBridgeUnreachable(e.message);
        return;
      }
      _comfyBridgeState = state;
      _comfyStatus = ComfyUiConnectionStatus.connected;
      _comfyLastError = null;

      final targets = _resolveComfyNodeTargets(state);
      if (targets.promptNodeId.isEmpty) {
        _comfyStatus = ComfyUiConnectionStatus.connected;
        _errorMessage = vmL10n.vmComfyNoPromptPanel;
        notifyListeners();
        return;
      }

      // 2. 种子控制 (生成前变更) + 随机种子落地 (ComfyUI 需要具体值)
      if (_params.seedTiming == NaiSeedTiming.before) {
        _applySeedMutationBefore();
      }
      var seed = _params.seed;
      if (seed < 0) {
        seed = generateRandomSeed();
        _params = _params.copyWith(seed: seed);
      }

      // 冻结此次请求参数，轮询期间用户修改工作台不能改写成品命名快照。
      final requestParams = _params;
      // 3. 推送参数 (ComfyUI 模式禁用质量词/UC 预设：正向词只组固定词缀)
      await service.setPrompt(targets.promptNodeId, requestParams.finalPrompt);
      final resolutionNodeId = targets.resolutionNodeId;
      if (resolutionNodeId != null) {
        await service.setResolution(
          resolutionNodeId,
          requestParams.width,
          requestParams.height,
        );
      }
      final paramsNodeId = targets.paramsNodeId;
      if (paramsNodeId != null) {
        final sampler = _config.comfyUiSampler.trim();
        final scheduler = _config.comfyUiScheduler.trim();
        await service.setParams(
          paramsNodeId,
          ComfyUiParamsPatch(
            negative: requestParams.negativePrompt.trim(),
            steps: requestParams.steps,
            cfg: requestParams.scale,
            seed: seed,
            samplerName: sampler.isEmpty ? null : sampler,
            scheduler: scheduler.isEmpty ? null : scheduler,
          ),
        );
      }

      // 4. 记录基线后排队 (只认基线之后发布的图，避免拿到旧图)
      final baseline = await service.latestImages(limit: 1);
      final baselineTime = baseline.isEmpty ? 0.0 : baseline.first.time;
      await service.queue();
      _statusMessage = vmL10n.vmComfyQueued;
      notifyListeners();

      // 5. 轮询等待新图
      final deadline = DateTime.now().add(_comfyWaitTimeout);
      ComfyUiBridgeImage? fresh;
      while (DateTime.now().isBefore(deadline)) {
        if (_comfyAbortRequested) {
          _statusMessage = vmL10n.vmGenAborted;
          return;
        }
        await Future<void>.delayed(_comfyPollInterval);
        if (_comfyAbortRequested) {
          _statusMessage = vmL10n.vmGenAborted;
          return;
        }
        final images = await service.latestImages(limit: 3);
        for (final image in images) {
          if (image.time > baselineTime) {
            fresh = image;
            break;
          }
        }
        if (fresh != null) break;
      }
      if (fresh == null) {
        _errorMessage = vmL10n.vmComfyWaitTimeout;
        return;
      }

      // 6. 拉取全分辨率字节并登记历史
      final bytes = await service.rawImageBytes();
      final image = await _repository.recordComfyUiImage(
        id: 'comfy_${DateTime.now().millisecondsSinceEpoch}',
        bytes: bytes,
        params: requestParams,
        seed: seed,
        saveDir: _config.saveDirectory,
        imageSaveTemplate: _config.imageSaveTemplate,
        autoSave: _config.autoSaveImages,
        enablePersistence: _config.enableImagePersistence,
        maxImages: _config.maxPersistentImages,
        stripMetadata: _config.stripMetadata,
        enableWatermark: _config.enableWatermark,
        keepOriginalImage: _config.keepOriginalImage,
        watermarkConfig: _config.watermarkConfig,
        watermarkBytes: _config.watermarkConfig.imageBytes,
      );
      _applyGeneratedImage(
        image,
        wasViewingLatest: wasViewingLatest || isViewingLatest,
      );
      if (_params.seedTiming == NaiSeedTiming.after) {
        _applySeedMutationAfter(seed);
      }
    } on ComfyUiBridgeException catch (e) {
      _errorMessage = vmL10n.vmComfyFailed(e.message);
      _statusMessage = null;
    } catch (e) {
      _errorMessage = vmL10n.vmComfyFailed('$e');
      _statusMessage = null;
    } finally {
      _comfyAbortRequested = false;
      _isGenerating = false;
      _liveProgressController.clear();
      notifyListeners();
    }
  }
}
