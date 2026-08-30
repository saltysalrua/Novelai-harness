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
         description: '按需加载指定 Skill 的完整专业规范、工作流与指令内容。当任务需要深入调用该 Skill 时调用。',
         parameters: {
           'type': 'object',
           'properties': {
             'skill_name': {'type': 'string', 'description': '要加载的技能标识或名称'},
           },
           'required': ['skill_name'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final name = args['skill_name'] as String? ?? '';
    if (name.trim().isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '错误：必须提供 skill_name 参数。',
        isError: true,
      );
    }

    final skill = _resolve(name);
    if (skill == null) {
      final available = _availableSkillIds().join(', ');
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到技能 "$name"。当前可用技能列表: $available',
        isError: true,
      );
    }

    final buffer = StringBuffer();
    buffer.writeln('<skill name="${skill.id}">');
    buffer.writeln('### 【${skill.name}】专业指令与工作流');
    buffer.writeln(skill.systemPrompt);
    buffer.writeln('</skill>');

    return ToolResult(
      toolCallId: toolCallId,
      content: buffer.toString().trim(),
    );
  }
}
