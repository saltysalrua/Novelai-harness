import 'dart:ui' show Rect;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/inpaint_service.dart';

void main() {
  group('InpaintService 几何与图像处理算法测试', () {
    test('resolveGeometry 正常选区正确扩展外延上下文并等比放大至 1MP 潜空间', () {
      // 原图 1024x1024，选区在中心 (400, 400, 200, 200)
      final geometry = InpaintService.resolveGeometry(
        sourceWidth: 1024,
        sourceHeight: 1024,
        selectionRect: const Rect.fromLTWH(400, 400, 200, 200),
        contextPadding: 64.0,
      );

      expect(geometry.focusBounds, const Rect.fromLTWH(400, 400, 200, 200));
      // 上下文扩展 64px: cropW = 200 + 128 = 328, cropH = 328
      // cx = 500, cy = 500 -> cropX = 500 - 164 = 336, cropY = 336
      expect(geometry.contextCrop.left, 336.0);
      expect(geometry.contextCrop.top, 336.0);
      expect(geometry.contextCrop.width, 328.0);
      expect(geometry.contextCrop.height, 328.0);

      // 请求尺寸必须对齐 64 网格且总像素 <= 1048576
      expect(geometry.requestWidth % 64, 0);
      expect(geometry.requestHeight % 64, 0);
      expect(geometry.requestArea, lessThanOrEqualTo(1048576));
      expect(geometry.isOpusFree, isTrue);
      expect(geometry.scale, greaterThan(1.0));
    });

    test('resolveGeometry 边界选区自动受限在原图边界内', () {
      // 选区贴在左上角 (0, 0, 100, 100)
      final geometry = InpaintService.resolveGeometry(
        sourceWidth: 1024,
        sourceHeight: 1024,
        selectionRect: const Rect.fromLTWH(0, 0, 100, 100),
        contextPadding: 64.0,
      );

      expect(geometry.contextCrop.left, 0.0);
      expect(geometry.contextCrop.top, 0.0);
      expect(geometry.contextCrop.right, lessThanOrEqualTo(1024.0));
      expect(geometry.contextCrop.bottom, lessThanOrEqualTo(1024.0));
      expect(geometry.requestWidth % 64, 0);
      expect(geometry.requestHeight % 64, 0);
    });

    test('prepareFocusedRequestData 与 compositeFocusedResult 完整回贴流水线测试', () {
      // 构造一张 512x512 的红色测试图
      final source = img.Image(width: 512, height: 512);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 255));
      final sourceBytes = img.encodePng(source);

      final geometry = InpaintService.resolveGeometry(
        sourceWidth: 512,
        sourceHeight: 512,
        selectionRect: const Rect.fromLTWH(100, 100, 100, 100),
        contextPadding: 32.0,
      );

      // 准备请求数据
      final reqData = InpaintService.prepareFocusedRequestData(
        sourceImageBytes: sourceBytes,
        geometry: geometry,
      );

      final decodedReqSource = img.decodeImage(reqData.sourceBytes);
      final decodedReqMask = img.decodeImage(reqData.maskBytes);

      expect(decodedReqSource, isNotNull);
      expect(decodedReqSource!.width, geometry.requestWidth);
      expect(decodedReqSource.height, geometry.requestHeight);

      expect(decodedReqMask, isNotNull);
      expect(decodedReqMask!.width, geometry.requestWidth);
      expect(decodedReqMask.height, geometry.requestHeight);

      // 模拟生成的潜空间图像 (全绿图像)
      final patch = img.Image(
        width: geometry.requestWidth,
        height: geometry.requestHeight,
      );
      img.fill(patch, color: img.ColorRgba8(0, 255, 0, 255));
      final patchBytes = img.encodePng(patch);

      // 执行无损贴回原图
      final compositedBytes = InpaintService.compositeFocusedResult(
        originalSourceBytes: sourceBytes,
        generatedPatchBytes: patchBytes,
        geometry: geometry,
      );

      final decodedComposited = img.decodeImage(compositedBytes);
      expect(decodedComposited, isNotNull);
      expect(decodedComposited!.width, 512);
      expect(decodedComposited.height, 512);

      // 验证未裁剪区域仍为红色 (例如原图坐标 10, 10)
      final uncroppedPixel = decodedComposited.getPixel(10, 10);
      expect(uncroppedPixel.r, 255);
      expect(uncroppedPixel.g, 0);

      // 验证裁剪回贴区域中心为绿色 (例如原图坐标 150, 150)
      final patchedPixel = decodedComposited.getPixel(150, 150);
      expect(patchedPixel.r, 0);
      expect(patchedPixel.g, 255);
    });

    test('InpaintParams JSON 往返序列化正确', () {
      const params = InpaintParams(
        mode: InpaintMode.focus,
        selectionRect: Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
        contextPadding: 80.0,
        strength: 0.85,
        noise: 0.10,
        customPrompt: 'masterpiece, glowing eyes',
        useMainPrompt: false,
      );

      final json = params.toJson();
      final fromJson = InpaintParams.fromJson(json);

      expect(fromJson.mode, InpaintMode.focus);
      expect(fromJson.selectionRect!.left, closeTo(0.1, 1e-5));
      expect(fromJson.selectionRect!.top, closeTo(0.2, 1e-5));
      expect(fromJson.selectionRect!.width, closeTo(0.3, 1e-5));
      expect(fromJson.selectionRect!.height, closeTo(0.4, 1e-5));
      expect(fromJson.contextPadding, 80.0);
      expect(fromJson.strength, 0.85);
      expect(fromJson.noise, 0.10);
      expect(fromJson.customPrompt, 'masterpiece, glowing eyes');
      expect(fromJson.useMainPrompt, isFalse);
    });

    test('InpaintParams 画笔描边 JSON 往返与生效选区', () {
      const params = InpaintParams(
        brushStrokes: [
          InpaintBrushStroke(
            points: [Offset(0.2, 0.2), Offset(0.4, 0.2)],
            radius: 0.05,
          ),
          InpaintBrushStroke(
            points: [Offset(0.6, 0.6), Offset(0.8, 0.6)],
            radius: 0.03,
          ),
        ],
        brushRadius: 0.07,
      );

      final restored = InpaintParams.fromJson(params.toJson());
      expect(restored.hasBrushMask, isTrue);
      expect(restored.brushStrokes.length, 2);
      expect(restored.brushStrokes[0].points, [
        const Offset(0.2, 0.2),
        const Offset(0.4, 0.2),
      ]);
      expect(restored.brushStrokes[1].radius, 0.03);
      expect(restored.brushRadius, 0.07);

      // 生效选区为描边包围盒外扩最大半径
      final eff = restored.effectiveSelectionRect;
      expect(eff.left, closeTo(0.15, 1e-5));
      expect(eff.top, closeTo(0.15, 1e-5));
      expect(eff.right, closeTo(0.85, 1e-5));
      expect(eff.bottom, closeTo(0.65, 1e-5));

      // 无描边时回退到矩形选区默认居中半幅
      expect(
        const InpaintParams().effectiveSelectionRect,
        const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
      );
    });

    test('buildSourceMask 矩形选区与画笔描边栅格化', () {
      // 矩形选区：仅选区内为白
      final rectMask = InpaintService.buildSourceMask(
        sourceWidth: 200,
        sourceHeight: 100,
        selectionRect: const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5),
      );
      expect(rectMask.width, 200);
      expect(rectMask.height, 100);
      expect(rectMask.getPixel(100, 50).r, 255);
      expect(rectMask.getPixel(10, 10).r, 0);

      // 无选区无描边：整图全白
      final fullMask = InpaintService.buildSourceMask(
        sourceWidth: 200,
        sourceHeight: 100,
      );
      expect(fullMask.getPixel(10, 10).r, 255);

      // 画笔描边：轨迹中心为白，远端为黑
      final strokeMask = InpaintService.buildSourceMask(
        sourceWidth: 200,
        sourceHeight: 200,
        brushStrokes: const [
          InpaintBrushStroke(points: [Offset(0.5, 0.5)], radius: 0.05),
        ],
      );
      expect(strokeMask.getPixel(100, 100).r, 255);
      expect(strokeMask.getPixel(10, 10).r, 0);
    });

    test('compositeFocusedResult 带蒙版回贴：外延环保留原图像素', () {
      // 构造 512x512 红色原图，选区 (100,100,100,100)，蒙版为该选区矩形
      final source = img.Image(width: 512, height: 512);
      img.fill(source, color: img.ColorRgba8(255, 0, 0, 255));
      final sourceBytes = img.encodePng(source);

      final geometry = InpaintService.resolveGeometry(
        sourceWidth: 512,
        sourceHeight: 512,
        selectionRect: const Rect.fromLTWH(100, 100, 100, 100),
        contextPadding: 32.0,
      );

      final sourceMask = InpaintService.buildSourceMask(
        sourceWidth: 512,
        sourceHeight: 512,
        selectionRect: const Rect.fromLTWH(
          0.1953125,
          0.1953125,
          0.1953125,
          0.1953125,
        ),
      );

      // 生成的补丁为全绿
      final patch = img.Image(
        width: geometry.requestWidth,
        height: geometry.requestHeight,
      );
      img.fill(patch, color: img.ColorRgba8(0, 255, 0, 255));

      final compositedBytes = InpaintService.compositeFocusedResult(
        originalSourceBytes: sourceBytes,
        generatedPatchBytes: img.encodePng(patch),
        geometry: geometry,
        sourceMask: sourceMask,
      );
      final result = img.decodeImage(compositedBytes)!;

      // 选区中心 (蒙版内) 为绿色
      expect(result.getPixel(150, 150).g, 255);
      expect(result.getPixel(150, 150).r, 0);

      // 外延环境带内 (裁剪框内但蒙版外) 保留红色原图
      final crop = geometry.contextCrop;
      final ringX = (crop.left + 4).round();
      final ringY = (crop.top + 4).round();
      expect(result.getPixel(ringX, ringY).r, 255);
      expect(result.getPixel(ringX, ringY).g, 0);

      // 裁剪框外不受影响
      expect(result.getPixel(10, 10).r, 255);

      // 潜空间量化边缘：蒙版外但在膨胀羽化范围内的像素同样被补丁覆盖
      // (服务端按 8px 格子重绘，硬按原蒙版回贴会残留原图色环)
      final edgePixel = result.getPixel(97, 150);
      expect(edgePixel.r, lessThan(200));
    });

    test('buildSourceMask 反向画笔 (橡皮) 在蒙版上打黑抵消先前笔迹', () {
      final mask = InpaintService.buildSourceMask(
        sourceWidth: 200,
        sourceHeight: 200,
        brushStrokes: const [
          InpaintBrushStroke(points: [Offset(0.5, 0.5)], radius: 0.10),
          InpaintBrushStroke(
            points: [Offset(0.5, 0.5)],
            radius: 0.05,
            isEraser: true,
          ),
        ],
      );
      // 中心被反向画笔擦回黑
      expect(mask.getPixel(100, 100).r, 0);
      // 外环 (正向半径内、橡皮半径外) 仍为白
      expect(mask.getPixel(100, 85).r, 255);
      // 远处为黑
      expect(mask.getPixel(5, 5).r, 0);
    });

    test('buildSourceMask 只有橡皮描边时回退矩形选区', () {
      final mask = InpaintService.buildSourceMask(
        sourceWidth: 200,
        sourceHeight: 200,
        brushStrokes: const [
          InpaintBrushStroke(
            points: [Offset(0.5, 0.5)],
            radius: 0.20,
            isEraser: true,
          ),
        ],
        selectionRect: const Rect.fromLTWH(0.1, 0.1, 0.3, 0.3),
      );
      // 没有任何正向描边 → 蒙版回退矩形选区，而不是被橡皮栅格化成全黑空转
      expect(mask.getPixel(30, 30).r, 255);
      expect(mask.getPixel(100, 100).r, 0);
    });

    test('quantizeMaskToLatentGrid 按格中心采样量化到 8px 整格', () {
      final mask = img.Image(width: 64, height: 64, numChannels: 4);
      img.fill(mask, color: img.ColorRgba8(0, 0, 0, 255));
      // 1px 竖线 x=20，贯穿格 2 (16..23) 的中心 (20)
      for (var y = 0; y < 64; y++) {
        mask.setPixelRgba(20, y, 255, 255, 255, 255);
      }
      final q = InpaintService.quantizeMaskToLatentGrid(mask);
      // 被采样命中的格整格涂白
      expect(q.getPixel(16, 32).r, 255);
      expect(q.getPixel(23, 32).r, 255);
      // 未命中格保持黑
      expect(q.getPixel(8, 32).r, 0);
      expect(q.getPixel(24, 32).r, 0);
    });

    test('resolveStandardRequestSize 对齐源图尺寸到 64 网格并限制上限', () {
      // 正好对齐
      expect(InpaintService.resolveStandardRequestSize(1024, 1024), (
        width: 1024,
        height: 1024,
      ));
      // 非对齐尺寸四舍五入到 64 网格
      final odd = InpaintService.resolveStandardRequestSize(833, 1217);
      expect(odd.width % 64, 0);
      expect(odd.height % 64, 0);
      // 超大源图 (如 2x 超分 2432x3328) 等比收敛到 3MP 内
      final huge = InpaintService.resolveStandardRequestSize(2432, 3328);
      expect(huge.width * huge.height, lessThanOrEqualTo(3145728));
      expect(huge.width % 64, 0);
      expect(huge.height % 64, 0);
    });

    test('computeStrokeMaskBounds 正向描边返回含半径的归一化包围盒', () {
      final bounds = InpaintService.computeStrokeMaskBounds(const [
        InpaintBrushStroke(points: [Offset(0.5, 0.5)], radius: 0.10),
      ]);
      expect(bounds, isNotNull);
      // 中心 0.5 ± 半径 0.1，256 栅格下误差 <= 1/256
      expect(bounds!.left, closeTo(0.40, 0.01));
      expect(bounds.top, closeTo(0.40, 0.01));
      expect(bounds.right, closeTo(0.60, 0.01));
      expect(bounds.bottom, closeTo(0.60, 0.01));
    });

    test('computeStrokeMaskBounds 橡皮擦除后包围盒收缩到剩余蒙版', () {
      // 两个分离圆点，右侧那个被橡皮完全擦掉 → 包围盒只剩左侧
      final bounds = InpaintService.computeStrokeMaskBounds(const [
        InpaintBrushStroke(points: [Offset(0.2, 0.5)], radius: 0.05),
        InpaintBrushStroke(points: [Offset(0.8, 0.5)], radius: 0.05),
        InpaintBrushStroke(
          points: [Offset(0.8, 0.5)],
          radius: 0.06,
          isEraser: true,
        ),
      ]);
      expect(bounds, isNotNull);
      expect(bounds!.right, lessThan(0.35));
      expect(bounds.left, closeTo(0.15, 0.01));
    });

    test('computeStrokeMaskBounds 全被擦掉返回 Rect.zero，无正向描边返回 null', () {
      expect(
        InpaintService.computeStrokeMaskBounds(const [
          InpaintBrushStroke(points: [Offset(0.5, 0.5)], radius: 0.10),
          InpaintBrushStroke(
            points: [Offset(0.5, 0.5)],
            radius: 0.12,
            isEraser: true,
          ),
        ]),
        Rect.zero,
      );
      expect(
        InpaintService.computeStrokeMaskBounds(const [
          InpaintBrushStroke(
            points: [Offset(0.5, 0.5)],
            radius: 0.10,
            isEraser: true,
          ),
        ]),
        isNull,
      );
    });

    test('InpaintParams.effectiveSelectionRect 优先栅格化包围盒并回退', () {
      const strokes = [
        InpaintBrushStroke(points: [Offset(0.2, 0.5)], radius: 0.05),
        InpaintBrushStroke(points: [Offset(0.8, 0.5)], radius: 0.05),
      ];
      // 无 maskBounds (旧数据) → 几何并集，右缘接近 0.85
      final legacy = InpaintParams(brushStrokes: strokes);
      expect(legacy.effectiveSelectionRect.right, greaterThan(0.8));

      // 有 maskBounds (提交时计算，右侧已被擦掉) → 收缩
      final shrunk = InpaintParams(
        brushStrokes: strokes,
        maskBounds: const Rect.fromLTWH(0.15, 0.45, 0.10, 0.10),
      );
      expect(
        shrunk.effectiveSelectionRect,
        const Rect.fromLTWH(0.15, 0.45, 0.10, 0.10),
      );

      // maskBounds 为 Rect.zero (全被擦掉) → 回退矩形选区
      const sel = Rect.fromLTWH(0.1, 0.1, 0.3, 0.3);
      final erased = InpaintParams(
        brushStrokes: strokes,
        maskBounds: Rect.zero,
        selectionRect: sel,
      );
      expect(erased.effectiveSelectionRect, sel);
    });

    test('InpaintParams JSON 往返保留 maskBounds', () {
      const params = InpaintParams(
        brushStrokes: [
          InpaintBrushStroke(points: [Offset(0.2, 0.5)], radius: 0.05),
        ],
        maskBounds: Rect.fromLTWH(0.15, 0.45, 0.10, 0.10),
      );
      final restored = InpaintParams.fromJson(params.toJson());
      expect(restored.maskBounds, params.maskBounds);
      expect(restored.effectiveSelectionRect, params.maskBounds);

      // 清空蒙版时 copyWith 应一并清除 maskBounds
      final cleared = params.copyWith(
        clearBrushStrokes: true,
        clearMaskBounds: true,
      );
      expect(cleared.maskBounds, isNull);
      expect(cleared.brushStrokes, isEmpty);
    });
  });
}
