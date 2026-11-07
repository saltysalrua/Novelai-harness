import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

Uint8List _png(int red, int green, int blue) {
  final image = img.Image(width: 64, height: 64, numChannels: 4);
  img.fill(image, color: img.ColorRgba8(red, green, blue, 255));
  return Uint8List.fromList(img.encodePng(image));
}

void _expectColor(Uint8List png, int red, int green, int blue) {
  final decoded = img.decodeImage(png);
  expect(decoded, isNotNull);
  final pixel = decoded!.getPixel(decoded.width ~/ 2, decoded.height ~/ 2);
  expect(pixel.r.toInt(), red);
  expect(pixel.g.toInt(), green);
  expect(pixel.b.toInt(), blue);
}

NaiGeneratedImage _image({
  required String id,
  required Uint8List bytes,
  String? path,
}) {
  return NaiGeneratedImage(
    id: id,
    bytes: bytes,
    originalFilePath: path,
    params: const NaiGenerationParams(prompt: 'repair', width: 64, height: 64),
    seed: 7,
    isOpusFree: false,
    createdAt: DateTime(2026, 5, 1),
  );
}

class _InfillService extends NovelAiService {
  _InfillService(this.result);

  final Uint8List result;
  Uint8List? received;
  int calls = 0;

  void _record(Uint8List source) {
    calls++;
    received = Uint8List.fromList(source);
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
  }) async {
    _record(sourceBytes);
    return [result];
  }

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
    _record(sourceBytes);
    yield NaiStreamProgress.finalResult(finalImage: result);
  }
}

class _CountingRepository extends NovelAiRepository {
  _CountingRepository({required NovelAiService service})
    : super(service: service);

  int diskLoads = 0;

  @override
  Future<Uint8List?> loadHistoryImageBytes(NaiGeneratedImage image) {
    diskLoads++;
    return super.loadHistoryImageBytes(image);
  }
}

class _DelayRepository extends NovelAiRepository {
  _DelayRepository({required NovelAiService service}) : super(service: service);

  final pending = <String, Completer<Uint8List?>>{};

  @override
  Future<Uint8List?> loadHistoryImageBytes(NaiGeneratedImage image) {
    return pending.putIfAbsent(image.id, Completer<Uint8List?>.new).future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('inpaint_source_bytes_');
  });

  tearDown(() {
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('换图发送后，缓存命中的空历史对象仍把原图送去焦点和常规修复', () async {
    const red = 20, green = 40, blue = 60;
    final bytes = _png(red, green, blue);
    final file = File(p.join(temp.path, 'cached.png'));
    await file.writeAsBytes(bytes);
    final service = _InfillService(_png(1, 2, 3));
    final repo = _CountingRepository(service: service);
    repo.addImageForTesting(
      _image(id: 'cached', bytes: bytes, path: file.path),
    );
    final history = repo.history.first;
    expect(history.bytes, isEmpty);
    expect(repo.lruImageCache[history.id], bytes);

    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);
    vm.setInpaintSelectionRect(const Rect.fromLTWH(0.25, 0.25, 0.5, 0.5));

    for (final mode in [InpaintMode.focus, InpaintMode.standard]) {
      for (final stream in [false, true]) {
        await vm.updateConfig(
          vm.config.copyWith(
            novelAiKey: 'test-key',
            enableImagePersistence: false,
            enableStreamPreview: stream,
            autoSaveImages: false,
          ),
        );
        vm.setInpaintMode(mode);
        final before = service.calls;
        vm.sendImageToInpaint(history);
        expect(vm.inpaintSourceImage!.bytes, isEmpty);
        expect(identical(vm.inpaintSourceImage, history), isTrue);

        await vm.executeInpaint();

        expect(vm.errorMessage, isNull);
        expect(vm.isExecutingInpaint, isFalse);
        expect(service.calls, before + 1);
        expect(history.bytes, isEmpty);
        _expectColor(service.received!, red, green, blue);
      }
    }
    expect(repo.diskLoads, 0);
  });

  test('缓存没有原图时，从文件载入后再修复，不把空 bytes 送出去', () async {
    const red = 9, green = 80, blue = 200;
    final bytes = _png(red, green, blue);
    final file = File(p.join(temp.path, 'disk.png'));
    await file.writeAsBytes(bytes);
    final service = _InfillService(_png(4, 5, 6));
    final repo = _CountingRepository(service: service);
    repo.addImageForTesting(
      _image(id: 'disk', bytes: Uint8List(0), path: file.path),
    );
    final history = repo.history.first;
    expect(history.bytes, isEmpty);
    expect(repo.lruImageCache.containsKey(history.id), isFalse);

    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);
    await vm.updateConfig(
      vm.config.copyWith(
        novelAiKey: 'test-key',
        enableImagePersistence: false,
        enableStreamPreview: false,
        autoSaveImages: false,
      ),
    );
    vm.setInpaintMode(InpaintMode.standard);
    vm.sendImageToInpaint(history);

    await vm.executeInpaint();

    expect(vm.errorMessage, isNull);
    expect(service.calls, 1);
    expect(repo.diskLoads, 1);
    expect(history.bytes, isEmpty);
    _expectColor(service.received!, red, green, blue);
  });

  test('原图字节和文件都缺失时，请求发出前结束', () async {
    final service = _InfillService(_png(1, 1, 1));
    final repo = _CountingRepository(service: service);
    repo.addImageForTesting(_image(id: 'missing', bytes: Uint8List(0)));
    final history = repo.history.first;
    expect(history.bytes, isEmpty);

    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);
    await vm.updateConfig(
      vm.config.copyWith(
        novelAiKey: 'test-key',
        enableImagePersistence: false,
        enableStreamPreview: true,
        autoSaveImages: false,
      ),
    );
    vm.setInpaintMode(InpaintMode.standard);
    vm.sendImageToInpaint(history);

    await vm.executeInpaint();

    expect(service.calls, 0);
    expect(repo.diskLoads, 1);
    expect(vm.isExecutingInpaint, isFalse);
    expect(vm.errorMessage, vm.vmL10n.vmInpaintNoImage);
    expect(vm.errorMessage, isNot(contains('无法解码')));
  });

  test('加载尚未完成时改发送另一张图，这次修复仍使用开始时的那张', () async {
    const red = 180, green = 30, blue = 70;
    final bytesA = _png(red, green, blue);
    final service = _InfillService(_png(8, 8, 8));
    final repo = _DelayRepository(service: service);
    repo.addImageForTesting(
      _image(id: 'b', bytes: Uint8List(0), path: p.join(temp.path, 'b.png')),
    );
    repo.addImageForTesting(
      _image(id: 'a', bytes: Uint8List(0), path: p.join(temp.path, 'a.png')),
    );
    final sentA = repo.history.firstWhere((image) => image.id == 'a');
    final sentB = repo.history.firstWhere((image) => image.id == 'b');
    expect(sentA.bytes, isEmpty);
    expect(sentB.bytes, isEmpty);

    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);
    await vm.updateConfig(
      vm.config.copyWith(
        novelAiKey: 'test-key',
        enableImagePersistence: false,
        enableStreamPreview: true,
        autoSaveImages: false,
      ),
    );
    vm.setInpaintMode(InpaintMode.focus);
    vm.setInpaintSelectionRect(const Rect.fromLTWH(0.2, 0.2, 0.4, 0.4));
    vm.sendImageToInpaint(sentA);

    final operation = vm.executeInpaint();
    expect(repo.pending.containsKey('a'), isTrue);
    vm.sendImageToInpaint(sentB);
    expect(vm.inpaintSourceImage!.id, 'b');
    expect(vm.inpaintSourceImage!.bytes, isEmpty);

    repo.pending['a']!.complete(bytesA);
    await operation;

    expect(vm.errorMessage, isNull);
    expect(service.calls, 1);
    expect(repo.pending.containsKey('b'), isFalse);
    _expectColor(service.received!, red, green, blue);
    expect(sentA.bytes, isEmpty);
    expect(sentB.bytes, isEmpty);
  });
}
