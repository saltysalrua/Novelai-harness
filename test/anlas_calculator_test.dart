import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/anlas_calculator.dart';

/// Anlas 预计消耗计算器测试 (移植自 Aaalice_NAI_Launcher 的计费机制)
///
/// 期望值由官方网页端基础公式验证得出:
/// ceil(2.951823174884865e-6 * pixels + 5.753298233447344e-7 * pixels * steps)
void main() {
  group('calculateFromValues 基础计费', () {
    test('Opus 免费区间内为 0 (832x1216@28)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: true,
        ),
        equals(0),
      );
    });

    test('非 Opus 同参数按基础价计费 (832x1216@28 = 20)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v3,
          isOpus: false,
        ),
        equals(20),
      );
    });

    test('V5 基础价乘 1.5 倍率 (832x1216@28 非 Opus = 30)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: false,
        ),
        equals(30),
      );
    });

    test('1024x1024@23 非 Opus V5 为 26 (倍率生效)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 1024,
          height: 1024,
          steps: 23,
          nSamples: 1,
          model: NaiModel.v5Curated,
          isOpus: false,
        ),
        equals(26),
      );
    });

    test('1024x1024@23 非 Opus V3 为 17 (无倍率)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 1024,
          height: 1024,
          steps: 23,
          nSamples: 1,
          model: NaiModel.v3,
          isOpus: false,
        ),
        equals(17),
      );
    });

    test('单张消耗下限为 2 Anlas', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 64,
          height: 64,
          steps: 1,
          nSamples: 1,
          model: NaiModel.v3,
        ),
        equals(2),
      );
    });

    test('超出计费上限返回 invalidCost', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 2048,
          height: 2048,
          steps: 50,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: false,
        ),
        equals(AnlasCalculator.invalidCost),
      );
    });
  });

  group('Opus 免费条件', () {
    test('步数超过 28 不再免费', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 29,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: true,
        ),
        equals(30), // V5: 基础价 20 × 1.5 倍率
      );
    });

    test('像素数超过 1048576 不再免费', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 1024,
          height: 1536,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v3,
          isOpus: true,
        ),
        equals(30),
      );
    });

    test('单次请求多张只有第一张免费 (Opus, n=2)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 2,
          model: NaiModel.v3,
          isOpus: true,
        ),
        equals(20), // 一张免费、一张付费
      );
    });

    test('单次请求多张全价 (非 Opus, n=2)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 2,
          model: NaiModel.v3,
          isOpus: false,
        ),
        equals(40),
      );
    });

    test('V5 体力配额透支后 Opus 免费失效', () {
      // 参数在免费区间内，但配额透支 → 按正常价 (30) 扣费
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: true,
          opusQuotaExhausted: true,
        ),
        equals(30),
      );
    });

    test('V4.5 不受体力配额限制 (透支标志不影响免费)', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v45Full,
          isOpus: true,
          opusQuotaExhausted: true,
        ),
        equals(0),
      );
    });
  });

  group('estimateGenerationCost 参数对象入口', () {
    test('按参数对象透传计算 (默认 V5 模型，像素超限无免费)', () {
      const params = NaiGenerationParams(
        prompt: 'test',
        width: 1024,
        height: 1536,
        steps: 28,
      );
      expect(
        AnlasCalculator.estimateGenerationCost(params: params, isOpus: true),
        equals(45), // 基础价 30 × V5 1.5 倍率
      );
      expect(
        AnlasCalculator.estimateGenerationCost(params: params, isOpus: false),
        equals(45),
      );
    });

    test('nSamples 透传', () {
      const params = NaiGenerationParams(
        prompt: 'test',
        width: 832,
        height: 1216,
        steps: 28,
        nSamples: 3,
      );
      // V5 单张 30: Opus 一张免费 + 两张付费 = 60；非 Opus 三张全价 = 90
      expect(
        AnlasCalculator.estimateGenerationCost(params: params, isOpus: true),
        equals(60),
      );
      expect(
        AnlasCalculator.estimateGenerationCost(params: params, isOpus: false),
        equals(90),
      );
    });
  });

  group('estimateUpscaleCost 官方超分分档', () {
    test('Opus 输入不超过 640x640 免费', () {
      expect(
        AnlasCalculator.estimateUpscaleCost(
          inputWidth: 640,
          inputHeight: 640,
          isOpus: true,
        ),
        equals(0),
      );
    });

    test('非 Opus 640x640 按 1 Anlas 分档', () {
      expect(
        AnlasCalculator.estimateUpscaleCost(
          inputWidth: 640,
          inputHeight: 640,
          isOpus: false,
        ),
        equals(1),
      );
    });

    test('Opus 超过 640x640 后不再免费 (832x1216 = 1)', () {
      expect(
        AnlasCalculator.estimateUpscaleCost(
          inputWidth: 832,
          inputHeight: 1216,
          isOpus: true,
        ),
        equals(1),
      );
    });

    test('输入面积第二档 (1216x1216 = 2)', () {
      expect(
        AnlasCalculator.estimateUpscaleCost(
          inputWidth: 1216,
          inputHeight: 1216,
        ),
        equals(2),
      );
    });

    test('超过最高 3MP 分档返回 invalidCost', () {
      expect(
        AnlasCalculator.estimateUpscaleCost(
          inputWidth: 1792,
          inputHeight: 2560,
        ),
        equals(AnlasCalculator.invalidCost),
      );
    });

    test('非法输入返回 invalidCost', () {
      expect(
        AnlasCalculator.estimateUpscaleCost(inputWidth: 0, inputHeight: 512),
        equals(AnlasCalculator.invalidCost),
      );
    });
  });

  group('describeCost 状态文本', () {
    test('0 → Opus 免费', () {
      expect(AnlasCalculator.describeCost(0), equals('0 Anlas (Opus 免费)'));
    });

    test('正值 → 精确预估', () {
      expect(AnlasCalculator.describeCost(29), equals('预计 29 Anlas'));
    });

    test('负值 → 无法估算', () {
      expect(AnlasCalculator.describeCost(-3), equals('无法估算'));
    });
  });

  group('NaiModel 计费能力位', () {
    test('V5 基础价倍率为 1.5，其余模型为 1.0', () {
      expect(NaiModel.v5Full.anlasMultiplier, equals(1.5));
      expect(NaiModel.v5Curated.anlasMultiplier, equals(1.5));
      expect(NaiModel.v45Full.anlasMultiplier, equals(1.0));
      expect(NaiModel.v3.anlasMultiplier, equals(1.0));
      expect(NaiModel.v3Furry.anlasMultiplier, equals(1.0));
    });

    test('仅 V5 的 Opus 免费受体力配额限制', () {
      expect(NaiModel.v5Full.hasOpusUsageLimit, isTrue);
      expect(NaiModel.v5Curated.hasOpusUsageLimit, isTrue);
      expect(NaiModel.v45Full.hasOpusUsageLimit, isFalse);
      expect(NaiModel.v3.hasOpusUsageLimit, isFalse);
    });
  });

  group('NaiAccountInfo 订阅判定', () {
    test('解析 V5 体力透支标志与 Opus 权益', () {
      final info = NaiAccountInfo.fromJson({
        'subscription': {
          'tier': 3,
          'active': true,
          'expiresAt': 4102444800,
          'usage': {'percent': -12.5, 'isNegative': true},
          'trainingStepsLeft': {
            'fixedTrainingStepsLeft': 500,
            'purchasedTrainingSteps': 100,
          },
        },
      });
      expect(info.isOpus, isTrue);
      expect(info.v5QuotaExhausted, isTrue);
      expect(info.totalAnlas, equals(600));
    });

    test('未透支且未订阅时均不满足免费条件', () {
      final info = NaiAccountInfo.fromJson({
        'subscription': {
          'tier': 1,
          'active': true,
          'usage': {'percent': 100},
          'trainingStepsLeft': {'fixedTrainingStepsLeft': 0},
        },
      });
      expect(info.isOpus, isFalse);
      expect(info.v5QuotaExhausted, isFalse);
    });

    test('缺少 usage 字段时透支默认为 false', () {
      final info = NaiAccountInfo.fromJson({
        'subscription': {'tier': 3, 'active': true},
      });
      expect(info.v5QuotaExhausted, isFalse);
      expect(info.isOpus, isTrue);
    });
  });

  group('精准参考 (Precise Reference) Anlas 附加计费', () {
    test('Opus 免费档叠加精准参考：基础图免费，但每张参考图每张成图固定 +5 Anlas', () {
      // 1 张参考 + 1 张图 = 0 + 5
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: true,
          preciseReferenceCount: 1,
        ),
        equals(5),
      );
      // 2 张参考 + 1 张图 = 0 + 10
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: true,
          preciseReferenceCount: 2,
        ),
        equals(10),
      );
      // 1 张参考 + 2 张图 = 第 1 张基础免费 + 第 2 张基础价(30) + 5*1*2 = 40
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 2,
          model: NaiModel.v5Full,
          isOpus: true,
          preciseReferenceCount: 1,
        ),
        equals(40),
      );
    });

    test('V5 Full 节约档挂精准参考时按强制高档步数计费再叠加参考费', () {
      final params = NaiGenerationParams(
        prompt: '1girl',
        model: NaiModel.v5Full,
        effort: NaiEffort.medium,
        width: 832,
        height: 1216,
        steps: 28,
        preciseReferences: [
          NaiPreciseReference(
            id: 'ref1',
            imageBytes: Uint8List.fromList([1, 2, 3]),
            type: NaiPreciseRefType.outfit,
          ),
        ],
      );
      // 非 Opus：按高档 28 步基础价 30 + 参考费 5 = 35 (而非 14 步节约价)
      expect(
        AnlasCalculator.estimateGenerationCost(params: params, isOpus: false),
        equals(35),
      );
      // Opus 未透支：基础图免费 + 参考费 5 = 5
      expect(
        AnlasCalculator.estimateGenerationCost(params: params, isOpus: true),
        equals(5),
      );
    });

    test('V3/V4 不支持精准参考时不加收参考附加费', () {
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v3,
          isOpus: true,
          preciseReferenceCount: 2,
        ),
        equals(0),
      );
    });
  });

  group('Vibe Transfer Anlas 计费', () {
    test('前 4 张已编码 Vibe 免槽位费；第 5 张起每多 1 张每张成图 +2 Anlas', () {
      // 4 张已编码 Vibe + Opus 免费档 = 0
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v45Full,
          isOpus: true,
          vibeReferenceCount: 4,
          vibeEncodeCount: 0,
        ),
        equals(0),
      );
      // 6 张已编码 Vibe + 2 张成图 (Opus): 第 1 张基础免费 + 第 2 张基础 20 + (6-4)*2*2 = 28
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 2,
          model: NaiModel.v45Full,
          isOpus: true,
          vibeReferenceCount: 6,
          vibeEncodeCount: 0,
        ),
        equals(28),
      );
    });

    test('V4/V4.5 未编码原图单次加收 2 Anlas/张 编码费；V3 与 V5 行为正确', () {
      // V4.5 Opus 免费档 + 2 张待编码原图 = 0 + 2*2 = 4
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v45Full,
          isOpus: true,
          vibeReferenceCount: 2,
          vibeEncodeCount: 2,
        ),
        equals(4),
      );
      // V3 不走编码费，仅算超 4 张槽位费
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v3,
          isOpus: true,
          vibeReferenceCount: 5,
          vibeEncodeCount: 5,
        ),
        equals(2),
      );
      // V5 不支持 Vibe Transfer，不收 Vibe 费用
      expect(
        AnlasCalculator.calculateFromValues(
          width: 832,
          height: 1216,
          steps: 28,
          nSamples: 1,
          model: NaiModel.v5Full,
          isOpus: true,
          vibeReferenceCount: 6,
          vibeEncodeCount: 6,
        ),
        equals(0),
      );
    });
  });
}
