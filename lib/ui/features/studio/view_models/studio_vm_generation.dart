part of 'studio_view_model.dart';

/// 生图 / 超分 / 实时预览 / 账号信息
mixin _StudioGenerationMixin on _StudioCore {
  /// 生成完成后统一落图 (手动生成与 Agent 工具共用)。
  ///
  /// [wasViewingLatest] 由调用方决定取值时机：手动生图在发起前捕获，但
  /// 完成时会叠加当时的实时 isViewingLatest (用户生成期间滚回顶部看预览时
  /// 视为正在看最新，避免画面已跳到新图却残留“有新图”横幅与旧选中框)；
  /// Agent 工具在完成时刻取当前值。
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
    _statusMessage = '生图完成，已保存在 ${image.localFilePath ?? '本地'}';
  }

  /// 强行中止当前正在执行的生图流
  Future<void> abortGeneration() async {
    if (!_isGenerating) return;
    await _generationSubscription?.cancel();
    _generationSubscription = null;
    _isGenerating = false;
    _livePreviewBytes = null;
    _liveProgress = 0.0;
    _statusMessage = '已终止生成';
    notifyListeners();
  }

  /// 手动快速生图 (使用左侧面板参数，支持实时流式去噪步数预览)
  @override
  Future<void> generateImage() async {
    if (_params.prompt.trim().isEmpty) {
      _errorMessage = '提示词不能为空，请先在左侧或对话框中输入描述。';
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = '未配置 NovelAI API Key，请点击右上角设置。';
      notifyListeners();
      return;
    }

    // 付费闸门: 预计消耗非零时先向用户确认 (覆盖非 Opus 订阅与 V5 体力透支场景)
    if (_accountInfo == null) {
      await refreshAccountInfo();
    }
    final estimatedCost = estimatedGenerationCost;
    if (estimatedCost > 0) {
      final confirmed = await _confirmPaidGeneration(
        params: _params,
        estimatedCost: estimatedCost,
      );
      if (!confirmed) {
        _statusMessage = '已取消生成 (预计消耗 $estimatedCost Anlas)';
        _errorMessage = null;
        notifyListeners();
        return;
      }
    }

    final wasViewingLatest = isViewingLatest;

    _isGenerating = true;
    _livePreviewBytes = null;
    _liveCurrentStep = 0;
    _liveTotalSteps = _params.steps;
    _liveProgress = 0.0;
    _generationStartTime = DateTime.now();
    _errorMessage = null;
    _statusMessage =
        '正在请求 NovelAI 生图 (${_params.width}x${_params.height}, ${_params.steps}步)...';
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
              }
              _livePreviewBytes = null;
              _liveProgress = 1.0;
              notifyListeners();
            } else {
              _livePreviewBytes = progress.previewImage;
              _liveCurrentStep = progress.currentStep;
              _liveTotalSteps = progress.totalSteps;
              _liveProgress = progress.progress;
              _statusMessage =
                  '生成中 · 步数: $_liveCurrentStep / $_liveTotalSteps (${(_liveProgress * 100).toInt()}%)';
              notifyListeners();
            }
          },
          onError: (e) {
            _errorMessage = '生图失败: $e';
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
        _errorMessage = '生图失败: $e';
        _statusMessage = null;
      } finally {
        _generationSubscription = null;
        _isGenerating = false;
        _livePreviewBytes = null;
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
        );

        if (results.isNotEmpty) {
          _applyGeneratedImage(
            results.first,
            wasViewingLatest: wasViewingLatest || isViewingLatest,
          );
        }
      } catch (e) {
        _errorMessage = '生图失败: $e';
        _statusMessage = null;
      } finally {
        _isGenerating = false;
        _livePreviewBytes = null;
        notifyListeners();
        refreshAccountInfo();
      }
    }
  }

  /// 超分放大当前图片 (官方新超分模型，固定倍率输出)
  @override
  Future<void> upscaleSelected() async {
    if (_selectedImage == null) {
      _errorMessage = '当前画板中无图片可供放大。';
      notifyListeners();
      return;
    }

    if (_config.novelAiKey.trim().isEmpty) {
      _errorMessage = '未配置 NovelAI API Key。';
      notifyListeners();
      return;
    }

    // 付费闸门: 官方超分按输入面积分档计费，非零消耗时先向用户确认
    final dims = await AnlasCalculator.decodeImageDimensions(
      _selectedImage!.bytes,
    );
    if (dims != null) {
      if (_accountInfo == null) {
        await refreshAccountInfo();
      }
      final upscaleCost = AnlasCalculator.estimateUpscaleCost(
        inputWidth: dims.width,
        inputHeight: dims.height,
        isOpus: _accountInfo?.isOpus ?? false,
      );
      if (upscaleCost > 0) {
        final confirmed = await _confirmPaidUpscale(
          estimatedCost: upscaleCost,
          inputWidth: dims.width,
          inputHeight: dims.height,
        );
        if (!confirmed) {
          _statusMessage = '已取消放大 (预计消耗 $upscaleCost Anlas)';
          _errorMessage = null;
          notifyListeners();
          return;
        }
      }
    }

    _isGenerating = true;
    _errorMessage = null;
    _statusMessage = '正在执行图像超分放大...';
    notifyListeners();

    try {
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
      );
      _selectedImage = upscaled;
      _statusMessage =
          '放大完成 (${upscaled.params.width}x${upscaled.params.height})';
    } catch (e) {
      _errorMessage = '放大失败: $e';
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
    final rawBytes = ImageMetadataService.embedNovelAiMetadata(
      pngBytes: Uint8List.fromList(image.bytes),
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
