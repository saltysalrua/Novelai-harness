import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Rect;
import '../models/inpaint_models.dart';
import 'isolated_compute.dart';
import 'rgba_pixel_ops.dart';
import 'skia_image_codec.dart';

/// Inpaint 与 Focus Inpaint 图像处理服务引擎
///
/// 包含：
/// 1. 焦点特写外延几何计算 (对齐 1MP 潜空间与 64 步长网格)
/// 2. 画笔描边 / 矩形选区 → 源图尺寸二值蒙版栅格化
/// 3. 请求裁剪与等比超采样重编码
/// 4. 生成补丁按蒙版无损回贴合成流水线 (外延上下文环保留原图像素)
///
/// 图像编解码统一走 [decodeToRawRgba] / [encodeRawRgbaToPng] (Skia，
/// 仅根 isolate)；像素运算层保持纯 Dart，操作对象为 flat RGBA 字节
/// (像素下标 `(y * width + x) * 4`，无隐式 alpha 语义)。
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
  static RawRgbaImage buildSourceMask({
    required int sourceWidth,
    required int sourceHeight,
    List<InpaintBrushStroke> brushStrokes = const [],
    Rect? selectionRect,
  }) {
    final buf = _newBlackMaskBuffer(sourceWidth, sourceHeight);

    // 仅当存在非橡皮描边 (正向蒙版) 时才走描边栅格化；全部描边都被
    // 橡皮抵消时回退到矩形选区，避免拿着全黑蒙版自欺欺人地请求一次
    // 什么都不重绘的生成
    if (brushStrokes.any((s) => !s.isEraser && s.points.isNotEmpty)) {
      _paintStrokes(buf, sourceWidth, sourceHeight, brushStrokes);
      return RawRgbaImage(rgba: buf, width: sourceWidth, height: sourceHeight);
    }

    if (selectionRect == null) {
      // 整图重绘 (常规模式默认行为)
      _fillRectWhite(buf, sourceWidth, 0, 0, sourceWidth, sourceHeight);
      return RawRgbaImage(rgba: buf, width: sourceWidth, height: sourceHeight);
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
    _fillRectWhite(buf, sourceWidth, l, t, w, h);
    return RawRgbaImage(rgba: buf, width: sourceWidth, height: sourceHeight);
  }

  /// 将画笔描边按提交顺序栅格化进蒙版：正向描边盖章白色 (待重绘)，
  /// 反向橡皮描边盖章黑色 (抵消先前笔迹，后画优先)
  static void _paintStrokes(
    Uint8List buf,
    int width,
    int height,
    List<InpaintBrushStroke> strokes,
  ) {
    final shortSide = math.min(width, height).toDouble();
    for (final stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final white = !stroke.isEraser;
      final r = (stroke.radius * shortSide).round().clamp(1, 512);
      for (final p in stroke.points) {
        _stampCircle(
          buf,
          width,
          height,
          cx: (p.dx * width).round(),
          cy: (p.dy * height).round(),
          radius: r,
          white: white,
        );
      }
    }
  }

  /// 栅格化描边并计算剩余白色蒙版的归一化包围盒。
  ///
  /// **仅在描边提交时调用 (非实时)**：在 256x256 低分辨率画布上按提交顺序
  /// 回放全部描边 (橡皮打黑抵消先前笔迹，与 [buildSourceMask] 同规则)，
  /// 再扫描白色像素取包围盒。用于橡皮擦除后收缩生效选区/外延裁剪框。
  ///
  /// 方形画布下圆点在归一化坐标系呈正圆，与实际宽高比下的椭圆包围盒
  /// 偏差不超过笔刷半径，对带 contextPadding 的裁剪框估算无影响。
  ///
  /// 返回值：无正向描边返回 null；有正向描边但全被橡皮擦掉返回
  /// [Rect.zero] (调用方应回退矩形选区，与 buildSourceMask 语义一致)。
  static Rect? computeStrokeMaskBounds(List<InpaintBrushStroke> strokes) {
    if (!strokes.any((s) => !s.isEraser && s.points.isNotEmpty)) {
      return null;
    }
    const size = 256;
    final buf = _newBlackMaskBuffer(size, size);
    _paintStrokes(buf, size, size, strokes);

    var minX = size;
    var minY = size;
    var maxX = -1;
    var maxY = -1;
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        if (buf[(y * size + x) * 4] > 127) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }
    if (maxX < 0) return Rect.zero;
    return Rect.fromLTWH(
      minX / size,
      minY / size,
      (maxX - minX + 1) / size,
      (maxY - minY + 1) / size,
    );
  }

  static void _stampCircle(
    Uint8List buf,
    int width,
    int height, {
    required int cx,
    required int cy,
    required int radius,
    required bool white,
  }) {
    final rSq = radius * radius;
    final x0 = (cx - radius).clamp(0, width - 1);
    final x1 = (cx + radius).clamp(0, width - 1);
    final y0 = (cy - radius).clamp(0, height - 1);
    final y1 = (cy + radius).clamp(0, height - 1);
    final v = white ? 255 : 0;
    for (var y = y0; y <= y1; y++) {
      for (var x = x0; x <= x1; x++) {
        final dx = x - cx;
        final dy = y - cy;
        if (dx * dx + dy * dy <= rSq) {
          final i = (y * width + x) * 4;
          buf[i] = v;
          buf[i + 1] = v;
          buf[i + 2] = v;
          // alpha 恒为 255，不参与蒙版语义
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
  static List<Uint8List> _latentGridOf(RawRgbaImage mask, int gridSize) {
    final lw = math.max(1, mask.width ~/ gridSize);
    final lh = math.max(1, mask.height ~/ gridSize);
    final grid = List.generate(lh, (_) => Uint8List(lw), growable: false);
    final half = gridSize ~/ 2;
    for (var ly = 0; ly < lh; ly++) {
      for (var lx = 0; lx < lw; lx++) {
        final px = (lx * gridSize + half).clamp(0, mask.width - 1);
        final py = (ly * gridSize + half).clamp(0, mask.height - 1);
        grid[ly][lx] = mask.rgba[mask.offsetOf(px, py)] > 127 ? 1 : 0;
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
  static RawRgbaImage _gridToRequestMask(
    List<Uint8List> grid,
    int gridSize,
    int width,
    int height,
  ) {
    final buf = _newBlackMaskBuffer(width, height);
    for (var y = 0; y < grid.length; y++) {
      final row = grid[y];
      for (var x = 0; x < row.length; x++) {
        if (row[x] == 0) continue;
        _fillRectWhite(
          buf,
          width,
          x * gridSize,
          y * gridSize,
          math.min(gridSize, width - x * gridSize),
          math.min(gridSize, height - y * gridSize),
        );
      }
    }
    return RawRgbaImage(rgba: buf, width: width, height: height);
  }

  /// 由膨胀后的潜空间网格构建客户端回贴合成蒙版：整格涂白 → 盒式模糊
  /// 羽化 → alpha 匹配亮度 (Aaalice _officialWorkerBlur + _alphaMatchRed)
  static RawRgbaImage _compositeMaskFromGrid(
    List<Uint8List> grid,
    int gridSize,
    int width,
    int height,
  ) {
    final mask = _gridToRequestMask(grid, gridSize, width, height);
    if (compositeBlurRadius > 0 && compositeBlurIterations > 0) {
      _boxBlurRgba(
        mask.rgba,
        width,
        height,
        radius: compositeBlurRadius,
        iterations: compositeBlurIterations,
      );
    }
    // alpha 匹配亮度：蒙版亮度即回贴混合强度
    for (var i = 0; i < mask.rgba.length; i += 4) {
      mask.rgba[i + 3] = mask.rgba[i];
    }
    return mask;
  }

  /// 盒式模糊 (可分离 + 滑窗，O(1)/像素)，作用于 RGB 通道，alpha 恒写 255
  static void _boxBlurRgba(
    Uint8List buf,
    int width,
    int height, {
    required int radius,
    required int iterations,
  }) {
    if (width <= 1 || height <= 1 || radius < 1) return;

    final tmp = Uint8List(width * height * 4);

    for (var it = 0; it < iterations; it++) {
      // 水平通：读 buf 写 tmp
      for (var y = 0; y < height; y++) {
        var sumR = 0, sumG = 0, sumB = 0;
        // 初始窗口 [0, radius] (右缘钳制)
        final initCount = math.min(radius + 1, width);
        for (var k = 0; k < initCount; k++) {
          final i = (y * width + k) * 4;
          sumR += buf[i];
          sumG += buf[i + 1];
          sumB += buf[i + 2];
        }
        var count = initCount;
        for (var x = 0; x < width; x++) {
          final d = (y * width + x) * 4;
          tmp[d] = (sumR ~/ count).clamp(0, 255);
          tmp[d + 1] = (sumG ~/ count).clamp(0, 255);
          tmp[d + 2] = (sumB ~/ count).clamp(0, 255);
          tmp[d + 3] = 255;
          final addX = x + radius + 1;
          if (addX < width) {
            final a = (y * width + addX) * 4;
            sumR += buf[a];
            sumG += buf[a + 1];
            sumB += buf[a + 2];
            count++;
          }
          final removeX = x - radius;
          if (removeX >= 0) {
            final r = (y * width + removeX) * 4;
            sumR -= buf[r];
            sumG -= buf[r + 1];
            sumB -= buf[r + 2];
            count--;
          }
        }
      }
      // 垂直通：读 tmp 写 buf
      for (var x = 0; x < width; x++) {
        var sumR = 0, sumG = 0, sumB = 0;
        final initCount = math.min(radius + 1, height);
        for (var k = 0; k < initCount; k++) {
          final i = (k * width + x) * 4;
          sumR += tmp[i];
          sumG += tmp[i + 1];
          sumB += tmp[i + 2];
        }
        var count = initCount;
        for (var y = 0; y < height; y++) {
          final d = (y * width + x) * 4;
          buf[d] = (sumR ~/ count).clamp(0, 255);
          buf[d + 1] = (sumG ~/ count).clamp(0, 255);
          buf[d + 2] = (sumB ~/ count).clamp(0, 255);
          buf[d + 3] = 255;
          final addY = y + radius + 1;
          if (addY < height) {
            final a = (addY * width + x) * 4;
            sumR += tmp[a];
            sumG += tmp[a + 1];
            sumB += tmp[a + 2];
            count++;
          }
          final removeY = y - radius;
          if (removeY >= 0) {
            final r = (removeY * width + x) * 4;
            sumR -= tmp[r];
            sumG -= tmp[r + 1];
            sumB -= tmp[r + 2];
            count--;
          }
        }
      }
    }
  }

  /// 把请求尺寸蒙版量化到潜空间网格后重建 (发给官方 API 的最终蒙版)
  static RawRgbaImage quantizeMaskToLatentGrid(
    RawRgbaImage requestMask, {
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
  static Future<({Uint8List sourceBytes, Uint8List maskBytes})>
  prepareFocusedRequestData({
    required Uint8List sourceImageBytes,
    required InpaintGeometry geometry,
    RawRgbaImage? sourceMask,
  }) async {
    final decodedSource = await decodeToRawRgba(sourceImageBytes);
    if (decodedSource == null) {
      throw StateError('无法解码原图进行焦点裁剪。');
    }

    final crop = _cropRectFor(
      decodedSource.width,
      decodedSource.height,
      geometry.contextCrop,
    );

    // 1. 裁剪原图上下文区域并放大至请求尺寸
    final croppedRgba = cropRgba(
      decodedSource.rgba,
      decodedSource.width,
      crop.x,
      crop.y,
      crop.width,
      crop.height,
    );
    final resizedRgba = resizeRgbaCubic(
      croppedRgba,
      crop.width,
      crop.height,
      geometry.requestWidth,
      geometry.requestHeight,
    );

    // 2. 遮罩：源图蒙版裁剪缩放至请求尺寸；缺省时按几何选区绘制
    final Uint8List requestMaskRgba;
    if (sourceMask != null &&
        sourceMask.width == decodedSource.width &&
        sourceMask.height == decodedSource.height) {
      final croppedMask = cropRgba(
        sourceMask.rgba,
        sourceMask.width,
        crop.x,
        crop.y,
        crop.width,
        crop.height,
      );
      requestMaskRgba = resizeRgbaNearest(
        croppedMask,
        crop.width,
        crop.height,
        geometry.requestWidth,
        geometry.requestHeight,
      );
    } else {
      requestMaskRgba = _defaultFocusMaskRgba(geometry);
    }

    // 发给官方 API 的蒙版必须量化到 8px 潜空间网格 (与网页端一致)
    final quantizedMask = quantizeMaskToLatentGrid(
      RawRgbaImage(
        rgba: requestMaskRgba,
        width: geometry.requestWidth,
        height: geometry.requestHeight,
      ),
    );

    return (
      sourceBytes: await encodeRawRgbaToPng(
        resizedRgba,
        geometry.requestWidth,
        geometry.requestHeight,
      ),
      maskBytes: await encodeRawRgbaToPng(
        quantizedMask.rgba,
        geometry.requestWidth,
        geometry.requestHeight,
      ),
    );
  }

  /// 构建焦点选区对应的二值遮罩 (黑底白块)
  static Uint8List _defaultFocusMaskRgba(InpaintGeometry geometry) {
    final buf = _newBlackMaskBuffer(
      geometry.requestWidth,
      geometry.requestHeight,
    );
    // 默认全黑 (非修复区域)

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

    _fillRectWhite(buf, geometry.requestWidth, maskX, maskY, maskW, maskH);
    return buf;
  }

  /// 准备常规全图 Inpaint 请求数据
  ///
  /// [sourceMask] 为源图尺寸蒙版；缺省时整图全白 (整图重绘)。
  static Future<({Uint8List sourceBytes, Uint8List maskBytes})>
  prepareStandardRequestData({
    required Uint8List sourceImageBytes,
    required int requestWidth,
    required int requestHeight,
    RawRgbaImage? sourceMask,
  }) async {
    final decodedSource = await decodeToRawRgba(sourceImageBytes);
    if (decodedSource == null) {
      throw StateError('无法解码原图进行常规重绘。');
    }

    final resizedRgba =
        (decodedSource.width == requestWidth &&
            decodedSource.height == requestHeight)
        ? decodedSource.rgba
        : resizeRgbaCubic(
            decodedSource.rgba,
            decodedSource.width,
            decodedSource.height,
            requestWidth,
            requestHeight,
          );

    final Uint8List requestMaskRgba;
    if (sourceMask != null && sourceMask.width == decodedSource.width) {
      requestMaskRgba = resizeRgbaNearest(
        sourceMask.rgba,
        sourceMask.width,
        sourceMask.height,
        requestWidth,
        requestHeight,
      );
    } else {
      requestMaskRgba = _newWhiteMaskBuffer(requestWidth, requestHeight);
    }

    // 发给官方 API 的蒙版必须量化到 8px 潜空间网格 (与网页端一致)
    final quantizedMask = quantizeMaskToLatentGrid(
      RawRgbaImage(
        rgba: requestMaskRgba,
        width: requestWidth,
        height: requestHeight,
      ),
    );

    return (
      sourceBytes: await encodeRawRgbaToPng(
        resizedRgba,
        requestWidth,
        requestHeight,
      ),
      maskBytes: await encodeRawRgbaToPng(
        quantizedMask.rgba,
        requestWidth,
        requestHeight,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 结果回贴合成
  // ---------------------------------------------------------------------------

  /// 解码蒙版 PNG 字节，失败时返回 null (调用方回退整块回贴)
  static Future<RawRgbaImage?> decodeMaskOrNull(Uint8List bytes) =>
      decodeToRawRgba(bytes);

  /// 将 NovelAI infill 生成的焦点特写补丁等比缩放并按合成蒙版无损贴回原图
  /// (对齐 Aaalice FocusedInpaintRequest.composeGeneratedImageArtifact)。
  ///
  /// 官方流程：请求蒙版已量化到 8px 潜空间网格；服务端实际重绘区 =
  /// 量化网格。客户端回贴合成蒙版 = 量化网格再膨胀 4 格 + 盒式模糊，
  /// 保证服务端重绘过的每个像素都被生成补丁覆盖 (否则量化多出的格子
  /// 边缘会残留原图像素，表现为「贴不回去」)，羽化边缘避免硬接缝。
  static Future<Uint8List> compositeFocusedResult({
    required Uint8List originalSourceBytes,
    required Uint8List generatedPatchBytes,
    required InpaintGeometry geometry,
    RawRgbaImage? sourceMask,
  }) async {
    final originalSource = await decodeToRawRgba(originalSourceBytes);
    final generatedPatch = await decodeToRawRgba(generatedPatchBytes);
    if (originalSource == null || generatedPatch == null) {
      return generatedPatchBytes;
    }

    final crop = _cropRectFor(
      originalSource.width,
      originalSource.height,
      geometry.contextCrop,
    );
    final outRgba = await runIsolated(
      _compositeFocusedIsolate,
      _FocusedCompositeTask(
        orig: IsolateBytes(originalSource.rgba),
        origWidth: originalSource.width,
        origHeight: originalSource.height,
        patch: IsolateBytes(generatedPatch.rgba),
        patchWidth: generatedPatch.width,
        patchHeight: generatedPatch.height,
        requestWidth: geometry.requestWidth,
        requestHeight: geometry.requestHeight,
        cropX: crop.x,
        cropY: crop.y,
        mask:
            (sourceMask != null &&
                sourceMask.width == originalSource.width &&
                sourceMask.height == originalSource.height)
            ? IsolateBytes(sourceMask.rgba)
            : null,
        maskWidth: sourceMask?.width,
        maskHeight: sourceMask?.height,
      ),
    );
    return encodeRawRgbaToPng(
      outRgba.materialize(),
      originalSource.width,
      originalSource.height,
    );
  }

  /// 焦点回贴纯像素合成 (compute isolate 执行)：
  /// 蒙版量化 → 膨胀 → 羽化 → alpha 混合盖回原图
  static IsolateBytes _compositeFocusedIsolate(_FocusedCompositeTask task) {
    return IsolateBytes(_compositeFocusedPixels(task));
  }

  static Uint8List _compositeFocusedPixels(_FocusedCompositeTask task) {
    final origRgba = task.orig.materialize();
    final patchRgba = task.patch.materialize();
    final maskRgba = task.mask?.materialize();
    final origW = task.origWidth;
    final origH = task.origHeight;
    final reqW = task.requestWidth;
    final reqH = task.requestHeight;

    final cropX = task.cropX.clamp(0, math.max(0, origW - 1)).toInt();
    final cropY = task.cropY.clamp(0, math.max(0, origH - 1)).toInt();
    final targetW = (origW - cropX).clamp(1, origW).toInt();
    final targetH = (origH - cropY).clamp(1, origH).toInt();

    // 1. 生成补丁归一到请求尺寸 (服务端一般原尺寸返回，此处仅兜底)
    final requestPatchRgba =
        (task.patchWidth == reqW && task.patchHeight == reqH)
        ? patchRgba
        : resizeRgbaCubic(
            patchRgba,
            task.patchWidth,
            task.patchHeight,
            reqW,
            reqH,
          );

    final out = Uint8List.fromList(origRgba);

    final maskValid =
        maskRgba != null && task.maskWidth == origW && task.maskHeight == origH;

    if (maskValid) {
      // 2. 与请求准备同口径：源图蒙版裁剪缩放到请求尺寸
      final croppedMask = cropRgba(
        maskRgba,
        task.maskWidth!,
        cropX,
        cropY,
        targetW,
        targetH,
      );
      final requestMaskRgba = resizeRgbaNearest(
        croppedMask,
        targetW,
        targetH,
        reqW,
        reqH,
      );

      // 3. 量化到潜空间网格 → 膨胀 4 格 → 模糊羽化 → alpha 即混合强度
      final grid = _latentGridOf(
        RawRgbaImage(rgba: requestMaskRgba, width: reqW, height: reqH),
        latentGridSize,
      );
      final dilated = _dilateLatentGrid(grid, latentDilationIterations);
      final compositeMask = _compositeMaskFromGrid(
        dilated,
        latentGridSize,
        reqW,
        reqH,
      );

      // 4. 请求尺寸补丁：RGB 取生成图，alpha 取合成蒙版
      final maskedPatch = Uint8List(reqW * reqH * 4);
      for (var i = 0; i < maskedPatch.length; i += 4) {
        maskedPatch[i] = requestPatchRgba[i];
        maskedPatch[i + 1] = requestPatchRgba[i + 1];
        maskedPatch[i + 2] = requestPatchRgba[i + 2];
        maskedPatch[i + 3] = compositeMask.rgba[i + 3];
      }

      // 5. 缩回裁剪框尺寸后以 alpha 混合盖回原图
      final cropPatchRgba = (reqW == targetW && reqH == targetH)
          ? maskedPatch
          : resizeRgbaCubic(maskedPatch, reqW, reqH, targetW, targetH);
      blendAlphaRect(
        out,
        origW,
        origH,
        cropPatchRgba,
        targetW,
        targetH,
        dstX: cropX,
        dstY: cropY,
      );
    } else {
      // 无蒙版：整块裁剪区域回贴 (保持旧行为兜底，direct 整像素替换)
      final resizedPatchRgba =
          (task.patchWidth == targetW && task.patchHeight == targetH)
          ? patchRgba
          : resizeRgbaCubic(
              requestPatchRgba,
              (task.patchWidth == reqW && task.patchHeight == reqH)
                  ? reqW
                  : task.patchWidth,
              (task.patchWidth == reqW && task.patchHeight == reqH)
                  ? reqH
                  : task.patchHeight,
              targetW,
              targetH,
            );
      copyRect(
        out,
        origW,
        origH,
        resizedPatchRgba,
        targetW,
        targetH,
        dstX: cropX,
        dstY: cropY,
      );
    }

    return out;
  }

  /// 将常规 Inpaint 生成结果按蒙版与原图混合
  static Future<Uint8List> compositeStandardResult({
    required Uint8List originalSourceBytes,
    required Uint8List generatedImageBytes,
    required Uint8List maskBytes,
  }) async {
    final originalSource = await decodeToRawRgba(originalSourceBytes);
    final generated = await decodeToRawRgba(generatedImageBytes);
    final mask = await decodeToRawRgba(maskBytes);

    if (originalSource == null || generated == null || mask == null) {
      return generatedImageBytes;
    }

    final outRgba = await runIsolated(
      _compositeStandardIsolate,
      _StandardCompositeTask(
        orig: IsolateBytes(originalSource.rgba),
        width: originalSource.width,
        height: originalSource.height,
        gen: IsolateBytes(generated.rgba),
        genWidth: generated.width,
        genHeight: generated.height,
        mask: IsolateBytes(mask.rgba),
        maskWidth: mask.width,
        maskHeight: mask.height,
      ),
    );
    return encodeRawRgbaToPng(
      outRgba.materialize(),
      originalSource.width,
      originalSource.height,
    );
  }

  /// 常规回贴纯像素合成 (compute isolate 执行)：
  /// 按蒙版亮度做 alpha 混合 (m==1 整像素替换，0<m<1 线性 lerp)
  static IsolateBytes _compositeStandardIsolate(_StandardCompositeTask task) {
    return IsolateBytes(_compositeStandardPixels(task));
  }

  static Uint8List _compositeStandardPixels(_StandardCompositeTask task) {
    final origRgba = task.orig.materialize();
    final genRgba = task.gen.materialize();
    final maskRgba = task.mask.materialize();
    final w = task.width;
    final h = task.height;

    final resizedGen = (task.genWidth == w && task.genHeight == h)
        ? genRgba
        : resizeRgbaCubic(genRgba, task.genWidth, task.genHeight, w, h);

    final resizedMask = (task.maskWidth == w && task.maskHeight == h)
        ? maskRgba
        : resizeRgbaNearest(maskRgba, task.maskWidth, task.maskHeight, w, h);

    final out = Uint8List.fromList(origRgba);
    for (var i = 0; i < w * h * 4; i += 4) {
      final m =
          (0.299 * resizedMask[i] +
              0.587 * resizedMask[i + 1] +
              0.114 * resizedMask[i + 2]) /
          255.0;
      if (m <= 0) continue;
      if (m >= 1.0) {
        out[i] = resizedGen[i];
        out[i + 1] = resizedGen[i + 1];
        out[i + 2] = resizedGen[i + 2];
        out[i + 3] = resizedGen[i + 3];
        continue;
      }
      for (var c = 0; c < 4; c++) {
        out[i + c] = (out[i + c] * (1 - m) + resizedGen[i + c] * m)
            .round()
            .clamp(0, 255);
      }
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Flat RGBA 像素运算
  // ---------------------------------------------------------------------------

  /// 黑底不透明蒙版缓冲 (RGB=0, A=255)
  static Uint8List _newBlackMaskBuffer(int width, int height) {
    final buf = Uint8List(width * height * 4);
    for (var i = 3; i < buf.length; i += 4) {
      buf[i] = 255;
    }
    return buf;
  }

  /// 全白不透明蒙版缓冲 (RGB=255, A=255)
  static Uint8List _newWhiteMaskBuffer(int width, int height) {
    final buf = _newBlackMaskBuffer(width, height);
    for (var i = 0; i < buf.length; i += 4) {
      buf[i] = 255;
      buf[i + 1] = 255;
      buf[i + 2] = 255;
    }
    return buf;
  }

  /// 在蒙版缓冲上涂白矩形 (x/y/w/h，边界由调用方钳制)
  static void _fillRectWhite(
    Uint8List buf,
    int bufWidth,
    int x,
    int y,
    int w,
    int h,
  ) {
    for (var row = y; row < y + h; row++) {
      final start = (row * bufWidth + x) * 4;
      final end = start + w * 4;
      for (var i = start; i < end; i += 4) {
        buf[i] = 255;
        buf[i + 1] = 255;
        buf[i + 2] = 255;
      }
    }
  }

  // ---------------------------------------------------------------------------
  // 内部辅助
  // ---------------------------------------------------------------------------

  /// 把 contextCrop 钳制到解码图实际尺寸并取整 (解码图可能小于几何假设)
  static ({int x, int y, int width, int height}) _cropRectFor(
    int decodedWidth,
    int decodedHeight,
    Rect cropRect,
  ) {
    final x = cropRect.left.round().clamp(0, decodedWidth - 1);
    final y = cropRect.top.round().clamp(0, decodedHeight - 1);
    final w = cropRect.width.round().clamp(1, decodedWidth - x);
    final h = cropRect.height.round().clamp(1, decodedHeight - y);
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

/// 焦点回贴合成任务 (纯数据，大字节块经 IsolateBytes 零拷贝跨 isolate)
class _FocusedCompositeTask {
  final IsolateBytes orig;
  final int origWidth;
  final int origHeight;
  final IsolateBytes patch;
  final int patchWidth;
  final int patchHeight;
  final int requestWidth;
  final int requestHeight;
  final int cropX;
  final int cropY;
  final IsolateBytes? mask;
  final int? maskWidth;
  final int? maskHeight;

  const _FocusedCompositeTask({
    required this.orig,
    required this.origWidth,
    required this.origHeight,
    required this.patch,
    required this.patchWidth,
    required this.patchHeight,
    required this.requestWidth,
    required this.requestHeight,
    required this.cropX,
    required this.cropY,
    this.mask,
    this.maskWidth,
    this.maskHeight,
  });
}

/// 常规回贴合成任务 (纯数据，大字节块经 IsolateBytes 零拷贝跨 isolate)
class _StandardCompositeTask {
  final IsolateBytes orig;
  final int width;
  final int height;
  final IsolateBytes gen;
  final int genWidth;
  final int genHeight;
  final IsolateBytes mask;
  final int maskWidth;
  final int maskHeight;

  const _StandardCompositeTask({
    required this.orig,
    required this.width,
    required this.height,
    required this.gen,
    required this.genWidth,
    required this.genHeight,
    required this.mask,
    required this.maskWidth,
    required this.maskHeight,
  });
}
