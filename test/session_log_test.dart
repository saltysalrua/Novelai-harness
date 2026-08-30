import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/core/harness/types.dart';
import 'package:novelai_harness/data/services/session_log_service.dart';

void main() {
  late Directory tempDir;
  late SessionLogService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('nai_session_test');
    service = SessionLogService();
    await service.init(baseDir: tempDir.path);
  });

  tearDown(() async {
    await service.flush();
    try {
      await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  AgentMessage userMsg(String text) =>
      AgentMessage(id: 'u1', role: AgentRole.user, content: text);

  AgentMessage assistantMsg({
    String content = '好的，这就来。',
    String thoughts = '',
    List<ToolCall>? toolCalls,
    TokenUsage? usage,
  }) => AgentMessage(
    id: 'a1',
    role: AgentRole.assistant,
    content: content,
    thoughts: thoughts,
    toolCalls: toolCalls,
    usage: usage,
  );

  AgentMessage toolMsg({
    String toolCallId = 'call_1',
    String toolName = 'generate_image',
    String content = '生成完成',
    bool isError = false,
  }) => AgentMessage(
    id: 't1',
    role: AgentRole.tool,
    content: content,
    toolCallId: toolCallId,
    toolName: toolName,
    isError: isError,
  );

  test('writes Pi session format header and entries', () async {
    service.recordModelChange('deepseek', 'deepseek-chat');
    service.recordThinkingLevelChange('high');
    service.recordMessage(userMsg('画一张猫娘'));
    service.recordMessage(
      assistantMsg(
        thoughts: '思考中...',
        toolCalls: [
          const ToolCall(
            id: 'call_1',
            name: 'generate_image',
            arguments: {'prompt': 'catgirl'},
          ),
        ],
        content: '',
      ),
      provider: 'deepseek',
      model: 'deepseek-chat',
    );
    service.recordMessage(toolMsg());
    await service.flush();

    final files = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .toList();
    expect(files.length, equals(1));

    final lines = files.first
        .readAsLinesSync()
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
    expect(lines.length, equals(6));

    // 1. 头部
    final header = lines[0];
    expect(header['type'], equals('session'));
    expect(header['version'], equals(3));
    expect(header['cwd'], isA<String>());

    // 2. model_change / thinking_level_change
    expect(lines[1]['type'], equals('model_change'));
    expect(lines[1]['provider'], equals('deepseek'));
    expect(lines[1]['modelId'], equals('deepseek-chat'));
    expect(lines[2]['type'], equals('thinking_level_change'));
    expect(lines[2]['thinkingLevel'], equals('high'));

    // 3. id/parentId 树链
    expect(lines[1]['parentId'], isNull);
    for (var i = 2; i < lines.length; i++) {
      expect(lines[i]['parentId'], equals(lines[i - 1]['id']));
      expect(lines[i]['id'], isA<String>());
    }

    // 4. 用户消息
    final userEntry = lines[3];
    expect(userEntry['type'], equals('message'));
    final userMsgJson = userEntry['message'] as Map<String, dynamic>;
    expect(userMsgJson['role'], equals('user'));
    expect((userMsgJson['content'] as List).first['text'], equals('画一张猫娘'));

    // 5. 助手消息: thinking + toolCall 内容块与元数据
    final asstEntry = lines[4];
    final asstMsgJson = asstEntry['message'] as Map<String, dynamic>;
    expect(asstMsgJson['role'], equals('assistant'));
    expect(asstMsgJson['provider'], equals('deepseek'));
    expect(asstMsgJson['model'], equals('deepseek-chat'));
    expect(asstMsgJson['stopReason'], equals('toolUse'));
    final parts = asstMsgJson['content'] as List;
    expect(parts[0]['type'], equals('thinking'));
    expect(parts[0]['thinking'], equals('思考中...'));
    expect(parts[1]['type'], equals('toolCall'));
    expect(parts[1]['name'], equals('generate_image'));
    expect(parts[1]['arguments'], equals({'prompt': 'catgirl'}));
  });

  test('tool result message maps to role=toolResult with metadata', () async {
    service.recordMessage(userMsg('生成'));
    service.recordMessage(
      toolMsg(content: '失败: 401', isError: true, toolName: 'upscale'),
    );
    await service.flush();

    final file = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .first;
    final lines = file
        .readAsLinesSync()
        .map((l) => jsonDecode(l) as Map<String, dynamic>)
        .toList();
    final toolEntry = lines.last;
    final msg = toolEntry['message'] as Map<String, dynamic>;
    expect(msg['role'], equals('toolResult'));
    expect(msg['toolCallId'], equals('call_1'));
    expect(msg['toolName'], equals('upscale'));
    expect(msg['isError'], isTrue);
    expect((msg['content'] as List).first['text'], equals('失败: 401'));
  });

  test('system messages are not persisted', () async {
    service.recordMessage(
      AgentMessage(id: 's1', role: AgentRole.system, content: 'system prompt'),
    );
    await service.flush();

    final file = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.jsonl'))
        .first;
    // 只剩 session 头
    expect(file.readAsLinesSync().length, equals(1));
  });

  test('loadLatestSession roundtrips messages', () async {
    service.recordMessage(userMsg('画一张猫娘'));
    service.recordMessage(
      assistantMsg(
        thoughts: '先想提示词',
        toolCalls: [
          const ToolCall(
            id: 'call_9',
            name: 'generate_image',
            arguments: {'prompt': 'catgirl', 'width': 832},
          ),
        ],
      ),
      provider: 'deepseek',
      model: 'deepseek-chat',
    );
    service.recordMessage(
      toolMsg(toolCallId: 'call_9', content: 'line1\nline2'),
    );
    service.recordMessage(assistantMsg(content: '完成啦'));
    await service.flush();

    final snapshot = service.loadLatestSession();
    expect(snapshot, isNotNull);
    expect(snapshot!.messages.length, equals(4));
    expect(snapshot.provider, isNull); // 未记录 model_change
    expect(snapshot.modelId, isNull);

    final restoredUser = snapshot.messages[0];
    expect(restoredUser.role, equals(AgentRole.user));
    expect(restoredUser.content, equals('画一张猫娘'));

    final restoredAsst = snapshot.messages[1];
    expect(restoredAsst.role, equals(AgentRole.assistant));
    expect(restoredAsst.thoughts, equals('先想提示词'));
    expect(restoredAsst.toolCalls!.length, equals(1));
    expect(restoredAsst.toolCalls!.first.name, equals('generate_image'));
    expect(restoredAsst.toolCalls!.first.arguments['width'], equals(832));

    final restoredTool = snapshot.messages[2];
    expect(restoredTool.role, equals(AgentRole.tool));
    expect(restoredTool.toolCallId, equals('call_9'));
    expect(restoredTool.toolName, equals('generate_image'));
    expect(restoredTool.content, equals('line1\nline2'));

    expect(snapshot.messages[3].content, equals('完成啦'));
  });

  test(
    'startNewSession creates fresh file and clear is not resurrected',
    () async {
      service.recordMessage(userMsg('旧会话'));
      await service.flush();

      service.startNewSession();
      await service.flush();

      // 新会话文件只有头部，loadLatestSession 找到的是最新文件 -> 无消息
      final files = tempDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.jsonl'))
          .toList();
      expect(files.length, equals(2));
      expect(service.loadLatestSession(), isNull);

      // 新消息写入新会话文件
      service.recordMessage(userMsg('新会话'));
      await service.flush();
      final snapshot = service.loadLatestSession();
      expect(snapshot!.messages.length, equals(1));
      expect(snapshot.messages.first.content, equals('新会话'));
    },
  );

  test('loadLatestSession captures model and thinking level', () async {
    service.recordModelChange('kimi', 'kimi-k3');
    service.recordThinkingLevelChange('low');
    service.recordMessage(userMsg('hi'));
    await service.flush();

    final snapshot = service.loadLatestSession();
    expect(snapshot!.provider, equals('kimi'));
    expect(snapshot.modelId, equals('kimi-k3'));
    expect(snapshot.thinkingLevel, equals('low'));
  });

  test('assistant usage roundtrips into sessionUsage aggregation', () async {
    service.recordModelChange('deepseek', 'deepseek-chat');
    service.recordMessage(userMsg('画猫娘'));
    service.recordMessage(
      AgentMessage(
        id: 'a_usage',
        role: AgentRole.assistant,
        content: '好的',
        usage: const TokenUsage(input: 1000, output: 500, cacheRead: 200),
      ),
      provider: 'deepseek',
      model: 'deepseek-chat',
    );
    // 另一个模型的用量
    service.recordModelChange('kimi', 'kimi-k3');
    service.recordMessage(
      AgentMessage(
        id: 'a_usage_2',
        role: AgentRole.assistant,
        content: '完成',
        usage: const TokenUsage(input: 300, output: 100),
      ),
      provider: 'kimi',
      model: 'kimi-k3',
    );
    // 零用量的消息不应计入聚合
    service.recordMessage(
      AgentMessage(id: 'a_usage_0', role: AgentRole.assistant, content: '无计量'),
      provider: 'kimi',
      model: 'kimi-k3',
    );
    await service.flush();

    final snapshot = service.loadLatestSession();
    expect(snapshot!.sessionUsage.length, equals(2));
    final deepseek = snapshot.sessionUsage['deepseek/deepseek-chat']!;
    expect(deepseek.input, equals(1000));
    expect(deepseek.output, equals(500));
    expect(deepseek.cacheRead, equals(200));
    expect(deepseek.total, equals(1700));
    final kimi = snapshot.sessionUsage['kimi/kimi-k3']!;
    expect(kimi.total, equals(400));

    // 消息本体也携带 usage 与 provider/model 元数据
    final usageMsg = snapshot.messages.firstWhere((m) => m.content == '好的');
    expect(usageMsg.usage!.input, equals(1000));
    expect(usageMsg.provider, equals('deepseek'));
    expect(usageMsg.model, equals('deepseek-chat'));
  });

  test('uninitialized service is a no-op', () {
    final idle = SessionLogService();
    idle.recordMessage(userMsg('hi'));
    idle.recordModelChange('p', 'm');
    idle.recordThinkingLevelChange('high');
    idle.startNewSession();
    expect(idle.loadLatestSession(), isNull);
  });

  test('listSessions accurately parses and returns sessions metadata', () async {
    // 1. 第一个会话
    service.recordMessage(userMsg('画一张银发红瞳少女'));
    service.recordMessage(
      assistantMsg(
        content: '好的，正在构思提示词。',
        usage: const TokenUsage(input: 100, output: 50),
      ),
      provider: 'deepseek',
      model: 'deepseek-chat',
    );
    await service.flush();

    // 2. 第二个会话
    final session2 = await service.createSession(title: '自定义会话二');
    service.recordMessage(userMsg('帮我优化负向提示词'));
    await service.flush();

    final sessions = await service.listSessions();
    expect(sessions.length, equals(2));

    // 最新修改的会话排在第一位
    expect(sessions.first.id, equals(session2.id));
    expect(sessions.first.title, equals('自定义会话二'));
    expect(sessions.first.messageCount, equals(1));
    expect(sessions.first.isActive, isTrue);

    // 第一个会话
    final firstSession = sessions.firstWhere((s) => s.id != session2.id);
    expect(firstSession.title, contains('银发红瞳少女'));
    expect(firstSession.messageCount, equals(2));
    expect(firstSession.totalTokens, equals(150));
    expect(firstSession.isActive, isFalse);
  });

  test('createSession, loadSession and deleteSession lifecycle', () async {
    service.recordMessage(userMsg('会话一消息'));
    await service.flush();
    final firstId = service.currentSessionId!;

    // 创建新会话
    final newSession = await service.createSession(title: '新建测试会话');
    expect(service.currentSessionId, equals(newSession.id));
    service.recordMessage(userMsg('会话二消息'));
    await service.flush();

    // 切换回会话一
    final snap1 = service.loadSession(firstId);
    expect(snap1, isNotNull);
    expect(snap1!.messages.length, equals(1));
    expect(snap1.messages.first.content, equals('会话一消息'));
    expect(service.currentSessionId, equals(firstId));

    // 删除会话二
    final deleted = await service.deleteSession(newSession.id);
    expect(deleted, isTrue);
    final remaining = await service.listSessions();
    expect(remaining.length, equals(1));
    expect(remaining.first.id, equals(firstId));
  });

  test('renameSession updates session title and writes session_info entry', () async {
    service.recordMessage(userMsg('原始提示词'));
    await service.flush();
    final sid = service.currentSessionId!;

    await service.renameSession(sid, '重命名后的会话标题');
    await service.flush();

    final sessions = await service.listSessions();
    expect(sessions.first.title, equals('重命名后的会话标题'));

    final snap = service.loadSession(sid);
    expect(snap!.sessionTitle, equals('重命名后的会话标题'));
  });

  test('rewindToMessageCount truncates session entries in JSONL', () async {
    service.recordMessage(userMsg('第一轮提问'));
    service.recordMessage(assistantMsg(content: '第一轮回答'));
    service.recordMessage(userMsg('第二轮提问'));
    service.recordMessage(assistantMsg(content: '第二轮回答'));
    await service.flush();

    expect(service.loadLatestSession()!.messages.length, equals(4));

    // 回溯截断至保留前 2 条消息 (即第一轮提问 + 回答)
    service.rewindToMessageCount(2);
    await service.flush();

    final snapshot = service.loadLatestSession();
    expect(snapshot, isNotNull);
    expect(snapshot!.messages.length, equals(2));
    expect(snapshot.messages[0].content, equals('第一轮提问'));
    expect(snapshot.messages[1].content, equals('第一轮回答'));

    // 继续在回溯后的位置写入新消息，验证链条延续正常
    service.recordMessage(userMsg('新的第二轮提问'));
    await service.flush();

    final updatedSnapshot = service.loadLatestSession();
    expect(updatedSnapshot!.messages.length, equals(3));
    expect(updatedSnapshot.messages[2].content, equals('新的第二轮提问'));
  });
}

