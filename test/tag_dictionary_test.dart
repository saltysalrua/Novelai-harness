import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/tag_models.dart';
import 'package:novelai_harness/data/services/tag_dictionary_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TagDictionaryService tests', () {
    const sampleTsv = '''
1girl\t6008644\t1个女孩\t1girls,sole_female
solo\t5000954\t单人\tfemale_solo,solo_female
long_hair\t4350743\t长发\t/lh,longhair
blue_eyes\t1762765\t蓝眼\tblueeyes,light_blue_eyes
shirt\t1816895\t衬衫\tshirt_only,shirts
hatsune_miku_(vocaloid)\t540210\t初音未来\tmiku
artist:wlop\t120500\tWLOP\t
highres\t5256195\t高分辨率\thires
''';

    setUp(() async {
      await TagDictionaryService.instance.ensureLoaded(
        rawTsvContent: sampleTsv,
      );
    });

    test('loads TSV entries and builds lookup maps', () {
      expect(TagDictionaryService.instance.isLoaded, isTrue);
      expect(TagDictionaryService.instance.count, 8);

      expect(TagDictionaryService.instance.translationOf('1girl'), '1个女孩');
      expect(TagDictionaryService.instance.translationOf('long hair'), '长发');
      expect(
        TagDictionaryService.instance.translationOf('hatsune miku (vocaloid)'),
        '初音未来',
      );

      expect(
        TagDictionaryService.instance.categoryOf('hatsune miku (vocaloid)'),
        DanbooruTagCategory.character,
      );
      expect(
        TagDictionaryService.instance.categoryOf('artist:wlop'),
        DanbooruTagCategory.artist,
      );
      expect(
        TagDictionaryService.instance.categoryOf('highres'),
        DanbooruTagCategory.meta,
      );
    });

    test('searches tags by English prefix and popularity ranking', () async {
      final results = await TagDictionaryService.instance.search(
        'lo',
        limit: 5,
      );

      expect(results.isNotEmpty, isTrue);
      expect(results.first.tag, 'long hair');
      expect(results.first.translation, '长发');
      expect(results.first.postCount, 4350743);
    });

    test('searches tags by Chinese translation', () async {
      final results = await TagDictionaryService.instance.search(
        '长发',
        limit: 5,
      );

      expect(results.isNotEmpty, isTrue);
      expect(results.first.tag, 'long hair');
      expect(results.first.translation, '长发');
    });

    test('searches tags by alias', () async {
      final results = await TagDictionaryService.instance.search(
        '/lh',
        limit: 5,
      );

      expect(results.isNotEmpty, isTrue);
      expect(results.first.tag, 'long hair');
      expect(results.first.matchedAlias, '/lh');
    });

    test('formats tag counts correctly', () {
      expect(formatTagCount(6008644), '6.0M');
      expect(formatTagCount(540210), '540K');
      expect(formatTagCount(1520), '1.5K');
      expect(formatTagCount(980), '980');
      expect(formatTagCount(0), '');
    });
  });

  group('后台检索 isolate 与主线程兑底', () {
    // 本组使用真实 isolate 回投 (普通 test 环境真实事件循环可交付)
    const workerTsv =
        'long_hair\t4350743\t长发\t/lh,longhair\n'
        'blue_eyes\t1762765\t蓝眼\tblueeyes,light_blue_eyes\n';

    setUp(() async {
      TagDictionaryService.backgroundSearchEnabled = true;
      await TagDictionaryService.instance.ensureLoaded(
        rawTsvContent: workerTsv,
      );
    });

    test('后台 worker 检索与主线程同步扫描结果一致', () async {
      // 默认开启：查询经后台 worker isolate 扫描后回投
      final viaWorker = await TagDictionaryService.instance.search(
        'lo',
        limit: 5,
      );
      expect(viaWorker, isNotEmpty);
      expect(viaWorker.first.tag, 'long hair');

      // 关闭后台检索：主线程同步兑底，结果一致
      TagDictionaryService.instance.clearQueryCache();
      TagDictionaryService.backgroundSearchEnabled = false;
      final viaMain = await TagDictionaryService.instance.search(
        'lo',
        limit: 5,
      );
      expect(viaMain.first.tag, 'long hair');
      TagDictionaryService.backgroundSearchEnabled = true;
    });

    test('词库热替换后 worker 同步新词条并可检索', () async {
      await TagDictionaryService.instance.replaceWithContent(
        'murasaki_shion\t12000\t紫\tshion\n',
      );
      TagDictionaryService.instance.clearQueryCache();

      // 检索走已热替换的 worker 词条 (中文释义前缀命中)
      final results = await TagDictionaryService.instance.search(
        '紫',
        limit: 5,
      );
      expect(results, isNotEmpty);
      expect(results.first.tag, 'murasaki shion');
      expect(results.first.translation, '紫');
    });
  });
}
