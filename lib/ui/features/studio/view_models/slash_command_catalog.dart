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
  SlashCommandDef('/upscale', '', '超分放大当前图片'),
  SlashCommandDef('/tag', '<关键词>', '查询 Danbooru 官方标签联想'),
  SlashCommandDef('/account', '', '查询账号等级与 V5 专属体力池'),
  SlashCommandDef('/clear', '', '清空对话历史'),
];

/// 生成 /help 帮助文本 (由指令目录渲染)
String buildSlashHelpText() =>
    '快捷指令说明：\n${kSlashCommands.map((c) => '• ${c.helpLine}').join('\n')}';

/// /nai 方向标志 → 官方分辨率对照
const Map<String, (int, int)> _slashResolutionFlags = {
  '--landscape': (1216, 832),
  '--portrait': (832, 1216),
  '--square': (1024, 1024),
  '--wallpaper': (1920, 1088),
};

/// 解析 /nai 提示词中的方向标志，返回剥离标志后的提示词与目标尺寸
/// (无标志时沿用当前工作台尺寸)
({String prompt, int width, int height}) parseSlashResolutionFlags(
  String args, {
  required int fallbackWidth,
  required int fallbackHeight,
}) {
  var prompt = args;
  var width = fallbackWidth;
  var height = fallbackHeight;
  for (final entry in _slashResolutionFlags.entries) {
    if (prompt.contains(entry.key)) {
      prompt = prompt.replaceAll(entry.key, '').trim();
      (width, height) = entry.value;
      break;
    }
  }
  return (prompt: prompt, width: width, height: height);
}
