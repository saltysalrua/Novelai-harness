import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/prompt_library_mention.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/chat_mention_text_controller.dart';

import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PromptLibraryService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('prompt_lib_test_');
    service = PromptLibraryService();
    service.setCustomStorageDirectory(tempDir.path);
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  group('PromptComboEntry Model Tests', () {
    test('isCharacter should be true for 角色 or character', () {
      final e1 = PromptComboEntry(
        id: '1',
        title: 'Miku',
        category: '角色',
        prompt: '1girl, hatsune miku',
        negativePrompt: 'low quality',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(e1.isCharacter, isTrue);

      final e2 = PromptComboEntry(
        id: '2',
        title: 'Miku',
        category: 'Character',
        prompt: '1girl, hatsune miku',
        negativePrompt: 'low quality',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(e2.isCharacter, isTrue);

      final e3 = PromptComboEntry(
        id: '3',
        title: 'Watercolor',
        category: '风格',
        prompt: 'watercolor style',
        negativePrompt: 'bad',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      expect(e3.isCharacter, isFalse);
    });

    test(
      'copyWith preserves negativePrompt for style and cleans style/negative fields on other categories',
      () {
        final charEntry = PromptComboEntry(
          id: '1',
          title: 'Miku',
          category: '角色',
          prompt: '1girl, hatsune miku',
          negativePrompt: 'bad hands, lowres',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        final styleEntry = charEntry.copyWith(
          category: '风格',
          prefixPrompt: 'artist:foo',
          suffixPrompt: 'very aesthetic',
        );
        expect(styleEntry.category, '风格');
        expect(styleEntry.isStyle, isTrue);
        expect(styleEntry.negativePrompt, 'bad hands, lowres');
        expect(styleEntry.prefixPrompt, 'artist:foo');
        expect(styleEntry.suffixPrompt, 'very aesthetic');

        final attireEntry = styleEntry.copyWith(category: '服装');
        expect(attireEntry.category, '服装');
        expect(attireEntry.isCharacter, isFalse);
        expect(attireEntry.isStyle, isFalse);
        expect(attireEntry.negativePrompt, '');
        expect(attireEntry.prefixPrompt, '');
        expect(attireEntry.suffixPrompt, '');
      },
    );

    test('style entry toJson and fromJson round-trip keeps affixes and negativePrompt', () {
      final original = PromptComboEntry(
        id: 'style_100',
        title: '水彩厚涂',
        category: '风格',
        prefixPrompt: 'artist:foo, watercolor style',
        suffixPrompt: 'very aesthetic, soft lighting',
        negativePrompt: '3d, photorealistic',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 2),
        tags: ['watercolor'],
      );

      final json = original.toJson();
      expect(json['prefixPrompt'], 'artist:foo, watercolor style');
      expect(json['suffixPrompt'], 'very aesthetic, soft lighting');
      expect(json['negativePrompt'], '3d, photorealistic');

      final reconstructed = PromptComboEntry.fromJson(json);
      expect(reconstructed.prefixPrompt, original.prefixPrompt);
      expect(reconstructed.suffixPrompt, original.suffixPrompt);
      expect(reconstructed.negativePrompt, original.negativePrompt);
      expect(reconstructed.hasEffectiveContent, isTrue);
    });

    test('toJson and fromJson round-trip keeps values intact', () {
      final original = PromptComboEntry(
        id: 'c100',
        title: '赛博朋克少女',
        category: '角色',
        prompt: '1girl, cybernetic, neon',
        negativePrompt: 'worst quality, bad anatomy',
        previewImagePath: '/path/to/img.png',
        createdAt: DateTime(2026, 8, 1),
        updatedAt: DateTime(2026, 8, 2),
        isFavorite: true,
        isBuiltin: false,
        tags: ['cyberpunk', 'girl'],
      );

      final json = original.toJson();
      expect(json['negativePrompt'], 'worst quality, bad anatomy');

      final reconstructed = PromptComboEntry.fromJson(json);
      expect(reconstructed.id, original.id);
      expect(reconstructed.title, original.title);
      expect(reconstructed.category, original.category);
      expect(reconstructed.prompt, original.prompt);
      expect(reconstructed.negativePrompt, original.negativePrompt);
      expect(reconstructed.previewImagePath, original.previewImagePath);
      expect(reconstructed.isFavorite, isTrue);
      expect(reconstructed.tags, ['cyberpunk', 'girl']);
    });
  });

  group('PromptLibraryService Persistence Tests', () {
    test(
      'loadEntries returns empty on first launch (no builtin seeding)',
      () async {
        final entries = await service.loadEntries();
        expect(entries, isEmpty);
        expect(service.cachedEntries, isEmpty);
      },
    );

    test('deleteAll then reload stays empty (entries never respawn)', () async {
      // 先新增两条自定义条目
      for (var i = 0; i < 2; i++) {
        await service.addEntry(
          PromptComboEntry(
            id: 'e$i',
            title: '预设$i',
            category: '风格',
            prompt: 'prompt $i',
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );
      }
      expect((await service.loadEntries()).length, 2);

      // 删空全部条目 (磁盘上保存空数组)
      final all = await service.loadEntries();
      for (final e in all) {
        await service.deleteEntry(e.id);
      }
      expect(await service.loadEntries(), isEmpty);

      // 重启语义：重新加载不得有任何条目复活
      final reloaded = await service.loadEntries();
      expect(reloaded, isEmpty);
      expect(service.cachedEntries, isEmpty);

      // 空词库下新增后重启，仅保留新增条目
      await service.addEntry(
        PromptComboEntry(
          id: 'solo_1',
          title: '唯一预设',
          category: '风格',
          prompt: 'solo',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      final finalList = await service.loadEntries();
      expect(finalList.length, 1);
      expect(finalList.first.id, 'solo_1');
    });

    test('addEntry, updateEntry, deleteEntry CRUD workflow', () async {
      await service.loadEntries();

      final newEntry = PromptComboEntry(
        id: 'custom_001',
        title: '测试自定义角色',
        category: '角色',
        prompt: '1girl, test prompt',
        negativePrompt: 'test negative',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      await service.addEntry(newEntry);
      var current = await service.loadEntries();
      expect(current.first.id, 'custom_001');

      final updated = newEntry.copyWith(title: '修改后的名称');
      await service.updateEntry(updated);
      current = await service.loadEntries();
      expect(current.firstWhere((e) => e.id == 'custom_001').title, '修改后的名称');

      await service.deleteEntry('custom_001');
      current = await service.loadEntries();
      expect(current.any((e) => e.id == 'custom_001'), isFalse);
    });

    test(
      'savePreviewImageBytes saves file to prompt_previews folder',
      () async {
        final dummyBytes = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
        final savedPath = await service.savePreviewImageBytes(dummyBytes);
        expect(savedPath, isNotNull);
        final file = File(savedPath!);
        expect(file.existsSync(), isTrue);
        expect(await file.readAsBytes(), dummyBytes);
      },
    );

    test(
      'updateEntry removes old managed preview file when image changes',
      () async {
        final bytes1 = Uint8List.fromList([1, 1, 1]);
        final bytes2 = Uint8List.fromList([2, 2, 2]);
        final path1 = await service.savePreviewImageBytes(bytes1);
        final path2 = await service.savePreviewImageBytes(bytes2);
        expect(File(path1!).existsSync(), isTrue);

        final entry = PromptComboEntry(
          id: 'preview_swap',
          title: '预览图更换测试',
          category: '风格',
          prompt: 'test prompt',
          previewImagePath: path1,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await service.addEntry(entry);

        // 更换为另一张预览图后，旧托管文件应被清理
        await service.updateEntry(entry.copyWith(previewImagePath: path2));
        final reloaded = await service.loadEntries();
        final updated = reloaded.firstWhere((e) => e.id == 'preview_swap');
        expect(updated.previewImagePath, path2);
        expect(File(path1).existsSync(), isFalse);
        expect(File(path2!).existsSync(), isTrue);
      },
    );

    test(
      'deleteEntry only deletes preview files inside managed directory',
      () async {
        // 外部路径的预览图 (例如导入 JSON 携带的任意路径) 不应被删除
        final outsideFile = File('${tempDir.path}/outside_image.png');
        outsideFile.writeAsBytesSync([9, 9, 9]);

        final entry = PromptComboEntry(
          id: 'outside_preview',
          title: '外部预览图',
          category: '风格',
          prompt: 'test prompt',
          previewImagePath: outsideFile.path,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        await service.addEntry(entry);

        await service.deleteEntry('outside_preview');
        expect(File(outsideFile.path).existsSync(), isTrue);
      },
    );

    test('export and import json', () async {
      // 先准备两条自定义条目再导出
      await service.saveEntries([
        PromptComboEntry(
          id: 'exp_1',
          title: '导出预设',
          category: '风格',
          prompt: 'export prompt',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      ]);

      final jsonString = await service.exportToJson();
      expect(jsonString.contains('导出预设'), isTrue);

      final count = await service.importFromJson(jsonString, replaceAll: true);
      expect(count, 1);
    });
  });

  group('StudioViewModel Library Mixin Tests', () {
    test(
      'applyPromptCombo appends or replaces main and negative prompts',
      () async {
        final vm = StudioViewModel(
          configService: ConfigService(),
          promptLibraryService: service,
        );
        await vm.init();

        vm.updatePrompt('1girl');
        vm.updateNegativePrompt('lowres');

        final charCombo = PromptComboEntry(
          id: 'char_1',
          title: '初音',
          category: '角色',
          prompt: 'hatsune miku, aqua hair',
          negativePrompt: 'bad hands',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // 追加模式 (replace = false)
        vm.applyPromptCombo(charCombo, replace: false);
        expect(vm.params.prompt, '1girl, hatsune miku, aqua hair');
        expect(vm.params.negativePrompt, 'lowres, bad hands');

        // 替换模式 (replace = true)
        vm.applyPromptCombo(charCombo, replace: true);
        expect(vm.params.prompt, 'hatsune miku, aqua hair');
        expect(vm.params.negativePrompt, 'bad hands');
      },
    );

    test(
      'applyPromptCombo for style does not affect negative prompt',
      () async {
        final vm = StudioViewModel(
          configService: ConfigService(),
          promptLibraryService: service,
        );
        await vm.init();

        vm.updatePrompt('1girl');
        vm.updateNegativePrompt('lowres, bad hands');

        final styleCombo = PromptComboEntry(
          id: 'style_1',
          title: '水彩',
          category: '风格',
          prompt: 'watercolor style',
          negativePrompt: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        vm.applyPromptCombo(styleCombo, replace: false);
        expect(vm.params.prompt, '1girl, watercolor style');
        // 负向词保持不变
        expect(vm.params.negativePrompt, 'lowres, bad hands');
      },
    );

    test('applyPromptCombo asCharacter adds a character prompt', () async {
      final vm = StudioViewModel(
        configService: ConfigService(),
        promptLibraryService: service,
      );
      await vm.init();

      final charCombo = PromptComboEntry(
        id: 'char_1',
        title: '初音',
        category: '角色',
        prompt: 'hatsune miku, aqua hair',
        negativePrompt: 'bad hands',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      vm.applyPromptCombo(charCombo, asCharacter: true);
      expect(vm.params.characterPrompts.isNotEmpty, isTrue);
      expect(vm.params.characterPrompts.last.prompt, 'hatsune miku, aqua hair');
      expect(vm.params.characterPrompts.last.negativePrompt, 'bad hands');
      expect(vm.params.characterPrompts.last.enabled, isTrue);
    });

    test(
      'searchAsSuggestions suggests all combos with prompt as insertText and isPromptCombo true',
      () async {
        // 准备自定义词库条目 (不再有内置预设)
        final now = DateTime.now();
        await service.saveEntries([
          PromptComboEntry(
            id: 's_watercolor',
            title: '日系二次元水彩风',
            category: '风格',
            prompt: 'watercolor style, pastel',
            createdAt: now,
            updatedAt: now,
            tags: ['watercolor'],
          ),
          PromptComboEntry(
            id: 's_miku',
            title: '初音未来 (Hatsune Miku)',
            category: '角色',
            prompt: '1girl, hatsune miku',
            negativePrompt: 'lowres',
            createdAt: now,
            updatedAt: now,
            tags: ['miku'],
          ),
        ]);

        // 查询水彩 (风格条目)
        final styleMatches = service.searchAsSuggestions('水彩');
        expect(styleMatches.isNotEmpty, isTrue);
        final match = styleMatches.first;
        expect(match.tag, '日系二次元水彩风');
        expect(match.customCategoryLabel, '风格');
        expect(match.insertText, contains('watercolor style'));
        expect(match.isPromptCombo, isTrue);

      // 角色分类条目 (如 初音未来) 同样支持补全，且 insertText 仅为主提示词
      final charMatches = service.searchAsSuggestions('初音');
      expect(charMatches.isNotEmpty, isTrue);
      final charMatch = charMatches.first;
      expect(charMatch.tag, '初音未来 (Hatsune Miku)');
      expect(charMatch.customCategoryLabel, '角色');
      expect(charMatch.insertText, contains('hatsune miku'));
      expect(charMatch.isPromptCombo, isTrue);
    });

    test(
      'applyPromptCombo asStyle populates affixes and negative prompt with replace/append and legacy fallback',
      () async {
        final vm = StudioViewModel(
          configService: ConfigService(),
          promptLibraryService: service,
        );
        await vm.init();

        vm.updateParams(
          vm.params.copyWith(
            prefixPrompt: 'old_prefix',
            suffixPrompt: 'old_suffix',
            negativePrompt: 'existing_uc',
            applyFixedPrompts: false,
          ),
        );

        final styleWithNegative = PromptComboEntry(
          id: 'st_1',
          title: '赛博水彩',
          category: '风格',
          prefixPrompt: 'watercolor, neon',
          suffixPrompt: 'very aesthetic',
          negativePrompt: '3d, photo',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );

        // 追加模式
        vm.applyPromptCombo(styleWithNegative, asStyle: true, replace: false);
        expect(vm.params.applyFixedPrompts, isTrue);
        expect(vm.params.prefixPrompt, 'old_prefix, watercolor, neon');
        expect(vm.params.suffixPrompt, 'old_suffix, very aesthetic');
        expect(vm.params.negativePrompt, 'existing_uc, 3d, photo');

        // 覆盖模式 (且风格负面词为空时不得清空工作台现有负面词)
        final styleNoNegative = PromptComboEntry(
          id: 'st_2',
          title: '油画',
          category: '风格',
          prefixPrompt: 'oil painting',
          suffixPrompt: '',
          negativePrompt: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        vm.applyPromptCombo(styleNoNegative, asStyle: true, replace: true);
        expect(vm.params.prefixPrompt, 'oil painting');
        expect(vm.params.suffixPrompt, '');
        expect(vm.params.negativePrompt, 'existing_uc, 3d, photo');

        // 旧版仅填 prompt 的风格条目作为 prefix 回退
        final legacyStyle = PromptComboEntry(
          id: 'st_legacy',
          title: '旧水彩',
          category: '风格',
          prompt: 'legacy watercolor',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        );
        vm.applyPromptCombo(legacyStyle, asStyle: true, replace: true);
        expect(vm.params.prefixPrompt, 'legacy watercolor');
      },
    );
  });

  group('PromptLibraryMention Tests', () {
    final now = DateTime(2026, 1, 1);
    final entries = [
      PromptComboEntry(
        id: 'c_miku',
        title: '初音未来 (Hatsune Miku)',
        category: '角色',
        prompt: '1girl, hatsune miku, aqua hair',
        negativePrompt: 'bad hands, secret_uc',
        isFavorite: true,
        tags: ['vocaloid', 'miku'],
        createdAt: now,
        updatedAt: now,
      ),
      PromptComboEntry(
        id: 'c_rin',
        title: '镜音铃',
        category: '角色',
        prompt: '1girl, kagamine rin, blonde hair, secret_tag',
        createdAt: now,
        updatedAt: now,
      ),
      PromptComboEntry(
        id: 'c_k',
        title: 'K',
        category: '角色',
        prompt: '1girl, short name',
        createdAt: now,
        updatedAt: now,
      ),
      PromptComboEntry(
        id: 's_wc',
        title: '水彩风',
        category: '风格',
        prefixPrompt: 'watercolor',
        createdAt: now,
        updatedAt: now,
      ),
    ];

    test('extractActiveCharacterMention detects @ query and skips emails/spaces', () {
      final m1 = extractActiveCharacterMention('画一下 @初音', 7);
      expect(m1, isNotNull);
      expect(m1!.atIndex, 4);
      expect(m1.query, '初音');

      final mEmpty = extractActiveCharacterMention('@', 1);
      expect(mEmpty, isNotNull);
      expect(mEmpty!.query, '');

      expect(extractActiveCharacterMention('user@example.com', 16), isNull);
      expect(extractActiveCharacterMention('画 @[初音未来] 在海边', 15), isNull);
    });

    test('matchCharacterMentionSuggestions filters characters only and ranks favorites', () {
      final all = matchCharacterMentionSuggestions('', entries);
      expect(all.any((e) => e.id == 's_wc'), isFalse);
      expect(all.first.id, 'c_miku');

      final byTag = matchCharacterMentionSuggestions('vocaloid', entries);
      expect(byTag.single.id, 'c_miku');
    });

    test('extractLinkedCharacters and removeCharacterMention handle @[title]', () {
      final text = '帮我画 ${formatCharacterMention('初音未来 (Hatsune Miku)')} 和镜音铃';
      final linked = extractLinkedCharacters(text, entries);
      expect(linked.map((e) => e.id), ['c_miku']);

      final cleaned = removeCharacterMention(text, entries.first);
      expect(cleaned, '帮我画 和镜音铃');
    });

    test('resolveLibraryCharactersForMessage resolves explicit, implicit alias, and sanitizes banned words', () {
      final ctx1 = resolveLibraryCharactersForMessage(
        '让 Hatsune Miku 和 @[镜音铃] 一起喝奶茶',
        entries,
        sanitizeText: (s) => s.replaceAll('secret_tag', '').replaceAll('secret_uc', ''),
      );
      expect(ctx1, isNotNull);
      expect(ctx1, contains('<library_characters>'));
      expect(ctx1, contains('hatsune miku, aqua hair'));
      expect(ctx1, contains('kagamine rin, blonde hair'));
      expect(ctx1, isNot(contains('secret_tag')));
      expect(ctx1, isNot(contains('secret_uc')));

      // 单字符名称 'K' 不得误触发隐式关联
      final ctxNoShort = resolveLibraryCharactersForMessage(
        'ok let us draw a cat',
        entries,
      );
      expect(ctxNoShort, isNull);
    });

    test('ChatMentionTextController encodes/decodes inline atomic tokens without drift', () {
      var loaded = <PromptComboEntry>[];
      final controller = ChatMentionTextController(
        entriesProvider: () => loaded,
      );
      addTearDown(controller.dispose);

      // 词库未加载前保留纯文本，加载后 upgradeRawMentions 原地升级并保持光标正确
      controller.setSerializedText('画 @[镜音铃] 在海边');
      expect(controller.text, '画 @[镜音铃] 在海边');

      loaded = entries;
      controller.upgradeRawMentions();
      expect(controller.text.length, 7); // '画 ' + 1 占位符 + ' 在海边'
      expect(controller.toSerializedText(), '画 @[镜音铃] 在海边');
      expect(controller.selection.baseOffset, 7);

      // 插入第二个角色并校验范围序列化与原子移除
      controller.insertMention(
        '初音未来 (Hatsune Miku)',
        replaceStart: 7,
        replaceEnd: 7,
      );
      expect(
        controller.toSerializedText(),
        '画 @[镜音铃] 在海边@[初音未来 (Hatsune Miku)] ',
      );
      expect(controller.containsMentionInRange(0, controller.text.length), isTrue);
      expect(controller.serializeRange(2, 3), '@[镜音铃]');

      // 在占位符后直接输入 @ 不会把占位符误并入查询，也不会阻断新提及
      final withAt = '${controller.text}@初';
      final active = extractActiveCharacterMention(withAt, withAt.length);
      expect(active, isNotNull);
      expect(active!.query, '初');

      // 点击卡片删除后，顺带清理多余空格且保留后续文本
      controller.removeTokenAt(2);
      expect(
        controller.toSerializedText(),
        '画 在海边@[初音未来 (Hatsune Miku)] ',
      );

      // clearAll 后状态重置
      controller.clearAll();
      expect(controller.text, isEmpty);
      expect(controller.toSerializedText(), isEmpty);
    });
  });
}
