import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StudioViewModel viewModel;
  late Directory sessionBase;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    // 注入一次性干净会话目录：避免续接共享临时目录里历次运行残留的探针消息
    sessionBase = Directory.systemTemp.createTempSync('nai_reentry_test_');
    viewModel = StudioViewModel(sessionLogBaseDir: sessionBase.path);
    await viewModel.init();
  });

  tearDown(() {
    viewModel.dispose();
    try {
      sessionBase.deleteSync(recursive: true);
    } catch (_) {
      // 目录清理失败不影响断言
    }
  });

  // 注意：init() 会按 pi 语义续接磁盘上最新的会话文件，历史消息可能非空，
  // 因此断言按"本次发送的内容"过滤，不依赖消息总数。

  group('sendChatMessage 重入保护', () {
    test('流式进行中重复调用被静默忽略，第二条不落入消息流', () async {
      final first = viewModel.sendChatMessage('reentry-probe-A');
      // 第一次调用在首个 await 前已同步置位 _isChatStreaming，
      // 并发到达的第二条应被重入保护拦截
      final second = viewModel.sendChatMessage('reentry-probe-B');

      await first;
      await second;

      final userA = viewModel.messages
          .where(
            (m) => m.role == AgentRole.user && m.content == 'reentry-probe-A',
          )
          .length;
      final userB = viewModel.messages
          .where(
            (m) => m.role == AgentRole.user && m.content == 'reentry-probe-B',
          )
          .length;
      expect(userA, equals(1));
      expect(userB, equals(0));
      // 流式状态已复位
      expect(viewModel.isChatStreaming, isFalse);
      expect(viewModel.currentStreamingContent, isEmpty);
    });

    test('流式结束后可正常再次发送', () async {
      await viewModel.sendChatMessage('reentry-probe-C');
      expect(viewModel.isChatStreaming, isFalse);

      await viewModel.sendChatMessage('reentry-probe-D');
      final userC = viewModel.messages
          .where(
            (m) => m.role == AgentRole.user && m.content == 'reentry-probe-C',
          )
          .length;
      final userD = viewModel.messages
          .where(
            (m) => m.role == AgentRole.user && m.content == 'reentry-probe-D',
          )
          .length;
      expect(userC, equals(1));
      expect(userD, equals(1));
    });
  });
}
