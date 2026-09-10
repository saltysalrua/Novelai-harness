import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/image_edit_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/data/services/image_save_path_service.dart';
import 'package:path/path.dart' as p;

Uint8List _solidPng(int red, int green, int blue) {
  final image = img.Image(width: 64, height: 64, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(red, green, blue, 255));
  return Uint8List.fromList(img.encodePng(image));
}

class _ImageService extends NovelAiService {
  final Uint8List result;
  Uint8List? upscaleSource;
  int count = 1;
  _ImageService(this.result);

  @override
  Future<List<Uint8List>> generateImage({
    required String apiKey,
    required NaiGenerationParams params,
  }) async => List.filled(count, result);

  @override
  Stream<NaiStreamProgress> generateImageStream({
    required String apiKey,
    required NaiGenerationParams params,
  }) async* {
    yield NaiStreamProgress.finalResult(finalImage: result);
  }

  @override
  Future<Uint8List> upscaleImage({
    required String apiKey,
    required Uint8List imageBytes,
  }) async {
    upscaleSource = imageBytes;
    return result;
  }

  @override
  Future<List<Uint8List>> generateInfill({
    required String apiKey,
    required NaiGenerationParams params,
    required Uint8List sourceBytes,
    required Uint8List maskBytes,
    required int requestWidth,
    required int requestHeight,
    double strength = 0.70,
    double noise = 0.00,
  }) async => [result];

  @override
  Stream<NaiStreamProgress> generateInfillStream({
    required String apiKey,
    required NaiGenerationParams params,
    required Uint8List sourceBytes,
    required Uint8List maskBytes,
    required int requestWidth,
    required int requestHeight,
    double strength = 0.70,
    double noise = 0.00,
  }) async* {
    yield NaiStreamProgress.finalResult(finalImage: result);
  }
}

class _EditService extends ImageEditService {
  final Uint8List result;
  _EditService(this.result);

  @override
  Future<ImageEditResult> editImage({
    required String baseUrl,
    required String apiKey,
    required String modelId,
    required String prompt,
    required Uint8List imageBytes,
    String aspectRatio = '',
    String imageResolution = '',
    Duration timeout = const Duration(seconds: 240),
  }) async => ImageEditResult(imageBytes: result);
}

const _template = '{model}/{type}/{seed}_{date}_{time}';

const _params = NaiGenerationParams(prompt: 'test', width: 64, height: 64);
const _watermark = WatermarkConfig(
  enabled: true,
  posX: 0.5,
  posY: 0.5,
  scalePercent: 50,
  opacity: 1,
  marginPercent: 0,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late Uint8List raw;
  late Uint8List watermark;
  late _ImageService service;
  late NovelAiRepository repo;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('nai_original_cache_');
    raw = _solidPng(20, 40, 60);
    watermark = _solidPng(255, 0, 0);
    service = _ImageService(raw);
    repo = NovelAiRepository(
      service: service,
      imageEditService: _EditService(raw),
    );
  });
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> expectOriginalAfterRestart(NaiGeneratedImage image) async {
    expect(image.originalFilePath, isNotNull);
    expect(p.dirname(image.originalFilePath!), p.join(dir.path, 'cache'));
    expect(File(image.originalFilePath!).readAsBytesSync(), image.bytes);
    expect(
      image.localFilePath,
      p.joinAll([
        dir.path,
        ...ImageSavePathService.resolve(
          _template,
          ImageSaveContext.fromImage(image),
        ).split('/'),
      ]),
    );
    final exported = img.decodePng(
      File(image.localFilePath!).readAsBytesSync(),
    )!;
    final original = img.decodePng(image.bytes)!;
    expect(exported.getPixel(32, 32).r, 255);
    expect(original.getPixel(32, 32).r, 20);
    final restarted = NovelAiRepository();
    final restored = (await restarted.loadPersistedHistory(
      saveDir: dir.path,
    )).firstWhere((entry) => entry.id == image.id);
    expect(restored.bytes, isEmpty);
    expect(restored.originalFilePath, image.originalFilePath);
    expect(restored.localFilePath, image.localFilePath);
    expect(img.decodePng(restored.thumbnailBytes!)!.getPixel(32, 32).r, 20);
    expect(await restarted.loadHistoryImageBytes(restored), image.bytes);
  }

  for (final streaming in [false, true]) {
    test('生成 streaming=$streaming：导出加水印，重启大图及缩略图保持原图', () async {
      final image = streaming
          ? (await repo
                    .generateStream(
                      apiKey: 'mock',
                      params: _params,
                      saveDir: dir.path,
                      imageSaveTemplate: _template,
                      enableWatermark: true,
                      watermarkBytes: watermark,
                      watermarkConfig: _watermark,
                      stripMetadata: true,
                    )
                    .last)
                .generatedImage!
          : (await repo.generate(
              apiKey: 'mock',
              params: _params,
              saveDir: dir.path,
              imageSaveTemplate: _template,
              enableWatermark: true,
              watermarkBytes: watermark,
              watermarkConfig: _watermark,
              stripMetadata: true,
            )).single;
      await expectOriginalAfterRestart(image);
    });

    test('修复 streaming=$streaming：重启仍读取无水印合成原图', () async {
      final image = streaming
          ? (await repo
                    .generateInpaintStream(
                      apiKey: 'mock',
                      sourceImageBytes: raw,
                      inpaintParams: const InpaintParams(
                        mode: InpaintMode.standard,
                      ),
                      generationParams: _params,
                      saveDir: dir.path,
                      imageSaveTemplate: _template,
                      enableWatermark: true,
                      watermarkBytes: watermark,
                      watermarkConfig: _watermark,
                    )
                    .last)
                .generatedImage!
          : await repo.generateInpaint(
              apiKey: 'mock',
              sourceImageBytes: raw,
              inpaintParams: const InpaintParams(mode: InpaintMode.standard),
              generationParams: _params,
              saveDir: dir.path,
              imageSaveTemplate: _template,
              enableWatermark: true,
              watermarkBytes: watermark,
              watermarkConfig: _watermark,
            );
      expect(image.isInpainted, isTrue);
      await expectOriginalAfterRestart(image);
    });
  }

  test('AI 编辑也保留原图缓存', () async {
    final image = await repo.editImageAi(
      provider: const LlmProviderConfig(
        id: 'mock',
        name: 'mock',
        baseUrl: 'https://example.invalid',
        apiKey: 'mock',
      ),
      modelId: 'mock',
      prompt: 'edit',
      sourceImageBytes: raw,
      generationParams: _params,
      saveDir: dir.path,
      imageSaveTemplate: _template,
      enableWatermark: true,
      watermarkBytes: watermark,
      watermarkConfig: _watermark,
    );
    expect(image.isAiEdited, isTrue);
    expect(image.outputModel, 'mock');
    expect(NaiGeneratedImage.fromJson(image.toJson()).outputModel, 'mock');
    await expectOriginalAfterRestart(image);
  });

  test('超分读取恢复后的原图，超分输出同样分离导出与原图', () async {
    final source = (await repo.generate(
      apiKey: 'mock',
      params: _params,
      saveDir: dir.path,
      imageSaveTemplate: _template,
      enableWatermark: true,
      watermarkBytes: watermark,
      watermarkConfig: _watermark,
    )).single;
    final restarted = NovelAiRepository(service: service);
    final restored = (await restarted.loadPersistedHistory(
      saveDir: dir.path,
    )).single;
    final image = await restarted.upscale(
      apiKey: 'mock',
      sourceImage: restored,
      saveDir: dir.path,
      imageSaveTemplate: _template,
      enableWatermark: true,
      watermarkBytes: watermark,
      watermarkConfig: _watermark,
    );
    expect(service.upscaleSource, source.bytes);
    await expectOriginalAfterRestart(image);
  });

  test('未保存图片重启后手动导出不删除原图，再次重启不显示水印', () async {
    final source = (await repo.generate(
      apiKey: 'mock',
      params: _params,
      saveDir: dir.path,
      autoSave: false,
    )).single;
    final restarted = NovelAiRepository();
    await restarted.loadPersistedHistory(saveDir: dir.path);
    final saved = (await restarted.saveUnsavedImageToDisk(
      imageId: source.id,
      saveDir: dir.path,
      imageSaveTemplate: _template,
      enableWatermark: true,
      watermarkBytes: watermark,
      watermarkConfig: _watermark,
    ))!;
    expect(saved.isUnsaved, isFalse);
    expect(saved.originalFilePath, source.originalFilePath);
    await expectOriginalAfterRestart(saved);
  });

  test('画布脱离历史索引恢复时也使用原图缓存', () async {
    final source = (await repo.generate(
      apiKey: 'mock',
      params: _params,
      saveDir: dir.path,
      imageSaveTemplate: _template,
      enableWatermark: true,
      watermarkBytes: watermark,
      watermarkConfig: _watermark,
    )).single;
    await repo.saveBoardLayout(
      CanvasBoardData(
        noteNodes: const [],
        imageNodes: [
          CanvasImageNode(
            id: 'node',
            image: source,
            offset: Offset.zero,
            width: 64,
            height: 64,
          ),
        ],
      ),
      saveDir: dir.path,
    );
    final board = (await NovelAiRepository().loadBoardLayout(
      saveDir: dir.path,
    ))!;
    expect(board.imageNodes.single.image.bytes, source.bytes);
    expect(board.imageNodes.single.image.localFilePath, source.localFilePath);
    expect(
      board.imageNodes.single.image.originalFilePath,
      source.originalFilePath,
    );
  });

  test('淘汰或删除历史只移除原图缓存，可以保留正式导出', () async {
    final source = (await repo.generate(
      apiKey: 'mock',
      params: _params,
      saveDir: dir.path,
    )).single;
    await repo.savePersistedHistory(saveDir: dir.path, maxImages: 0);
    expect(File(source.originalFilePath!).existsSync(), isFalse);
    expect(File(source.localFilePath!).existsSync(), isTrue);
    expect(repo.lruImageCache, isEmpty);
    final next = (await repo.generate(
      apiKey: 'mock',
      params: _params,
      saveDir: dir.path,
    )).single;
    await repo.deleteImage(
      imageId: next.id,
      saveDir: dir.path,
      deleteLocalFile: false,
    );
    expect(File(next.originalFilePath!).existsSync(), isFalse);
    expect(File(next.localFilePath!).existsSync(), isTrue);
  });

  test('旧历史有 _raw 副本时优先恢复原图，无副本时兼容旧路径', () async {
    final exported = File(p.join(dir.path, 'legacy.png'))
      ..writeAsBytesSync(watermark);
    final original = File(p.join(dir.path, 'legacy_raw.png'))
      ..writeAsBytesSync(raw);
    final image = NaiGeneratedImage(
      id: 'legacy',
      bytes: Uint8List(0),
      localFilePath: exported.path,
      params: _params,
      createdAt: DateTime.now(),
      seed: 1,
      isOpusFree: true,
    );
    File(
      p.join(dir.path, 'image_history.json'),
    ).writeAsStringSync(jsonEncode([image.toJson()]));
    final restored = (await repo.loadPersistedHistory(
      saveDir: dir.path,
    )).single;
    expect(restored.originalFilePath, original.path);
    expect(await repo.loadHistoryImageBytes(restored), raw);
    original.deleteSync();
    final legacy = (await repo.loadPersistedHistory(saveDir: dir.path)).single;
    expect(legacy.originalFilePath, isNull);
    expect(await repo.loadHistoryImageBytes(legacy), watermark);
  });

  test('同种子批量导出不覆盖成品与缓存，raw 副本跟随编号', () async {
    service.count = 3;
    final images = await repo.generate(
      apiKey: 'mock',
      params: _params.copyWith(seed: 42, nSamples: 3),
      saveDir: dir.path,
      imageSaveTemplate: '{seed}',
      stripMetadata: true,
      keepOriginalImage: true,
    );
    expect(images.map((image) => p.basename(image.localFilePath!)), [
      '42.png',
      '42_2.png',
      '42_3.png',
    ]);
    expect(images.map((image) => image.originalFilePath).toSet(), hasLength(3));
    for (final image in images) {
      expect(File(image.originalFilePath!).readAsBytesSync(), image.bytes);
      expect(
        File(
          '${p.withoutExtension(image.localFilePath!)}_raw.png',
        ).existsSync(),
        isTrue,
      );
    }
  });

  test('隔天手动保存使用图片时间，改模板不移动旧文件', () async {
    final source = NaiGeneratedImage(
      id: 'old',
      bytes: raw,
      params: _params,
      createdAt: DateTime(2020, 1, 2, 3, 4, 5),
      seed: 99,
      isOpusFree: true,
      isUnsaved: true,
    );
    repo.addImageForTesting(source);
    final saved = (await repo.saveUnsavedImageToDisk(
      imageId: source.id,
      saveDir: dir.path,
      imageSaveTemplate: '{date:yyyy-MM-dd}/{seed}_{time}',
    ))!;
    expect(
      saved.localFilePath,
      p.join(dir.path, '2020-01-02', '99_030405.png'),
    );
    final again = (await repo.saveUnsavedImageToDisk(
      imageId: source.id,
      saveDir: dir.path,
      imageSaveTemplate: 'changed/{seed}',
    ))!;
    expect(again.localFilePath, saved.localFilePath);
    expect(File(saved.localFilePath!).existsSync(), isTrue);
  });

  test('模板目录不可写时保留缓存和未保存状态，换模板可重试', () async {
    File(p.join(dir.path, 'blocked')).writeAsStringSync('keep');
    final image = (await repo.generate(
      apiKey: 'mock',
      params: _params,
      saveDir: dir.path,
      imageSaveTemplate: 'blocked/{seed}',
    )).single;
    expect(image.isUnsaved, isTrue);
    expect(File(image.originalFilePath!).existsSync(), isTrue);
    expect(File(p.join(dir.path, 'blocked')).readAsStringSync(), 'keep');
    final saved = await repo.saveUnsavedImageToDisk(
      imageId: image.id,
      saveDir: dir.path,
      imageSaveTemplate: 'working/{seed}',
    );
    expect(saved!.isUnsaved, isFalse);
    expect(p.dirname(saved.localFilePath!), p.join(dir.path, 'working'));
  });

  for (final autoSave in [false, true]) {
    test('ComfyUI autoSave=$autoSave：统一缓存、命名、手动导出及重启恢复', () async {
      final image = await repo.recordComfyUiImage(
        id: 'comfy_1',
        bytes: raw,
        params: _params.copyWith(width: 1024),
        seed: 42,
        saveDir: dir.path,
        imageSaveTemplate: _template,
        autoSave: autoSave,
        enableWatermark: true,
        watermarkBytes: watermark,
        watermarkConfig: _watermark,
      );
      expect(image.params.width, 64);
      expect(image.outputModel, 'comfyui');
      expect(image.isUnsaved, !autoSave);
      final restarted = NovelAiRepository();
      final restored = (await restarted.loadPersistedHistory(
        saveDir: dir.path,
      )).single;
      expect(restored.outputModel, 'comfyui');
      final saved = autoSave
          ? image
          : (await restarted.saveUnsavedImageToDisk(
              imageId: image.id,
              saveDir: dir.path,
              imageSaveTemplate: _template,
              enableWatermark: true,
              watermarkBytes: watermark,
              watermarkConfig: _watermark,
            ))!;
      expect(saved.isUnsaved, isFalse);
      await expectOriginalAfterRestart(saved);
    });
  }

  test('独立原图丢失时不悄悄将导出水印图当成原图', () async {
    final source = (await repo.generate(
      apiKey: 'mock',
      params: _params,
      saveDir: dir.path,
    )).single;
    File(source.originalFilePath!).deleteSync();
    final restarted = NovelAiRepository();
    expect(
      await restarted.loadHistoryImageBytes(
        source.copyWith(bytes: Uint8List(0)),
      ),
      isNull,
    );
    expect(await restarted.loadPersistedHistory(saveDir: dir.path), isEmpty);
  });
}
