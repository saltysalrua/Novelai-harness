import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/data/services/danbooru_search_service.dart';
import 'package:novelai_harness/data/services/tag_dictionary_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/tag_autocomplete_overlay.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sampleTsv = '''
blue_eyes\t1762765\t蓝眼\tblueeyes,light_blue_eyes
''';

  DanbooruSearchService mockService(Map<String, dynamic> searchResponse) {
    return DanbooruSearchService.forTesting(
      baseUrl: 'http://test/api',
      client: MockClient((request) async {
        return http.Response.bytes(
          utf8.encode(jsonEncode(searchResponse)),
          200,
        );
      }),
    );
  }

  Future<void> pumpAnchor(
    WidgetTester tester, {
    required TextEditingController controller,
    required FocusNode focusNode,
    required DanbooruSearchService service,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(20),
            child: TagAutocompleteAnchor(
              controller: controller,
              focusNode: focusNode,
              searchService: service,
              child: TextField(controller: controller, focusNode: focusNode),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.byType(TextField));
    await tester.pump();
  }

  setUp(() async {
    // FakeAsync 环境无法处理真实 Isolate 回投，检索退回主线程同步扫描
    TagDictionaryService.backgroundSearchEnabled = false;
    await TagDictionaryService.instance.ensureLoaded(rawTsvContent: sampleTsv);
  });

  testWidgets('失焦取消在线防抖，快速切页不继续发起旧查询', (tester) async {
    var requests = 0;
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final service = DanbooruSearchService.forTesting(
      client: MockClient((request) async {
        requests++;
        return http.Response('{"results":[]}', 200);
      }),
    );
    await pumpAnchor(
      tester,
      controller: controller,
      focusNode: focusNode,
      service: service,
    );
    await tester.enterText(find.byType(TextField), '白色水手服');
    await tester.pump(const Duration(milliseconds: 100));
    focusNode.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(requests, 0);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('清空后重输同词，旧请求结果不能抢先弹出', (tester) async {
    final responses = <Completer<http.Response>>[];
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final service = DanbooruSearchService.forTesting(
      client: MockClient((request) {
        final response = Completer<http.Response>();
        responses.add(response);
        return response.future;
      }),
    );
    await pumpAnchor(
      tester,
      controller: controller,
      focusNode: focusNode,
      service: service,
    );
    Future<void> search() async {
      await tester.enterText(find.byType(TextField), '白色水手服');
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 500));
    }

    await search();
    await tester.enterText(find.byType(TextField), '');
    await search();
    expect(responses, hasLength(2));
    http.Response result(String tag) => http.Response(
      jsonEncode({
        'results': [
          {'tag': tag, 'category': 'General'},
        ],
      }),
      200,
    );
    responses.first.complete(result('stale_result'));
    await tester.pumpAndSettle();
    expect(find.textContaining('stale result'), findsNothing);
    responses.last.complete(result('current_result'));
    await tester.pumpAndSettle();
    expect(find.textContaining('current result'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    controller.dispose();
    focusNode.dispose();
  });

  testWidgets('中文查询离线无结果时由在线语义搜索补齐', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final service = mockService({
      'results': [
        {
          'tag': 'white_serafuku',
          'cn_name': '白色水手服,水手服,制服',
          'category': 'General',
          'count': 3948,
          'final_score': 0.92,
          'wiki': '',
        },
      ],
    });

    await pumpAnchor(
      tester,
      controller: controller,
      focusNode: focusNode,
      service: service,
    );

    await tester.enterText(find.byType(TextField), '白色水手服');
    // 100ms 离线防抖 + 400ms 在线慢路径防抖
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // 在线语义结果上屏展示 (空格形态 + 中文名；输入框本身也显示查询词，共两处)
    expect(find.textContaining('white serafuku'), findsOneWidget);
    expect(find.text('白色水手服'), findsNWidgets(2));

    // Enter 确认上屏
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(controller.text, 'white serafuku, ');
  });

  testWidgets('在线结果与离线结果合并去重且在线优先', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final service = mockService({
      'results': [
        {
          'tag': 'blue_eyes',
          'cn_name': '蓝眼,眼睛',
          'category': 'General',
          'count': 1762765,
          'final_score': 0.9,
          'wiki': '',
        },
      ],
    });

    await pumpAnchor(
      tester,
      controller: controller,
      focusNode: focusNode,
      service: service,
    );

    // "蓝" 命中离线 blue_eyes (中文释义前缀)，同时触发在线语义搜索
    await tester.enterText(find.byType(TextField), '蓝');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // 合并后只剩一条 (在线优先，离线同名去重)
    final tiles = find.textContaining('blue eyes');
    expect(tiles, findsOneWidget);
    expect(find.text('蓝眼'), findsOneWidget);
  });

  testWidgets('在线服务不可用时静默降级为纯离线结果', (tester) async {
    final controller = TextEditingController();
    final focusNode = FocusNode();
    final service = DanbooruSearchService.forTesting(
      baseUrl: 'http://test/api',
      client: MockClient((request) async => throw Exception('network down')),
    );

    await pumpAnchor(
      tester,
      controller: controller,
      focusNode: focusNode,
      service: service,
    );

    await tester.enterText(find.byType(TextField), '蓝');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    // 离线结果正常展示，不弹错误
    expect(find.textContaining('blue eyes'), findsOneWidget);
  });
}
