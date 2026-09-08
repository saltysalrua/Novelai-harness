import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/tools/studio_params_tool.dart';
import 'package:novelai_harness/core/harness/tools/character_prompt_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';

void main() {
  test('skill directory uses live registry and excludes disabled skills', () {
    const custom = Skill(
      id: 'custom',
      name: 'Custom',
      description: 'custom description',
      systemPrompt: 'FULL BODY',
    );
    final registry = SkillRegistry(initialSkills: [custom]);
    final harness = AgentHarness(
      tools: ToolRegistry(),
      skillRegistry: registry,
    );
    final preset = BuiltinPresets.freeCreator.copyWith(
      enabledSkillIds: ['custom'],
    );
    final prompt = harness.buildSystemPrompt(preset);
    expect(prompt, contains('<name>custom</name>'));
    expect(prompt, isNot(contains('FULL BODY')));
    registry.register(custom.copyWith(disableModelInvocation: true));
    expect(
      harness.buildSystemPrompt(preset),
      isNot(contains('<name>custom</name>')),
    );
  });

  test(
    'parameter write keeps full state but returns short acknowledgement',
    () async {
      var params = const NaiGenerationParams(prompt: '');
      final tool = NovelAiUpdateParamsTool(
        getCurrentParams: () => params,
        onUpdateParams: (value) => params = value,
      );
      final text = List.filled(500, 'long prompt').join(', ');
      final result = await tool.execute('p', {
        'prompt': text,
        'negative_prompt': text,
      });
      expect(result.isError, isFalse);
      expect(params.prompt, text);
      expect(params.negativePrompt, text);
      expect(result.content.length, lessThan(200));
      expect(result.content, isNot(contains(text)));
    },
  );

  test('character writes retain content without echoing it', () async {
    var characters = <NaiCharacterPrompt>[];
    final text = List.filled(500, 'girl').join(', ');
    final add = NovelAiAddCharacterPromptTool(
      getCharacterPrompts: () => characters,
      updateCharacterPrompts: (value) => characters = value,
    );
    final result = await add.execute('a', {
      'prompt': text,
      'negative_prompt': text,
    });
    expect(result.isError, isFalse);
    expect(characters.single.prompt, text);
    expect(result.content, contains(characters.single.id));
    expect(result.content, isNot(contains(text)));
    final update = NovelAiUpdateCharacterPromptTool(
      getCharacterPrompts: () => characters,
      updateCharacterPrompts: (value) => characters = value,
    );
    final changed = await update.execute('u', {
      'id': characters.single.id,
      'prompt': '$text updated',
    });
    expect(characters.single.prompt, '$text updated');
    expect(changed.content, isNot(contains(text)));
  });
}
