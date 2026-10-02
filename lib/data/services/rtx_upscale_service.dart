import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

class RtxUpscaleException implements Exception {
  const RtxUpscaleException(this.message, {this.cancelled = false});

  final String message;
  final bool cancelled;

  @override
  String toString() => message;
}

/// Windows NVIDIA driver VSR. The bundled worker keeps GPU/PNG work off the UI
/// thread and can be killed without corrupting the application's D3D device.
class RtxUpscaleService {
  RtxUpscaleService({String? executablePath, bool? isSupported})
    : _executablePath =
          executablePath ??
          p.join(p.dirname(Platform.resolvedExecutable), 'rtx_upscale.exe'),
      isSupported = isSupported ?? Platform.isWindows;

  final String _executablePath;
  final bool isSupported;
  Process? _process;
  bool _running = false;
  bool _cancelled = false;

  void cancel() {
    if (!_running) return;
    _cancelled = true;
    _process?.kill();
  }

  void _checkCancelled() {
    if (_cancelled) {
      throw const RtxUpscaleException('RTX upscale cancelled', cancelled: true);
    }
  }

  Future<Uint8List> upscale(Uint8List bytes, {int scale = 2}) async {
    if (!isSupported) {
      throw const RtxUpscaleException(
        'RTX upscale is only supported on Windows',
      );
    }
    if (scale != 2 && scale != 4) {
      throw ArgumentError.value(scale, 'scale', 'Expected 2 or 4');
    }
    if (bytes.isEmpty) {
      throw const RtxUpscaleException('Source image is missing or empty');
    }
    if (_running) {
      throw const RtxUpscaleException('RTX upscale is already running');
    }
    _running = true;
    _cancelled = false;
    Directory? temp;
    try {
      if (!await File(_executablePath).exists()) {
        throw const RtxUpscaleException(
          'rtx_upscale.exe is missing; rebuild or reinstall the Windows application',
        );
      }
      _checkCancelled();
      temp = await Directory.systemTemp.createTemp('novelai_rtx_');
      final input = File(p.join(temp.path, 'input.png'));
      final output = File(p.join(temp.path, 'output.png'));
      await input.writeAsBytes(bytes, flush: true);
      _checkCancelled();
      final process = await Process.start(_executablePath, [
        input.path,
        output.path,
        '$scale',
      ], runInShell: false);
      _process = process;
      if (_cancelled) process.kill();
      // Drain both pipes immediately (otherwise a full pipe can deadlock exit).
      final stdoutDone = process.stdout.drain<void>();
      final stderrDone = process.stderr.transform(utf8.decoder).join();
      final int exitCode;
      try {
        exitCode = await process.exitCode.timeout(const Duration(minutes: 2));
      } on TimeoutException {
        process.kill();
        await process.exitCode;
        throw const RtxUpscaleException('RTX upscale timed out');
      }
      await stdoutDone;
      final error = await stderrDone;
      _checkCancelled();
      if (exitCode != 0) {
        throw RtxUpscaleException(
          error.trim().isEmpty ? 'RTX worker failed ($exitCode)' : error.trim(),
        );
      }
      if (!await output.exists()) {
        throw const RtxUpscaleException('RTX worker did not produce an image');
      }
      final result = await output.readAsBytes();
      _checkCancelled();
      if (result.isEmpty) {
        throw const RtxUpscaleException('RTX worker produced an empty image');
      }
      return result;
    } finally {
      _process = null;
      _running = false;
      if (temp != null) await temp.delete(recursive: true);
    }
  }
}
