import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_canvas_overlay.dart';
import 'package:novelai_harness/ui/features/studio/widgets/inpaint_page.dart';

// 1x1 红色 PNG
final kTestPngBytes = Uint8List.fromList([
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB0,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

NaiGeneratedImage _image(String id) => NaiGeneratedImage(
  id: id,
  bytes: kTestPngBytes,
  params: const NaiGenerationParams(prompt: 'p', width: 1024, height: 1024),
  seed: 1,
  isOpusFree: true,
  createdAt: DateTime.now(),
);

void main() {
  group('Inpaint UI 渲染与交互测试', () {
    late StudioViewModel viewModel;

    setUp(() {
      viewModel = StudioViewModel();
      viewModel.setInpaintSourceImage(_image('img-0'));
    });

    testWidgets('InpaintPage 成功渲染模式切换、几何卡片与滑块', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: InpaintPage(viewModel: viewModel)),
        ),
      );

      expect(find.text('修复设置'), findsOneWidget);
      expect(find.text('焦点特写'), findsOneWidget);
      expect(find.text('常规重绘'), findsOneWidget);
      expect(find.text('潜空间焦点几何'), findsOneWidget);
      expect(find.text('外延上下文 (px)'), findsOneWidget);
      expect(find.text('重绘强度'), findsOneWidget);
      expect(find.text('附加噪声'), findsOneWidget);
      // 执行入口统一在左侧生成坞，修复页不再携带「开始修复」按钮
      expect(find.text('开始修复'), findsNothing);

      await tester.tap(find.text('常规重绘'));
      await tester.pumpAndSettle();

      expect(viewModel.inpaintParams.mode, InpaintMode.standard);
    });

    testWidgets('修复画板渲染工具坞；无选区时不再显示默认框', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: InpaintRepairCanvas(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('框选'), findsOneWidget);
      expect(find.text('画笔'), findsOneWidget);
      expect(find.text('橡皮'), findsOneWidget);
      expect(find.text('清除蒙版'), findsOneWidget);
      // 选区与蒙版由 CustomPaint 绘制 (非 Text widget)
      expect(find.byType(CustomPaint), findsAtLeastNWidgets(1));
      // 无选区无描边：不画默认选区框与外延虚线框
      expect(find.text('上下文外延 +64px'), findsNothing);
      expect(viewModel.inpaintParams.selectionRect, isNull);

      // 框选出一个选区后，外延虚线框出现
      // 画布 800x600，顶部为工具坞预留 56px → 源图 contain 544x544 于 (128,56)
      final marquee = await tester.startGesture(const Offset(196, 124));
      await marquee.moveBy(const Offset(200, 200));
      await tester.pump();
      await marquee.up();
      await tester.pumpAndSettle();
      expect(find.text('上下文外延 +64px'), findsOneWidget);

      // 清除蒙版后选区框彻底消失 (不再弹回默认居中框)
      await tester.tap(find.text('清除蒙版'));
      await tester.pumpAndSettle();
      expect(viewModel.inpaintParams.selectionRect, isNull);
      expect(find.text('上下文外延 +64px'), findsNothing);
    });

    testWidgets('框选工具：空白处拖拽新建选区，选区内拖拽移动选区', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: InpaintRepairCanvas(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 画布 800x600 (顶部为工具坞预留 56px)，源图 1024x1024 → contain
      // 显示 544x544 居中于 (128, 56)

      // 1. 在空白处 (选区外) 拖拽新建选区
      final marquee = await tester.startGesture(const Offset(196, 124));
      await marquee.moveBy(const Offset(100, 100));
      await tester.pump();
      await marquee.up();
      await tester.pumpAndSettle();

      final created = viewModel.inpaintParams.selectionRect;
      expect(created, isNotNull);
      // 起点 (196,124) → 归一化 ((196-128)/544, (124-56)/544) = (0.125, 0.125)
      expect(created!.left, closeTo(0.125, 0.01));
      expect(created.top, closeTo(0.125, 0.01));
      // 终点 (296,224) → (0.3088, 0.3088)
      expect(created.right, closeTo(0.3088, 0.01));
      expect(created.bottom, closeTo(0.3088, 0.01));

      // 2. 在新选区内拖拽移动 (新选区屏幕坐标 196,124 - 296,224)
      final move = await tester.startGesture(const Offset(246, 174));
      await move.moveBy(const Offset(60, 60));
      await tester.pump();
      await move.up();
      await tester.pumpAndSettle();

      final moved = viewModel.inpaintParams.selectionRect!;
      // 位移 60px / 544px = 0.1103
      expect(moved.left, closeTo(0.125 + 60 / 544, 0.02));
      expect(moved.top, closeTo(0.125 + 60 / 544, 0.02));
      expect(moved.width, closeTo(created.width, 1e-6));
      expect(moved.height, closeTo(created.height, 1e-6));
    });

    testWidgets('画笔工具：自由绘制提交描边，橡皮可擦除', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: InpaintRepairCanvas(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 切换到画笔
      await tester.tap(find.text('画笔'));
      await tester.pumpAndSettle();
      expect(viewModel.inpaintTool, InpaintTool.brush);

      // 在图片区域内绘制一条描边
      final brush = await tester.startGesture(const Offset(200, 100));
      await brush.moveBy(const Offset(120, 80));
      await tester.pump();
      await brush.up();
      await tester.pumpAndSettle();

      expect(viewModel.inpaintParams.hasBrushMask, isTrue);
      expect(viewModel.inpaintParams.brushStrokes.length, 1);
      final stroke = viewModel.inpaintParams.brushStrokes.first;
      expect(stroke.points.length, greaterThanOrEqualTo(2));

      // 切换到橡皮：反向画笔在蒙版上打黑，而不是删描边
      await tester.tap(find.text('橡皮'));
      await tester.pumpAndSettle();
      expect(viewModel.inpaintTool, InpaintTool.eraser);

      final erase = await tester.startGesture(const Offset(260, 140));
      await erase.moveBy(const Offset(20, 0));
      await tester.pump();
      await erase.up();
      await tester.pumpAndSettle();

      // 橡皮提交的是 isEraser 描边 (原描边仍在列表中，由蒙版栅格化抵消)
      expect(viewModel.inpaintParams.brushStrokes.length, 2);
      expect(viewModel.inpaintParams.brushStrokes.last.isEraser, isTrue);
      // 蒙版有效性看栅格化结果，正向描边仍在列表中
      expect(viewModel.inpaintParams.hasBrushMask, isTrue);
    });

    testWidgets('画笔/橡皮单击即可盖章提交单点描边', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: InpaintRepairCanvas(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 画笔单击 = 盖章一个圆点 (单点描边)
      await tester.tap(find.text('画笔'));
      await tester.pumpAndSettle();
      final brushTap = await tester.startGesture(const Offset(300, 200));
      await tester.pump();
      await brushTap.up();
      await tester.pumpAndSettle();

      expect(viewModel.inpaintParams.brushStrokes.length, 1);
      expect(viewModel.inpaintParams.brushStrokes.first.points.length, 1);

      // 橡皮单击 = 抠一个洞 (单点反向描边)
      await tester.tap(find.text('橡皮'));
      await tester.pumpAndSettle();
      final eraseTap = await tester.startGesture(const Offset(300, 200));
      await tester.pump();
      await eraseTap.up();
      await tester.pumpAndSettle();

      expect(viewModel.inpaintParams.brushStrokes.length, 2);
      expect(viewModel.inpaintParams.brushStrokes.last.isEraser, isTrue);
      expect(viewModel.inpaintParams.brushStrokes.last.points.length, 1);
    });

    testWidgets('橡皮拖拽不改变外延裁剪框位置 (只做减法)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: InpaintRepairCanvas(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 先用画笔画一条描边，外延框出现并定位
      await tester.tap(find.text('画笔'));
      await tester.pumpAndSettle();
      final brush = await tester.startGesture(const Offset(200, 100));
      await brush.moveBy(const Offset(120, 80));
      await tester.pump();
      await brush.up();
      await tester.pumpAndSettle();

      final label = find.text('上下文外延 +64px');
      expect(label, findsOneWidget);
      final labelPos = tester.getTopLeft(label);

      // 切换橡皮在别处拖拽：外延框不应跟随橡皮轨迹移动
      await tester.tap(find.text('橡皮'));
      await tester.pumpAndSettle();
      final erase = await tester.startGesture(const Offset(480, 380));
      await erase.moveBy(const Offset(60, 40));
      await tester.pump();
      expect(tester.getTopLeft(label), labelPos);
      await erase.up();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(label), labelPos);
    });

    testWidgets('四角手柄可拖拽缩放选区 (State 级起点基准)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 800,
              height: 600,
              child: InpaintRepairCanvas(viewModel: viewModel),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 画一个选区：屏幕 (196,124)-(396,324)
      final marquee = await tester.startGesture(const Offset(196, 124));
      await marquee.moveBy(const Offset(200, 200));
      await tester.pump();
      await marquee.up();
      await tester.pumpAndSettle();
      final before = viewModel.inpaintParams.selectionRect!;
      expect(before.width, closeTo(200 / 544, 0.02));

      // 拖右下角手柄外扩 (BR corner 位于屏幕 (396,324))
      final handle = await tester.startGesture(const Offset(396, 324));
      await handle.moveBy(const Offset(60, 40));
      await tester.pump();
      await handle.up();
      await tester.pumpAndSettle();

      final after = viewModel.inpaintParams.selectionRect!;
      expect(after.right, greaterThan(before.right));
      expect(after.bottom, greaterThan(before.bottom));
      expect(after.left, closeTo(before.left, 1e-6));
      expect(after.top, closeTo(before.top, 1e-6));
    });

    testWidgets('发送到修复：图片右键入口切换页签并设为底图', (tester) async {
      final img2 = _image('img-1');
      viewModel.sendImageToInpaint(img2);
      expect(viewModel.activeSidebarTab, StudioSidebarTab.inpaint);
      expect(viewModel.inpaintSourceImage!.id, 'img-1');
    });

    testWidgets('批注选区发送到修复：选区与备注一并带入', (tester) async {
      final annotation = ImageAnnotation(
        id: 'ann-1',
        type: AnnotationType.rect,
        rect: const Rect.fromLTWH(0.1, 0.1, 0.2, 0.2),
        note: '修复这里的眼睛',
        createdAt: DateTime.now(),
      );
      viewModel.sendAnnotationToInpaint(_image('img-2'), annotation);

      expect(viewModel.activeSidebarTab, StudioSidebarTab.inpaint);
      expect(viewModel.inpaintSourceImage!.id, 'img-2');
      expect(viewModel.inpaintParams.selectionRect, annotation.rect);
      expect(viewModel.inpaintParams.customPrompt, '修复这里的眼睛');
      expect(viewModel.inpaintParams.useMainPrompt, isFalse);
    });
  });
}
