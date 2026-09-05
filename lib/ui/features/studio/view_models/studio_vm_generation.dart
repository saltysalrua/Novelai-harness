part of 'studio_view_model.dart';

/// 生图 / 超分 / 实时预览 / 账号信息
mixin _StudioGenerationMixin on _StudioCore {
  /// 生成完成后统一落图 (手动生成与 Agent 工具共用)。
  ///
  /// [wasViewingLatest] 由调用方决定取值时机：手动生图与 Agent 工具
  /// (经 onBeforeGenerate 回调) 都在发起前捕获，但完成时会叠加当时的
  /// 实时 isViewingLatest (用户生成期间滚回顶部看预览时视为正在看最新，
  /// 避免画面已跳到新图却残留“有新图”横幅与旧选中框)。
  @override
  void _applyGeneratedImage(
    NaiGeneratedImage image, {
    required bool wasViewingLatest,
  }) {
    if (wasViewingLatest) {
      _selectedImage = image;
      _hasUnseenLatest = false;
    } else {
      _hasUnseenLatest = true;
    }
    _statusMessage = image.isUnsaved
        ? vmL10n.vmGenDoneUnsaved
        : vmL10n.vmGenDoneSavedTo(image.localFilePath ?? vmL10n.vmGenLocalPath);
  }

  /// 手动保存当前选中的未保存 (缓存) 图片到本地存储目录。
  ///
  /// 自动保存关闭时画板右下角保存按钮调用；按全局导出设置处理元数据与
  /// 水印后落盘，删除旧缓存文件。返回是否保存成功。
  @override
  Future<bool> saveCurrentImageToDisk() async {
    final image = _selectedImage;
    if (image == null || !image.isUnsaved) return false;

    await ensureImageLoaded(image);

    if (_config.saveDirectory.isEmpty) {
      _errorMessage = vmL10n.vmGenNoSaveDir;
      notifyListeners();
      return false;
    }

    try {
      final saved = await _repository.saveUnsavedImageToDisk(
        imageId: image.id,
        saveDir: _config.saveDirectory,
        enablePersistence: _config.enableImagePersistence,
        maxImages: _config.maxPersistentImages,
        stripMetadata: _config.stripMetadata,
        enableWatermark: _config.enableWatermark,
        keepOriginalImage: _config.keepOriginalImage,
        watermarkConfig: _config.watermarkConfig,
        watermarkBytes: _config.watermarkConfig.imageBytes,
      );
      if (saved == null) {
        _errorMessage = vmL10n.vmGenSaveFailedNoTarget;
        notifyListeners();
        return false;
      }
      if (_selectedImage?.id == saved.id) {
        _selectedImage = saved;
      }
      _statusMessage = vmL10n.vmGenSavedTo(saved.localFilePath!);
      notifyListeners();
      return true;
    } catch (e) {
      _errorMessage = vmL10n.vmGenSaveFailed('$e');
      notifyListeners();
      return false;
    }
  }

  /// 强行中止当前正在执行的生图流
  Future<void> abortGeneration() async {
    if (!_isGenerating) return;
    await _generationSubscription?.cancel();
    _generationSubscription = null;
    _isGenerating = false;
    _liveProgressController.clear();
    _statusMessage = vmL10n.vmGenAborted;
    notifyListeners();
  }

  /// 手动快速生图 (使用左侧面板参数，支持实时流式去噪步数预览)
  @override
  Future<void> generateImage() async {
    if (_params.prompt.trim().isEmpty) {
      _errorMessage = vmL10n.vmGenEmptyPrompt;
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = vmL10n.vmGenNoApiKey;
      notifyListeners();
      return;
    }

    // 用户手动生图不再弹付费确认：生成坞按钮已实时显示预计点数
    // (需点数/生成图片 (N Anlas) 警示色)，足够的 UI 提醒已前置；
    // 点数消耗申请卡片只保留给 Agent (模型主动调用生图工具) 场景。
    if (_accountInfo == null) {
      await refreshAccountInfo();
    }

    final wasViewingLatest = isViewingLatest;

    // 种子生成控制：生图前变更种子 (若 timing == before)
    if (_params.seedTiming == NaiSeedTiming.before) {
      _applySeedMutationBefore();
    }

    _isGenerating = true;
    _liveProgressController.begin(_params.steps, DateTime.now());
    _errorMessage = null;
    _statusMessage = vmL10n.vmGenRequesting(
      _params.width,
      _params.height,
      _params.steps,
    );
    notifyListeners();

    if (_config.enableStreamPreview) {
      final completer = Completer<void>();
      try {
        final stream = _repository.generateStream(
          apiKey: _config.novelAiKey,
          params: _params,
          saveDir: _config.saveDirectory,
          enablePersistence: _config.enableImagePersistence,
          maxImages: _config.maxPersistentImages,
          stripMetadata: _config.stripMetadata,
          enableWatermark: _config.enableWatermark,
          keepOriginalImage: _config.keepOriginalImage,
          watermarkConfig: _config.watermarkConfig,
          watermarkBytes: _config.watermarkConfig.imageBytes,
          autoSave: _config.autoSaveImages,
        );

        _generationSubscription = stream.listen(
          (progress) {
            if (progress.errorMessage != null &&
                progress.errorMessage!.isNotEmpty) {
              _errorMessage = progress.errorMessage;
              notifyListeners();
              return;
            }

            if (progress.isFinal) {
              final newImage = progress.generatedImage;
              if (newImage != null) {
                _applyGeneratedImage(
                  newImage,
                  // 发起前在看最新，或生成期间已滚回顶部看预览，都视为正在看最新
                  wasViewingLatest: wasViewingLatest || isViewingLatest,
                );
                // 种子生成控制：生图后变更种子 (若 timing == after)
                if (_params.seedTiming == NaiSeedTiming.after) {
                  _applySeedMutationAfter(newImage.seed);
                }
              }
              _liveProgressController.complete();
              notifyListeners();
            } else {
              // 中间去噪帧：只驱动画板占位卡/历史缩略图/生成熔按钮局部刷新，
              // 不触发全局 notifyListeners()，主工作台零重绘
              _liveProgressController.updateFrame(
                previewBytes: progress.previewImage,
                currentStep: progress.currentStep,
                totalSteps: progress.totalSteps,
                progress: progress.progress,
              );
            }
          },
          onError: (e) {
            _errorMessage = vmL10n.vmGenFailed('$e');
            _statusMessage = null;
            if (!completer.isCompleted) completer.complete();
          },
          onDone: () {
            if (!completer.isCompleted) completer.complete();
          },
          cancelOnError: true,
        );

        await completer.future;
      } catch (e) {
        _errorMessage = vmL10n.vmGenFailed('$e');
        _statusMessage = null;
      } finally {
        _generationSubscription = null;
        _isGenerating = false;
        _liveProgressController.clear();
        notifyListeners();
        refreshAccountInfo();
      }
    } else {
      try {
        final results = await _repository.generate(
          apiKey: _config.novelAiKey,
          params: _params,
          saveDir: _config.saveDirectory,
          enablePersistence: _config.enableImagePersistence,
          maxImages: _config.maxPersistentImages,
          stripMetadata: _config.stripMetadata,
          enableWatermark: _config.enableWatermark,
          keepOriginalImage: _config.keepOriginalImage,
          watermarkConfig: _config.watermarkConfig,
          watermarkBytes: _config.watermarkConfig.imageBytes,
          autoSave: _config.autoSaveImages,
        );

        if (results.isNotEmpty) {
          _applyGeneratedImage(
            results.first,
            wasViewingLatest: wasViewingLatest || isViewingLatest,
          );
          // 种子生成控制：生图后变更种子 (若 timing == after)
          if (_params.seedTiming == NaiSeedTiming.after) {
            _applySeedMutationAfter(results.first.seed);
          }
        }
      } catch (e) {
        _errorMessage = vmL10n.vmGenFailed('$e');
        _statusMessage = null;
      } finally {
        _isGenerating = false;
        _liveProgressController.clear();
        notifyListeners();
        refreshAccountInfo();
      }
    }
  }

  /// 生图前根据种子模式更新种子 (当 timing == before 时触发)
  void _applySeedMutationBefore() {
    switch (_params.seedMode) {
      case NaiSeedMode.random:
        final newSeed = generateRandomSeed();
        _params = _params.copyWith(seed: newSeed);
        break;
      case NaiSeedMode.increase:
        final current = _params.seed;
        final next = current < 0
            ? generateRandomSeed()
            : (current + 1) % 4294967295;
        _params = _params.copyWith(seed: next);
        break;
      case NaiSeedMode.fixed:
        break;
    }
  }

  /// 生图后根据种子模式更新种子 (当 timing == after 时触发)
  void _applySeedMutationAfter(int generatedSeed) {
    switch (_params.seedMode) {
      case NaiSeedMode.random:
        final nextSeed = generateRandomSeed();
        _params = _params.copyWith(seed: nextSeed);
        break;
      case NaiSeedMode.increase:
        final base = generatedSeed >= 0
            ? generatedSeed
            : (_params.seed >= 0 ? _params.seed : 0);
        final nextSeed = (base + 1) % 4294967295;
        _params = _params.copyWith(seed: nextSeed);
        break;
      case NaiSeedMode.fixed:
        break;
    }
  }

  /// 超分放大当前图片 (官方新超分模型，固定倍率输出)
  @override
  Future<void> upscaleSelected() async {
    if (_selectedImage == null) {
      _errorMessage = vmL10n.vmUpscaleNoImage;
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = vmL10n.vmUpscaleNoApiKey;
      notifyListeners();
      return;
    }

    // 官方超分按输入面积分档计费；用户手动超分不弹付费确认，
    // 画板操作条与账号栏已展示点数信息，付费确认卡片只保留给 Agent 场景。

    _isGenerating = true;
    _errorMessage = null;
    _statusMessage = vmL10n.vmUpscaleRunning;
    notifyListeners();

    try {
      final loaded = await ensureImageLoaded(_selectedImage!);
      if (loaded != null && _selectedImage!.bytes.isEmpty) {
        _selectedImage = _selectedImage!.copyWith(bytes: loaded);
      }
      final upscaled = await _repository.upscale(
        apiKey: _config.novelAiKey,
        sourceImage: _selectedImage!,
        saveDir: _config.saveDirectory,
        enablePersistence: _config.enableImagePersistence,
        maxImages: _config.maxPersistentImages,
        stripMetadata: _config.stripMetadata,
        enableWatermark: _config.enableWatermark,
        keepOriginalImage: _config.keepOriginalImage,
        watermarkConfig: _config.watermarkConfig,
        watermarkBytes: _config.watermarkConfig.imageBytes,
        autoSave: _config.autoSaveImages,
      );
      _selectedImage = upscaled;
      _statusMessage = upscaled.isUnsaved
          ? vmL10n.vmUpscaleDoneUnsaved(
              upscaled.params.width,
              upscaled.params.height,
            )
          : vmL10n.vmUpscaleDone(upscaled.params.width, upscaled.params.height);
    } catch (e) {
      _errorMessage = vmL10n.vmUpscaleFailed('$e');
      _statusMessage = null;
    } finally {
      _isGenerating = false;
      notifyListeners();
      refreshAccountInfo();
    }
  }

  /// 获取用于导出/复制的图像字节 (根据全局设置决定是否去元数据或添加水印)
  @override
  Future<Uint8List> getExportImageBytes(
    NaiGeneratedImage image, {
    bool raw = false,
  }) async {
    final bytes = await ensureImageLoaded(image) ?? image.bytes;
    final rawBytes = ImageMetadataService.embedNovelAiMetadata(
      pngBytes: bytes,
      params: image.params,
      seed: image.seed,
    );
    if (raw) return rawBytes;

    return WatermarkService.processExportImage(
      rawBytes: rawBytes,
      stripMetadata: _config.stripMetadata,
      enableWatermark: _config.enableWatermark,
      watermarkConfig: _config.watermarkConfig,
      watermarkBytes: _config.watermarkConfig.imageBytes,
    );
  }

  /// 刷新账号与体力信息
  @override
  Future<void> refreshAccountInfo() async {
    if (_config.novelAiKey.trim().isEmpty) return;

    _isLoadingAccount = true;
    notifyListeners();

    try {
      _accountInfo = await _repository.fetchAccountInfo(
        apiKey: _config.novelAiKey,
      );
    } catch (_) {
      // ignore
    } finally {
      _isLoadingAccount = false;
      notifyListeners();
    }
  }
}
