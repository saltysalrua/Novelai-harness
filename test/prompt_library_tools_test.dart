import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/tools/prompt_library_tools.dart';
import 'package:novelai_harness/data/models/prompt_library_models.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';

void main() {
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

  test('搜索工具: 无参数列出全部条目', () async {
    final tool = SearchPromptLibraryTool(getEntries: () => entries);
    final result = await tool.execute('t1', {});
    expect(result.isError, isFalse);
    expect(result.content, contains('共 3 条'));
    expect(result.content, contains('[e1] 水彩风'));
    expect(result.content, contains('负面提示词: lowres'));
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
  });
}
