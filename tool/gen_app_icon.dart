// 应用图标一键重生成工具 (全平台)
//
// ignore_for_file: avoid_print — 本文件为独立 CLI 工具，print 即标准输出。
//
// 用法: dart run tool/gen_app_icon.dart [源图路径]
// 源图默认取项目根目录 icon03.png (建议 1024x1024 正方形 PNG)。
//
// 覆盖目标:
// - windows/runner/resources/app_icon.ico  (16/24/32/48/64/128/256 多尺寸 ICO)
// - android  mipmap-{mdpi..xxxhdpi}/ic_launcher.png (48~192)
// - macos    AppIcon.appiconset/app_icon_{16..1024}.png (Contents.json 声明的全部档位)
//
// Linux 端未接入应用图标 (无 .desktop/icon 资源)，无需生成。

import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart';

void main(List<String> args) {
  final sourcePath = args.isNotEmpty ? args.first : 'icon03.png';
  final sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) {
    stderr.writeln('源图不存在: $sourcePath');
    exitCode = 1;
    return;
  }
  final source = decodeImage(sourceFile.readAsBytesSync());
  if (source == null) {
    stderr.writeln('源图解码失败 (仅支持 PNG/JPEG 等常见格式): $sourcePath');
    exitCode = 1;
    return;
  }
  final side = source.width < source.height ? source.width : source.height;
  print(
    '源图: $sourcePath (${source.width}x${source.height}, 取中心 ${side}x$side 裁切)',
  );

  // 统一先裁成正方形 (取居中最大正方形)，避免非正方形源图拉伸变形
  final square = side == source.width && side == source.height
      ? source
      : copyCrop(
          source,
          x: (source.width - side) ~/ 2,
          y: (source.height - side) ~/ 2,
          width: side,
          height: side,
        );

  Image scaled(int size) => copyResize(
    square,
    width: size,
    height: size,
    interpolation: Interpolation.average,
  );
  void writePng(String path, Image image) {
    File(path)
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(encodePng(image));
    print('  ✓ $path');
  }

  // 1. Windows ICO (多尺寸合一；目录项 + PNG-in-ICO 数据块，Vista+ 原生支持)
  //   image 包的 IcoEncoder 未从主库导出，此处按官方 ICO 二进制格式手工封装。
  final icoSizes = [16, 24, 32, 48, 64, 128, 256];
  final icoBytes = _encodeMultiSizeIco(icoSizes.map(scaled).toList());
  File('windows/runner/resources/app_icon.ico').writeAsBytesSync(icoBytes);
  print('  ✓ windows/runner/resources/app_icon.ico ($icoSizes)');

  // 2. Android mipmap 全密度档
  const androidDensities = {
    'mdpi': 48,
    'hdpi': 72,
    'xhdpi': 96,
    'xxhdpi': 144,
    'xxxhdpi': 192,
  };
  for (final entry in androidDensities.entries) {
    writePng(
      'android/app/src/main/res/mipmap-${entry.key}/ic_launcher.png',
      scaled(entry.value),
    );
  }

  // 3. macOS AppIcon.appiconset (Contents.json 声明的 7 档)
  const macosSizes = [16, 32, 64, 128, 256, 512, 1024];
  for (final size in macosSizes) {
    writePng(
      'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_$size.png',
      scaled(size),
    );
  }

  print('全部平台图标已重生成。');
}

/// 多尺寸 ICO 封装：16 字节目录项/帧 + 依次拼接的 PNG 数据块。
/// 256px 宽高在目录项中以 0 表示 (官方 ICO 规范)。
Uint8List _encodeMultiSizeIco(List<Image> frames) {
  final pngBlobs = [for (final frame in frames) encodePng(frame)];
  final count = frames.length;
  final headerLength = 6 + count * 16;
  final totalLength =
      headerLength + pngBlobs.fold<int>(0, (sum, b) => sum + b.length);
  final out = ByteData(totalLength);

  // 文件头: 保留字 0 / 类型 1 (ICO) / 帧数
  out.setUint16(0, 0, Endian.little);
  out.setUint16(2, 1, Endian.little);
  out.setUint16(4, count, Endian.little);

  var offset = headerLength;
  for (var i = 0; i < count; i++) {
    final entryStart = 6 + i * 16;
    final frame = frames[i];
    out.setUint8(entryStart, frame.width >= 256 ? 0 : frame.width);
    out.setUint8(entryStart + 1, frame.height >= 256 ? 0 : frame.height);
    out.setUint8(entryStart + 2, 0); // 颜色数 (0 = 大于 256 色)
    out.setUint8(entryStart + 3, 0); // 保留
    out.setUint16(entryStart + 4, 1, Endian.little); // 色彩平面数
    out.setUint16(entryStart + 6, 32, Endian.little); // 位深
    out.setUint32(entryStart + 8, pngBlobs[i].length, Endian.little);
    out.setUint32(entryStart + 12, offset, Endian.little);
    offset += pngBlobs[i].length;
  }

  final bytes = out.buffer.asUint8List();
  var pos = headerLength;
  for (var i = 0; i < count; i++) {
    bytes.setRange(pos, pos + pngBlobs[i].length, pngBlobs[i]);
    pos += pngBlobs[i].length;
  }
  return bytes;
}
