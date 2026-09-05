import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/watermark_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/metadata_reader_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MetadataReaderDialog Widget Tests', () {
    late StudioViewModel viewModel;
    late Uint8List testImageBytes;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      viewModel = StudioViewModel(
        configService: ConfigService(),
        repository: NovelAiRepository(),
      );

      final dummy = img.Image(width: 48, height: 48);
      testImageBytes = Uint8List.fromList(img.encodePng(dummy));
    });

    testWidgets('Renders all metadata sections and applies to workbench', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const metadata = ImageMetadataResult(
        prompt: '1girl, white hair, masterpiece',
        negativePrompt: 'lowres, bad hands',
        steps: 28,
        scale: 6.0,
        seed: 777888,
        sampler: 'k_euler',
        width: 832,
        height: 1216,
        model: 'nai-diffusion-5',
        software: 'NovelAI',
        characterPrompts: ['cat ears, cute'],
        characterNegativePrompts: ['bad tail'],
        rawJson: '{"prompt":"1girl, white hair, masterpiece"}',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MetadataReaderDialog.show(
                  context,
                  metadata: metadata,
                  imageBytes: testImageBytes,
                  fileName: 'test_drop.png',
                  viewModel: viewModel,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.byType(MetadataReaderDialog), findsOneWidget);
      expect(find.text('test_drop.png'), findsOneWidget);
      expect(find.text('NovelAI'), findsOneWidget);
      expect(find.text('1girl, white hair, masterpiece'), findsOneWidget);
      expect(find.text('lowres, bad hands'), findsOneWidget);
      expect(find.text('角色 1'), findsOneWidget);
      expect(find.text('cat ears, cute'), findsOneWidget);
      expect(find.text('777888'), findsOneWidget);

      // 点击展开原始元数据
      await tester.ensureVisible(find.textContaining('原始元数据'));
      await tester.tap(find.textContaining('原始元数据'));
      await tester.pumpAndSettle();
      expect(
        find.text('{"prompt":"1girl, white hair, masterpiece"}'),
        findsOneWidget,
      );

      // 点击应用全部参数到工作台
      await tester.tap(find.text('应用全部参数到工作台'));
      await tester.pumpAndSettle();

      // 对话框应已关闭，且 ViewModel 参数被更新
      expect(find.byType(MetadataReaderDialog), findsNothing);
      expect(viewModel.params.prompt, equals('1girl, white hair, masterpiece'));
      expect(viewModel.params.negativePrompt, equals('lowres, bad hands'));
      expect(viewModel.params.steps, equals(28));
      expect(viewModel.params.scale, equals(6.0));
      expect(viewModel.params.seed, equals(777888));
      expect(viewModel.params.model, equals(NaiModel.v5Full));
      expect(viewModel.params.characterPrompts.length, equals(1));
      expect(
        viewModel.params.characterPrompts.first.prompt,
        equals('cat ears, cute'),
      );
      expect(
        viewModel.params.characterPrompts.first.negativePrompt,
        equals('bad tail'),
      );
    });

    test(
      'applyMetadataToWorkbench updates all parameters and resolves model/sampler/resolution',
      () {
        const fullMeta = ImageMetadataResult(
          prompt: 'scenery, starry sky, lake',
          negativePrompt: 'blurry, worst quality',
          steps: 32,
          scale: 7.5,
          cfgRescale: 0.2,
          seed: 12345678,
          sampler: 'k_euler_ancestral',
          noiseSchedule: 'karras',
          width: 1216,
          height: 832,
          model: 'nai-diffusion-4.5-full',
          qualityToggle: true,
          qualityPreset: '高质量预设',
          ucPreset: '通用负向词',
          transparentBackground: true,
          characterPrompts: ['girl holding umbrella', 'boy with cat'],
          characterNegativePrompts: ['bad hands', 'extra limbs'],
        );

        viewModel.applyMetadataToWorkbench(fullMeta);

        expect(viewModel.params.prompt, equals('scenery, starry sky, lake'));
        expect(
          viewModel.params.negativePrompt,
          equals('blurry, worst quality'),
        );
        expect(viewModel.params.steps, equals(32));
        expect(viewModel.params.scale, equals(7.5));
        expect(viewModel.params.cfgRescale, equals(0.2));
        expect(viewModel.params.seed, equals(12345678));
        expect(viewModel.params.model, equals(NaiModel.v45Full));
        expect(viewModel.params.sampler, equals(NaiSampler.kEulerAncestral));
        expect(viewModel.params.noiseSchedule, equals(NoiseSchedule.karras));
        expect(viewModel.params.width, equals(1216));
        expect(viewModel.params.height, equals(832));
        expect(viewModel.params.qualityToggle, isTrue);
        expect(viewModel.params.qualityPreset, equals('高质量预设'));
        expect(viewModel.params.ucPresetKey, equals('通用负向词'));
        expect(viewModel.params.transparentBg, isTrue);
        expect(viewModel.params.characterPrompts.length, equals(2));
        expect(
          viewModel.params.characterPrompts[0].prompt,
          equals('girl holding umbrella'),
        );
        expect(
          viewModel.params.characterPrompts[1].prompt,
          equals('boy with cat'),
        );
      },
    );

    testWidgets('Extract blind watermark button reveals embedded payload', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 构造一张已嵌入盲水印的图 (后台 isolate 嵌入)
      final image = img.Image(width: 256, height: 256);
      for (var y = 0; y < 256; y++) {
        for (var x = 0; x < 256; x++) {
          image.setPixel(x, y, img.ColorRgb8(100 + x ~/ 8, 120 + y ~/ 8, 160));
        }
      }
      final raw = Uint8List.fromList(img.encodePng(image));
      // Skia 解码是真实引擎异步：FakeAsync 下不会推进，必须包进 runAsync
      final embedded =
          await tester.runAsync(
            () => WatermarkService.embedBlindWatermarkAsync(
              raw,
              text: 'onii-chan-42',
            ),
          ) ??
          raw;

      const metadata = ImageMetadataResult(
        prompt: '1girl',
        software: 'NovelAI',
        rawJson: '{"prompt":"1girl"}',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MetadataReaderDialog.show(
                  context,
                  metadata: metadata,
                  imageBytes: embedded,
                  fileName: 'blind.png',
                  viewModel: viewModel,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // compute 在 FakeAsync 下不会推进：先 tap 再用 runAsync 等 Isolate 完成
      await tester.tap(find.text('提取盲水印'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pumpAndSettle();

      expect(find.text('盲水印内容'), findsOneWidget);
      expect(find.text('onii-chan-42'), findsOneWidget);
    });

    testWidgets('Extract blind watermark shows absent state for clean image', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const metadata = ImageMetadataResult(
        prompt: '1girl',
        software: 'NovelAI',
        rawJson: '{"prompt":"1girl"}',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => MetadataReaderDialog.show(
                  context,
                  metadata: metadata,
                  imageBytes: testImageBytes,
                  fileName: 'clean.png',
                  viewModel: viewModel,
                ),
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('提取盲水印'));
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 800));
      });
      await tester.pumpAndSettle();

      expect(find.text('未检测到盲水印'), findsOneWidget);
    });
  });
}
