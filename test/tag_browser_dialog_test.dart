import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/features/studio/widgets/tag_browser_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Widget buildTestApp({
    required ValueChanged<String> onTagSelected,
    Locale locale = const Locale('zh'),
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: TagBrowserDialog(onTagSelected: onTagSelected)),
    );
  }

  group('TagBrowserDialog UI & i18n Tests', () {
    testWidgets('Renders Chinese strings when locale is zh', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? selectedTag;
      await tester.pumpWidget(
        buildTestApp(
          onTagSelected: (tag) => selectedTag = tag,
          locale: const Locale('zh'),
        ),
      );
      await tester.pumpAndSettle();

      // 对话框标题与搜索框提示
      expect(find.text('Danbooru 标签灵感库'), findsOneWidget);
      expect(find.text('输入英文或中文搜索 14万+ Danbooru 标签...'), findsOneWidget);

      // 搜索无结果空态展示
      await tester.enterText(
        find.byType(TextField),
        'nonexistent_query_xyz_12345',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('未找到匹配标签'), findsOneWidget);
      expect(find.text('请尝试输入其他英文或中文关键词检索'), findsOneWidget);

      // 清空搜索返回预设浏览
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // 点击标签触发选择并显示 SnackBar
      final tagChip = find.text('masterpiece');
      expect(tagChip, findsOneWidget);
      await tester.tap(tagChip);
      await tester.pump();

      expect(selectedTag, 'masterpiece');
      expect(find.textContaining('已添加标签: masterpiece'), findsOneWidget);
    });

    testWidgets('Renders English strings when locale is en', (tester) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      String? selectedTag;
      await tester.pumpWidget(
        buildTestApp(
          onTagSelected: (tag) => selectedTag = tag,
          locale: const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      // 对话框标题与搜索框提示
      expect(find.text('Danbooru Tag Inspiration Library'), findsOneWidget);
      expect(
        find.text('Search 140k+ Danbooru tags in English or Chinese...'),
        findsOneWidget,
      );

      // 搜索无结果空态展示
      await tester.enterText(
        find.byType(TextField),
        'nonexistent_query_xyz_12345',
      );
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      expect(find.text('No matching tags found'), findsOneWidget);
      expect(
        find.text('Try searching with different English or Chinese keywords'),
        findsOneWidget,
      );

      // 清空搜索返回预设浏览
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();

      // 点击标签触发选择并显示 SnackBar
      final tagChip = find.text('masterpiece');
      expect(tagChip, findsOneWidget);
      await tester.tap(tagChip);
      await tester.pump();

      expect(selectedTag, 'masterpiece');
      expect(find.textContaining('Added tag: masterpiece'), findsOneWidget);
    });
  });
}
