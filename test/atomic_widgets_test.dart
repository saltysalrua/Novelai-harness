import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_colors_extension.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/theme/app_tokens.dart';
import 'package:novelai_harness/ui/core/theme/theme_context_extensions.dart';
import 'package:novelai_harness/ui/core/widgets/app_badge.dart';
import 'package:novelai_harness/ui/core/widgets/app_collapsible_section.dart';
import 'package:novelai_harness/ui/core/widgets/app_dialog_scaffold.dart';
import 'package:novelai_harness/ui/core/widgets/app_dropdown.dart';
import 'package:novelai_harness/ui/core/widgets/app_empty_state.dart';
import 'package:novelai_harness/ui/core/widgets/app_number_slider.dart';
import 'package:novelai_harness/ui/core/widgets/app_search_field.dart';
import 'package:novelai_harness/ui/core/widgets/app_section_header.dart';
import 'package:novelai_harness/ui/core/widgets/app_setting_tile.dart';
import 'package:novelai_harness/ui/core/widgets/app_thumbnail_card.dart';
import 'package:novelai_harness/ui/core/widgets/app_tool_chip.dart';

void main() {
  group('Theme Tokens & Extension Tests', () {
    test('AppColorsExtension provides distinct light and dark palettes', () {
      const light = AppColorsExtension.light;
      const dark = AppColorsExtension.dark;

      expect(light.canvasBackground, isNot(equals(dark.canvasBackground)));
      expect(light.cardBackground, isNot(equals(dark.cardBackground)));
      expect(light.textPrimary, isNot(equals(dark.textPrimary)));
    });

    test('AppTokens have valid positive scales', () {
      expect(AppSpacing.xs < AppSpacing.sm, isTrue);
      expect(AppSpacing.sm < AppSpacing.md, isTrue);
      expect(AppRadius.sm < AppRadius.md, isTrue);
      expect(AppRadius.pill, equals(9999.0));
    });

    test('AppShadows adapt between light and dark brightness', () {
      final light = AppShadows.dialog(Colors.black);
      final dark = AppShadows.dialog(Colors.black, brightness: Brightness.dark);

      // 暗色阴影加深加扩，保证深色表面上可见
      expect(dark.first.blurRadius, greaterThan(light.first.blurRadius));
      expect(dark.first.spreadRadius, greaterThan(0));
      expect(light.first.spreadRadius, equals(0));
    });

    testWidgets('ThemeContextX accesses colors in widget tree', (tester) async {
      late AppColorsExtension resolvedColors;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          home: Builder(
            builder: (context) {
              resolvedColors = context.colors;
              return Container(color: context.colors.cardBackground);
            },
          ),
        ),
      );

      expect(resolvedColors.cardBackground, equals(const Color(0xFFFFFFFF)));
    });

    testWidgets('ThemeContextX shadow getters follow theme brightness', (
      tester,
    ) async {
      late List<BoxShadow> lightShadows;
      late List<BoxShadow> darkShadows;

      // 注意: 直接包 Theme 组件驱动亮度；MaterialApp 的 theme 参数热替换
      // 在同一测试内不会重解析 (真实应用走 themeMode 切换，无此问题)
      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: AppTheme.lightTheme,
            child: Builder(
              builder: (context) {
                lightShadows = context.shadowDialog;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: AppTheme.darkTheme,
            child: Builder(
              builder: (context) {
                darkShadows = context.shadowDialog;
                return const SizedBox();
              },
            ),
          ),
        ),
      );

      expect(lightShadows.first.spreadRadius, equals(0));
      expect(darkShadows.first.spreadRadius, greaterThan(0));
    });
  });

  group('Atomic Widgets Tests', () {
    testWidgets('AppDropdown displays items and triggers selection', (
      tester,
    ) async {
      String selected = 'opt1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppDropdown<String>.simple(
                  value: selected,
                  items: const ['opt1', 'opt2'],
                  labelOf: (item) => 'Label $item',
                  onChanged: (v) => setState(() => selected = v),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Label opt1'), findsOneWidget);
    });

    testWidgets('AppDropdown opens menu and selects another item', (
      tester,
    ) async {
      String selected = 'opt1';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppDropdown<String>.simple(
                  value: selected,
                  items: const ['opt1', 'opt2', 'opt3'],
                  labelOf: (item) => 'Label $item',
                  onChanged: (v) => setState(() => selected = v),
                );
              },
            ),
          ),
        ),
      );

      // 展开菜单并选择第三项
      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();
      expect(find.text('Label opt3'), findsOneWidget);

      await tester.tap(find.text('Label opt3'));
      await tester.pumpAndSettle();

      expect(selected, equals('opt3'));
      expect(find.text('Label opt3'), findsOneWidget);
    });

    testWidgets('AppDropdown survives dangling value not in items', (
      tester,
    ) async {
      // 动态列表被外部刷新/删除后 value 悬挂在 items 之外，不得断言崩溃
      const selected = 'ghost-model';

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppDropdown<String>.simple(
              value: selected,
              items: const ['opt1', 'opt2'],
              labelOf: _labelOf,
              onChanged: _noopChanged,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      // 防悬挂兜底：显示「未识别」占位而不是崩溃
      expect(find.text('未识别'), findsOneWidget);

      // 菜单仍可正常打开并选择有效项
      await tester.tap(find.byType(AppDropdown<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Label opt1'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('AppNumberSlider updates on value change', (tester) async {
      int currentValue = 20;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppNumberSlider.integer(
                  title: 'Test Steps',
                  value: currentValue,
                  min: 1,
                  max: 50,
                  onChanged: (val) => setState(() => currentValue = val),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Test Steps'), findsOneWidget);
      expect(find.text('20'), findsOneWidget);
    });

    testWidgets(
      'AppNumberSlider commits input on focus loss and clamps range',
      (tester) async {
        int currentValue = 20;
        final List<int> history = [];

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: StatefulBuilder(
                builder: (context, setState) {
                  return Column(
                    children: [
                      AppNumberSlider.integer(
                        title: 'Steps',
                        value: currentValue,
                        min: 1,
                        max: 50,
                        onChanged: (val) => setState(() => currentValue = val),
                      ),
                      // 点击别处的落点，用于触发输入框失焦
                      const SizedBox(height: 40, child: Text('outside')),
                    ],
                  );
                },
              ),
            ),
          ),
        );

        // 输入合法值后令输入框失焦 (点击非可聚焦区域不会转移焦点，
        // 直接驱动 FocusManager 模拟真实失焦路径) → 自动提交
        await tester.enterText(find.byType(TextField), '30');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(currentValue, equals(30));

        // 输入越界值后失焦 → 自动钳制到上限
        await tester.enterText(find.byType(TextField), '999');
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pump();
        expect(currentValue, equals(50));
        expect(find.text('50'), findsOneWidget);
        expect(history, isEmpty);
      },
    );

    testWidgets('AppNumberSlider snaps to step grid on drag', (tester) async {
      double currentValue = 0.0;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppNumberSlider(
                  title: 'Strength',
                  value: currentValue,
                  min: 0,
                  max: 1,
                  fractionDigits: 2,
                  step: 0.05,
                  onChanged: (v) => setState(() => currentValue = v),
                );
              },
            ),
          ),
        ),
      );

      // 拖动滑块后值必须吸附到 0.05 的整数倍
      await tester.drag(find.byType(Slider), const Offset(120, 0));
      await tester.pump();

      expect(currentValue, greaterThan(0));
      expect(
        (currentValue / 0.05).roundToDouble() * 0.05,
        closeTo(currentValue, 1e-9),
      );
    });

    testWidgets('AppSettingTile renders title, subtitle and switch', (
      tester,
    ) async {
      bool toggleVal = true;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppSettingTile.switchTile(
                  title: 'Auto Save',
                  subtitle: 'Save images to local directory',
                  value: toggleVal,
                  onChanged: (v) => setState(() => toggleVal = v),
                );
              },
            ),
          ),
        ),
      );

      expect(find.text('Auto Save'), findsOneWidget);
      expect(find.text('Save images to local directory'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets('AppSettingTile switch row toggles on whole-row tap', (
      tester,
    ) async {
      bool toggleVal = false;

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return AppSettingTile.switchTile(
                  title: 'Auto Save',
                  value: toggleVal,
                  onChanged: (v) => setState(() => toggleVal = v),
                );
              },
            ),
          ),
        ),
      );

      // 点击标题区域 (非 Switch 本体) 也应触发整行切换
      expect(toggleVal, isFalse);
      await tester.tap(find.text('Auto Save'));
      await tester.pump();
      expect(toggleVal, isTrue);

      // 再点一次切回
      await tester.tap(find.text('Auto Save'));
      await tester.pump();
      expect(toggleVal, isFalse);
    });

    testWidgets('AppSettingTile actionTile renders without icon gap', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppSettingTile.actionTile(
              title: 'Open Folder',
              buttonLabel: '打开',
              onPressed: _noop,
            ),
          ),
        ),
      );

      expect(find.text('打开'), findsOneWidget);
      // 无图标时按钮内部不应残留占位空隙 (标题与控件间的合法 SizedBox 不受影响)
      expect(
        find.descendant(
          of: find.byType(OutlinedButton),
          matching: find.byType(SizedBox),
        ),
        findsNothing,
      );
    });

    testWidgets('AppSectionHeader renders title and subtitle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppSectionHeader(
              title: 'Model Options',
              subtitle: 'Select base diffusion model',
            ),
          ),
        ),
      );

      expect(find.text('Model Options'), findsOneWidget);
      expect(find.text('Select base diffusion model'), findsOneWidget);
    });

    testWidgets('AppSectionHeader keeps safe gap before trailing', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppSectionHeader(title: 'Header', trailing: Text('Action')),
          ),
        ),
      );

      final headerLeft = tester.getTopLeft(find.text('Header')).dx;
      final trailingLeft = tester.getTopLeft(find.text('Action')).dx;
      expect(trailingLeft - headerLeft, greaterThan(60));
    });

    testWidgets('AppDialogScaffold displays modal with title and actions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppDialogScaffold(
              title: 'Test Dialog',
              subtitle: 'Dialog Description',
              body: const Text('Dialog Content'),
              actions: [
                ElevatedButton(onPressed: () {}, child: const Text('OK')),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Test Dialog'), findsOneWidget);
      expect(find.text('Dialog Description'), findsOneWidget);
      expect(find.text('Dialog Content'), findsOneWidget);
      expect(find.text('OK'), findsOneWidget);
    });

    testWidgets('AppDialogScaffold renders sidebar slot in two-column layout', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppDialogScaffold(
              title: 'Two Column',
              sidebar: const Text('NAV'),
              body: const Text('BODY'),
            ),
          ),
        ),
      );

      expect(find.text('NAV'), findsOneWidget);
      expect(find.text('BODY'), findsOneWidget);
      // 侧栏应位于主体左侧
      expect(
        tester.getTopLeft(find.text('NAV')).dx,
        lessThan(tester.getTopLeft(find.text('BODY')).dx),
      );
    });

    testWidgets('AppDialogScaffold ESC closes dialog when no input focused', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => AppDialogScaffold.show(
                  context: context,
                  builder: (_) => AppDialogScaffold(
                    title: 'Esc Dialog',
                    body: const Text('Content'),
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Esc Dialog'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text('Esc Dialog'), findsNothing);
    });

    testWidgets(
      'AppDialogScaffold ESC unfocuses TextField first, closes later',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () => AppDialogScaffold.show(
                    context: context,
                    builder: (_) => AppDialogScaffold(
                      title: 'Input Dialog',
                      body: const TextField(),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();

        // 聚焦输入框后第一次 ESC：只退焦，弹窗保留
        await tester.tap(find.byType(TextField));
        await tester.enterText(find.byType(TextField), 'draft');
        await tester.pump();

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Input Dialog'), findsOneWidget);

        // 第二次 ESC：关闭弹窗
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.text('Input Dialog'), findsNothing);
      },
    );

    testWidgets('AppThumbnailCard displays with badge', (tester) async {
      final dummyBytes = Uint8List(100);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: AppThumbnailCard(
              imageBytes: dummyBytes,
              badgeLabel: '放大',
              isSelected: true,
            ),
          ),
        ),
      );

      expect(find.text('放大'), findsOneWidget);
    });

    testWidgets('AppThumbnailCard badge position defaults to top-right', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppThumbnailCard(
              imageWidget: ColoredBox(color: Colors.blue),
              badgeLabel: 'TAG',
            ),
          ),
        ),
      );

      final cardRight = tester.getTopRight(find.byType(AppThumbnailCard)).dx;
      final badgeRight = tester.getTopRight(find.text('TAG')).dx;
      // 右上规范：角标贴近卡片右缘
      expect(cardRight - badgeRight, lessThan(20));
    });

    testWidgets('AppThumbnailCard hover actions fade in on hover', (
      tester,
    ) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);

      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: AppThumbnailCard(
              imageWidget: ColoredBox(color: Colors.blue),
              badgeLabel: 'TAG',
              hoverActions: Icon(Icons.delete_rounded),
            ),
          ),
        ),
      );

      final opacityBefore = tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .opacity;
      expect(opacityBefore, equals(0.0));

      await gesture.moveTo(tester.getCenter(find.byType(AppThumbnailCard)));
      await tester.pumpAndSettle();

      final opacityAfter = tester
          .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
          .opacity;
      expect(opacityAfter, equals(1.0));
    });
  });

  group('Dark Theme Rendering Tests', () {
    testWidgets('atomic widgets render under darkTheme without exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: Column(
              children: [
                const AppSectionHeader(
                  title: 'Dark Header',
                  trailing: Text('act'),
                ),
                AppSettingTile.actionTile(
                  title: 'Dark Tile',
                  buttonLabel: '操作',
                  onPressed: _noop,
                ),
              ],
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Dark Header'), findsOneWidget);
      expect(find.text('Dark Tile'), findsOneWidget);
    });

    testWidgets('AppDropdown renders under darkTheme', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: Scaffold(
            body: AppDropdown<String>.simple(
              value: 'a',
              items: const ['a', 'b'],
              labelOf: _labelOf,
              onChanged: _noopChanged,
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('Label a'), findsOneWidget);
    });
  });
  group(
    'Batch 2 Widgets Tests (AppBadge / AppToolChip / AppSearchField / AppCollapsibleSection / AppEmptyState)',
    () {
      testWidgets(
        'AppBadge renders label, icon, trailing and dark variant colors',
        (tester) async {
          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: const Scaffold(
                body: AppBadge(
                  key: Key('badge'),
                  label: '角标',
                  icon: Icons.star_rounded,
                  trailing: Icon(Icons.close_rounded, size: 10),
                  variant: AppBadgeVariant.dark,
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.text('角标'), findsOneWidget);
          expect(find.byIcon(Icons.star_rounded), findsOneWidget);
          expect(find.byIcon(Icons.close_rounded), findsOneWidget);

          final container = tester.widget<Container>(
            find.descendant(
              of: find.byKey(const Key('badge')),
              matching: find.byType(Container),
            ),
          );
          final decoration = container.decoration! as BoxDecoration;
          expect(
            decoration.color,
            equals(Colors.black.withValues(alpha: 0.65)),
          );
          expect(decoration.border, isNull);
        },
      );

      testWidgets('AppBadge.pill factory honors custom color overrides', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Scaffold(
              body: AppBadge.pill(
                key: Key('pill'),
                label: 'V5',
                variant: AppBadgeVariant.neutral,
                customBackgroundColor: Color(0xFF123456),
                customForegroundColor: Color(0xFFABCDEF),
              ),
            ),
          ),
        );

        final container = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const Key('pill')),
            matching: find.byType(Container),
          ),
        );
        final decoration = container.decoration! as BoxDecoration;
        expect(decoration.color, equals(const Color(0xFF123456)));
        expect(
          decoration.borderRadius,
          equals(BorderRadius.circular(AppRadius.pill)),
        );
        expect(
          tester.widget<Text>(find.text('V5')).style!.color,
          equals(const Color(0xFFABCDEF)),
        );
      });

      testWidgets(
        'AppToolChip tap triggers callback and selected state paints primary',
        (tester) async {
          var tapCount = 0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: AppToolChip(
                  icon: Icons.brush_rounded,
                  label: '画笔',
                  isSelected: true,
                  tooltip: '切换画笔',
                  onTap: () => tapCount++,
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.text('画笔'), findsOneWidget);

          // 选中态 filled 变体：文字为白色、加粗
          final textStyle = tester.widget<Text>(find.text('画笔')).style!;
          expect(textStyle.color, equals(Colors.white));
          expect(textStyle.fontWeight, equals(FontWeight.w600));

          await tester.tap(find.text('画笔'));
          await tester.pump();
          expect(tapCount, equals(1));
        },
      );

      testWidgets('AppToolChip tinted variant and disabled state', (
        tester,
      ) async {
        final lightColors = AppColorsExtension.light;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: Column(
                children: [
                  AppToolChip(
                    key: Key('tinted'),
                    label: '选中胶囊',
                    isSelected: true,
                    variant: AppToolChipVariant.tinted,
                  ),
                  AppToolChip(key: Key('disabled'), label: '禁用胶囊'),
                ],
              ),
            ),
          ),
        );

        // tinted 选中态：浅蓝底 + 主色文字
        expect(
          tester.widget<Text>(find.text('选中胶囊')).style!.color,
          equals(lightColors.primary),
        );
        final tintedContainer = tester.widget<Container>(
          find.descendant(
            of: find.byKey(const Key('tinted')),
            matching: find.byType(Container),
          ),
        );
        expect(
          (tintedContainer.decoration! as BoxDecoration).color,
          equals(lightColors.primaryTint),
        );

        // 无 onTap = 禁用态：文字用 muted 色，点击不崩溃
        expect(
          tester.widget<Text>(find.text('禁用胶囊')).style!.color,
          equals(lightColors.textMuted),
        );
        await tester.tap(find.text('禁用胶囊'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      });

      testWidgets(
        'AppSearchField debounces onChanged and fires onSubmitted on enter',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          final received = <String>[];
          var submitted = '';

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: AppSearchField(
                  controller: controller,
                  hintText: '搜索词库',
                  onChanged: received.add,
                  onSubmitted: (v) => submitted = v,
                ),
              ),
            ),
          );

          expect(find.text('搜索词库'), findsOneWidget);

          // 防抖期内不触发
          await tester.enterText(find.byType(TextField), 'girl');
          await tester.pump(const Duration(milliseconds: 100));
          expect(received, isEmpty);

          // 超过 250ms 防抖窗口后触发一次
          await tester.pump(const Duration(milliseconds: 200));
          expect(received, equals(['girl']));

          // 回车提交
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await tester.pump();
          expect(submitted, equals('girl'));
        },
      );

      testWidgets(
        'AppSearchField clear button empties text and calls onClear',
        (tester) async {
          final controller = TextEditingController();
          addTearDown(controller.dispose);
          var clearCount = 0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: AppSearchField(
                  controller: controller,
                  debounceDuration: Duration.zero,
                  onClear: () => clearCount++,
                ),
              ),
            ),
          );

          // 无内容时不显示清空按钮
          expect(find.byTooltip('清空输入'), findsNothing);

          await tester.enterText(find.byType(TextField), 'abc');
          await tester.pump();
          expect(find.byTooltip('清空输入'), findsOneWidget);

          await tester.tap(find.byTooltip('清空输入'));
          await tester.pump();
          expect(controller.text, isEmpty);
          expect(clearCount, equals(1));
          expect(find.byTooltip('清空输入'), findsNothing);
        },
      );

      testWidgets('AppCollapsibleSection uncontrolled toggle expands child', (
        tester,
      ) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: AppCollapsibleSection(
                key: Key('section'),
                title: '高级参数',
                subtitle: '采样与引导高级选项',
                child: Text('折叠体内容'),
              ),
            ),
          ),
        );

        final collapsedHeight = tester
            .getSize(find.byKey(const Key('section')))
            .height;
        expect(find.text('高级参数'), findsOneWidget);
        expect(find.text('折叠体内容'), findsOneWidget);

        await tester.tap(find.text('高级参数'));
        await tester.pumpAndSettle();

        final expandedHeight = tester
            .getSize(find.byKey(const Key('section')))
            .height;
        expect(expandedHeight, greaterThan(collapsedHeight));

        // 再次点击收起
        await tester.tap(find.text('高级参数'));
        await tester.pumpAndSettle();
        expect(
          tester.getSize(find.byKey(const Key('section'))).height,
          lessThan(expandedHeight),
        );
      });

      testWidgets(
        'AppCollapsibleSection controlled mode reports expansion and animates',
        (tester) async {
          bool? expanded = false;
          bool? reported;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    return AppCollapsibleSection(
                      title: '原始 JSON',
                      isExpanded: expanded,
                      onExpansionChanged: (v) {
                        reported = v;
                        setState(() => expanded = v);
                      },
                      child: const Text('{"steps": 28}'),
                    );
                  },
                ),
              ),
            ),
          );

          await tester.tap(find.text('原始 JSON'));
          await tester.pumpAndSettle();
          expect(reported, isTrue);
          expect(expanded, isTrue);
          expect(find.text('{"steps": 28}'), findsOneWidget);
        },
      );

      testWidgets(
        'AppEmptyState renders texts and action button triggers callback',
        (tester) async {
          var actionCount = 0;

          await tester.pumpWidget(
            MaterialApp(
              theme: AppTheme.lightTheme,
              home: Scaffold(
                body: AppEmptyState(
                  icon: Icons.image_not_supported_outlined,
                  title: '暂无图片',
                  description: '生成后会出现在这里',
                  actionLabel: '去生成',
                  actionIcon: Icons.add_rounded,
                  onActionPressed: () => actionCount++,
                ),
              ),
            ),
          );

          expect(tester.takeException(), isNull);
          expect(find.text('暂无图片'), findsOneWidget);
          expect(find.text('生成后会出现在这里'), findsOneWidget);
          expect(
            find.byIcon(Icons.image_not_supported_outlined),
            findsOneWidget,
          );

          await tester.tap(find.text('去生成'));
          await tester.pump();
          expect(actionCount, equals(1));
        },
      );

      testWidgets(
        'AppEmptyState custom action widget takes precedence over label',
        (tester) async {
          await tester.pumpWidget(
            const MaterialApp(
              home: Scaffold(
                body: AppEmptyState(
                  icon: Icons.folder_open_rounded,
                  title: '词库为空',
                  isCompact: true,
                  actionLabel: '不应出现的按钮',
                  action: Text('自定义动作'),
                ),
              ),
            ),
          );

          expect(find.text('自定义动作'), findsOneWidget);
          expect(find.text('不应出现的按钮'), findsNothing);

          // 紧凑形态默认图标 28px
          expect(
            tester.widget<Icon>(find.byIcon(Icons.folder_open_rounded)).size,
            equals(28.0),
          );
        },
      );
    },
  );
}

String _labelOf(String item) => 'Label $item';
void _noop() {}
void _noopChanged(String _) {}
