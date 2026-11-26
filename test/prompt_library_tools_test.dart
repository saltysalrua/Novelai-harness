import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/prompt_library_tools.dart';
import 'package:novelai_harness/core/harness/tools/reference_guide_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/data/services/prompt_library_mention.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';

/// 1x1 纯净 PNG 字节 (供预览图工具解码)
const List<int> kTestPngBytes = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tempDir;
  late List<PromptComboEntry> entries;

  PromptComboEntry entry(
    String id,
    String title, {
    String category = PromptComboCategories.style,
    String prompt = 'sample prompt',
    String negativePrompt = '',
    List<String> tags = const [],
    bool favorite = false,
    bool builtin = false,
  }) {
    final now = DateTime(2026, 1, 1);
    return PromptComboEntry(
      id: id,
      title: title,
      category: category,
      prompt: prompt,
      negativePrompt: negativePrompt,
      createdAt: now,
      updatedAt: now,
      isFavorite: favorite,
      isBuiltin: builtin,
      tags: tags,
    );
  }

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('prompt_lib_tools_');
    PromptLibraryService.instance.setCustomStorageDirectory(tempDir.path);
    await PromptLibraryService.instance.saveEntries([
      entry(
        'e1',
        '水彩风',
        category: PromptComboCategories.style,
        prompt: 'watercolor, pastel',
        tags: ['watercolor'],
      ),
      entry(
        'e2',
        '初音未来',
        category: PromptComboCategories.character,
        prompt: '1girl, hatsune miku',
        negativePrompt: 'lowres',
        favorite: true,
      ),
      entry(
        'e3',
        '和服',
        category: PromptComboCategories.attire,
        prompt: 'kimono, traditional',
        tags: ['japan', 'kimono'],
      ),
    ]);
    entries = List.from(PromptLibraryService.instance.cachedEntries);
  });

  tearDown(() async {
    PromptLibraryService.instance.setCustomStorageDirectory(null);
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  // 回调挂接到真实服务，验证工具真正驱动持久化层
  Future<PromptComboEntry> addEntry(PromptComboEntry e) async {
    final created = await PromptLibraryService.instance.addEntry(e);
    entries = List.from(PromptLibraryService.instance.cachedEntries);
    return created;
  }

  Future<void> updateEntry(PromptComboEntry e) async {
    await PromptLibraryService.instance.updateEntry(e);
    entries = List.from(PromptLibraryService.instance.cachedEntries);
  }

  Future<void> deleteEntry(String id) async {
    await PromptLibraryService.instance.deleteEntry(id);
    entries = List.from(PromptLibraryService.instance.cachedEntries);
  }

  test('搜索工具: 无参数返回摘要而非全文', () async {
    final tool = SearchPromptLibraryTool(getEntries: () => entries);
    final result = await tool.execute('t1', {});
    expect(result.isError, isFalse);
    expect(result.content, contains('共 3 条'));
    expect(result.content, contains('[e1] 水彩风'));
    expect(result.content, isNot(contains('lowres')));
    expect(result.content, isNot(contains('watercolor, pastel')));
  });

  test('搜索工具: 分页与边界保留按 ID 读取全文', () async {
    final many = List.generate(60, (i) => entry('p$i', '标题$i', prompt: '全文$i'));
    final tool = SearchPromptLibraryTool(getEntries: () => many);
    final first = await tool.execute('p1', {});
    expect(first.content, contains('下一页 offset: 10'));
    expect(first.content, isNot(contains('[p10]')));
    expect(first.content, isNot(contains('提示词: 全文')));
    final next = await tool.execute('p2', {'offset': 10, 'limit': 2});
    expect(next.content, contains('[p10]'));
    expect(next.content, contains('[p11]'));
    expect(next.content, isNot(contains('[p12]')));
    final capped = await tool.execute('p3', {'offset': -1, 'limit': 999});
    expect(capped.content, contains('下一页 offset: 50'));
    final empty = await tool.execute('p4', {'offset': 999});
    expect(empty.content, contains('本页 0 条'));
    final detail = await tool.execute('p5', {'id': 'p59'});
    expect(detail.content, contains('提示词: 全文59'));
  });

  test('搜索工具: 关键词与分类过滤', () async {
    final tool = SearchPromptLibraryTool(getEntries: () => entries);

    final byQuery = await tool.execute('t1', {'query': 'miku'});
    expect(byQuery.content, contains('[e2] 初音未来'));
    expect(byQuery.content, isNot(contains('[e1]')));

    final byTag = await tool.execute('t2', {'query': 'japan'});
    expect(byTag.content, contains('[e3] 和服'));

    final byCategory = await tool.execute('t3', {'category': '角色'});
    expect(byCategory.content, contains('[e2]'));
    expect(byCategory.content, isNot(contains('[e1]')));

    final none = await tool.execute('t4', {'query': '不存在'});
    expect(none.content, contains('没有匹配'));
  });

  test('搜索工具: 按 ID 精确读取与不存在报错', () async {
    final tool = SearchPromptLibraryTool(getEntries: () => entries);

    final byId = await tool.execute('t1', {'id': 'e2'});
    expect(byId.content, contains('初音未来'));
    expect(byId.content, contains('[收藏]'));

    final missing = await tool.execute('t2', {'id': 'nope'});
    expect(missing.isError, isTrue);
  });

  test('新增工具: 正常新增并返回 ID', () async {
    final tool = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    );
    final result = await tool.execute('t1', {
      'title': '赛博朋克',
      'prompt': 'cyberpunk, neon',
      'category': '风格',
      'tags': ['neon'],
    });

    expect(result.isError, isFalse);
    expect(result.content, contains('赛博朋克'));

    // 已持久化到服务
    final persisted = await PromptLibraryService.instance.loadEntries();
    final created = persisted.firstWhere((e) => e.title == '赛博朋克');
    expect(created.prompt, 'cyberpunk, neon');
    expect(created.tags, contains('neon'));
    expect(created.isBuiltin, isFalse);
  });

  test('新增工具: 必填校验与同名拦截', () async {
    final tool = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    );

    final empty = await tool.execute('t1', {'title': '', 'prompt': 'x'});
    expect(empty.isError, isTrue);
    expect(empty.content, contains('必填'));

    final dup = await tool.execute('t2', {'title': '水彩风', 'prompt': 'x'});
    expect(dup.isError, isTrue);
    expect(dup.content, contains('同名'));
  });

  test('新增工具: 风格分类支持仅前后缀与负面词，非角色/风格自动清空', () async {
    final addTool = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    );
    final styleResult = await addTool.execute('t_style', {
      'title': '赛博厚涂风',
      'category': '风格',
      'prefix_prompt': 'artist:cyber, impasto',
      'suffix_prompt': 'very aesthetic',
      'negative_prompt': 'flat color',
    });
    expect(styleResult.isError, isFalse);
    expect(styleResult.content, contains('前置词: artist:cyber, impasto'));
    expect(styleResult.content, contains('后置词: very aesthetic'));
    expect(styleResult.content, contains('负面提示词: flat color'));

    final searchTool = SearchPromptLibraryTool(getEntries: () => entries);
    final byPrefix = await searchTool.execute('t_search', {'query': 'impasto'});
    expect(byPrefix.content, contains('赛博厚涂风'));

    final createdStyle = entries.firstWhere((e) => e.title == '赛博厚涂风');
    final updateTool = UpdatePromptLibraryEntryTool(
      getEntries: () => entries,
      updateEntry: updateEntry,
    );
    final updatedRes = await updateTool.execute('t_upd', {
      'id': createdStyle.id,
      'suffix_prompt': 'masterpiece',
    });
    expect(updatedRes.isError, isFalse);
    expect(
      entries.firstWhere((e) => e.id == createdStyle.id).suffixPrompt,
      'masterpiece',
    );

    final attireResult = await addTool.execute('t_attire', {
      'title': '构图预设',
      'prompt': 'low angle',
      'category': '构图',
      'prefix_prompt': 'should drop',
      'negative_prompt': 'should be dropped',
    });

    expect(attireResult.isError, isFalse);
    final persisted = await PromptLibraryService.instance.loadEntries();
    final createdAttire = persisted.firstWhere((e) => e.title == '构图预设');
    expect(createdAttire.negativePrompt, isEmpty);
    expect(createdAttire.prefixPrompt, isEmpty);
  });

  test('修改工具: 部分字段更新，未传字段保持原值', () async {
    final tool = UpdatePromptLibraryEntryTool(
      getEntries: () => entries,
      updateEntry: updateEntry,
    );
    final result = await tool.execute('t1', {
      'id': 'e1',
      'title': '新水彩',
      'tags': ['watercolor', 'updated'],
    });

    expect(result.isError, isFalse);
    expect(result.content, contains('[e1] 新水彩'));
    expect(result.content, contains('watercolor, pastel')); // prompt 未变

    final persisted = await PromptLibraryService.instance.loadEntries();
    final updated = persisted.firstWhere((e) => e.id == 'e1');
    expect(updated.title, '新水彩');
    expect(updated.prompt, 'watercolor, pastel');
    expect(updated.tags, ['watercolor', 'updated']);
  });

  test('修改工具: 不存在 ID 报错', () async {
    final tool = UpdatePromptLibraryEntryTool(
      getEntries: () => entries,
      updateEntry: updateEntry,
    );
    final result = await tool.execute('t1', {'id': 'ghost', 'title': 'x'});
    expect(result.isError, isTrue);
  });

  test('修改工具: updates 数组一次修改复数条目', () async {
    final tool = UpdatePromptLibraryEntryTool(
      getEntries: () => entries,
      updateEntry: updateEntry,
    );
    final result = await tool.execute('t1', {
      'updates': [
        {'id': 'e1', 'title': '批量改水彩'},
        {'id': 'e3', 'favorite': true},
        {'id': 'ghost', 'title': 'x'},
      ],
    });

    expect(result.isError, isFalse);
    // 不存在的 ID 只作部分失败提示，不阻断已命中的条目
    expect(result.content, contains('未修改'));
    expect(result.content, contains('ghost'));

    final persisted = await PromptLibraryService.instance.loadEntries();
    expect(persisted.firstWhere((e) => e.id == 'e1').title, '批量改水彩');
    // 未传的字段保持原值
    expect(
      persisted.firstWhere((e) => e.id == 'e1').prompt,
      'watercolor, pastel',
    );
    expect(persisted.firstWhere((e) => e.id == 'e3').isFavorite, isTrue);
  });

  test('修改工具: 全部未命中时按错误返回', () async {
    final tool = UpdatePromptLibraryEntryTool(
      getEntries: () => entries,
      updateEntry: updateEntry,
    );
    final result = await tool.execute('t1', {
      'updates': [
        {'id': 'ghost', 'title': 'x'},
        {'id': 'nada', 'title': 'y'},
      ],
    });
    expect(result.isError, isTrue);
    expect(result.content, contains('未修改任何条目'));
  });

  test('删除工具: 正常删除与不存在报错', () async {
    final tool = DeletePromptLibraryEntryTool(
      getEntries: () => entries,
      deleteEntry: deleteEntry,
    );

    final ok = await tool.execute('t1', {'id': 'e3'});
    expect(ok.isError, isFalse);
    final persisted = await PromptLibraryService.instance.loadEntries();
    expect(persisted.any((e) => e.id == 'e3'), isFalse);

    final missing = await tool.execute('t2', {'id': 'e3'});
    expect(missing.isError, isTrue);
  });

  test('删除工具: ids 数组一次删除复数条目', () async {
    final tool = DeletePromptLibraryEntryTool(
      getEntries: () => entries,
      deleteEntry: deleteEntry,
    );

    final result = await tool.execute('t1', {
      'ids': ['e1', 'e2', 'nope'],
    });
    expect(result.isError, isFalse);
    expect(result.content, contains('未找到 nope'));

    final persisted = await PromptLibraryService.instance.loadEntries();
    expect(persisted.any((e) => e.id == 'e1' || e.id == 'e2'), isFalse);
    expect(persisted.any((e) => e.id == 'e3'), isTrue);
  });

  test('删除工具: 全部未命中时按错误返回且不动数据', () async {
    final tool = DeletePromptLibraryEntryTool(
      getEntries: () => entries,
      deleteEntry: deleteEntry,
    );
    final result = await tool.execute('t1', {
      'ids': ['nope', 'nada'],
    });
    expect(result.isError, isTrue);
    expect(entries, hasLength(3));
  });

  test('新增工具: entries 数组一次新增复数条目且 ID 不冲突', () async {
    final tool = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    );

    final result = await tool.execute('t1', {
      'entries': [
        {'title': '批量甲', 'prompt': 'alpha', 'category': '风格'},
        {
          'title': '批量乙',
          'prompt': 'beta',
          'tags': ['beta'],
        },
      ],
    });
    expect(result.isError, isFalse);

    final persisted = await PromptLibraryService.instance.loadEntries();
    final created = persisted.where((e) => e.title.startsWith('批量')).toList();
    expect(created, hasLength(2));
    expect(created.map((e) => e.id).toSet(), hasLength(2));
    expect(created.firstWhere((e) => e.title == '批量甲').tags, isEmpty);
    expect(created.firstWhere((e) => e.title == '批量乙').tags, contains('beta'));
  });

  test('新增工具: 批量中途重名则整体拒绝', () async {
    final tool = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    );

    final result = await tool.execute('t1', {
      'entries': [
        {'title': '全新条目', 'prompt': 'alpha'},
        {'title': '水彩风', 'prompt': 'beta'},
      ],
    });
    expect(result.isError, isTrue);
    expect(result.content, contains('同名'));

    final persisted = await PromptLibraryService.instance.loadEntries();
    expect(persisted.any((e) => e.title == '全新条目'), isFalse);
  });

  test('工具 Schema: OpenAI Function Definition 格式正确', () {
    final search = SearchPromptLibraryTool(
      getEntries: () => entries,
    ).toOpenAiFunction();
    expect(search['function']['name'], 'search_prompt_library');

    final add = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    ).toOpenAiFunction();
    // 顶层 title/prompt 与 entries 数组二选一，故不设 required，由工具侧校验
    expect(
      add['function']['parameters']['properties'].keys,
      containsAll(<String>['title', 'prompt', 'entries']),
    );

    final update = UpdatePromptLibraryEntryTool(
      getEntries: () => entries,
      updateEntry: updateEntry,
    ).toOpenAiFunction();
    expect(
      update['function']['parameters']['properties'].containsKey('id'),
      isTrue,
    );

    final delete = DeletePromptLibraryEntryTool(
      getEntries: () => entries,
      deleteEntry: deleteEntry,
    ).toOpenAiFunction();
    expect(delete['function']['name'], 'delete_prompt_library_entry');

    final preview = SetPromptLibraryPreviewTool(
      getEntries: () => entries,
      updateEntry: updateEntry,
    ).toOpenAiFunction();
    expect(preview['function']['name'], 'set_prompt_library_preview');
    expect(preview['function']['parameters']['required'], ['id']);
  });

  group('预览图工具', () {
    NaiGeneratedImage makeImage(String id) => NaiGeneratedImage(
      id: id,
      bytes: Uint8List.fromList(kTestPngBytes),
      params: const NaiGenerationParams(
        prompt: '1girl',
        width: 832,
        height: 1216,
      ),
      seed: 42,
      isOpusFree: true,
      createdAt: DateTime(2026, 1, 1),
    );

    SetPromptLibraryPreviewTool makeTool({
      List<NaiGeneratedImage> history = const [],
    }) {
      return SetPromptLibraryPreviewTool(
        getEntries: () => entries,
        updateEntry: updateEntry,
        getHistory: () => history,
        loadImageBytes: (image) async => image.bytes,
        savePreviewBytes: (bytes) =>
            PromptLibraryService.instance.savePreviewImageBytes(bytes),
        copyPreviewFromPath: (path) =>
            PromptLibraryService.instance.copyPreviewImageFromPath(path),
      );
    }

    test('来源校验: 缺 id / 条目不存在 / 无来源', () async {
      final tool = makeTool(history: [makeImage('img-1')]);

      final noId = await tool.execute('t1', {'index': 0});
      expect(noId.isError, isTrue);

      final missing = await tool.execute('t2', {'id': 'ghost', 'index': 0});
      expect(missing.isError, isTrue);

      final noSource = await tool.execute('t3', {'id': 'e1'});
      expect(noSource.isError, isTrue);
      expect(noSource.content, contains('未指定预览图来源'));
    });

    test('索引来源: 从画板历史图片设置预览图并落盘', () async {
      final history = [makeImage('img-new'), makeImage('img-old')];
      final tool = makeTool(history: history);

      final result = await tool.execute('t1', {'id': 'e1', 'index': 0});
      expect(result.isError, isFalse);
      expect(result.content, contains('预览图'));
      expect(result.content, contains('索引 0'));

      final persisted = await PromptLibraryService.instance.loadEntries();
      final updated = persisted.firstWhere((e) => e.id == 'e1');
      expect(updated.previewImagePath, isNotNull);
      // 落盘到托管预览目录且文件真实存在
      expect(updated.previewImagePath!, contains('prompt_previews'));
      expect(File(updated.previewImagePath!).existsSync(), isTrue);

      // 搜索结果展示预览图状态
      final searchTool = SearchPromptLibraryTool(getEntries: () => entries);
      final search = await searchTool.execute('t2', {'id': 'e1'});
      expect(search.content, contains('预览图: 已设置'));
    });

    test('索引来源: 越界与空历史报错', () async {
      final tool = makeTool(history: [makeImage('img-1')]);

      final outOfRange = await tool.execute('t1', {'id': 'e1', 'index': 5});
      expect(outOfRange.isError, isTrue);
      expect(outOfRange.content, contains('超出范围'));

      final emptyHistory = makeTool(history: const []);
      final empty = await emptyHistory.execute('t2', {'id': 'e1', 'index': 0});
      expect(empty.isError, isTrue);
      expect(empty.content, contains('没有任何历史图片'));
    });

    test('路径来源: 从本地文件复制预览图', () async {
      final srcFile = File(
        '${tempDir.path}${Platform.pathSeparator}source.png',
      );
      await srcFile.writeAsBytes(kTestPngBytes);

      final tool = makeTool();
      final result = await tool.execute('t1', {
        'id': 'e3',
        'image_path': srcFile.path,
      });
      expect(result.isError, isFalse);

      final persisted = await PromptLibraryService.instance.loadEntries();
      final updated = persisted.firstWhere((e) => e.id == 'e3');
      expect(updated.previewImagePath, isNotNull);
      expect(updated.previewImagePath!, contains('prompt_previews'));
      expect(File(updated.previewImagePath!).existsSync(), isTrue);

      // 不存在的路径报错
      final badPath = await tool.execute('t2', {
        'id': 'e3',
        'image_path': '${tempDir.path}/not_exist.png',
      });
      expect(badPath.isError, isTrue);
      expect(badPath.content, contains('未能从路径读取图片'));
    });

    test('清除预览图: 正常清除并删除托管文件；无预览图时提示无需清除', () async {
      // 先设置预览图
      final history = [makeImage('img-1')];
      final tool = makeTool(history: history);
      final setResult = await tool.execute('t1', {'id': 'e2', 'index': 0});
      expect(setResult.isError, isFalse);

      var persisted = await PromptLibraryService.instance.loadEntries();
      var target = persisted.firstWhere((e) => e.id == 'e2');
      final previewPath = target.previewImagePath!;
      expect(File(previewPath).existsSync(), isTrue);

      // 再清除
      final clearResult = await tool.execute('t2', {'id': 'e2', 'clear': true});
      expect(clearResult.isError, isFalse);

      persisted = await PromptLibraryService.instance.loadEntries();
      target = persisted.firstWhere((e) => e.id == 'e2');
      expect(target.previewImagePath, isNull);
      // 旧托管预览文件被同步清理，无孤儿文件
      expect(File(previewPath).existsSync(), isFalse);

      // 无预览图时再清除: 提示而非报错
      final noop = await tool.execute('t3', {'id': 'e2', 'clear': true});
      expect(noop.isError, isFalse);
      expect(noop.content, contains('本就没有预览图'));
    });
  });

  group('ReferenceGuidesTool & Library-Reference Linkage', () {
    test('ReferenceGuidesTool supports add_from_canvas, list, update, remove, clear and add_from_library', () async {
      var params = const NaiGenerationParams(
        prompt: '1girl',
        model: NaiModel.v5Full,
      );
      var refSeq = 0;

      final refImgPath = await PromptLibraryService.instance
          .savePreviewImageBytes(Uint8List.fromList(kTestPngBytes), prefix: 'ref');
      expect(refImgPath, isNotNull);

      final charWithRef = PromptComboEntry(
        id: 'char_ref_1',
        title: '白丝祈酱',
        category: PromptComboCategories.character,
        prompt: '1girl, black hair, white thighhighs',
        preciseReferences: [
          PromptLibraryPreciseRef(
            id: 'lib_p1',
            imagePath: refImgPath!,
            fileName: 'inori.png',
            type: NaiPreciseRefType.character,
            preferSameOutfit: true,
            strength: 1.2,
          ),
        ],
        createdAt: DateTime(2026, 11, 25),
        updatedAt: DateTime(2026, 11, 25),
      );
      await addEntry(charWithRef);

      final history = [
        NaiGeneratedImage(
          id: 'canvas_0',
          bytes: Uint8List.fromList(kTestPngBytes),
          params: params,
          seed: 42,
          isOpusFree: true,
          createdAt: DateTime(2026, 11, 25),
        ),
      ];

      final tool = ReferenceGuidesTool(
        getCurrentParams: () => params,
        addPreciseReference: (
          bytes, {
          fileName,
          type,
          preferSameOutfit,
          strength,
          fidelity,
          replace = false,
        }) {
          final resolvedType = type ?? NaiPreciseRefType.characterAndStyle;
          final ref = NaiPreciseReference(
            id: 'pref_${++refSeq}',
            imageBytes: bytes,
            fileName: fileName,
            type: resolvedType,
            preferSameOutfit:
                preferSameOutfit ??
                (resolvedType == NaiPreciseRefType.characterAndStyle),
            strength: strength ?? 1.0,
            fidelity: fidelity ?? 1.0,
          );
          params = params.copyWith(
            preciseReferences: replace ? [ref] : [...params.preciseReferences, ref],
          );
        },
        updatePreciseReference: (
          id, {
          type,
          preferSameOutfit,
          strength,
          fidelity,
          enabled,
        }) {
          params = params.copyWith(
            preciseReferences: params.preciseReferences
                .map(
                  (r) => r.id == id
                      ? r.copyWith(
                          type: type,
                          preferSameOutfit: preferSameOutfit,
                          strength: strength,
                          fidelity: fidelity,
                          enabled: enabled,
                        )
                      : r,
                )
                .toList(),
          );
        },
        removePreciseReference: (id) {
          params = params.copyWith(
            preciseReferences:
                params.preciseReferences.where((r) => r.id != id).toList(),
          );
        },
        clearPreciseReferences: () {
          params = params.copyWith(preciseReferences: const []);
        },
        importVibeFromBytes: ({
          required fileName,
          required bytes,
          strength,
          informationExtracted,
          replace = false,
        }) async {
          final v = NaiVibeReference(
            id: 'vibe_${++refSeq}',
            displayName: fileName,
            rawImageBytes: bytes,
            strength: strength ?? 0.6,
            informationExtracted: informationExtracted ?? 1.0,
          );
          params = params.copyWith(
            vibeReferences: replace ? [v] : [...params.vibeReferences, v],
          );
          return 1;
        },
        updateVibeReference: (id, {strength, informationExtracted, enabled}) {},
        removeVibeReference: (id) {
          params = params.copyWith(
            vibeReferences:
                params.vibeReferences.where((v) => v.id != id).toList(),
          );
        },
        clearVibeReferences: () {
          params = params.copyWith(vibeReferences: const []);
        },
        setNormalizeVibeStrength: (v) {
          params = params.copyWith(normalizeVibeStrength: v);
        },
        getHistory: () => history,
        loadImageBytes: (img) async => img.bytes,
        getLibraryEntries: () => entries,
        applyLibraryReferences: (
          entry, {
          bool includePrecise = true,
          bool includeVibe = true,
          bool replace = false,
          Set<String>? preciseRefIds,
          Set<String>? vibeRefIds,
        }) async {
          var count = 0;
          if (includePrecise) {
            final added = <NaiPreciseReference>[];
            for (final r in entry.preciseReferences) {
              if (preciseRefIds != null && !preciseRefIds.contains(r.id)) {
                continue;
              }
              added.add(
                NaiPreciseReference(
                  id: 'pref_${++refSeq}',
                  imageBytes: await File(r.imagePath).readAsBytes(),
                  fileName: r.fileName,
                  type: r.type,
                  preferSameOutfit: r.preferSameOutfit,
                  strength: r.strength,
                ),
              );
            }
            params = params.copyWith(
              preciseReferences: replace
                  ? added
                  : [...params.preciseReferences, ...added],
            );
            count = added.length;
          }
          return (appliedPreciseCount: count, appliedVibeCount: 0);
        },
      );

      // 1. Mount canvas image as Outfit Reference
      final addRes = await tool.execute('rg1', {
        'action': 'add_from_canvas',
        'image_index': 0,
        'ref_type': 'outfit',
        'strength': 1.8,
      });
      expect(addRes.isError, isFalse);
      expect(params.preciseReferences.length, 1);
      expect(params.preciseReferences.first.type, NaiPreciseRefType.outfit);
      expect(params.preciseReferences.first.strength, 1.8);

      // 2. Mount from library entry
      final libRes = await tool.execute('rg2', {
        'action': 'add_from_library',
        'entry_id': 'char_ref_1',
      });
      expect(libRes.isError, isFalse);
      expect(params.preciseReferences.length, 2);

      // 3. Update strength & disable
      final targetId = params.preciseReferences.last.id;
      final updRes = await tool.execute('rg3', {
        'action': 'update',
        'id': targetId,
        'prefer_same_outfit': false,
        'strength': 2.5,
      });
      expect(updRes.isError, isFalse);
      expect(params.preciseReferences.last.preferSameOutfit, isFalse);
      expect(params.preciseReferences.last.strength, 2.5);

      // 4. Remove & clear
      final remRes = await tool.execute('rg4', {
        'action': 'remove',
        'id': targetId,
      });
      expect(remRes.isError, isFalse);
      expect(params.preciseReferences.length, 1);

      final clrRes = await tool.execute('rg5', {
        'action': 'clear',
        'scope': 'precise',
      });
      expect(clrRes.isError, isFalse);
      expect(params.preciseReferences, isEmpty);

      // 5. Mention resolution informs Agent of attached visual reference
      final mentionCtx = resolveLibraryCharactersForMessage(
        '画一张 @[白丝祈酱] 穿泳装',
        entries,
      );
      expect(mentionCtx, isNotNull);
      expect(mentionCtx!, contains('已关联参考图'));
      expect(mentionCtx, contains('reference_guides'));
      expect(mentionCtx, contains('char_ref_1'));
    });

    test('待整理区工具全链路: list_inbox -> read_inbox(含视觉附件) -> add(复用图) -> delete_inbox', () async {
      final imgPath = await PromptLibraryService.instance.savePreviewImageBytes(
        Uint8List.fromList(kTestPngBytes),
        prefix: 'inbox',
      );
      expect(imgPath, isNotNull);

      final now = DateTime(2026, 11, 26, 18, 0);
      await PromptLibraryService.instance.addInboxItem(
        PromptInboxItem(
          id: 'inbox_a',
          prompt: '1girl, outdoor cafe, golden hour, cinematic lighting',
          negativePrompt: 'lowres',
          characterPrompts: const [
            PromptInboxCharacter(
              name: '祈酱',
              prompt: 'black hair, golden eyes, white cardigan, white stockings',
              negativePrompt: 'bad hands',
            ),
          ],
          imagePath: imgPath,
          createdAt: now,
          updatedAt: now,
        ),
      );
      var inboxItems = await PromptLibraryService.instance.loadInboxItems();

      final tool = PromptLibraryTool(
        getEntries: () => entries,
        addEntry: addEntry,
        updateEntry: updateEntry,
        deleteEntry: deleteEntry,
        getInboxItems: () => inboxItems,
        deleteInboxItems: (ids) async {
          final removed = await PromptLibraryService.instance.deleteInboxItems(
            ids,
          );
          inboxItems = await PromptLibraryService.instance.loadInboxItems();
          return removed;
        },
        isModelMultimodal: () => true,
        getHistory: () => const [],
        loadImageBytes: (_) async => null,
      );

      // 1. list_inbox
      final listRes = await tool.execute('in_1', {'action': 'list_inbox'});
      expect(listRes.isError, isFalse);
      expect(listRes.content, contains('[inbox_a]'));
      expect(listRes.content, contains('角色×1'));
      expect(listRes.content, contains('有图'));

      // 2. read_inbox (returns main prompt, character prompt & imageBase64)
      final readRes = await tool.execute('in_2', {
        'action': 'read_inbox',
        'inbox_id': 'inbox_a',
      });
      expect(readRes.isError, isFalse);
      expect(readRes.content, contains('outdoor cafe, golden hour'));
      expect(readRes.content, contains('祈酱'));
      expect(readRes.content, contains('white stockings'));
      expect(readRes.imageBase64, isNotNull);
      expect(readRes.imageBase64, isNotEmpty);

      // 3. add formal entries reusing inbox image via preview_inbox_id
      final addRes = await tool.execute('in_3', {
        'action': 'add',
        'entries': [
          {
            'title': '祈酱常服',
            'category': '角色',
            'prompt': 'black hair, golden eyes, white cardigan, white stockings',
            'negative_prompt': 'bad hands',
            'preview_inbox_id': 'inbox_a',
            'tags': ['白丝', '祈酱'],
          },
          {
            'title': '黄金时刻露天咖啡馆',
            'category': '环境',
            'prompt': 'outdoor cafe, golden hour, cinematic lighting',
            'preview_inbox_id': 'inbox_a',
          },
        ],
      });
      expect(addRes.isError, isFalse);
      final addedChar = entries.firstWhere((e) => e.title == '祈酱常服');
      expect(addedChar.previewImagePath, imgPath);

      // 4. delete_inbox removes inbox item while keeping image referenced by formal entry
      final delRes = await tool.execute('in_4', {
        'action': 'delete_inbox',
        'inbox_id': 'inbox_a',
      });
      expect(delRes.isError, isFalse);
      expect(inboxItems, isEmpty);
      expect(File(imgPath!).existsSync(), isTrue);
    });

    test('批量新增支持 linked_entry_titles 关联同批角色与 character_prompts，且支持 generate_library_preview', () async {
      final tool = PromptLibraryTool(
        getEntries: () => entries,
        addEntry: addEntry,
        updateEntry: updateEntry,
        deleteEntry: deleteEntry,
        getHistory: () => const [],
        loadImageBytes: (_) async => null,
      );

      final addRes = await tool.execute('link_1', {
        'action': 'add',
        'entries': [
          {
            'title': '小祈本体',
            'category': '角色',
            'prompt': '1girl, black hair, golden eyes',
          },
          {
            'title': '小祈白丝针织开衫',
            'category': '服装',
            'prompt': 'white knit cardigan, black dress, white thighhighs',
            'linked_entry_titles': ['小祈本体'],
          },
          {
            'title': '双人咖啡馆构图',
            'category': '构图',
            'prompt': '2girls, cafe table, warm sunlight',
            'character_prompts': [
              {'name': '小祈', 'prompt': 'black hair, smiling'},
            ],
            'linked_entry_titles': ['小祈本体'],
          },
        ],
      });
      expect(addRes.isError, isFalse);

      final charEntry = entries.firstWhere((e) => e.title == '小祈本体');
      final outfitEntry = entries.firstWhere((e) => e.title == '小祈白丝针织开衫');
      final compEntry = entries.firstWhere((e) => e.title == '双人咖啡馆构图');
      expect(outfitEntry.linkedEntryIds, [charEntry.id]);
      expect(compEntry.characterPrompts.length, 1);
      expect(compEntry.characterPrompts.first.name, '小祈');

      // search detail shows one-way link on outfit card without bloating character card
      final outfitDetailRes = await tool.execute('link_2', {
        'action': 'search',
        'id': outfitEntry.id,
      });
      expect(outfitDetailRes.isError, isFalse);
      expect(outfitDetailRes.content, contains('关联条目'));
      expect(outfitDetailRes.content, contains('小祈本体'));

      final charDetailRes = await tool.execute('link_3', {
        'action': 'search',
        'id': charEntry.id,
      });
      expect(charDetailRes.isError, isFalse);
      expect(charDetailRes.content, isNot(contains('小祈白丝针织开衫')));

      // GenerateLibraryPreviewTool clamps dimensions to <= 1MP and triggers callback
      int? receivedW;
      int? receivedH;
      String? receivedEntryId;
      final previewGenTool = GenerateLibraryPreviewTool(
        getEntries: () => entries,
        generatePreview: ({
          required entry,
          required prompt,
          String negativePrompt = '',
          List<PromptInboxCharacter> characterPrompts = const [],
          int width = 832,
          int height = 1216,
        }) async {
          receivedEntryId = entry.id;
          receivedW = width;
          receivedH = height;
          return (ok: true, message: '预览图已重跑');
        },
      );

      final genRes = await previewGenTool.execute('gen_p1', {
        'entry_id': outfitEntry.id,
        'prompt': '1girl, white knit cardigan, white thighhighs',
        'width': 1216,
        'height': 1216, // > 1MP -> clamped safely back to 832x1216
      });
      expect(genRes.isError, isFalse);
      expect(receivedEntryId, outfitEntry.id);
      expect(receivedW! * receivedH!, lessThanOrEqualTo(1048576));
    });

    test('新增工具: excludedCategories 拦截被禁拆分的分类并放行允许分类', () async {
      final tool = PromptLibraryTool(
        getEntries: () => entries,
        addEntry: addEntry,
        updateEntry: updateEntry,
        deleteEntry: deleteEntry,
        excludedCategories: const {'构图', '环境'},
        getHistory: () => const [],
        loadImageBytes: (_) async => null,
      );

      // Single add of forbidden category is rejected
      final blockedSingle = await tool.execute('ex_1', {
        'action': 'add',
        'title': '仰拍构图',
        'category': '构图',
        'prompt': 'low angle, dutch angle',
      });
      expect(blockedSingle.isError, isTrue);
      expect(blockedSingle.content, contains('已禁用后台整理拆分'));
      expect(entries.any((e) => e.title == '仰拍构图'), isFalse);

      // Batch containing a forbidden category rejects the entire batch atomically
      final blockedBatch = await tool.execute('ex_2', {
        'action': 'add',
        'entries': [
          {
            'title': '允许的新服装',
            'category': '服装',
            'prompt': 'school uniform, white thighhighs',
          },
          {
            'title': '被禁的新环境',
            'category': '环境',
            'prompt': 'classroom, sunset',
          },
        ],
      });
      expect(blockedBatch.isError, isTrue);
      expect(blockedBatch.content, contains('环境'));
      expect(entries.any((e) => e.title == '允许的新服装'), isFalse);

      // Allowed category succeeds normally
      final allowedRes = await tool.execute('ex_3', {
        'action': 'add',
        'title': '允许的新服装',
        'category': '服装',
        'prompt': 'school uniform, white thighhighs',
      });
      expect(allowedRes.isError, isFalse);
      expect(entries.any((e) => e.title == '允许的新服装'), isTrue);
    });
  });
}
