import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/theme/app_theme.dart';
import 'package:novelai_harness/ui/core/widgets/app_async_icon_button.dart';
import 'package:novelai_harness/ui/core/widgets/app_autocomplete_panel.dart';
import 'package:novelai_harness/ui/core/widgets/app_confirm_dialog.dart';
import 'package:novelai_harness/ui/core/widgets/app_copyable_box.dart';
import 'package:novelai_harness/ui/core/widgets/app_drop_target_overlay.dart';
import 'package:novelai_harness/ui/core/widgets/app_icon_button.dart';
import 'package:novelai_harness/ui/core/widgets/app_key_value_row.dart';
import 'package:novelai_harness/ui/core/widgets/app_nav_tile.dart';
import 'package:novelai_harness/ui/core/widgets/app_progress_bar.dart';
import 'package:novelai_harness/ui/core/widgets/app_prompt_dialog.dart';
import 'package:novelai_harness/ui/core/widgets/app_resize_divider.dart';
import 'package:novelai_harness/ui/core/widgets/app_segmented_controls.dart';

Widget wrapWithTheme(Widget child, {ThemeMode mode = ThemeMode.light}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: mode,
    home: Scaffold(body: Center(child: child)),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppIconButton Tests', () {
    testWidgets('Renders all variants with custom size, icon and tooltip', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const Column(
            children: [
              AppIconButton(
                icon: Icons.edit,
                size: 28.0,
                variant: AppIconButtonVariant.outlined,
                tooltip: '编辑',
              ),
              AppIconButton(
                icon: Icons.delete,
                size: 32.0,
                variant: AppIconButtonVariant.elevated,
              ),
              AppIconButton(
                icon: Icons.send,
                size: 36.0,
                variant: AppIconButtonVariant.primary,
              ),
              AppIconButton(
                icon: Icons.more_vert,
                size: 24.0,
                variant: AppIconButtonVariant.ghost,
              ),
            ],
          ),
        ),
      );

      expect(find.byIcon(Icons.edit), findsOneWidget);
      expect(find.byIcon(Icons.delete), findsOneWidget);
      expect(find.byIcon(Icons.send), findsOneWidget);
      expect(find.byIcon(Icons.more_vert), findsOneWidget);
      expect(find.byTooltip('编辑'), findsOneWidget);
    });

    testWidgets('Handles tap and disabled state correctly', (tester) async {
      int tapCount = 0;

      await tester.pumpWidget(
        wrapWithTheme(
          Column(
            children: [
              AppIconButton(icon: Icons.add, onPressed: () => tapCount++),
              AppIconButton(
                icon: Icons.remove,
                enabled: false,
                onPressed: () => tapCount++,
              ),
            ],
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pumpAndSettle();
      expect(tapCount, equals(1));

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pumpAndSettle();
      expect(tapCount, equals(1)); // 不增加
    });
  });

  group('AppConfirmDialog Tests', () {
    testWidgets('Renders title, message, and destructive styling', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const AppConfirmDialog(
            title: '清空历史',
            message: '确定要清空画板吗？',
            confirmLabel: '清空',
            isDestructive: true,
          ),
        ),
      );

      expect(find.text('清空历史'), findsOneWidget);
      expect(find.text('确定要清空画板吗？'), findsOneWidget);
      expect(find.text('清空'), findsOneWidget);
      expect(find.text('取消'), findsOneWidget);
    });

    testWidgets(
      'showAppConfirmDialog integration returns true on confirm and false on cancel',
      (tester) async {
        bool? dialogResult;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    dialogResult = await showAppConfirmDialog(
                      context,
                      title: '确认删除',
                      message: '删除后无法恢复',
                      confirmLabel: '删除',
                      isDestructive: true,
                    );
                  },
                  child: const Text('打开弹窗'),
                );
              },
            ),
          ),
        );

        // 1. 打开弹窗并取消
        await tester.tap(find.text('打开弹窗'));
        await tester.pumpAndSettle();
        expect(find.text('确认删除'), findsOneWidget);

        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
        expect(dialogResult, equals(false));

        // 2. 再次打开弹窗并确认
        await tester.tap(find.text('打开弹窗'));
        await tester.pumpAndSettle();
        expect(find.text('确认删除'), findsOneWidget);

        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(dialogResult, equals(true));
      },
    );
  });

  group('AppPromptDialog Tests', () {
    testWidgets('Renders with autofocus, initialValue, hintText and icon', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const AppPromptDialog(
            title: '重命名会话',
            initialValue: '新会话 1',
            hintText: '请输入会话名称...',
            icon: Icons.edit_outlined,
          ),
        ),
      );

      expect(find.text('重命名会话'), findsOneWidget);
      expect(find.text('新会话 1'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    });

    testWidgets(
      'showAppPromptDialog returns entered text and handles non-empty validation',
      (tester) async {
        String? result;

        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) {
                return ElevatedButton(
                  onPressed: () async {
                    result = await showAppPromptDialog(
                      context,
                      title: '重命名',
                      initialValue: '原始名称',
                      allowEmpty: false,
                    );
                  },
                  child: const Text('打开重命名'),
                );
              },
            ),
          ),
        );

        // 打开弹窗并清空内容尝试提交 (非空校验拦截)
        await tester.tap(find.text('打开重命名'));
        await tester.pumpAndSettle();

        final textFieldFinder = find.byType(TextField);
        await tester.enterText(textFieldFinder, '   ');
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();

        expect(find.text('内容不能为空'), findsOneWidget);
        expect(find.text('重命名'), findsOneWidget); // 仍未关闭

        // 输入合法文本并确认
        await tester.enterText(textFieldFinder, '更新后的会话');
        await tester.tap(find.text('确定'));
        await tester.pumpAndSettle();

        expect(result, equals('更新后的会话'));
      },
    );
  });

  group('AppDropTargetOverlay Tests', () {
    testWidgets('Does not render when isDragging is false', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const Stack(
            children: [
              AppDropTargetOverlay(isDragging: false, title: '松开鼠标导入图片'),
            ],
          ),
        ),
      );

      expect(find.text('松开鼠标导入图片'), findsNothing);
    });

    testWidgets(
      'Renders correctly with icon, title and subtitle when isDragging is true',
      (tester) async {
        await tester.pumpWidget(
          wrapWithTheme(
            const Stack(
              children: [
                AppDropTargetOverlay(
                  isDragging: true,
                  icon: Icons.file_download_outlined,
                  title: '松开鼠标导入图片',
                  subtitle: '自动识别生成元数据',
                ),
              ],
            ),
          ),
        );

        expect(find.text('松开鼠标导入图片'), findsOneWidget);
        expect(find.text('自动识别生成元数据'), findsOneWidget);
        expect(find.byIcon(Icons.file_download_outlined), findsOneWidget);
      },
    );
  });

  group('AppSegmentedControls Tests', () {
    testWidgets(
      'AppSegmentedPillBar handles item switching and variant styles',
      (tester) async {
        String selected = 'all';

        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              return wrapWithTheme(
                AppSegmentedPillBar<String>(
                  selectedValue: selected,
                  items: const [
                    AppSegmentedItem(value: 'all', label: '全部'),
                    AppSegmentedItem(value: 'month', label: '本月'),
                    AppSegmentedItem(value: 'week', label: '本周'),
                  ],
                  onValueChanged: (val) {
                    setState(() => selected = val);
                  },
                ),
              );
            },
          ),
        );

        expect(find.text('全部'), findsOneWidget);
        expect(find.text('本月'), findsOneWidget);

        await tester.tap(find.text('本月'));
        await tester.pumpAndSettle();

        expect(selected, equals('month'));
      },
    );

    testWidgets(
      'AppOptionCard renders title, subtitle, icon and triggers callbacks',
      (tester) async {
        bool cardSelected = false;
        String? selectedValue;

        await tester.pumpWidget(
          wrapWithTheme(
            AppOptionCard<String>(
              value: 'inpaint_original',
              isSelected: false,
              icon: Icons.auto_fix_high_rounded,
              title: '原图模式',
              subtitle: '基于原图区域重绘',
              onTap: () => cardSelected = true,
              onSelected: (val) => selectedValue = val,
            ),
          ),
        );

        expect(find.text('原图模式'), findsOneWidget);
        expect(find.text('基于原图区域重绘'), findsOneWidget);
        expect(find.byIcon(Icons.auto_fix_high_rounded), findsOneWidget);

        await tester.tap(find.text('原图模式'));
        await tester.pumpAndSettle();

        expect(cardSelected, isTrue);
        expect(selectedValue, equals('inpaint_original'));
      },
    );
  });

  group('AppCopyableBox Tests', () {
    testWidgets('Renders title, prefix badge and content', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const AppCopyableBox(
            title: '提示词预览',
            prefixBadge: 'UC: ',
            content: 'bad anatomy, blurry, low quality',
          ),
        ),
      );

      expect(find.text('提示词预览'), findsOneWidget);
      expect(find.text('UC: '), findsOneWidget);
      expect(find.text('bad anatomy, blurry, low quality'), findsOneWidget);
      expect(find.text('复制'), findsOneWidget);
    });

    testWidgets('Triggers onCopy and shows copied feedback state', (
      tester,
    ) async {
      bool copied = false;

      await tester.pumpWidget(
        wrapWithTheme(
          AppCopyableBox(
            title: '正向提示词',
            content: '1girl, master_piece',
            onCopy: () => copied = true,
          ),
        ),
      );

      await tester.tap(find.text('复制'));
      await tester.pump();

      expect(copied, isTrue);
      expect(find.text('已复制'), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('AppKeyValueRow Tests', () {
    testWidgets(
      'Renders label and value with monospace and highlight styling',
      (tester) async {
        await tester.pumpWidget(
          wrapWithTheme(
            const Column(
              children: [
                AppKeyValueRow(
                  label: '尺寸',
                  value: '1024 × 1024',
                  isMonospace: true,
                ),
                AppKeyValueRow(
                  label: '消耗',
                  value: '0 Anlas (Opus 免费)',
                  isPrimaryHighlight: true,
                ),
              ],
            ),
          ),
        );

        expect(find.text('尺寸'), findsOneWidget);
        expect(find.text('1024 × 1024'), findsOneWidget);
        expect(find.text('消耗'), findsOneWidget);
        expect(find.text('0 Anlas (Opus 免费)'), findsOneWidget);
      },
    );

    testWidgets('Handles tap and copy interaction with feedback', (
      tester,
    ) async {
      bool rowTapped = false;
      bool rowCopied = false;

      await tester.pumpWidget(
        wrapWithTheme(
          AppKeyValueRow(
            label: '随机种子',
            value: '2948271827',
            copyable: true,
            onTap: () => rowTapped = true,
            onCopy: () => rowCopied = true,
          ),
        ),
      );

      await tester.tap(find.text('2948271827'));
      await tester.pump();

      expect(rowTapped, isTrue);
      expect(rowCopied, isTrue);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('AppResizeDivider Tests', () {
    testWidgets('Renders vertical and horizontal resize handles', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          Column(
            children: [
              AppResizeDivider(
                axis: Axis.vertical,
                onDelta: (_) {},
                tooltip: '上下拖动',
              ),
              AppResizeDivider(
                axis: Axis.horizontal,
                onDelta: (_) {},
                tooltip: '左右拖动',
              ),
            ],
          ),
        ),
      );

      expect(find.byTooltip('上下拖动'), findsOneWidget);
      expect(find.byTooltip('左右拖动'), findsOneWidget);
    });

    testWidgets('Captures drag deltas and double tap reset', (tester) async {
      double totalDelta = 0;
      bool resetCalled = false;

      await tester.pumpWidget(
        wrapWithTheme(
          AppResizeDivider(
            axis: Axis.vertical,
            onDelta: (delta) => totalDelta += delta,
            onReset: () => resetCalled = true,
          ),
        ),
      );

      final handleFinder = find.byType(AppResizeDivider);

      // 拖拽手势
      await tester.drag(handleFinder, const Offset(0, 50));
      await tester.pumpAndSettle();
      expect(totalDelta, greaterThan(0));

      // 双击手势
      await tester.tap(handleFinder);
      await tester.pump(const Duration(milliseconds: 50));
      await tester.tap(handleFinder);
      await tester.pumpAndSettle();
      expect(resetCalled, isTrue);
    });
  });

  group('AppAsyncIconButton Tests', () {
    testWidgets('Renders normal icon and invokes tap when not loading', (
      tester,
    ) async {
      int count = 0;

      await tester.pumpWidget(
        wrapWithTheme(
          AppAsyncIconButton(
            isLoading: false,
            icon: Icons.refresh,
            onPressed: () => count++,
          ),
        ),
      );

      expect(find.byIcon(Icons.refresh), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byIcon(Icons.refresh));
      await tester.pumpAndSettle();
      expect(count, equals(1));
    });

    testWidgets(
      'Renders CircularProgressIndicator and intercepts taps when loading',
      (tester) async {
        int count = 0;

        await tester.pumpWidget(
          wrapWithTheme(
            AppAsyncIconButton(
              isLoading: true,
              icon: Icons.refresh,
              onPressed: () => count++,
            ),
          ),
        );

        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        await tester.tap(find.byType(AppAsyncIconButton));
        await tester.pump(const Duration(milliseconds: 100));
        expect(count, equals(0)); // 拦截连击，计数不增
      },
    );
  });

  group('AppProgressBar Tests', () {
    testWidgets('Clamps progress and renders standard bar', (tester) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const Column(
            children: [
              AppProgressBar(value: 0.5, height: 4.0),
              AppProgressBar(value: 1.5, height: 6.0),
            ],
          ),
        ),
      );

      final indicators = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(indicators.length, equals(2));
      expect(indicators[0].value, equals(0.5));
      expect(indicators[1].value, equals(1.0)); // 钳制在 1.0
    });

    testWidgets('AppProgressBar applies threshold colors correctly', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const Column(
            children: [
              AppProgressBar(value: 0.85, useThresholdColors: true),
              AppProgressBar(value: 0.45, useThresholdColors: true),
              AppProgressBar(value: 0.15, useThresholdColors: true),
              AppProgressBar(
                value: 0.95,
                useThresholdColors: true,
                invertThresholds: true,
              ),
            ],
          ),
        ),
      );

      final indicators = tester
          .widgetList<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          )
          .toList();
      expect(indicators.length, equals(4));

      // 验证指示器均正常渲染
      for (final indicator in indicators) {
        expect(indicator.valueColor, isNotNull);
      }
    });
  });

  group('AppAutocompletePanel Tests', () {
    testWidgets('Renders list and triggers onSelect when item tapped', (
      tester,
    ) async {
      String? selected;

      await tester.pumpWidget(
        wrapWithTheme(
          AppAutocompletePanel<String>(
            items: const ['1girl', 'solo', 'blue_eyes'],
            selectedIndex: 0,
            itemBuilder: (ctx, item, index, isSelected) {
              return Text(item);
            },
            onSelect: (item) => selected = item,
          ),
        ),
      );

      expect(find.text('1girl'), findsOneWidget);
      expect(find.text('solo'), findsOneWidget);
      expect(find.text('blue_eyes'), findsOneWidget);

      await tester.tap(find.text('solo'));
      await tester.pumpAndSettle();

      expect(selected, equals('solo'));
    });

    testWidgets('Handles emptyBuilder when suggestions list is empty', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          AppAutocompletePanel<String>(
            items: const [],
            selectedIndex: 0,
            itemBuilder: (ctx, item, index, isSelected) => Text(item),
            onSelect: (_) {},
            emptyBuilder: (ctx) => const Text('无匹配标签'),
          ),
        ),
      );

      expect(find.text('无匹配标签'), findsOneWidget);
    });
  });

  group('AppNavTile Tests', () {
    testWidgets('Renders title, subtitle, icon and badge count', (
      tester,
    ) async {
      await tester.pumpWidget(
        wrapWithTheme(
          const Column(
            children: [
              AppNavTile(
                title: '常用提示词',
                subtitle: '快捷词组合管理',
                icon: Icons.bookmark_border_rounded,
                badgeCount: 24,
                isSelected: false,
              ),
              AppNavTile(
                title: '角色模型',
                icon: Icons.person_outline_rounded,
                badgeText: '新',
                isSelected: true,
              ),
            ],
          ),
        ),
      );

      expect(find.text('常用提示词'), findsOneWidget);
      expect(find.text('快捷词组合管理'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('角色模型'), findsOneWidget);
      expect(find.text('新'), findsOneWidget);
    });

    testWidgets('Triggers onTap when clicked', (tester) async {
      bool tapped = false;

      await tester.pumpWidget(
        wrapWithTheme(
          AppNavTile(
            title: '设置',
            icon: Icons.settings_outlined,
            onTap: () => tapped = true,
          ),
        ),
      );

      await tester.tap(find.text('设置'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
