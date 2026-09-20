import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/comfyui_models.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/generate_dock.dart';
import 'package:novelai_harness/ui/features/studio/widgets/parameters_page.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompts_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final configService = ConfigService();
    await configService.loadConfig();
    viewModel = StudioViewModel(
      configService: configService,
      repository: NovelAiRepository(service: NovelAiService()),
    );
    // ComfyUI 模式：地址指向必然拒绝的本机端口，状态探测快速失败，
    // 不依赖任何真实网络服务
    await viewModel.updateConfig(
      viewModel.config.copyWith(
        comfyUiEnabled: true,
        comfyUiBaseUrl: 'http://127.0.0.1:9',
      ),
    );
  });

  Widget buildTestWidget(Widget child) {
    return MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: AppTheme.darkTheme,
      home: Scaffold(body: child),
    );
  }

  test('estimatedGenerationCost 在 ComfyUI 模式下恒为 0', () {
    expect(viewModel.isComfyUiMode, isTrue);
    expect(viewModel.estimatedGenerationCost, 0);
  });

  test('AppConfig ComfyUI 字段 copyWith 往返', () {
    final config = viewModel.config.copyWith(
      comfyUiEnabled: true,
      comfyUiBaseUrl: 'http://192.168.1.20:8188',
      comfyUiPromptNodeId: '10',
      comfyUiResolutionNodeId: '20',
      comfyUiParamsNodeId: '30',
      comfyUiSampler: 'dpmpp_2m',
      comfyUiScheduler: 'karras',
    );
    expect(config.comfyUiEnabled, isTrue);
    expect(config.comfyUiBaseUrl, 'http://192.168.1.20:8188');
    expect(config.comfyUiPromptNodeId, '10');
    expect(config.comfyUiResolutionNodeId, '20');
    expect(config.comfyUiParamsNodeId, '30');
    expect(config.comfyUiSampler, 'dpmpp_2m');
    expect(config.comfyUiScheduler, 'karras');
  });

  test('ComfyUI 配置经 SharedPreferences 持久化往返', () async {
    final configService = ConfigService();
    final config = (await configService.loadConfig()).copyWith(
      comfyUiEnabled: true,
      comfyUiBaseUrl: 'http://192.168.1.50:8188',
      comfyUiPromptNodeId: '1',
      comfyUiResolutionNodeId: '2',
      comfyUiParamsNodeId: '3',
      comfyUiSampler: 'dpmpp_2m',
      comfyUiScheduler: 'exponential',
    );
    await configService.saveConfig(config);

    // 新实例重新加载，验证全部 ComfyUI 字段落盘不丢
    final reloaded = await ConfigService().loadConfig();
    expect(reloaded.comfyUiEnabled, isTrue);
    expect(reloaded.comfyUiBaseUrl, 'http://192.168.1.50:8188');
    expect(reloaded.comfyUiPromptNodeId, '1');
    expect(reloaded.comfyUiResolutionNodeId, '2');
    expect(reloaded.comfyUiParamsNodeId, '3');
    expect(reloaded.comfyUiSampler, 'dpmpp_2m');
    expect(reloaded.comfyUiScheduler, 'exponential');
  });

  test('ComfyUI 采样器/调度器默认为空 (跟随工作流)', () {
    expect(viewModel.comfySampler, isEmpty);
    expect(viewModel.comfyScheduler, isEmpty);
    expect(viewModel.comfyOptionCatalog, isNull);
  });

  testWidgets('参数页 ComfyUI 模式：显示后端切换与连接卡，隐藏模型与采样器', (
    WidgetTester tester,
  ) async {
    // 参数页较长：拉大视口保证 ComfyUI 采样区块构建
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      buildTestWidget(ParametersPage(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    // 后端切换胶囊与 ComfyUI 连接状态卡
    expect(find.text('ComfyUI'), findsAtLeastNWidgets(1));

    // NovelAI 专属区块隐藏：模型选择 / Sampler 下拉 / 高级选项
    expect(find.text('模型'), findsNothing);
    expect(find.text('采样器'), findsNothing);
    // ComfyUI 采样区块：未连接时展示等待提示而非下拉
    expect(find.text('采样器'), findsNothing);
    expect(find.text('调度器'), findsNothing);
    expect(find.textContaining('连接 ComfyUI 后自动获取'), findsOneWidget);
  });

  testWidgets('参数页 ComfyUI 模式：连接后展示采样器与调度器下拉', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    // 直接注入模拟选项清单并选中一个采样器 (绕过网络探测)
    await viewModel.setComfySampler('dpmpp_2m');
    viewModel.setComfyOptionCatalogForTesting(
      const ComfyUiOptionCatalog(
        samplers: ['euler', 'dpmpp_2m'],
        schedulers: ['normal', 'karras'],
      ),
    );

    await tester.pumpWidget(
      buildTestWidget(ParametersPage(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    expect(find.text('采样器'), findsOneWidget);
    expect(find.text('调度器'), findsOneWidget);
    // 下拉收起态只渲染选中项：调度器未选中 → 显示首项「跟随工作流」
    expect(find.text('跟随工作流'), findsOneWidget);
    expect(find.text('dpmpp_2m'), findsAtLeastNWidgets(1));
  });

  testWidgets('参数页 NovelAI 模式：恢复模型选择与 Sampler 两栏', (WidgetTester tester) async {
    // 参数页较长，Sampler 两栏在默认 600 高视口之外：拉大视口保证全部构建
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await viewModel.updateConfig(
      viewModel.config.copyWith(comfyUiEnabled: false),
    );
    await tester.pumpWidget(
      buildTestWidget(ParametersPage(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    expect(find.text('模型'), findsOneWidget);
    expect(find.text('采样器'), findsOneWidget);
    // 连接状态卡不再展示 (后端切换胶囊仍常驻，ComfyUI 仅作为未选中选项出现)
    expect(find.text('http://127.0.0.1:9'), findsNothing);
    expect(find.textContaining('ComfyUI 未连接'), findsNothing);
  });

  testWidgets('提示词页 ComfyUI 模式：隐藏质量词与 UC 预设工具条及 Token 状态条', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(buildTestWidget(PromptsPage(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.textContaining('质量词'), findsNothing);
    expect(find.textContaining('UC 预设'), findsNothing);
    expect(find.textContaining('透明背景'), findsNothing);
  });

  testWidgets('提示词页 NovelAI 模式：恢复质量词与 UC 预设工具条', (WidgetTester tester) async {
    await viewModel.updateConfig(
      viewModel.config.copyWith(comfyUiEnabled: false),
    );
    await tester.pumpWidget(buildTestWidget(PromptsPage(viewModel: viewModel)));
    await tester.pumpAndSettle();

    expect(find.text('质量词: 标准'), findsOneWidget);
    expect(find.text('UC 预设: 强力'), findsNWidgets(2));
  });

  testWidgets('生成坞 ComfyUI 模式：账号栏换成 Bridge 状态行', (WidgetTester tester) async {
    await tester.pumpWidget(
      buildTestWidget(GenerateDock(viewModel: viewModel)),
    );
    await tester.pumpAndSettle();

    // 状态行出现 ComfyUI 字样与服务地址，主按钮仍为「生成图片」
    expect(find.textContaining('ComfyUI'), findsAtLeastNWidgets(1));
    expect(find.text('http://127.0.0.1:9'), findsOneWidget);
    expect(find.text('生成图片'), findsOneWidget);
    // 账号信息与点数相关文案不应出现
    expect(find.textContaining('Anlas'), findsNothing);
  });
}
