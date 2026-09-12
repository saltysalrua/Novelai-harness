import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/ui/features/settings/views/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 窄屏设置弹窗回归：五个页签在多个窄宽度下轮询，断言无 RenderFlex 溢出。
///
/// 覆盖 2026-12 修复的窄屏溢出点 (均由 AppControlFlow 流式容器接管)：
/// 1. Models 页供应商切换 / 端点+协议 / 在线拉取控件行与模型网格工具条；
/// 2. Presets 页预设管理坞 (下拉 + 设为默认 / 新建 / 复制 / 删除)；
/// 3. Bill 页周期胶囊 + 汇总行。
void main() {
  /// 弹窗内顶部横向页签胶囊 (窄屏布局专用，与工作台顶栏胶囊同 key 隔离)
  Finder dialogPill(int index) => find.descendant(
    of: find.byType(SettingsDialog),
    matching: find.byKey(Key('segmented_pill_$index')),
  );

  /// 断言当前帧没有任何渲染异常 (RenderFlex overflow 经 FlutterError 上报)
  void expectNoRenderErrors(WidgetTester tester, String step) {
    final error = tester.takeException();
    expect(error, isNull, reason: '$step 出现渲染异常: $error');
  }

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final width in const [320.0, 360.0, 430.0]) {
    testWidgets('${width.toInt()}px 宽度下设置弹窗五页签轮询无渲染异常', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = Size(width, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      AppLocaleController.instance.syncFromConfig(
        const AppConfig(localePreference: AppLocalePreference.zh),
      );
      addTearDown(AppLocaleController.instance.resetForTest);

      await tester.pumpWidget(const NovelAiHarnessApp());
      await tester.pumpAndSettle();

      // 窄屏经底部导航打开设置弹窗
      await tester.tap(find.byKey(const Key('mobile_nav_settings')));
      await tester.pumpAndSettle();
      expectNoRenderErrors(tester, '打开设置弹窗');
      expect(find.byType(SettingsDialog), findsOneWidget);

      // 顶部胶囊轮询：0 常规 / 1 模型 / 2 预设 / 3 默认 / 4 账单
      for (var i = 0; i < 5; i++) {
        await tester.ensureVisible(dialogPill(i));
        await tester.tap(dialogPill(i));
        await tester.pumpAndSettle();
        expectNoRenderErrors(tester, '切到页签 $i');
      }

      // 关闭弹窗同样不得引入布局异常
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      expectNoRenderErrors(tester, '关闭设置弹窗');
      expect(find.byType(SettingsDialog), findsNothing);
    });
  }
}
