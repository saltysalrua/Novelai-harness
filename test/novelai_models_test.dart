import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/llm_model_fetcher.dart';

void main() {
  group('NovelAI Models & Payload Tests', () {
    test('isOpusFree returns true for standard portrait with <=28 steps', () {
      const params = NaiGenerationParams(
        prompt: '1girl, silver hair',
        width: 832,
        height: 1216,
        steps: 28,
        nSamples: 1,
      );
      expect(params.isOpusFree, isTrue);
    });

    test('isOpusFree returns false for >28 steps', () {
      const params = NaiGenerationParams(
        prompt: '1girl, silver hair',
        width: 832,
        height: 1216,
        steps: 35,
        nSamples: 1,
      );
      expect(params.isOpusFree, isFalse);
    });

    test('isOpusFree returns false for large wallpaper', () {
      const params = NaiGenerationParams(
        prompt: 'landscape',
        width: 1920,
        height: 1088, // 1920*1088 = 2088960 > 1048576
        steps: 28,
        nSamples: 1,
      );
      expect(params.isOpusFree, isFalse);
    });

    test(
      'finalPrompt joins prefix, core prompt, suffix and transparentBg correctly',
      () {
        const params = NaiGenerationParams(
          prompt: '1girl, solo',
          prefixPrompt: 'masterpiece, anime',
          suffixPrompt: 'high resolution',
          transparentBg: true,
        );
        expect(
          params.finalPrompt,
          equals(
            'masterpiece, anime, 1girl, solo, high resolution, transparent background',
          ),
        );
      },
    );

    test('toApiPayload structures V5 request correctly with v4_prompt', () {
      const params = NaiGenerationParams(
        prompt: '1girl in rain',
        negativePrompt: 'lowres, bad quality',
        model: NaiModel.v5Full,
        width: 832,
        height: 1216,
      );

      final payload = params.toApiPayload();
      expect(payload['model'], equals('nai-diffusion-5-full'));
      expect(payload['action'], equals('generate'));
      expect(payload['parameters']['v4_prompt'], isNotNull);
      // 官方字段名为 cfg_rescale (scale_rescale 是野字段，服务端不认)
      expect(payload['parameters']['cfg_rescale'], equals(params.cfgRescale));
      // params_version 仅 v4+ 结构下发，且用字符串预设 ID 替代旧版布尔/整型
      expect(payload['parameters']['params_version'], equals(4));
      expect(payload['parameters']['ucPresetId'], equals('heavy'));
      expect(payload['parameters']['qualityPresetId'], equals('standard'));
      expect(payload['parameters']['tag_hint_uc_preset'], equals(2));
      expect(payload['parameters']['tag_hint_qt'], equals(1));
      expect(payload['parameters']['legacy_uc'], isFalse);
      expect(payload['parameters']['v4_negative_prompt']['legacy_uc'], isFalse);
      // 质量词作为后缀拼进正向 caption，UC 预设拼进负面 caption
      expect(
        payload['parameters']['v4_prompt']['caption']['base_caption'],
        equals('1girl in rain, very aesthetic, masterpiece, no text'),
      );
      expect(
        payload['parameters']['negative_prompt'],
        params.effectiveNegativePrompt,
      );
      expect(
        payload['parameters']['v4_negative_prompt']['caption']['base_caption'],
        equals(params.effectiveNegativePrompt),
      );
    });

    test(
      'effectivePrompt appends quality tags and effectiveNegativePrompt appends uc preset',
      () {
        const params = NaiGenerationParams(
          prompt: '1girl, solo',
          negativePrompt: 'bad hands',
          model: NaiModel.v5Full,
        );

        // 默认 Standard 质量词拼为正向后缀；Heavy UC 预设拼在用户负面词前面，
        // 且正向无 nsfw 时官方会在负面词最开头附加 nsfw 压制
        expect(
          params.effectivePrompt,
          equals('1girl, solo, very aesthetic, masterpiece, no text'),
        );
        expect(
          params.effectiveNegativePrompt,
          equals(
            'nsfw, lowres, artistic error, film grain, scan artifacts, worst quality, bad quality, jpeg artifacts, very displeasing, chromatic aberration, dithering, halftone, screentone, multiple views, logo, too many watermarks, negative space, blank page, bad hands',
          ),
        );

        // 关闭质量词开关后不再拼接；UC 预设 None 时也不前置 nsfw
        const noneQuality = NaiGenerationParams(
          prompt: '1girl, solo',
          model: NaiModel.v5Full,
          qualityPreset: 'None',
          qualityToggle: false,
          ucPresetKey: 'None',
        );
        expect(noneQuality.effectivePrompt, equals('1girl, solo'));
        expect(noneQuality.effectiveNegativePrompt, equals(''));
      },
    );

    test('effectivePrompt keeps quality tags out of text: render sections', () {
      // V4+ 支持文字渲染：质量词必须插在 text: 标记之前，否则会被画进图里
      const v5 = NaiGenerationParams(prompt: '1girl, text:hello');
      expect(
        v5.effectivePrompt,
        equals('1girl, very aesthetic, masterpiece, no text text:hello'),
      );

      // text: 段后还有内容时保持段内完整
      const v5b = NaiGenerationParams(prompt: '1girl, text:hello, smiling');
      expect(
        v5b.effectivePrompt,
        equals(
          '1girl, very aesthetic, masterpiece, no text text:hello, smiling',
        ),
      );

      // 转义写法 text:: 是普通词，不触发插入
      const escaped = NaiGenerationParams(prompt: '1girl, text::escaped');
      expect(
        escaped.effectivePrompt,
        equals('1girl, text::escaped, very aesthetic, masterpiece, no text'),
      );

      // v3 无文字渲染能力，text: 只是普通词，直接追加末尾
      const v3 = NaiGenerationParams(
        prompt: '1girl, text:hello',
        model: NaiModel.v3,
      );
      expect(
        v3.effectivePrompt,
        equals(
          '1girl, text:hello, best quality, amazing quality, very aesthetic, absurdres',
        ),
      );
    });

    test(
      'effectiveNegativePrompt nsfw dual policy matches official behavior',
      () {
        // 正向含 nsfw：移除负面词中的 nsfw (含花括号变体)，且不前置
        const positiveNsfw = NaiGenerationParams(
          prompt: '1girl, nsfw',
          negativePrompt: '{nsfw}, bad hands',
          model: NaiModel.v5Full,
          qualityPreset: 'None',
          qualityToggle: false,
          ucPresetKey: 'None',
        );
        expect(positiveNsfw.effectiveNegativePrompt, equals('bad hands'));

        // UC 预设 None 时不前置 nsfw
        const nonePreset = NaiGenerationParams(
          prompt: '1girl',
          negativePrompt: 'bad hands',
          model: NaiModel.v5Full,
          qualityPreset: 'None',
          qualityToggle: false,
          ucPresetKey: 'None',
        );
        expect(nonePreset.effectiveNegativePrompt, equals('bad hands'));

        // 官网实例：UC 预设启用时无条件前置 nsfw，用户词里已有 nsfw 也照加不去重
        const officialCase = NaiGenerationParams(
          prompt: '1girl',
          negativePrompt: 'nsfw',
          model: NaiModel.v5Full,
          qualityPreset: 'None',
          qualityToggle: false,
          ucPresetKey: 'Light',
        );
        expect(
          officialCase.effectiveNegativePrompt,
          equals(
            'nsfw, lowres, bad hands, bad anatomy, artistic error, sepia, white haze, worst quality, very displeasing, jpeg artifacts, 0::ai-generated::, nsfw',
          ),
        );
      },
    );

    test('V5 Auto Text injects quoted strings as teXt: block after quality tags', () {
      // 官网行为：引号文字自动注入 teXt: 段，质量词落在它之前
      const v5 = NaiGenerationParams(
        prompt: '1girl, "WELCOME", neon sign',
        model: NaiModel.v5Full,
      );
      expect(
        v5.effectivePrompt,
        equals(
          '1girl, "WELCOME", neon sign, very aesthetic, masterpiece, no text, teXt: WELCOME',
        ),
      );

      // 多段引号文字用空行分隔
      const multi = NaiGenerationParams(
        prompt: '1girl, "first", "second"',
        model: NaiModel.v5Full,
      );
      expect(
        multi.effectivePrompt,
        equals(
          '1girl, "first", "second", very aesthetic, masterpiece, no text, teXt: first\n\nsecond',
        ),
      );

      // 已有手写 text: 标记时跳过注入 (大小写不敏感检测)
      const manual = NaiGenerationParams(
        prompt: '1girl, "WELCOME", text: "WELCOME"',
        model: NaiModel.v5Full,
      );
      expect(
        manual.effectivePrompt,
        equals(
          '1girl, "WELCOME", very aesthetic, masterpiece, no text text: "WELCOME"',
        ),
      );

      // V4/V4.5 无 Auto Text，引号文字不注入
      const v4 = NaiGenerationParams(
        prompt: '1girl, "WELCOME"',
        model: NaiModel.v45Full,
      );
      expect(
        v4.effectivePrompt,
        equals(
          '1girl, "WELCOME", location, very aesthetic, masterpiece, no text',
        ),
      );

      // 中文/日文引号 (“”、「」) 同样提取；日文占比>30% 时倒序
      const jp = NaiGenerationParams(
        prompt: '1girl, 「こんにちは」, 「さようなら」',
        model: NaiModel.v5Curated,
      );
      expect(
        jp.effectivePrompt,
        equals(
          '1girl, 「こんにちは」, 「さようなら」, very aesthetic, masterpiece, no text, teXt: さようなら\n\nこんにちは',
        ),
      );

      // 无引号文字时不注入
      const noQuotes = NaiGenerationParams(
        prompt: '1girl, neon sign',
        model: NaiModel.v5Full,
      );
      expect(
        noQuotes.effectivePrompt,
        equals('1girl, neon sign, very aesthetic, masterpiece, no text'),
      );
    });

    test('V5 Auto Text collects quoted strings from character prompts', () {
      const multi = NaiGenerationParams(
        prompt: '2girls, street',
        model: NaiModel.v5Full,
        characterPrompts: [
          NaiCharacterPrompt(id: 'a', name: 'A', prompt: 'girl, "HELLO"'),
          NaiCharacterPrompt(id: 'b', name: 'B', prompt: 'girl, "BYE"'),
        ],
      );
      expect(
        multi.effectivePrompt,
        equals(
          '2girls, street, very aesthetic, masterpiece, no text, teXt: HELLO\n\nBYE',
        ),
      );
    });

    test(
      'applySuffix handles prompt-mix chunks per official two-layer logic',
      () {
        // V4+：prompt-mix 只有第 0 段是基础提示词，质量词只加第 0 段
        // (段首尾空白原样保留)
        const v5Mix = NaiGenerationParams(
          prompt: '1girl, solo | 1boy, solo',
          model: NaiModel.v5Full,
        );
        expect(
          v5Mix.effectivePrompt,
          equals(
            '1girl, solo, very aesthetic, masterpiece, no text | 1boy, solo',
          ),
        );

        // ||…|| 随机区间内的 | 不算分段分隔
        const v5Random = NaiGenerationParams(
          prompt: '1girl, ||red | blue|| dress',
          model: NaiModel.v5Full,
        );
        expect(
          v5Random.effectivePrompt,
          equals(
            '1girl, ||red | blue|| dress, very aesthetic, masterpiece, no text',
          ),
        );

        // V3：每段都追加且保留段尾 :权重 (官网按字面 | 切，权重必须在段尾)
        const v3Mix = NaiGenerationParams(
          prompt: '1girl:0.7|landscape:0.3',
          model: NaiModel.v3,
        );
        expect(
          v3Mix.effectivePrompt,
          equals(
            '1girl, best quality, amazing quality, very aesthetic, absurdres:0.7|landscape, best quality, amazing quality, very aesthetic, absurdres:0.3',
          ),
        );

        // 段尾带空格时权重正则不匹配，权重作为普通字符保留 (官网同行为)
        const v3Spaced = NaiGenerationParams(
          prompt: '1girl:0.7 | landscape',
          model: NaiModel.v3,
        );
        expect(v3Spaced.effectivePrompt, contains('1girl:0.7, best quality'));
      },
    );

    test('NovelAiAutoText stripGeneratedBlock round-trip and safety', () {
      // 注入 → 剥离还原
      const params = NaiGenerationParams(
        prompt: '1girl, "WELCOME"',
        model: NaiModel.v5Full,
      );
      final effective = params.effectivePrompt;
      expect(
        NovelAiAutoText.stripGeneratedBlock(effective),
        equals('1girl, "WELCOME", very aesthetic, masterpiece, no text'),
      );

      // 用户手写的 teXt: 内容与引号提取不一致时保留
      expect(
        NovelAiAutoText.stripGeneratedBlock('1girl, teXt: something else'),
        equals('1girl, teXt: something else'),
      );

      // 用户手写但内容恰好一致时也会剥离 (官网同款歧义，接受)
      expect(
        NovelAiAutoText.stripGeneratedBlock('1girl, "HI", teXt: HI'),
        equals('1girl, "HI"'),
      );
    });

    test('NaiAccountInfo parses json properly', () {
      final json = {
        'subscription': {
          'tier': 3,
          'active': true,
          'expiresAt': 1780000000,
          'usage': {'percent': 95.5, 'timeUntilNextPercent': 45},
          'trainingStepsLeft': {
            'fixedTrainingStepsLeft': 10000,
            'purchasedTrainingSteps': 500,
          },
        },
        'priority': {'taskPriority': 10, 'nextRefillAt': 1780000000},
      };

      final info = NaiAccountInfo.fromJson(json);
      expect(info.tierName, equals('Opus'));
      expect(info.active, isTrue);
      expect(info.staminaPercent, equals(95.5));
      expect(info.timeUntilNextPercent, equals(45));
      expect(info.totalAnlas, equals(10500));
      expect(info.fixedAnlas, equals(10000));
    });

    test(
      'ResolutionPresetHelper correctly identifies Wallpaper does not support square',
      () {
        expect(
          ResolutionPresetHelper.supportsSquare(ResolutionCategory.wallpaper),
          isFalse,
        );
        expect(
          ResolutionPresetHelper.supportsSquare(ResolutionCategory.normal),
          isTrue,
        );
        expect(
          ResolutionPresetHelper.supportsSquare(ResolutionCategory.large),
          isTrue,
        );
        expect(
          ResolutionPresetHelper.supportsSquare(ResolutionCategory.small),
          isTrue,
        );

        final (wLandscape, hLandscape) = ResolutionPresetHelper.getDimensions(
          ResolutionCategory.wallpaper,
          ResolutionOrientation.landscape,
        );
        expect(wLandscape, equals(1920));
        expect(hLandscape, equals(1088));

        final (wPortrait, hPortrait) = ResolutionPresetHelper.getDimensions(
          ResolutionCategory.wallpaper,
          ResolutionOrientation.portrait,
        );
        expect(wPortrait, equals(1088));
        expect(hPortrait, equals(1920));

        final (wFallback, hFallback) = ResolutionPresetHelper.getDimensions(
          ResolutionCategory.wallpaper,
          ResolutionOrientation.square,
        );
        expect(wFallback, equals(1920));
        expect(hFallback, equals(1088));
      },
    );

    test('NovelAiQualityTagsHelper returns correct model-specific tags', () {
      expect(
        NovelAiQualityTagsHelper.getQualityTags(NaiModel.v5Full, 'Standard'),
        equals('very aesthetic, masterpiece, no text'),
      );
      expect(
        NovelAiQualityTagsHelper.getQualityTags(NaiModel.v45Full, 'Standard'),
        equals('location, very aesthetic, masterpiece, no text'),
      );
      expect(
        NovelAiQualityTagsHelper.getQualityTags(
          NaiModel.v45Curated,
          'Standard',
        ),
        equals('location, masterpiece, no text, -0.8::feet::, rating:general'),
      );
      expect(
        NovelAiQualityTagsHelper.getQualityTags(NaiModel.v3Furry, 'Standard'),
        equals('{best quality}, {amazing quality}'),
      );
    });

    test(
      'NovelAiUndesiredContentHelper returns correct model-specific presets',
      () {
        final v5Heavy = NovelAiUndesiredContentHelper.getUndesiredContent(
          NaiModel.v5Full,
          'Heavy',
        );
        expect(v5Heavy, contains('lowres, artistic error'));
        expect(v5Heavy, contains('dithering, halftone, screentone'));

        final v45CuratedLight =
            NovelAiUndesiredContentHelper.getUndesiredContent(
              NaiModel.v45Curated,
              'Light',
            );
        expect(
          v45CuratedLight,
          equals(
            'blurry, lowres, upscaled, artistic error, scan artifacts, jpeg artifacts, logo, too many watermarks, negative space, blank page',
          ),
        );

        final v3FurryHeavy = NovelAiUndesiredContentHelper.getUndesiredContent(
          NaiModel.v3Furry,
          'Heavy',
        );
        expect(v3FurryHeavy, contains('{{worst quality}}'));
        expect(v3FurryHeavy, contains('commissioner name'));
      },
    );

    test('LlmModelFetcher detects reasoning capabilities accurately', () {
      expect(
        LlmModelFetcher.detectReasoningCapability('deepseek-reasoner'),
        isTrue,
      );
      expect(LlmModelFetcher.detectReasoningCapability('deepseek-r1'), isTrue);
      expect(LlmModelFetcher.detectReasoningCapability('o3-mini'), isTrue);
      expect(LlmModelFetcher.detectReasoningCapability('o1-preview'), isTrue);
      expect(
        LlmModelFetcher.detectReasoningCapability('claude-3-7-sonnet-20250219'),
        isTrue,
      );
      expect(
        LlmModelFetcher.detectReasoningCapability('qwq-32b-preview'),
        isTrue,
      );

      expect(
        LlmModelFetcher.detectReasoningCapability('deepseek-chat'),
        isFalse,
      );
      expect(LlmModelFetcher.detectReasoningCapability('gpt-4o'), isFalse);
      expect(
        LlmModelFetcher.detectReasoningCapability('claude-3-5-sonnet-20241022'),
        isFalse,
      );
    });

    test(
      'LlmModelFetcher detects multimodal vision capabilities accurately',
      () {
        expect(LlmModelFetcher.detectMultimodalCapability('gpt-4o'), isTrue);
        expect(
          LlmModelFetcher.detectMultimodalCapability('gpt-4o-mini'),
          isTrue,
        );
        expect(
          LlmModelFetcher.detectMultimodalCapability(
            'claude-3-7-sonnet-20250219',
          ),
          isTrue,
        );
        expect(
          LlmModelFetcher.detectMultimodalCapability(
            'claude-3-5-sonnet-20241022',
          ),
          isTrue,
        );
        expect(
          LlmModelFetcher.detectMultimodalCapability('gemini-2.5-flash'),
          isTrue,
        );
        expect(
          LlmModelFetcher.detectMultimodalCapability('qwen-vl-max'),
          isTrue,
        );

        expect(
          LlmModelFetcher.detectMultimodalCapability('deepseek-chat'),
          isFalse,
        );
        expect(
          LlmModelFetcher.detectMultimodalCapability('deepseek-reasoner'),
          isFalse,
        );
      },
    );

    test('LlmModelFetcher formats /models endpoint correctly', () {
      expect(
        LlmModelFetcher.calculateModelsEndpoint(
          'https://api.deepseek.com/v1',
          LlmProtocol.openAiChat,
        ),
        equals('https://api.deepseek.com/v1/models'),
      );
      expect(
        LlmModelFetcher.calculateModelsEndpoint(
          'https://api.deepseek.com/v1/chat/completions',
          LlmProtocol.openAiChat,
        ),
        equals('https://api.deepseek.com/v1/models'),
      );
      expect(
        LlmModelFetcher.calculateModelsEndpoint(
          'http://localhost:11434',
          LlmProtocol.openAiChat,
        ),
        equals('http://localhost:11434/api/tags'),
      );
    });

    test('LlmProviderConfig serialization with multi-models works', () {
      final provider = LlmProviderConfig(
        id: 'test_provider',
        name: 'Test Provider',
        baseUrl: 'https://api.example.com/v1',
        protocol: LlmProtocol.openAiChat,
        apiKey: 'sk-test',
        activeModelId: 'm2',
        models: const [
          LlmModelConfig(
            id: 'm1',
            name: 'Model 1',
            reasoning: false,
            input: ['text'],
          ),
          LlmModelConfig(
            id: 'm2',
            name: 'Model 2',
            reasoning: true,
            input: ['text', 'image'],
            supportedThinkingLevels: [ThinkingEffort.low, ThinkingEffort.high],
            temperature: 0.6,
          ),
        ],
      );

      final json = provider.toJson();
      final decoded = LlmProviderConfig.fromJson(json);

      expect(decoded.id, equals('test_provider'));
      expect(decoded.models.length, equals(2));
      expect(decoded.activeModel.id, equals('m2'));
      expect(decoded.activeModel.reasoning, isTrue);
      expect(decoded.activeModel.isMultimodal, isTrue);
      expect(
        decoded.activeModel.supportedThinkingLevels,
        contains(ThinkingEffort.high),
      );
      expect(decoded.activeModel.temperature, equals(0.6));
      expect(
        decoded.fullEndpointUrl,
        equals('https://api.example.com/v1/chat/completions'),
      );
    });
  });

  group('NaiGeneratedImage 历史角标与序列化', () {
    test('isUpscaled / isImportedReference JSON 往返与角标文案优先级', () {
      const params = NaiGenerationParams(prompt: '1girl');
      final upscaled = NaiGeneratedImage(
        id: 'img_up',
        bytes: Uint8List.fromList([1, 2, 3]),
        params: params,
        createdAt: DateTime(2026, 12, 1),
        seed: 42,
        isOpusFree: false,
        isUpscaled: true,
      );

      // 角标文案：放大 > 修复 > 导入 优先
      expect(upscaled.provenance, equals(NaiImageProvenance.upscaled));
      final imported = upscaled.copyWith(
        isUpscaled: false,
        isImportedReference: true,
      );
      expect(imported.provenance, equals(NaiImageProvenance.imported));
      final repaired = upscaled.copyWith(isUpscaled: false, isInpainted: true);
      expect(repaired.provenance, equals(NaiImageProvenance.inpainted));
      final normal = NaiGeneratedImage(
        id: 'img_n',
        bytes: Uint8List(0),
        params: params,
        createdAt: DateTime(2026, 12, 2),
        seed: -1,
        isOpusFree: true,
      );
      expect(normal.provenance, isNull);

      // JSON 往返：标记保留，普通图不携带字段
      final upJson = upscaled.toJson();
      expect(upJson['isUpscaled'], isTrue);
      final restored = NaiGeneratedImage.fromJson(upJson);
      expect(restored.isUpscaled, isTrue);
      expect(restored.provenance, equals(NaiImageProvenance.upscaled));

      // 修复标记 JSON 往返同样保留
      final repairedJson = repaired.toJson();
      expect(repairedJson['isInpainted'], isTrue);
      final restoredRepaired = NaiGeneratedImage.fromJson(repairedJson);
      expect(restoredRepaired.isInpainted, isTrue);
      expect(restoredRepaired.provenance, equals(NaiImageProvenance.inpainted));

      final normalJson = normal.toJson();
      expect(normalJson.containsKey('isUpscaled'), isFalse);
      expect(normalJson.containsKey('isImportedReference'), isFalse);
      expect(normalJson.containsKey('isInpainted'), isFalse);
      final restoredNormal = NaiGeneratedImage.fromJson(normalJson);
      expect(restoredNormal.isUpscaled, isFalse);
      expect(restoredNormal.isImportedReference, isFalse);
    });
  });
}
