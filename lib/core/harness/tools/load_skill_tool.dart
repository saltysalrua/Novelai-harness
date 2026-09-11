import '../skills/skills.dart';
import '../types.dart';
import 'agent_tool.dart';

/// Skill 查询解析器函数类型
typedef SkillResolver = Skill? Function(String skillIdOrName);

/// 遵循 Pi 标准的 Skill 按需加载工具 (Progressive Disclosure)
///
/// 解析器与可用技能清单由外部注入，通常应按当前预设的 enabledSkillIds
/// 作用域化，防止模型加载预设未开放的技能。
class LoadSkillTool extends AgentTool {
  final SkillResolver _resolve;
  final List<String> Function() _availableSkillIds;

  LoadSkillTool({
    required SkillResolver skillResolver,
    required this._availableSkillIds,
  }) : _resolve = skillResolver,
       super(
         name: 'load_skill',
         label: '加载专业技能指令',
         description:
             '按需加载指定 Skill 的完整专业规范、工作流与指令内容。当任务需要深入调用该 Skill 时调用。'
             '需要多个技能时用 skill_names 数组一次加载，不要逐条多次调用。',
         parameters: {
           'type': 'object',
           'properties': {
             'skill_name': {'type': 'string', 'description': '要加载的技能标识或名称'},
             'skill_names': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量加载的技能标识或名称列表 (与 skill_name 可并用)',
             },
           },
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final names = <String>[];
    void collect(Object? raw) {
      if (raw is String && raw.trim().isNotEmpty) names.add(raw.trim());
    }

    collect(args['skill_name']);
    final many = args['skill_names'];
    if (many is List) {
      for (final item in many) {
        collect(item);
      }
    }
    if (names.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：必须提供 skill_name 参数。',
        isError: true,
      );
    }

    final blocks = <String>[];
    final missing = <String>[];
    for (final name in names.toSet()) {
      final skill = _resolve(name);
      if (skill == null) {
        missing.add(name);
        continue;
      }
      blocks.add(
        '<skill name="${skill.id}">\n'
        '### 【${skill.name}】专业指令与工作流\n'
        '${skill.systemPrompt}\n'
        '</skill>',
      );
    }

    final missingText = missing.isEmpty
        ? ''
        : '未找到技能 ${missing.map((n) => '"$n"').join('、')}。'
              '当前可用技能列表: ${_availableSkillIds().join(', ')}';
    if (blocks.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: missingText,
        isError: true,
      );
    }

    final buffer = StringBuffer(blocks.join('\n\n'));
    if (missingText.isNotEmpty) buffer.write('\n\n$missingText');
    return ToolResult(
      toolCallId: toolCallId,
      content: buffer.toString().trim(),
    );
  }
}
