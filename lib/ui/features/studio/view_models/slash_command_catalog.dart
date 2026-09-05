import '../../../../l10n/app_localizations.dart';

/// 一条内置斜杠指令的定义 (指令名 / 参数提示 / 简要说明)
///
/// [description]/[argsHint] 为中文数据域兑底文案；界面展示经
/// slashCommandDescriptionOf / slashArgsHintOf 在 UI 层本地化。
class SlashCommandDef {
  final String name;
  final String argsHint;
  final String description;

  const SlashCommandDef(this.name, this.argsHint, this.description);

  /// 补全列表主标题 (带参数提示，中文兑底)
  String get displayTitle => argsHint.isEmpty ? name : '$name $argsHint';

  /// /help 帮助列表的单行文案 (中文兑底)
  String get helpLine => argsHint.isEmpty
      ? '$name : $description'
      : '$name $argsHint : $description';

  /// 本地化后的补全主标题 (带参数提示)
  String localizedDisplayTitle(AppLocalizations l10n) =>
      slashArgsHintOf(l10n, this).isEmpty
      ? name
      : '$name ${slashArgsHintOf(l10n, this)}';

  /// 本地化后的 /help 单行文案
  String localizedHelpLine(AppLocalizations l10n) {
    final hint = slashArgsHintOf(l10n, this);
    final desc = slashCommandDescriptionOf(l10n, this);
    return hint.isEmpty ? '$name : $desc' : '$name $hint : $desc';
  }
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
  SlashCommandDef('/compact', '', '手动压缩对话上下文 (摘要替换更早消息，原始消息仍保留)'),
  SlashCommandDef('/new', '<标题>', '新建一个空白会话 (可附带标题)'),
  SlashCommandDef('/undo', '', '撤销上一轮对话 (回复与参数修改一并回滚)'),
  SlashCommandDef('/rename', '<标题>', '重命名当前会话'),
  SlashCommandDef('/sessions', '', '列出已保存的会话'),
  SlashCommandDef('/clear', '', '清空对话历史'),
];

/// 生成 /help 帮助文本 (由指令目录渲染；传 l10n 时本地化，缺省中文兑底)
String buildSlashHelpText([AppLocalizations? l10n]) =>
    '${l10n?.slashHelpHeader ?? '快捷指令说明：'}\n'
    '${kSlashCommands.map((c) => '• ${l10n != null ? c.localizedHelpLine(l10n) : c.helpLine}').join('\n')}';

/// 指令说明的本地化解析 (UI 扩展层，未匹配时回退中文数据域文案)
String slashCommandDescriptionOf(AppLocalizations l10n, SlashCommandDef c) =>
    switch (c.name) {
      '/help' => l10n.slashDescHelp,
      '/params' => l10n.slashDescParams,
      '/preset' => l10n.slashDescPreset,
      '/skill' => l10n.slashDescSkill,
      '/nai' => l10n.slashDescNai,
      '/upscale' => l10n.slashDescUpscale,
      '/tag' => l10n.slashDescTag,
      '/account' => l10n.slashDescAccount,
      '/compact' => l10n.slashDescCompact,
      '/new' => l10n.slashDescNew,
      '/undo' => l10n.slashDescUndo,
      '/rename' => l10n.slashDescRename,
      '/sessions' => l10n.slashDescSessions,
      '/clear' => l10n.slashDescClear,
      _ => c.description,
    };

/// 指令参数提示的本地化解析 (未匹配时回退中文数据域提示)
String slashArgsHintOf(AppLocalizations l10n, SlashCommandDef c) =>
    switch (c.argsHint) {
      '<名称>' => l10n.slashArgsName,
      '<提示词>' => l10n.slashArgsPrompt,
      '<关键词>' => l10n.slashArgsKeyword,
      '<标题>' => l10n.slashArgsTitle,
      _ => c.argsHint,
    };

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
