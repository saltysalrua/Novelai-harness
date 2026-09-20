import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/tools/character_prompt_tools.dart';
import 'package:novelai_harness/core/harness/tools/studio_params_tool.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NovelAiGetStudioParamsTool exact readback', () {
    test('publishes every exact-readback key in its schema', () {
      final tool = NovelAiGetStudioParamsTool(
        getCurrentParams: () => const NaiGenerationParams(prompt: ''),
      );
      final properties = tool.parameters['properties'] as Map<String, dynamic>;
      final keys = properties['keys'] as Map<String, dynamic>;
      final items = keys['items'] as Map<String, dynamic>;
      final values = (items['enum'] as List).cast<String>();

      expect(
        values,
        containsAll([
          'uc_preset',
          'quality_toggle',
          'effective_prompt',
          'effective_negative_prompt',
          'generation_backend',
          'character_ai_position',
        ]),
      );
    });

    test('distinguishes raw prompts from effective prompts', () async {
      const rawPrompt = '  1girl,  {{{ink}}}, "HELLO"  ';
      const rawNegative = '  lowres,  bad hands  ';
      const params = NaiGenerationParams(
        prompt: rawPrompt,
        negativePrompt: rawNegative,
        qualityToggle: true,
        qualityPreset: 'Light',
        ucPresetKey: 'Human Focus',
        characterAiPosition: false,
      );
      final tool = NovelAiGetStudioParamsTool(getCurrentParams: () => params);

      final result = await tool.execute('read-exact', {
        'keys': [
          'prompt',
          'negative_prompt',
          'uc_preset',
          'quality_toggle',
          'effective_prompt',
          'effective_negative_prompt',
          'character_ai_position',
        ],
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('原始正向提示词: $rawPrompt'));
      expect(result.content, contains('原始负向提示词: $rawNegative'));
      expect(result.content, contains('UC 预设: Human Focus'));
      expect(result.content, contains('质量开关: 开启'));
      expect(result.content, contains('最终正向提示词: ${params.effectivePrompt}'));
      expect(
        result.content,
        contains('最终负向提示词: ${params.effectiveNegativePrompt}'),
      );
      expect(result.content, contains('角色位置模式: 自定义定位'));
    });

    test(
      'all-parameter report exposes exact readback without character slots',
      () async {
        const params = NaiGenerationParams(
          prompt: '1girl',
          negativePrompt: 'lowres',
          qualityToggle: false,
          qualityPreset: 'Standard',
          ucPresetKey: 'None',
          characterAiPosition: false,
        );

        final result = await NovelAiGetStudioParamsTool(
          getCurrentParams: () => params,
        ).execute('read-all-empty-slots', {});

        expect(result.isError, isFalse);
        expect(result.content, contains('原始正向提示词: 1girl'));
        expect(result.content, contains('最终正向提示词: 1girl'));
        expect(result.content, contains('原始负向提示词: lowres'));
        expect(result.content, contains('最终负向提示词: lowres'));
        expect(result.content, contains('UC 预设: None'));
        expect(result.content, contains('质量开关: 关闭'));
        expect(result.content, contains('角色位置模式: 自定义定位'));
        expect(result.content, contains('当前没有角色提示词'));
      },
    );

    test(
      'ComfyUI mode reports the strings its request path actually sends',
      () async {
        SharedPreferences.setMockInitialValues({
          'novelai_comfyui_enabled': true,
          'novelai_enable_tag_dictionary_auto_update': false,
        });
        final sessionDirectory = Directory.systemTemp.createTempSync(
          'studio_comfy_readback_',
        );
        final viewModel = StudioViewModel(
          sessionLogBaseDir: sessionDirectory.path,
        );
        addTearDown(() async {
          await viewModel.flushPendingSaves();
          viewModel.dispose();
          if (sessionDirectory.existsSync()) {
            sessionDirectory.deleteSync(recursive: true);
          }
        });
        await viewModel.init();

        const params = NaiGenerationParams(
          prompt: '  1girl, "SIGN"  ',
          negativePrompt: '  lowres,  bad hands  ',
          prefixPrompt: 'cinematic light',
          suffixPrompt: 'manga page',
          qualityToggle: true,
          qualityPreset: 'Standard',
          ucPresetKey: 'Heavy',
        );
        viewModel.updateParams(params);
        final tool = viewModel.availableTools
            .whereType<NovelAiGetStudioParamsTool>()
            .single;

        final result = await tool.execute('comfy-effective-readback', {
          'keys': [
            'generation_backend',
            'prompt',
            'negative_prompt',
            'effective_prompt',
            'effective_negative_prompt',
          ],
        });

        expect(result.isError, isFalse);
        expect(result.content, contains('实际生图后端: ComfyUI'));
        expect(result.content, contains('原始正向提示词: ${params.prompt}'));
        expect(result.content, contains('原始负向提示词: ${params.negativePrompt}'));
        expect(result.content, contains('最终正向提示词: ${params.finalPrompt}'));
        expect(
          result.content,
          contains('最终负向提示词: ${params.negativePrompt.trim()}'),
        );
        expect(result.content, isNot(contains(params.effectivePrompt)));
        expect(result.content, isNot(contains(params.effectiveNegativePrompt)));

        await viewModel.sendChatMessage('/params');
        final slashReport = viewModel.messages.last.content;
        expect(slashReport, contains('实际生图后端: ComfyUI'));
        expect(slashReport, contains('原始正向提示词: ${params.prompt}'));
        expect(slashReport, contains('原始负向提示词: ${params.negativePrompt}'));
        expect(slashReport, contains('最终正向提示词: ${params.finalPrompt}'));
        expect(
          slashReport,
          contains('最终负向提示词: ${params.negativePrompt.trim()}'),
        );
        expect(slashReport, isNot(contains(params.effectivePrompt)));
        expect(slashReport, isNot(contains(params.effectiveNegativePrompt)));
      },
    );
  });

  group('NovelAiListCharacterPromptsTool exact readback', () {
    test(
      'keeps percent display and reports exact raw coordinates and prompts',
      () async {
        const rawPrompt = '  girl,  {{{red dress}}}  ';
        const rawNegative = '  lowres,  extra fingers  ';
        const characters = [
          NaiCharacterPrompt(
            id: '1234abcd',
            name: '左侧角色',
            prompt: rawPrompt,
            negativePrompt: rawNegative,
            useCustomPosition: true,
            positionX: 0.3333,
            positionY: 0.6667,
          ),
        ];
        final tool = NovelAiListCharacterPromptsTool(
          getCharacterPrompts: () => characters,
          getAiPosition: () => false,
        );

        final result = await tool.execute('list-exact', {});

        expect(result.isError, isFalse);
        expect(result.content, contains('手动 (33%, 67%)'));
        expect(result.content, contains('position_x: 0.3333'));
        expect(result.content, contains('position_y: 0.6667'));
        expect(result.content, contains('正向: $rawPrompt'));
        expect(result.content, contains('负面: $rawNegative'));
      },
    );

    test('empty list still reports the global position mode', () async {
      final tool = NovelAiListCharacterPromptsTool(
        getCharacterPrompts: () => const [],
        getAiPosition: () => false,
      );

      final result = await tool.execute('list-empty', {});

      expect(result.isError, isFalse);
      expect(result.content, contains('当前没有角色提示词'));
      expect(result.content, contains('位置模式: 自定义定位'));
    });
  });

  group('NovelAiUpdateParamsTool validation and reporting', () {
    test('mixed permitted and denied updates report both outcomes', () async {
      var state = const NaiGenerationParams(prompt: 'before', steps: 28);
      var updateCount = 0;
      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => state,
        onUpdateParams: (value) {
          state = value;
          updateCount++;
        },
        permissionChecker: (key) => key == PresetParamKeys.prompt,
      );

      final result = await tool.execute('mixed-permission', {
        'prompt': 'after',
        'steps': 40,
      });

      expect(result.isError, isFalse);
      expect(updateCount, 1);
      expect(state.prompt, 'after');
      expect(state.steps, 28);
      expect(result.content, contains('正向提示词: 已更新'));
      expect(result.content, contains('未修改（权限受限）'));
      expect(result.content, contains('采样步数'));
    });

    test('rejects an unknown model id without updating state', () async {
      const state = NaiGenerationParams(
        prompt: 'before',
        model: NaiModel.v45Full,
      );
      NaiGenerationParams? updated;
      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => state,
        onUpdateParams: (value) => updated = value,
      );

      final result = await tool.execute('unknown-model', {
        'model': 'nai-diffusion-5-unofficial',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('未知模型 ID'));
      expect(result.content, contains('nai-diffusion-5-unofficial'));
      expect(updated, isNull);
    });
  });
}
