import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/app_page_stack.dart';

Widget _host({
  required int index,
  required IndexedWidgetBuilder builder,
  bool reduceMotion = false,
  int count = 3,
}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduceMotion),
    child: SizedBox.expand(
      child: AppPageStack(index: index, itemCount: count, itemBuilder: builder),
    ),
  ),
);

void main() {
  testWidgets('首次只构建当前页，父级更新不重建隐藏页，返回读取新参数', (tester) async {
    final builds = <int>[0, 0, 0];
    var revision = 0;
    Widget page(BuildContext context, int index) {
      final currentRevision = revision;
      return Builder(
        builder: (_) {
          builds[index]++;
          return Text('$index:$currentRevision');
        },
      );
    }

    await tester.pumpWidget(_host(index: 0, builder: page));
    expect(builds, [1, 0, 0]);
    await tester.pumpWidget(_host(index: 1, builder: page));
    await tester.pumpAndSettle();
    expect(builds, [1, 1, 0]);
    revision++;
    await tester.pumpWidget(_host(index: 1, builder: page));
    expect(builds, [1, 2, 0]);
    await tester.pumpWidget(_host(index: 0, builder: page));
    await tester.pumpAndSettle();
    expect(builds, [2, 2, 0]);
    expect(find.text('0:1'), findsOneWidget);
  });

  testWidgets('切页保留编辑状态和滚动位置，隐藏页不接收焦点或运行 Ticker', (tester) async {
    final key = GlobalKey<_StatefulPageState>();
    Widget page(BuildContext context, int index) =>
        index == 0 ? _StatefulPage(key: key) : const Text('other');
    await tester.pumpWidget(_host(index: 0, builder: page));
    final state = key.currentState!;
    await tester.enterText(find.byType(TextField), '保留草稿');
    state.scroll.jumpTo(150);
    await tester.pump();
    await tester.pumpWidget(_host(index: 1, builder: page));
    await tester.pumpAndSettle();
    expect(key.currentState, same(state));
    expect(state.focus.canRequestFocus, isFalse);
    expect(TickerMode.valuesOf(state.context).enabled, isFalse);
    await tester.pumpWidget(_host(index: 0, builder: page));
    await tester.pumpAndSettle();
    expect(key.currentState, same(state));
    expect(state.text.text, '保留草稿');
    expect(state.scroll.offset, 150);
    expect(state.focus.canRequestFocus, isTrue);
    expect(TickerMode.valuesOf(state.context).enabled, isTrue);
  });

  testWidgets('动效逐帧只改绘制属性，不重复构建页面，快速切页无残留', (tester) async {
    var builds = 0;
    Widget page(BuildContext context, int index) => Builder(
      builder: (_) {
        builds++;
        return Text('page-$index');
      },
    );
    await tester.pumpWidget(_host(index: 0, builder: page));
    await tester.pumpWidget(_host(index: 1, builder: page));
    final baseline = builds;
    final fade = find.descendant(
      of: find.byType(AppPageStack),
      matching: find.byType(FadeTransition),
    );
    expect(tester.widget<FadeTransition>(fade).opacity.value, lessThan(1));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(builds, baseline);
    await tester.pumpWidget(_host(index: 2, builder: page));
    await tester.pumpWidget(_host(index: 0, builder: page));
    await tester.pumpAndSettle();
    expect(find.text('page-0'), findsOneWidget);
    expect(find.text('page-1'), findsNothing);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('减少动画设置立即完成切换', (tester) async {
    Widget page(BuildContext context, int index) => Text('page-$index');
    await tester.pumpWidget(_host(index: 0, builder: page, reduceMotion: true));
    await tester.pumpWidget(_host(index: 1, builder: page, reduceMotion: true));
    final fade = tester.widget<FadeTransition>(
      find.descendant(
        of: find.byType(AppPageStack),
        matching: find.byType(FadeTransition),
      ),
    );
    expect(fade.opacity.value, 1);
    expect(fade.opacity.isAnimating, isFalse);
    expect(find.text('page-1'), findsOneWidget);
  });

  testWidgets('减少槽位时释放移除页状态', (tester) async {
    final key = GlobalKey<_StatefulPageState>();
    Widget page(BuildContext context, int index) =>
        index == 2 ? _StatefulPage(key: key) : Text('page-$index');
    await tester.pumpWidget(_host(index: 2, builder: page));
    expect(key.currentState, isNotNull);
    await tester.pumpWidget(_host(index: 0, count: 1, builder: page));
    await tester.pumpAndSettle();
    expect(key.currentState, isNull);
    expect(tester.takeException(), isNull);
  });
}

class _StatefulPage extends StatefulWidget {
  const _StatefulPage({super.key});

  @override
  State<_StatefulPage> createState() => _StatefulPageState();
}

class _StatefulPageState extends State<_StatefulPage> {
  final text = TextEditingController();
  final scroll = ScrollController();
  final focus = FocusNode();

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Material(
    child: Column(
      children: [
        TextField(controller: text, focusNode: focus),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: 100,
            itemExtent: 50,
            itemBuilder: (_, index) => Text('$index'),
          ),
        ),
      ],
    ),
  );
}
