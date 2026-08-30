import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/tag_dictionary_update_service.dart';

void main() {
  group('buildTagTsv 纯函数构建', () {
    test('按热度降序输出五列 TSV 并挂载别名', () {
      const rows = [
        TagRow('1girl', 0, '单人女性', 8348948),
        TagRow('highres', 5, '高分辨率', 8077196),
        TagRow('hatsune_miku', 4, '初音未来', 144505),
      ];
      final tsv = buildTagTsv(rows, {
        '1girl': ['1girls'],
        'hatsune_miku': ['miku_hatsune', 'hatsune_miku'],
      });

      final lines = tsv.split('\n')..removeLast();
      expect(lines.length, 3);
      // 热度降序
      expect(lines[0].startsWith('1girl\t8348948\t单人女性'), isTrue);
      expect(lines[1].startsWith('highres\t8077196'), isTrue);
      expect(lines[2].startsWith('hatsune_miku\t144505'), isTrue);
      // 第 5 列官方分类
      expect(lines[0].split('\t')[4], '0');
      expect(lines[1].split('\t')[4], '5');
      expect(lines[2].split('\t')[4], '4');
      // 别名列: 排序去重且剔除与标签同名项
      expect(lines[0].split('\t')[3], '1girls');
      expect(lines[2].split('\t')[3], 'miku_hatsune');
    });

    test('中文释义中的制表符与换行被清洗', () {
      const rows = [TagRow('bad\ttag\nname', 0, '怪\t东西\n喂', 100)];
      // 标签名含非法字符直接跳过
      expect(buildTagTsv(rows, {}).isEmpty, isTrue);

      const rows2 = [TagRow('ok_tag', 0, '怪\t东西\n喂', 100)];
      final line = buildTagTsv(rows2, {}).split('\n').first;
      expect(line, 'ok_tag\t100\t怪 东西 喂\t\t0');
    });

    test('别名超过 10 个时截断', () {
      const rows = [TagRow('tag_a', 0, '甲', 500)];
      final aliases = {
        'tag_a': [for (var i = 1; i <= 15; i++) 'alias_$i'],
      };
      final fields = buildTagTsv(rows, aliases).split('\n').first.split('\t');
      expect(fields[3].split(',').length, 10);
    });
  });

  group('parseAliasCache 别名缓存解析', () {
    test('解析 antecedent/consequent 对并过滤自指与空行', () {
      const raw =
          '1girls\t1girl\nmiku_hatsune\thatsune_miku\nbad_line\n'
          'self\tself\n\n';
      final map = parseAliasCache(raw);
      expect(map['1girl'], ['1girls']);
      expect(map['hatsune_miku'], ['miku_hatsune']);
      expect(map.containsKey('self'), isFalse);
      expect(map.length, 2);
    });
  });

  group('updateNow 单飞锁 (并发去重)', () {
    test('在途更新期间并发调用复用同一 Future，完成后重新开闸', () async {
      const fallback = TagDictUpdateResult(success: false, message: '');
      final f1 = TagDictionaryUpdateService.instance.updateNow();
      final f2 = TagDictionaryUpdateService.instance.updateNow();
      // 并发调用拿到的是同一个在途 Future，不会并发争抢临时文件
      expect(identical(f1, f2), isTrue);
      // 测试环境无 path_provider 插件，_performUpdate 会在取目录时抛错，吞掉
      await f1.then((v) => v, onError: (_) => fallback);
      await f2.then((v) => v, onError: (_) => fallback);
      // 在途锁已释放：新调用会开启新一轮
      final f3 = TagDictionaryUpdateService.instance.updateNow();
      expect(identical(f3, f1), isFalse);
      await f3.then((v) => v, onError: (_) => fallback);
    });
  });

  group('TagDictMeta JSON 往返', () {
    test('序列化与反序列化保持字段一致', () {
      final now = DateTime.parse('2026-08-30T12:00:00');
      final meta = TagDictMeta(
        entryCount: 324491,
        etag: '"abc123"',
        installedAt: now,
        lastCheckAt: now,
      );
      final restored = TagDictMeta.fromJson(meta.toJson());
      expect(restored, isNotNull);
      expect(restored!.entryCount, 324491);
      expect(restored.etag, '"abc123"');
      expect(restored.installedAt, now);
      expect(restored.lastCheckAt, now);
    });

    test('缺失必填字段返回 null', () {
      expect(TagDictMeta.fromJson({'entryCount': 1}), isNull);
      expect(TagDictMeta.fromJson({}), isNull);
    });

    test('旧版弱校验前缀 W/ 的 etag 被规范化', () {
      final meta = TagDictMeta.fromJson({
        'entryCount': 1,
        'etag': 'W/"abc"',
        'installedAt': '2026-08-30T12:00:00',
      });
      expect(meta!.etag, '"abc"');
    });
  });
}
