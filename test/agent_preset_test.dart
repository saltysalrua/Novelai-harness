import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/tools/load_skill_tool.dart';
import 'package:novelai_harness/core/harness/tools/studio_params_tool.dart';
import 'package:novelai_harness/core/harness/tools/novelai_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('AgentPreset Data Model & Serialization Tests', () {
    test('Builtin presets contain expected standard configurations', () {
      expect(BuiltinPresets.all.length, greaterThanOrEqualTo(4));
      final v5 = BuiltinPresets.v5Architect;
      expect(v5.id, equals('v5-architect-preset'));
      expect(v5.isBuiltin, isTrue);
      expect(v5.enabledSkillIds, contains('v5-architect'));
      expect(v5.isToolEnabled('novelai_generate'), isTrue);
      expect(v5.isParamModifiable('prompt'), isTrue);
    });

    test(
      'loadConfig refreshes stale persisted builtin presets from code',
      () async {
        // 模拟旧版本保存的内置预设：白名单里还没有角色四件套工具
        final staleBuiltin = AgentPreset(
          id: BuiltinPresets.v5Architect.id,
          name: 'V5 自然语言架构师 (旧)',
          description: '旧版本保存的内置预设',
          systemPrompt: '旧版系统提示词',
          enabledSkillIds: ['v5-architect'],
          enabledToolNames: [PresetToolKeys.generate, PresetToolKeys.askUser],
          allowedModifiableParams: [PresetParamKeys.prompt],
          isBuiltin: true,
        );
        final customPreset = AgentPreset(
          id: 'my-custom-preset',
          name: '我的自定义预设',
          description: '用户自定义预设',
          systemPrompt: '自定义提示词',
          enabledToolNames: [PresetToolKeys.generate],
          allowedModifiableParams: [PresetParamKeys.prompt],
        );
        SharedPreferences.setMockInitialValues({
          'agent_presets_json': jsonEncode([
            staleBuiltin.toJson(),
            customPreset.toJson(),
          ]),
        });

        final config = await ConfigService().loadConfig();

        // 内置预设按 id 被当前出厂定义覆盖，新工具白名单自动升级
        final restored = config.presets.firstWhere(
          (p) => p.id == BuiltinPresets.v5Architect.id,
        );
        expect(
          restored.systemPrompt,
          equals(BuiltinPresets.v5Architect.systemPrompt),
        );
        expect(restored.isToolEnabled('add_character_prompt'), isTrue);
        expect(restored.isToolEnabled('update_character_prompt'), isTrue);
        expect(restored.isToolEnabled('remove_character_prompt'), isTrue);
        expect(restored.isToolEnabled('list_character_prompts'), isTrue);
        // 三个内置预设全部存在
        for (final builtin in BuiltinPresets.all) {
          expect(
            config.presets.any((p) => p.id == builtin.id),
            isTrue,
            reason: '内置预设 ${builtin.id} 缺失',
          );
        }
        // 用户自定义预设不受刷新影响
        final keptCustom = config.presets.firstWhere(
          (p) => p.id == 'my-custom-preset',
        );
        expect(keptCustom.systemPrompt, equals('自定义提示词'));
        expect(keptCustom.isToolEnabled('add_character_prompt'), isFalse);
      },
    );

    test('AgentPreset toJson and fromJson round-trip', () {
      final preset = AgentPreset(
        id: 'custom-preset-1',
        name: 'Custom Preset',
        description: 'Testing description',
        systemPrompt: 'Custom prompt instructions',
        enabledSkillIds: ['v5-architect', 'danbooru-tags'],
        enabledToolNames: ['novelai_generate', 'ask_user'],
        allowedModifiableParams: ['prompt', 'width', 'height'],
        isBuiltin: false,
      );

      final json = preset.toJson();
      final restored = AgentPreset.fromJson(json);

      expect(restored.id, equals(preset.id));
      expect(restored.name, equals(preset.name));
      expect(restored.description, equals(preset.description));
      expect(restored.systemPrompt, equals(preset.systemPrompt));
      expect(restored.enabledSkillIds, equals(preset.enabledSkillIds));
      expect(restored.enabledToolNames, equals(preset.enabledToolNames));
      expect(
        restored.allowedModifiableParams,
        equals(preset.allowedModifiableParams),
      );
      expect(restored.isBuiltin, isFalse);
    });

    test('AgentPreset permission checking', () {
      final preset = AgentPreset(
        id: 'test-perm',
        name: 'Perm Test',
        description: '',
        systemPrompt: '',
        enabledToolNames: ['novelai_generate'],
        allowedModifiableParams: ['prompt', 'steps'],
      );

      expect(preset.isToolEnabled('novelai_generate'), isTrue);
      expect(preset.isToolEnabled('novelai_upscale'), isFalse);

      expect(preset.isParamModifiable('prompt'), isTrue);
      expect(preset.isParamModifiable('steps'), isTrue);
      expect(preset.isParamModifiable('width'), isFalse);
    });

    test('explicit empty permission lists mean nothing allowed', () {
      const preset = AgentPreset(
        id: 'no-tools',
        name: 'No Tools',
        description: '',
        systemPrompt: '',
      );

      expect(preset.isToolEnabled('novelai_generate'), isFalse);
      expect(preset.isParamModifiable('prompt'), isFalse);
    });

    test(
      'fromJson falls back to full access when legacy fields are missing',
      () {
        final restored = AgentPreset.fromJson({
          'id': 'legacy-preset',
          'name': 'Legacy',
          'systemPrompt': 'x',
        });

        expect(restored.isToolEnabled('novelai_generate'), isTrue);
        expect(restored.isToolEnabled('load_skill'), isTrue);
        expect(restored.isParamModifiable('steps'), isTrue);
        expect(restored.isParamModifiable('sampler'), isTrue);
      },
    );

    test('fromJson keeps explicitly saved empty permission lists empty', () {
      final restored = AgentPreset.fromJson({
        'id': 'locked-preset',
        'name': 'Locked',
        'systemPrompt': 'x',
        'enabledToolNames': <String>[],
        'allowedModifiableParams': <String>[],
      });

      expect(restored.isToolEnabled('novelai_generate'), isFalse);
      expect(restored.isParamModifiable('steps'), isFalse);
    });
  });

  group('Pi Standard Skill Formatting & LoadSkillTool Tests', () {
    test('Skill.formatSkillsForSystemPrompt outputs valid XML block', () {
      final skills = [
        BuiltinSkills.v5PromptArchitect,
        BuiltinSkills.danbooruTagMaster,
      ];
      final xml = Skill.formatSkillsForSystemPrompt(skills);

      expect(xml, contains('<available_skills>'));
      expect(xml, contains('</available_skills>'));
      expect(xml, contains('<name>v5-architect</name>'));
      expect(xml, contains('<name>danbooru-tags</name>'));
      expect(xml, contains('load_skill'));
    });

    test('LoadSkillTool loads built-in skill successfully', () async {
      final tool = LoadSkillTool(
        skillResolver: (name) => BuiltinSkills.findById(name),
        availableSkillIds: () => BuiltinSkills.all.map((s) => s.id).toList(),
      );
      final result = await tool.execute('call_1', {
        'skill_name': 'v5-architect',
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('<skill name="v5-architect">'));
      expect(result.content, contains('V5 自然语言架构师'));
    });

    test('LoadSkillTool returns error for unknown skill', () async {
      final tool = LoadSkillTool(
        skillResolver: (name) => BuiltinSkills.findById(name),
        availableSkillIds: () => BuiltinSkills.all.map((s) => s.id).toList(),
      );
      final result = await tool.execute('call_2', {
        'skill_name': 'unknown-skill-xyz',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('未找到技能'));
    });

    test('LoadSkillTool blocks skills outside the preset scope', () async {
      // 预设只开放 danbooru-tags，模型尝试加载 v5-architect 应被拒绝
      final enabled = <String>['danbooru-tags'];
      final tool = LoadSkillTool(
        skillResolver: (name) {
          final skill = BuiltinSkills.findById(name);
          if (skill == null || !enabled.contains(skill.id)) return null;
          return skill;
        },
        availableSkillIds: () => enabled.toList(),
      );
      final result = await tool.execute('call_3', {
        'skill_name': 'v5-architect',
      });

      expect(result.isError, isTrue);
      expect(result.content, contains('danbooru-tags'));
    });
  });

  group('NovelAiUpdateParamsTool Execution & Real Mutation Tests', () {
    test('Modifies permitted parameters and invokes callback', () async {
      var current = const NaiGenerationParams(
        prompt: '1girl, smiling',
        width: 832,
        height: 1216,
        steps: 28,
        scale: 5.0,
      );

      NaiGenerationParams? updatedParams;

      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => current,
        onUpdateParams: (newParams) {
          updatedParams = newParams;
          current = newParams;
        },
        permissionChecker: (key) => ['prompt', 'width', 'height'].contains(key),
      );

      final result = await tool.execute('call_update_1', {
        'prompt': 'A high-contrast cinematic portrait of a cybernetic warrior',
        'width': 1216,
        'height': 832,
      });

      expect(result.isError, isFalse);
      expect(result.content, contains('已成功同步修改工作台 UI 生图参数'));
      expect(updatedParams, isNotNull);
      expect(
        updatedParams!.prompt,
        equals('A high-contrast cinematic portrait of a cybernetic warrior'),
      );
      expect(updatedParams!.width, equals(1216));
      expect(updatedParams!.height, equals(832));
    });

    test('Blocks modification when parameter is not permitted', () async {
      var current = const NaiGenerationParams(prompt: 'initial', steps: 28);
      NaiGenerationParams? updatedParams;

      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => current,
        onUpdateParams: (newParams) => updatedParams = newParams,
        // 仅允许修改 prompt，不允许修改 steps
        permissionChecker: (key) => key == 'prompt',
      );

      final result = await tool.execute('call_update_2', {'steps': 50});

      expect(result.isError, isTrue);
      expect(result.content, contains('权限受限'));
      expect(updatedParams, isNull);
    });

    test(
      'NovelAiGetStudioParamsTool reads and formats all studio parameters',
      () async {
        const current = NaiGenerationParams(
          prompt: '1girl, silver hair, glowing eyes',
          negativePrompt: 'lowres, bad hands',
          width: 832,
          height: 1216,
          steps: 28,
          scale: 5.0,
          cfgRescale: 0.0,
        );

        final tool = NovelAiGetStudioParamsTool(
          getCurrentParams: () => current,
        );

        final result = await tool.execute('call_get_params', {});

        expect(result.isError, isFalse);
        expect(result.content, contains('1girl, silver hair, glowing eyes'));
        expect(result.content, contains('lowres, bad hands'));
        expect(result.content, contains('832x1216'));
        expect(result.content, contains('28 步'));
        expect(result.content, contains('Opus 免费区间'));
      },
    );

    test(
      'NovelAiGetStudioParamsTool selectively returns only requested keys',
      () async {
        const current = NaiGenerationParams(
          prompt: 'cyberpunk city, neon rain',
          negativePrompt: 'blurry',
          width: 1216,
          height: 832,
          steps: 25,
          scale: 6.0,
        );

        final tool = NovelAiGetStudioParamsTool(
          getCurrentParams: () => current,
        );

        final result = await tool.execute('call_get_selective', {
          'keys': ['prompt', 'steps'],
        });

        expect(result.isError, isFalse);
        expect(result.content, contains('cyberpunk city, neon rain'));
        expect(result.content, contains('25 步'));
        expect(result.content, isNot(contains('blurry')));
        expect(result.content, isNot(contains('1216x832')));
      },
    );

    test(
      'NovelAiUpdateParamsTool incrementally updates only provided fields',
      () async {
        var current = const NaiGenerationParams(
          prompt: 'original prompt',
          steps: 28,
          scale: 5.0,
        );
        NaiGenerationParams? updatedParams;

        final tool = NovelAiUpdateParamsTool(
          getCurrentParams: () => current,
          onUpdateParams: (newParams) => updatedParams = newParams,
        );

        final result = await tool.execute('call_update_partial', {'steps': 20});

        expect(result.isError, isFalse);
        expect(result.content, contains('步数: 20'));
        expect(result.content, isNot(contains('正向提示词')));
        expect(updatedParams!.steps, equals(20));
        expect(updatedParams!.prompt, equals('original prompt'));
        expect(updatedParams!.scale, equals(5.0));
      },
    );
  });

  group('Standard SKILL.md Parsing & Exporting Tests', () {
    test('Skill.fromSkillMd parses standard YAML frontmatter and body', () {
      const rawMd = '''---
name: anime-lighting-expert
description: 专业的光影色彩与环境光照分析技能
disable-model-invocation: true
---

# Anime Lighting Instructions
You are an expert in cinematic lighting, rim light, and ambient color harmony.''';

      final skill = Skill.fromSkillMd(rawMd);

      expect(skill.id, equals('anime-lighting-expert'));
      expect(skill.name, equals('anime-lighting-expert'));
      expect(skill.description, equals('专业的光影色彩与环境光照分析技能'));
      expect(skill.disableModelInvocation, isTrue);
      expect(skill.systemPrompt, contains('Anime Lighting Instructions'));
      expect(skill.isBuiltin, isFalse);
    });

    test('Skill.toSkillMd exports standard Pi YAML frontmatter and body', () {
      const skill = Skill(
        id: 'color-theory',
        name: '色彩理论',
        description: '色彩搭配与色盘生成',
        systemPrompt: 'Follow these color harmony rules...',
        disableModelInvocation: false,
      );

      final exported = skill.toSkillMd();

      expect(exported, contains('---'));
      expect(exported, contains('name: color-theory'));
      expect(exported, contains('description: 色彩搭配与色盘生成'));
      expect(exported, contains('label: 色彩理论'));
      expect(exported, contains('Follow these color harmony rules...'));
    });
  });

  group('SkillRegistry & ToolRegistry Dynamic Tests', () {
    test('SkillRegistry manages builtin and custom skills dynamically', () {
      final registry = SkillRegistry();
      expect(registry.getAll().length, greaterThanOrEqualTo(3));

      const customSkill = Skill(
        id: 'custom-1',
        name: 'My Custom Skill',
        description: 'Test description',
        systemPrompt: 'Instructions',
        isBuiltin: false,
      );

      registry.register(customSkill);
      expect(registry.get('custom-1'), isNotNull);
      expect(registry.getCustomSkills().length, equals(1));

      final deleted = registry.unregister('custom-1');
      expect(deleted, isTrue);
      expect(registry.get('custom-1'), isNull);

      // 内置技能不可注销
      final deletedBuiltin = registry.unregister('v5-architect');
      expect(deletedBuiltin, isFalse);
      expect(registry.get('v5-architect'), isNotNull);
    });

    test('CustomAgentTool executes with template interpolation', () async {
      final tool = CustomAgentTool(
        name: 'format_tag',
        label: '标签格式化',
        description: '格式化标签',
        parameters: const {
          'type': 'object',
          'properties': {
            'tag': {'type': 'string'},
          },
          'required': ['tag'],
        },
        outputTemplate: 'formatted: {{tag}}',
      );

      final result = await tool.execute('call_test', {'tag': '1girl, solo'});
      expect(result.isError, isFalse);
      expect(result.content, equals('formatted: 1girl, solo'));
    });

    test(
      'NovelAiGenerateTool intercepts paid parameters when user rejects',
      () async {
        SharedPreferences.setMockInitialValues({'novelai_key': 'test-token'});

        bool confirmationRequested = false;
        int recordedCost = 0;

        final configService = ConfigService();
        await configService.saveConfig(
          (await configService.loadConfig()).copyWith(novelAiKey: 'test-token'),
        );

        final tool = NovelAiGenerateTool(
          repository: NovelAiRepository(),
          configService: configService,
          getCurrentParams: () => const NaiGenerationParams(
            prompt: '1girl, masterpiece',
            width: 1920,
            height: 1088, // 超过 1048576 像素限制
            steps: 35, // 超过 28 步限制
          ),
          // Paper 账号: 无 Opus 免费折扣，预计消耗非零
          getAccountInfo: () => NaiAccountInfo(
            tierName: 'Paper',
            tier: 0,
            active: true,
            staminaPercent: 100,
            timeUntilNextPercent: 0,
            totalAnlas: 0,
            fixedAnlas: 0,
            purchasedAnlas: 0,
            taskPriority: 10,
            unlimitedFree: false,
          ),
          onConfirmPaidGeneration:
              ({required params, required estimatedCost}) async {
                confirmationRequested = true;
                recordedCost = estimatedCost;
                return false; // 用户拒绝
              },
        );

        final result = await tool.execute('call_gen_paid', {});
        expect(confirmationRequested, isTrue);
        expect(recordedCost, greaterThan(0));
        expect(result.isError, isTrue);
        expect(result.content, contains('已取消生成'));
        expect(result.content, contains('用户已拒绝扣费'));
      },
    );
  });
}
