import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/skills/skills.dart';
import 'package:novelai_harness/core/harness/tools/load_skill_tool.dart';
import 'package:novelai_harness/data/services/skill_package_service.dart';
import 'package:path/path.dart' as p;

const _md = '''---
name: example-skill
description: >-
  Read references and
  prepare a result.
license: MIT
compatibility: Python is optional
metadata:
  author: tester
  version: "1.0"
allowed-tools: Bash Read
disable-model-invocation: true
---

Read [guide](references/guide.md); scripts/example.py is optional.
''';

Uint8List _zip(Map<String, List<int>> files) {
  final archive = Archive();
  for (final entry in files.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive)!);
}

Map<String, List<int>> _files([String prefix = 'example-skill/']) => {
  '${prefix}SKILL.md': utf8.encode(_md),
  '${prefix}references/guide.md': utf8.encode('参考内容 0123456789'),
  '${prefix}scripts/example.py': utf8.encode(
    'raise RuntimeError("never execute")',
  ),
  '${prefix}assets/template.bin': [0, 255, 20, 42],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temp;
  late SkillPackageService service;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('skill_package_test_');
    service = SkillPackageService(
      rootDirectory: () async => Directory(p.join(temp.path, 'managed')),
    );
  });
  tearDown(() async => temp.delete(recursive: true));

  test('YAML multiline, optional fields and special strings round-trip', () {
    final parsed = Skill.fromSkillMd('\uFEFF${_md.replaceAll('\n', '\r\n')}');
    expect(parsed.description, 'Read references and prepare a result.');
    expect(parsed.disableModelInvocation, isTrue);
    expect(parsed.extraFrontmatter['metadata'], {
      'author': 'tester',
      'version': '1.0',
    });
    expect(parsed.extraFrontmatter['allowed-tools'], 'Bash Read');
    final edited = parsed.copyWith(
      description: 'first: "quoted"\nsecond \\ path # hash',
      name: 'true',
    );
    final restored = Skill.fromSkillMd(edited.toSkillMd());
    expect(restored.description, edited.description);
    expect(restored.name, 'true');
    expect(restored.extraFrontmatter, edited.extraFrontmatter);
    expect(
      Skill.fromSkillMd(
        '---\nname: demo\ndescription: |\n  first\n  second\n---\nbody',
      ).description,
      'first\nsecond\n',
    );
  });

  test(
    'malformed YAML is rejected instead of silently corrupting metadata',
    () {
      for (final input in [
        '---\nname: [\n---\nbody',
        '---\nname: demo',
        '---\nname: [bad]\n---\nbody',
        '---\n- list\n---\nbody',
      ]) {
        expect(() => Skill.fromSkillMd(input), throwsFormatException);
      }
      expect(Skill.fromSkillMd('# Legacy text').systemPrompt, '# Legacy text');
      expect(Skill.fromJson({'id': 'legacy'}).resourcePaths, isEmpty);
    },
  );

  for (final prefix in [
    '',
    'example-skill/',
    'download-main/skills/example-skill/',
  ]) {
    test('ZIP and .skill support root and wrapper directories: $prefix', () {
      final package = SkillPackageService.decodeImport(
        _zip(_files(prefix)),
        'bundle.skill',
      );
      expect(package.skill.id, 'example-skill');
      expect(package.skill.resourcePaths, [
        'assets/template.bin',
        'references/guide.md',
        'scripts/example.py',
      ]);
      expect(package.files['assets/template.bin'], [0, 255, 20, 42]);
      expect(package.skill.packageId, isNull);
    });
  }

  test('standalone Markdown import remains supported', () {
    final package = SkillPackageService.decodeImport(
      utf8.encode('# legacy'),
      'notes.md',
    );
    expect(package.skill.id, 'notes');
    expect(package.skill.resourcePaths, isEmpty);
    expect(package.files.keys, ['SKILL.md']);
  });

  test(
    'directory preview does not install, source can be removed after confirmation',
    () async {
      final source = Directory(p.join(temp.path, 'source'));
      for (final entry in _files('').entries) {
        final file = File(p.join(source.path, entry.key));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value);
      }
      final package = await service.readImportDirectory(source.path);
      expect(await Directory(p.join(temp.path, 'managed')).exists(), isFalse);
      final installed = await service.install(package, package.skill);
      expect(installed.packageId, startsWith('pkg_'));
      expect(await source.exists(), isTrue);
      await source.delete(recursive: true);
      final restored = Skill.fromJson(
        jsonDecode(jsonEncode(installed.toJson())) as Map<String, dynamic>,
      );
      final restarted = SkillPackageService(
        rootDirectory: () async => Directory(p.join(temp.path, 'managed')),
      );
      expect(
        utf8.decode(
          await restarted.readResource(restored, 'references/guide.md'),
        ),
        '参考内容 0123456789',
      );
      final edited = restored.copyWith(systemPrompt: 'edited instructions');
      final exported = SkillPackageService.decodeImport(
        await restarted.exportPackage(edited),
        'round-trip.zip',
      );
      expect(exported.skill.systemPrompt, 'edited instructions');
      expect(exported.skill.extraFrontmatter, installed.extraFrontmatter);
      expect(exported.files['assets/template.bin'], [0, 255, 20, 42]);
      expect(
        exported.files['scripts/example.py'],
        package.files['scripts/example.py'],
      );
      await restarted.deletePackage(restored);
      expect(
        await Directory(
          p.join(temp.path, 'managed', restored.packageId!),
        ).exists(),
        isFalse,
      );
    },
  );

  test('independent installs never overwrite each other', () async {
    final package = SkillPackageService.decodeImport(_zip(_files()), 'a.zip');
    final first = await service.install(package, package.skill);
    final second = await service.install(package, package.skill);
    expect(first.packageId, isNot(second.packageId));
    await service.deletePackage(first);
    expect(await service.readResource(second, 'assets/template.bin'), [
      0,
      255,
      20,
      42,
    ]);
  });

  test(
    'rejects missing/multiple entry points and invalid package metadata',
    () {
      for (final files in [
        <String, List<int>>{'README.md': utf8.encode('no skill')},
        {..._files('a/'), ..._files('b/')},
        {
          'SKILL.md': utf8.encode(
            '---\nname: BadName\ndescription: test\n---\nbody',
          ),
        },
        {'SKILL.md': utf8.encode('---\nname: test\n---\nbody')},
      ]) {
        expect(
          () => SkillPackageService.decodeImport(_zip(files), 'a.zip'),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'blocks traversal, absolute paths, ADS, aliases and file-directory collisions',
    () {
      for (final bad in [
        '../escape',
        '/absolute',
        'C:/absolute',
        'assets/../escape',
        'assets//bad',
        'assets/a:stream',
        'assets/CON.txt',
        'assets/trailing.',
        'assets/trailing ',
      ]) {
        expect(
          () => SkillPackageService.decodeImport(
            _zip({
              ..._files(''),
              bad: [1],
            }),
            'a.zip',
          ),
          throwsFormatException,
          reason: bad,
        );
      }
      for (final files in [
        {
          ..._files(''),
          'A.txt': [1],
          'a.txt': [2],
        },
        {
          ..._files(''),
          'references': [1],
        },
      ]) {
        expect(
          () => SkillPackageService.decodeImport(_zip(files), 'a.zip'),
          throwsFormatException,
        );
      }
    },
  );

  test('ZIP symlinks are rejected before content extraction', () {
    final archive = Archive()
      ..addFile(
        ArchiveFile('SKILL.md', utf8.encode(_md).length, utf8.encode(_md)),
      );
    final link = ArchiveFile('link', 3, [46, 46, 47])..mode = 0xa1ff;
    archive.addFile(link);
    expect(
      () => SkillPackageService.decodeImport(
        Uint8List.fromList(ZipEncoder().encode(archive)!),
        'link.zip',
      ),
      throwsFormatException,
    );
  });

  test('limits advertised and actual decompressed sizes', () {
    final bytes = _zip(_files(''));
    // 中央目录第一项的 uncompressed size。伪造很小的声明值也不能绕过输出限额。
    final headerOffset = ZipDirectory.read(
      InputStream(bytes),
    ).centralDirectoryOffset;
    final data = ByteData.sublistView(bytes);
    data.setUint32(headerOffset + 24, 1, Endian.little);
    expect(
      () => SkillPackageService.decodeImport(bytes, 'bomb.zip'),
      throwsFormatException,
    );
    data.setUint32(
      headerOffset + 24,
      SkillPackageService.maxFileBytes + 1,
      Endian.little,
    );
    expect(
      () => SkillPackageService.decodeImport(bytes, 'large.zip'),
      throwsFormatException,
    );
    expect(
      () => SkillPackageService.decodeImport(
        _zip({
          'SKILL.md': utf8.encode(_md),
          for (var i = 0; i < 512; i++) 'file-$i': [1],
        }),
        'count.zip',
      ),
      throwsFormatException,
    );
  });

  test('resource access is confined to manifest and managed package', () async {
    final package = SkillPackageService.decodeImport(_zip(_files()), 'a.zip');
    final skill = await service.install(package, package.skill);
    await expectLater(
      service.readResource(skill, '../outside'),
      throwsFormatException,
    );
    await expectLater(
      service.readResource(skill, 'not-listed.txt'),
      throwsFormatException,
    );
    await expectLater(
      service.readResource(
        skill.copyWith(packageId: '../source'),
        'references/guide.md',
      ),
      throwsFormatException,
    );
    await service.deletePackage(skill);
    await expectLater(
      service.readResource(skill, 'references/guide.md'),
      throwsFormatException,
    );
  });

  test(
    'load_skill progressively lists, pages and reads without executing scripts',
    () async {
      final package = SkillPackageService.decodeImport(_zip(_files()), 'a.zip');
      final skill = await service.install(package, package.skill);
      final tool = LoadSkillTool(
        skillResolver: (name) => name == skill.id ? skill : null,
        availableSkillIds: () => [skill.id],
        readResource: service.readResource,
      );
      final instructions = await tool.execute('1', {'skill_name': skill.id});
      expect(instructions.content, contains('references/guide.md'));
      expect(instructions.content, isNot(contains('参考内容 0123456789')));
      final listed = await tool.execute('2', {
        'skill_name': skill.id,
        'list_resources': true,
        'offset': 1,
        'limit': 1,
      });
      expect(listed.content, contains('references/guide.md'));
      expect(listed.content, isNot(contains('assets/template.bin')));
      final read = await tool.execute('3', {
        'skill_name': skill.id,
        'path': 'references/guide.md',
        'offset': 5,
        'limit': 3,
      });
      expect(read.isError, isFalse);
      expect(read.content, contains('012'));
      expect(read.content, contains('offset: 8'));
      final batch = await tool.execute('4', {
        'skill_name': skill.id,
        'paths': ['scripts/example.py', 'not-listed.txt'],
      });
      expect(batch.isError, isFalse);
      expect(batch.content, contains('raise RuntimeError'));
      expect(batch.content, contains('读取失败'));
      final binary = await tool.execute('5', {
        'skill_name': skill.id,
        'path': 'assets/template.bin',
      });
      expect(binary.isError, isTrue);
      expect(binary.imageBase64, isNull);
      final outside = await tool.execute('6', {
        'skill_name': skill.id,
        'path': '../outside',
      });
      expect(outside.isError, isTrue);
      final invalid = await tool.execute('7', {
        'skill_name': skill.id,
        'path': 'references/guide.md',
        'offset': -1,
      });
      expect(invalid.isError, isTrue);
    },
  );

  test(
    'preset scope blocks even resource listing and direct SKILL.md reads',
    () async {
      var reads = 0;
      final tool = LoadSkillTool(
        skillResolver: (_) => null,
        availableSkillIds: () => [],
        readResource: (_, _) async {
          reads++;
          return Uint8List(0);
        },
      );
      for (final args in [
        {'skill_name': 'disabled', 'path': 'SKILL.md'},
        {'skill_name': 'disabled', 'list_resources': true},
        {'skill_name': 'disabled', 'path': 'references/guide.md'},
      ]) {
        expect((await tool.execute('blocked', args)).isError, isTrue);
      }
      expect(reads, 0);
    },
  );
}
