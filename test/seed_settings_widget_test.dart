import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    viewModel = StudioViewModel();
    await viewModel.init();
  });

  tearDown(() {
    viewModel.dispose();
  });

  Widget buildTestWidget() {
    return MaterialApp(
      theme: AppTheme.darkTheme,
      home: Scaffold(
        body: SizedBox(
          width: 500,
          height: 2400,
          child: ParametersPage(viewModel: viewModel),
        ),
      ),
    );
  }

  group('Seed Mode & Timing Widget Tests', () {
    testWidgets('Seed button opens settings overlay and switches modes', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // 初始状态为 random
      expect(viewModel.params.seedMode, equals(NaiSeedMode.random));
      expect(viewModel.params.seedTiming, equals(NaiSeedTiming.before));

      // 查找并滚动到种子设置按钮
      final seedButton = find.byTooltip('种子设置 (随机 · 生成前)');
      expect(seedButton, findsOneWidget);
      await tester.ensureVisible(seedButton);
      await tester.tap(seedButton);
      await tester.pumpAndSettle();

      // 验证弹出的选择框
      expect(find.text('种子模式'), findsOneWidget);
      expect(find.text('1. Random (随机)'), findsOneWidget);
      expect(find.text('2. Increase (递增)'), findsOneWidget);
      expect(find.text('3. Fixed (固定)'), findsOneWidget);
      expect(find.text('生成控制'), findsOneWidget);
      expect(find.text('生成前'), findsOneWidget);
      expect(find.text('生成后'), findsOneWidget);
      expect(find.text('立即随机种子'), findsOneWidget);

      // 点击切换为 Increase
      await tester.tap(find.text('2. Increase (递增)'));
      await tester.pumpAndSettle();
      expect(viewModel.params.seedMode, equals(NaiSeedMode.increase));

      // 点击切换生成控制为 生成后
      await tester.tap(find.text('生成后'));
      await tester.pumpAndSettle();
      expect(viewModel.params.seedTiming, equals(NaiSeedTiming.after));

      // 点击 立即随机种子
      await tester.tap(find.text('立即随机种子'));
      await tester.pumpAndSettle();
      expect(viewModel.params.seed, isNonNegative);

      // 现在种子非负，应该出现清空重置按钮
      expect(find.text('清空重置为随机 (-1)'), findsOneWidget);
      await tester.tap(find.text('清空重置为随机 (-1)'));
      await tester.pumpAndSettle();
      expect(viewModel.params.seed, equals(-1));

      // 点击外部区域关闭浮层
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.text('种子模式'), findsNothing);
    });

    testWidgets('Seed textfield input syncs with viewModel', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final seedTextField = find.byWidgetPredicate(
        (w) => w is TextField && w.decoration?.hintText == 'Enter a seed',
      );
      expect(seedTextField, findsOneWidget);
      await tester.ensureVisible(seedTextField);

      // 输入种子数字
      await tester.enterText(seedTextField, '123456789');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(viewModel.params.seed, equals(123456789));

      // 清空输入框重置为 -1
      await tester.enterText(seedTextField, '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(viewModel.params.seed, equals(-1));
    });
  });
}
