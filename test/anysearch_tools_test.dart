import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/tools/anysearch_tools.dart';
import 'package:novelai_harness/data/services/anysearch_service.dart';

/// 构造 Mock 服务: routes 键为 "METHOD /path" (可含 query)，值为响应 JSON
AnySearchService _svc(
  Map<String, String> routes, {
  void Function(http.Request)? onRequest,
}) {
  return AnySearchService.forTesting(
    baseUrl: 'http://test',
    client: MockClient((request) async {
      onRequest?.call(request);
      final key =
          '${request.method} ${request.url.path}'
          '${request.url.query.isEmpty ? '' : '?${request.url.query}'}';
      final body = routes[key];
      return http.Response.bytes(
        utf8.encode(body ?? jsonEncode({'code': -1, 'message': 'not found'})),
        body == null ? 404 : 200,
      );
    }),
  );
}

Map<String, dynamic> _ok([Map<String, dynamic>? data]) => {
  'code': 0,
  'message': 'success',
  'data': data ?? {},
};

void main() {
  group('WebSearchTool', () {
    test('单查询: 渲染标题/URL/摘要', () async {
      final tool = WebSearchTool(
        service: _svc({
          'POST /v1/search': jsonEncode(
            _ok({
              'results': [
                {
                  'title': 'NovelAI V5 发布公告',
                  'url': 'https://example.com/v5',
                  'content': 'V5 模型上线，支持散文提示词。',
                },
              ],
              'metadata': {'total_results': 1, 'search_time_ms': 120},
            }),
          ),
        }),
      );
      final r = await tool.execute('t1', {'query': 'novelai v5 发布'});
      expect(r.isError, isFalse);
      expect(r.content, contains('NovelAI V5 发布公告'));
      expect(r.content, contains('https://example.com/v5'));
      expect(r.content, contains('V5 模型上线'));
      expect(r.content, contains('120ms'));
    });

    test('空查询返回错误', () async {
      final tool = WebSearchTool(service: _svc({}));
      final r = await tool.execute('t1', {'query': '   '});
      expect(r.isError, isTrue);
      expect(r.content, contains('至少提供一个非空查询词'));
    });

    test('批量查询: 并行下发多条并按查询分组渲染', () async {
      final bodies = <String>[];
      final tool = WebSearchTool(
        service: _svc(
          {
            'POST /v1/search': jsonEncode(
              _ok({
                'results': [
                  {'title': '结果A', 'url': 'https://a.com', 'content': 'a'},
                ],
              }),
            ),
          },
          onRequest: (r) => bodies.add(
            (jsonDecode(r.body) as Map<String, dynamic>)['query'] as String,
          ),
        ),
      );
      final r = await tool.execute('t1', {
        'queries': ['苹果股价', '特斯拉股价'],
      });
      expect(r.isError, isFalse);
      expect(bodies, containsAll(['苹果股价', '特斯拉股价']));
      expect(r.content, contains('查询「苹果股价」'));
      expect(r.content, contains('查询「特斯拉股价」'));
    });

    test('垂直搜索: sub_domain 与 params 透传到请求体', () async {
      final bodies = <Map<String, dynamic>>[];
      final tool = WebSearchTool(
        service: _svc(
          {'POST /v1/search': jsonEncode(_ok({}))},
          onRequest: (r) =>
              bodies.add(jsonDecode(r.body) as Map<String, dynamic>),
        ),
        apiKeyGetter: () => 'as_sk_test',
      );
      final r = await tool.execute('t1', {
        'query': 'AAPL',
        'sub_domain': 'finance.quote',
        'params': {'type': 'stock', 'symbol': 'AAPL', 'cn_code': ''},
      });
      expect(r.isError, isFalse);
      expect(bodies.single['tag'], 'finance.quote');
      expect(bodies.single['params'], {
        'type': 'stock',
        'symbol': 'AAPL',
        'cn_code': '',
      });
    });

    test('apiKeyGetter 注入的密钥进入 Bearer 头', () async {
      final auths = <String?>[];
      final tool = WebSearchTool(
        service: _svc({
          'POST /v1/search': jsonEncode(_ok({})),
        }, onRequest: (r) => auths.add(r.headers['Authorization'])),
        apiKeyGetter: () => 'as_sk_cfg',
      );
      await tool.execute('t1', {'query': 'q'});
      expect(auths.single, 'Bearer as_sk_cfg');
    });

    test('服务端错误: isError 并带配置密钥提示', () async {
      final tool = WebSearchTool(
        service: _svc({
          'POST /v1/search': jsonEncode({
            'code': -1,
            'message': 'Quota exceeded.',
            'request_id': 'req_9',
          }),
        }),
      );
      final r = await tool.execute('t1', {'query': 'q'});
      expect(r.isError, isTrue);
      expect(r.content, contains('Quota exceeded'));
      expect(r.content, contains('req_9'));
      expect(r.content, contains('AnySearch API Key'));
    });

    test('配额耗尽自动签发新 Key: 提示用户去设置页配置', () async {
      final tool = WebSearchTool(
        service: _svc({
          'POST /v1/search': jsonEncode({
            'code': -1,
            'message': 'Quota exceeded.',
            'auto_registered': {'api_key': 'as_sk_new'},
          }),
        }),
      );
      final r = await tool.execute('t1', {'query': 'q'});
      expect(r.isError, isTrue);
      expect(r.content, contains('as_sk_new'));
      expect(r.content, contains('设置'));
    });
  });

  group('WebGetDomainsTool', () {
    test('渲染子域目录与必填标记', () async {
      final tool = WebGetDomainsTool(
        service: _svc({
          'GET /v1/sub-domains?domain=finance': jsonEncode(
            _ok({
              'domains': [
                {
                  'domain': 'finance',
                  'sub_domains': [
                    {
                      'sub_domain': 'finance.quote',
                      'description': '股票/基金实时行情',
                      'params': {
                        'symbol': {
                          'description': '股票代码',
                          'required': true,
                          'sort_order': 1,
                        },
                      },
                    },
                  ],
                },
              ],
            }),
          ),
        }),
      );
      final r = await tool.execute('t1', {
        'domains': ['finance'],
      });
      expect(r.isError, isFalse);
      expect(r.content, contains('finance.quote'));
      expect(r.content, contains('股票/基金实时行情'));
      expect(r.content, contains('symbol` (必填)'));
    });

    test('未知领域直接拦截不发请求', () async {
      var called = 0;
      final tool = WebGetDomainsTool(
        service: _svc({}, onRequest: (_) => called++),
      );
      final r = await tool.execute('t1', {
        'domains': ['crypto'],
      });
      expect(r.isError, isTrue);
      expect(r.content, contains('未知领域'));
      expect(called, 0);
    });

    test('domains 缺失返回错误', () async {
      final tool = WebGetDomainsTool(service: _svc({}));
      final r = await tool.execute('t1', {});
      expect(r.isError, isTrue);
      expect(r.content, contains('不能为空'));
    });
  });

  group('WebExtractTool', () {
    test('输出不可信警示 + 标题 + 正文', () async {
      final tool = WebExtractTool(
        service: _svc({
          'POST /v1/extract': jsonEncode(
            _ok({
              'title': 'Flutter 官方文档',
              'url': 'https://docs.flutter.dev/',
              'content': '# Flutter\n跨平台 UI 框架',
            }),
          ),
        }),
      );
      final r = await tool.execute('t1', {'url': 'https://docs.flutter.dev/'});
      expect(r.isError, isFalse);
      expect(r.content, contains('不可信'));
      expect(r.content, contains('Flutter 官方文档'));
      expect(r.content, contains('跨平台 UI 框架'));
    });

    test('超长正文截断', () async {
      final long = 'A' * 20000;
      final tool = WebExtractTool(
        service: _svc({
          'POST /v1/extract': jsonEncode(
            _ok({
              'title': '长文',
              'url': 'https://example.com/long',
              'content': long,
            }),
          ),
        }),
      );
      final r = await tool.execute('t1', {'url': 'https://example.com/long'});
      expect(r.isError, isFalse);
      expect(r.content, contains('已截断'));
      expect(r.content.length, lessThan(14000));
    });

    test('非法 URL 前缀拦截', () async {
      final tool = WebExtractTool(service: _svc({}));
      final r = await tool.execute('t1', {'url': 'ftp://example.com'});
      expect(r.isError, isTrue);
      expect(r.content, contains('http'));
    });

    test('urls 数组批量提取: 共享正文预算且逐页渲染', () async {
      final requested = <String>[];
      final tool = WebExtractTool(
        service: _svc({
          'POST /v1/extract': jsonEncode(
            _ok({
              'title': '长文',
              'url': 'https://example.com/long',
              'content': 'B' * 20000,
            }),
          ),
        }, onRequest: (r) => requested.add(r.body)),
      );

      final r = await tool.execute('t1', {
        'urls': ['https://example.com/a', 'https://example.com/b'],
      });

      expect(r.isError, isFalse);
      expect(requested, hasLength(2));
      // 两条 URL 均分 12000 字符预算，各截断一次
      expect('已截断'.allMatches(r.content).length, 2);
      expect(r.content.length, lessThan(14000));
    });

    test('urls 超过 5 条时拦截', () async {
      final tool = WebExtractTool(service: _svc({}));
      final r = await tool.execute('t1', {
        'urls': [for (var i = 0; i < 6; i++) 'https://example.com/$i'],
      });
      expect(r.isError, isTrue);
      expect(r.content, contains('最多提取 5 个 URL'));
    });
  });
}
