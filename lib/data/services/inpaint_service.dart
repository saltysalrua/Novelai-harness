import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import 'package:image/image.dart' as img;
import '../models/inpaint_models.dart';

/// Inpaint 与 Focus Inpaint 图像处理服务引擎
///
/// 包含：
/// 1. 焦点特写外延几何计算 (对齐 1MP 潜空间与 64 步长网格)
/// 2. 画笔描边 / 矩形选区 → 源图尺寸二值蒙版栅格化
/// 3. 请求裁剪与等比超采样重编码
/// 4. 生成补丁按蒙版无损回贴合成流水线 (外延上下文环保留原图像素)
abstract final class InpaintService {
  /// 官方对齐尺寸步长 (64 像素对齐)
  static const int dimensionStep = 64;

  /// 焦点重绘默认潜空间像素预算 (1048576 像素 = 1024x1024，100% 享受 Opus 免费)
  static const int focusedTargetAreaPixels = 1048576;

  /// 请求区域最大像素上限 (3145728 像素)
  static const int maxRequestAreaPixels = 3145728;

  // ---------------------------------------------------------------------------
  // 几何计算
  // ---------------------------------------------------------------------------

  /// 计算指定选区的焦点重绘几何信息 (Focus Bounds -> Context Crop -> Request Size)
  static InpaintGeometry resolveGeometry({
    required int sourceWidth,
    required int sourceHeight,
    required Rect selectionRect,
    double contextPadding = 64.0,
  }) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return const InpaintGeometry(
        focusBounds: Rect.zero,
        contextCrop: Rect.zero,
        requestWidth: 1024,
        requestHeight: 1024,
        scale: 1.0,
      );
    }

    // 1. 限制并量化选区边界
    final left = selectionRect.left.clamp(0.0, sourceWidth.toDouble());
    final top = selectionRect.top.clamp(0.0, sourceHeight.toDouble());
    final right = selectionRect.right.clamp(left, sourceWidth.toDouble());
    final bottom = selectionRect.bottom.clamp(top, sourceHeight.toDouble());

    final focusW = math.max(1.0, right - left);
    final focusH = math.max(1.0, bottom - top);
    final focusBounds = Rect.fromLTWH(
      left.floorToDouble(),
      top.floorToDouble(),
      focusW.ceilToDouble(),
      focusH.ceilToDouble(),
    );

    // 2. 计算包含外延上下文 (Context Padding) 的扩展裁剪框
    final padding = contextPadding.clamp(16.0, 192.0);
    final cx = focusBounds.left + focusBounds.width / 2.0;
    final cy = focusBounds.top + focusBounds.height / 2.0;

    final cropW = (focusBounds.width + padding * 2.0).clamp(
      1.0,
      sourceWidth.toDouble(),
    );
    final cropH = (focusBounds.height + padding * 2.0).clamp(
      1.0,
      sourceHeight.toDouble(),
    );

    final cropX = (cx - cropW / 2.0).floorToDouble().clamp(
      0.0,
      sourceWidth - cropW,
    );
    final cropY = (cy - cropH / 2.0).floorToDouble().clamp(
      0.0,
      sourceHeight - cropH,
    );
    final contextCrop = Rect.fromLTWH(cropX, cropY, cropW, cropH);

    // 3. 计算发送给 API 的请求尺寸 (等比放大至 1MP 潜空间，对齐 64 网格)
    final cropArea = contextCrop.width * contextCrop.height;
    final scale = cropArea <= focusedTargetAreaPixels
        ? math.sqrt(focusedTargetAreaPixels / cropArea)
        : 1.0;

    var reqW = _floorToGrid((contextCrop.width * scale).round());
    var reqH = _floorToGrid((contextCrop.height * scale).round());

    // 面积超限收敛
    final areaLimit = cropArea <= focusedTargetAreaPixels
        ? focusedTargetAreaPixels
        : maxRequestAreaPixels;

    if (reqW * reqH > areaLimit) {
      if (reqW >= reqH) {
        reqW = _largestGridDimensionForArea(areaLimit, reqH);
      } else {
        reqH = _largestGridDimensionForArea(areaLimit, reqW);
      }
    }

    return InpaintGeometry(
      focusBounds: focusBounds,
      contextCrop: contextCrop,
      requestWidth: math.max(dimensionStep, reqW),
      requestHeight: math.max(dimensionStep, reqH),
      scale: scale,
      wasDynamicallyConstrained: reqW * reqH > areaLimit,
    );
  }

  /// 常规整图重绘的请求尺寸：对齐源图实际分辨率到 64 步长网格，
  /// 并在最大像素上限内等比收敛 (避免用工作台生成参数的宽高去拉伸任意源图)
  static ({int width, int height}) resolveStandardRequestSize(
    int sourceWidth,
    int sourceHeight,
  ) {
    if (sourceWidth <= 0 || sourceHeight <= 0) {
      return (width: 1024, height: 1024);
    }

    var w = _roundToGrid(sourceWidth);
    var h = _roundToGrid(sourceHeight);

    if (w * h > maxRequestAreaPixels) {
      final shrink = math.sqrt(maxRequestAreaPixels / (w * h));
      w = _floorToGrid((w * shrink).round());
      h = _floorToGrid((h * shrink).round());
    }

    return (
      width: math.max(dimensionStep, w),
      height: math.max(dimensionStep, h),
    );
  }

  // ---------------------------------------------------------------------------
  // 蒙版构建 (源图尺寸)
  // ---------------------------------------------------------------------------

  /// 按修复参数构建源图尺寸的二值蒙版 (白 = 待重绘区域，黑 = 保留区域)
  ///
  /// 画笔描边非空时栅格化描边；否则按归一化矩形选区绘制；
  /// 两者皆无时返回全白蒙版 (整图重绘)。
  static img.Image buildSourceMask({
    required int sourceWidth,
    required int sourceHeight,
    List<InpaintBrushStroke> brushStrokes = const [],
    Rect? selectionRect,
  }) {
    final mask = img.Image(
      width: sourceWidth,
      height: sourceHeight,
      numChannels: 4,
    );
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));

    // 仅当存在非橡皮描边 (正向蒙版) 时才走描边栅格化；全部描边都被
    // 橡皮抵消时回退到矩形选区，避免拿着全黑蒙版自欺欺人地请求一次
    // 什么都不重绘的生成
    if (brushStrokes.any((s) => !s.isEraser && s.points.isNotEmpty)) {
      _paintStrokes(mask, brushStrokes);
      return mask;
    }

    if (selectionRect == null) {
      // 整图重绘 (常规模式默认行为)
      img.fill(mask, color: img.ColorRgba8(255, 255, 255, 255));
      return mask;
    }

    final l = (selectionRect.left * sourceWidth).round().clamp(
      0,
      sourceWidth - 1,
    );
    final t = (selectionRect.top * sourceHeight).round().clamp(
      0,
      sourceHeight - 1,
    );
    final w = (selectionRect.width * sourceWidth).round().clamp(
      1,
      sourceWidth - l,
    );
    final h = (selectionRect.height * sourceHeight).round().clamp(
      1,
      sourceHeight - t,
    );
    img.fillRect(
      mask,
      x1: l,
      y1: t,
      x2: l + w,
      y2: t + h,
      color: img.ColorRgba8(255, 255, 255, 255),
    );
    return mask;
  }

  /// 将画笔描边按提交顺序栅格化进蒙版：正向描边盖章白色 (待重绘)，
  /// 反向橡皮描边盖章黑色 (抵消先前笔迹，后画优先)
  static void _paintStrokes(img.Image mask, List<InpaintBrushStroke> strokes) {
    final shortSide = math.min(mask.width, mask.height).toDouble();
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final color = stroke.isEraser
          ? img.ColorRgba8(0, 0, 0, 255)
          : img.ColorRgba8(255, 255, 255, 255);
      final r = (stroke.radius * shortSide).round().clamp(1, 512);
      for (final p in stroke.points) {
        _stampCircle(
          mask,
          cx: (p.dx * mask.width).round(),
          cy: (p.dy * mask.height).round(),
          radius: r,
          color: color,
        );
      }
    }
  }

  static void _stampCircle(
    img.Image mask, {
    required int cx,
    required int cy,
    required int radius,
    required img.Color color,
  }) {
    final rSq = radius * radius;
    final x0 = (cx - radius).clamp(0, mask.width - 1);
    final x1 = (cx + radius).clamp(0, mask.width - 1);
    final y0 = (cy - radius).clamp(0, mask.height - 1);
    final y1 = (cy + radius).clamp(0, mask.height - 1);
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy <= rSq) {
          mask.setPixel(x, y, color);
        }
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 潜空间蒙版协议 (对齐官方网页端 infill 流程，参考 Aaalice 启动器)
  // ---------------------------------------------------------------------------

  /// 潜空间网格尺寸 (8px 对应一个 latent 单元，请求尺寸为 64 倍数必然整除)
  static const int latentGridSize = 8;

  /// 回贴合成蒙版的潜空间膨胀迭代数 (官方 4 格，覆盖服务端量化后的重绘区)
  static const int latentDilationIterations = 4;

  /// 合成蒙版羽化模糊半径与迭代 (官方 stack blur 20px × 2)
  static const int compositeBlurRadius = 20;
  static const int compositeBlurIterations = 2;

  /// 把请求尺寸蒙版降采样为潜空间二值网格 (格中心采样 + 亮度阈值，
  /// 与官方 canvas nearest 采样 + alpha>155 阈值同效)
  static List<Uint8List> _latentGridOf(img.Image mask, int gridSize) {
    final lw = math.max(1, mask.width ~/ gridSize);
    final lh = math.max(1, mask.height ~/ gridSize);
    final grid = List.generate(lh, (_) => Uint8List(lw), growable: false);
    final half = gridSize ~/ 2;
    for (var ly = 0; ly < lh; ly++) {
      for (var lx = 0; lx < lw; lx++) {
        final px = (lx * gridSize + half).clamp(0, mask.width - 1);
        final py = (ly * gridSize + half).clamp(0, mask.height - 1);
        final pixel = mask.getPixel(px, py);
        grid[ly][lx] = pixel.r > 127 ? 1 : 0;
      }
    }
    return grid;
  }

  /// 潜空间网格四邻域膨胀
  static List<Uint8List> _dilateLatentGrid(
    List<Uint8List> grid,
    int iterations,
  ) {
    if (iterations <= 0) return grid;
    var cur = grid;
    final lh = cur.length;
    for (var it = 0; it < iterations; it++) {
      final lw = cur[0].length;
      final next = List.generate(
        lh,
        (y) => Uint8List.fromList(cur[y]),
        growable: false,
      );
      for (var y = 0; y < lh; y++) {
        for (var x = 0; x < lw; x++) {
          if (cur[y][x] == 1) continue;
          final up = y > 0 && cur[y - 1][x] == 1;
          final down = y + 1 < lh && cur[y + 1][x] == 1;
          final left = x > 0 && cur[y][x - 1] == 1;
          final right = x + 1 < lw && cur[y][x + 1] == 1;
          if (up || down || left || right) next[y][x] = 1;
        }
      }
      cur = next;
    }
    return cur;
  }

  /// 由潜空间网格构建请求尺寸二值蒙版 (整格涂白，量化后发给 API)
  static img.Image _gridToRequestMask(
    List<Uint8List> grid,
    int gridSize,
    int width,
    int height,
  ) {
    final mask = img.Image(width: width, height: height, numChannels: 4);
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));
    final white = img.ColorRgba8(255, 255, 255, 255);
    for (var y = 0; y < grid.length; y++) {
      final row = grid[y];
      for (var x = 0; x < row.length; x++) {
        if (row[x] == 0) continue;
        for (
          var py = y * gridSize;
          py < math.min((y + 1) * gridSize, height);
          py++
        ) {
          for (
            var px = x * gridSize;
            px < math.min((x + 1) * gridSize, width);
            px++
          ) {
            mask.setPixel(px, py, white);
          }
        }
      }
    }
    return mask;
  }

  /// 由膨胀后的潜空间网格构建客户端回贴合成蒙版：整格涂白 → 盒式模糊
  /// 羽化 → alpha 匹配亮度 (Aaalice _officialWorkerBlur + _alphaMatchRed)
  static img.Image _compositeMaskFromGrid(
    List<Uint8List> grid,
    int gridSize,
    int width,
    int height,
  ) {
    final mask = _gridToRequestMask(grid, gridSize, width, height);
    if (compositeBlurRadius > 0 && compositeBlurIterations > 0) {
      _boxBlur(
        mask,
        radius: compositeBlurRadius,
        iterations: compositeBlurIterations,
      );
    }
    // alpha 匹配亮度：蒙版亮度即回贴混合强度
    for (final pixel in mask) {
      pixel.a = pixel.r;
    }
    return mask;
  }

  /// 盒式模糊 (可分离 + 前缀和，O(1)/像素)，作用于 RGB 通道
  static void _boxBlur(
    img.Image image, {
    required int radius,
    required int iterations,
  }) {
    final w = image.width;
    final h = image.height;
    if (w <= 1 || h <= 1 || radius < 1) return;

    final tmp = img.Image(width: w, height: h, numChannels: 4);
    var src = image;
    var dst = tmp;

    for (var it = 0; it < iterations; it++) {
      // 水平通
      for (var y = 0; y < h; y++) {
        final sums = List<int>.filled(4, 0);
        // 初始窗口 [0, radius] (右缘钳制)
        for (var k = 0; k <= math.min(radius, w - 1); k++) {
          final p = src.getPixel(k, y);
          sums[0] += p.r.toInt();
          sums[1] += p.g.toInt();
          sums[2] += p.b.toInt();
        }
        var count = math.min(radius + 1, w);
        for (var x = 0; x < w; x++) {
          dst.setPixelRgba(
            x,
            y,
            sums[0] ~/ count,
            sums[1] ~/ count,
            sums[2] ~/ count,
            255,
          );
          final addX = x + radius + 1;
          if (addX < w) {
            final add = src.getPixel(addX, y);
            sums[0] += add.r.toInt();
            sums[1] += add.g.toInt();
            sums[2] += add.b.toInt();
            count++;
          }
          final removeX = x - radius;
          if (removeX >= 0) {
            final remove = src.getPixel(removeX, y);
            sums[0] -= remove.r.toInt();
            sums[1] -= remove.g.toInt();
            sums[2] -= remove.b.toInt();
            count--;
          }
        }
      }
      // 垂直通
      for (var x = 0; x < w; x++) {
        final sums = List<int>.filled(4, 0);
        for (var k = 0; k <= math.min(radius, h - 1); k++) {
          final p = dst.getPixel(x, k);
          sums[0] += p.r.toInt();
          sums[1] += p.g.toInt();
          sums[2] += p.b.toInt();
        }
        var count = math.min(radius + 1, h);
        for (var y = 0; y < h; y++) {
          src.setPixelRgba(
            x,
            y,
            sums[0] ~/ count,
            sums[1] ~/ count,
            sums[2] ~/ count,
            255,
          );
          final addY = y + radius + 1;
          if (addY < h) {
            final add = dst.getPixel(x, addY);
            sums[0] += add.r.toInt();
            sums[1] += add.g.toInt();
            sums[2] += add.b.toInt();
            count++;
          }
          final removeY = y - radius;
          if (removeY >= 0) {
            final remove = dst.getPixel(x, removeY);
            sums[0] -= remove.r.toInt();
            sums[1] -= remove.g.toInt();
            sums[2] -= remove.b.toInt();
            count--;
          }
        }
      }
    }
  }

  /// 把请求尺寸蒙版量化到潜空间网格后重建 (发给官方 API 的最终蒙版)
  static img.Image quantizeMaskToLatentGrid(
    img.Image requestMask, {
    int gridSize = latentGridSize,
  }) {
    if (gridSize <= 1) return requestMask;
    final grid = _latentGridOf(requestMask, gridSize);
    return _gridToRequestMask(
      grid,
      gridSize,
      requestMask.width,
      requestMask.height,
    );
  }

  // ---------------------------------------------------------------------------
  // 请求准备
  // ---------------------------------------------------------------------------

  /// 准备焦点特写请求所需的裁剪原图与遮罩数据 (PNG 字节流)
  ///
  /// [sourceMask] 为源图尺寸二值蒙版 (白 = 重绘)；为空时按几何默认选区构建。
  static ({Uint8List sourceBytes, Uint8List maskBytes})
  prepareFocusedRequestData({
    required Uint8List sourceImageBytes,
    required InpaintGeometry geometry,
    img.Image? sourceMask,
  }) {
    final decodedSource = img.decodeImage(sourceImageBytes);
    if (decodedSource == null) {
      throw StateError('无法解码原图进行焦点裁剪。');
    }

    final crop = _cropRectFor(decodedSource, geometry.contextCrop);

    // 1. 裁剪原图上下文区域并放大至请求尺寸
    final croppedSource = img.copyCrop(
      decodedSource,
      x: crop.x,
      y: crop.y,
      width: crop.width,
      height: crop.height,
    );
    final resizedSource = img.copyResize(
      croppedSource,
      width: geometry.requestWidth,
      height: geometry.requestHeight,
      interpolation: img.Interpolation.cubic,
    );

    // 2. 遮罩：源图蒙版裁剪缩放至请求尺寸；缺省时按几何选区绘制
    final img.Image requestMask;
    if (sourceMask != null &&
        sourceMask.width == decodedSource.width &&
        sourceMask.height == decodedSource.height) {
      final croppedMask = img.copyCrop(
        sourceMask,
        x: crop.x,
        y: crop.y,
        width: crop.width,
        height: crop.height,
      );
      requestMask = img.copyResize(
        croppedMask,
        width: geometry.requestWidth,
        height: geometry.requestHeight,
        interpolation: img.Interpolation.nearest,
      );
    } else {
      requestMask = _buildDefaultFocusMask(geometry);
    }

    return (
      sourceBytes: Uint8List.fromList(img.encodePng(resizedSource, level: 1)),
      maskBytes: Uint8List.fromList(
        img.encodePng(
          // 发给官方 API 的蒙版必须量化到 8px 潜空间网格 (与网页端一致)
          quantizeMaskToLatentGrid(requestMask),
          level: 1,
        ),
      ),
    );
  }

  /// 构建焦点选区对应的二值遮罩 (黑底白块)
  static img.Image _buildDefaultFocusMask(InpaintGeometry geometry) {
    final mask = img.Image(
      width: geometry.requestWidth,
      height: geometry.requestHeight,
      numChannels: 4,
    );
    // 默认全黑 (非修复区域)
    img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));

    final relLeft =
        (geometry.focusBounds.left - geometry.contextCrop.left) /
        geometry.contextCrop.width;
    final relTop =
        (geometry.focusBounds.top - geometry.contextCrop.top) /
        geometry.contextCrop.height;
    final relW = geometry.focusBounds.width / geometry.contextCrop.width;
    final relH = geometry.focusBounds.height / geometry.contextCrop.height;

    final maskX = (relLeft * geometry.requestWidth).round().clamp(
      0,
      geometry.requestWidth - 1,
    );
    final maskY = (relTop * geometry.requestHeight).round().clamp(
      0,
      geometry.requestHeight - 1,
    );
    final maskW = (relW * geometry.requestWidth).round().clamp(
      1,
      geometry.requestWidth - maskX,
    );
    final maskH = (relH * geometry.requestHeight).round().clamp(
      1,
      geometry.requestHeight - maskY,
    );

    img.fillRect(
      mask,
      x1: maskX,
      y1: maskY,
      x2: maskX + maskW,
      y2: maskY + maskH,
      color: img.ColorRgba8(255, 255, 255, 255),
    );

    return mask;
  }

  /// 准备常规全图 Inpaint 请求数据
  ///
  /// [sourceMask] 为源图尺寸蒙版；缺省时整图全白 (整图重绘)。
  static ({Uint8List sourceBytes, Uint8List maskBytes})
  prepareStandardRequestData({
    required Uint8List sourceImageBytes,
    required int requestWidth,
    required int requestHeight,
    img.Image? sourceMask,
  }) {
    final decodedSource = img.decodeImage(sourceImageBytes);
    if (decodedSource == null) {
      throw StateError('无法解码原图进行常规重绘。');
    }

    final resizedSource =
        (decodedSource.width == requestWidth &&
            decodedSource.height == requestHeight)
        ? decodedSource
        : img.copyResize(
            decodedSource,
            width: requestWidth,
            height: requestHeight,
            interpolation: img.Interpolation.cubic,
          );

    final img.Image requestMask;
    if (sourceMask != null && sourceMask.width == decodedSource.width) {
      requestMask = img.copyResize(
        sourceMask,
        width: requestWidth,
        height: requestHeight,
        interpolation: img.Interpolation.nearest,
      );
    } else {
      requestMask = img.Image(
        width: requestWidth,
        height: requestHeight,
        numChannels: 4,
      );
      img.fill(requestMask, color: img.ColorRgba8(255, 255, 255, 255));
    }

    return (
      sourceBytes: Uint8List.fromList(img.encodePng(resizedSource, level: 1)),
      maskBytes: Uint8List.fromList(
        img.encodePng(
          // 发给官方 API 的蒙版必须量化到 8px 潜空间网格 (与网页端一致)
          quantizeMaskToLatentGrid(requestMask),
          level: 1,
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 结果回贴合成
  // ---------------------------------------------------------------------------

  /// 解码蒙版 PNG 字节，失败时返回 null (调用方回退整块回贴)
  static img.Image? decodeMaskOrNull(Uint8List bytes) {
    try {
      return img.decodeImage(bytes);
    } catch (_) {
      return null;
    }
  }

  /// 将 NovelAI infill 生成的焦点特写补丁等比缩放并按合成蒙版无损贴回原图
  /// (对齐 Aaalice FocusedInpaintRequest.composeGeneratedImageArtifact)。
  ///
  /// 官方流程：请求蒙版已量化到 8px 潜空间网格；服务端实际重绘区 =
  /// 量化网格。客户端回贴合成蒙版 = 量化网格再膨胀 4 格 + 盒式模糊，
  /// 保证服务端重绘过的每个像素都被生成补丁覆盖 (否则量化多出的格子
  /// 边缘会残留原图像素，表现为「贴不回去」)，羽化边缘避免硬接缝。
  static Uint8List compositeFocusedResult({
    required Uint8List originalSourceBytes,
    required Uint8List generatedPatchBytes,
    required InpaintGeometry geometry,
    img.Image? sourceMask,
  }) {
    final originalSource = img.decodeImage(originalSourceBytes);
    final generatedPatch = img.decodeImage(generatedPatchBytes);
    if (originalSource == null || generatedPatch == null) {
      return generatedPatchBytes;
    }

    final crop = _cropRectFor(originalSource, geometry.contextCrop);
    final targetW = crop.width;
    final targetH = crop.height;

    // 1. 生成补丁归一到请求尺寸 (服务端一般原尺寸返回，此处仅兜底)
    final requestPatch =
        (generatedPatch.width == geometry.requestWidth &&
            generatedPatch.height == geometry.requestHeight)
        ? generatedPatch
        : img.copyResize(
            generatedPatch,
            width: geometry.requestWidth,
            height: geometry.requestHeight,
            interpolation: img.Interpolation.cubic,
          );

    final result = img.Image.from(originalSource, noAnimation: true);

    final bool maskValid =
        sourceMask != null &&
        sourceMask.width == originalSource.width &&
        sourceMask.height == originalSource.height;

    if (maskValid) {
      // 2. 与请求准备同口径：源图蒙版裁剪缩放到请求尺寸
      final croppedMask = img.copyCrop(
        sourceMask,
        x: crop.x,
        y: crop.y,
        width: targetW,
        height: targetH,
      );
      final requestMask = img.copyResize(
        croppedMask,
        width: geometry.requestWidth,
        height: geometry.requestHeight,
        interpolation: img.Interpolation.nearest,
      );

      // 3. 量化到潜空间网格 → 膨胀 4 格 → 模糊羽化 → alpha 即混合强度
      final grid = _latentGridOf(requestMask, latentGridSize);
      final dilated = _dilateLatentGrid(grid, latentDilationIterations);
      final compositeMask = _compositeMaskFromGrid(
        dilated,
        latentGridSize,
        geometry.requestWidth,
        geometry.requestHeight,
      );

      // 4. 请求尺寸补丁：RGB 取生成图，alpha 取合成蒙版
      final maskedPatch = img.Image(
        width: geometry.requestWidth,
        height: geometry.requestHeight,
        numChannels: 4,
      );
      for (var y = 0; y < maskedPatch.height; y++) {
        for (var x = 0; x < maskedPatch.width; x++) {
          final gen = requestPatch.getPixel(x, y);
          final alpha = compositeMask.getPixel(x, y).a;
          maskedPatch.setPixelRgba(
            x,
            y,
            gen.r.toInt(),
            gen.g.toInt(),
            gen.b.toInt(),
            alpha,
          );
        }
      }

      // 5. 缩回裁剪框尺寸后以 alpha 混合盖回原图
      final cropPatch =
          (maskedPatch.width == targetW && maskedPatch.height == targetH)
          ? maskedPatch
          : img.copyResize(
              maskedPatch,
              width: targetW,
              height: targetH,
              interpolation: img.Interpolation.cubic,
            );
      img.compositeImage(
        result,
        cropPatch,
        dstX: crop.x,
        dstY: crop.y,
        blend: img.BlendMode.alpha,
      );
    } else {
      // 无蒙版：整块裁剪区域回贴 (保持旧行为兜底)
      final resizedPatch =
          (requestPatch.width == targetW && requestPatch.height == targetH)
          ? requestPatch
          : img.copyResize(
              requestPatch,
              width: targetW,
              height: targetH,
              interpolation: img.Interpolation.cubic,
            );
      img.compositeImage(
        result,
        resizedPatch,
        dstX: crop.x,
        dstY: crop.y,
        blend: img.BlendMode.direct,
      );
    }

    return Uint8List.fromList(img.encodePng(result));
  }

  /// 将常规 Inpaint 生成结果按蒙版与原图混合
  static Uint8List compositeStandardResult({
    required Uint8List originalSourceBytes,
    required Uint8List generatedImageBytes,
    required Uint8List maskBytes,
  }) {
    final originalSource = img.decodeImage(originalSourceBytes);
    final generated = img.decodeImage(generatedImageBytes);
    final mask = img.decodeImage(maskBytes);

    if (originalSource == null || generated == null || mask == null) {
      return generatedImageBytes;
    }

    final resizedGen =
        (generated.width == originalSource.width &&
            generated.height == originalSource.height)
        ? generated
        : img.copyResize(
            generated,
            width: originalSource.width,
            height: originalSource.height,
            interpolation: img.Interpolation.cubic,
          );

    final resizedMask =
        (mask.width == originalSource.width &&
            mask.height == originalSource.height)
        ? mask
        : img.copyResize(
            mask,
            width: originalSource.width,
            height: originalSource.height,
            interpolation: img.Interpolation.nearest,
          );

    final result = img.Image.from(originalSource, noAnimation: true);
    img.compositeImage(
      result,
      resizedGen,
      dstX: 0,
      dstY: 0,
      mask: resizedMask,
      blend: img.BlendMode.direct,
    );

    return Uint8List.fromList(img.encodePng(result));
  }

  // ---------------------------------------------------------------------------
  // 内部辅助
  // ---------------------------------------------------------------------------

  /// 把 contextCrop 钳制到解码图实际尺寸并取整 (解码图可能小于几何假设)
  static ({int x, int y, int width, int height}) _cropRectFor(
    img.Image decoded,
    Rect cropRect,
  ) {
    final x = cropRect.left.round().clamp(0, decoded.width - 1);
    final y = cropRect.top.round().clamp(0, decoded.height - 1);
    final w = cropRect.width.round().clamp(1, decoded.width - x);
    final h = cropRect.height.round().clamp(1, decoded.height - y);
    return (x: x, y: y, width: w, height: h);
  }

  static int _floorToGrid(int value) {
    return math.max(dimensionStep, (value ~/ dimensionStep) * dimensionStep);
  }

  static int _roundToGrid(int value) {
    return math.max(
      dimensionStep,
      ((value + dimensionStep ~/ 2) ~/ dimensionStep) * dimensionStep,
    );
  }

  static int _largestGridDimensionForArea(int areaLimit, int otherDimension) {
    if (otherDimension <= 0) return dimensionStep;
    final gridUnits = areaLimit ~/ otherDimension ~/ dimensionStep;
    return math.max(dimensionStep, gridUnits * dimensionStep);
  }
}
