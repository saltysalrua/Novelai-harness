import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/studio_params_tool.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

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
  });
}
