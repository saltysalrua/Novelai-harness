/// 一条内置斜杠指令的定义 (指令名 / 参数提示 / 简要说明)
class SlashCommandDef {
  final String name;
  final String argsHint;
  final String description;

  const SlashCommandDef(this.name, this.argsHint, this.description);

  /// 补全列表主标题 (带参数提示)
  String get displayTitle => argsHint.isEmpty ? name : '$name $argsHint';

  /// /help 帮助列表的单行文案
  String get helpLine => argsHint.isEmpty
      ? '$name : $description'
      : '$name $argsHint : $description';
}

/// 内置斜杠指令目录 (单一数据源)
///
/// 输入框自动补全建议与 /help 帮助文本均由本表生成；
/// 各指令的执行逻辑在 StudioViewModel._handleSlashCommand 的 switch 中分发，
/// 新增指令时在两处各加一条即可 (本表 + 对应 case 分支)。
const List<SlashCommandDef> kSlashCommands = [
  SlashCommandDef('/help', '', '查看指令帮助列表'),
  SlashCommandDef('/params', '', '查看工作台当前生效的生图参数'),
  SlashCommandDef('/preset', '<名称>', '切换当前 Agent 预设'),
  SlashCommandDef('/skill', '<名称>', '按需加载并执行专业技能'),
  SlashCommandDef(
    '/nai',
    '<提示词>',
    '快速生成插画，支持 --landscape/--portrait/--square/--wallpaper 方向标志',
  ),
  SlashCommandDef('/upscale', '[2|4]', '超分放大当前图片'),
  SlashCommandDef('/tag', '<关键词>', '查询 Danbooru 官方标签联想'),
  SlashCommandDef('/account', '', '查询账号等级与 V5 专属体力池'),
  SlashCommandDef('/clear', '', '清空对话历史'),
];

/// 生成 /help 帮助文本 (由指令目录渲染)
String buildSlashHelpText() =>
    '快捷指令说明：\n${kSlashCommands.map((c) => '• ${c.helpLine}').join('\n')}';