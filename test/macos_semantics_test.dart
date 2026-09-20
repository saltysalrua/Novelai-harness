import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/ui/core/theme/ui_zoom_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('macOS exposes navigation and the active parameter page', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'llm_api_key': '',
      'novelai_enable_tag_dictionary_auto_update': false,
      'novelai_enable_image_persistence': false,
    });
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    AppLocaleController.instance.syncFromConfig(
      const AppConfig(localePreference: AppLocalePreference.zh),
    );
    addTearDown(AppLocaleController.instance.resetForTest);
    addTearDown(AppUiZoomController.instance.resetForTest);

    await tester.pumpWidget(const NovelAiHarnessApp());
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('设置')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('参数设置')), findsWidgets);
    final parameters = tester.getSemantics(find.text('参数'));
    expect(parameters.flagsCollection.isButton, isTrue);
    expect(parameters.flagsCollection.isSelected == ui.Tristate.isTrue, isTrue);
    final settings = tester.getSemantics(find.text('设置'));
    expect(settings.flagsCollection.isButton, isTrue);

    tester.platformDispatcher.onSemanticsActionEvent!(
      ui.SemanticsActionEvent(
        type: ui.SemanticsAction.tap,
        viewId: tester.view.viewId,
        nodeId: tester.getSemantics(find.text('提示词')).id,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel(RegExp('提示词管理')), findsWidgets);
    expect(find.bySemanticsLabel(RegExp('参数设置')), findsNothing);
    expect(
      tester.getSemantics(find.text('提示词')).flagsCollection.isSelected ==
          ui.Tristate.isTrue,
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
