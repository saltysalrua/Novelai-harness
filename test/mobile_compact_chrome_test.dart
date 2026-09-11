import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/ui/core/context_l10n.dart';
import 'package:novelai_harness/ui/core/widgets/app_nav_tile.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_input_bar.dart';
import 'package:novelai_harness/ui/features/studio/widgets/generate_dock.dart';

import 'mobile_layout_regression_test.dart' show pumpApp;

void main() {
  for (final width in [320.0, 390.0]) {
    testWidgets(
      '$width portrait: compact chrome and keyboard preserve usable chat space',
      (tester) async {
        await pumpApp(tester, Size(width, 844));
        addTearDown(tester.view.resetViewInsets);
        final vm = StudioView.testViewModelHook!;
        vm.setAccountInfoForTest(
          NaiAccountInfo.fromJson({
            'subscription': {
              'tier': 3,
              'active': true,
              'usage': {'percent': 70},
              'trainingStepsLeft': {'fixedTrainingStepsLeft': 10000},
            },
          }),
        );
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const ValueKey('mobile_top_bar'))).height,
          48,
        );
        expect(
          tester.getSize(find.byType(GenerateDock)).height,
          lessThanOrEqualTo(160),
        );
        expect(find.text('10000 Anlas'), findsOneWidget);
        final l10n = tester.element(find.byType(GenerateDock)).l10n;
        expect(find.text(l10n.v5Stamina), findsOneWidget);
        expect(find.text('70%'), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(GenerateDock),
            matching: find.text('Opus'),
          ),
          findsOneWidget,
          reason: '手机底部同样展示账号等级徽章',
        );
        expect(
          tester.getSize(find.byType(ElevatedButton)).height,
          greaterThanOrEqualTo(48),
        );
        expect(
          find.text(
            tester.element(find.byType(GenerateDock)).l10n.generateImage,
          ),
          findsOneWidget,
        );
        final params = find.byKey(const ValueKey('mobile_nav_parameters'));
        final prompts = find.byKey(const ValueKey('mobile_nav_prompts'));
        expect(tester.widget<AppNavTile>(params).isSelected, isTrue);
        expect(tester.widget<AppNavTile>(params).axis, Axis.vertical);
        await tester.tap(prompts);
        await tester.pumpAndSettle();
        expect(tester.widget<AppNavTile>(prompts).isSelected, isTrue);
        expect(tester.widget<AppNavTile>(params).isSelected, isFalse);

        await tester.tap(find.byKey(const ValueKey('segmented_pill_2')));
        await tester.pumpAndSettle();
        final input = find.byType(AgentChatInputBar);
        expect(tester.widget<AgentChatInputBar>(input).compact, isTrue);
        expect(tester.getSize(input).height, lessThanOrEqualTo(210));
        final field = find.descendant(
          of: input,
          matching: find.byType(TextField),
        );
        await tester.enterText(field, '竖屏草稿');
        tester.view.viewInsets = const FakeViewPadding(bottom: 320);
        await tester.pumpAndSettle();
        expect(
          params,
          findsNothing,
          reason: 'keyboard hides shortcuts rather than crowding chat',
        );
        expect(tester.getBottomLeft(input).dy, lessThanOrEqualTo(844 - 320));
        expect(tester.getTopLeft(input).dy, greaterThan(200));
        expect(vm.chatDraft, '竖屏草稿');
        tester.view.viewInsets = FakeViewPadding.zero;
        await tester.pumpAndSettle();
        expect(params, findsOneWidget);
        expect(vm.chatDraft, '竖屏草稿');
        final focus = tester
            .widget<EditableText>(
              find.descendant(of: input, matching: find.byType(EditableText)),
            )
            .focusNode;
        expect(focus.hasFocus, isTrue);
        await tester.tap(find.byKey(const ValueKey('segmented_pill_0')));
        await tester.pumpAndSettle();
        expect(focus.hasFocus, isFalse, reason: '离开聊天页收起键盘焦点');
        expect(vm.chatDraft, '竖屏草稿');
        expect(tester.takeException(), isNull);
      },
    );
  }
}
