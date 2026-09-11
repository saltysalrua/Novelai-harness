import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_number_slider.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/resolution_pad_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _generation = NaiGenerationParams(
  prompt: '中文测试提示词',
  negativePrompt: 'blur',
  model: NaiModel.v5Curated,
  width: 1344,
  height: 768,
  steps: 24,
  scale: 6.7,
  cfgRescale: 0.23,
  sampler: NaiSampler.kEulerAncestral,
  noiseSchedule: NoiseSchedule.exponential,
  seed: 4294967294,
  seedMode: NaiSeedMode.fixed,
  seedTiming: NaiSeedTiming.after,
  nSamples: 3,
  qualityToggle: false,
  qualityPreset: 'Light',
  ucPresetKey: 'Human Focus',
  transparentBg: true,
  prefixPrompt: 'prefix',
  suffixPrompt: 'suffix',
  applyFixedPrompts: false,
  characterAiPosition: false,
  characterPrompts: [
    NaiCharacterPrompt(
      id: 'test-character',
      name: '角色',
      prompt: 'girl, red hair',
      negativePrompt: 'hat',
      enabled: false,
      useCustomPosition: true,
      positionX: 0.18,
      positionY: 0.62,
    ),
  ],
);

const _inpaint = InpaintParams(
  mode: InpaintMode.aiEdit,
  strength: 0.85,
  noise: 0.15,
  contextPadding: 96,
  brushRadius: 0.05,
  customPrompt: '修复用提示词',
  customNegativePrompt: '修复用负面词',
  useMainPrompt: false,
  useMainNegative: false,
  customModel: NaiModel.v4Full,
  customSteps: 21,
  customScale: 4.5,
  aiEditAspectRatio: '16:9',
  aiEditResolution: '2K',
);

/// 不读取本机私有配置，不加载图片历史或调用线上端点。
class _TestConfigService extends ConfigService {
  AppConfig _config = const AppConfig(
    enableImagePersistence: false,
    enableTagDictionaryAutoUpdate: false,
    defaultSteps: 23,
    defaultScale: 7,
  );
  final _saved = <NaiGenerationParams>[];
  Completer<void>? _saveBlocker;

  @override
  Future<AppConfig> loadConfig() async => _config;

  @override
  Future<void> saveConfig(AppConfig config) async {
    _config = config;
    await super.saveConfig(config);
  }

  @override
  Future<void> saveStudioParameters(
    NaiGenerationParams generation,
    InpaintParams inpaint,
  ) async {
    _saved.add(generation);
    await _saveBlocker?.future;
    await super.saveStudioParameters(generation, inpaint);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late _TestConfigService service;
  final viewModels = <StudioViewModel>[];

  StudioViewModel createViewModel() {
    final vm = StudioViewModel(
      configService: service,
      sessionLogBaseDir: temp.path,
    );
    viewModels.add(vm);
    return vm;
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    temp = Directory.systemTemp.createTempSync('studio_params_');
    PromptLibraryService.instance.setCustomStorageDirectory(temp.path);
    service = _TestConfigService();
  });

  tearDown(() async {
    for (final vm in viewModels) {
      await vm.flushPendingSaves();
      vm.dispose();
    }
    viewModels.clear();
    PromptLibraryService.instance.setCustomStorageDirectory(null);
    await temp.delete(recursive: true);
  });

  test('完整生图参数和修复设置一次往返，不存旧图片几何', () async {
    await service.saveStudioParameters(
      _generation,
      _inpaint.copyWith(
        selectionRect: const Rect.fromLTWH(0.1, 0.2, 0.3, 0.4),
        maskBounds: const Rect.fromLTWH(0.1, 0.2, 0.1, 0.1),
        brushStrokes: const [
          InpaintBrushStroke(points: [Offset(0.2, 0.3)], radius: 0.04),
        ],
      ),
    );
    final restored = await ConfigService().loadStudioParameters(
      const NaiGenerationParams(prompt: ''),
    );
    expect(restored.generation.toJson(), _generation.toJson());
    expect(restored.inpaint.toJson(), _inpaint.toJson());
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('novelai_studio_parameters')!;
    expect(raw, isNot(contains('selectionRect')));
    expect(raw, isNot(contains('brushStrokes')));
    expect(raw, isNot(contains('maskBounds')));
  });

  test('旧版散项与设置默认值兼容迁移，优先恢复已有完整快照', () async {
    await service.saveLastPrompt('旧草稿');
    await service.saveApplyFixedPrompts(true);
    await service.saveCharacterPrompts(_generation.characterPrompts);
    await service.saveCharacterAiPosition(false);
    await service.saveSeedMode(NaiSeedMode.increase);
    await service.saveSeedTiming(NaiSeedTiming.after);
    final oldVm = createViewModel();
    await oldVm.init();
    expect(oldVm.params.prompt, '旧草稿');
    expect(oldVm.params.scale, 7);
    expect(oldVm.params.steps, 23);
    expect(oldVm.params.applyFixedPrompts, isTrue);
    expect(oldVm.params.seedMode, NaiSeedMode.increase);
    expect(oldVm.params.seedTiming, NaiSeedTiming.after);
    expect(oldVm.params.characterAiPosition, isFalse);
    expect(oldVm.params.characterPrompts.single.name, '角色');

    oldVm.updateParams(_generation);
    oldVm.updateInpaintParams(_inpaint);
    await oldVm.flushPendingParameterSave();
    final restarted = createViewModel();
    await restarted.init();
    expect(restarted.params.toJson(), _generation.toJson());
    expect(restarted.inpaintParams.toJson(), _inpaint.toJson());
    expect(restarted.config.defaultScale, 7, reason: '工作台值不能污染设置页默认值');
  });

  for (final raw in ['{broken', '[]', '{"generation":{"qualityToggle":42}}']) {
    test('损坏快照安全回退：$raw', () async {
      SharedPreferences.setMockInitialValues({
        'novelai_studio_parameters': raw,
      });
      final restored = await service.loadStudioParameters(_generation);
      expect(restored.generation.toJson(), _generation.toJson());
      expect(restored.inpaint.toJson(), const InpaintParams().toJson());
    });
  }

  test('部分快照继承迁移默认值，读取时也丢弃任何旧蒙版', () async {
    SharedPreferences.setMockInitialValues({
      'novelai_studio_parameters': jsonEncode({
        'generation': {'scale': 8.2},
        'inpaint': {
          'noise': 0.2,
          'selectionRect': {'invalid': true},
          'maskBounds': {'invalid': true},
          'brushStrokes': 'invalid',
        },
      }),
    });
    final restored = await service.loadStudioParameters(_generation);
    expect(
      restored.generation.toJson(),
      _generation.copyWith(scale: 8.2).toJson(),
    );
    expect(restored.inpaint.noise, 0.2);
    expect(restored.inpaint.selectionRect, isNull);
    expect(restored.inpaint.maskBounds, isNull);
    expect(restored.inpaint.brushStrokes, isEmpty);
  });

  test('快速连续修改合并保存，关闭冲刷无需等防抖到期', () async {
    final vm = createViewModel();
    vm.updateParams(_generation.copyWith(scale: 5));
    vm.updateParams(_generation.copyWith(scale: 6));
    vm.updateParams(_generation.copyWith(scale: 8));
    expect(service._saved, isEmpty);
    await vm.flushPendingParameterSave();
    expect(service._saved, hasLength(1));
    expect(service._saved.single.scale, 8);
    final restored = await service.loadStudioParameters(_generation);
    expect(restored.generation.scale, 8);
  });

  test('慢旧写入不能覆盖新快照，flush 等待全部排队写入', () async {
    final vm = createViewModel();
    service._saveBlocker = Completer<void>();
    vm.updateParams(_generation.copyWith(scale: 5));
    final first = vm.flushPendingParameterSave();
    await Future<void>.delayed(Duration.zero);
    vm.updateParams(_generation.copyWith(scale: 9));
    final second = vm.flushPendingParameterSave();
    await Future<void>.delayed(Duration.zero);
    expect(service._saved, hasLength(1));
    service._saveBlocker!.complete();
    await Future.wait([first, second]);
    expect(service._saved.map((p) => p.scale), [5, 9]);
    expect(
      (await service.loadStudioParameters(_generation)).generation.scale,
      9,
    );
  });

  test('只修改默认设置的差异项，保存无关设置不覆盖工作台', () async {
    final vm = createViewModel();
    await vm.init();
    vm.updateParams(_generation);
    await vm.updateConfig(vm.config.copyWith(stripMetadata: true));
    expect(vm.params.toJson(), _generation.toJson());
    await vm.updateConfig(vm.config.copyWith(defaultScale: 8.1));
    expect(vm.params.toJson(), _generation.copyWith(scale: 8.1).toJson());
    await vm.flushPendingSaves();
    final restarted = createViewModel();
    await restarted.init();
    expect(restarted.params.toJson(), vm.params.toJson());
    expect(restarted.config.stripMetadata, isTrue);
  });

  test('启动恢复前关闭不会以出厂参数覆盖已有快照', () async {
    await service.saveStudioParameters(_generation, _inpaint);
    final vm = createViewModel();
    await vm.flushPendingSaves();
    final saved = await service.loadStudioParameters(vm.params);
    expect(saved.generation.toJson(), _generation.toJson());
    expect(saved.inpaint.toJson(), _inpaint.toJson());
    expect(service._saved, hasLength(1));
  });

  test('修复各设置入口与角色位置快捷入口都触发保存', () async {
    final vm = createViewModel();
    vm.updateParams(_generation.copyWith(characterAiPosition: true));
    vm.setEditingCharacterPositions(true);
    vm.setInpaintMode(_inpaint.mode);
    vm.setInpaintContextPadding(_inpaint.contextPadding);
    vm.setInpaintStrength(_inpaint.strength);
    vm.setInpaintNoise(_inpaint.noise);
    vm.setInpaintBrushRadius(_inpaint.brushRadius);
    vm.setInpaintCustomPrompt(_inpaint.customPrompt);
    vm.setInpaintCustomNegativePrompt(_inpaint.customNegativePrompt);
    vm.setInpaintUseMainPrompt(false);
    vm.setInpaintUseMainNegative(false);
    vm.setInpaintCustomModel(_inpaint.customModel);
    vm.setInpaintAiEditAspectRatio(_inpaint.aiEditAspectRatio);
    vm.setInpaintAiEditResolution(_inpaint.aiEditResolution);
    await vm.flushPendingParameterSave();
    final restored = await service.loadStudioParameters(_generation);
    expect(restored.generation.characterAiPosition, isFalse);
    expect(restored.inpaint.toJson(), vm.inpaintParams.toJson());
    vm.setInpaintCustomModel(null);
    await vm.flushPendingParameterSave();
    expect(
      (await service.loadStudioParameters(_generation)).inpaint.customModel,
      isNull,
    );
  });

  testWidgets('300ms 后自动保存而非必须手动 flush', (tester) async {
    final vm = createViewModel();
    vm.updateParams(_generation);
    await tester.pump(const Duration(milliseconds: 299));
    expect(service._saved, isEmpty);
    await tester.pump(const Duration(milliseconds: 1));
    expect(service._saved, hasLength(1));
    expect(service._saved.single.toJson(), _generation.toJson());
  });

  testWidgets('重启后分辨率与 Prompt Guidance 的实际表单显示恢复值', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // 构造与初始化都放在真实异步区，避免会话写队列 Future 被假时钟挂起。
    final restarted = (await tester.runAsync(() async {
      final vm = createViewModel();
      await vm.init();
      vm.updateParams(_generation);
      await vm.flushPendingParameterSave();
      final restored = createViewModel();
      await restored.init();
      return restored;
    }))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 360,
              child: ListenableBuilder(
                listenable: restarted,
                builder: (context, _) => ParametersPage(viewModel: restarted),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final resolution = tester.widget<ResolutionPadPicker>(
      find.byType(ResolutionPadPicker),
    );
    expect(resolution.width, 1344);
    expect(resolution.height, 768);
    expect(find.text('1344'), findsOneWidget);
    expect(find.text('768'), findsOneWidget);
    final l10n = AppLocalizations.of(
      tester.element(find.byType(ParametersPage)),
    );
    final guidance = tester
        .widgetList<AppNumberSlider>(find.byType(AppNumberSlider))
        .singleWhere((slider) => slider.title == l10n.paramsPromptGuidance);
    expect(guidance.value, 6.7);
    resolution.onChanged((width: 1024, height: 1024));
    await tester.pump();
    final changedGuidance = tester
        .widgetList<AppNumberSlider>(find.byType(AppNumberSlider))
        .singleWhere((slider) => slider.title == l10n.paramsPromptGuidance);
    changedGuidance.onChanged(7.8);
    await tester.runAsync(restarted.flushPendingParameterSave);
    final saved = await service.loadStudioParameters(_generation);
    expect(saved.generation.width, 1024);
    expect(saved.generation.height, 1024);
    expect(saved.generation.scale, 7.8);
    expect(tester.takeException(), isNull);
  });
}
