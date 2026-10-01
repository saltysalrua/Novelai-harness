import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_session_list_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late StudioViewModel vm;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    directory = Directory.systemTemp.createTempSync('session_batch_');
    vm = StudioViewModel(sessionLogBaseDir: directory.path);
    await vm.init();
    await vm.createNewSession(title: '目标 A');
    await vm.createNewSession(title: '目标 B');
    await vm.createNewSession(title: '保留 C');
  });

  tearDown(() async {
    vm.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('批量删除包含当前会话后切至剩余会话，全部删除后创建空会话', () async {
    final keep = vm.sessions.firstWhere((s) => s.title == '目标 A').id;
    final ids = vm.sessions
        .where((s) => s.id != keep)
        .map((s) => s.id)
        .toList();
    await vm.deleteSessions([...ids, ...ids]);
    expect(vm.currentSessionId, keep);
    expect(vm.sessions.map((s) => s.id), [keep]);
    await vm.deleteSessions([keep]);
    expect(vm.currentSessionId, isNot(keep));
    expect(vm.messages, isEmpty);
  });

  testWidgets('搜索结果全选后确认批量删除，不删除未命中会话', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: ListenableBuilder(
              listenable: vm,
              builder: (_, _) =>
                  AgentSessionListView(viewModel: vm, onBack: () {}),
            ),
          ),
        ),
      ),
    );
    await tester.runAsync(vm.refreshSessions);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '目标');
    await tester.pumpAndSettle();
    await tester.tap(find.text('批量管理'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();
    expect(find.text('已选 2 项'), findsOneWidget);
    await tester.tap(find.byTooltip('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除选中的 2 个会话？此操作无法撤销。'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    // 目录流与 isolate 是真实异步 IO；逐次让出真实事件循环并 pump，
    // 避免在 fakeAsync 内 pumpAndSettle 把等待磁盘的忙碌动画推进到超时。
    for (var attempt = 0; attempt < 100; attempt++) {
      if (!vm.sessions.any((s) => s.title.startsWith('目标')) &&
          find.byType(LinearProgressIndicator).evaluate().isEmpty) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
    expect(vm.sessions.where((s) => s.title.startsWith('目标')), isEmpty);
    expect(vm.sessions.any((s) => s.title == '保留 C'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
