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
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00,
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

      final textDataAfter = ImageMetadataService.extractPngTextData(strippedPng);
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
      expect(restored.characterNegativePrompts, equals(model.characterNegativePrompts));
      expect(restored.rawJson, equals(model.rawJson));
      expect(restored.hasData, isTrue);
    });

    test('embedNovelAiMetadata embeds NovelAI chunks and parseMetadata reads it back correctly', () {
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
    });
  });
}
