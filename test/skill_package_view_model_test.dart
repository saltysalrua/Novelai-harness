import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/data/models/skill_package.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/skill_package_service.dart';
import 'package:novelai_harness/ui/features/settings/widgets/presets_settings_tab.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FailingConfigService extends ConfigService {
  @override
  Future<void> saveConfig(AppConfig config) async =>
      throw const FileSystemException('write denied');
}

const _skill = Skill(
  id: 'bundle',
  name: 'Bundle',
  description: 'test package',
  systemPrompt: 'read references/test.md',
  resourcePaths: ['references/test.md'],
  extraFrontmatter: {'license': 'MIT'},
);
SkillPackage _package() => SkillPackage(
  skill: _skill,
  files: {
    'SKILL.md': utf8.encode(_skill.toSkillMd()),
    'references/test.md': utf8.encode('retained resource'),
  },
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late SkillPackageService service;
  late StudioViewModel vm;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    temp = await Directory.systemTemp.createTemp('skill_vm_');
    service = SkillPackageService(
      rootDirectory: () async => Directory('${temp.path}/packages'),
    );
    vm = StudioViewModel(
      skillPackageService: service,
      sessionLogBaseDir: temp.path,
    );
  });
  tearDown(() async {
    vm.dispose();
    await temp.delete(recursive: true);
  });

  test(
    'import persists descriptors; edit and rename retain resources and preset references',
    () async {
      await vm.savePreset(
        BuiltinPresets.v5Architect.copyWith(
          id: 'custom',
          isBuiltin: false,
          enabledSkillIds: ['bundle'],
        ),
      );
      final installed = await vm.importSkillPackage(_package(), _skill);
      expect(vm.availableSkills.any((s) => s.id == 'bundle'), isTrue);
      final config = await ConfigService().loadConfig();
      expect(config.customSkills.single.packageId, installed.packageId);
      expect(config.customSkills.single.extraFrontmatter, {'license': 'MIT'});
      expect(
        utf8.decode(
          await service.readResource(
            config.customSkills.single,
            'references/test.md',
          ),
        ),
        'retained resource',
      );
      await vm.saveCustomSkill(
        installed.copyWith(id: 'renamed', systemPrompt: 'new instructions'),
        originalId: installed.id,
      );
      expect(vm.availableSkills.any((s) => s.id == 'bundle'), isFalse);
      final renamed = vm.availableSkills.singleWhere((s) => s.id == 'renamed');
      expect(renamed.resourcePaths, installed.resourcePaths);
      expect(renamed.packageId, installed.packageId);
      expect(vm.presets.singleWhere((p) => p.id == 'custom').enabledSkillIds, [
        'renamed',
      ]);
      final exported = SkillPackageService.decodeImport(
        await vm.exportSkillPackage(renamed),
        'export.zip',
      );
      expect(exported.skill.systemPrompt, 'new instructions');
      expect(
        utf8.decode(exported.files['references/test.md']!),
        'retained resource',
      );
      await vm.deleteCustomSkill('renamed');
      expect(vm.config.customSkills, isEmpty);
      expect(
        vm.presets.singleWhere((p) => p.id == 'custom').enabledSkillIds,
        isEmpty,
      );
      expect(
        await Directory(
          '${temp.path}/packages/${installed.packageId}',
        ).exists(),
        isFalse,
      );
    },
  );

  test(
    'duplicate imports and builtin collisions cannot overwrite existing skills',
    () async {
      final installed = await vm.importSkillPackage(_package(), _skill);
      await expectLater(
        vm.importSkillPackage(_package(), _skill),
        throwsFormatException,
      );
      await expectLater(
        vm.importSkillPackage(_package(), _skill.copyWith(id: 'v5-architect')),
        throwsFormatException,
      );
      expect(vm.config.customSkills.single.packageId, installed.packageId);
      expect(await Directory('${temp.path}/packages').list().length, 1);
      // 失败不污染串行队列，下一次导入可以继续。
      await vm.importSkillPackage(_package(), _skill.copyWith(id: 'second'));
      expect(vm.config.customSkills.length, 2);
    },
  );

  test(
    'concurrent same-ID imports serialize and create only one package',
    () async {
      final first = vm.importSkillPackage(_package(), _skill);
      final second = vm.importSkillPackage(_package(), _skill);
      final rejected = expectLater(second, throwsFormatException);
      await first;
      await rejected;
      expect(vm.config.customSkills.length, 1);
      expect(await Directory('${temp.path}/packages').list().length, 1);
    },
  );

  test(
    'failed persistence rolls back config and cleans only the new install',
    () async {
      final failing = StudioViewModel(
        configService: _FailingConfigService(),
        skillPackageService: service,
      );
      addTearDown(failing.dispose);
      await expectLater(
        failing.importSkillPackage(_package(), _skill),
        throwsA(isA<FileSystemException>()),
      );
      expect(failing.config.customSkills, isEmpty);
      expect(await Directory('${temp.path}/packages').list().length, 0);
    },
  );

  test('settings draft rewrites or removes references across all presets', () {
    final preset = BuiltinPresets.v5Architect.copyWith(
      id: 'custom',
      isBuiltin: false,
      enabledSkillIds: ['bundle'],
    );
    final draft = PresetsSettingsDraft(
      AppConfig(presets: [preset], activePresetId: preset.id),
    );
    addTearDown(draft.dispose);
    draft.replaceSkillReferences('bundle', 'renamed');
    expect(draft.currentPreset.enabledSkillIds, ['renamed']);
    draft.replaceSkillReferences('renamed', null);
    expect(draft.currentPreset.enabledSkillIds, isEmpty);
  });
}
