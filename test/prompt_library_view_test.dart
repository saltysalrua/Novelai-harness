import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/widgets/app_action_button.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/character_card_item.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_combo_card.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_combo_edit_dialog.dart';
import 'package:novelai_harness/ui/features/studio/widgets/prompt_library_view.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'test_library_seeds.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late PromptLibraryService service;
  late StudioViewModel viewModel;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('prompt_ui_test_');
    service = PromptLibraryService();
    service.setCustomStorageDirectory(tempDir.path);
    // 词库不再内置默认条目，测试数据显式播种
    await service.saveEntries(seedLibraryEntries());

    viewModel = StudioViewModel(
      configService: ConfigService(),
      promptLibraryService: service,
    );
    await viewModel.init();
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  Widget buildTestApp(Widget child, [Locale locale = const Locale('zh')]) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData.light(),
      home: Scaffold(body: child),
    );
  }

  group('PromptComboEditDialog UI Tests', () {
    testWidgets(
      'Shows negative prompt for character category and hides for style category',
      (tester) async {
        await tester.pumpWidget(
          buildTestApp(PromptComboEditDialog(viewModel: viewModel)),
        );
        await tester.pumpAndSettle();

        // 默认选中“角色”，应看到负面提示词区域及“仅角色分类可用”标识
        expect(find.text('负面提示词'), findsOneWidget);
        expect(find.text('仅角色分类可用'), findsOneWidget);
        expect(find.text('设置预览图'), findsOneWidget);
        expect(find.text('选择本地图片'), findsOneWidget);

        // 打开分类下拉框并选择“风格”
        final dropdown = find.byType(DropdownButton<String>);
        expect(dropdown, findsOneWidget);
        // 窄窗口为上下分区，表单独立滚动，先滚动到分类控件。
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        final styleItem = find.text('风格').last;
        await tester.tap(styleItem);
        await tester.pumpAndSettle();

        // 负面提示词输入框应完全消失
        expect(find.text('负面提示词'), findsNothing);
        expect(find.text('仅角色分类可用'), findsNothing);

        // 重新切回“角色”
        await tester.ensureVisible(dropdown);
        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        final charItem = find.text('角色').last;
        await tester.tap(charItem);
        await tester.pumpAndSettle();

        expect(find.text('负面提示词'), findsOneWidget);
        expect(find.text('仅角色分类可用'), findsOneWidget);
      },
    );
  });

  group('PromptLibraryView Widget Tests', () {
    testWidgets('Renders grid of prompt combos and category chips', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(PromptLibraryView(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      // 应有标题“词库”和“新建词组合”按钮
      expect(find.text('词库'), findsWidgets);
      expect(find.text('新建词组合'), findsOneWidget);

      // 应能找到内置预设中的“初音未来 (Hatsune Miku)”
      expect(find.text('初音未来 (Hatsune Miku)'), findsOneWidget);

      // 点击左侧“风格”分类筛选
      final styleFilter = find.text('风格').first;
      await tester.tap(styleFilter);
      await tester.pumpAndSettle();

      // 初音未来应被过滤掉，出现水彩风
      expect(find.text('初音未来 (Hatsune Miku)'), findsNothing);
      expect(find.text('日系二次元水彩风'), findsOneWidget);
    });

    testWidgets('Apply overlay button appends combo prompt to workbench', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      viewModel.updatePrompt('1girl, solo');

      await tester.pumpWidget(
        buildTestApp(PromptLibraryView(viewModel: viewModel)),
      );
      await tester.pumpAndSettle();

      // 每张卡片预览图底部都应有「应用到工作台」按钮
      final applyBtn = find.text('应用到工作台');
      expect(applyBtn, findsWidgets);

      // 精确定位初音未来卡片上的应用按钮
      final mikuCard = find.ancestor(
        of: find.text('初音未来 (Hatsune Miku)'),
        matching: find.byType(PromptComboCard),
      );
      final mikuApply = find.descendant(of: mikuCard, matching: applyBtn);
      await tester.ensureVisible(mikuApply);
      await tester.tap(mikuApply);
      await tester.pumpAndSettle();

      // 主提示词应被追加初音未来预设内容
      expect(viewModel.params.prompt, startsWith('1girl, solo'));
      expect(viewModel.params.prompt, contains('hatsune miku'));
      // 角色分类同时追加负面词
      expect(viewModel.params.negativePrompt, isNotEmpty);
    });

    testWidgets(
      'Character prompt combo card shows [+ 角色] button and adds character on tap',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(PromptLibraryView(viewModel: viewModel)),
        );
        await tester.pumpAndSettle();

        // 角色分类卡片应该显示 [+ 角色] 按钮
        final addCharBtn = find.text('+ 角色');
        expect(addCharBtn, findsWidgets);

        // 点击 [+ 角色]
        await tester.tap(addCharBtn.first);
        await tester.pumpAndSettle();

        // viewModel 中应该成功添加了一个角色
        expect(viewModel.params.characterPrompts.isNotEmpty, isTrue);
        expect(
          viewModel.params.characterPrompts.last.prompt,
          contains('hatsune miku'),
        );
      },
    );

    testWidgets(
      'CharacterCardItem has save to library button and opens prefilled dialog',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final char = NaiCharacterPrompt.create(
          name: '月见八千代',
          prompt: 'twin tails, hair rings, kimono',
          negativePrompt: 'blurry, bad hands',
        );

        await tester.pumpWidget(
          buildTestApp(
            CharacterCardItem(
              character: char,
              index: 0,
              enabledTotal: 1,
              viewModel: viewModel,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 验证卡片头部有保存到词库按钮
        final saveBtn = find.byTooltip('保存角色到词库');
        expect(saveBtn, findsOneWidget);

        // 点击保存到词库
        await tester.tap(saveBtn);
        await tester.pumpAndSettle();

        // 应该弹出新建词组合弹窗，并且预填充角色的名称与提示词
        final dialogFinder = find.byType(PromptComboEditDialog);
        expect(dialogFinder, findsOneWidget);
        expect(
          find.descendant(of: dialogFinder, matching: find.text('月见八千代')),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('twin tails, hair rings, kimono'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: dialogFinder,
            matching: find.text('blurry, bad hands'),
          ),
          findsOneWidget,
        );

        // 点击保存并在 runAsync 中等待 I/O 完成
        final submitBtn = find.widgetWithText(AppActionButton, '创建词组合');
        expect(submitBtn, findsOneWidget);
        await tester.runAsync(() async {
          await tester.tap(submitBtn);
          await Future.delayed(const Duration(milliseconds: 300));
        });
        await tester.pump();

        // 验证词库中已新增该角色条目
        final entry = viewModel.promptLibraryEntries.firstWhere(
          (e) => e.title == '月见八千代',
        );
        expect(entry.prompt, 'twin tails, hair rings, kimono');
        expect(entry.negativePrompt, 'blurry, bad hands');
        expect(entry.category, '角色');
      },
    );
  });

  group('StudioSidebar and StudioView Full-screen Integration', () {
    testWidgets('Sidebar has library tab and switches to full-screen view', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData.light(),
          home: const StudioView(),
        ),
      );
      await tester.pumpAndSettle();

      // 侧边栏应有“参数”、“提示词”、“词库”
      expect(find.text('参数'), findsWidgets);
      expect(find.text('提示词'), findsWidgets);
      expect(find.text('词库'), findsOneWidget);

      // 点击“词库”Tab
      final libraryTab = find.text('词库');
      await tester.tap(libraryTab);
      await tester.pumpAndSettle();

      // 现在应渲染全屏 PromptLibraryView（包含新建词组合按钮和侧边标签栏）
      expect(find.text('新建词组合'), findsWidgets);
      expect(find.text('标签分类'), findsOneWidget);

      // 点击常驻侧边栏“参数”按钮切回三栏工作台
      final paramsTab = find.text('参数').first;
      await tester.tap(paramsTab);
      await tester.pumpAndSettle();

      // 再次呈现参数/提示词工作台
      expect(find.text('参数设置'), findsOneWidget);
    });
  });

  group('Bilingual i18n Tests (en)', () {
    testWidgets(
      'PromptComboEditDialog renders English strings when locale is en',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 800);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        await tester.pumpWidget(
          buildTestApp(
            PromptComboEditDialog(viewModel: viewModel),
            const Locale('en'),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Negative Prompt'), findsOneWidget);
        expect(find.text('Character category only'), findsOneWidget);
        expect(find.text('Set Preview Image'), findsOneWidget);
        expect(find.text('Choose Local Image'), findsOneWidget);
        expect(find.text('Use Current Canvas Image'), findsOneWidget);
        expect(find.text('New Prompt Combo'), findsOneWidget);
        expect(find.text('Title *'), findsOneWidget);
        expect(find.text('Fill from Workbench'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('Create Prompt Combo'), findsOneWidget);
      },
    );

    testWidgets('PromptLibraryView renders English strings when locale is en', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1200, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      await tester.pumpWidget(
        buildTestApp(
          PromptLibraryView(viewModel: viewModel),
          const Locale('en'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Library'), findsWidgets);
      expect(find.text('New Prompt Combo'), findsOneWidget);
      expect(find.text('Categories'), findsOneWidget);
      expect(find.text('Apply to Workbench'), findsWidgets);
      expect(find.text('+ Character'), findsWidgets);
    });
  });
}
