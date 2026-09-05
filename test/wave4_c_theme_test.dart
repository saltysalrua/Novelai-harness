import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/novelai_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_badge.dart';
import 'package:novelai_harness/ui/core/widgets/app_card.dart';
import 'package:novelai_harness/ui/core/widgets/app_progress_bar.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/fixed_affixes_panel.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_editor_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/studio_shared.dart';

void main() {
  group('wave4-C PromptEditorCard 主题与原子组件清洗', () {
    testWidgets('PromptEditorCard 使用 AppCard、AppBadge 与 AppProgressBar', (
      WidgetTester tester,
    ) async {
      final controller = TextEditingController(text: 'masterpiece, 1girl');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: PromptEditorCard(
              controller: controller,
              onChanged: (_) {},
              hintText: 'Enter prompt',
              headerTags: const [GrayTag('PREFIX', '0.7::artist::')],
              footerTags: const [GrayTag('UC', 'lowres, bad quality')],
              tokenEstimate: 45,
              tokenLimit: 225,
            ),
          ),
        ),
      );

      // 验证外壳已清洗为 AppCard
      expect(find.byType(AppCard), findsWidgets);

      // 验证只读标签已清洗为 AppBadge
      final badges = find.byType(AppBadge);
      expect(badges, findsNWidgets(2));
      expect(find.text('PREFIX'), findsOneWidget);
      expect(find.text('UC'), findsOneWidget);

      // 验证进度条已清洗为 AppProgressBar
      expect(find.byType(AppProgressBar), findsOneWidget);
    });

    testWidgets('PromptEditorCard 深色主题自适应', (WidgetTester tester) async {
      final controller = TextEditingController(text: 'solo, blue eyes');
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: PromptEditorCard(
              controller: controller,
              onChanged: (_) {},
              hintText: 'Enter prompt',
              headerTags: const [GrayTag('PREFIX', 'artist_tag')],
              tokenEstimate: 20,
              tokenLimit: 225,
            ),
          ),
        ),
      );

      expect(find.byType(AppCard), findsWidgets);
      expect(find.byType(AppBadge), findsOneWidget);
      expect(find.byType(AppProgressBar), findsOneWidget);
      expect(find.text('+0.1'), findsOneWidget);
    });
  });

  group('wave4-C FixedAffixesCardContent 主题与原子组件清洗', () {
    late StudioViewModel viewModel;

    setUp(() {
      final configService = ConfigService();
      final novelAiService = NovelAiService();
      final repository = NovelAiRepository(service: novelAiService);
      viewModel = StudioViewModel(
        configService: configService,
        repository: repository,
      );
    });

    tearDown(() {
      viewModel.dispose();
    });

    testWidgets('FixedAffixesCardContent 使用 AppCard 与 AppBadge', (
      WidgetTester tester,
    ) async {
      final prefixController = TextEditingController(text: '0.8::artist::');
      final suffixController = TextEditingController(text: 'aesthetic');
      addTearDown(prefixController.dispose);
      addTearDown(suffixController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FixedAffixesCardContent(
                viewModel: viewModel,
                prefixController: prefixController,
                suffixController: suffixController,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppCard), findsOneWidget);
      final badges = find.byType(AppBadge);
      expect(badges, findsNWidgets(2));
      expect(find.text('PREFIX'), findsOneWidget);
      expect(find.text('SUFFIX'), findsOneWidget);
    });

    testWidgets('FixedAffixesCardContent 深浅模式正常渲染', (
      WidgetTester tester,
    ) async {
      final prefixController = TextEditingController();
      final suffixController = TextEditingController();
      addTearDown(prefixController.dispose);
      addTearDown(suffixController.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: FixedAffixesCardContent(
                viewModel: viewModel,
                prefixController: prefixController,
                suffixController: suffixController,
              ),
            ),
          ),
        ),
      );

      expect(find.byType(AppCard), findsOneWidget);
      expect(find.text('PREFIX'), findsOneWidget);
      expect(find.text('SUFFIX'), findsOneWidget);
    });
  });

  group('wave4-C studio_shared TokenProgressBar 委托 AppProgressBar', () {
    testWidgets('TokenProgressBar 内部渲染 AppProgressBar', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: TokenProgressBar(tokens: 50, tokenLimit: 200),
          ),
        ),
      );

      expect(find.byType(TokenProgressBar), findsOneWidget);
      expect(find.byType(AppProgressBar), findsOneWidget);

      final progressBar = tester.widget<AppProgressBar>(
        find.byType(AppProgressBar),
      );
      expect(progressBar.value, 0.25);
      expect(progressBar.height, 3);
    });
  });
}
