import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/anlas_calculator.dart';
import 'package:novelai_harness/data/services/image_edit_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<Uint8List> _png(int width, int height) async {
  final recorder = ui.PictureRecorder();
  Canvas(recorder).drawColor(Colors.blue, BlendMode.src);
  final picture = recorder.endRecording();
  final image = await picture.toImage(width, height);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

void main() {
  testWidgets('界面选择 4K：1664x2432 原图不缩小上传，new-api 配置和成品尺寸贯通', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final dir = Directory.systemTemp.createTempSync('nai_ai_edit_resolution_');
    addTearDown(() => dir.deleteSync(recursive: true));
    late Uint8List source;
    late Uint8List output;
    await tester.runAsync(() async {
      source = await _png(1664, 2432);
      // 模拟供应商返回的一张高分辨率竖图，不把 4K 档位强制解释为固定宽高。
      output = await _png(2816, 4096);
    });
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.path, '/v1/chat/completions');
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      expect(body['model'], 'gemini-3-pro-image');
      expect(body['extra_body'], {
        'google': {
          'image_config': {'image_size': '4K'},
        },
      });
      expect(body['image_config'], {'image_size': '4K'});
      final messages = body['messages'] as List<dynamic>;
      final content = messages.first['content'] as List<dynamic>;
      final dataUrl = content.last['image_url']['url'] as String;
      // 整段原图字节一致，防止误用对话视觉附件的 1024px 压缩链路。
      expect(base64Decode(dataUrl.split(',').last), source);
      return http.Response.bytes(
        utf8.encode(
          jsonEncode({
            'choices': [
              {
                'message': {
                  'images': [
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/png;base64,${base64Encode(output)}',
                      },
                    },
                  ],
                },
              },
            ],
          }),
        ),
        200,
      );
    });
    addTearDown(client.close);
    final repo = NovelAiRepository(
      imageEditService: ImageEditService(client: client),
    );
    final vm = StudioViewModel(repository: repo);
    addTearDown(vm.dispose);
    const provider = LlmProviderConfig(
      id: 'mock-edit',
      name: 'Mock',
      apiKey: 'mock-key',
      baseUrl: 'https://example.invalid/v1',
      models: [
        LlmModelConfig(
          id: 'gemini-3-pro-image',
          name: 'Gemini 3 Pro Image',
          imageOutput: true,
        ),
      ],
    );
    await tester.runAsync(() async {
      await vm.updateConfig(
        vm.config.copyWith(
          llmProviders: [provider],
          imageEditProviderId: provider.id,
          imageEditModelId: provider.models.single.id,
          saveDirectory: dir.path,
          autoSaveImages: true,
          imageSaveTemplate: '{resolution}',
        ),
      );
    });
    vm.setInpaintSourceImage(
      NaiGeneratedImage(
        id: 'source',
        bytes: source,
        params: const NaiGenerationParams(
          prompt: '',
          width: 1664,
          height: 2432,
        ),
        seed: 1,
        isOpusFree: false,
        createdAt: DateTime.now(),
      ),
    );
    vm.setInpaintMode(InpaintMode.aiEdit);
    vm.setInpaintUseMainPrompt(false);
    vm.setInpaintCustomPrompt('只修改背景，保持人物不变');

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: InpaintPage(viewModel: vm)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('默认'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('4K').last);
    await tester.pumpAndSettle();
    expect(vm.inpaintParams.aiEditResolution, '4K');
    expect(vm.inpaintParams.aiEditAspectRatio, isEmpty);
    expect(find.text('4K'), findsOneWidget);
    expect(find.text('跟随原图'), findsOneWidget);

    await tester.runAsync(() async {
      await vm.executeInpaint();
      expect(vm.errorMessage, isNull);
      expect(requests, 1);
      final result = repo.history.single;
      expect(result.isAiEdited, isTrue);
      expect(result.bytes, output);
      expect(result.params.width, 2816);
      expect(result.params.height, 4096);
      expect(vm.inpaintSourceImage!.id, result.id);
      expect(File(result.originalFilePath!).readAsBytesSync(), output);
      expect(result.localFilePath, endsWith('2816x4096.png'));
      final savedDims = await AnlasCalculator.decodeImageDimensions(
        File(result.localFilePath!).readAsBytesSync(),
      );
      expect(savedDims?.width, 2816);
      expect(savedDims?.height, 4096);
    });
    await tester.pumpAndSettle();
    expect(find.text('4K'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
