import 'package:flutter_test/flutter_test.dart';
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
}
