import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:novelai_harness/core/harness/agent_harness.dart';
import 'package:novelai_harness/core/harness/presets/agent_preset.dart';
import 'package:novelai_harness/core/harness/providers/openai_provider.dart';
import 'package:novelai_harness/core/harness/tools/agent_tool.dart';
import 'package:novelai_harness/core/harness/types.dart';

const _image =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a4f8AAAAASUVORK5CYII=';

class _ImageTool extends AgentTool {
  _ImageTool()
    : super(
        name: 'image_test',
        label: '测试图片',
        description: 'Return an image.',
        parameters: const {'type': 'object', 'properties': <String, Object?>{}},
      );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async =>
      ToolResult(toolCallId: toolCallId, content: '返回的图片', imageBase64: _image);
}

http.StreamedResponse _sse(Map<String, Object?> delta) => http.StreamedResponse(
  http.ByteStream.fromBytes(
    utf8.encode(
      'data: ${jsonEncode({
        'choices': [
          {'delta': delta},
        ],
      })}\ndata: [DONE]\n',
    ),
  ),
  200,
);

List<Map<String, dynamic>> _messages(Map<String, dynamic> body) =>
    (body['messages'] as List).cast<Map<String, dynamic>>();

List<String> _images(List<Map<String, dynamic>> messages) => [
  for (final message in messages)
    if (message['content'] case final List<Object?> blocks)
      for (final block in blocks.whereType<Map<String, dynamic>>())
        if (block['image_url'] case final Map<String, dynamic> image)
          image['url'] as String,
];

void main() {
  for (final prompt in [false, true]) {
    test('${prompt ? '提示词' : '原生'}模式实际请求保留本轮用户/工具图片，跨轮不重复发送', () async {
      final requests = <Map<String, dynamic>>[];
      final client = MockClient.streaming((request, stream) async {
        requests.add(
          jsonDecode(utf8.decode(await stream.toBytes()))
              as Map<String, dynamic>,
        );
        if (requests.length == 1) {
          return _sse(
            prompt
                ? {
                    'content':
                        '<tool_call>{"name":"image_test","arguments":{}}</tool_call>\n<tool_call>{"name":"image_test","arguments":{}}</tool_call>',
                  }
                : {
                    'tool_calls': [
                      for (var i = 0; i < 2; i++)
                        {
                          'index': i,
                          'id': 'duplicate',
                          'function': {'name': 'image_test', 'arguments': '{}'},
                        },
                    ],
                  },
          );
        }
        return _sse({'content': 'done'});
      });
      final harness = AgentHarness(
        provider: OpenAiCompatibleProvider(
          baseUrl: 'https://relay.test/v1',
          apiKey: 'test',
          model: 'claude-test',
          promptToolUse: prompt,
          client: client,
        ),
        tools: ToolRegistry()..register(_ImageTool()),
        initialPreset: const AgentPreset(
          id: 'test',
          name: 'Test',
          description: '',
          systemPrompt: '',
          enabledToolNames: ['image_test'],
        ),
      );
      addTearDown(harness.dispose);
      addTearDown(client.close);
      final events = await harness
          .send('查看图片', images: const [AgentMessageImage(base64: _image)])
          .toList();
      expect(events.whereType<ErrorEvent>(), isEmpty);
      expect(requests, hasLength(2));
      expect(_images(_messages(requests.first)), [
        'data:image/png;base64,$_image',
      ]);
      final afterTools = _messages(requests[1]);
      expect(
        _images(afterTools),
        List.filled(3, 'data:image/png;base64,$_image'),
      );
      for (final message in afterTools) {
        if (message['content'] is List) expect(message['role'], 'user');
      }
      if (!prompt) {
        final toolIndexes = [
          for (var i = 0; i < afterTools.length; i++)
            if (afterTools[i]['role'] == 'tool') i,
        ];
        expect(toolIndexes, hasLength(2));
        expect(toolIndexes[1], toolIndexes[0] + 1);
        expect(afterTools[toolIndexes.last + 1]['role'], 'user');
        final calls = afterTools[toolIndexes.first - 1]['tool_calls'] as List;
        expect(calls.map((call) => (call as Map)['id']).toSet(), hasLength(2));
        for (var i = 0; i < 2; i++) {
          final result = afterTools[toolIndexes[i]];
          expect(result['content'], '返回的图片');
          expect(result['tool_call_id'], (calls[i] as Map)['id']);
        }
      } else {
        expect(requests[1].containsKey('tools'), isFalse);
        expect(afterTools.first['content'], contains('此兼容模式不关闭图像输入'));
      }

      final followUp = await harness.send('继续').toList();
      expect(followUp.whereType<ErrorEvent>(), isEmpty);
      expect(_images(_messages(requests.last)), isEmpty);
      expect(jsonEncode(requests.last), contains('图片附件已折叠'));
      expect(
        harness.messages
            .where((message) => message.role == AgentRole.tool)
            .every((message) => message.imageBase64 == _image),
        isTrue,
      );
    });
  }
}
