import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/novelai_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Config extends ConfigService {
  final bool stream;
  _Config(this.stream);

  @override
  Future<AppConfig> loadConfig() async => AppConfig(
    novelAiKey: 'mock-only',
    enableStreamPreview: stream,
    enableImagePersistence: false,
    enableTagDictionaryAutoUpdate: false,
    autoSaveImages: false,
  );
}

/// 完全替换网络与落图边界，不读取凭证或请求真实 NovelAI。
class _Repository extends NovelAiRepository {
  final requests = <NaiGenerationParams>[];
  bool fail = false;

  @override
  Future<NaiAccountInfo> fetchAccountInfo({required String apiKey}) async =>
      NaiAccountInfo.fromJson({
        'subscription': {'tier': 3, 'active': true},
      });

  NaiGeneratedImage _generate(NaiGenerationParams params) {
    requests.add(params);
    if (fail) throw StateError('mock generation failure');
    return NaiGeneratedImage(
      id: 'mock-${requests.length}',
      bytes: Uint8List(0),
      params: params,
      createdAt: DateTime(2026),
      seed: params.seed,
      isOpusFree: true,
    );
  }

  @override
  Future<List<NaiGeneratedImage>> generate({
    required String apiKey,
    required NaiGenerationParams params,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
    String imageSaveTemplate = '',
  }) async => [_generate(params)];

  @override
  Stream<NaiStreamProgress> generateStream({
    required String apiKey,
    required NaiGenerationParams params,
    required String saveDir,
    bool enablePersistence = true,
    int maxImages = 50,
    bool stripMetadata = false,
    bool enableWatermark = false,
    bool keepOriginalImage = false,
    WatermarkConfig? watermarkConfig,
    Uint8List? watermarkBytes,
    bool autoSave = true,
    String imageSaveTemplate = '',
  }) async* {
    final image = _generate(params);
    yield NaiStreamProgress.finalResult(
      finalImage: image.bytes,
      generatedImage: image,
      totalSteps: params.steps,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('agent-seed-test-');
  });
  tearDown(() => temp.deleteSync(recursive: true));

  for (final stream in [false, true]) {
    for (final mode in NaiSeedMode.values) {
      for (final timing in NaiSeedTiming.values) {
        test('Agent seed: stream=$stream, ${mode.id}, ${timing.id}', () async {
          final config = _Config(stream);
          final repository = _Repository();
          final vm = StudioViewModel(
            configService: config,
            repository: repository,
            sessionLogBaseDir: temp.path,
          );
          addTearDown(vm.dispose);
          await vm.init();
          vm.updateParams(
            vm.params.copyWith(
              prompt: 'landscape',
              seed: 100,
              seedMode: mode,
              seedTiming: timing,
            ),
          );
          final tool = vm.availableTools
              .whereType<NovelAiGenerateTool>()
              .single;
          for (var i = 0; i < 2; i++) {
            final result = await tool.execute('generate-$i', {});
            expect(result.isError, isFalse, reason: result.content);
            expect(
              result.content,
              contains('随机种子: ${repository.requests.last.seed}'),
            );
          }
          final seeds = repository.requests.map((p) => p.seed).toList();
          switch (mode) {
            case NaiSeedMode.fixed:
              expect(seeds, [100, 100]);
              expect(vm.params.seed, 100);
            case NaiSeedMode.increase:
              expect(
                seeds,
                timing == NaiSeedTiming.before ? [101, 102] : [100, 101],
              );
              expect(vm.params.seed, 102);
            case NaiSeedMode.random:
              expect(seeds[1], isNot(seeds[0]));
              if (timing == NaiSeedTiming.before) {
                expect(seeds[0], isNot(100));
                expect(vm.params.seed, seeds.last);
              } else {
                expect(seeds[0], 100);
                expect(vm.params.seed, isNot(seeds.last));
              }
          }
          await vm.flushPendingSaves();
          final saved = await config.loadStudioParameters(
            const NaiGenerationParams(prompt: ''),
          );
          expect(saved.generation.seed, vm.params.seed);
          expect(saved.generation.seedMode, mode);
          expect(saved.generation.seedTiming, timing);
        });
      }
    }

    test(
      'failed Agent generation does not advance after seed ($stream)',
      () async {
        final repository = _Repository()..fail = true;
        final vm = StudioViewModel(
          configService: _Config(stream),
          repository: repository,
          sessionLogBaseDir: temp.path,
        );
        addTearDown(vm.dispose);
        await vm.init();
        vm.updateParams(
          vm.params.copyWith(
            prompt: 'landscape',
            seed: 100,
            seedMode: NaiSeedMode.increase,
            seedTiming: NaiSeedTiming.after,
          ),
        );
        final tool = vm.availableTools.whereType<NovelAiGenerateTool>().single;
        expect((await tool.execute('fail', {})).isError, isTrue);
        expect(vm.params.seed, 100);
        await vm.flushPendingSaves();
      },
    );
  }

  test(
    'rejected paid generation never mutates seed or reaches repository',
    () async {
      final repository = _Repository();
      var beforeCalled = false;
      final tool = NovelAiGenerateTool(
        repository: repository,
        configService: _Config(false),
        getCurrentParams: () => const NaiGenerationParams(
          prompt: 'landscape',
          seed: 100,
          width: 2048,
          height: 2048,
        ),
        getAccountInfo: () => NaiAccountInfo.fromJson({}),
        onBeforeGenerate: () => beforeCalled = true,
        onConfirmPaidGeneration:
            ({required params, required estimatedCost}) async => false,
      );
      expect((await tool.execute('cancel', {})).isError, isTrue);
      expect(beforeCalled, isFalse);
      expect(repository.requests, isEmpty);
    },
  );
}
