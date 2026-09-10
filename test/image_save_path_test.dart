import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/image_file_store.dart';
import 'package:novelai_harness/data/services/image_save_path_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/settings/widgets/general_settings_tab.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final throwsFileSystemException = throwsA(isA<FileSystemException>());
  final context = ImageSaveContext(
    params: const NaiGenerationParams(
      prompt: '海边/日落: test?',
      model: NaiModel.v5Full,
      width: 832,
      height: 1216,
      steps: 23,
      scale: 7,
    ),
    createdAt: DateTime(2026, 9, 2, 3, 4, 5, 6),
    seed: 42,
  );

  group('命名宏解析', () {
    test('空模板兼容默认命名，PNG 后缀只补一次', () {
      expect(
        ImageSavePathService.resolve('', context),
        'nai_20260902_030405_42.png',
      );
      expect(ImageSavePathService.resolve('{seed}.PNG', context), '42.png');
    });
    test('自定义日期格式、双平台目录分隔与参数', () {
      expect(
        ImageSavePathService.resolve(
          r'{date:yyyy-MM}\{model}/{seed}_{resolution}_{steps}_{cfg}',
          context,
        ),
        '2026-09/nai-diffusion-5-full/42_832x1216_23_7.0.png',
      );
      expect(
        ImageSavePathService.resolve('{date:HHmmss_SSS}', context),
        '030405_006.png',
      );
      expect(
        ImageSavePathService.resolve('{year}/{month}/{day}/{seed}', context),
        '2026/09/02/42.png',
      );
      for (final macro in ImageSavePathService.macroNames) {
        expect(ImageSavePathService.validate('{$macro}'), isNull);
        expect(
          ImageSavePathService.resolve('{$macro}', context),
          isNot(contains('{')),
        );
      }
    });
    test('宏值中斜杠只净化，不会注入目录或重新展开宏', () {
      expect(
        ImageSavePathService.resolve('{prompt}/{seed}', context),
        '海边_日落_ test_/42.png',
      );
      final injected = ImageSaveContext(
        params: context.params.copyWith(prompt: '../{seed}/..\\x'),
        createdAt: context.createdAt,
        seed: 42,
      );
      expect(
        ImageSavePathService.resolve('{prompt}', injected),
        '.._{seed}_.._x.png',
      );
    });
    test('拒绝错误宏、绝对路径、目录穿越、缓存目录与无效日期格式', () {
      for (final template in [
        '{unknown}',
        '{seed',
        '{{seed}}',
        '{date:yyyy/MM/dd}',
        '{date:unknown}',
        '/tmp/{seed}',
        r'C:\out\{seed}',
        'C:out/{seed}',
        r'\\server\share\{seed}',
        '../{seed}',
        'a/../{seed}',
        'a//{seed}',
        'a/',
        './{seed}',
        'cache/{seed}',
        'BOARD_REFS/{seed}',
      ]) {
        expect(
          ImageSavePathService.validate(template),
          isNotNull,
          reason: template,
        );
        expect(
          ImageSavePathService.resolve(template, context),
          ImageSavePathService.resolve('', context),
          reason: template,
        );
      }
      expect(
        ImageSavePathService.validate(List.filled(9, 'a').join('/')),
        ImageSaveTemplateError.tooLong,
      );
      expect(
        ImageSavePathService.validate('a' * 513),
        ImageSaveTemplateError.tooLong,
      );
    });
    test('Windows 设备名、空值、尾随点空格与 UTF-8 长度限制', () {
      for (final name in ['CON', 'con.txt', 'LPT1', 'COM¹', 'NUL']) {
        expect(ImageSavePathService.sanitizeSegment(name), startsWith('_'));
      }
      expect(ImageSavePathService.sanitizeSegment(' hello... '), 'hello');
      expect(ImageSavePathService.sanitizeSegment('..'), '_');
      final longContext = ImageSaveContext(
        params: context.params.copyWith(prompt: '中文🙂' * 200),
        createdAt: context.createdAt,
        seed: 42,
      );
      final path = ImageSavePathService.resolve(
        '{prompt}/{prompt}/{prompt}',
        longContext,
      );
      expect(utf8.encode(path).length, lessThanOrEqualTo(180));
      expect(path, isNot(contains('\uFFFD')));
    });
    test('动态保留目录不会覆盖缓存；外部模型使用持久化标识', () {
      final external = ImageSaveContext(
        params: context.params.copyWith(prompt: 'cache'),
        createdAt: context.createdAt,
        seed: 42,
        prefix: 'nai_ai_edit',
        outputModel: 'external/model',
      );
      expect(
        ImageSavePathService.resolve('{prompt}/{seed}', external),
        '_cache/42.png',
      );
      expect(
        ImageSavePathService.resolve('{model}/{type}/{seed}', external),
        'external_model/ai_edit/42.png',
      );
    });
  });

  group('无覆盖文件写入', () {
    late Directory root;
    setUp(() => root = Directory.systemTemp.createTempSync('image_names_'));
    tearDown(() => root.deleteSync(recursive: true));

    test('递归建目录、同名自动编号、raw 与成品共享编号', () {
      final first = ImageFileStore.write(
        root: root.path,
        relativePath: 'nested/image.png',
        bytes: [1],
        originalBytes: [2],
      );
      final second = ImageFileStore.write(
        root: root.path,
        relativePath: 'nested/image.png',
        bytes: [3],
        originalBytes: [4],
      );
      expect(p.basename(second), 'image_2.png');
      expect(File(first).readAsBytesSync(), [1]);
      expect(
        File(p.join(root.path, 'nested', 'image_raw.png')).readAsBytesSync(),
        [2],
      );
      expect(
        File(p.join(root.path, 'nested', 'image_2_raw.png')).readAsBytesSync(),
        [4],
      );
    });
    test('仅 raw 存在时也跳过该编号，目录同名不被覆盖', () {
      File(p.join(root.path, 'image_raw.png')).writeAsBytesSync([9]);
      Directory(p.join(root.path, 'image_2.png')).createSync();
      final file = ImageFileStore.write(
        root: root.path,
        relativePath: 'image.png',
        bytes: [1],
        originalBytes: [2],
      );
      expect(p.basename(file), 'image_3.png');
      expect(File(p.join(root.path, 'image_raw.png')).readAsBytesSync(), [9]);
    });
    test('拒绝越界与非目录父节点', () {
      File(p.join(root.path, 'blocked')).writeAsStringSync('keep');
      for (final path in [
        '../escape.png',
        '/escape.png',
        r'C:\escape.png',
        'blocked/image.png',
      ]) {
        expect(
          () => ImageFileStore.write(
            root: root.path,
            relativePath: path,
            bytes: [1],
          ),
          throwsFileSystemException,
        );
      }
      expect(File(p.join(root.path, 'blocked')).readAsStringSync(), 'keep');
    });
    test('不跟随模板子目录的符号链接', () {
      final outside = Directory.systemTemp.createTempSync(
        'image_names_outside_',
      );
      addTearDown(() => outside.deleteSync(recursive: true));
      final linkPath = p.join(root.path, 'link');
      if (Platform.isWindows) {
        // Junction 无需 Windows 开发者模式/管理员权限。
        final result = Process.runSync('cmd', [
          '/c',
          'mklink',
          '/J',
          linkPath,
          outside.path,
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
      } else {
        Link(linkPath).createSync(outside.path);
      }
      expect(
        () => ImageFileStore.write(
          root: root.path,
          relativePath: 'link/image.png',
          bytes: [1],
        ),
        throwsFileSystemException,
      );
      expect(outside.listSync(), isEmpty);
      if (Platform.isWindows) {
        Process.runSync('cmd', ['/c', 'rmdir', linkPath]);
      } else {
        Link(linkPath).deleteSync();
      }
    });
  });

  test('配置默认值、copyWith 与持久化往返', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ConfigService();
    expect((await service.loadConfig()).imageSaveTemplate, '');
    const template = '{model}/{date:yyyy-MM-dd}/{seed}';
    await service.saveConfig(
      const AppConfig().copyWith(imageSaveTemplate: template),
    );
    expect((await service.loadConfig()).imageSaveTemplate, template);
  });

  testWidgets('设置模板可编辑、预览更新、显示校验错误与宏插入', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final draft = GeneralSettingsDraft(const AppConfig());
    addTearDown(draft.dispose);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: GeneralSettingsTab(draft: draft)),
      ),
    );
    await tester.pumpAndSettle();
    final input = find.byKey(const ValueKey('image-save-template'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '{model}/{seed}');
    await tester.pump();
    expect(find.text('nai-diffusion-5-full/123456.png'), findsOneWidget);
    await tester.enterText(input, '../{seed}');
    await tester.pump();
    expect(draft.saveTemplateError, ImageSaveTemplateError.invalidPath);
    expect(find.byKey(const ValueKey('image-save-preview')), findsNothing);
    draft.saveTemplateController.text = '';
    draft.insertSaveMacro('seed');
    await tester.pump();
    expect(draft.saveTemplateController.text, '{seed}');
    expect(find.text('123456.png'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
