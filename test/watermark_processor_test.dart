import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/image_metadata_service.dart';
import 'package:novelai_harness/data/services/skia_image_codec.dart';
import 'package:novelai_harness/data/services/watermark_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Watermark Processor Tests', () {
    late Uint8List baseImageBytes;
    late Uint8List watermarkImageBytes;

    setUp(() {
      // 创建 200x200 基础白图
      final base = img.Image(width: 200, height: 200);
      img.fill(base, color: img.ColorRgb8(255, 255, 255));
      baseImageBytes = Uint8List.fromList(img.encodePng(base));

      // 创建 40x40 红色水印图
      final wm = img.Image(width: 40, height: 40);
      img.fill(wm, color: img.ColorRgba8(255, 0, 0, 200));
      watermarkImageBytes = Uint8List.fromList(img.encodePng(wm));
    });

    test('WatermarkConfig JSON roundtrip and copyWith', () {
      const config = WatermarkConfig(
        enabled: true,
        imagePath: 'C:\\watermark.png',
        posX: 0.9,
        posY: 0.8,
        scalePercent: 20.0,
        opacity: 0.75,
        marginPercent: 3.0,
      );

      final json = config.toJson();
      final restored = WatermarkConfig.fromJson(json);

      expect(restored.enabled, equals(config.enabled));
      expect(restored.imagePath, equals(config.imagePath));
      expect(restored.posX, equals(config.posX));
      expect(restored.posY, equals(config.posY));
      expect(restored.scalePercent, equals(config.scalePercent));
      expect(restored.opacity, equals(config.opacity));
      expect(restored.marginPercent, equals(config.marginPercent));

      final copied = config.copyWith(
        scalePercent: 25.0,
        opacity: 0.9,
        clearImage: true,
      );
      expect(copied.scalePercent, equals(25.0));
      expect(copied.opacity, equals(0.9));
      expect(copied.imagePath, isNull);
    });

    test('applyWatermark places watermark onto base image correctly', () async {
      const config = WatermarkConfig(
        enabled: true,
        posX: 1.0, // 右下
        posY: 1.0,
        scalePercent: 20.0,
        opacity: 1.0,
        marginPercent: 0.0,
      );

      final resultBytes = await WatermarkService.applyWatermarkAsync(
        imageBytes: baseImageBytes,
        watermarkBytes: watermarkImageBytes,
        config: config,
      );

      expect(ImageMetadataService.isPngHeader(resultBytes), isTrue);

      final decoded = img.decodePng(resultBytes);
      expect(decoded, isNotNull);
      expect(decoded!.width, equals(200));
      expect(decoded.height, equals(200));

      // 验证右下角像素被水印红色着色 (非纯白)
      final bottomRightPixel = decoded.getPixel(195, 195);
      expect(bottomRightPixel.r.toInt(), equals(255));
      expect(bottomRightPixel.g.toInt(), lessThan(100));
    });

    test('processExportImage applies watermark and strips metadata', () async {
      // 给底图注入文本元数据
      final base = img.Image(width: 100, height: 100);
      base.textData = {'Comment': '{"prompt":"test"}'};
      final rawWithMeta = Uint8List.fromList(img.encodePng(base));

      expect(ImageMetadataService.parseMetadata(rawWithMeta), isNotNull);

      const config = WatermarkConfig(
        enabled: true,
        posX: 0.5,
        posY: 0.5,
        scalePercent: 15.0,
        opacity: 0.8,
      );

      final exportedBytes = await WatermarkService.processExportImage(
        rawBytes: rawWithMeta,
        stripMetadata: true,
        enableWatermark: true,
        watermarkConfig: config,
        watermarkBytes: watermarkImageBytes,
      );

      expect(ImageMetadataService.isPngHeader(exportedBytes), isTrue);

      // 元数据已抹除
      expect(ImageMetadataService.parseMetadata(exportedBytes), isNull);
    });

    test(
      'applyWatermark auto contrast darkens watermark on bright background',
      () async {
        const config = WatermarkConfig(
          enabled: true,
          posX: 0.5,
          posY: 0.5,
          scalePercent: 20.0,
          opacity: 1.0,
          marginPercent: 0.0,
          autoContrast: true,
        );

        final resultBytes = await WatermarkService.applyWatermarkAsync(
          imageBytes: baseImageBytes,
          watermarkBytes: watermarkImageBytes,
          config: config,
        );

        final decoded = img.decodePng(resultBytes)!;
        // 纯白背景 + 自动对比度 -> 红色水印应被压暗 (中心点亮度显著低于无自动对比度时)
        final center = decoded.getPixel(100, 100);
        final centerLuma =
            0.299 * center.r + 0.587 * center.g + 0.114 * center.b;

        const noAutoConfig = WatermarkConfig(
          enabled: true,
          posX: 0.5,
          posY: 0.5,
          scalePercent: 20.0,
          opacity: 1.0,
          marginPercent: 0.0,
        );
        final noAutoBytes = await WatermarkService.applyWatermarkAsync(
          imageBytes: baseImageBytes,
          watermarkBytes: watermarkImageBytes,
          config: noAutoConfig,
        );
        final noAutoCenter = img.decodePng(noAutoBytes)!.getPixel(100, 100);
        final noAutoLuma =
            0.299 * noAutoCenter.r +
            0.587 * noAutoCenter.g +
            0.114 * noAutoCenter.b;

        expect(centerLuma, lessThan(noAutoLuma));
      },
    );

    test(
      'applyWatermark auto contrast lightens watermark on dark background',
      () async {
        final dark = img.Image(width: 200, height: 200);
        img.fill(dark, color: img.ColorRgb8(10, 10, 10));
        final darkBytes = Uint8List.fromList(img.encodePng(dark));

        const config = WatermarkConfig(
          enabled: true,
          posX: 0.5,
          posY: 0.5,
          scalePercent: 20.0,
          opacity: 1.0,
          marginPercent: 0.0,
          autoContrast: true,
        );

        final resultBytes = await WatermarkService.applyWatermarkAsync(
          imageBytes: darkBytes,
          watermarkBytes: watermarkImageBytes,
          config: config,
        );

        final decoded = img.decodePng(resultBytes)!;
        final center = decoded.getPixel(100, 100);
        // 暗背景 + 自动对比度 -> 水印应被提亮 (中心点不再是接近纯黑)
        final centerLuma =
            0.299 * center.r + 0.587 * center.g + 0.114 * center.b;
        expect(centerLuma, greaterThan(60));
      },
    );

    test('findLowInformationPosition picks flat region over busy region', () {
      // 左半边高噪声细节，右半边纯色平坦 (flat RGBA 缓冲)
      const w = 400, h = 400;
      final rgba = Uint8List(w * h * 4);
      for (var i = 0; i < rgba.length; i += 4) {
        rgba[i] = 128;
        rgba[i + 1] = 128;
        rgba[i + 2] = 128;
        rgba[i + 3] = 255;
      }
      final rng = math.Random(42);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < 200; x++) {
          final v = rng.nextInt(256);
          final i = (y * w + x) * 4;
          rgba[i] = v;
          rgba[i + 1] = v;
          rgba[i + 2] = v;
        }
      }

      final pos = WatermarkService.findLowInformationPosition(
        RawRgbaImage(rgba: rgba, width: w, height: h),
        wmW: 40,
        wmH: 40,
        marginPx: 4,
      );

      // 应选中右侧平坦区 (噪声区止于 x=200/400=0.5，选位归一值应落在其后)
      expect(pos.$1, greaterThan(0.5));
    });

    test(
      'applyWatermark autoPosition composites into low information area',
      () async {
        // 左半边高噪声细节，右半边纯色平坦
        final image = img.Image(width: 400, height: 400);
        img.fill(image, color: img.ColorRgb8(255, 255, 255));
        final rng = math.Random(7);
        for (var y = 0; y < 400; y++) {
          for (var x = 0; x < 200; x++) {
            final v = rng.nextInt(256);
            image.setPixel(x, y, img.ColorRgb8(v, v, v));
          }
        }
        final bytes = Uint8List.fromList(img.encodePng(image));

        const config = WatermarkConfig(
          enabled: true,
          posX: 0.0,
          posY: 0.0,
          scalePercent: 10.0,
          opacity: 1.0,
          marginPercent: 1.0,
          autoPosition: true,
        );

        final resultBytes = await WatermarkService.applyWatermarkAsync(
          imageBytes: bytes,
          watermarkBytes: watermarkImageBytes,
          config: config,
        );

        final decoded = img.decodePng(resultBytes)!;
        // 选位算法会命中右侧平坦区首个零能量窗口 (约 x=202 起)，检查该区域被水印覆盖 (红色渗透)
        final coveredPixel = decoded.getPixel(220, 24);
        expect(coveredPixel.g.toInt(), lessThan(200));
      },
    );

    test(
      'applyWatermark with transparent background blends instead of stamping',
      () async {
        // 40x40 水印：仅中心 20x20 不透明红色，其余全透明 (典型 logo PNG)
        // 注意：image 包默认 numChannels=3 会丢掉 alpha，必须显式建 4 通道图
        final wm = img.Image(width: 40, height: 40, numChannels: 4);
        for (var y = 0; y < 40; y++) {
          for (var x = 0; x < 40; x++) {
            final opaque = x >= 10 && x < 30 && y >= 10 && y < 30;
            wm.setPixel(
              x,
              y,
              opaque
                  ? img.ColorRgba8(255, 0, 0, 255)
                  : img.ColorRgba8(255, 0, 0, 0),
            );
          }
        }
        final wmBytes = Uint8List.fromList(img.encodePng(wm));

        const config = WatermarkConfig(
          enabled: true,
          posX: 0.0, // 左上，marginPercent 0 → 贴合 (0,0)
          posY: 0.0,
          scalePercent: 20.0, // shortSide=200 → 目标 40px，不缩放，几何可直接推算
          opacity: 1.0,
          marginPercent: 0.0,
        );

        final resultBytes = await WatermarkService.applyWatermarkAsync(
          imageBytes: baseImageBytes,
          watermarkBytes: wmBytes,
          config: config,
        );

        final decoded = img.decodePng(resultBytes)!;
        // 水印矩形内的透明底像素：必须保持原白底不透明，不得被透明像素顶掉
        final untouched = decoded.getPixel(0, 0);
        expect(untouched.r.toInt(), equals(255));
        expect(untouched.g.toInt(), equals(255));
        expect(untouched.b.toInt(), equals(255));
        expect(untouched.a.toInt(), equals(255));

        // 中心不透明红色应正常盖住背景
        final center = decoded.getPixel(20, 20);
        expect(center.r.toInt(), equals(255));
        expect(center.g.toInt(), equals(0));
        expect(center.b.toInt(), equals(0));
        expect(center.a.toInt(), equals(255));
      },
    );

    test('blind watermark embed and extract roundtrip', () async {
      final image = img.Image(width: 256, height: 256);
      img.fill(image, color: img.ColorRgb8(120, 140, 160));
      // 加入平滑渐变避免全平图像
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          image.setPixel(x, y, img.ColorRgb8(100 + x ~/ 8, 120 + y ~/ 8, 160));
        }
      }
      final bytes = Uint8List.fromList(img.encodePng(image));

      const payload = '测试版权签名 NovelAI-Harness 2026';
      final embedded = await WatermarkService.embedBlindWatermarkAsync(
        bytes,
        text: payload,
        strength: 3,
      );

      // 嵌入后仍是合法 PNG 且尺寸不变
      expect(ImageMetadataService.isPngHeader(embedded), isTrue);
      final decoded = img.decodePng(embedded)!;
      expect(decoded.width, equals(256));
      expect(decoded.height, equals(256));

      // 视觉扰动极小：像素级均方差应远低于可感知级别 (T=48 时单像素扰动约 T/8)
      var sqDiff = 0.0;
      var sampleCount = 0;
      final orig = img.decodePng(bytes)!;
      for (var y = 0; y < 256; y += 2) {
        for (var x = 0; x < 256; x += 2) {
          final a = orig.getPixel(x, y);
          final b = decoded.getPixel(x, y);
          sqDiff += (a.r - b.r) * (a.r - b.r);
          sampleCount++;
        }
      }
      final mse = sqDiff / sampleCount;
      expect(mse, lessThan(20.0)); // 单像素 RMS < 4.5 级 (QIM+平坦区降档后畸变约减半以上)

      // 提取应还原载荷
      final extracted = await WatermarkService.extractBlindWatermarkAsync(
        embedded,
      );
      expect(extracted, equals(payload));
    });

    test('blind watermark flat solid image roundtrip with tiny MSE', () async {
      // 512x512 纯色填充图：平坦块极端场景，是盲水印画质修复的核心回归测试
      final image = img.Image(width: 512, height: 512);
      img.fill(image, color: img.ColorRgb8(150, 170, 190));
      final bytes = Uint8List.fromList(img.encodePng(image));

      const payload = 'flat-test';
      final embedded = await WatermarkService.embedBlindWatermarkAsync(
        bytes,
        text: payload,
        strength: 3,
      );

      // 嵌入后仍是合法 PNG 且尺寸不变
      expect(ImageMetadataService.isPngHeader(embedded), isTrue);
      final decoded = img.decodePng(embedded)!;
      expect(decoded.width, equals(512));
      expect(decoded.height, equals(512));

      // 纯色图全部为平坦块：扰动应被感知掩码压制到接近无损
      var sqDiff = 0.0;
      var sampleCount = 0;
      final orig = img.decodePng(bytes)!;
      for (var y = 0; y < 512; y += 2) {
        for (var x = 0; x < 512; x += 2) {
          final a = orig.getPixel(x, y);
          final b = decoded.getPixel(x, y);
          sqDiff += (a.r - b.r) * (a.r - b.r);
          sampleCount++;
        }
      }
      final mse = sqDiff / sampleCount;
      expect(mse, lessThan(15.0));

      // 提取应还原载荷
      final extracted = await WatermarkService.extractBlindWatermarkAsync(
        embedded,
      );
      expect(extracted, equals(payload));
    });

    test('blind watermark returns null for clean image', () async {
      final image = img.Image(width: 128, height: 128);
      img.fill(image, color: img.ColorRgb8(90, 90, 90));
      final bytes = Uint8List.fromList(img.encodePng(image));
      expect(await WatermarkService.extractBlindWatermarkAsync(bytes), isNull);
    });

    test('blind watermark insufficient capacity returns original', () async {
      // 8x8 图只有一个块，容量不足
      final image = img.Image(width: 8, height: 8);
      img.fill(image, color: img.ColorRgb8(90, 90, 90));
      final bytes = Uint8List.fromList(img.encodePng(image));
      final result = await WatermarkService.embedBlindWatermarkAsync(
        bytes,
        text: 'copyright',
      );
      expect(result, equals(bytes));
    });

    test(
      'processExportImage embeds blind watermark with stripped metadata',
      () async {
        final image = img.Image(width: 256, height: 256);
        for (var y = 0; y < 256; y++) {
          for (var x = 0; x < 256; x++) {
            image.setPixel(
              x,
              y,
              img.ColorRgb8(100 + x ~/ 8, 120 + y ~/ 8, 160),
            );
          }
        }
        image.textData = {'Comment': '{"prompt":"secret"}'};
        final raw = Uint8List.fromList(img.encodePng(image));

        const config = WatermarkConfig(
          enabled: true,
          blindEnabled: true,
          blindText: 'owner-42',
          blindStrength: 3,
        );

        final exported = await WatermarkService.processExportImage(
          rawBytes: raw,
          stripMetadata: true,
          enableWatermark: false,
          watermarkConfig: config,
        );

        // 元数据已抹除，但盲水印仍可提取
        expect(ImageMetadataService.parseMetadata(exported), isNull);
        expect(
          await WatermarkService.extractBlindWatermarkAsync(exported),
          equals('owner-42'),
        );
      },
    );
  });
}
