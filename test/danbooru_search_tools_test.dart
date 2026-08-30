import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/tools/danbooru_search_tools.dart';
import 'package:novelai_harness/data/services/danbooru_search_service.dart';

DanbooruSearchService _svc({
  Map<String, String> routes = const {},
  int status = 200,
}) {
  return DanbooruSearchService.forTesting(
    baseUrl: 'http://test/api',
    client: MockClient((request) async {
      final body = routes['${request.method} ${request.url.path}'];
      return http.Response.bytes(
        utf8.encode(body ?? '{}'),
        body == null ? 500 : status,
      );
    }),
  );
}

void main() {
  group('DanbooruSearchTagsTool', () {
    test('解析语义搜词结果', () async {
      final tool = DanbooruSearchTagsTool(
        service: _svc(
          routes: {
            'POST /api/search': jsonEncode({
              'results': [
                {
                  'tag': 'white_serafuku',
                  'cn_name': '白色水手服,水手服,制服',
                  'category': 'General',
                  'count': 3948,
                  'final_score': 0.92,
                  'wiki': '上衣和裙子均为白色的水手服',
                },
              ],
            }),
          },
        ),
      );

      final r = await tool.execute('t1', {'query': '白色水手服'});
      expect(r.isError, isFalse);
      expect(r.content, contains('white_serafuku'));
      expect(r.content, contains('白色水手服'));
      expect(r.content, contains('上衣和裙子'));
    });

    test('空查询返回错误', () async {
      final tool = DanbooruSearchTagsTool(service: _svc());
      final r = await tool.execute('t1', {'query': '  '});
      expect(r.isError, isTrue);
      expect(r.content, contains('不能为空'));
    });

    test('无结果时友好提示', () async {
      final tool = DanbooruSearchTagsTool(
        service: _svc(routes: {'POST /api/search': '{"results": []}'}),
      );
      final r = await tool.execute('t1', {'query': '不存在的概念xyz'});
      expect(r.isError, isFalse);
      expect(r.content, contains('未找到'));
    });

    test('服务异常映射为错误结果', () async {
      final tool = DanbooruSearchTagsTool(
        service: _svc(routes: {'POST /api/search': '{}'}, status: 500),
      );
      final r = await tool.execute('t1', {'query': 'test'});
      expect(r.isError, isTrue);
      expect(r.content, contains('语义搜词失败'));
    });
  });

  group('DanbooruRelatedTagsTool', () {
    test('解析关联推荐与纠错说明', () async {
      final tool = DanbooruRelatedTagsTool(
        service: _svc(
          routes: {
            'POST /api/related': jsonEncode({
              'results': [
                {
                  'tag': 'maid_headdress',
                  'cn_name': '女仆发带,头饰',
                  'category': 'General',
                  'sources': ['maid'],
                  'wiki': '褶边发带',
                },
              ],
              'corrections': {'twintail': 'twintails'},
            }),
          },
        ),
      );

      final r = await tool.execute('t1', {
        'tags': ['maid', 'twintail'],
      });
      expect(r.isError, isFalse);
      expect(r.content, contains('maid headdress'));
      expect(r.content, contains('女仆发带'));
      expect(r.content, contains('twintail -> twintails'));
    });

    test('空标签列表返回错误', () async {
      final tool = DanbooruRelatedTagsTool(service: _svc());
      final r = await tool.execute('t1', {'tags': []});
      expect(r.isError, isTrue);
    });

    test('类别过滤参数透传', () async {
      var captured = <String, dynamic>{};
      final tool = DanbooruRelatedTagsTool(
        service: DanbooruSearchService.forTesting(
          baseUrl: 'http://test/api',
          client: MockClient((request) async {
            captured = jsonDecode(request.body) as Map<String, dynamic>;
            return http.Response.bytes(utf8.encode('{"results": []}'), 200);
          }),
        ),
      );

      final r = await tool.execute('t1', {
        'tags': ['genshin_impact'],
        'category': 'Character',
      });
      expect(r.isError, isFalse);
      expect(captured['target_categories'], ['Character']);
      expect(r.content, contains('未找到'));
    });
  });

  group('DanbooruRecommendArtistsTool', () {
    test('解析画师推荐结果', () async {
      final tool = DanbooruRecommendArtistsTool(
        service: _svc(
          routes: {
            'POST /api/artists': jsonEncode({
              'results': [
                {
                  'artist': 'iwonu',
                  'cooc_count': 288,
                  'post_count': 193,
                  'sources': ['maid', 'twintails'],
                  'top_tags': ['maid_headdress (女仆发带)'],
                },
              ],
            }),
          },
        ),
      );

      final r = await tool.execute('t1', {
        'tags': ['maid', 'twintails'],
        'limit': 5,
      });
      expect(r.isError, isFalse);
      expect(r.content, contains('iwonu'));
      expect(r.content, contains('共现: 288'));
      expect(r.content, contains('常画:'));
    });

    test('空标签列表返回错误', () async {
      final tool = DanbooruRecommendArtistsTool(service: _svc());
      final r = await tool.execute('t1', {'tags': 'not-a-list'});
      expect(r.isError, isTrue);
    });
  });
}
