import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/core/widgets/two_finger_scale.dart';

Matrix4 _transformOf(WidgetTester tester, Finder zoomable) {
  final transform = tester.widget<Transform>(
    find.descendant(of: zoomable, matching: find.byType(Transform)).first,
  );
  return transform.transform;
}

/// 独立双指捏合缩放容器 (无外层滚动)
Future<Finder> _pumpStandalone(WidgetTester tester) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 400,
            height: 400,
            child: TwoFingerPinchZoom(
              key: const Key('zoom'),
              child: const ColoredBox(key: Key('content'), color: Colors.red),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return find.byKey(const Key('zoom'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TwoFingerPinchZoom 独立容器', () {
    testWidgets('双指捏合放大并以焦点为不动点，单指拖拽不缩放', (tester) async {
      final zoomable = await _pumpStandalone(tester);

      // 单指拖拽：不产生任何缩放 (识别器不接受单指手势)
      final single = await tester.startGesture(const Offset(200, 200));
      await single.moveBy(const Offset(60, 40));
      await single.moveBy(const Offset(60, 40));
      await single.up();
      await tester.pump();
      var matrix = _transformOf(tester, zoomable);
      expect(matrix, Matrix4.identity());

      // 双指捏合：先各移 2px (低于判定阈值)，再对称拉开
      final topLeft = tester.getTopLeft(zoomable);
      final p1 = topLeft + const Offset(148, 200);
      final p2 = topLeft + const Offset(252, 200);
      final g1 = await tester.startGesture(p1);
      final g2 = await tester.startGesture(p2);
      await g1.moveBy(const Offset(-2, 0));
      await g2.moveBy(const Offset(2, 0));
      // 首次大位移触发接受并重建基线 (指距 168，焦点 (170, 200))
      await g1.moveBy(const Offset(-60, 0));
      // 对称拉开第二段：指距 228
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();

      matrix = _transformOf(tester, zoomable);
      final scale = matrix.storage[0];
      expect(scale, greaterThan(1.3), reason: '双指捏合应放大内容');
      expect(scale, lessThan(2.0));

      // 焦点不变性：手势起点焦点 (170, 200) 下的内容点在捏合后仍位于当前焦点下方
      // (两指位置最终为 86 / 314，中点 (200, 200)；矩阵在组件局部坐标系结算)
      final sceneNow = MatrixUtils.transformPoint(
        Matrix4.inverted(matrix),
        const Offset(200, 200),
      );
      expect(sceneNow.dx, closeTo(170, 0.5));
      expect(sceneNow.dy, closeTo(200, 0.5));

      await g1.up();
      await g2.up();
      await tester.pump();

      // 松手后缩放状态保持
      expect(_transformOf(tester, zoomable).storage[0], greaterThan(1.3));
    });

    testWidgets('捏合后双指平移受钳制，缩回 1 倍归位', (tester) async {
      final zoomable = await _pumpStandalone(tester);
      final topLeft = tester.getTopLeft(zoomable);
      final p1 = topLeft + const Offset(148, 200);
      final p2 = topLeft + const Offset(252, 200);
      final g1 = await tester.startGesture(p1);
      final g2 = await tester.startGesture(p2);
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();
      var matrix = _transformOf(tester, zoomable);
      final zoomedScale = matrix.storage[0];
      expect(zoomedScale, greaterThan(1.0));

      // 双指同步平移：内容跟随中点移动
      final txBeforePan = matrix.storage[12];
      await g1.moveBy(const Offset(30, 0));
      await g2.moveBy(const Offset(30, 0));
      await tester.pump();
      matrix = _transformOf(tester, zoomable);
      expect(matrix.storage[0], closeTo(zoomedScale, 0.001),
          reason: '纯平移不改变缩放');
      expect(
        matrix.storage[12],
        greaterThan(txBeforePan),
        reason: '双指同步右移应带动内容右移',
      );

      // 对称捏回：缩放倍数回落到 1 附近时矩阵归位
      await g1.moveBy(const Offset(80, 0));
      await g2.moveBy(const Offset(-80, 0));
      await tester.pump();
      matrix = _transformOf(tester, zoomable);
      expect(
        matrix,
        Matrix4.identity(),
        reason: '捏回最小倍时矩阵应整体归位',
      );

      await g1.up();
      await g2.up();
      await tester.pump();
    });

    testWidgets('捏合中途加入第三根手指不产生跳变', (tester) async {
      final zoomable = await _pumpStandalone(tester);
      final topLeft = tester.getTopLeft(zoomable);
      final g1 = await tester.startGesture(topLeft + const Offset(148, 200));
      final g2 = await tester.startGesture(topLeft + const Offset(252, 200));
      await g1.moveBy(const Offset(-60, 0));
      await g2.moveBy(const Offset(60, 0));
      await tester.pump();
      final matrixBefore = _transformOf(tester, zoomable);
      final scaleBefore = matrixBefore.storage[0];
      expect(scaleBefore, greaterThan(1.0));

      // 第三根手指落下并小幅移动：手指组合变化帧只重建基准
      final g3 = await tester.startGesture(topLeft + const Offset(200, 100));
      await g3.moveBy(const Offset(0, 20));
      await tester.pump();
      final matrixAfter = _transformOf(tester, zoomable);
      expect(matrixAfter.storage[0], closeTo(scaleBefore, 0.001),
          reason: '第三根手指加入不应引起缩放跳变');

      await g1.up();
      await g2.up();
      await g3.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('嵌套滚动容器 (不劫持单指滚动)', () {
    Future<ScrollController> pumpList(WidgetTester tester) async {
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                const SizedBox(height: 80, child: ColoredBox(color: Colors.blue)),
                SizedBox(
                  width: 400,
                  height: 400,
                  child: TwoFingerPinchZoom(
                    key: const Key('zoom'),
                    child: const ColoredBox(color: Colors.red),
                  ),
                ),
                const SizedBox(
                  height: 800,
                  child: ColoredBox(color: Colors.green),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return scrollController;
    }

    testWidgets('单指纵向拖拽滚动列表且不缩放卡片', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final zoomable = find.byKey(const Key('zoom'));
      final controller = await pumpList(tester);
      final topLeft = tester.getTopLeft(zoomable);
      final cardCenter = topLeft + const Offset(200, 200);

      // 列表先滚到卡片可见
      controller.position.jumpTo(40);
      await tester.pumpAndSettle();

      // 分步小位移：拖拽识别器接受竞技场后的移动才计入滚动，
      // 一次性大位移会被判定阈值吞掉
      final single = await tester.startGesture(cardCenter);
      for (var i = 0; i < 8; i++) {
        await single.moveBy(const Offset(0, -10));
      }
      await tester.pump();
      await single.up();
      await tester.pump();

      expect(
        controller.offset,
        greaterThan(40 + 40),
        reason: '单指拖拽应滚动列表 (判定阈值只吞掉前几步)',
      );
      expect(_transformOf(tester, zoomable), Matrix4.identity(),
          reason: '单指拖拽不得缩放卡片');
      expect(tester.takeException(), isNull);
    });

    testWidgets('双指纵向捏合缩放卡片且列表不滚动', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final zoomable = find.byKey(const Key('zoom'));
      final controller = await pumpList(tester);
      controller.position.jumpTo(40);
      await tester.pumpAndSettle();
      final topLeft = tester.getTopLeft(zoomable);
      final offsetBefore = controller.offset;

      // 上下分开捏合 (每根手指都有纵向位移，考验识别器能赢下竞技场)
      final g1 = await tester.startGesture(topLeft + const Offset(200, 150));
      final g2 = await tester.startGesture(topLeft + const Offset(200, 250));
      await g1.moveBy(const Offset(0, -60));
      await g2.moveBy(const Offset(0, 60));
      await tester.pump();

      final matrix = _transformOf(tester, zoomable);
      expect(matrix.storage[0], greaterThan(1.2), reason: '双指捏合应缩放卡片');
      expect(controller.offset, closeTo(offsetBefore, 0.5),
          reason: '捏合期间列表不得滚动');

      await g1.up();
      await g2.up();
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });
}