import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/resizable_split_view.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConfigService Layout Persistence Tests', () {
    test('split widths default and save/load', () async {
      final configService = ConfigService();
      final defaults = await configService.loadSplitWidths();
      expect(defaults.$1, 320.0);
      expect(defaults.$2, 400.0);

      await configService.saveSplitWidths(350.0, 450.0);
      final loaded = await configService.loadSplitWidths();
      expect(loaded.$1, 350.0);
      expect(loaded.$2, 450.0);
    });

    test('sidebar active tab save/load', () async {
      final configService = ConfigService();
      expect(await configService.loadSidebarActiveTab(), 'parameters');

      await configService.saveSidebarActiveTab('prompts');
      expect(await configService.loadSidebarActiveTab(), 'prompts');
    });

    test('prompt tabbed mode and active tab save/load', () async {
      final configService = ConfigService();
      expect(await configService.loadPromptTabbedMode(), isFalse);
      expect(await configService.loadPromptActiveTab(), 0);

      await configService.savePromptTabbedMode(true);
      await configService.savePromptActiveTab(1);

      expect(await configService.loadPromptTabbedMode(), isTrue);
      expect(await configService.loadPromptActiveTab(), 1);
    });

    test('deck active tab and canvas history open save/load', () async {
      final configService = ConfigService();
      expect(await configService.loadDeckActiveTab(), 0);
      expect(await configService.loadCanvasHistoryOpen(), isFalse);

      await configService.saveDeckActiveTab(1);
      await configService.saveCanvasHistoryOpen(true);

      expect(await configService.loadDeckActiveTab(), 1);
      expect(await configService.loadCanvasHistoryOpen(), isTrue);
    });

    test('prompt field heights default and save/load', () async {
      final configService = ConfigService();
      final defaults = await configService.loadPromptFieldHeights();
      expect(defaults.promptStacked, 116.0);
      expect(defaults.negativeStacked, 92.0);
      expect(defaults.promptTabbed, 212.0);
      expect(defaults.negativeTabbed, 212.0);
      expect(defaults.prefix, 88.0);
      expect(defaults.suffix, 64.0);
      expect(defaults.characterPrompt, 72.0);
      expect(defaults.characterNegative, 56.0);

      await configService.savePromptFieldHeights(
        promptStacked: 150.0,
        negativeStacked: 120.0,
        promptTabbed: 280.0,
        negativeTabbed: 260.0,
        prefix: 110.0,
        suffix: 90.0,
        characterPrompt: 100.0,
        characterNegative: 80.0,
      );

      final loaded = await configService.loadPromptFieldHeights();
      expect(loaded.promptStacked, 150.0);
      expect(loaded.negativeStacked, 120.0);
      expect(loaded.promptTabbed, 280.0);
      expect(loaded.negativeTabbed, 260.0);
      expect(loaded.prefix, 110.0);
      expect(loaded.suffix, 90.0);
      expect(loaded.characterPrompt, 100.0);
      expect(loaded.characterNegative, 80.0);
    });

    test('chat draft default and save/load', () async {
      final configService = ConfigService();
      expect(await configService.loadChatDraft(), '');

      await configService.saveChatDraft('test chat draft构思');
      expect(await configService.loadChatDraft(), 'test chat draft构思');
    });
  });

  group('StudioViewModel Layout State Tests', () {
    test('loads persisted layout on init', () async {
      SharedPreferences.setMockInitialValues({
        'novelai_layout_split_left_width': 360.0,
        'novelai_layout_split_right_width': 440.0,
        'novelai_layout_sidebar_active_tab': 'prompts',
        'novelai_layout_prompt_tabbed_mode': true,
        'novelai_layout_prompt_active_tab': 1,
        'novelai_layout_deck_active_tab': 1,
        'novelai_layout_canvas_history_open': true,
        'novelai_layout_prompt_height_stacked': 140.0,
        'novelai_layout_negative_height_stacked': 110.0,
        'novelai_layout_prompt_height_tabbed': 260.0,
        'novelai_layout_negative_height_tabbed': 250.0,
        'novelai_layout_prefix_height': 105.0,
        'novelai_layout_suffix_height': 85.0,
        'novelai_layout_char_prompt_height': 95.0,
        'novelai_layout_char_negative_height': 75.0,
        'novelai_chat_draft': 'draft message',
      });

      final vm = StudioViewModel();
      await vm.init();

      expect(vm.splitLeftWidth, 360.0);
      expect(vm.splitRightWidth, 440.0);
      expect(vm.activeSidebarTab, StudioSidebarTab.prompts);
      expect(vm.promptTabbedMode, isTrue);
      expect(vm.promptActiveTab, 1);
      expect(vm.deckActiveTab, 1);
      expect(vm.canvasHistoryOpen, isTrue);
      expect(vm.promptHeightStacked, 140.0);
      expect(vm.negativePromptHeightStacked, 110.0);
      expect(vm.promptHeightTabbed, 260.0);
      expect(vm.negativePromptHeightTabbed, 250.0);
      expect(vm.prefixPromptHeight, 105.0);
      expect(vm.suffixPromptHeight, 85.0);
      expect(vm.characterPromptHeight, 95.0);
      expect(vm.characterNegativePromptHeight, 75.0);
      expect(vm.chatDraft, 'draft message');
    });

    test('updates layout and saves to SharedPreferences', () async {
      final vm = StudioViewModel();
      await vm.init();

      vm.updateSplitWidths(340.0, 420.0);
      vm.setActiveSidebarTab(StudioSidebarTab.prompts);
      vm.setPromptTabbedMode(true);
      vm.setPromptActiveTab(1);
      vm.setDeckActiveTab(1);
      vm.setCanvasHistoryOpen(true);
      vm.updatePromptHeightStacked(160.0);
      vm.updateNegativePromptHeightStacked(130.0);
      vm.updatePromptHeightTabbed(300.0);
      vm.updateNegativePromptHeightTabbed(290.0);
      vm.updatePrefixPromptHeight(120.0);
      vm.updateSuffixPromptHeight(95.0);
      vm.updateCharacterPromptHeight(115.0);
      vm.updateCharacterNegativePromptHeight(85.0);
      vm.updateChatDraft('updated draft message');

      expect(vm.splitLeftWidth, 340.0);
      expect(vm.splitRightWidth, 420.0);
      expect(vm.activeSidebarTab, StudioSidebarTab.prompts);
      expect(vm.promptTabbedMode, isTrue);
      expect(vm.promptActiveTab, 1);
      expect(vm.deckActiveTab, 1);
      expect(vm.canvasHistoryOpen, isTrue);
      expect(vm.promptHeightStacked, 160.0);
      expect(vm.negativePromptHeightStacked, 130.0);
      expect(vm.promptHeightTabbed, 300.0);
      expect(vm.negativePromptHeightTabbed, 290.0);
      expect(vm.prefixPromptHeight, 120.0);
      expect(vm.suffixPromptHeight, 95.0);
      expect(vm.characterPromptHeight, 115.0);
      expect(vm.characterNegativePromptHeight, 85.0);
      expect(vm.chatDraft, 'updated draft message');

      // 分割线与高度宽度防抖落盘：立即冲刷尚未到期的保存，模拟拖动停止后落盘
      await vm.flushPendingLayoutSave();

      // 验证重启后新建 ViewModel 加载保存的布局
      final restartedVm = StudioViewModel();
      await restartedVm.init();

      expect(restartedVm.splitLeftWidth, 340.0);
      expect(restartedVm.splitRightWidth, 420.0);
      expect(restartedVm.activeSidebarTab, StudioSidebarTab.prompts);
      expect(restartedVm.promptTabbedMode, isTrue);
      expect(restartedVm.promptActiveTab, 1);
      expect(restartedVm.deckActiveTab, 1);
      expect(restartedVm.canvasHistoryOpen, isTrue);
      expect(restartedVm.promptHeightStacked, 160.0);
      expect(restartedVm.negativePromptHeightStacked, 130.0);
      expect(restartedVm.promptHeightTabbed, 300.0);
      expect(restartedVm.negativePromptHeightTabbed, 290.0);
      expect(restartedVm.prefixPromptHeight, 120.0);
      expect(restartedVm.suffixPromptHeight, 95.0);
      expect(restartedVm.characterPromptHeight, 115.0);
      expect(restartedVm.characterNegativePromptHeight, 85.0);
      expect(restartedVm.chatDraft, 'updated draft message');
    });
  });

  group('ResizableThreeSplitView Layout Widget Tests', () {
    testWidgets('dragging divider calls onWidthsChanged callback', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      double changedLeft = 0;
      double changedRight = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ResizableThreeSplitView(
              initialLeftWidth: 320.0,
              initialRightWidth: 400.0,
              onWidthsChanged: (left, right) {
                changedLeft = left;
                changedRight = right;
              },
              leftChild: const Text('Left'),
              centerChild: const Text('Center'),
              rightChild: const Text('Right'),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final splitDividers = find.byType(GestureDetector);
      expect(splitDividers, findsWidgets);

      await tester.drag(splitDividers.first, const Offset(30, 0));
      await tester.pumpAndSettle();

      expect(changedLeft, greaterThan(320.0));
      expect(changedRight, 400.0);
    });
  });
}
