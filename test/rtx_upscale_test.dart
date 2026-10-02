import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/image_metadata_service.dart';
import 'package:novelai_harness/data/services/image_save_path_service.dart';
import 'package:novelai_harness/data/services/rtx_upscale_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _png(int width, int height) => Uint8List.fromList(
  img.encodePng(
    img.Image(width: width, height: height, numChannels: 4)
      ..clear(img.ColorRgba8(90, 160, 230, 128)),
  ),
);

NaiGeneratedImage _source({Uint8List? bytes, String? path}) =>
    NaiGeneratedImage(
      id: 'source',
      bytes: bytes ?? Uint8List(0),
      originalFilePath: path,
      params: const NaiGenerationParams(prompt: 'test', width: 64, height: 64),
      seed: 42,
      createdAt: DateTime(2026, 1, 2),
      isOpusFree: true,
      outputModel: 'source-model',
    );

class _FakeRtx extends RtxUpscaleService {
  _FakeRtx() : super(isSupported: true);
  int calls = 0;
  Uint8List? received;
  int? receivedScale;
  Uint8List? result;
  Completer<Uint8List>? pending;

  @override
  Future<Uint8List> upscale(Uint8List bytes, {int scale = 2}) async {
    calls++;
    received = bytes;
    receivedScale = scale;
    if (pending != null) return pending!.future;
    return result ?? _png(64 * scale, 64 * scale);
  }

  @override
  void cancel() {
    if (pending case final operation? when !operation.isCompleted) {
      operation.completeError(
        const RtxUpscaleException('cancelled', cancelled: true),
      );
    }
  }
}

class _PendingReadRepository extends NovelAiRepository {
  _PendingReadRepository(_FakeRtx service) : super(rtxUpscaleService: service);
  final read = Completer<Uint8List?>();

  @override
  Future<Uint8List?> loadHistoryImageBytes(NaiGeneratedImage image) =>
      read.future;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _FakeRtx service;
  late NovelAiRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('rtx_test_');
    service = _FakeRtx();
    repo = NovelAiRepository(rtxUpscaleService: service);
  });
  tearDown(() => temp.deleteSync(recursive: true));

  test(
    'local upscale lazily loads original and preserves snapshot/metadata',
    () async {
      final original = File(p.join(temp.path, 'source.png'));
      final bytes = _png(64, 64);
      await original.writeAsBytes(bytes);
      final source = _source(path: original.path);
      final result = await repo.upscale(
        apiKey: '',
        sourceImage: source,
        saveDir: temp.path,
        rtxScale: 2,
        autoSave: false,
      );
      expect(service.received, bytes);
      expect(result.params.width, 128);
      expect(result.params.height, 128);
      expect(result.seed, 42);
      expect(result.outputModel, 'source-model');
      expect(result.isUpscaled, isTrue);
      expect(result.isUnsaved, isTrue);
      expect(result.id, startsWith('rtx_'));
      expect(repo.history.single.id, result.id);
      expect(await original.readAsBytes(), bytes);
      final decoded = img.decodePng(result.bytes)!;
      expect(decoded.getPixel(0, 0).a, 128);
      expect(ImageSaveContext.fromImage(result).prefix, 'rtx_upscaled');
      expect(ImageSaveContext.fromImage(result).type, 'upscale');
      // Metadata describes the output dimensions, not the source dimensions.
      final metadata = await ImageMetadataService.parseMetadataAsync(
        result.bytes,
      );
      expect(metadata?.width, 128);
      expect(metadata?.height, 128);
      final restored = NovelAiRepository();
      await restored.loadPersistedHistory(saveDir: temp.path);
      expect(restored.history.single.isUpscaled, isTrue);
      expect(restored.history.single.params.width, 128);
      expect(
        await restored.loadHistoryImageBytes(restored.history.single),
        result.bytes,
      );
    },
  );

  test(
    '4x exports through naming and metadata stripping, retaining raw cache',
    () async {
      final result = await repo.upscale(
        apiKey: '',
        sourceImage: _source(bytes: _png(64, 64)),
        saveDir: temp.path,
        rtxScale: 4,
        stripMetadata: true,
        imageSaveTemplate: '{type}/{prefix}_{resolution}_{seed}',
      );
      expect(result.params.width, 256);
      expect(result.isUnsaved, isFalse);
      expect(
        p
            .relative(result.localFilePath!, from: temp.path)
            .replaceAll('\\', '/'),
        'upscale/rtx_upscaled_256x256_42.png',
      );
      expect(result.originalFilePath, isNot(result.localFilePath));
      final export = await File(result.localFilePath!).readAsBytes();
      expect(export, isNot(result.bytes));
      expect(img.decodePng(export)!.width, 256);
    },
  );

  test(
    'missing originals and corrupt worker outputs never register history',
    () async {
      await expectLater(
        repo.upscale(
          apiKey: '',
          sourceImage: _source(),
          saveDir: temp.path,
          rtxScale: 2,
        ),
        throwsA(isA<RtxUpscaleException>()),
      );
      expect(service.calls, 0);
      service.result = Uint8List.fromList([1, 2, 3]);
      await expectLater(
        repo.upscale(
          apiKey: '',
          sourceImage: _source(bytes: _png(64, 64)),
          saveDir: temp.path,
          rtxScale: 2,
        ),
        throwsA(isA<RtxUpscaleException>()),
      );
      expect(repo.history, isEmpty);
    },
  );

  test(
    'VM uses configured scale, prevents reentry and captures target/config',
    () async {
      final vm = StudioViewModel(repository: repo);
      addTearDown(vm.dispose);
      await vm.updateConfig(vm.config.copyWith(rtxUpscaleScale: 4));
      service.pending = Completer<Uint8List>();
      final source = _source(bytes: _png(64, 64));
      final operation = vm.upscaleRtx(source);
      expect(vm.isGenerating, isTrue);
      vm.selectImage(_source(bytes: _png(32, 32)).copyWith(id: 'other'));
      await vm.updateConfig(vm.config.copyWith(rtxUpscaleScale: 2));
      await vm.upscaleRtx(source);
      expect(service.calls, 1);
      expect(service.received, source.bytes);
      expect(service.receivedScale, 4);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('novelai_rtx_upscale_scale'), 2);
      service.pending!.complete(_png(256, 256));
      await operation;
      expect(vm.isGenerating, isFalse);
      expect(vm.errorMessage, isNull);
      expect(vm.selectedImage!.id, startsWith('rtx_'));
    },
  );

  test(
    'VM aborts RTX even in ComfyUI mode, without registering late output',
    () async {
      final vm = StudioViewModel(repository: repo);
      addTearDown(vm.dispose);
      await vm.updateConfig(vm.config.copyWith(comfyUiEnabled: true));
      service.pending = Completer<Uint8List>();
      final operation = vm.upscaleRtx(_source(bytes: _png(64, 64)));
      await vm.abortGeneration();
      await operation;
      expect(vm.isGenerating, isFalse);
      expect(vm.errorMessage, isNull);
      expect(repo.history, isEmpty);
    },
  );

  test(
    'cancellation during lazy loading never starts the GPU worker',
    () async {
      final delayed = _PendingReadRepository(service);
      final operation = delayed.upscale(
        apiKey: '',
        sourceImage: _source(),
        saveDir: temp.path,
        rtxScale: 2,
      );
      delayed.cancelRtxUpscale();
      delayed.read.complete(_png(64, 64));
      await expectLater(
        operation,
        throwsA(
          isA<RtxUpscaleException>().having(
            (e) => e.cancelled,
            'cancelled',
            isTrue,
          ),
        ),
      );
      expect(service.calls, 0);
      expect(delayed.history, isEmpty);
    },
  );

  test(
    'normal close waits for RTX cancellation even before initialization',
    () async {
      final vm = StudioViewModel(repository: repo);
      addTearDown(vm.dispose);
      service.pending = Completer<Uint8List>();
      final operation = vm.upscaleRtx(_source(bytes: _png(64, 64)));
      await vm.flushPendingSaves();
      await operation;
      expect(vm.isGenerating, isFalse);
      expect(vm.errorMessage, isNull);
      expect(repo.history, isEmpty);
    },
  );

  test(
    'service rejects unsupported platform, bad scale and missing worker',
    () async {
      await expectLater(
        RtxUpscaleService(isSupported: false).upscale(_png(8, 8)),
        throwsA(isA<RtxUpscaleException>()),
      );
      final absent = RtxUpscaleService(
        isSupported: true,
        executablePath: p.join(temp.path, 'missing.exe'),
      );
      await expectLater(
        absent.upscale(_png(8, 8), scale: 3),
        throwsArgumentError,
      );
      await expectLater(
        absent.upscale(Uint8List(0)),
        throwsA(isA<RtxUpscaleException>()),
      );
      await expectLater(
        absent.upscale(_png(8, 8)),
        throwsA(isA<RtxUpscaleException>()),
      );
    },
  );

  final nativeWorker = Platform.environment['RTX_UPSCALE_EXE'];
  test(
    'native RTX worker produces true dimensions and retains alpha',
    () async {
      final native = RtxUpscaleService(executablePath: nativeWorker);
      final bytes = _png(513, 511);
      for (final scale in [2, 4]) {
        final result = img.decodePng(
          await native.upscale(bytes, scale: scale),
        )!;
        expect(result.width, 513 * scale);
        expect(result.height, 511 * scale);
        expect(result.getPixel(result.width ~/ 2, result.height ~/ 2).a, 128);
      }
    },
    skip: nativeWorker == null || !Platform.isWindows,
  );
}
