import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/prompt_library_tools.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
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

  test('新增工具: 非角色分类自动清空负面提示词', () async {
    final tool = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    );
    final result = await tool.execute('t1', {
      'title': '构图预设',
      'prompt': 'low angle',
      'category': '构图',
      'negative_prompt': 'should be dropped',
    });

    expect(result.isError, isFalse);
    final persisted = await PromptLibraryService.instance.loadEntries();
    final created = persisted.firstWhere((e) => e.title == '构图预设');
    expect(created.negativePrompt, isEmpty);
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

  test('工具 Schema: OpenAI Function Definition 格式正确', () {
    final search = SearchPromptLibraryTool(
      getEntries: () => entries,
    ).toOpenAiFunction();
    expect(search['function']['name'], 'search_prompt_library');

    final add = AddPromptLibraryEntryTool(
      getEntries: () => entries,
      addEntry: addEntry,
    ).toOpenAiFunction();
    expect(add['function']['parameters']['required'], ['title', 'prompt']);

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
}
