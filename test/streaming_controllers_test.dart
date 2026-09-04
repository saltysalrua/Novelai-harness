import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/ui/features/studio/view_models/streaming_controllers.dart';

/// 等待一个真实 40ms 批量窗口过期 (真实计时器，普通 test() 环境可用)
Future<void> _flushWindow() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('StreamingTextController', () {
    test('连续增量合并进同一 40ms 批量窗口，只通知一次', () async {
      final controller = StreamingTextController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.appendThoughts('思');
      controller.appendThoughts('考');
      controller.appendContent('正');
      controller.appendContent('文');

      // 窗口内不立即通知
      expect(notifyCount, 0);
      await _flushWindow();

      expect(notifyCount, 1);
      expect(controller.thoughts, '思考');
      expect(controller.content, '正文');

      controller.dispose();
    });

    test('批量窗口结束后新增量再次调度刷新', () async {
      final controller = StreamingTextController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.appendContent('a');
      await _flushWindow();
      expect(notifyCount, 1);

      controller.appendContent('b');
      await _flushWindow();
      expect(notifyCount, 2);
      expect(controller.content, 'ab');

      controller.dispose();
    });

    test('setNotice 立即通知且无需等待批量窗口', () {
      final controller = StreamingTextController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.setNotice('请求失败自动重试 (1/3)');
      expect(notifyCount, 1);
      expect(controller.notice, '请求失败自动重试 (1/3)');
      expect(controller.hasNotice, isTrue);

      controller.dispose();
    });

    test('reset 清空全部文本并立即通知，挂起批次被取消', () async {
      final controller = StreamingTextController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.appendThoughts('残留');
      controller.setNotice('提示');
      expect(notifyCount, 1);

      controller.reset();
      expect(notifyCount, 2);
      expect(controller.thoughts, isEmpty);
      expect(controller.content, isEmpty);
      expect(controller.notice, isNull);
      expect(controller.hasNotice, isFalse);

      // 原挂起的批量刷新已被取消，不再产生额外通知
      await _flushWindow();
      expect(notifyCount, 2);

      controller.dispose();
    });

    test('空字符串增量不触发调度', () async {
      final controller = StreamingTextController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.appendThoughts('');
      controller.appendContent('');
      await _flushWindow();
      expect(notifyCount, 0);

      controller.dispose();
    });
  });

  group('LiveProgressController', () {
    test('begin 重置进度并通知', () {
      final controller = LiveProgressController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      final start = DateTime(2026, 1, 1);
      controller.begin(28, start);
      expect(notifyCount, 1);
      expect(controller.totalSteps, 28);
      expect(controller.currentStep, 0);
      expect(controller.progress, 0.0);
      expect(controller.previewBytes, isNull);
      expect(controller.startTime, start);

      controller.dispose();
    });

    test('updateFrame 更新帧数据并通知，progress 缺省按步数推算', () {
      final controller = LiveProgressController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.updateFrame(previewBytes: null, currentStep: 7, totalSteps: 28);
      expect(notifyCount, 1);
      expect(controller.currentStep, 7);
      expect(controller.previewBytes, isNull);
      expect(controller.progress, closeTo(7 / 28, 1e-9));

      controller.updateFrame(currentStep: 8, totalSteps: 28, progress: 0.5);
      expect(notifyCount, 2);
      expect(controller.progress, 0.5);

      controller.dispose();
    });

    test('complete 置满进度并清空预览，clear 归零', () {
      final controller = LiveProgressController();
      var notifyCount = 0;
      controller.addListener(() => notifyCount++);

      controller.begin(23, DateTime.now());
      controller.updateFrame(currentStep: 10, totalSteps: 23);
      controller.complete();
      expect(notifyCount, 3);
      expect(controller.previewBytes, isNull);
      expect(controller.progress, 1.0);

      controller.clear();
      expect(notifyCount, 4);
      expect(controller.currentStep, 0);
      expect(controller.progress, 0.0);

      controller.dispose();
    });
  });
}
