// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'NovelAI Harness';

  @override
  String get generateImage => '生成图片';

  @override
  String get startInpaint => '开始修复';

  @override
  String get startAiEdit => '开始 AI 编辑';

  @override
  String get abortGeneration => '终止生成';

  @override
  String get opusFree => 'Opus 免费';

  @override
  String get needAnlas => '需点数';

  @override
  String get v5Stamina => 'V5 体力';

  @override
  String get tabParameters => '参数设置';

  @override
  String get tabPrompts => '提示词';

  @override
  String get tabInpaint => '局部修复';

  @override
  String get tabLibrary => '词库';

  @override
  String get history => '历史记录';

  @override
  String get settings => '设置';

  @override
  String get save => '保存';

  @override
  String get cancel => '取消';

  @override
  String get confirm => '确定';

  @override
  String get clear => '清空';

  @override
  String get delete => '删除';

  @override
  String get copy => '复制';

  @override
  String get close => '关闭';

  @override
  String get import => '导入';

  @override
  String get export => '导出';

  @override
  String get settingsSectionAppearance => '外观';

  @override
  String get settingsThemeMode => '主题模式';

  @override
  String get settingsThemeModeSubtitle => '切换亮色/深色工作台外观，深色采用 Notion 极简暗调色板';

  @override
  String get themeModeSystem => '跟随系统';

  @override
  String get themeModeLight => '亮色';

  @override
  String get themeModeDark => '深色';

  @override
  String get settingsLanguage => '语言';

  @override
  String get settingsLanguageSubtitle => '切换界面显示语言；现阶段设置页优先接入，其余界面将分模块逐步迁移';

  @override
  String get localeSystem => '跟随系统';

  @override
  String get localeChinese => '中文';

  @override
  String get localeEnglish => 'English';

  @override
  String get settingsUiZoom => '界面缩放';

  @override
  String get settingsUiZoomSubtitle =>
      '整体缩放工作台界面；快捷键 Ctrl + = / Ctrl + - 步进，Ctrl + 0 重置';

  @override
  String get settingsSectionNovelaiService => 'NovelAI Service';

  @override
  String get settingsApiKeyTitle => 'NovelAI API Key';

  @override
  String get settingsApiKeySubtitle => '官方 API 凭证 (pst-...)，用于图像生成与体力池同步';

  @override
  String get settingsSaveDirTitle => '本地存储目录';

  @override
  String get settingsSaveDirSubtitle => '生成的高清图像与元数据自动保存至此路径';

  @override
  String get settingsSaveDirHint => '存储路径...';

  @override
  String get settingsChooseButton => '选择';

  @override
  String get settingsAutoSaveTitle => '自动保存生成图片';

  @override
  String get settingsAutoSaveSubtitleOn => '生成图片自动写入本地存储目录 (按导出设置处理元数据与水印)';

  @override
  String get settingsAutoSaveSubtitleOff =>
      '生成图片先存入缓存目录 (无水印)，在画板右下角点击保存按钮手动保存；超出历史上限的缓存图片自动删除';

  @override
  String get settingsStreamPreviewTitle => '实时生图预览';

  @override
  String get settingsStreamPreviewSubtitle =>
      '生图过程中接收并实时渲染中间去噪步数预览图 (Stream Preview)';

  @override
  String get settingsImagePersistenceTitle => '图片历史持久化';

  @override
  String get settingsImagePersistenceSubtitle => '应用重启后自动恢复画板历史中的生成图片记录';

  @override
  String get settingsMaxImagesTitle => '可持久化图像上限';

  @override
  String get settingsMaxImagesSubtitle => '限制本地画板历史中保留的最大图片数量';

  @override
  String settingsImageCount(int count) {
    return '$count 张';
  }

  @override
  String get settingsSectionTagAutocomplete => 'Danbooru Tag Autocomplete';

  @override
  String get settingsTagAutocompleteTitle => '标签智能自动补全';

  @override
  String get settingsTagAutocompleteSubtitle =>
      '输入提示词时自动弹出 32万+ Danbooru 词库悬浮联想建议';

  @override
  String get settingsDictUpdateTitle => '词库在线更新';

  @override
  String get settingsDictUpdateNowButton => '立即更新';

  @override
  String get settingsDictAutoCheckTitle => '启动时自动检查更新';

  @override
  String get settingsDictAutoCheckSubtitle =>
      '每日一次后台拉取最新词库 (ffdkj 每日构建，含新标签与中文翻译)';

  @override
  String get settingsTagTranslationsTitle => '显示标签中文释义';

  @override
  String get settingsTagTranslationsSubtitle => '在补全候选词列表与灵感库中展示对应的中文翻译释义';

  @override
  String get settingsTagColorsTitle => '标签分类着色高亮';

  @override
  String get settingsTagColorsSubtitle => '在提示词输入框中对画师、角色、作品、通用等标签施加分类色彩高亮';

  @override
  String dictOnlineInfo(int count, String date) {
    return '在线词库 $count 条 · 更新于 $date';
  }

  @override
  String dictBuiltinInfo(int count) {
    return '内置词库 $count 条';
  }

  @override
  String get dictBuiltinLoading => '内置词库 (加载中)';

  @override
  String get settingsSectionProtection => '保护';

  @override
  String get settingsOpusTitle => 'Opus 免点数保护';

  @override
  String get settingsOpusSubtitle =>
      '自动将默认参数限制在免费区间内 (像素 <= 1048576 且 步数 <= 28)';

  @override
  String dictUpdateFailed(String error) {
    return '更新失败: $error';
  }

  @override
  String get settingsModelSettings => '模型设置';

  @override
  String get settingsDeleteModel => '删除模型';

  @override
  String get settingsModelBadgeThinking => '思考';

  @override
  String get settingsModelBadgeMultimodal => '多模态';

  @override
  String get settingsModelBadgeImageOutput => '绘图';

  @override
  String settingsModelBadgeContext(String tokens) {
    return '$tokens 上下文';
  }

  @override
  String get settingsAddModel => '添加模型';

  @override
  String get settingsModelIdEmptyError => '模型 ID 不能为空';

  @override
  String get settingsModelDisplayName => '显示名称';

  @override
  String get settingsModelDisplayNameHint => '如 DeepSeek R1';

  @override
  String get settingsModelId => '模型 ID';

  @override
  String get settingsModelIdHint => '发送给 API 的模型标识';

  @override
  String get settingsModelTemperature => '温度 (Temperature)';

  @override
  String get settingsModelReasoning => '深度思考 (Reasoning)';

  @override
  String get settingsModelThinkingEffort => '思考等级';

  @override
  String get settingsModelMultimodal => '多模态 (图像输入)';

  @override
  String get settingsModelImageOutput => '图像输出 (绘图模型)';

  @override
  String get settingsModelContextWindow => '上下文窗口 (tokens)';

  @override
  String get settingsModelMaxTokens => '最大输出 (tokens)';

  @override
  String get settingsAdd => '添加';

  @override
  String get settingsCustomProviderDefaultName => '自定义供应商';

  @override
  String settingsNewProviderDefaultName(int index) {
    return '新供应商 $index';
  }

  @override
  String get settingsFetchModelsEnterBaseUrl => '请先填写有效的 API 基础 URL';

  @override
  String settingsFetchModelsSuccess(int count) {
    return '成功拉取 $count 个模型';
  }

  @override
  String settingsFetchModelsSuccessWithEnriched(int count, int enrichedCount) {
    return '成功拉取 $count 个模型，$enrichedCount 个已匹配 models.dev 元数据';
  }

  @override
  String get settingsEndpointUrlNotConfigured => '未配置 URL';

  @override
  String settingsFullEndpoint(String endpoint) {
    return '完整接口地址: $endpoint';
  }

  @override
  String get settingsSectionProviderSelection => 'Provider Selection';

  @override
  String get settingsSectionProviderProfile => 'Provider Profile & Endpoint';

  @override
  String get settingsSectionModels => 'Models';

  @override
  String get settingsSectionImageEdit => 'AI 整图编辑';

  @override
  String get settingsCurrentProvider => '当前供应商';

  @override
  String get settingsCurrentProviderSubtitle => '选择要配置的 AI 服务商，或添加自定义供应商';

  @override
  String get settingsNewProviderButton => '新建';

  @override
  String get settingsDeleteCurrentProviderTooltip => '删除当前供应商';

  @override
  String get settingsProviderName => '供应商名称';

  @override
  String get settingsProviderNameSubtitle => '在界面与下拉菜单中显示的自定义标识';

  @override
  String get settingsProviderNameHint => '如 DeepSeek / OpenAI / 本地 Ollama';

  @override
  String get settingsApiEndpointAndProtocol => 'API 接口与协议';

  @override
  String get settingsApiEndpointAndProtocolSubtitle => '服务基础 URL 与对应的通讯协议格式';

  @override
  String get settingsLlmApiKeyTitle => 'LLM API Key';

  @override
  String get settingsLlmApiKeySubtitle => '访问该供应商所需的身份密钥';

  @override
  String get settingsThinkingParamFormat => '思考参数格式';

  @override
  String get settingsThinkingParamFormatSubtitle =>
      '不同供应商用不同字段开关思维链，格式不匹配时思考会被静默丢弃；中转站请按其上游格式指定';

  @override
  String get settingsModelsListTitle => '模型列表';

  @override
  String get settingsModelsListSubtitle => '点击卡片切换当前模型，设置按钮调整模型参数与能力档案';

  @override
  String get settingsFetchingModels => '拉取中...';

  @override
  String get settingsFetchModelsOnline => '在线拉取模型';

  @override
  String get settingsImageEditModelTitle => '绘图模型';

  @override
  String get settingsImageEditModelSubtitle =>
      '修复页「AI 整图编辑」使用的供应商与模型 (仅列出绘图模型)，独立于对话 LLM；需选择具备图像输出能力的模型 (如 nano banana / gpt-image)';

  @override
  String get settingsDropdownNotConfigured => '未配置';

  @override
  String get settingsDropdownNoModelSelected => '未选择模型';

  @override
  String settingsImageEditUnrecognizedModel(String modelId) {
    return '$modelId (未识别为绘图模型)';
  }

  @override
  String get settingsImageEditTip =>
      '整图编辑不消耗 Anlas 点数，计费走绘图模型供应商；未识别到能力的模型可在模型设置中手动开启「图像输出」';

  @override
  String get settingsSearchModelHint => '搜索模型名称或 ID';

  @override
  String get settingsModelSortDefault => '默认顺序';

  @override
  String get settingsModelSortNameAsc => '名称 A-Z';

  @override
  String get settingsModelSortNameDesc => '名称 Z-A';

  @override
  String get settingsFilterImageOnly => '仅绘图模型';

  @override
  String get settingsFilterImageOnlyTooltip =>
      '仅显示具备图像输出能力的模型 (如 nano banana / gpt-image)';

  @override
  String settingsModelCount(int current, int total) {
    return '$current / $total 个模型';
  }

  @override
  String get settingsNoModelsInProvider => '当前供应商暂无模型';

  @override
  String get settingsNoModelsInProviderDesc => '点击上方\"在线拉取模型\"或\"添加模型\"';

  @override
  String settingsNoMatchingModels(String query) {
    return '没有匹配 \"$query\" 的模型';
  }

  @override
  String get settingsBadgeBuiltin => '内置';

  @override
  String get settingsBadgeCustom => '自定义';

  @override
  String get settingsSectionPresetSelection => 'Preset Selection';

  @override
  String get settingsSectionPresetProfile => 'Preset Profile & System Prompt';

  @override
  String get settingsSectionAvailableSkills => 'Available Skills';

  @override
  String get settingsSectionEnabledTools => 'Enabled Tools';

  @override
  String get settingsSectionModifiableParams => 'Modifiable Parameters';

  @override
  String get presetCurrentPreset => '当前预设';

  @override
  String get presetCurrentPresetSubtitle =>
      '选择要配置的 Agent 预设（系统提示词、可用技能、工具与参数权限）';

  @override
  String get presetBadgeActiveDefault => '当前默认';

  @override
  String get presetSetAsActiveDefault => '设为当前默认';

  @override
  String get presetNewButton => '新建';

  @override
  String get presetDeleteTooltip => '删除此预设';

  @override
  String get presetDefaultCustomName => '自定义预设';

  @override
  String presetNewName(int index) {
    return '新预设 $index';
  }

  @override
  String get presetNewDescription => '自定义 Agent 预设描述';

  @override
  String get presetNewSystemPrompt => '你是由 NovelAI Harness 驱动的绘画创作助手。';

  @override
  String presetDuplicateName(String name) {
    return '$name (副本)';
  }

  @override
  String presetExportSkillSuccess(String name) {
    return '已复制 Skill [$name] 为标准 SKILL.md 至剪贴板';
  }

  @override
  String get presetBuiltinNotice =>
      '内置预设为出厂定义，每次启动以代码为准自动刷新，不支持直接修改。需要定制请先点击「复制」生成副本。';

  @override
  String get presetDisplayName => '预设显示名称';

  @override
  String get presetDisplayNameHint => '如 V5 自然语言架构师';

  @override
  String get presetDescription => '预设描述';

  @override
  String get presetDescriptionHint => '如 擅长 V5 自然语言散文提示词...';

  @override
  String get presetSystemPrompt => '系统提示词 (System Prompt - 作为对话首要根基指令)';

  @override
  String get presetSystemPromptHint => '输入 AI 助手的核心人设与工作流指引...';

  @override
  String get presetImportSkill => '导入 SKILL.md';

  @override
  String get presetNewSkill => '新建 Skill';

  @override
  String get presetNewCustomTool => '新建自定义工具';

  @override
  String get presetParamPrompt => '提示词';

  @override
  String get presetParamNegativePrompt => '负向提示词';

  @override
  String get presetParamModel => '模型';

  @override
  String get presetParamResolution => '分辨率';

  @override
  String get presetParamWidth => '宽度';

  @override
  String get presetParamHeight => '高度';

  @override
  String get presetParamSteps => '步数';

  @override
  String get presetParamScale => 'CFG';

  @override
  String get presetParamCfgRescale => 'CFG Rescale';

  @override
  String get presetParamSampler => '采样器';

  @override
  String get presetParamNoiseSchedule => '噪声调度';

  @override
  String get presetParamQualityPreset => '质量标签';

  @override
  String get presetParamCharacterAiPosition => '角色定位模式';

  @override
  String get skillTooltipExport => '导出为 SKILL.md';

  @override
  String get skillTooltipEdit => '查看与编辑 Skill';

  @override
  String get skillTooltipDelete => '删除 Skill';

  @override
  String get skillNoDescription => '暂无描述';

  @override
  String get skillDialogImportTitle => '导入标准 SKILL.md';

  @override
  String get skillDialogNewTitle => '新建 Skill';

  @override
  String skillDialogEditTitle(String name) {
    return '编辑 Skill ($name)';
  }

  @override
  String get skillEditorTabStructured => '结构化编辑';

  @override
  String get skillEditorTabRaw => 'SKILL.md 源码';

  @override
  String get skillCopySkillMd => '复制 SKILL.md';

  @override
  String get skillCopySuccess => '已复制标准 SKILL.md 内容至剪贴板';

  @override
  String get skillSave => '保存 Skill';

  @override
  String get skillFieldId => '标识';

  @override
  String get skillFieldIdHint => '如 v5-architect';

  @override
  String get skillFieldName => '名称';

  @override
  String get skillFieldNameHint => '如 V5 自然语言架构师';

  @override
  String get skillFieldDescription => '技能描述';

  @override
  String get skillFieldDescriptionHint => '简要说明该技能擅长处理的任务场景...';

  @override
  String get skillFieldPrompt => '技能指令';

  @override
  String get skillFieldDisableInvocation => '禁止自动调用';

  @override
  String get skillFieldPromptHint => '输入该技能加载后生效的完整提示词与规范...';

  @override
  String get skillRawEditorHelp =>
      '粘贴或编辑标准 SKILL.md (含 YAML Frontmatter 与 Markdown Body)：';

  @override
  String get skillIdEmptyError => 'Skill 标识 (ID) 不能为空';

  @override
  String get toolTooltipEdit => '编辑工具';

  @override
  String get toolTooltipInspectSchema => '查看 Schema';

  @override
  String get toolTooltipDelete => '删除自定义工具';

  @override
  String get toolNoDescription => '暂无工具描述';

  @override
  String toolDialogSchemaTitle(String label) {
    return '工具 Schema ($label)';
  }

  @override
  String get toolDialogNewTitle => '新建自定义工具';

  @override
  String toolDialogEditTitle(String label) {
    return '编辑自定义工具 ($label)';
  }

  @override
  String get toolFieldId => '标识';

  @override
  String get toolFieldIdHint => '如 custom_tool';

  @override
  String get toolFieldName => '名称';

  @override
  String get toolFieldNameHint => '如 自定义工具';

  @override
  String get toolFieldDescription => '工具描述';

  @override
  String get toolFieldDescriptionHint => '清楚描述该工具的作用与使用时机...';

  @override
  String get toolFieldSchema => '参数 Schema';

  @override
  String get toolCopySchema => '复制 Schema';

  @override
  String get toolCopySchemaSuccess => '已复制 Schema JSON 至剪贴板';

  @override
  String get toolFieldOutputTemplate => '输出模板';

  @override
  String toolFieldOutputTemplateHint(String placeholder) {
    return '如：已成功执行并构建结果：$placeholder';
  }

  @override
  String get toolSave => '保存工具';

  @override
  String get toolNameEmptyError => '工具名称 (Name) 不能为空';

  @override
  String toolSchemaParseError(String error) {
    return 'Schema JSON 解析失败: $error';
  }

  @override
  String get settingsSaveButton => '保存设置';

  @override
  String get settingsSubtitleGeneral => '配置 NovelAI 绘图服务凭证、本地存储目录与 Opus 免点保护。';

  @override
  String get settingsSubtitleModels =>
      '按供应商管理大语言模型服务，在线拉取模型列表并自动匹配 models.dev 能力元数据。';

  @override
  String get settingsSubtitlePresets =>
      '管理 Agent 预设，配置系统提示词、按需加载的 Skill 库与生图参数控制权限。';

  @override
  String get settingsSubtitleDefaults => '配置启动时的出厂默认生图模型、采样算法与步数引导。';

  @override
  String get settingsSubtitleBill => '按周期统计各模型的 Token 用量账单，数据来自本地增量账本。';

  @override
  String get settingsSectionModelAndSampler => 'Model & Sampler';

  @override
  String get settingsDefaultModelTitle => '默认生图模型';

  @override
  String get settingsDefaultModelSubtitle => '应用启动或参数重置时的默认出厂模型';

  @override
  String get settingsDefaultSamplerTitle => '默认采样算法';

  @override
  String get settingsDefaultSamplerSubtitle => '生图时默认使用的降噪采样器';

  @override
  String get settingsDefaultNoiseScheduleTitle => '默认噪声调度';

  @override
  String get settingsDefaultNoiseScheduleSubtitle => '采样降噪过程中的时间步长调度算法';

  @override
  String get settingsSectionDefaultStepsAndScale => 'Default Steps & Scale';

  @override
  String get settingsDefaultStepsTitle => '默认步数 (Steps)';

  @override
  String get settingsDefaultStepsSubtitle => '初始采样迭代步数';

  @override
  String get settingsDefaultScaleTitle => '默认 CFG Scale';

  @override
  String settingsDefaultScaleSubtitle(String scale) {
    return '提示词引导强度 (当前: $scale)';
  }

  @override
  String get settingsSectionAgentLoop => 'Agent Loop';

  @override
  String get settingsAgentMaxTurnsTitle => 'Agent 最大工具轮数';

  @override
  String get settingsAgentMaxTurnsSubtitle => '单次对话允许的工具链式调用轮数，达到后自动收尾总结';

  @override
  String get settingsSectionUsageBill => 'Usage Bill';

  @override
  String get billPeriodToday => '今天';

  @override
  String get billPeriodLast7Days => '近 7 天';

  @override
  String get billPeriodLast30Days => '近 30 天';

  @override
  String get billPeriodAll => '全部';

  @override
  String billSummaryRequestsAndTokens(int requests, String tokens) {
    return '$requests 次请求 · 总计 $tokens tokens';
  }

  @override
  String get billEmptyRecords => '该周期内暂无用量记录';

  @override
  String get billTableHeaderModel => '模型';

  @override
  String get billTableHeaderRequests => '请求数';

  @override
  String get billTableHeaderInput => '输入';

  @override
  String get billTableHeaderOutput => '输出';

  @override
  String get billTableHeaderCacheRead => '缓存读';

  @override
  String get billTableHeaderHitRate => '命中率';

  @override
  String get billTableHeaderTotal => '总计';

  @override
  String get billTableTotalRow => '总计';

  @override
  String get paramsPageTitle => '参数设置';

  @override
  String get paramsPageSubtitle => '模型、分辨率与采样属性调节';

  @override
  String get paramsSectionModel => '模型';

  @override
  String get paramsSteps => 'Steps';

  @override
  String get paramsPromptGuidance => 'Prompt Guidance';

  @override
  String get paramsSectionSeed => 'Seed';

  @override
  String get paramsSeedHint => 'Enter a seed';

  @override
  String paramsSeedTooltip(String mode, String timing) {
    return '种子设置 ($mode · $timing)';
  }

  @override
  String get paramsSeedModeRandomShort => '随机';

  @override
  String get paramsSeedModeIncreaseShort => '递增';

  @override
  String get paramsSeedModeFixedShort => '固定';

  @override
  String get paramsSeedTimingBefore => '生成前';

  @override
  String get paramsSeedTimingAfter => '生成后';

  @override
  String get paramsSectionSampler => 'Sampler';

  @override
  String get paramsSeedModeGroup => '种子模式';

  @override
  String get paramsSeedModeRandomTitle => '1. Random (随机)';

  @override
  String get paramsSeedModeRandomSubtitle => '生图时自动生成全新随机种子';

  @override
  String get paramsSeedModeIncreaseTitle => '2. Increase (递增)';

  @override
  String get paramsSeedModeIncreaseSubtitle => '生图时种子数值自动 +1';

  @override
  String get paramsSeedModeFixedTitle => '3. Fixed (固定)';

  @override
  String get paramsSeedModeFixedSubtitle => '保持当前设置的种子数值不变';

  @override
  String get paramsSeedTimingGroup => '生成控制';

  @override
  String get paramsSeedRandomizeNow => '立即随机种子';

  @override
  String get paramsSeedResetRandom => '清空重置为随机 (-1)';

  @override
  String get paramsSectionAdvanced => 'Advanced Settings';

  @override
  String get paramsPromptGuidanceRescale => 'Prompt Guidance Rescale';

  @override
  String get paramsSectionNoiseSchedule => 'Noise Schedule';

  @override
  String get paramsStripMetadata => '删除元数据';

  @override
  String get paramsStripMetadataSubtitle => '导出与复制时抹除所有生成参数与隐写';

  @override
  String get paramsAddWatermark => '添加水印';

  @override
  String get paramsAddWatermarkSubtitle => '仅在复制/下载时生效，UI 画板不显示';

  @override
  String get paramsKeepOriginalImage => '保持原图像';

  @override
  String get paramsKeepOriginalImageSubtitle => '生图落盘时额外保存一份纯净原图 (_raw.png)';

  @override
  String get resolutionTitle => '分辨率';

  @override
  String get resolutionOrientationLandscape => 'Landscape';

  @override
  String get resolutionOrientationPortrait => 'Portrait';

  @override
  String get resolutionOrientationSquare => 'Square';

  @override
  String get resolutionOrientationSquareDisabled =>
      'Square (Wallpaper 暂无 1:1 比例)';

  @override
  String get resolutionSwapTooltip => 'Swap';

  @override
  String watermarkPickImageFailed(String error) {
    return '选择图片失败: $error';
  }

  @override
  String get watermarkPositionTopLeft => '左上';

  @override
  String get watermarkPositionTopRight => '右上';

  @override
  String get watermarkPositionCenter => '居中';

  @override
  String get watermarkPositionBottomLeft => '左下';

  @override
  String get watermarkPositionBottomRight => '右下';

  @override
  String get watermarkSmartPositionApplied => '已按低信息区域智能选位';

  @override
  String get watermarkSmartPositionNoImage => '画板暂无图片，无法智能选位';

  @override
  String get watermarkPositionTitle => '水印位置';

  @override
  String get watermarkSmartPositionTooltip => '智能选位：分析当前画板图像，把水印放到细节最少的区域';

  @override
  String get watermarkPositionPillTooltip => '在画板上拖动定位水印 (或按 ESC 退出)';

  @override
  String watermarkPositionPillLabel(String position) {
    return '位置: $position';
  }

  @override
  String get watermarkAutoPosition => '自动选位';

  @override
  String get watermarkAutoPositionSubtitle => '每次合成时分析图像，自动放入信息量最低的区域';

  @override
  String get watermarkAutoContrast => '自动对比度';

  @override
  String get watermarkAutoContrastSubtitle => '按水印下方背景亮度自动加深或提亮，保证可见';

  @override
  String get watermarkScalePercent => '水印缩放 (%)';

  @override
  String get watermarkOpacityPercent => '不透明度 (%)';

  @override
  String get watermarkMarginPercent => '边距比例 (%)';

  @override
  String get watermarkBlindTitle => '盲水印';

  @override
  String get watermarkBlindSubtitle => '频域隐形水印，肉眼不可见；粘贴图片到元数据弹窗可提取';

  @override
  String get watermarkBlindEnable => '启用';

  @override
  String get watermarkBlindTextHint => '签名 / 版权信息文本';

  @override
  String get watermarkBlindStrength => '盲水印强度';

  @override
  String get watermarkLoadedImage => '已加载水印图片';

  @override
  String get watermarkEffectiveOnExport => '仅在复制/下载时合成生效';

  @override
  String get watermarkChangeImageTooltip => '更换图片';

  @override
  String get watermarkClearImageTooltip => '清除水印图片';

  @override
  String get watermarkSelectLocalImage => '点击选择本地水印图片 (PNG/JPG)';

  @override
  String watermarkOverlayScale(String scale) {
    return '缩放: $scale%';
  }

  @override
  String watermarkOverlayPosition(int x, int y) {
    return '位置: $x%, $y%';
  }

  @override
  String get promptsPageTitle => '提示词管理';

  @override
  String get promptsPageSubtitle => '正向提示词、负面排除词与全局固定词缀';

  @override
  String get promptsCorePromptHint =>
      '输入核心提示词或自然语言散文描述，如: 1girl, solo, silver hair, masterpiece...';

  @override
  String get promptsSwitchToTabbedMode => '切换为标签页模式';

  @override
  String get promptsCustomUndesiredHint =>
      '输入自定义排除词，如: bad hands, blurry, extra limbs...';

  @override
  String get promptsSwitchToStackedMode => '切换为垂直并排模式';

  @override
  String get promptsTabbedPromptHint =>
      '输入核心提示词或自然语言散文描述，如: 1girl, solo, silver hair...';

  @override
  String get promptsTabbedUndesiredHint =>
      '排除不需要的特征与缺陷，如: lowres, bad anatomy, bad hands...';

  @override
  String get promptsResizePromptTooltip => '拖动调整提示词输入区高度 (双击重置)';

  @override
  String get promptsIncreaseWeightTooltip => '增加标签数值权重 (Ctrl+↑，格式 x.x::tag::)';

  @override
  String get promptsDecreaseWeightTooltip => '降低标签数值权重 (Ctrl+↓，格式 x.x::tag::)';

  @override
  String get promptsToggleDisabledTooltip => '切换禁用状态 (Ctrl+/)';

  @override
  String get promptsFormatTooltip => '格式化与SD语法转换 (Ctrl+Shift+F)';

  @override
  String get promptsTagBrowserTooltip => '打开 Danbooru 标签灵感库';

  @override
  String get promptsAffixesHint => '全局固定前置与后置词缀';

  @override
  String get charPromptDeckTabCharacter => '多角色提示词';

  @override
  String get charPromptDeckTabAffixes => '固定词缀';

  @override
  String get charPromptEnabled => '已启用';

  @override
  String get charPromptDisabled => '已停用';

  @override
  String get charPromptPositionAi => 'AI 自动';

  @override
  String get charPromptPositionCustom => '自定义';

  @override
  String get charPromptIsolationHint => '独立角色物理隔离';

  @override
  String get charPromptUnsupportedModel =>
      '当前模型不支持角色提示词 (仅 V4 及以上模型生效)，下方配置将保留但不会参与生成。';

  @override
  String get charPromptEmptyTitle => '暂无独立角色提示词';

  @override
  String get charPromptEmptyDescription =>
      '点击右上角「女 / 男 / 其他」预设按钮即可开启多角色防串色隔离生图';

  @override
  String get charPromptExitCanvasEditTooltip => '退出画板位置编辑';

  @override
  String get charPromptEnterCanvasEditTooltip => '在中间画板编辑角色位置';

  @override
  String get charPromptCanvasEditing => '编辑中';

  @override
  String get charPromptCanvasEdit => '画板编辑';

  @override
  String get charPromptAddFemaleTooltip => '添加女角色 (初始提示词 girl)';

  @override
  String get charPromptAddMaleTooltip => '添加男角色 (初始提示词 boy)';

  @override
  String get charPromptAddOtherTooltip => '添加其他角色 (初始提示词留空)';

  @override
  String get charPromptLimitReached => '已达上限';

  @override
  String get charPromptGenderFemale => '女';

  @override
  String get charPromptGenderMale => '男';

  @override
  String get charPromptGenderOther => '其他';

  @override
  String charPromptDefaultName(int index) {
    return '角色 $index';
  }

  @override
  String get charPromptNameHint => '角色名称 (可选)';

  @override
  String get charPromptSaveToLibraryTooltip => '保存角色到词库';

  @override
  String get charPromptDeleteTooltip => '删除该角色';

  @override
  String get charPromptEnable => '启用';

  @override
  String get charPromptDisable => '停用';

  @override
  String get charPromptPromptHint =>
      '角色正向提示词，如: 1girl, silver hair, twintails, smile...';

  @override
  String get charPromptResizePromptTooltip => '拖动调整正向提示词高度 (双击重置)';

  @override
  String get charPromptNegativePromptHint =>
      '角色负面提示词 (可选)，如: bad hands, blurry...';

  @override
  String get charPromptResizeNegativeTooltip => '拖动调整负面提示词高度 (双击重置)';

  @override
  String get affixPrefixTitle => '前置词 (放置于主提示词最前)';

  @override
  String get affixResizePrefixTooltip => '拖动调整前置词高度 (双击重置)';

  @override
  String get affixSuffixTitle => '后缀词 (放置于主提示词最后)';

  @override
  String get affixResizeSuffixTooltip => '拖动调整后缀词高度 (双击重置)';

  @override
  String get annotHistoryTitle => 'History ';

  @override
  String get annotHistoryEmpty => '无图片';

  @override
  String get annotHistoryAddedAsReference => '已将历史图片添加为大画布参考图';

  @override
  String get annotHistoryImportTooltip => '导入本地图片为参考图';

  @override
  String get annotHistoryImportImage => '导入图片';

  @override
  String get inpaintPageTitle => '修复设置';

  @override
  String get inpaintPageSubtitle => '局部重绘与高精度潜空间焦点特写';

  @override
  String get inpaintSectionMode => '修复模式';

  @override
  String get inpaintModeFocus => '焦点特写';

  @override
  String get inpaintModeFocusSubtitle => '超采样无损回贴';

  @override
  String get inpaintModeStandard => '常规重绘';

  @override
  String get inpaintModeStandardSubtitle => '整图尺度重绘';

  @override
  String get inpaintModeAiEdit => 'AI 整图编辑';

  @override
  String get inpaintModeAiEditSubtitle => '外部绘图模型重绘';

  @override
  String get inpaintAiEditAspectRatio => '生图比例';

  @override
  String get inpaintAiEditFollowSource => '跟随原图';

  @override
  String get inpaintAiEditResolution => '生图分辨率';

  @override
  String get inpaintAiEditDefaultResolution => '默认';

  @override
  String get inpaintContextPadding => '外延上下文 (px)';

  @override
  String get inpaintStrength => '重绘强度';

  @override
  String get inpaintNoise => '附加噪声';

  @override
  String get inpaintSectionInstruction => '修改指令设置';

  @override
  String get inpaintSectionPrompt => '提示词设置';

  @override
  String get inpaintReuseMainPromptAsInstruction => '复用主工作台正向词作为指令';

  @override
  String get inpaintReuseMainPrompt => '复用主工作台正向词';

  @override
  String get inpaintCustomInstruction => '自定义修改指令';

  @override
  String get inpaintCustomPrompt => '修复专属正向词';

  @override
  String get inpaintInstructionHint => '输入自然语言修改指令，如: 把背景换成夕阳下的海滩...';

  @override
  String get inpaintPromptHint => '输入修复专属正向提示词...';

  @override
  String get inpaintMainPrompt => '主工作台正向词';

  @override
  String get inpaintMainNegativePrompt => '主工作台负向词';

  @override
  String get inpaintReuseMainNegative => '复用主工作台负向词';

  @override
  String get inpaintCustomNegative => '修复专属负向词';

  @override
  String get inpaintNegativePromptHint => '输入修复专属负向提示词...';

  @override
  String get inpaintImageModel => '绘图模型';

  @override
  String get inpaintConsumeQuota => '消耗绘图模型额度';

  @override
  String get inpaintProvider => '供应商';

  @override
  String get inpaintModel => '模型';

  @override
  String get inpaintNoModelConfigured =>
      '未配置绘图模型。请到设置 → Models 页「AI 整图编辑」选择具备图像输出能力的模型供应商与模型 (如 nano banana / gpt-image)。';

  @override
  String get inpaintLatentFocusGeometry => '潜空间焦点几何';

  @override
  String get inpaintRequiresPoints => '需消耗点数';

  @override
  String get inpaintTargetSelection => '目标选区';

  @override
  String get inpaintContextCrop => '上下文外延';

  @override
  String get inpaintRequestResolution => '请求分辨率';

  @override
  String inpaintSupersample(String scale) {
    return '${scale}x 超采样';
  }

  @override
  String inpaintReusedLabel(String label) {
    return '已复用 $label';
  }

  @override
  String get inpaintReusedPromptEmpty => '（内容为空，可至提示词管理页配置）';

  @override
  String get inpaintOverlayEmptyHint => '生成或选择一张图片后即可开始局部修复';

  @override
  String inpaintOverlayContextCrop(int padding) {
    return '上下文外延 +${padding}px';
  }

  @override
  String get inpaintOverlayInProgress => '局部修复中...';

  @override
  String get inpaintOverlayAiEditHint => 'AI 整图编辑 · 整张图片重绘，无需框选区域';

  @override
  String get inpaintToolRect => '框选';

  @override
  String get inpaintToolBrush => '画笔';

  @override
  String get inpaintToolEraser => '橡皮';

  @override
  String get inpaintClearMask => '清除蒙版';

  @override
  String canvasImportedReference(String fileName) {
    return '已导入参考图: $fileName';
  }

  @override
  String get canvasDropTargetTitle => '松开鼠标导入图片 (自动识别生成元数据)';

  @override
  String get canvasCopiedRawImage => '已复制原图像到剪贴板';

  @override
  String get canvasCopiedImage => '已复制图像到剪贴板';

  @override
  String get canvasCopyImageFailed => '复制图像失败';

  @override
  String get canvasActionAddAnnotation => '添加批注';

  @override
  String canvasActionViewAnnotation(int count) {
    return '查看批注 ($count)';
  }

  @override
  String get canvasActionSendToInpaint => '发送到修复';

  @override
  String get canvasActionUpscale => '超分放大';

  @override
  String get canvasActionCopyImage => '复制图像';

  @override
  String get canvasActionCopyRawImage => '复制原图像';

  @override
  String get canvasActionCopyPrompt => '复制提示词';

  @override
  String get canvasCopiedPrompt => '已复制提示词到剪贴板';

  @override
  String get canvasActionReuseParams => '复用参数';

  @override
  String get canvasAppliedParams => '已应用该图参数至左侧面板';

  @override
  String get canvasActionViewLightbox => '查看大图';

  @override
  String get canvasActionDeleteFromHistory => '从历史记录删除';

  @override
  String get canvasDeletedFromHistory => '已从历史记录删除图片';

  @override
  String get canvasActionClearHistory => '清空历史记录';

  @override
  String get canvasClearedHistory => '已清空历史记录';

  @override
  String canvasClearHistoryAutoSaveMessage(int count) {
    return '确定要清空画板历史中的 $count 张图片吗？仅清空界面记录，本地已保存的图片文件会保留，此操作无法撤销。';
  }

  @override
  String canvasClearHistoryManualSaveMessage(int count) {
    return '确定要清空历史中的 $count 张图片吗？缓存中未保存的图片会被删除，已手动保存到存储目录的文件会保留，此操作无法撤销。';
  }

  @override
  String get canvasHistoryEmpty => '暂无历史';

  @override
  String get canvasCopySeedTooltip => '点击复制随机种子';

  @override
  String get canvasCopiedSeed => '已复制种子到剪贴板';

  @override
  String get canvasEnterAnnotationTooltip => '进入画板批注模式 (圈选/锚点/整图)';

  @override
  String get canvasAnnotate => '批注';

  @override
  String canvasAnnotateWithCount(int count) {
    return '批注 ($count)';
  }

  @override
  String get canvasSaveButtonTooltip => '保存当前图片到本地存储目录 (按导出设置处理元数据与水印)';

  @override
  String canvasSavedImage(String path) {
    return '已保存: $path';
  }

  @override
  String get canvasSaveFailed => '保存失败，请检查存储目录设置';

  @override
  String get canvasSaveImage => '保存图片';

  @override
  String get canvasUnseenLatestBanner => '已生成新图片 · 点击查看最新';

  @override
  String get canvasOpenHistoryTooltip => '展开历史记录';

  @override
  String get canvasEmptyTitle => '画板暂无图像';

  @override
  String get canvasEmptyDescription => '可在左侧配置参数后生成图片，历史记录将以垂直图像流展示';

  @override
  String get metadataBlindWatermarkContent => '盲水印内容';

  @override
  String get metadataBlindWatermarkNotFound => '未检测到盲水印';

  @override
  String get metadataDialogTitle => '图像元数据读取';

  @override
  String get metadataPromptTitle => '正向提示词 (Prompt)';

  @override
  String get metadataCopiedPrompt => '已复制正向提示词';

  @override
  String get metadataNegativePromptTitle => '负向提示词 (Negative Prompt)';

  @override
  String get metadataCopiedNegativePrompt => '已复制负向提示词';

  @override
  String get metadataDimensionAuto => '自动';

  @override
  String metadataDimensions(String width, String height) {
    return '尺寸: $width x $height';
  }

  @override
  String get metadataModelUnknown => '未知模型';

  @override
  String get metadataSamplerDefault => '默认';

  @override
  String metadataModelAndSampler(String model, String sampler) {
    return '模型: $model  ·  采样: $sampler';
  }

  @override
  String metadataSeedLabel(String seed) {
    return '种子: $seed';
  }

  @override
  String get metadataCharacterPromptsTitle => '多角色提示词 (Character Prompts)';

  @override
  String metadataCharacterIndex(int index) {
    return '角色 $index';
  }

  @override
  String metadataNegativePrefix(String negative) {
    return '负向: $negative';
  }

  @override
  String get metadataParametersTitle => '生成参数';

  @override
  String get metadataParamModel => '模型';

  @override
  String get metadataParamUnknown => '未知';

  @override
  String get metadataParamSampler => '采样算法';

  @override
  String get metadataParamDefault => '默认';

  @override
  String get metadataParamSteps => '步数';

  @override
  String get metadataParamSeed => '种子 (Seed)';

  @override
  String get metadataParamSeedRandom => '随机';

  @override
  String get metadataParamNoiseSchedule => '噪声调度';

  @override
  String get metadataParamQualityPreset => '质量预设';

  @override
  String get metadataParamUcPreset => 'UC 预设';

  @override
  String get metadataParamTransparentBg => '透明背景';

  @override
  String get metadataParamEnabled => '开启';

  @override
  String get metadataRawJsonTitle => '原始元数据 (Raw JSON / Text)';

  @override
  String get metadataCopyRawTooltip => '复制原始文本';

  @override
  String get metadataCopiedRaw => '已复制原始元数据';

  @override
  String get metadataExtractBlindWatermark => '提取盲水印';

  @override
  String get metadataImportAsReference => '作为参考图导入';

  @override
  String get metadataImportedReference => '已导入参考图';

  @override
  String get metadataApplyToWorkbench => '应用全部参数到工作台';

  @override
  String dockAbortWithSteps(int current, int total) {
    return '终止生成 ($current/$total)';
  }

  @override
  String dockGenerateWithCost(int cost) {
    return '生成图片 ($cost Anlas)';
  }

  @override
  String get dockGenerateNeedPoints => '生成图片 (需点数)';

  @override
  String get dockNoAccountInfo => '未获取账号信息 (请检查 API Key)';

  @override
  String get dockAiEditing => 'AI 编辑中...';

  @override
  String get dockInpainting => '修复中...';

  @override
  String get dockRefreshTooltip => '刷新体力与点数';

  @override
  String get sidebarTabParameters => '参数';

  @override
  String get sidebarTabInpaint => '修复';

  @override
  String get sidebarSettingsTooltip => '全局配置 (API Key / 存储 / LLM)';

  @override
  String get promptResizeTooltip => '拖动调整高度 (双击重置)';

  @override
  String get studioClipboardImageDefaultName => '剪贴板图片.png';

  @override
  String get studioImportedReference => '已导入参考图';

  @override
  String get boardPastedImage => '已粘贴图片至大画布';

  @override
  String boardImportedReferenceNamed(String name) {
    return '已导入参考图: $name';
  }

  @override
  String get boardAddedHistoryImage => '已将历史图片添加为大画布参考图';

  @override
  String get boardDropInternalHint => '松开鼠标放置参考图';

  @override
  String get boardDropExternalHint => '松开鼠标导入外部参考图';

  @override
  String get boardExitAnnotation => '退出批注';

  @override
  String get boardSendAllToAi => '发送全部批注到 AI';

  @override
  String get boardWireMissedTarget => '未命中选区/图钉，已取消连线';

  @override
  String get boardToolPan => '漫游';

  @override
  String get boardToolRect => '圈选选区';

  @override
  String get boardToolPoint => '图钉锚点';

  @override
  String get boardToolAddNote => '+ 便利贴';

  @override
  String get boardToolAddImage => '+ 参考图';

  @override
  String get boardToolPasteImage => '粘贴图 (Ctrl+V)';

  @override
  String get boardToolResetView => '适应视口';

  @override
  String get boardImageCardMainTitle => '主图 (当前生成图)';

  @override
  String boardImageCardRefTitle(int width, int height) {
    return '参考图 (${width}x$height)';
  }

  @override
  String get boardImageCardRemoveTooltip => '移除参考图卡片';

  @override
  String get boardImageResizeTooltip => '拖拽调节图片卡片大小 (按住 Shift 锁定宽高比)';

  @override
  String get boardImageSendToInpaint => '发送到修复';

  @override
  String get boardAnnotationDeleteRect => '删除选区';

  @override
  String get boardAnnotationDeletePoint => '删除锚点';

  @override
  String get boardAnnotationResizeRect => '拖拽调节选区大小';

  @override
  String get boardAnnotationSelectTooltip => '点击选中该批注';

  @override
  String get boardWireDragSourceTooltip => '按住拖出连线到选区/图钉';

  @override
  String get boardNoteConnected => '已连线';

  @override
  String get boardNoteTitle => '便签';

  @override
  String get boardNoteDisconnectTooltip => '断开连线';

  @override
  String get boardNoteDeleteTooltip => '删除便签';

  @override
  String get boardNoteHint => '输入修改意见...';

  @override
  String get boardNoteResizeTooltip => '拖拽调节便签大小';

  @override
  String charPosCanvasTempBoard(int width, int height) {
    return '临时画板 · $width × $height';
  }

  @override
  String get posControlsDoneEditing => '完成编辑';

  @override
  String get lightboxCloseTooltip => '关闭大图展示';

  @override
  String get librarySearchHint => '搜索词组合名称、提示词、标签...';

  @override
  String get libraryDataManagement => '数据管理';

  @override
  String get libraryExportJson => '导出词库 (JSON)';

  @override
  String get libraryImportJson => '导入词库 (JSON)';

  @override
  String get libraryManageButton => '管理';

  @override
  String get libraryNewCombo => '新建词组合';

  @override
  String get libraryCategorySidebarTitle => '标签分类';

  @override
  String libraryEntriesCount(int count) {
    return '$count 条';
  }

  @override
  String get libraryCategoryAll => '全部';

  @override
  String get libraryExportCopied => '已复制词库 JSON 数据到剪贴板，可粘贴备份或分享';

  @override
  String libraryExportFailed(String error) {
    return '导出失败: $error';
  }

  @override
  String get libraryImportDialogTitle => '导入词库 JSON';

  @override
  String get libraryImportPrompt => '请粘贴导出的词库 JSON 文本：';

  @override
  String libraryImportSuccess(int count) {
    return '成功导入 $count 个新词组合条目';
  }

  @override
  String libraryImportFailed(String error) {
    return '导入失败，请检查 JSON 格式: $error';
  }

  @override
  String libraryApplyAsCharacter(String title) {
    return '已添加角色卡片: $title';
  }

  @override
  String libraryApplyReplace(String title) {
    return '已替换工作台提示词: $title';
  }

  @override
  String libraryApplyAppendBoth(String title) {
    return '已追加正负提示词: $title';
  }

  @override
  String libraryApplyAppendPrompt(String title) {
    return '已追加主提示词: $title';
  }

  @override
  String get libraryReturnToWorkbench => '返回工作台';

  @override
  String get libraryDeleteDialogTitle => '删除词组合';

  @override
  String libraryDeleteDialogMessage(String title) {
    return '确定要删除词组合「$title」吗？此操作无法撤销。';
  }

  @override
  String libraryDeletedCombo(String title) {
    return '已删除词组合: $title';
  }

  @override
  String get libraryEmptyTitle => '词库暂无条目';

  @override
  String get libraryNoMatchingTitle => '没有匹配的词组合';

  @override
  String get libraryEmptyDescription => '点击右上角「新建词组合」创建您的第一个专属提示词组合';

  @override
  String get libraryNoMatchingDescription => '请尝试更换搜索词或分类筛选条件';

  @override
  String get libraryResetFilter => '重置筛选条件';

  @override
  String libraryCardCopiedPrompt(String title) {
    return '已复制「$title」提示词到剪贴板';
  }

  @override
  String get libraryMenuAppendToPrompt => '追加到工作台提示词';

  @override
  String get libraryMenuReplacePrompt => '替换工作台提示词';

  @override
  String get libraryMenuAddAsCharacter => '添加为多角色卡片';

  @override
  String get libraryMenuCopyPrompt => '复制提示词';

  @override
  String get libraryMenuEdit => '编辑';

  @override
  String get libraryCardApply => '应用到工作台';

  @override
  String get libraryCardAddAsCharacterTooltip => '添加为工作台多角色卡片';

  @override
  String get libraryCardAddCharacter => '+ 角色';

  @override
  String get libraryCardNoPreview => '无预览图';

  @override
  String get libraryEditCustomCategoryOption => '自定义...';

  @override
  String libraryEditPickImageFailed(String error) {
    return '选择图片失败: $error';
  }

  @override
  String get libraryEditAdoptedCanvasImage => '已采用当前画板图像作为预览图';

  @override
  String get libraryEditCanvasNoImage => '画板当前暂无生成的图像';

  @override
  String get libraryEditWorkspacePromptEmpty => '工作台主提示词为空';

  @override
  String get libraryEditWorkspaceNegativeEmpty => '工作台负面提示词为空';

  @override
  String get libraryEditTitleEmpty => '请输入词组合名称';

  @override
  String get libraryEditPromptEmpty => '请输入主提示词内容';

  @override
  String libraryEditUpdatedSuccess(String title) {
    return '已更新词组合: $title';
  }

  @override
  String libraryEditCreatedSuccess(String title) {
    return '已添加词组合: $title';
  }

  @override
  String libraryEditSaveFailed(String error) {
    return '保存失败: $error';
  }

  @override
  String get libraryEditDialogTitleEdit => '编辑词组合';

  @override
  String get libraryEditDialogTitleNew => '新建词组合';

  @override
  String get libraryEditFieldTitle => '组合名称';

  @override
  String get libraryEditFieldTitleHint => '例如：赛博朋克猫耳少女 / 日系水彩插画';

  @override
  String get libraryEditFieldCategory => '分类';

  @override
  String get libraryEditFieldCustomCategoryHint => '输入自定义分类名称 (如：光影、视角)';

  @override
  String get libraryEditFieldPrompt => '主提示词';

  @override
  String get libraryEditFillFromPrompt => '填入工作台主词';

  @override
  String get libraryEditFieldPromptHint =>
      '输入正向提示词 (如: 1girl, hatsune miku, cybernetic...)';

  @override
  String get libraryEditFieldNegative => '负面提示词';

  @override
  String get libraryEditCharacterOnlyBadge => '仅角色分类可用';

  @override
  String get libraryEditFillFromNegative => '填入工作台负向词';

  @override
  String get libraryEditFieldNegativeHint =>
      '角色专有负面词 (如: worst quality, bad hands, mutated...)';

  @override
  String get libraryEditFieldTags => '检索标签 (Tags)';

  @override
  String get libraryEditFieldTagsHint => '用于快速筛选，用逗号分隔 (例如：miku, 水彩, 二次元, 赛博)';

  @override
  String get libraryEditSaveButton => '保存修改';

  @override
  String get libraryEditCreateButton => '创建词组合';

  @override
  String get libraryEditPosterTitle => '设置预览图';

  @override
  String get libraryEditPickLocalImage => '选择本地图片';

  @override
  String get libraryEditUseCanvasImage => '使用画板当前图';

  @override
  String get libraryEditRemovePreviewImage => '移除预览图';

  @override
  String tagAcAlias(String alias) {
    return '别名: $alias';
  }

  @override
  String get tagBrowserTitle => 'Danbooru 标签灵感库';

  @override
  String get tagBrowserSearchHint => '输入英文或中文搜索 14万+ Danbooru 标签...';

  @override
  String tagBrowserAddedTag(String tag) {
    return '已添加标签: $tag';
  }

  @override
  String tagBrowserAddedTagWithZh(String tag, String zh) {
    return '已添加标签: $tag ($zh)';
  }

  @override
  String get tagBrowserNoMatchingTitle => '未找到匹配标签';

  @override
  String get tagBrowserNoMatchingDesc => '请尝试输入其他英文或中文关键词检索';

  @override
  String get chatSessionManagementTooltip => '会话管理';

  @override
  String get chatModelNoVisionNotice => '当前模型不支持图片输入，请先切换到多模态模型';

  @override
  String chatMaxAttachmentsNotice(int count) {
    return '一次最多附带 $count 张图片';
  }

  @override
  String get chatImageParseFailedNotice => '图片解析失败，请换一张图片重试';

  @override
  String get chatModelNoVisionBeforeSendNotice => '当前模型不支持图片输入，发送前请切换到多模态模型';

  @override
  String get chatInputHint => '输入绘画构思，或输入 /nai <词> 快速生图...';

  @override
  String get chatThinkingLabel => '思考:';

  @override
  String get chatThinkingEffortOff => '关';

  @override
  String get chatThinkingEffortLow => '低';

  @override
  String get chatThinkingEffortMedium => '中';

  @override
  String get chatThinkingEffortHigh => '高';

  @override
  String get chatSessionUsageEmpty => '当前会话暂无 Token 用量记录';

  @override
  String get chatSessionUsageTitle => '当前会话 Token 用量';

  @override
  String chatSessionUsageDetail(String input, String output, String total) {
    return '输入 $input · 输出 $output · 总计 $total';
  }

  @override
  String chatSessionUsageCacheRead(String cacheRead) {
    return ' · 缓存读 $cacheRead';
  }

  @override
  String chatSessionUsageCacheReadWithRate(String cacheRead, String rate) {
    return ' · 缓存读 $cacheRead ($rate%)';
  }

  @override
  String get chatToolNoOutput => '(无输出)';

  @override
  String chatToolResultSummary(int count, String firstLine) {
    return '$count 行 · $firstLine';
  }

  @override
  String get chatThinkingProgress => '正在思考...';

  @override
  String get chatConceiving => '构思中...';

  @override
  String get chatRemoveAttachmentTooltip => '移除附件';

  @override
  String get chatAddAttachmentTooltip => '添加附件';

  @override
  String get rewindBackTooltip => '返回对话 (ESC)';

  @override
  String get rewindTitle => '回溯历史时刻';

  @override
  String get rewindEscExit => 'ESC 退出';

  @override
  String get rewindDescription => '选择要回退到的对话时刻。确认后将撤销此时刻之后的所有修改与对话记录。';

  @override
  String get rewindEmptyTitle => '当前会话暂无历史对话轮次可回溯';

  @override
  String get rewindBackAction => '返回对话';

  @override
  String get rewindLatestBadge => '(最新时刻)';

  @override
  String rewindSelectedTurn(int index) {
    return '已选择第 #$index 轮对话';
  }

  @override
  String get rewindSelectPrompt => '请在上方列表中选择要回退的轮次';

  @override
  String get rewindCancelButton => '取消';

  @override
  String get rewindConfirmButton => '回到此时刻';

  @override
  String get sessionRenameTitle => '重命名会话';

  @override
  String get sessionRenameHint => '请输入会话新名称...';

  @override
  String get sessionSave => '保存';

  @override
  String get sessionCancel => '取消';

  @override
  String get sessionDeleteTitle => '删除会话';

  @override
  String sessionDeleteConfirm(String title) {
    return '确定要永久删除会话 \"$title\" 吗？此操作无法撤销。';
  }

  @override
  String get sessionDeleteConfirmButton => '删除';

  @override
  String sessionDateFormat(int month, int day, String time) {
    return '$month月$day日 $time';
  }

  @override
  String get sessionBackTooltip => '返回对话';

  @override
  String get sessionTitle => '会话管理';

  @override
  String get sessionNew => '新建会话';

  @override
  String get sessionSearchHint => '搜索历史会话...';

  @override
  String get sessionNoMatchingTitle => '未找到匹配的会话';

  @override
  String get sessionEmptyTitle => '暂无历史会话记录';

  @override
  String get sessionCurrentBadge => '当前';

  @override
  String get sessionRenameAction => '重命名';

  @override
  String get sessionDeleteAction => '删除';

  @override
  String sessionMessageCount(int count) {
    return '$count 条';
  }

  @override
  String get askCardDefaultHeader => '向用户提问';

  @override
  String get askCardPendingConfirm => '待确认';

  @override
  String get askCardCancel => '取消';

  @override
  String get askCardSubmit => '提交回答';

  @override
  String get askCardCustomInputHint => '输入自定义回答...';

  @override
  String get chatThinkingProcess => '思考过程';

  @override
  String get canvasBadgeUnsaved => '未保存';

  @override
  String get canvasBadgeUpscale => '放大';

  @override
  String get canvasBadgeInpaint => '修复';

  @override
  String get canvasBadgeAiEdit => 'AI 编辑';

  @override
  String get canvasBadgeImported => '导入';

  @override
  String get tagCatGeneral => '通用';

  @override
  String get tagCatArtist => '画师';

  @override
  String get tagCatCopyright => '作品';

  @override
  String get tagCatCharacter => '角色';

  @override
  String get tagCatMeta => '元数据';

  @override
  String get llmProtocolOpenAiChat => 'OpenAI 兼容 (/chat/completions)';

  @override
  String get llmProtocolOpenAiResponses => 'Response (/responses)';

  @override
  String get llmProtocolAnthropicMessages => 'Message (/messages)';

  @override
  String get thinkingFormatAuto => '自动 (按端点识别)';

  @override
  String get thinkingFormatOpenai => 'OpenAI (reasoning_effort)';

  @override
  String get thinkingFormatDeepseek => 'DeepSeek (thinking)';

  @override
  String get thinkingFormatQwen => 'Qwen (enable_thinking)';

  @override
  String get thinkingFormatQwenChatTemplate => 'Qwen Chat Template';

  @override
  String get thinkingFormatZai => 'Z.ai (thinking + clear_thinking)';

  @override
  String get thinkingFormatOpenrouter => 'OpenRouter (reasoning.effort)';

  @override
  String get thinkingFormatTogether => 'Together (reasoning.enabled)';

  @override
  String get libraryCatCharacter => '角色';

  @override
  String get libraryCatStyle => '风格';

  @override
  String get libraryCatAttire => '服装';

  @override
  String get libraryCatComposition => '构图';

  @override
  String get libraryCatEnvironment => '环境';

  @override
  String get libraryCatEffect => '特效';

  @override
  String get libraryCatOther => '其他';

  @override
  String get libraryCatCustom => '自定义...';

  @override
  String get vmGenDoneUnsaved => '生图完成 (未保存，可点击画板右下角保存)';

  @override
  String vmGenDoneSavedTo(String path) {
    return '生图完成，已保存在 $path';
  }

  @override
  String get vmGenLocalPath => '本地';

  @override
  String get vmGenNoSaveDir => '未设置本地存储目录，请先在设置中配置保存路径。';

  @override
  String get vmGenSaveFailedNoTarget => '保存图片失败：未找到图片或存储目录不可写。';

  @override
  String vmGenSavedTo(String path) {
    return '已保存到 $path';
  }

  @override
  String vmGenSaveFailed(String error) {
    return '保存图片失败: $error';
  }

  @override
  String get vmGenAborted => '已终止生成';

  @override
  String get vmGenEmptyPrompt => '提示词不能为空，请先在左侧或对话框中输入描述。';

  @override
  String get vmGenNoApiKey => '未配置 NovelAI API Key，请点击右上角设置。';

  @override
  String vmGenRequesting(int width, int height, int steps) {
    return '正在请求 NovelAI 生图 (${width}x$height, $steps步)...';
  }

  @override
  String vmGenFailed(String error) {
    return '生图失败: $error';
  }

  @override
  String get vmUpscaleNoImage => '当前画板中无图片可供放大。';

  @override
  String get vmUpscaleNoApiKey => '未配置 NovelAI API Key。';

  @override
  String get vmUpscaleRunning => '正在执行图像超分放大...';

  @override
  String vmUpscaleDoneUnsaved(int width, int height) {
    return '放大完成 (${width}x$height，未保存)';
  }

  @override
  String vmUpscaleDone(int width, int height) {
    return '放大完成 (${width}x$height)';
  }

  @override
  String vmUpscaleFailed(String error) {
    return '放大失败: $error';
  }

  @override
  String get vmChatSlashNoImage => '斜杠指令不支持附带图片，请直接发送对话消息';

  @override
  String vmChatSlashFailed(String error) {
    return '指令执行失败: $error';
  }

  @override
  String vmChatRetryNotice(int attempt, int max, String reason, String retry) {
    return '请求失败自动重试 ($attempt/$max): $reason · $retry';
  }

  @override
  String vmChatRetryDelayed(int seconds) {
    return '$seconds 秒后重试';
  }

  @override
  String get vmChatRetrySoon => '即将重试';

  @override
  String vmChatCompacted(int before, int after) {
    return '上下文已自动压缩 ($before → $after tokens)，更早消息已摘要替换';
  }

  @override
  String vmChatError(String error) {
    return '对话异常: $error';
  }

  @override
  String get vmChatForceAborted => '已强制终止当前生成';

  @override
  String get vmCostNoOpusQuota => '当前账号无 Opus 免费额度';

  @override
  String vmCostEstimate(int cost) {
    return '预计消耗 $cost Anlas 点数';
  }

  @override
  String get vmCostWillCost => '将消耗 Anlas 点数';

  @override
  String get vmCostTitle => '点数消耗申请';

  @override
  String vmCostGenQuestion(String reasons, String cost) {
    return '本次生图参数（$reasons）$cost。是否确认生成？';
  }

  @override
  String get vmCostGenConfirm => '确认生成';

  @override
  String get vmCostGenConfirmDesc => '使用当前参数直接生图并扣除点数';

  @override
  String get vmCostGenCancel => '取消生图';

  @override
  String get vmCostGenCancelDesc => '取消本次生成，调整参数至免费区间';

  @override
  String vmCostUpscaleQuestion(int width, int height, int cost) {
    return '将输入尺寸 ${width}x$height 的图片执行官方超分放大，预计消耗 $cost Anlas 点数。是否确认放大？';
  }

  @override
  String get vmCostUpscaleConfirm => '确认放大';

  @override
  String get vmCostUpscaleConfirmDesc => '执行官方超分并扣除点数';

  @override
  String get vmCostUpscaleCancel => '取消放大';

  @override
  String get vmCostUpscaleCancelDesc => '取消本次超分操作';

  @override
  String get vmInpaintConverted => '已将批注转换为修复选区';

  @override
  String vmInpaintSentToBoard(String path) {
    return '已发送到修复画板: $path';
  }

  @override
  String get vmInpaintNoImage => '未找到可供修复的底图，请先选择或生成图片。';

  @override
  String get vmInpaintNoMask => '请先在修复画板框选或用画笔绘制待修复区域。';

  @override
  String get vmInpaintNoApiKey => '未配置 NovelAI API Key，请在设置中输入 Token。';

  @override
  String get vmInpaintRunning => '正在执行局部修复...';

  @override
  String get vmInpaintDone => '局部修复完成';

  @override
  String vmInpaintFailed(String error) {
    return '修复失败: $error';
  }

  @override
  String get vmAiEditNoImage => '未找到可供编辑的底图，请先选择或生成图片。';

  @override
  String get vmAiEditNoModel => '未配置 AI 整图编辑的绘图模型，请在设置 → Models 页选择绘图模型供应商与模型。';

  @override
  String vmAiEditNoKey(String provider) {
    return '绘图模型供应商「$provider」未配置 API Key，请先在设置中填写。';
  }

  @override
  String get vmAiEditEmptyPrompt =>
      '请先输入 AI 整图编辑的修改指令 (修复页提示词设置，或关闭「复用主工作台正向词」后填写)。';

  @override
  String get vmAiEditRunning => 'AI 整图编辑中 (绘图模型处理中，通常需要数十秒)...';

  @override
  String get vmAiEditDone => 'AI 整图编辑完成';

  @override
  String vmAiEditFailed(String error) {
    return 'AI 整图编辑失败: $error';
  }

  @override
  String vmSessionSwitched(String title) {
    return '已切换会话: $title';
  }

  @override
  String get vmSessionCreated => '已创建新会话';

  @override
  String get vmSessionDeleted => '会话已删除';

  @override
  String get vmRewindChatAndParams => '已回到历史时刻，后续对话与参数修改已撤回';

  @override
  String get vmRewindChatOnly => '已回到历史时刻，后续对话与修改已撤回';

  @override
  String get vmHistoryDeleted => '已从历史记录删除图片';

  @override
  String get vmHistoryCleared => '已清空历史记录';

  @override
  String get vmMetadataApplied => '已应用图片元数据至工作台';

  @override
  String vmPresetSwitched(String name, String description) {
    return '已切换为预设: 【$name】\n$description';
  }

  @override
  String vmCharacterDefaultName(int index) {
    return '角色 $index';
  }

  @override
  String get vmNewCharacterName => '新角色';

  @override
  String get slashHelpHeader => '快捷指令说明：';

  @override
  String get slashDescHelp => '查看指令帮助列表';

  @override
  String get slashDescParams => '查看工作台当前生效的生图参数';

  @override
  String get slashDescPreset => '切换当前 Agent 预设';

  @override
  String get slashDescSkill => '按需加载并执行专业技能';

  @override
  String get slashDescNai =>
      '快速生成插画，支持 --landscape/--portrait/--square/--wallpaper 方向标志';

  @override
  String get slashDescUpscale => '超分放大当前图片';

  @override
  String get slashDescTag => '查询 Danbooru 官方标签联想';

  @override
  String get slashDescAccount => '查询账号等级与 V5 专属体力池';

  @override
  String get slashDescCompact => '手动压缩对话上下文 (摘要替换更早消息，原始消息仍保留)';

  @override
  String get slashDescNew => '新建一个空白会话 (可附带标题)';

  @override
  String get slashDescUndo => '撤销上一轮对话 (回复与参数修改一并回滚)';

  @override
  String get slashDescRename => '重命名当前会话';

  @override
  String get slashDescSessions => '列出已保存的会话';

  @override
  String get slashDescClear => '清空对话历史';

  @override
  String get slashArgsName => '<名称>';

  @override
  String get slashArgsPrompt => '<提示词>';

  @override
  String get slashArgsKeyword => '<关键词>';

  @override
  String get slashArgsTitle => '<标题>';

  @override
  String get slashPresetListIntro => '可用预设列表：';

  @override
  String get slashPresetUsage => '用法: /preset <预设名称或ID>';

  @override
  String slashPresetNotFound(String query) {
    return '未找到预设 \"$query\"，输入 /preset 查看可用预设。';
  }

  @override
  String get slashSkillListIntro => '可用技能列表：';

  @override
  String get slashSkillUsage => '用法: /skill <技能名称或ID>';

  @override
  String slashSkillLoaded(
    String name,
    String description,
    String systemPrompt,
  ) {
    return '【Skill 已载入】$name\n$description\n\n$systemPrompt';
  }

  @override
  String slashSkillNotFound(String query) {
    return '未找到技能 \"$query\"，输入 /skill 查看可用技能。';
  }

  @override
  String get slashCompactNoProvider => '未配置 LLM 提供商，无法压缩上下文。';

  @override
  String get slashCompactEmpty => '当前对话为空，无需压缩上下文。';

  @override
  String get slashCompactRunning => '正在压缩对话上下文...';

  @override
  String get slashCompactNothing => '上下文没有可压缩的内容 (需要至少两轮对话)，或摘要生成失败。';

  @override
  String slashCompactDone(int before, int after, String summary) {
    return '上下文压缩完成 ($before → $after tokens)。更早的消息已替换为以下摘要，原始消息仍保留在对话流与会话记录中：\n\n$summary';
  }

  @override
  String get slashNewNoTitle => '已创建新会话，开始新的对话吧。';

  @override
  String slashNewWithTitle(String title) {
    return '已创建新会话: $title';
  }

  @override
  String get slashUndoNothing => '没有可撤销的上一轮对话 (首轮之前的消息不存在)。';

  @override
  String get slashRenameUsage => '用法: /rename <新标题>';

  @override
  String get slashRenameNoSession => '当前没有活跃会话，无法重命名。';

  @override
  String slashRenamed(String title) {
    return '会话已重命名为 \"$title\"';
  }

  @override
  String get slashSessionsEmpty => '暂无已保存的会话。';

  @override
  String slashSessionsHeader(int count) {
    return '已保存的会话 (共 $count 个，按最近使用排序)：';
  }

  @override
  String slashSessionMsgCount(int count) {
    return '$count 条消息';
  }

  @override
  String get slashSessionCurrentMarker => ' [当前]';

  @override
  String slashSessionsMore(int count) {
    return '…… 其余 $count 个会话请打开会话管理视图查看。';
  }

  @override
  String get slashAccountTitle => 'NovelAI 账号状态：';

  @override
  String slashAccountTier(String tier) {
    return '• 订阅等级: $tier';
  }

  @override
  String slashAccountStamina(String percent) {
    return '• V5 专属体力池: $percent%';
  }

  @override
  String slashAccountAnlas(int total, int fixed, int purchased) {
    return '• 可用 Anlas: $total (赠送: $fixed, 购买: $purchased)';
  }

  @override
  String get slashAccountQuotaExhausted => '• V5 体力配额已透支，生图将按正常价消耗 Anlas';

  @override
  String get slashAccountFailed => '查询账号信息失败，请检查 API Key 设置。';

  @override
  String get slashTagUsage => '用法: /tag <关键词> (例如: /tag silver)';

  @override
  String slashTagNotFound(String query) {
    return '未找到与 \"$query\" 相关的标签。';
  }

  @override
  String slashTagSuggestions(String query, String list) {
    return '标签联想建议 (\"$query\"):\n$list';
  }

  @override
  String get slashUpscaleDone => '已执行超分放大';

  @override
  String get slashNaiUsage => '用法: /nai <提示词>';

  @override
  String slashNaiDone(String path, int width, int height, int seed) {
    return '插画已生成: $path\n尺寸: ${width}x$height, 种子: $seed';
  }

  @override
  String get slashNaiDoneFallback => '完成';

  @override
  String slashUnknown(String cmd) {
    return '未知指令 \"$cmd\"，输入 /help 查看可用指令。';
  }

  @override
  String get vmSlashParamsTitle => '工作台当前生图参数：';
}
