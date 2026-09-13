import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_dialog_scaffold.dart';
import 'package:novelai_harness/ui/features/settings/widgets/skill_editor_dialog.dart';

const _skill = Skill(
  id: 'package',
  name: 'Package',
  description: 'description',
  systemPrompt: 'instructions',
  packageId: 'pkg_test',
  resourcePaths: ['references/readme.md', 'scripts/task.py'],
  extraFrontmatter: {
    'license': 'MIT',
    'metadata': {'author': 'test'},
  },
);

Future<void> _open(
  WidgetTester tester, {
  required Future<void> Function(Skill) onSave,
}) async {
  await tester.binding.setSurfaceSize(const Size(900, 850));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.lightTheme,
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => AppDialogScaffold.show<Skill>(
              context: context,
              builder: (_) => SkillEditorDialog(
                skill: _skill,
                isImportMode: true,
                onSave: onSave,
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('raw edits preserve metadata and resource descriptors after save', (
    tester,
  ) async {
    Skill? saved;
    await _open(tester, onSave: (skill) async => saved = skill);
    expect(find.text('配套文件：2 个'), findsOneWidget);
    await tester.enterText(
      find.byType(TextField),
      '---\nname: renamed\ndescription: >-\n  first\n  second\nlicense: MIT\nmetadata:\n  author: test\n---\nchanged',
    );
    await tester.tap(find.text('结构化编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存 Skill'));
    await tester.pumpAndSettle();
    expect(saved!.id, 'renamed');
    expect(saved!.description, 'first second');
    expect(saved!.extraFrontmatter, _skill.extraFrontmatter);
    expect(saved!.packageId, _skill.packageId);
    expect(saved!.resourcePaths, _skill.resourcePaths);
    expect(saved!.systemPrompt, 'changed');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'copy from raw mode uses the edited text rather than stale form fields',
    (tester) async {
      String? clipboard;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await _open(tester, onSave: (_) async {});
      await tester.enterText(find.byType(TextField), '# latest raw draft');
      await tester.tap(find.text('复制 SKILL.md'));
      await tester.pumpAndSettle();
      expect(clipboard, '# latest raw draft');
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '# latest raw draft',
      );
    },
  );

  testWidgets(
    'invalid YAML and failed save keep dialog open and preserve draft',
    (tester) async {
      var calls = 0;
      await _open(
        tester,
        onSave: (_) async {
          calls++;
          throw const FormatException('duplicate id');
        },
      );
      await tester.enterText(find.byType(TextField), '---\nname: [\n---\nbody');
      await tester.tap(find.text('保存 Skill'));
      await tester.pumpAndSettle();
      expect(calls, 0);
      expect(find.byType(SkillEditorDialog), findsOneWidget);
      await tester.enterText(find.byType(TextField), _skill.toSkillMd());
      await tester.tap(find.text('保存 Skill'));
      await tester.pumpAndSettle();
      expect(calls, 1);
      expect(find.byType(SkillEditorDialog), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        _skill.toSkillMd(),
      );
      expect(tester.takeException(), isNull);
    },
  );
}
