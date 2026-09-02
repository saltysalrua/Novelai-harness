part of 'studio_view_model.dart';

/// 局部修复 / 焦点特写状态管理 Mixin
mixin _StudioInpaintMixin on _StudioCore {
  InpaintParams get inpaintParams => _inpaintParams;
  bool get isExecutingInpaint => _isExecutingInpaint;
  InpaintTool get inpaintTool => _inpaintTool;

  /// 修复执行中的中间帧预览 (仅修复画板展示，完成后清空)
  Uint8List? get inpaintPreviewBytes => _inpaintPreviewBytes;

  NaiGeneratedImage? get inpaintSourceImage =>
      _inpaintSourceImage ??
      _selectedImage ??
      (_repository.history.isNotEmpty ? _repository.history.first : null);

  /// 修复底图的实际像素尺寸 (params 异常时回退工作台参数)
  ({int width, int height}) _inpaintSourceDims() {
    final src = inpaintSourceImage;
    return (
      width: (src?.params.width ?? 0) > 0 ? src!.params.width : _params.width,
      height: (src?.params.height ?? 0) > 0
          ? src!.params.height
          : _params.height,
    );
  }

  /// 计算当前生效选区 (画笔描边优先) 对应的焦点几何信息
  InpaintGeometry get inpaintGeometry {
    final dims = _inpaintSourceDims();
    final srcW = dims.width;
    final srcH = dims.height;
    final selRect = _inpaintParams.effectiveSelectionRect;

    if (_inpaintParams.mode == InpaintMode.focus) {
      final pixelRect = Rect.fromLTWH(
        selRect.left * srcW,
        selRect.top * srcH,
        selRect.width * srcW,
        selRect.height * srcH,
      );
      return InpaintService.resolveGeometry(
        sourceWidth: srcW,
        sourceHeight: srcH,
        selectionRect: pixelRect,
        contextPadding: _inpaintParams.contextPadding,
      );
    }

    final reqSize = InpaintService.resolveStandardRequestSize(srcW, srcH);
    return InpaintGeometry(
      focusBounds: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
      contextCrop: Rect.fromLTWH(0, 0, srcW.toDouble(), srcH.toDouble()),
      requestWidth: reqSize.width,
      requestHeight: reqSize.height,
      scale: 1.0,
    );
  }

  void updateInpaintParams(InpaintParams newParams) {
    _inpaintParams = newParams;
    notifyListeners();
  }

  void setInpaintMode(InpaintMode mode) {
    if (_inpaintParams.mode == mode) return;
    _inpaintParams = _inpaintParams.copyWith(mode: mode);
    notifyListeners();
  }

  void setInpaintTool(InpaintTool tool) {
    if (_inpaintTool == tool) return;
    _inpaintTool = tool;
    notifyListeners();
  }

  void setInpaintSelectionRect(Rect? rect) {
    _inpaintParams = _inpaintParams.copyWith(
      selectionRect: rect,
      clearSelectionRect: rect == null,
    );
    notifyListeners();
  }

  void setInpaintContextPadding(double padding) {
    if (_inpaintParams.contextPadding == padding) return;
    _inpaintParams = _inpaintParams.copyWith(contextPadding: padding);
    notifyListeners();
  }

  void setInpaintStrength(double strength) {
    if (_inpaintParams.strength == strength) return;
    _inpaintParams = _inpaintParams.copyWith(strength: strength);
    notifyListeners();
  }

  void setInpaintNoise(double noise) {
    if (_inpaintParams.noise == noise) return;
    _inpaintParams = _inpaintParams.copyWith(noise: noise);
    notifyListeners();
  }

  void setInpaintBrushRadius(double radius) {
    final clamped = radius.clamp(0.005, 0.25);
    if ((_inpaintParams.brushRadius - clamped).abs() < 0.0001) return;
    _inpaintParams = _inpaintParams.copyWith(brushRadius: clamped);
    notifyListeners();
  }

  /// 提交一条画笔描边 (归一化轨迹点，来自修复画板拖拽；单点 = 盖章一个圆点)。
  /// [erase] 为 true 时是反向画笔：在蒙版上打黑，抵消先前笔迹。
  ///
  /// 提交时一次性栅格化计算剩余蒙版包围盒 (非实时)，橡皮擦除后
  /// 生效选区/外延裁剪框随之收缩；拖拽中沿用旧包围盒不跳动。
  void commitInpaintStroke(List<Offset> points, {bool erase = false}) {
    if (points.isEmpty) return;
    final strokes = List<InpaintBrushStroke>.from(_inpaintParams.brushStrokes)
      ..add(
        InpaintBrushStroke(
          points: List.unmodifiable(points),
          radius: _inpaintParams.brushRadius,
          isEraser: erase,
        ),
      );
    final bounds = InpaintService.computeStrokeMaskBounds(strokes);
    _inpaintParams = _inpaintParams.copyWith(
      brushStrokes: strokes,
      maskBounds: bounds,
      clearMaskBounds: bounds == null,
    );
    notifyListeners();
  }

  /// 清空修复蒙版 (画笔描边与矩形选区一并清除)
  void clearInpaintMask() {
    if (_inpaintParams.brushStrokes.isEmpty &&
        _inpaintParams.selectionRect == null) {
      return;
    }
    _inpaintParams = _inpaintParams.copyWith(
      brushStrokes: const [],
      clearBrushStrokes: true,
      clearSelectionRect: true,
      clearMaskBounds: true,
    );
    notifyListeners();
  }

  void setInpaintCustomPrompt(String prompt) {
    _inpaintParams = _inpaintParams.copyWith(customPrompt: prompt);
    notifyListeners();
  }

  void setInpaintCustomNegativePrompt(String negPrompt) {
    _inpaintParams = _inpaintParams.copyWith(customNegativePrompt: negPrompt);
    notifyListeners();
  }

  void setInpaintUseMainPrompt(bool use) {
    if (_inpaintParams.useMainPrompt == use) return;
    _inpaintParams = _inpaintParams.copyWith(useMainPrompt: use);
    notifyListeners();
  }

  void setInpaintUseMainNegative(bool use) {
    if (_inpaintParams.useMainNegative == use) return;
    _inpaintParams = _inpaintParams.copyWith(useMainNegative: use);
    notifyListeners();
  }

  void setInpaintCustomModel(NaiModel? model) {
    _inpaintParams = _inpaintParams.copyWith(
      customModel: model,
      clearCustomModel: model == null,
    );
    notifyListeners();
  }

  void setInpaintSourceImage(NaiGeneratedImage? img) {
    _inpaintSourceImage = img;
    notifyListeners();
  }

  /// 一键将画板上的批注转换为修复选区
  void useAnnotationAsInpaintRect(ImageAnnotation annotation) {
    if (annotation.type == AnnotationType.rect && annotation.rect != null) {
      setInpaintSelectionRect(annotation.rect);
      if (annotation.note.trim().isNotEmpty) {
        setInpaintCustomPrompt(annotation.note.trim());
        setInpaintUseMainPrompt(false);
      }
      _statusMessage = '已将批注转换为修复选区';
      notifyListeners();
    }
  }

  /// 图片右键「发送到修复」：设为修复底图并切换到修复页签
  void sendImageToInpaint(NaiGeneratedImage image) {
    _inpaintSourceImage = image;
    _statusMessage = '已发送到修复画板: ${image.localFilePath ?? image.id}';
    setActiveSidebarTab(StudioSidebarTab.inpaint);
  }

  /// 批注选区右键「发送到修复」：底图 + 选区 + 批注备注一并带入修复页
  void sendAnnotationToInpaint(
    NaiGeneratedImage sourceImage,
    ImageAnnotation annotation,
  ) {
    _inpaintSourceImage = sourceImage;
    _inpaintParams = _inpaintParams.copyWith(
      brushStrokes: const [],
      clearBrushStrokes: true,
      clearMaskBounds: true,
    );
    useAnnotationAsInpaintRect(annotation);
    if (isAnnotatingImage) {
      setAnnotatingImage(false);
    }
    setActiveSidebarTab(StudioSidebarTab.inpaint);
  }

  /// 执行局部修复 / 焦点特写
  Future<void> executeInpaint() async {
    final target = inpaintSourceImage;
    if (target == null) {
      _errorMessage = '未找到可供修复的底图，请先选择或生成图片。';
      notifyListeners();
      return;
    }

    if (_isExecutingInpaint || _isGenerating) return;

    // 焦点模式必须先在画板框选或绘制修复区域 (常规模式无选区 = 整图重绘)
    if (_inpaintParams.mode == InpaintMode.focus &&
        _inpaintParams.selectionRect == null &&
        !_inpaintParams.hasBrushMask) {
      _errorMessage = '请先在修复画板框选或用画笔绘制待修复区域。';
      notifyListeners();
      return;
    }

    final config = _config;
    if (config.novelAiKey.trim().isEmpty) {
      _errorMessage = '未配置 NovelAI API Key，请在设置中输入 Token。';
      notifyListeners();
      return;
    }

    _isExecutingInpaint = true;
    _errorMessage = null;
    _inpaintPreviewBytes = null;
    _statusMessage = '正在执行局部修复...';
    notifyListeners();

    try {
      if (config.enableStreamPreview) {
        final stream = _repository.generateInpaintStream(
          apiKey: config.novelAiKey,
          sourceImageBytes: Uint8List.fromList(target.bytes),
          inpaintParams: _inpaintParams,
          generationParams: _params,
          saveDir: config.saveDirectory,
          enablePersistence: config.enableImagePersistence,
          maxImages: config.maxPersistentImages,
          stripMetadata: config.stripMetadata,
          enableWatermark: config.enableWatermark,
          keepOriginalImage: config.keepOriginalImage,
          watermarkConfig: config.watermarkConfig,
          watermarkBytes: config.watermarkConfig.imageBytes,
          autoSave: config.autoSaveImages,
        );

        await for (final progress in stream) {
          if (progress.isFinal && progress.generatedImage != null) {
            final result = progress.generatedImage!;
            // 修复完成直接跳到新图：选中新图 (不弹「有新图」横幅)，
            // 并把修复底图切到新图，画板立即展示修复结果，便于继续迭代
            _applyGeneratedImage(result, wasViewingLatest: true);
            _inpaintSourceImage = result;
          } else if (!progress.isFinal && progress.previewImage != null) {
            // 修复中间帧预览只驱动修复画板，不占用生图预览通道
            _inpaintPreviewBytes = progress.previewImage;
            notifyListeners();
          }
        }
      } else {
        final result = await _repository.generateInpaint(
          apiKey: config.novelAiKey,
          sourceImageBytes: Uint8List.fromList(target.bytes),
          inpaintParams: _inpaintParams,
          generationParams: _params,
          saveDir: config.saveDirectory,
          enablePersistence: config.enableImagePersistence,
          maxImages: config.maxPersistentImages,
          stripMetadata: config.stripMetadata,
          enableWatermark: config.enableWatermark,
          keepOriginalImage: config.keepOriginalImage,
          watermarkConfig: config.watermarkConfig,
          watermarkBytes: config.watermarkConfig.imageBytes,
          autoSave: config.autoSaveImages,
        );
        // 同上：完成即跳到新图，不弹「有新图」横幅
        _applyGeneratedImage(result, wasViewingLatest: true);
        _inpaintSourceImage = result;
      }

      _inpaintPreviewBytes = null;
      _statusMessage = '局部修复完成';
    } catch (e) {
      _errorMessage = '修复失败: $e';
    } finally {
      _isExecutingInpaint = false;
      notifyListeners();
    }
  }
}
