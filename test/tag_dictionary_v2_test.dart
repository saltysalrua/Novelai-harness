import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/tag_models.dart';
import 'package:novelai_harness/data/services/tag_dictionary_service.dart';

/// 新版 5 列词库格式测试：第 5 列为官方 Danbooru 分类 ID (0/1/3/4/5)，
/// 缺失时回退旧版 4 列启发式推断。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TagDictionaryService v2 五列词库格式', () {
    const sampleTsv = '''
hatsune_miku\t144505\t初音未来\tmiku_hatsune\t4
as109\t1535\tAS109\t\t1
touhou\t1091543\t东方Project\t\t3
highres\t8077196\t高分辨率\thires\t5
blue_eyes\t1762765\t蓝眼\tblueeyes\t0
weird_tag_name\t500\t怪东西\t\t
''';

    setUp(() async {
      await TagDictionaryService.instance.ensureLoaded(
        rawTsvContent: sampleTsv,
      );
    });

    test('第 5 列官方分类优先于启发式推断', () {
      // 无括号后缀但官方标记为角色 (4)
      expect(
        TagDictionaryService.instance.categoryOf('hatsune miku'),
        DanbooruTagCategory.character,
      );
      // 无 artist: 前缀但官方标记为画师 (1)
      expect(
        TagDictionaryService.instance.categoryOf('as109'),
        DanbooruTagCategory.artist,
      );
      // 官方版权分类 (3)
      expect(
        TagDictionaryService.instance.categoryOf('touhou'),
        DanbooruTagCategory.copyright,
      );
      // 官方元数据分类 (5)
      expect(
        TagDictionaryService.instance.categoryOf('highres'),
        DanbooruTagCategory.meta,
      );
      // 官方通用分类 (0)
      expect(
        TagDictionaryService.instance.categoryOf('blue eyes'),
        DanbooruTagCategory.general,
      );
      // 旧版 4 列行回退启发式 (通用)
      expect(
        TagDictionaryService.instance.categoryOf('weird tag name'),
        DanbooruTagCategory.general,
      );
    });

    test('官方别名列参与联想搜索', () async {
      final results = await TagDictionaryService.instance.search(
        'miku_hatsune',
        limit: 3,
      );
      expect(results.isNotEmpty, isTrue);
      expect(results.first.tag, 'hatsune miku');
      expect(results.first.category, DanbooruTagCategory.character);
    });

    test('搜索结果携带官方分类胶囊', () async {
      final results = await TagDictionaryService.instance.search(
        'touhou',
        limit: 3,
      );
      expect(results.isNotEmpty, isTrue);
      expect(results.first.category, DanbooruTagCategory.copyright);
    });
  });
}
