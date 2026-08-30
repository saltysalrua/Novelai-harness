import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/prompt_library_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
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

  Widget buildTestApp(Widget child) {
    return MaterialApp(
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
        await tester.tap(dropdown);
        await tester.pumpAndSettle();

        final styleItem = find.text('风格').last;
        await tester.tap(styleItem);
        await tester.pumpAndSettle();

        // 负面提示词输入框应完全消失
        expect(find.text('负面提示词'), findsNothing);
        expect(find.text('仅角色分类可用'), findsNothing);

        // 重新切回“角色”
        await tester.tap(find.byType(DropdownButton<String>));
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
        MaterialApp(theme: ThemeData.light(), home: const StudioView()),
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
}
