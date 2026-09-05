import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/ui/core/theme/ui_zoom_controller.dart';
import 'package:novelai_harness/ui/core/widgets/context_menu.dart';
import 'package:novelai_harness/ui/core/widgets/overlay_anchor.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppConfig.uiZoom 字段', () {
    test('默认出厂 100%', () {
      expect(const AppConfig().uiZoom, 1.0);
    });

    test('copyWith 透传 uiZoom', () {
      const config = AppConfig();
      expect(config.copyWith(uiZoom: 1.25).uiZoom, 1.25);
      // 不传时保持原值
      expect(config.copyWith(uiZoom: 1.25).copyWith().uiZoom, 1.25);
    });
  });

  group('UI 缩放持久化', () {
    test('saveConfig → loadConfig 往返不丢失', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ConfigService();
      await service.saveConfig(const AppConfig(uiZoom: 1.25));
      final loaded = await service.loadConfig();
      expect(loaded.uiZoom, 1.25);
    });

    test('旧版本无 novelai_ui_zoom 键时回退 100%', () async {
      SharedPreferences.setMockInitialValues({'novelai_opus_free_mode': false});
      final loaded = await ConfigService().loadConfig();
      expect(loaded.uiZoom, 1.0);
    });

    test('损坏值 (超范围/NaN) 加载时钳制或回退', () async {
      SharedPreferences.setMockInitialValues({'novelai_ui_zoom': 9.9});
      expect((await ConfigService().loadConfig()).uiZoom, 1.75);

      SharedPreferences.setMockInitialValues({'novelai_ui_zoom': 0.1});
      expect((await ConfigService().loadConfig()).uiZoom, 0.8);

      SharedPreferences.setMockInitialValues({'novelai_ui_zoom': double.nan});
      expect((await ConfigService().loadConfig()).uiZoom, 1.0);
    });

    test('saveUiZoom 单字段快存生效', () async {
      SharedPreferences.setMockInitialValues({});
      await ConfigService().saveUiZoom(1.5);
      final loaded = await ConfigService().loadConfig();
      expect(loaded.uiZoom, 1.5);
    });
  });

  group('AppUiZoomController', () {
    setUp(AppUiZoomController.instance.resetForTest);

    test('adjust 步进并钳制边界', () {
      final controller = AppUiZoomController.instance;
      expect(controller.adjust(0.05), 1.05);
      // 上界钳制
      expect(controller.adjust(10), ConfigService.maxUiZoom);
      // 下界钳制
      expect(controller.adjust(-100), ConfigService.minUiZoom);
      expect(controller.zoom.value, ConfigService.minUiZoom);
    });

    test('syncFromConfig 同步且同值不通知', () {
      final controller = AppUiZoomController.instance;
      controller.syncFromConfig(const AppConfig(uiZoom: 1.5));
      expect(controller.zoom.value, 1.5);

      var notified = 0;
      controller.zoom.addListener(() => notified++);
      // 同值同步不触发监听
      controller.syncFromConfig(const AppConfig(uiZoom: 1.5));
      expect(notified, 0);
      // 变值同步触发
      controller.syncFromConfig(const AppConfig(uiZoom: 1.0));
      expect(notified, 1);
    });

    test('reset 回到 100%', () {
      final controller = AppUiZoomController.instance;
      controller.zoom.value = 1.75;
      controller.reset();
      expect(controller.zoom.value, 1.0);
    });
  });

  group('AppUiZoomScope 布局几何', () {
    testWidgets('zoom=1.0 直通无包裹', (tester) async {
      const child = SizedBox.shrink();
      await tester.pumpWidget(
        const MaterialApp(home: AppUiZoomScope(zoom: 1.0, child: child)),
      );
      expect(find.byType(Transform), findsNothing);
      expect(find.byType(FittedBox), findsNothing);
    });

    testWidgets('zoom=1.25 子树在缩小坐标系布局并放大回去', (tester) async {
      // 800x600 视口下 125% 缩放：子树布局坐标系应为 640x480
      const childKey = Key('zoom_child_probe');
      await tester.pumpWidget(
        MaterialApp(
          home: AppUiZoomScope(
            zoom: 1.25,
            child: Builder(
              builder: (context) => SizedBox(
                key: childKey,
                width: MediaQuery.sizeOf(context).width,
                height: MediaQuery.sizeOf(context).height,
              ),
            ),
          ),
        ),
      );

      // 布局尺寸 (布局坐标系, RenderBox.layout 原始值): 640x480
      final childSize = tester
          .renderObject<RenderBox>(find.byKey(childKey))
          .size;
      expect(childSize.width, closeTo(640, 0.1));
      expect(childSize.height, closeTo(480, 0.1));
      // 视觉尺寸 (窗口坐标系, 含缩放变换): 铺满 800x600
      final childRect = tester.getRect(find.byKey(childKey));
      expect(childRect.width, closeTo(800, 0.5));
      expect(childRect.height, closeTo(600, 0.5));
    });

    testWidgets('MediaQuery size 覆写为缩放后逻辑屏幕 (对话框屏障不溢出)', (tester) async {
      late Size mediaQuerySize;
      await tester.pumpWidget(
        MaterialApp(
          home: AppUiZoomScope(
            zoom: 1.5,
            child: Builder(
              builder: (context) {
                mediaQuerySize = MediaQuery.sizeOf(context);
                return const SizedBox.shrink();
              },
            ),
          ),
        ),
      );
      expect(mediaQuerySize.width, closeTo(800 / 1.5, 0.1));
      expect(mediaQuerySize.height, closeTo(600 / 1.5, 0.1));
    });
  });

  group('UI 缩放下的浮层锚定坐标 (Overlay 坐标换算)', () {
    testWidgets('zoom>1 时窗口右/下超出缩小布局的区域仍可命中 (按钮死区修复)', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => AppUiZoomScope(
            zoom: 1.25,
            child: child ?? const SizedBox.shrink(),
          ),
          home: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => taps++,
            child: const SizedBox.expand(),
          ),
        ),
      );

      // 800x600 窗口 125% 缩放：缩小布局为 640x480。
      // 旧 OverflowBox+Transform 方案下，SizedBox 的边界检查发生在窗口坐标系，
      // 右带 (x>640)、下带 (y>480) 与右下角全部无法命中——生成坞/标题栏按钮死区
      await tester.tapAt(const Offset(780, 580));
      await tester.tapAt(const Offset(20, 580));
      await tester.tapAt(const Offset(780, 20));
      await tester.pump();
      expect(taps, 3);
    });

    /// 与 main.dart 同构：builder 包裹 Navigator，Overlay 在缩放坐标系内
    Widget wrapWithZoom(double zoom, Widget home) {
      return MaterialApp(
        builder: (context, child) =>
            AppUiZoomScope(zoom: zoom, child: child ?? const SizedBox.shrink()),
        home: home,
      );
    }

    testWidgets('globalToOverlayOf 把窗口全局坐标换算到 Overlay 布局坐标系', (tester) async {
      late Offset converted;
      await tester.pumpWidget(
        wrapWithZoom(
          1.5,
          Builder(
            builder: (context) => TextButton(
              // 首帧 build 期间 Overlay 尚未完成布局，须在帧后交互时取值
              onPressed: () {
                converted = globalToOverlayOf(context, const Offset(600, 450));
              },
              child: const Text('换算'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('换算'));

      // 800x600 窗口 150% 缩放：Overlay 坐标系为 533.33x400，全局 (600,450)
      // 应换算为 (400, 300)
      expect(converted.dx, closeTo(400, 0.5));
      expect(converted.dy, closeTo(300, 0.5));
    });

    testWidgets('zoom=1.0 时换算退化为恒等', (tester) async {
      late Offset converted;
      await tester.pumpWidget(
        wrapWithZoom(
          1.0,
          Builder(
            builder: (context) {
              converted = globalToOverlayOf(context, const Offset(123, 456));
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(converted, const Offset(123, 456));
    });

    testWidgets('右键菜单在 zoom=1.5 下精准落在指定的全局坐标处', (tester) async {
      await tester.pumpWidget(
        wrapWithZoom(
          1.5,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showStudioContextMenu(
                context,
                position: const Offset(300, 200),
                actions: [
                  ContextMenuItem(
                    icon: Icons.add_outlined,
                    label: '测试动作',
                    onTap: () {},
                  ),
                ],
              ),
              child: const Text('弹菜单'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('弹菜单'));
      await tester.pumpAndSettle();

      // 菜单本体最外层是 AnimatedScale (缩放动画对齐 topLeft，结算后即菜单左上角)
      final menuFinder = find.byType(AnimatedScale);
      expect(menuFinder, findsOneWidget);

      // 换算后菜单应精确出现在窗口全局坐标 (300, 200)——修复前会偏移到 (450, 300)
      final topLeft = tester.getTopLeft(menuFinder);
      expect(topLeft.dx, closeTo(300, 0.5));
      expect(topLeft.dy, closeTo(200, 0.5));
    });

    testWidgets('右键菜单在 zoom=0.8 下精准落在指定的全局坐标处', (tester) async {
      await tester.pumpWidget(
        wrapWithZoom(
          0.8,
          Builder(
            builder: (context) => TextButton(
              onPressed: () => showStudioContextMenu(
                context,
                position: const Offset(300, 200),
                actions: [
                  ContextMenuItem(
                    icon: Icons.add_outlined,
                    label: '测试动作',
                    onTap: () {},
                  ),
                ],
              ),
              child: const Text('弹菜单'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('弹菜单'));
      await tester.pumpAndSettle();

      final menuFinder = find.byType(AnimatedScale);
      expect(menuFinder, findsOneWidget);

      // 修复前会偏移到 (240, 160)
      final topLeft = tester.getTopLeft(menuFinder);
      expect(topLeft.dx, closeTo(300, 0.5));
      expect(topLeft.dy, closeTo(200, 0.5));
    });
  });
}
