import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/image_metadata_service.dart';

void main() {
  group('ImageMetadataService Tests', () {
    test('isPngHeader returns true for valid PNG and false otherwise', () {
      final validPng = Uint8List.fromList([
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        0x00,
        0x00,
      ]);
      expect(ImageMetadataService.isPngHeader(validPng), isTrue);

      final invalidHeader = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      expect(ImageMetadataService.isPngHeader(invalidHeader), isFalse);

      final shortHeader = Uint8List.fromList([0x89, 0x50]);
      expect(ImageMetadataService.isPngHeader(shortHeader), isFalse);
    });

    test('Parses NovelAI JSON metadata correctly', () {
      final naiJson = jsonEncode({
        'prompt': '1girl, masterpiece, solo',
        'uc': 'lowres, bad anatomy',
        'steps': 28,
        'scale': 5.5,
        'seed': 12345678,
        'sampler': 'k_euler',
        'noise_schedule': 'karras',
        'width': 832,
        'height': 1216,
        'Source': 'NovelAI Diffusion V5',
        'characterPrompts': [
          {'prompt': 'blue hair, cat ears', 'uc': 'red hair'},
        ],
      });

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'Comment': naiJson};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, masterpiece, solo'));
      expect(result.negativePrompt, equals('lowres, bad anatomy'));
      expect(result.steps, equals(28));
      expect(result.scale, equals(5.5));
      expect(result.seed, equals(12345678));
      expect(result.sampler, equals('k_euler'));
      expect(result.noiseSchedule, equals('karras'));
      expect(result.model, equals('nai-diffusion-5-full'));
      expect(result.characterPrompts.length, equals(1));
      expect(result.characterPrompts.first, equals('blue hair, cat ears'));
      expect(result.characterNegativePrompts.first, equals('red hair'));
    });

    test('Parses WebUI plaintext metadata correctly', () {
      const webUiParams =
          '1girl, sitting on bench\n'
          'Negative prompt: bad hands, blurry\n'
          'Steps: 20, Sampler: Euler a, CFG scale: 7, Seed: 998877, Size: 512x768, Model: v1-5-pruned';

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'parameters': webUiParams};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, sitting on bench'));
      expect(result.negativePrompt, equals('bad hands, blurry'));
      expect(result.steps, equals(20));
      expect(result.sampler, equals('Euler a'));
      expect(result.scale, equals(7.0));
      expect(result.seed, equals(998877));
      expect(result.width, equals(512));
      expect(result.height, equals(768));
      expect(result.software, equals('Stable Diffusion WebUI'));
    });

    test('Parses ComfyUI JSON node graph metadata correctly', () {
      final comfyJson = jsonEncode({
        '3': {
          'class_type': 'KSampler',
          'inputs': {
            'seed': 424242,
            'steps': 25,
            'cfg': 6.5,
            'sampler_name': 'euler_ancestral',
          },
        },
        '6': {
          'class_type': 'CLIPTextEncode',
          'inputs': {'text': 'masterpiece, 1girl, smiling'},
        },
        '7': {
          'class_type': 'CLIPTextEncode',
          'inputs': {'text': 'ugly, deformed'},
        },
      });

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'prompt': comfyJson};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('masterpiece, 1girl, smiling'));
      expect(result.negativePrompt, equals('ugly, deformed'));
      expect(result.steps, equals(25));
      expect(result.sampler, equals('euler_ancestral'));
      expect(result.scale, equals(6.5));
      expect(result.seed, equals(424242));
      expect(result.software, equals('ComfyUI'));
    });

    test('stripPngMetadata strips metadata chunks from PNG', () {
      final testImage = img.Image(width: 32, height: 32);
      testImage.textData = {
        'Comment': jsonEncode({'prompt': 'test'}),
        'Author': 'Novelist',
      };
      final originalPng = Uint8List.fromList(img.encodePng(testImage));

      final parsedBefore = ImageMetadataService.parseMetadata(originalPng);
      expect(parsedBefore, isNotNull);

      final strippedPng = ImageMetadataService.stripPngMetadata(originalPng);
      expect(ImageMetadataService.isPngHeader(strippedPng), isTrue);

      final parsedAfter = ImageMetadataService.parseMetadata(strippedPng);
      expect(parsedAfter, isNull);

      final textDataAfter = ImageMetadataService.extractPngTextData(
        strippedPng,
      );
      expect(textDataAfter.isEmpty, isTrue);
    });

    test('ImageMetadataResult JSON serialization roundtrip', () {
      const model = ImageMetadataResult(
        prompt: 'scenery, fantasy castle',
        negativePrompt: 'low quality',
        seed: 8888,
        sampler: 'k_euler',
        steps: 30,
        scale: 6.0,
        cfgRescale: 0.2,
        width: 1024,
        height: 1024,
        model: 'nai-diffusion-5',
        software: 'NovelAI',
        characterPrompts: ['girl with dragon'],
        characterNegativePrompts: ['bad anatomy'],
        rawJson: '{"prompt":"scenery"}',
      );

      final json = model.toJson();
      final restored = ImageMetadataResult.fromJson(json);

      expect(restored.prompt, equals(model.prompt));
      expect(restored.negativePrompt, equals(model.negativePrompt));
      expect(restored.seed, equals(model.seed));
      expect(restored.sampler, equals(model.sampler));
      expect(restored.steps, equals(model.steps));
      expect(restored.scale, equals(model.scale));
      expect(restored.cfgRescale, equals(model.cfgRescale));
      expect(restored.width, equals(model.width));
      expect(restored.height, equals(model.height));
      expect(restored.model, equals(model.model));
      expect(restored.characterPrompts, equals(model.characterPrompts));
      expect(
        restored.characterNegativePrompts,
        equals(model.characterNegativePrompts),
      );
      expect(restored.rawJson, equals(model.rawJson));
      expect(restored.hasData, isTrue);
    });

    test(
      'embedNovelAiMetadata embeds NovelAI chunks and parseMetadata reads it back correctly',
      () {
        final blankImage = img.Image(width: 48, height: 48);
        final rawPngBytes = Uint8List.fromList(img.encodePng(blankImage));

        const params = NaiGenerationParams(
          prompt: '1girl, cyberpunk, neon light',
          negativePrompt: 'blurry, low quality',
          model: NaiModel.v5Full,
          sampler: NaiSampler.kDpmpp2m,
          noiseSchedule: NoiseSchedule.karras,
          steps: 28,
          scale: 6.5,
          width: 832,
          height: 1216,
        );

        final pngWithMeta = ImageMetadataService.embedNovelAiMetadata(
          pngBytes: rawPngBytes,
          params: params,
          seed: 987654321,
        );

        final result = ImageMetadataService.parseMetadata(pngWithMeta);
        expect(result, isNotNull);
        expect(result!.prompt, equals('1girl, cyberpunk, neon light'));
        expect(result.negativePrompt, equals('blurry, low quality'));
        expect(result.steps, equals(28));
        expect(result.scale, equals(6.5));
        expect(result.seed, equals(987654321));
        expect(result.sampler, equals('k_dpmpp_2m'));
        expect(result.model, equals('nai-diffusion-5-full'));
      },
    );

    test(
      'toMetadataComment embeds full effective prompt/uc with official fields',
      () {
        const params = NaiGenerationParams(
          prompt: '1girl, cyberpunk, neon light',
          negativePrompt: 'blurry, low quality',
          model: NaiModel.v5Full,
          sampler: NaiSampler.kDpmpp2m,
          noiseSchedule: NoiseSchedule.karras,
          steps: 28,
          scale: 6.5,
          width: 832,
          height: 1216,
        );

        final comment = params.toMetadataComment(seed: 42);

        // prompt/uc 携带完整生效文本 (质量词后缀 + UC 预设前缀 + nsfw 前置)
        expect(
          comment['prompt'],
          equals(
            '1girl, cyberpunk, neon light, very aesthetic, masterpiece, no text',
          ),
        );
        expect(
          (comment['uc'] as String).startsWith('nsfw, lowres, artistic error'),
          isTrue,
        );
        expect(
          (comment['uc'] as String).endsWith('blank page, blurry, low quality'),
          isTrue,
        );
        // 官方标准字段
        expect(comment['version'], equals(1));
        expect(comment['uncond_scale'], equals(0.0));
        expect(comment['sm'], isFalse);
        expect(comment['n_samples'], equals(1));
        expect(comment['tag_hint_qt'], equals(1));
        expect(comment['tag_hint_uc_preset'], equals(2));
        expect(comment['legacy_uc'], isFalse);
        // v4 多角色结构
        final v4 = comment['v4_prompt'] as Map<String, dynamic>;
        expect(
          (v4['caption'] as Map)['base_caption'],
          equals(comment['prompt']),
        );
        expect(v4['use_order'], isTrue);
        final v4Neg = comment['v4_negative_prompt'] as Map<String, dynamic>;
        expect(v4Neg['use_order'], isFalse);
        expect(
          (v4Neg['caption'] as Map)['base_caption'],
          equals(comment['uc']),
        );
        // v3 模型不带 v4_prompt 结构且 version 为 'v3'
        final v3Comment = params
            .copyWith(model: NaiModel.v3)
            .toMetadataComment(seed: 42);
        expect(v3Comment['version'], equals('v3'));
        expect(v3Comment.containsKey('v4_prompt'), isFalse);
      },
    );

    test(
      'toMetadataComment with multi-character mirrors payload char captions',
      () {
        const params = NaiGenerationParams(
          prompt: '2girls, scenery',
          model: NaiModel.v5Curated,
          characterPrompts: [
            NaiCharacterPrompt(
              id: 'a',
              name: 'A',
              prompt: 'girl with dragon',
              negativePrompt: 'bad anatomy',
            ),
          ],
          characterAiPosition: false,
        );

        final comment = params.toMetadataComment(seed: 7);
        final payload = params.toApiPayload();

        final v4 = comment['v4_prompt'] as Map<String, dynamic>;
        final captions =
            (v4['caption'] as Map<String, dynamic>)['char_captions'] as List;
        expect(captions.first['char_caption'], equals('girl with dragon'));
        expect(captions.first.containsKey('centers'), isTrue);
        expect(v4['use_coords'], isTrue);

        // 与 payload 的 char_captions 完全同构
        final payloadCaptions =
            ((payload['parameters']['v4_prompt'] as Map)['caption']
                    as Map)['char_captions']
                as List;
        expect(captions.first, equals(payloadCaptions.first));
      },
    );

    test('parses official tag-hint-only comment and restores base prompts', () {
      // 官网/第三方 comment：仅带数字提示，无 qualityToggle/qualityPreset/ucPreset 字段
      final naiJson = jsonEncode({
        'prompt': '1girl, solo, very aesthetic, masterpiece, no text',
        'uc':
            'nsfw, lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page, blurry, low quality',
        'steps': 28,
        'scale': 7.0,
        'seed': 12345678,
        'sampler': 'k_euler_ancestral',
        'noise_schedule': 'karras',
        'width': 832,
        'height': 1216,
        'model': 'nai-diffusion-5-curated',
        'version': 1,
        'tag_hint_qt': 1,
        'tag_hint_uc_preset': 2,
      });

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'Comment': naiJson};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, solo'));
      expect(result.negativePrompt, equals('blurry, low quality'));
      expect(result.qualityToggle, isTrue);
      expect(result.qualityPreset, equals('Standard'));
      expect(result.ucPreset, equals('Heavy'));
    });

    test('restores Light tier from tag_hint_qt 3', () {
      final naiJson = jsonEncode({
        'prompt': '1girl, solo, very aesthetic, amazing quality, no text',
        'uc':
            'nsfw, lowres, bad hands, bad anatomy, artistic error, sepia, white haze, worst quality, very displeasing, jpeg artifacts, 0::ai-generated::, extra tag',
        'steps': 28,
        'scale': 7.0,
        'seed': 12345678,
        'width': 832,
        'height': 1216,
        'model': 'nai-diffusion-5-full',
        'tag_hint_qt': 3,
        'tag_hint_uc_preset': 3,
      });

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'Comment': naiJson};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, solo'));
      expect(result.negativePrompt, equals('extra tag'));
      expect(result.qualityPreset, equals('Light'));
      expect(result.ucPreset, equals('Light'));
    });

    test('strips quality words inserted before text: render markers', () {
      const params = NaiGenerationParams(
        prompt: '1girl, sign, text: "Welcome"',
        negativePrompt: 'blurry',
        model: NaiModel.v5Full,
      );
      // 生效文本: 质量词被插到 text: 标记之前 (标记前尾逗号接空格)
      final effective = params.effectivePrompt;
      expect(
        effective,
        equals(
          '1girl, sign, very aesthetic, masterpiece, no text text: "Welcome"',
        ),
      );

      final naiJson = jsonEncode({
        'prompt': effective,
        'uc': params.effectiveNegativePrompt,
        'steps': 28,
        'scale': 7.0,
        'seed': 12345678,
        'width': 832,
        'height': 1216,
        'model': 'nai-diffusion-5-full',
        'qualityToggle': true,
        'qualityPreset': 'Standard',
        'ucPreset': 'Heavy',
      });

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'Comment': naiJson};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, sign text: "Welcome"'));
      expect(result.negativePrompt, equals('blurry'));
    });

    test('strips transparent background tag when hint is set', () {
      final naiJson = jsonEncode({
        'prompt':
            '1girl, solo, transparent background, very aesthetic, masterpiece, no text',
        'uc': 'nsfw, lowres, artistic error, worst quality',
        'steps': 28,
        'scale': 7.0,
        'seed': 12345678,
        'width': 832,
        'height': 1216,
        'model': 'nai-diffusion-5-full',
        'qualityToggle': true,
        'qualityPreset': 'Standard',
        'ucPreset': 'Heavy',
        'tag_hint_transparent_background': true,
      });

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'Comment': naiJson};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, solo'));
      expect(result.transparentBackground, isTrue);
    });

    test(
      'parses character negatives from v4_negative_prompt char captions',
      () {
        final naiJson = jsonEncode({
          'prompt': '2girls, scenery',
          'uc': 'nsfw, lowres',
          'steps': 28,
          'scale': 7.0,
          'seed': 12345678,
          'width': 832,
          'height': 1216,
          'model': 'nai-diffusion-5-full',
          'version': 1,
          'v4_prompt': {
            'caption': {
              'base_caption': '2girls, scenery',
              'char_captions': [
                {'char_caption': 'girl with dragon'},
                {'char_caption': 'girl with sword'},
              ],
            },
            'use_coords': false,
          },
          'v4_negative_prompt': {
            'caption': {
              'base_caption': 'nsfw, lowres',
              'char_captions': [
                {'char_caption': 'bad anatomy'},
                {'char_caption': 'bad hands'},
              ],
            },
          },
        });

        final testImage = img.Image(width: 64, height: 64);
        testImage.textData = {'Comment': naiJson};
        final pngBytes = Uint8List.fromList(img.encodePng(testImage));

        final result = ImageMetadataService.parseMetadata(pngBytes);
        expect(result, isNotNull);
        expect(
          result!.characterPrompts,
          equals(['girl with dragon', 'girl with sword']),
        );
        expect(
          result.characterNegativePrompts,
          equals(['bad anatomy', 'bad hands']),
        );
      },
    );

    test('round-trips V5 Auto Text teXt: block back to base prompt', () {
      const params = NaiGenerationParams(
        prompt: '1girl, "WELCOME", neon sign',
        negativePrompt: 'blurry',
        model: NaiModel.v5Full,
      );

      final blank = img.Image(width: 48, height: 48);
      final pngWithMeta = ImageMetadataService.embedNovelAiMetadata(
        pngBytes: Uint8List.fromList(img.encodePng(blank)),
        params: params,
        seed: 1234567,
      );

      // 生效文本: 质量词在 teXt: 之前 (官网顺序)
      final textData = ImageMetadataService.extractPngTextData(pngWithMeta);
      final comment = jsonDecode(textData['Comment']!) as Map<String, dynamic>;
      expect(
        comment['prompt'],
        equals(
          '1girl, "WELCOME", neon sign, very aesthetic, masterpiece, no text, teXt: WELCOME',
        ),
      );

      // 读回：剥 teXt: 段 + 质量词后缀 → 还原基础提示词
      final result = ImageMetadataService.parseMetadata(pngWithMeta);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, "WELCOME", neon sign'));
      expect(result.negativePrompt, equals('blurry'));
    });

    test(
      'writes iTXt (not tEXt) when prompt contains Chinese, per PNG spec',
      () {
        // PNG 规范: tEXt 为 Latin-1 字节；含中文时必须改写 UTF-8 iTXt，
        // 否则官方读取器按 Latin-1 解出乱码。
        const chinesePrompt = '1girl, 男孩第一人称视角，伸出一只手看手机，屏幕顶部居中显示大号白色时间：“23:27”';
        const params = NaiGenerationParams(
          prompt: chinesePrompt,
          negativePrompt: 'lowres',
          model: NaiModel.v5Full,
        );

        final blank = img.Image(width: 48, height: 48);
        final pngWithMeta = ImageMetadataService.embedNovelAiMetadata(
          pngBytes: Uint8List.fromList(img.encodePng(blank)),
          params: params,
          seed: 7,
        );

        // 含中文的 Description/Comment 必须走 iTXt；Title/Software/Source 仍为 tEXt
        final types = _chunkKeywordsByType(pngWithMeta);
        expect(types['iTXt'], containsAll(['Description', 'Comment']));
        expect(types['tEXt'], containsAll(['Title', 'Software', 'Source']));
        expect(types['tEXt'], isNot(contains('Description')));
        expect(types['tEXt'], isNot(contains('Comment')));

        // 读回不乱码
        final result = ImageMetadataService.parseMetadata(pngWithMeta);
        expect(result, isNotNull);
        expect(result!.prompt, contains('男孩第一人称视角'));
        expect(result.prompt, contains('大号白色时间'));
      },
    );

    test(
      'writes Latin-1 tEXt for ASCII prompts (spec-compliant legacy layout)',
      () {
        const params = NaiGenerationParams(
          prompt: '1girl, masterpiece, solo',
          negativePrompt: 'lowres',
          model: NaiModel.v5Full,
        );

        final blank = img.Image(width: 48, height: 48);
        final pngWithMeta = ImageMetadataService.embedNovelAiMetadata(
          pngBytes: Uint8List.fromList(img.encodePng(blank)),
          params: params,
          seed: 99,
        );

        // 纯 ASCII 时必须写 tEXt (与官方图片布局一致)，不得多余写 iTXt
        final types = _chunkKeywordsByType(pngWithMeta);
        expect(
          types['tEXt'],
          containsAll([
            'Title',
            'Software',
            'Source',
            'Description',
            'Comment',
          ]),
        );
        expect(types.containsKey('iTXt'), isFalse);

        final result = ImageMetadataService.parseMetadata(pngWithMeta);
        expect(result, isNotNull);
        expect(result!.prompt, equals('1girl, masterpiece, solo'));
      },
    );

    test(
      'reads UTF-8 Chinese text chunks without mojibake (official site layout)',
      () {
        // 官方网页可能把 UTF-8 字节直接写进 tEXt 块，读取侧需 UTF-8 优先探测。
        // 修复前读取侧按 Latin-1 解码，中文会变成 "ç”·å­©" 乱码。
        const chinesePrompt =
            '1girl, nahida_(genshin_impact), 男孩第一人称视角，伸出一只手看手机，屏幕顶部居中显示大号白色时间：“23:27”';
        const params = NaiGenerationParams(
          prompt: chinesePrompt,
          negativePrompt: 'lowres',
          model: NaiModel.v5Full,
        );

        final blank = img.Image(width: 48, height: 48);
        final pngWithMeta = ImageMetadataService.embedNovelAiMetadata(
          pngBytes: Uint8List.fromList(img.encodePng(blank)),
          params: params,
          seed: 42,
        );

        final textData = ImageMetadataService.extractPngTextData(pngWithMeta);
        expect(textData['Description'], contains('男孩第一人称视角'));

        final result = ImageMetadataService.parseMetadata(pngWithMeta);
        expect(result, isNotNull);
        expect(result!.prompt, contains('男孩第一人称视角'));
        expect(result.prompt, contains('大号白色时间'));
      },
    );

    test('falls back to Latin-1 for legacy non-UTF-8 text chunk values', () {
      // 老图可能把 Latin-1 高位字节写进 tEXt；字节序列不是合法 UTF-8 时应回退 Latin-1。
      int crc32(Uint8List data) {
        var crc = 0xFFFFFFFF;
        for (final b in data) {
          crc ^= b;
          for (var i = 0; i < 8; i++) {
            final mask = (crc & 1) != 0 ? 0xEDB88320 : 0;
            crc = (crc >> 1) ^ mask;
          }
        }
        return crc ^ 0xFFFFFFFF;
      }

      Uint8List chunk(String type, List<int> data) {
        final typeBytes = type.codeUnits;
        final body = [...typeBytes, ...data];
        final lengthBytes = ByteData(4)..setUint32(0, data.length);
        final crcBytes = ByteData(4)
          ..setUint32(0, crc32(Uint8List.fromList(body)));
        return Uint8List.fromList(
          lengthBytes.buffer.asUint8List().toList()
            ..addAll(body)
            ..addAll(crcBytes.buffer.asUint8List().toList()),
        );
      }

      // 最小合法 PNG: 签名 + IHDR(1x1 灰度) + tEXt(Comment = 单字节 0xE9, 合法 Latin-1 "é" 但非法 UTF-8) + IEND
      const u32one = [0, 0, 0, 1];
      final ihdrData = [
        ...u32one,
        ...u32one,
        8,
        0,
        0,
        0,
        0, // width, height, bitDepth, colorType, compression, filter, interlace
      ];
      final png = Uint8List.fromList([
        ...[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A],
        ...chunk('IHDR', ihdrData),
        ...chunk('tEXt', [...'Comment'.codeUnits, 0, 0xE9]),
        ...chunk('IEND', const []),
      ]);

      final textData = ImageMetadataService.extractPngTextData(png);
      expect(textData['Comment'], equals('é'));
    });

    test('keeps legacy comment intact when no preset hints present', () {
      // 旧格式/第三方 comment：无任何预设字段时不做剥离，保留完整文本
      final naiJson = jsonEncode({
        'prompt': '1girl, masterpiece, solo',
        'uc': 'lowres, bad anatomy',
        'steps': 28,
        'scale': 5.5,
        'seed': 12345678,
        'sampler': 'k_euler',
        'width': 832,
        'height': 1216,
        'Source': 'NovelAI Diffusion V5',
      });

      final testImage = img.Image(width: 64, height: 64);
      testImage.textData = {'Comment': naiJson};
      final pngBytes = Uint8List.fromList(img.encodePng(testImage));

      final result = ImageMetadataService.parseMetadata(pngBytes);
      expect(result, isNotNull);
      expect(result!.prompt, equals('1girl, masterpiece, solo'));
      expect(result.negativePrompt, equals('lowres, bad anatomy'));
      expect(result.qualityToggle, isNull);
      expect(result.ucPreset, isNull);
    });
  });
}

/// 解析 PNG 文本块，返回「块类型 → 关键字列表」映射，用于断言写入侧布局。
Map<String, List<String>> _chunkKeywordsByType(Uint8List png) {
  const signatureLength = 8;
  final result = <String, List<String>>{};
  var offset = signatureLength;
  while (offset + 12 <= png.length) {
    final length = ByteData.sublistView(png, offset, offset + 4).getUint32(0);
    final type = String.fromCharCodes(png.sublist(offset + 4, offset + 8));
    final data = png.sublist(offset + 8, offset + 8 + length);
    if (type == 'tEXt' || type == 'iTXt') {
      final keywordEnd = data.indexOf(0);
      if (keywordEnd > 0) {
        result
            .putIfAbsent(type, () => [])
            .add(String.fromCharCodes(data.sublist(0, keywordEnd)));
      }
    }
    offset += 12 + length;
  }
  return result;
}
