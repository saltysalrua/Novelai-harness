import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/generate_dock.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final configService = ConfigService();
    await configService.loadConfig();
    final novelAiService = NovelAiService();
    final novelAiRepository = NovelAiRepository(service: novelAiService);
    viewModel = StudioViewModel(
      configService: configService,
      repository: novelAiRepository,
    );
  });

  Widget buildTestWidget(StudioViewModel vm) {
    return MaterialApp(
      home: Scaffold(body: GenerateDock(viewModel: vm)),
    );
  }

  testWidgets('Opus 免费生图时：顶部无 Opus 免费胶囊，按钮为蓝色「生成图片」', (
    WidgetTester tester,
  ) async {
    final opusAccount = NaiAccountInfo.fromJson({
      'subscription': {
        'tier': 3,
        'active': true,
        'expiresAt': 4102444800,
        'usage': {'percent': 99, 'isNegative': false},
        'trainingStepsLeft': {
          'fixedTrainingStepsLeft': 10000,
          'purchasedTrainingSteps': 0,
        },
      },
    });

    viewModel.setAccountInfoForTest(opusAccount);
    // 默认模型为 V5 Full
    expect(viewModel.params.model.isV5, isTrue);
    expect(viewModel.estimatedGenerationCost, equals(0));

    await tester.pumpWidget(buildTestWidget(viewModel));
    await tester.pumpAndSettle();

    // 验证账号等级和点数
    expect(find.text('Opus'), findsOneWidget);
    expect(find.text('10000 Anlas'), findsOneWidget);
    expect(find.text('Opus 免费'), findsNothing);

    // 验证 V5 体力进度条展示，且不显示秒数
    expect(find.text('V5 体力'), findsOneWidget);
    expect(find.text('99%'), findsOneWidget);
    expect(find.textContaining('s)'), findsNothing);

    // 验证生成按钮为蓝色且文本为纯净的「生成图片」
    expect(find.text('生成图片'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    final style = button.style;
    expect(style?.backgroundColor?.resolve({}), equals(AppTheme.notionBlue));
  });

  testWidgets('超出免费区间消耗点数时：按钮变黄并结合显示「生成图片 (X Anlas)」', (
    WidgetTester tester,
  ) async {
    final paperAccount = NaiAccountInfo.fromJson({
      'subscription': {
        'tier': 0,
        'active': true,
        'expiresAt': 4102444800,
        'usage': {'percent': 100},
        'trainingStepsLeft': {
          'fixedTrainingStepsLeft': 500,
          'purchasedTrainingSteps': 0,
        },
      },
    });

    viewModel.setAccountInfoForTest(paperAccount);
    expect(viewModel.estimatedGenerationCost, greaterThan(0));
    final cost = viewModel.estimatedGenerationCost;

    await tester.pumpWidget(buildTestWidget(viewModel));
    await tester.pumpAndSettle();

    expect(find.text('Paper'), findsOneWidget);
    expect(find.text('500 Anlas'), findsOneWidget);
    expect(find.text('Opus 免费'), findsNothing);

    // 验证按钮结合了预计点数且背景为黄色警告色
    expect(find.text('生成图片 ($cost Anlas)'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(
      button.style?.backgroundColor?.resolve({}),
      equals(AppTheme.warning),
    );
  });

  testWidgets('切换为非 V5 模型时：不展示 V5 体力条', (WidgetTester tester) async {
    final opusAccount = NaiAccountInfo.fromJson({
      'subscription': {
        'tier': 3,
        'active': true,
        'expiresAt': 4102444800,
        'usage': {'percent': 80},
        'trainingStepsLeft': {
          'fixedTrainingStepsLeft': 10000,
          'purchasedTrainingSteps': 0,
        },
      },
    });

    viewModel.setAccountInfoForTest(opusAccount);
    viewModel.updateParams(viewModel.params.copyWith(model: NaiModel.v3));
    expect(viewModel.params.model.isV5, isFalse);

    await tester.pumpWidget(buildTestWidget(viewModel));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    // 验证 V5 体力条不渲染
    expect(find.text('V5 体力'), findsNothing);
  });

  testWidgets('修复页签下：主按钮切换为「开始修复」并可执行局部修复', (WidgetTester tester) async {
    // 切到修复页签 (无账号信息也能渲染)
    viewModel.setActiveSidebarTab(StudioSidebarTab.inpaint);

    await tester.pumpWidget(buildTestWidget(viewModel));
    await tester.pumpAndSettle();

    expect(find.textContaining('生成图片'), findsNothing);
    expect(find.text('开始修复'), findsOneWidget);
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(
      button.style?.backgroundColor?.resolve({}),
      equals(AppTheme.notionBlue),
    );
    expect(button.onPressed, isNotNull);

    // 切回参数页签：恢复「生成图片」(无 ListenableBuilder 包裹，重新 pump)
    viewModel.setActiveSidebarTab(StudioSidebarTab.parameters);
    await tester.pumpWidget(buildTestWidget(viewModel));
    await tester.pumpAndSettle();
    expect(find.text('开始修复'), findsNothing);
    expect(find.textContaining('生成图片'), findsOneWidget);
  });
}
