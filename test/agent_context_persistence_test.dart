import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/context_memory.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/session_log_service.dart';
import 'package:novelai_harness/ui/features/studio/widgets/agent_chat_messages.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'agent_harness_test.dart' show MockLlmProvider;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('上下文配置默认主模型并可持久化独立选择与开关', () async {
    SharedPreferences.setMockInitialValues({});
    final service = ConfigService();
    final defaults = await service.loadConfig();
    expect(defaults.compactionProviderId, isEmpty);
    expect(defaults.agentBackgroundCompaction, isTrue);
    await service.saveConfig(
      defaults.copyWith(
        agentCompactionEnabled: false,
        agentBackgroundCompaction: false,
        compactionProviderId: 'provider',
        compactionModelId: 'summary-model',
      ),
    );
    final restored = await service.loadConfig();
    expect(restored.agentCompactionEnabled, isFalse);
    expect(restored.agentBackgroundCompaction, isFalse);
    expect(restored.compactionProviderId, 'provider');
    expect(restored.compactionModelId, 'summary-model');
  });

  test('摘要、笔记、编号持久化；回溯不复用编号；跨会话隔离', () async {
    final dir = Directory.systemTemp.createTempSync('agent-context-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final log = SessionLogService();
    await log.init(baseDir: dir.path);
    final provider = MockLlmProvider(
      (messages, _) => [
        ContentDeltaEvent(
          messages.first.id == 'summarization_system' ? '简短摘要' : '答复' * 300,
        ),
      ],
    );
    final h = AgentHarness(
      tools: ToolRegistry(),
      provider: provider,
      recorder: log,
    );
    h.onContextChanged = () => log.saveContextState(h.exportContextState());
    await h.send('第一问' * 300).toList();
    await h.send('第二问').toList();
    h.memory.addNote('保留的事实');
    h.memoryChanged();
    expect(await h.compactContext(force: true), isNotNull);
    await log.flush();
    final firstId = log.currentSessionId!;
    final file = log.currentSessionFile!;
    final snapshot = log.loadLatestSession()!;
    final restored = AgentHarness(tools: ToolRegistry(), provider: provider);
    restored.setMessages(snapshot.messages);
    restored.restoreContextState(log.loadContextState());
    expect(restored.compactionSummary, '简短摘要');
    expect(restored.memory.notes.values, ['保留的事实']);
    expect(restored.messages.map((m) => m.id), h.messages.map((m) => m.id));
    expect(restored.messages.last.replyNumber, 2);
    restored.rewindToMessage(restored.messages[1].id);
    await restored.send('分支问题').toList();
    expect(restored.messages.last.replyNumber, 3);
    final newSession = await log.createSession();
    expect(log.loadContextState(), isEmpty);
    restored.setMessages([]);
    expect(restored.memory.notes, isEmpty);
    expect(newSession.id, isNot(firstId));
    h.dispose();
    restored.dispose();
    expect(await log.deleteSession(firstId), isTrue);
    expect(File('${file.path}.context.json').existsSync(), isFalse);
  });

  test('过期分支检查点不污染其他消息树，笔记有容量与长度限制', () {
    final h = AgentHarness(tools: ToolRegistry());
    h.setMessages([
      AgentMessage(id: 'old', role: AgentRole.user, content: 'old'),
    ]);
    h.memory.addNote('旧分支');
    final state = h.exportContextState();
    h.setMessages([
      AgentMessage(id: 'new', role: AgentRole.user, content: 'new'),
    ]);
    h.restoreContextState(state);
    expect(h.memory.notes, isEmpty);
    final memory = ContextMemory();
    expect(() => memory.addNote(' '), throwsArgumentError);
    expect(() => memory.addNote('x' * 2001), throwsArgumentError);
    for (var i = 0; i < 64; i++) {
      memory.addNote('note $i');
    }
    expect(() => memory.addNote('overflow'), throwsStateError);
    memory.deleteNote(1);
    expect(memory.addNote('new'), 65);
    final restored = ContextMemory()..restore(memory.toJson());
    expect(restored.notes, memory.notes);
    h.dispose();
  });

  testWidgets('助手正文显示可引用的回复编号', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AssistantMessageItem(
            message: AgentMessage(
              id: 'a',
              role: AgentRole.assistant,
              content: '回复正文',
              replyNumber: 42,
            ),
          ),
        ),
      ),
    );
    expect(find.text('#42'), findsOneWidget);
    expect(find.text('回复正文'), findsOneWidget);
  });
}
