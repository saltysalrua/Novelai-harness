import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';

void main() {
  group('AgentMessageImage memoize cache', () {
    test('同一 AgentMessageImage 实例二次访问解码结果 identical 且字节数与输入一致', () {
      final sampleString = 'Hello NovelAI Harness Performance Test';
      final rawBytes = Uint8List.fromList(utf8.encode(sampleString));
      final base64Str = base64Encode(rawBytes);

      final img = AgentMessageImage(base64: base64Str);

      final firstAccess = img.bytes;
      final secondAccess = img.bytes;

      // 验证引用同一性 (memoize 单次解码)
      expect(identical(firstAccess, secondAccess), isTrue);

      // 验证解码字节数与输入一致
      expect(firstAccess.length, equals(rawBytes.length));
      expect(firstAccess, equals(rawBytes));
    });

    test('const 构造的 AgentMessageImage 实例二次访问解码结果 identical', () {
      const sampleBase64 = 'aGVsbG8gd29ybGQ='; // 'hello world'
      const constImg = AgentMessageImage(base64: sampleBase64);

      final firstAccess = constImg.bytes;
      final secondAccess = constImg.bytes;

      expect(identical(firstAccess, secondAccess), isTrue);
      expect(firstAccess.length, equals(11));
      expect(utf8.decode(firstAccess), equals('hello world'));
    });

    test('空 base64 返回空 Uint8List 且多次访问 identical', () {
      const emptyImg = AgentMessageImage(base64: '');

      final firstAccess = emptyImg.bytes;
      final secondAccess = emptyImg.bytes;

      expect(identical(firstAccess, secondAccess), isTrue);
      expect(firstAccess.isEmpty, isTrue);
    });

    test('AgentMessageImage.fromBytes 预热缓存，访问时不重复解码', () {
      final rawBytes = Uint8List.fromList([10, 20, 30, 40, 50]);
      final img = AgentMessageImage.fromBytes(bytes: rawBytes);

      expect(identical(img.bytes, rawBytes), isTrue);
      expect(img.base64, equals(base64Encode(rawBytes)));
    });

    test('attachBytes 手动注入缓存后 bytes 直接复用该实例', () {
      final rawBytes = Uint8List.fromList([1, 2, 3]);
      final img = AgentMessageImage(base64: 'AAAA');
      img.attachBytes(rawBytes);

      expect(identical(img.bytes, rawBytes), isTrue);
    });
  });

  group('AgentMessage imageBytes memoize cache', () {
    test('同一 AgentMessage 实例多次访问 imageBytes 返回 identical 解码结果', () {
      final rawBytes = Uint8List.fromList([42, 43, 44, 45]);
      final base64Str = base64Encode(rawBytes);

      final message = AgentMessage(
        id: 'msg-1',
        role: AgentRole.tool,
        toolCallId: 'call-1',
        content: 'image preview',
        imageBase64: base64Str,
      );

      final firstAccess = message.imageBytes;
      final secondAccess = message.imageBytes;

      expect(firstAccess, isNotNull);
      expect(identical(firstAccess, secondAccess), isTrue);
      expect(firstAccess!.length, equals(rawBytes.length));
      expect(firstAccess, equals(rawBytes));
    });

    test('未包含 imageBase64 或为空时 imageBytes 返回 null', () {
      final msgNoImage = AgentMessage(
        id: 'msg-2',
        role: AgentRole.assistant,
        content: 'text only',
      );
      expect(msgNoImage.imageBytes, isNull);

      final msgEmptyImage = AgentMessage(
        id: 'msg-3',
        role: AgentRole.tool,
        content: 'empty image',
        imageBase64: '',
      );
      expect(msgEmptyImage.imageBytes, isNull);
    });

    test('copyWith 未修改 imageBase64 时复用已有的解码字节缓存', () {
      final rawBytes = Uint8List.fromList([99, 100, 101]);
      final message = AgentMessage(
        id: 'msg-4',
        role: AgentRole.tool,
        imageBase64: base64Encode(rawBytes),
      );

      final originalBytes = message.imageBytes;
      final copied = message.copyWith(content: 'updated text');

      expect(identical(copied.imageBytes, originalBytes), isTrue);
    });
  });
}
