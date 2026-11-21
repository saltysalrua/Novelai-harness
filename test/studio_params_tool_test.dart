import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/tools/studio_params_tool.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/anlas_calculator.dart';

void main() {
  group('buildStudioParamsReport', () {
    test('包含全部关键字段与 Opus 状态', () {
      final report = buildStudioParamsReport(
        const NaiGenerationParams(prompt: '1girl', steps: 28),
      );

      expect(report, contains('正向提示词: 1girl'));
      expect(report, contains('负向提示词: (空)'));
      expect(report, contains('绘图模型:'));
      expect(report, contains('画面尺寸:'));
      expect(report, contains('采样步数: 28 步'));
      expect(report, contains('CFG 强度:'));
      expect(report, contains('采样算法:'));
      expect(report, contains('噪声调度:'));
      expect(report, contains('质量标签:'));
      expect(report, contains('随机种子: 随机 (-1)'));
      // 默认 832x1216@28 在免费区间内: 显示精确点数预估
      expect(report, contains('点数预估: 符合 Opus 免费区间 (0 Anlas；无订阅 30 Anlas)'));
    });

    test('自定义标题生效 (区分工具查询与 /params 指令场景)', () {
      final report = buildStudioParamsReport(
        const NaiGenerationParams(prompt: ''),
        title: '工作台当前生图参数：',
      );

      expect(report.startsWith('工作台当前生图参数：'), isTrue);
      expect(report, contains('正向提示词: (空)'));
    });

    test('节约档报表展示实际发出的锁定参数', () {
      final report = buildStudioParamsReport(
        const NaiGenerationParams(
          prompt: '1girl',
          model: NaiModel.v5Full,
          effort: NaiEffort.medium,
          steps: 28,
          sampler: NaiSampler.kEuler,
          cfgRescale: 0.3,
        ),
      );

      expect(report, contains('nai-diffusion-5-full-medium'));
      expect(report, contains('算力: 节约'));
      expect(report, contains('采样步数: 14 步'));
      expect(report, contains('Euler Ancestral'));
      expect(report, contains('Rescale: 0.0'));
    });
  });

  group('NovelAiUpdateParamsTool effort locks', () {
    test('节约档拒绝改写步数、采样器、重缩放和排除词', () async {
      var state = const NaiGenerationParams(
        prompt: '1girl',
        model: NaiModel.v5Full,
        effort: NaiEffort.medium,
        steps: 28,
        scale: 7,
        cfgRescale: 0.2,
        sampler: NaiSampler.kEuler,
        negativePrompt: 'blur',
      );
      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => state,
        onUpdateParams: (value) => state = value,
      );

      final locked = await tool.execute('lock', {
        'steps': 40,
        'sampler': 'k_euler',
        'cfg_rescale': 0.8,
        'negative_prompt': 'hat',
        'scale': 8.5,
      });

      expect(locked.isError, isFalse);
      expect(locked.content, contains('CFG Scale: 8.5'));
      expect(locked.content, contains('节约档'));
      expect(state.steps, equals(28));
      expect(state.sampler, equals(NaiSampler.kEuler));
      expect(state.cfgRescale, equals(0.2));
      expect(state.negativePrompt, equals('blur'));
      expect(state.scale, equals(8.5));
      expect(state.toApiPayload()['parameters']['steps'], equals(14));
      expect(
        AnlasCalculator.estimateGenerationCost(params: state, isOpus: false),
        equals(
          AnlasCalculator.calculateFromValues(
            width: state.width,
            height: state.height,
            steps: 14,
            nSamples: state.nSamples,
            model: state.model,
          ),
        ),
      );
    });
  });

  group('NovelAiUpdateParamsTool quality presets', () {
    for (final off in ['Off', 'None']) {
      test('$off disables quality text and request metadata together', () async {
        var state = const NaiGenerationParams(
          prompt: '1girl, manga',
          model: NaiModel.v5Full,
          qualityToggle: true,
          qualityPreset: 'Standard',
        );
        final tool = NovelAiUpdateParamsTool(
          getCurrentParams: () => state,
          onUpdateParams: (value) => state = value,
        );

        await tool.execute('quality-off', {'quality_preset': off});

        expect(state.effectivePrompt, '1girl, manga');
        final payload = state.toApiPayload();
        final parameters = payload['parameters'] as Map<String, dynamic>;
        expect(payload['input'], '1girl, manga');
        expect(parameters['qualityPresetId'], 'none');
        expect(parameters['tag_hint_qt'], 0);
        final report =
            await NovelAiGetStudioParamsTool(
              getCurrentParams: () => state,
            ).execute('quality-state', {
              'keys': ['quality_preset'],
            });
        expect(report.content, contains('质量标签: Off'));
      });
    }

    test('selecting a quality preset re-enables its effective suffix', () async {
      var state = const NaiGenerationParams(
        prompt: '1girl, manga',
        model: NaiModel.v5Full,
        qualityToggle: false,
        qualityPreset: 'Standard',
      );
      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => state,
        onUpdateParams: (value) => state = value,
      );
      await tool.execute('quality-light', {'quality_preset': 'Light'});

      expect(state.effectivePrompt, contains('amazing quality'));
      expect(state.effectivePrompt, isNot(contains('masterpiece')));
      final parameters =
          state.toApiPayload()['parameters'] as Map<String, dynamic>;
      expect(parameters['qualityPresetId'], 'light');
      expect(parameters['tag_hint_qt'], 3);
    });

    test(
      'a locked quality setting cannot disable the effective preset',
      () async {
        var state = const NaiGenerationParams(
          prompt: '1girl, manga',
          model: NaiModel.v5Full,
        );
        final before = state.effectivePrompt;
        final tool = NovelAiUpdateParamsTool(
          getCurrentParams: () => state,
          onUpdateParams: (value) => state = value,
          permissionChecker: (key) => key != PresetParamKeys.qualityPreset,
        );
        final result = await tool.execute('locked', {'quality_preset': 'Off'});
        expect(result.isError, isTrue);
        expect(state.effectivePrompt, before);
        expect(state.qualityToggle, isTrue);
      },
    );
  });
}
