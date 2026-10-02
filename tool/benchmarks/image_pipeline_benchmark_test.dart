import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/services/image_metadata_service.dart';
import 'package:novelai_harness/data/services/image_thumbnail_service.dart';
import 'package:novelai_harness/data/services/isolated_compute.dart';
import 'package:novelai_harness/data/services/skia_image_codec.dart';

IsolateBytes _legacyStrip(IsolateBytes bytes) =>
    IsolateBytes(ImageMetadataService.stripPngMetadata(bytes.materialize()));
Uint8List _legacyThumb(IsolateBytes bytes) {
  final image = img.decodeImage(bytes.materialize())!;
  final aspect = image.width / image.height;
  return Uint8List.fromList(
    img.encodePng(
      img.copyResize(
        image,
        width: aspect >= 1 ? 240 : (240 * aspect).round(),
        height: aspect >= 1 ? (240 / aspect).round() : 240,
        interpolation: img.Interpolation.average,
      ),
    ),
  );
}

Future<Uint8List> _fixture(int w, int h) async {
  final rgba = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      rgba[i] = x & 255;
      rgba[i + 1] = y & 255;
      rgba[i + 2] = (x ^ y) & 255;
      rgba[i + 3] = 255;
    }
  }
  return encodeRawRgbaToPng(rgba, w, h);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('同进程合成图基准（非 Release；不作为性能门禁）', () async {
    for (final size in [(832, 1216), (3328, 4864)]) {
      final bytes = await _fixture(size.$1, size.$2);
      final old = Stopwatch()..start();
      await runIsolated(_legacyStrip, IsolateBytes(bytes));
      old.stop();
      final current = Stopwatch()..start();
      await ImageMetadataService.stripPngMetadataAsync(bytes);
      current.stop();
      stdout.writeln(
        'STRIP ${size.$1}x${size.$2}: old=${old.elapsedMilliseconds}ms new=${current.elapsedMilliseconds}ms',
      );
    }
    final dir = await Directory.systemTemp.createTemp('nai_thumb_bench_');
    try {
      final bytes = await _fixture(832, 1216);
      final sources = <File>[];
      for (var i = 0; i < 20; i++) {
        final file = File('${dir.path}/$i.png');
        await file.writeAsBytes(bytes);
        sources.add(file);
      }
      final old = Stopwatch()..start();
      for (final file in sources) {
        await runIsolated(_legacyThumb, IsolateBytes(await file.readAsBytes()));
      }
      old.stop();
      final cold = Stopwatch()..start();
      for (final file in sources) {
        await ImageThumbnailService.load(
          sourcePath: file.path,
          cacheDirectory: '${dir.path}/thumbs',
        );
      }
      cold.stop();
      final warm = Stopwatch()..start();
      for (final file in sources) {
        await ImageThumbnailService.load(
          sourcePath: file.path,
          cacheDirectory: '${dir.path}/thumbs',
        );
      }
      warm.stop();
      stdout.writeln(
        'THUMBS 20 images: old=${old.elapsedMilliseconds}ms cold=${cold.elapsedMilliseconds}ms warm=${warm.elapsedMilliseconds}ms',
      );
    } finally {
      await dir.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
