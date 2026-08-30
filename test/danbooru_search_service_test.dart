import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/models/danbooru_search_models.dart';
import 'package:novelai_harness/data/models/tag_models.dart';
import 'package:novelai_harness/data/services/danbooru_search_service.dart';

/// DanbooruSearch HF Space API 真实返回结构样例 (节选自实测响应)
const searchResponse = {
  'tags_all': 'white_serafuku, white_sailor_collar',
  'tags_sfw': 'white_serafuku, white_sailor_collar',
  'results': [
    {
      'tag': 'white_serafuku',
      'cn_name': '白色水手服,水手服,制服,校服',
      'category': 'General',
      'nsfw': '0',
      'final_score': 0.9282,
      'semantic_score': 1.0,
      'count': 3948,
      'source': '白色水手服',
      'layer': '中文核心词',
      'wiki': '上衣和裙子均为白色的水手服，不包括领巾和领子。',
      'artist_top_tags': [],
    },
    {
      'tag': 'ayanami_rei_(evangelion)',
      'cn_name': '绫波丽,新世纪福音战士,角色',
      'category': 'Character',
      'nsfw': '0',
      'final_score': 0.8,
      'semantic_score': 0.9,
      'count': 88000,
      'source': '蓝色短发角色',
      'layer': '中文核心词',
      'wiki': '',
      'artist_top_tags': [],
    },
  ],
  'keywords': ['白色水手服'],
};

const relatedResponse = {
  'results': [
    {
      'tag': 'maid_headdress',
      'cn_name': '女仆发带,头饰,女仆装,发饰',
      'category': 'General',
      'sources': ['maid'],
      'wiki': '通常与女仆制服搭配的褶边发带',
    },
    {
      'tag': 'maid_apron',
      'cn_name': '女仆围裙,围裙,女仆装',
      'category': 'General',
      'sources': ['maid'],
      'wiki': '女仆穿戴的围裙',
    },
  ],
};

const artistsResponse = {
  'results': [
    {
      'artist': 'iwonu',
      'cooc_count': 288,
      'post_count': 193,
      'sources': ['maid', 'twintails'],
      'top_tags': ['frilled_wrist_cuffs (碎边护腕)', 'maid_headdress (女仆发带)'],
    },
    {
      'artist': 'rino_cnc',
      'cooc_count': 749,
      'post_count': 1333,
      'sources': ['maid'],
      'top_tags': ['low_twintails (低双马尾)'],
    },
  ],
};

DanbooruSearchService _service(Map<String, String> routes) {
  return DanbooruSearchService.forTesting(
    baseUrl: 'http://test/api',
    client: MockClient((request) async {
      final body = routes['${request.method} ${request.url.path}'];
      if (body == null) {
        return http.Response.bytes(utf8.encode('not found'), 404);
      }
      return http.Response.bytes(utf8.encode(body), 200);
    }),
  );
}

void main() {
  group('danbooruCnHead', () {
    test('逗号多段取首段', () {
      expect(danbooruCnHead('白色水手服,水手服,制服,校服'), '白色水手服');
      expect(danbooruCnHead('女仆发带，头饰'), '女仆发带');
    });

    test('首段不含汉字视为未译出', () {
      expect(danbooruCnHead('serafuku,水手服'), isNull);
      expect(danbooruCnHead(''), isNull);
    });
  });

  group('DanbooruSearchService.searchTags', () {
    test('解析搜索结果并缓存', () async {
      var calls = 0;
      final svc = DanbooruSearchService.forTesting(
        baseUrl: 'http://test/api',
        client: MockClient((request) async {
          calls++;
          return http.Response.bytes(
            utf8.encode(jsonEncode(searchResponse)),
            200,
          );
        }),
      );

      final r1 = await svc.searchTags('白色水手服', limit: 20);
      expect(calls, 1);
      expect(r1.length, 2);
      expect(r1.first.tag, 'white_serafuku');
      expect(r1.first.cnHead, '白色水手服');
      expect(r1.first.category, DanbooruTagCategory.general);
      expect(r1.first.count, 3948);
      expect(r1.first.wiki, contains('水手服'));
      expect(r1[1].category, DanbooruTagCategory.character);

      // 第二次同参查询命中缓存，不再发请求
      final r2 = await svc.searchTags('白色水手服', limit: 20);
      expect(calls, 1);
      expect(r2.length, 2);
    });

    test('空查询直接返回空列表', () async {
      final svc = _service({});
      expect(await svc.searchTags('  '), isEmpty);
    });

    test('服务端 error 返回抛异常', () async {
      final svc = DanbooruSearchService.forTesting(
        baseUrl: 'http://test/api',
        client: MockClient(
          (request) async => http.Response(
            jsonEncode({
              'error': '所有传入的标签均不存在于标签表中',
              'invalid_tags': ['xxx'],
            }),
            200,
          ),
        ),
      );
      expect(
        () => svc.relatedTags(['xxx']),
        throwsA(isA<DanbooruSearchException>()),
      );
    });
  });

  group('DanbooruSearchService.relatedTags', () {
    test('解析关联推荐与纠错映射', () async {
      final svc = _service({
        'POST /api/related': jsonEncode({
          ...relatedResponse,
          'corrections': {'twintail': 'twintails'},
          'correction_note': '标签拼写错误，已经纠错: twintail -> twintails',
        }),
      });

      final corrections = <String, String>{};
      final results = await svc.relatedTags([
        'maid',
        'Twintail',
      ], corrections: corrections);

      expect(results.length, 2);
      expect(results.first.tag, 'maid_headdress');
      expect(results.first.cnHead, '女仆发带');
      expect(results.first.sources, ['maid']);
      expect(corrections['twintail'], 'twintails');
    });

    test('标签规范化：空格转下划线、小写、去空项', () async {
      var captured = <String, dynamic>{};
      final svc = DanbooruSearchService.forTesting(
        baseUrl: 'http://test/api',
        client: MockClient((request) async {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(jsonEncode(relatedResponse)),
            200,
          );
        }),
      );

      await svc.relatedTags([' Maid Dress ', '', '  ']);
      expect(captured['tags'], ['maid_dress']);
    });

    test('类别过滤参数映射', () async {
      var captured = <String, dynamic>{};
      final svc = DanbooruSearchService.forTesting(
        baseUrl: 'http://test/api',
        client: MockClient((request) async {
          captured = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response.bytes(
            utf8.encode(jsonEncode(relatedResponse)),
            200,
          );
        }),
      );

      await svc.relatedTags(
        ['genshin_impact'],
        categories: [DanbooruTagCategory.character],
      );
      expect(captured['target_categories'], ['Character']);
    });
  });

  group('DanbooruSearchService.recommendArtists', () {
    test('解析画师推荐', () async {
      final svc = _service({'POST /api/artists': jsonEncode(artistsResponse)});

      final results = await svc.recommendArtists(['maid', 'twintails']);
      expect(results.length, 2);
      expect(results.first.artist, 'iwonu');
      expect(results.first.coocCount, 288);
      expect(results.first.postCount, 193);
      expect(results.first.sources, ['maid', 'twintails']);
      expect(results.first.topTags.first, contains('碎边护腕'));
    });

    test('空标签列表返回空', () async {
      final svc = _service({});
      expect(await svc.recommendArtists(['', ' ']), isEmpty);
    });
  });

  group('DanbooruSearchService 错误处理', () {
    test('HTTP 非 200 抛异常并携带状态码', () async {
      final svc = DanbooruSearchService.forTesting(
        baseUrl: 'http://test/api',
        client: MockClient((request) async => http.Response('busy', 429)),
      );
      try {
        await svc.searchTags('test');
        fail('should throw');
      } on DanbooruSearchException catch (e) {
        expect(e.statusCode, 429);
        expect(e.message, contains('429'));
      }
    });

    test('网络异常包装为 DanbooruSearchException', () async {
      final svc = DanbooruSearchService.forTesting(
        baseUrl: 'http://test/api',
        client: MockClient(
          (request) async => throw Exception('connection refused'),
        ),
      );
      await expectLater(
        svc.searchTags('test'),
        throwsA(isA<DanbooruSearchException>()),
      );
    });
  });

  group('DanbooruSearchResult.toTagSuggestion', () {
    test('转换为补全建议：中文名优先、wiki 兜底、高分排序', () {
      const withZh = DanbooruSearchResult(
        tag: 'white_serafuku',
        cnName: '白色水手服,水手服',
        count: 3948,
        score: 0.9,
      );
      const noZh = DanbooruSearchResult(
        tag: 'skindentation',
        cnName: '',
        wiki: '紧身衣勒入皮肤产生的凹陷',
        score: 0.5,
      );

      final s1 = withZh.toTagSuggestion();
      expect(s1.tag, 'white serafuku');
      expect(s1.translation, '白色水手服');
      expect(s1.postCount, 3948);
      expect(s1.score, greaterThan(1500));

      final s2 = noZh.toTagSuggestion();
      expect(s2.translation, '紧身衣勒入皮肤产生的凹陷');
      expect(s1.score, greaterThan(s2.score));
    });
  });

  group('DanbooruSearchService.baseUrl', () {
    test('尾斜杠被规范化', () {
      final svc = DanbooruSearchService.forTesting();
      svc.baseUrl = 'https://example.com/api//';
      expect(svc.baseUrl, 'https://example.com/api');
      // 空串不覆盖
      svc.baseUrl = '  ';
      expect(svc.baseUrl, 'https://example.com/api');
    });
  });
}
