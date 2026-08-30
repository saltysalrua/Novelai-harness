import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/ui/features/studio/view_models/slash_command_catalog.dart';
import 'package:novelai_harness/ui/features/studio/widgets/slash_command_overlay.dart';

Skill _skill(String id, String name) => Skill(
  id: id,
  name: name,
  description: '技能 $name 说明',
  systemPrompt: 'prompt',
);

AgentPreset _preset(String id, String name) => AgentPreset(
  id: id,
  name: name,
  description: '预设 $name 说明',
  systemPrompt: 'prompt',
);

void main() {
  final skills = [
    _skill('v5-architect', 'V5 架构师'),
    _skill('danbooru-tags', 'Danbooru 标签'),
  ];
  final presets = [_preset('v5', 'V5 画师'), _preset('default', '默认助手')];

  group('buildSlashSuggestions 指令名补全', () {
    test('单独斜杠列出全部指令', () {
      final result = buildSlashSuggestions(
        text: '/',
        skills: skills,
        presets: presets,
      );
      expect(result.length, 9);
      expect(result.first.completion, '/help');
    });

    test('按前缀过滤指令名', () {
      final result = buildSlashSuggestions(
        text: '/u',
        skills: skills,
        presets: presets,
      );
      expect(result.map((s) => s.completion), containsAll(['/upscale']));
      expect(result.length, 1);
    });

    test('无匹配返回空列表', () {
      final result = buildSlashSuggestions(
        text: '/zzz',
        skills: skills,
        presets: presets,
      );
      expect(result, isEmpty);
    });

    test('非斜杠开头返回空列表', () {
      final result = buildSlashSuggestions(
        text: '画一张图',
        skills: skills,
        presets: presets,
      );
      expect(result, isEmpty);
    });
  });

  group('buildSlashSuggestions 参数补全', () {
    test('/skill 按前缀匹配技能 ID 与名称', () {
      final result = buildSlashSuggestions(
        text: '/skill dan',
        skills: skills,
        presets: presets,
      );
      expect(result.length, 1);
      expect(result.first.completion, 'danbooru-tags');
    });

    test('/preset 按前缀匹配预设', () {
      final result = buildSlashSuggestions(
        text: '/preset v',
        skills: skills,
        presets: presets,
      );
      expect(result.length, 1);
      expect(result.first.completion, 'v5');
    });

    test('第二个及之后的参数不再补全', () {
      final result = buildSlashSuggestions(
        text: '/skill danbooru-tags extra',
        skills: skills,
        presets: presets,
      );
      expect(result, isEmpty);
    });

    test('其他指令的参数不补全', () {
      final result = buildSlashSuggestions(
        text: '/nai a girl',
        skills: skills,
        presets: presets,
      );
      expect(result, isEmpty);
    });
  });

  testWidgets('SlashSuggestionPanel size inside OverlayPortal', (tester) async {
    final suggestions = buildSlashSuggestions(
      text: '/',
      skills: const [],
      presets: const [],
    );

    final controller = OverlayPortalController();
    final link = LayerLink();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              Positioned(
                bottom: 20,
                left: 100,
                child: CompositedTransformTarget(
                  link: link,
                  child: Container(
                    width: 300,
                    height: 40,
                    color: Colors.blue,
                  ),
                ),
              ),
              OverlayPortal(
                controller: controller,
                overlayChildBuilder: (context) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: CompositedTransformFollower(
                      link: link,
                      targetAnchor: Alignment.topLeft,
                      followerAnchor: Alignment.bottomLeft,
                      offset: const Offset(0, -6),
                      showWhenUnlinked: false,
                      child: SizedBox(
                        width: 300,
                        child: SlashSuggestionPanel(
                          suggestions: suggestions,
                          selectedIndex: 0,
                          onSelected: (_) {},
                        ),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    controller.show();
    await tester.pump();

    final panelFinder = find.byType(SlashSuggestionPanel);
    expect(panelFinder, findsOneWidget);
    final size = tester.getSize(panelFinder);
    expect(size.width, 300.0);
    expect(size.height, 204.0);
  });

  test('slash command catalog is well-formed and renders complete help', () {
    // 指令名必须唯一且以 / 开头
    final names = kSlashCommands.map((c) => c.name).toList();
    expect(names.toSet().length, names.length);
    for (final name in names) {
      expect(name.startsWith('/'), isTrue);
    }
    // help 文本必须覆盖每条指令的名称与说明
    final help = buildSlashHelpText();
    for (final cmd in kSlashCommands) {
      expect(help.contains(cmd.name), isTrue);
      expect(help.contains(cmd.description), isTrue);
    }
  });
}
