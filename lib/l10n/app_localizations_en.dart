// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'NovelAI Harness';

  @override
  String get generateImage => 'Generate Image';

  @override
  String get startInpaint => 'Start Inpaint';

  @override
  String get startAiEdit => 'Start AI Edit';

  @override
  String get abortGeneration => 'Abort Generation';

  @override
  String get opusFree => 'Opus Free';

  @override
  String get needAnlas => 'Costs Anlas';

  @override
  String get v5Stamina => 'V5 Stamina';

  @override
  String get tabParameters => 'Parameters';

  @override
  String get tabPrompts => 'Prompts';

  @override
  String get tabInpaint => 'Inpaint';

  @override
  String get tabLibrary => 'Library';

  @override
  String get history => 'History';

  @override
  String get settings => 'Settings';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get confirm => 'Confirm';

  @override
  String get clear => 'Clear';

  @override
  String get delete => 'Delete';

  @override
  String get copy => 'Copy';

  @override
  String get close => 'Close';

  @override
  String get import => 'Import';

  @override
  String get export => 'Export';

  @override
  String get settingsSectionAppearance => 'Appearance';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsThemeModeSubtitle =>
      'Switch between light/dark workspace; dark uses a Notion-minimal palette';

  @override
  String get themeModeSystem => 'Follow System';

  @override
  String get themeModeLight => 'Light';

  @override
  String get themeModeDark => 'Dark';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageSubtitle =>
      'Switch the display language; the settings page comes first, other screens migrate module by module';

  @override
  String get localeSystem => 'Follow System';

  @override
  String get localeChinese => '中文';

  @override
  String get localeEnglish => 'English';

  @override
  String get settingsUiZoom => 'UI Zoom';

  @override
  String get settingsUiZoomSubtitle =>
      'Scale the whole workspace; Ctrl+= / Ctrl+- to step, Ctrl+0 to reset';

  @override
  String get settingsSectionNovelaiService => 'NovelAI Service';

  @override
  String get settingsApiKeyTitle => 'NovelAI API Key';

  @override
  String get settingsApiKeySubtitle =>
      'Official API token (pst-...) for image generation and stamina sync';

  @override
  String get settingsSaveDirTitle => 'Local Storage Directory';

  @override
  String get settingsSaveDirSubtitle =>
      'Generated images and metadata are saved to this path';

  @override
  String get settingsSaveDirHint => 'Storage path...';

  @override
  String get settingsChooseButton => 'Choose';

  @override
  String get settingsAutoSaveTitle => 'Auto-save Generated Images';

  @override
  String get settingsAutoSaveSubtitleOn =>
      'Images are written to the storage directory automatically (metadata & watermark follow export settings)';

  @override
  String get settingsAutoSaveSubtitleOff =>
      'Images go to the cache directory (no watermark) first; save manually from the canvas, and cache beyond the history limit is pruned automatically';

  @override
  String get settingsStreamPreviewTitle => 'Live Generation Preview';

  @override
  String get settingsStreamPreviewSubtitle =>
      'Receive and render intermediate denoising previews during generation (Stream Preview)';

  @override
  String get settingsImagePersistenceTitle => 'Image History Persistence';

  @override
  String get settingsImagePersistenceSubtitle =>
      'Restore canvas history images after app restart';

  @override
  String get settingsMaxImagesTitle => 'Max Persisted Images';

  @override
  String get settingsMaxImagesSubtitle =>
      'Cap the number of images kept in local canvas history';

  @override
  String settingsImageCount(int count) {
    return '$count images';
  }

  @override
  String get settingsSectionTagAutocomplete => 'Danbooru Tag Autocomplete';

  @override
  String get settingsTagAutocompleteTitle => 'Smart Tag Autocomplete';

  @override
  String get settingsTagAutocompleteSubtitle =>
      'Pop up suggestions from the 320k+ Danbooru dictionary while typing prompts';

  @override
  String get settingsDictUpdateTitle => 'Online Dictionary Update';

  @override
  String get settingsDictUpdateNowButton => 'Update Now';

  @override
  String get settingsDictAutoCheckTitle => 'Check for Updates at Startup';

  @override
  String get settingsDictAutoCheckSubtitle =>
      'Fetch the latest dictionary once daily in the background (ffdkj daily builds with new tags and Chinese translations)';

  @override
  String get settingsTagTranslationsTitle => 'Show Chinese Tag Meanings';

  @override
  String get settingsTagTranslationsSubtitle =>
      'Show Chinese translations in the suggestion list and the tag browser';

  @override
  String get settingsTagColorsTitle => 'Tag Category Highlight';

  @override
  String get settingsTagColorsSubtitle =>
      'Colorize artist, character, copyright and general tags in the prompt editor';

  @override
  String dictOnlineInfo(int count, String date) {
    return 'Online dictionary, $count entries · updated $date';
  }

  @override
  String dictBuiltinInfo(int count) {
    return 'Built-in dictionary, $count entries';
  }

  @override
  String get dictBuiltinLoading => 'Built-in dictionary (loading)';

  @override
  String get settingsSectionProtection => 'Protection';

  @override
  String get settingsOpusTitle => 'Opus Free-Tier Protection';

  @override
  String get settingsOpusSubtitle =>
      'Clamp default parameters into the free tier (pixels <= 1048576 and steps <= 28)';

  @override
  String dictUpdateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String get settingsModelSettings => 'Model Settings';

  @override
  String get settingsDeleteModel => 'Delete Model';

  @override
  String get settingsModelBadgeThinking => 'Thinking';

  @override
  String get settingsModelBadgeMultimodal => 'Multimodal';

  @override
  String get settingsModelBadgeImageOutput => 'Image';

  @override
  String settingsModelBadgeContext(String tokens) {
    return '$tokens Context';
  }

  @override
  String get settingsAddModel => 'Add Model';

  @override
  String get settingsModelIdEmptyError => 'Model ID cannot be empty';

  @override
  String get settingsModelDisplayName => 'Display Name';

  @override
  String get settingsModelDisplayNameHint => 'e.g. DeepSeek R1';

  @override
  String get settingsModelId => 'Model ID';

  @override
  String get settingsModelIdHint => 'Model identifier sent to API';

  @override
  String get settingsModelTemperature => 'Temperature';

  @override
  String get settingsModelReasoning => 'Reasoning';

  @override
  String get settingsModelThinkingEffort => 'Thinking Effort';

  @override
  String get settingsModelMultimodal => 'Multimodal (Image Input)';

  @override
  String get settingsModelImageOutput => 'Image Output (Drawing Model)';

  @override
  String get settingsModelContextWindow => 'Context Window (tokens)';

  @override
  String get settingsModelMaxTokens => 'Max Output (tokens)';

  @override
  String get settingsAdd => 'Add';

  @override
  String get settingsCustomProviderDefaultName => 'Custom Provider';

  @override
  String settingsNewProviderDefaultName(int index) {
    return 'New Provider $index';
  }

  @override
  String get settingsFetchModelsEnterBaseUrl =>
      'Please enter a valid API Base URL first';

  @override
  String settingsFetchModelsSuccess(int count) {
    return 'Successfully fetched $count models';
  }

  @override
  String settingsFetchModelsSuccessWithEnriched(int count, int enrichedCount) {
    return 'Successfully fetched $count models, $enrichedCount matched with models.dev metadata';
  }

  @override
  String get settingsEndpointUrlNotConfigured => 'URL not configured';

  @override
  String settingsFullEndpoint(String endpoint) {
    return 'Full Endpoint: $endpoint';
  }

  @override
  String get settingsSectionProviderSelection => 'Provider Selection';

  @override
  String get settingsSectionProviderProfile => 'Provider Profile & Endpoint';

  @override
  String get settingsSectionModels => 'Models';

  @override
  String get settingsSectionImageEdit => 'AI Image Edit';

  @override
  String get settingsCurrentProvider => 'Current Provider';

  @override
  String get settingsCurrentProviderSubtitle =>
      'Select an AI provider to configure, or add a custom provider';

  @override
  String get settingsNewProviderButton => 'New';

  @override
  String get settingsDeleteCurrentProviderTooltip => 'Delete current provider';

  @override
  String get settingsProviderName => 'Provider Name';

  @override
  String get settingsProviderNameSubtitle =>
      'Custom label displayed in UI and dropdown menus';

  @override
  String get settingsProviderNameHint =>
      'e.g. DeepSeek / OpenAI / Local Ollama';

  @override
  String get settingsApiEndpointAndProtocol => 'API Endpoint & Protocol';

  @override
  String get settingsApiEndpointAndProtocolSubtitle =>
      'Service base URL and communication protocol format';

  @override
  String get settingsLlmApiKeyTitle => 'LLM API Key';

  @override
  String get settingsLlmApiKeySubtitle =>
      'Credentials required to access this provider';

  @override
  String get settingsThinkingParamFormat => 'Thinking Param Format';

  @override
  String get settingsThinkingParamFormatSubtitle =>
      'Different providers use different fields to toggle reasoning. Reasoning will be silently discarded if the format does not match; configure according to the upstream format for relays.';

  @override
  String get settingsModelsListTitle => 'Models';

  @override
  String get settingsModelsListSubtitle =>
      'Click a card to switch current model; use settings to adjust parameters and capability profiles';

  @override
  String get settingsFetchingModels => 'Fetching...';

  @override
  String get settingsFetchModelsOnline => 'Fetch Models Online';

  @override
  String get settingsImageEditModelTitle => 'Drawing Model';

  @override
  String get settingsImageEditModelSubtitle =>
      'Provider and model used by Inpaint \'AI Image Edit\' (drawing models only), independent of chat LLM; select a model with image output capabilities (e.g. nano banana / gpt-image)';

  @override
  String get settingsDropdownNotConfigured => 'Not Configured';

  @override
  String get settingsDropdownNoModelSelected => 'No Model Selected';

  @override
  String settingsImageEditUnrecognizedModel(String modelId) {
    return '$modelId (not recognized as drawing model)';
  }

  @override
  String get settingsImageEditTip =>
      'Image edit does not consume Anlas points, billing follows the drawing model provider; models without auto-detected capabilities can enable \'Image Output\' manually in model settings';

  @override
  String get settingsSearchModelHint => 'Search model name or ID';

  @override
  String get settingsModelSortDefault => 'Default Order';

  @override
  String get settingsModelSortNameAsc => 'Name A-Z';

  @override
  String get settingsModelSortNameDesc => 'Name Z-A';

  @override
  String get settingsFilterImageOnly => 'Drawing Models Only';

  @override
  String get settingsFilterImageOnlyTooltip =>
      'Only show models with image output capabilities (e.g. nano banana / gpt-image)';

  @override
  String settingsModelCount(int current, int total) {
    return '$current / $total models';
  }

  @override
  String get settingsNoModelsInProvider => 'No models in current provider';

  @override
  String get settingsNoModelsInProviderDesc =>
      'Click \"Fetch Models Online\" or \"Add Model\" above';

  @override
  String settingsNoMatchingModels(String query) {
    return 'No models matching \"$query\"';
  }

  @override
  String get settingsBadgeBuiltin => 'Built-in';

  @override
  String get settingsBadgeCustom => 'Custom';

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
  String get presetCurrentPreset => 'Current Preset';

  @override
  String get presetCurrentPresetSubtitle =>
      'Select an Agent preset to configure (system prompt, available skills, tool and parameter permissions)';

  @override
  String get presetBadgeActiveDefault => 'Default';

  @override
  String get presetSetAsActiveDefault => 'Set as Default';

  @override
  String get presetNewButton => 'New';

  @override
  String get presetDeleteTooltip => 'Delete this preset';

  @override
  String get presetDefaultCustomName => 'Custom Preset';

  @override
  String presetNewName(int index) {
    return 'New Preset $index';
  }

  @override
  String get presetNewDescription => 'Custom Agent preset description';

  @override
  String get presetNewSystemPrompt =>
      'You are a painting creation assistant powered by NovelAI Harness.';

  @override
  String presetDuplicateName(String name) {
    return '$name (Copy)';
  }

  @override
  String presetExportSkillSuccess(String name) {
    return 'Copied Skill [$name] as standard SKILL.md to clipboard';
  }

  @override
  String get presetBuiltinNotice =>
      'Built-in presets are factory defaults refreshed automatically from code on launch and cannot be edited directly. To customize, click \"Copy\" first to make a copy.';

  @override
  String get presetDisplayName => 'Preset Display Name';

  @override
  String get presetDisplayNameHint => 'e.g. V5 Natural Language Architect';

  @override
  String get presetDescription => 'Preset Description';

  @override
  String get presetDescriptionHint =>
      'e.g. Specialized in V5 natural language prose prompts...';

  @override
  String get presetSystemPrompt =>
      'System Prompt (serves as the primary root instruction for conversations)';

  @override
  String get presetSystemPromptHint =>
      'Enter the core persona and workflow guidelines for the AI assistant...';

  @override
  String get presetImportSkill => 'Import SKILL.md';

  @override
  String get presetNewSkill => 'New Skill';

  @override
  String get presetNewCustomTool => 'New Custom Tool';

  @override
  String get presetParamPrompt => 'Prompt';

  @override
  String get presetParamNegativePrompt => 'Negative Prompt';

  @override
  String get presetParamModel => 'Model';

  @override
  String get presetParamResolution => 'Resolution';

  @override
  String get presetParamWidth => 'Width';

  @override
  String get presetParamHeight => 'Height';

  @override
  String get presetParamSteps => 'Steps';

  @override
  String get presetParamScale => 'CFG';

  @override
  String get presetParamCfgRescale => 'CFG Rescale';

  @override
  String get presetParamSampler => 'Sampler';

  @override
  String get presetParamNoiseSchedule => 'Noise Schedule';

  @override
  String get presetParamQualityPreset => 'Quality Tags';

  @override
  String get presetParamCharacterAiPosition => 'Character Position';

  @override
  String get skillTooltipExport => 'Export as SKILL.md';

  @override
  String get skillTooltipEdit => 'View & Edit Skill';

  @override
  String get skillTooltipDelete => 'Delete Skill';

  @override
  String get skillNoDescription => 'No description';

  @override
  String get skillDialogImportTitle => 'Import Standard SKILL.md';

  @override
  String get skillDialogNewTitle => 'New Skill';

  @override
  String skillDialogEditTitle(String name) {
    return 'Edit Skill ($name)';
  }

  @override
  String get skillEditorTabStructured => 'Structured Edit';

  @override
  String get skillEditorTabRaw => 'SKILL.md Source';

  @override
  String get skillCopySkillMd => 'Copy SKILL.md';

  @override
  String get skillCopySuccess =>
      'Copied standard SKILL.md content to clipboard';

  @override
  String get skillSave => 'Save Skill';

  @override
  String get skillFieldId => 'ID';

  @override
  String get skillFieldIdHint => 'e.g. v5-architect';

  @override
  String get skillFieldName => 'Name';

  @override
  String get skillFieldNameHint => 'e.g. V5 Natural Language Architect';

  @override
  String get skillFieldDescription => 'Skill Description';

  @override
  String get skillFieldDescriptionHint =>
      'Briefly describe task scenarios this skill excels at...';

  @override
  String get skillFieldPrompt => 'Skill Instructions';

  @override
  String get skillFieldDisableInvocation => 'Disable model auto-invocation';

  @override
  String get skillFieldPromptHint =>
      'Enter complete prompt and specifications applied when this skill is loaded...';

  @override
  String get skillRawEditorHelp =>
      'Paste or edit standard SKILL.md (including YAML Frontmatter and Markdown Body):';

  @override
  String get skillIdEmptyError => 'Skill ID cannot be empty';

  @override
  String get toolTooltipEdit => 'Edit Tool';

  @override
  String get toolTooltipInspectSchema => 'View Schema';

  @override
  String get toolTooltipDelete => 'Delete Custom Tool';

  @override
  String get toolNoDescription => 'No tool description';

  @override
  String toolDialogSchemaTitle(String label) {
    return 'Tool Schema ($label)';
  }

  @override
  String get toolDialogNewTitle => 'New Custom Tool';

  @override
  String toolDialogEditTitle(String label) {
    return 'Edit Custom Tool ($label)';
  }

  @override
  String get toolFieldId => 'ID';

  @override
  String get toolFieldIdHint => 'e.g. custom_tool';

  @override
  String get toolFieldName => 'Name';

  @override
  String get toolFieldNameHint => 'e.g. Custom Tool';

  @override
  String get toolFieldDescription => 'Tool Description';

  @override
  String get toolFieldDescriptionHint =>
      'Clearly describe what this tool does and when to use it...';

  @override
  String get toolFieldSchema => 'Parameter Schema';

  @override
  String get toolCopySchema => 'Copy Schema';

  @override
  String get toolCopySchemaSuccess => 'Copied Schema JSON to clipboard';

  @override
  String get toolFieldOutputTemplate => 'Output Template';

  @override
  String toolFieldOutputTemplateHint(String placeholder) {
    return 'e.g. Successfully executed and built result: $placeholder';
  }

  @override
  String get toolSave => 'Save Tool';

  @override
  String get toolNameEmptyError => 'Tool Name cannot be empty';

  @override
  String toolSchemaParseError(String error) {
    return 'Schema JSON parse failed: $error';
  }

  @override
  String get settingsSaveButton => 'Save Settings';

  @override
  String get settingsSubtitleGeneral =>
      'Configure NovelAI image generation credentials, local storage directory, and Opus free-tier protection.';

  @override
  String get settingsSubtitleModels =>
      'Manage LLM services by provider, fetch model lists online, and automatically match models.dev capability metadata.';

  @override
  String get settingsSubtitlePresets =>
      'Manage Agent presets, configure system prompts, on-demand Skill libraries, and image generation parameter permissions.';

  @override
  String get settingsSubtitleDefaults =>
      'Configure startup default image generation model, sampling algorithm, and step guidance.';

  @override
  String get settingsSubtitleBill =>
      'Track Token usage bills for each model by period, powered by the local incremental ledger.';

  @override
  String get settingsSectionModelAndSampler => 'Model & Sampler';

  @override
  String get settingsDefaultModelTitle => 'Default Model';

  @override
  String get settingsDefaultModelSubtitle =>
      'Default factory model used at application startup or after parameter reset';

  @override
  String get settingsDefaultSamplerTitle => 'Default Sampler';

  @override
  String get settingsDefaultSamplerSubtitle =>
      'Default denoising sampler used during image generation';

  @override
  String get settingsDefaultNoiseScheduleTitle => 'Default Noise Schedule';

  @override
  String get settingsDefaultNoiseScheduleSubtitle =>
      'Time step schedule algorithm used during denoising';

  @override
  String get settingsSectionDefaultStepsAndScale => 'Default Steps & Scale';

  @override
  String get settingsDefaultStepsTitle => 'Default Steps (Steps)';

  @override
  String get settingsDefaultStepsSubtitle => 'Initial sampling iteration steps';

  @override
  String get settingsDefaultScaleTitle => 'Default CFG Scale';

  @override
  String settingsDefaultScaleSubtitle(String scale) {
    return 'Prompt guidance scale (current: $scale)';
  }

  @override
  String get settingsSectionAgentLoop => 'Agent Loop';

  @override
  String get settingsAgentMaxTurnsTitle => 'Agent Max Turns';

  @override
  String get settingsAgentMaxTurnsSubtitle =>
      'Maximum tool chain call turns allowed per single conversation before automatically wrapping up';

  @override
  String get settingsSectionUsageBill => 'Usage Bill';

  @override
  String get billPeriodToday => 'Today';

  @override
  String get billPeriodLast7Days => 'Last 7 Days';

  @override
  String get billPeriodLast30Days => 'Last 30 Days';

  @override
  String get billPeriodAll => 'All';

  @override
  String billSummaryRequestsAndTokens(int requests, String tokens) {
    return '$requests requests · Total $tokens tokens';
  }

  @override
  String get billEmptyRecords => 'No usage records in this period';

  @override
  String get billTableHeaderModel => 'Model';

  @override
  String get billTableHeaderRequests => 'Requests';

  @override
  String get billTableHeaderInput => 'Input';

  @override
  String get billTableHeaderOutput => 'Output';

  @override
  String get billTableHeaderCacheRead => 'Cache Read';

  @override
  String get billTableHeaderHitRate => 'Hit Rate';

  @override
  String get billTableHeaderTotal => 'Total';

  @override
  String get billTableTotalRow => 'Total';

  @override
  String get paramsPageTitle => 'Parameters';

  @override
  String get paramsPageSubtitle =>
      'Adjust model, resolution, and sampling attributes';

  @override
  String get paramsSectionModel => 'Model';

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
    return 'Seed Settings ($mode · $timing)';
  }

  @override
  String get paramsSeedModeRandomShort => 'Random';

  @override
  String get paramsSeedModeIncreaseShort => 'Increase';

  @override
  String get paramsSeedModeFixedShort => 'Fixed';

  @override
  String get paramsSeedTimingBefore => 'Before';

  @override
  String get paramsSeedTimingAfter => 'After';

  @override
  String get paramsSectionSampler => 'Sampler';

  @override
  String get paramsSeedModeGroup => 'Seed Mode';

  @override
  String get paramsSeedModeRandomTitle => '1. Random';

  @override
  String get paramsSeedModeRandomSubtitle =>
      'Generate a new random seed on each image generation';

  @override
  String get paramsSeedModeIncreaseTitle => '2. Increase';

  @override
  String get paramsSeedModeIncreaseSubtitle =>
      'Increment seed value by 1 on each image generation';

  @override
  String get paramsSeedModeFixedTitle => '3. Fixed';

  @override
  String get paramsSeedModeFixedSubtitle => 'Keep current seed value unchanged';

  @override
  String get paramsSeedTimingGroup => 'Generation Timing';

  @override
  String get paramsSeedRandomizeNow => 'Randomize Seed Now';

  @override
  String get paramsSeedResetRandom => 'Reset to Random (-1)';

  @override
  String get paramsSectionAdvanced => 'Advanced Settings';

  @override
  String get paramsPromptGuidanceRescale => 'Prompt Guidance Rescale';

  @override
  String get paramsSectionNoiseSchedule => 'Noise Schedule';

  @override
  String get paramsStripMetadata => 'Strip Metadata';

  @override
  String get paramsStripMetadataSubtitle =>
      'Remove all generation parameters and steganography when exporting and copying';

  @override
  String get paramsAddWatermark => 'Add Watermark';

  @override
  String get paramsAddWatermarkSubtitle =>
      'Applies only on copy/download, not displayed on canvas';

  @override
  String get paramsKeepOriginalImage => 'Keep Original Image';

  @override
  String get paramsKeepOriginalImageSubtitle =>
      'Save an additional clean raw image (_raw.png) when saving generated images';

  @override
  String get resolutionTitle => 'Resolution';

  @override
  String get resolutionOrientationLandscape => 'Landscape';

  @override
  String get resolutionOrientationPortrait => 'Portrait';

  @override
  String get resolutionOrientationSquare => 'Square';

  @override
  String get resolutionOrientationSquareDisabled =>
      'Square (1:1 aspect ratio unavailable for Wallpaper)';

  @override
  String get resolutionSwapTooltip => 'Swap';

  @override
  String watermarkPickImageFailed(String error) {
    return 'Failed to select image: $error';
  }

  @override
  String get watermarkPositionTopLeft => 'Top Left';

  @override
  String get watermarkPositionTopRight => 'Top Right';

  @override
  String get watermarkPositionCenter => 'Center';

  @override
  String get watermarkPositionBottomLeft => 'Bottom Left';

  @override
  String get watermarkPositionBottomRight => 'Bottom Right';

  @override
  String get watermarkSmartPositionApplied =>
      'Positioned smartly on low-detail area';

  @override
  String get watermarkSmartPositionNoImage =>
      'No image on canvas for smart positioning';

  @override
  String get watermarkPositionTitle => 'Watermark Position';

  @override
  String get watermarkSmartPositionTooltip =>
      'Smart Positioning: Analyze canvas image and place watermark in the lowest-detail area';

  @override
  String get watermarkPositionPillTooltip =>
      'Drag to position watermark on canvas (or press ESC to exit)';

  @override
  String watermarkPositionPillLabel(String position) {
    return 'Position: $position';
  }

  @override
  String get watermarkAutoPosition => 'Auto Position';

  @override
  String get watermarkAutoPositionSubtitle =>
      'Analyze image on each composition and automatically place in lowest-detail area';

  @override
  String get watermarkAutoContrast => 'Auto Contrast';

  @override
  String get watermarkAutoContrastSubtitle =>
      'Automatically darken or brighten based on background luminance to ensure visibility';

  @override
  String get watermarkScalePercent => 'Watermark Scale (%)';

  @override
  String get watermarkOpacityPercent => 'Opacity (%)';

  @override
  String get watermarkMarginPercent => 'Margin (%)';

  @override
  String get watermarkBlindTitle => 'Blind Watermark';

  @override
  String get watermarkBlindSubtitle =>
      'Frequency-domain invisible watermark, invisible to the eye; extractable by pasting image in metadata dialog';

  @override
  String get watermarkBlindEnable => 'Enable';

  @override
  String get watermarkBlindTextHint => 'Signature / copyright text';

  @override
  String get watermarkBlindStrength => 'Blind Watermark Strength';

  @override
  String get watermarkLoadedImage => 'Watermark image loaded';

  @override
  String get watermarkEffectiveOnExport => 'Effective only upon copy/download';

  @override
  String get watermarkChangeImageTooltip => 'Change image';

  @override
  String get watermarkClearImageTooltip => 'Clear watermark image';

  @override
  String get watermarkSelectLocalImage =>
      'Click to select local watermark image (PNG/JPG)';

  @override
  String watermarkOverlayScale(String scale) {
    return 'Scale: $scale%';
  }

  @override
  String watermarkOverlayPosition(int x, int y) {
    return 'Position: $x%, $y%';
  }

  @override
  String get promptsPageTitle => 'Prompt Management';

  @override
  String get promptsPageSubtitle =>
      'Positive prompts, negative undesired content, and global fixed affixes';

  @override
  String get promptsCorePromptHint =>
      'Enter core tags or natural language prose, e.g.: 1girl, solo, silver hair, masterpiece...';

  @override
  String get promptsSwitchToTabbedMode => 'Switch to tabbed mode';

  @override
  String get promptsCustomUndesiredHint =>
      'Enter custom negative tags, e.g.: bad hands, blurry, extra limbs...';

  @override
  String get promptsSwitchToStackedMode => 'Switch to stacked mode';

  @override
  String get promptsTabbedPromptHint =>
      'Enter core tags or natural language prose, e.g.: 1girl, solo, silver hair...';

  @override
  String get promptsTabbedUndesiredHint =>
      'Exclude unwanted artifacts or defects, e.g.: lowres, bad anatomy, bad hands...';

  @override
  String get promptsResizePromptTooltip =>
      'Drag to resize prompt input height (double-click to reset)';

  @override
  String get promptsIncreaseWeightTooltip =>
      'Increase tag numeric weight (Ctrl+Up, format x.x::tag::)';

  @override
  String get promptsDecreaseWeightTooltip =>
      'Decrease tag numeric weight (Ctrl+Down, format x.x::tag::)';

  @override
  String get promptsToggleDisabledTooltip => 'Toggle disabled state (Ctrl+/)';

  @override
  String get promptsFormatTooltip =>
      'Format and convert SD syntax (Ctrl+Shift+F)';

  @override
  String get promptsTagBrowserTooltip => 'Open Danbooru tag browser';

  @override
  String get promptsAffixesHint => 'Global fixed prefix & suffix affixes';

  @override
  String get charPromptDeckTabCharacter => 'Character Prompts';

  @override
  String get charPromptDeckTabAffixes => 'Fixed Affixes';

  @override
  String get charPromptEnabled => 'Enabled';

  @override
  String get charPromptDisabled => 'Disabled';

  @override
  String get charPromptPositionAi => 'AI Auto';

  @override
  String get charPromptPositionCustom => 'Custom';

  @override
  String get charPromptIsolationHint => 'Isolated character prompts';

  @override
  String get charPromptUnsupportedModel =>
      'Current model does not support character prompts (V4+ only). Settings below are kept but will not be used in generation.';

  @override
  String get charPromptEmptyTitle => 'No character prompts yet';

  @override
  String get charPromptEmptyDescription =>
      'Click Female / Male / Other preset buttons above to start multi-character generation';

  @override
  String get charPromptExitCanvasEditTooltip => 'Exit canvas position editing';

  @override
  String get charPromptEnterCanvasEditTooltip =>
      'Edit character position on canvas';

  @override
  String get charPromptCanvasEditing => 'Editing';

  @override
  String get charPromptCanvasEdit => 'Canvas Edit';

  @override
  String get charPromptAddFemaleTooltip =>
      'Add female character (initial prompt: girl)';

  @override
  String get charPromptAddMaleTooltip =>
      'Add male character (initial prompt: boy)';

  @override
  String get charPromptAddOtherTooltip =>
      'Add other character (empty initial prompt)';

  @override
  String get charPromptLimitReached => 'Limit Reached';

  @override
  String get charPromptGenderFemale => 'Female';

  @override
  String get charPromptGenderMale => 'Male';

  @override
  String get charPromptGenderOther => 'Other';

  @override
  String charPromptDefaultName(int index) {
    return 'Character $index';
  }

  @override
  String get charPromptNameHint => 'Character name (optional)';

  @override
  String get charPromptSaveToLibraryTooltip =>
      'Save character to prompt library';

  @override
  String get charPromptDeleteTooltip => 'Delete character';

  @override
  String get charPromptEnable => 'Enable';

  @override
  String get charPromptDisable => 'Disable';

  @override
  String get charPromptPromptHint =>
      'Character prompt, e.g.: 1girl, silver hair, twintails, smile...';

  @override
  String get charPromptResizePromptTooltip =>
      'Drag to resize prompt height (double-click to reset)';

  @override
  String get charPromptNegativePromptHint =>
      'Character negative prompt (optional), e.g.: bad hands, blurry...';

  @override
  String get charPromptResizeNegativeTooltip =>
      'Drag to resize negative prompt height (double-click to reset)';

  @override
  String get affixPrefixTitle => 'Prefix (placed before main prompt)';

  @override
  String get affixResizePrefixTooltip =>
      'Drag to resize prefix height (double-click to reset)';

  @override
  String get affixSuffixTitle => 'Suffix (placed after main prompt)';

  @override
  String get affixResizeSuffixTooltip =>
      'Drag to resize suffix height (double-click to reset)';

  @override
  String get annotHistoryTitle => 'History ';

  @override
  String get annotHistoryEmpty => 'No images';

  @override
  String get annotHistoryAddedAsReference =>
      'Added history image to canvas as reference';

  @override
  String get annotHistoryImportTooltip => 'Import local image as reference';

  @override
  String get annotHistoryImportImage => 'Import Image';

  @override
  String get inpaintPageTitle => 'Inpaint Settings';

  @override
  String get inpaintPageSubtitle =>
      'Inpainting & high-precision latent focus closeup';

  @override
  String get inpaintSectionMode => 'Inpaint Mode';

  @override
  String get inpaintModeFocus => 'Focus Closeup';

  @override
  String get inpaintModeFocusSubtitle => 'Supersampled lossless blend';

  @override
  String get inpaintModeStandard => 'Standard Inpaint';

  @override
  String get inpaintModeStandardSubtitle => 'Full canvas inpainting';

  @override
  String get inpaintModeAiEdit => 'AI Edit';

  @override
  String get inpaintModeAiEditSubtitle => 'External image model repaint';

  @override
  String get inpaintAiEditAspectRatio => 'Aspect Ratio';

  @override
  String get inpaintAiEditFollowSource => 'Match Source';

  @override
  String get inpaintAiEditResolution => 'Resolution';

  @override
  String get inpaintAiEditDefaultResolution => 'Default';

  @override
  String get inpaintContextPadding => 'Context Padding (px)';

  @override
  String get inpaintStrength => 'Inpaint Strength';

  @override
  String get inpaintNoise => 'Noise';

  @override
  String get inpaintSectionInstruction => 'Edit Instructions';

  @override
  String get inpaintSectionPrompt => 'Prompt Settings';

  @override
  String get inpaintReuseMainPromptAsInstruction =>
      'Reuse main prompt as instruction';

  @override
  String get inpaintReuseMainPrompt => 'Reuse main prompt';

  @override
  String get inpaintCustomInstruction => 'Custom Instruction';

  @override
  String get inpaintCustomPrompt => 'Custom Inpaint Prompt';

  @override
  String get inpaintInstructionHint =>
      'Enter natural language instruction, e.g.: change background to sunset beach...';

  @override
  String get inpaintPromptHint => 'Enter inpaint positive prompt...';

  @override
  String get inpaintMainPrompt => 'Main Positive Prompt';

  @override
  String get inpaintMainNegativePrompt => 'Main Negative Prompt';

  @override
  String get inpaintReuseMainNegative => 'Reuse main negative prompt';

  @override
  String get inpaintCustomNegative => 'Custom Negative Prompt';

  @override
  String get inpaintNegativePromptHint => 'Enter inpaint negative prompt...';

  @override
  String get inpaintImageModel => 'Image Model';

  @override
  String get inpaintConsumeQuota => 'Consumes model quota';

  @override
  String get inpaintProvider => 'Provider';

  @override
  String get inpaintModel => 'Model';

  @override
  String get inpaintNoModelConfigured =>
      'No image model configured. Go to Settings -> Models -> AI Edit to select a model provider and model with image output capabilities (e.g. nano banana / gpt-image).';

  @override
  String get inpaintLatentFocusGeometry => 'Latent Focus Geometry';

  @override
  String get inpaintRequiresPoints => 'Requires Points';

  @override
  String get inpaintTargetSelection => 'Target Selection';

  @override
  String get inpaintContextCrop => 'Context Extension';

  @override
  String get inpaintRequestResolution => 'Request Resolution';

  @override
  String inpaintSupersample(String scale) {
    return '${scale}x supersampling';
  }

  @override
  String inpaintReusedLabel(String label) {
    return 'Reused $label';
  }

  @override
  String get inpaintReusedPromptEmpty => '(Empty, configure in Prompt tab)';

  @override
  String get inpaintOverlayEmptyHint =>
      'Generate or select an image to start inpainting';

  @override
  String inpaintOverlayContextCrop(int padding) {
    return 'Context extension +${padding}px';
  }

  @override
  String get inpaintOverlayInProgress => 'Inpainting...';

  @override
  String get inpaintOverlayAiEditHint =>
      'AI Edit · Full image repaint, no region selection needed';

  @override
  String get inpaintToolRect => 'Marquee';

  @override
  String get inpaintToolBrush => 'Brush';

  @override
  String get inpaintToolEraser => 'Eraser';

  @override
  String get inpaintClearMask => 'Clear Mask';

  @override
  String canvasImportedReference(String fileName) {
    return 'Imported reference image: $fileName';
  }

  @override
  String get canvasDropTargetTitle =>
      'Drop image to import (Metadata will be auto-detected)';

  @override
  String get canvasCopiedRawImage => 'Original image copied to clipboard';

  @override
  String get canvasCopiedImage => 'Image copied to clipboard';

  @override
  String get canvasCopyImageFailed => 'Failed to copy image';

  @override
  String get canvasActionAddAnnotation => 'Add Annotation';

  @override
  String canvasActionViewAnnotation(int count) {
    return 'View Annotations ($count)';
  }

  @override
  String get canvasActionSendToInpaint => 'Send to Inpaint';

  @override
  String get canvasActionUpscale => 'Upscale';

  @override
  String get canvasActionCopyImage => 'Copy Image';

  @override
  String get canvasActionCopyRawImage => 'Copy Original Image';

  @override
  String get canvasActionCopyPrompt => 'Copy Prompt';

  @override
  String get canvasCopiedPrompt => 'Prompt copied to clipboard';

  @override
  String get canvasActionReuseParams => 'Reuse Parameters';

  @override
  String get canvasAppliedParams =>
      'Applied image parameters to the left panel';

  @override
  String get canvasActionViewLightbox => 'View Full Size';

  @override
  String get canvasActionDeleteFromHistory => 'Delete from History';

  @override
  String get canvasDeletedFromHistory => 'Image deleted from history';

  @override
  String get canvasActionClearHistory => 'Clear History';

  @override
  String get canvasClearedHistory => 'History cleared';

  @override
  String canvasClearHistoryAutoSaveMessage(int count) {
    return 'Are you sure you want to clear $count images from canvas history? Only UI records will be cleared, locally saved files are kept. This action cannot be undone.';
  }

  @override
  String canvasClearHistoryManualSaveMessage(int count) {
    return 'Are you sure you want to clear $count images from history? Unsaved cached images will be deleted, manually saved files are kept. This action cannot be undone.';
  }

  @override
  String get canvasHistoryEmpty => 'No history';

  @override
  String get canvasCopySeedTooltip => 'Click to copy seed';

  @override
  String get canvasCopiedSeed => 'Seed copied to clipboard';

  @override
  String get canvasEnterAnnotationTooltip =>
      'Enter annotation mode (Select / Pin / Full Image)';

  @override
  String get canvasAnnotate => 'Annotate';

  @override
  String canvasAnnotateWithCount(int count) {
    return 'Annotate ($count)';
  }

  @override
  String get canvasSaveButtonTooltip =>
      'Save current image to local directory (apply metadata and watermark per export settings)';

  @override
  String canvasSavedImage(String path) {
    return 'Saved: $path';
  }

  @override
  String get canvasSaveFailed =>
      'Save failed, please check storage directory settings';

  @override
  String get canvasSaveImage => 'Save Image';

  @override
  String get canvasUnseenLatestBanner =>
      'New image generated · Click to view latest';

  @override
  String get canvasOpenHistoryTooltip => 'Expand history';

  @override
  String get canvasEmptyTitle => 'No image on canvas';

  @override
  String get canvasEmptyDescription =>
      'Configure parameters on the left to generate images. History will be displayed as a vertical stream.';

  @override
  String get metadataBlindWatermarkContent => 'Blind Watermark Content';

  @override
  String get metadataBlindWatermarkNotFound => 'No blind watermark detected';

  @override
  String get metadataDialogTitle => 'Image Metadata Reader';

  @override
  String get metadataPromptTitle => 'Prompt';

  @override
  String get metadataCopiedPrompt => 'Prompt copied to clipboard';

  @override
  String get metadataNegativePromptTitle => 'Negative Prompt';

  @override
  String get metadataCopiedNegativePrompt =>
      'Negative prompt copied to clipboard';

  @override
  String get metadataDimensionAuto => 'Auto';

  @override
  String metadataDimensions(String width, String height) {
    return 'Dimensions: $width x $height';
  }

  @override
  String get metadataModelUnknown => 'Unknown Model';

  @override
  String get metadataSamplerDefault => 'Default';

  @override
  String metadataModelAndSampler(String model, String sampler) {
    return 'Model: $model  ·  Sampler: $sampler';
  }

  @override
  String metadataSeedLabel(String seed) {
    return 'Seed: $seed';
  }

  @override
  String get metadataCharacterPromptsTitle => 'Character Prompts';

  @override
  String metadataCharacterIndex(int index) {
    return 'Character $index';
  }

  @override
  String metadataNegativePrefix(String negative) {
    return 'Negative: $negative';
  }

  @override
  String get metadataParametersTitle => 'Generation Parameters';

  @override
  String get metadataParamModel => 'Model';

  @override
  String get metadataParamUnknown => 'Unknown';

  @override
  String get metadataParamSampler => 'Sampler';

  @override
  String get metadataParamDefault => 'Default';

  @override
  String get metadataParamSteps => 'Steps';

  @override
  String get metadataParamSeed => 'Seed';

  @override
  String get metadataParamSeedRandom => 'Random';

  @override
  String get metadataParamNoiseSchedule => 'Noise Schedule';

  @override
  String get metadataParamQualityPreset => 'Quality Preset';

  @override
  String get metadataParamUcPreset => 'UC Preset';

  @override
  String get metadataParamTransparentBg => 'Transparent Background';

  @override
  String get metadataParamEnabled => 'Enabled';

  @override
  String get metadataRawJsonTitle => 'Raw Metadata (JSON / Text)';

  @override
  String get metadataCopyRawTooltip => 'Copy raw text';

  @override
  String get metadataCopiedRaw => 'Raw metadata copied to clipboard';

  @override
  String get metadataExtractBlindWatermark => 'Extract Blind Watermark';

  @override
  String get metadataImportAsReference => 'Import as Reference';

  @override
  String get metadataImportedReference => 'Imported reference image';

  @override
  String get metadataApplyToWorkbench => 'Apply All Parameters to Studio';

  @override
  String dockAbortWithSteps(int current, int total) {
    return 'Abort Generation ($current/$total)';
  }

  @override
  String dockGenerateWithCost(int cost) {
    return 'Generate Image ($cost Anlas)';
  }

  @override
  String get dockGenerateNeedPoints => 'Generate Image (Costs Anlas)';

  @override
  String get dockNoAccountInfo => 'Account info unavailable (Check API Key)';

  @override
  String get dockAiEditing => 'AI Editing...';

  @override
  String get dockInpainting => 'Inpainting...';

  @override
  String get dockRefreshTooltip => 'Refresh stamina and points';

  @override
  String get sidebarTabParameters => 'Parameters';

  @override
  String get sidebarTabInpaint => 'Inpaint';

  @override
  String get sidebarSettingsTooltip =>
      'Global settings (API Key / Storage / LLM)';

  @override
  String get promptResizeTooltip =>
      'Drag to resize height (double-click to reset)';

  @override
  String get studioClipboardImageDefaultName => 'clipboard_image.png';

  @override
  String get studioImportedReference => 'Imported reference image';

  @override
  String get boardPastedImage => 'Image pasted to board';

  @override
  String boardImportedReferenceNamed(String name) {
    return 'Imported reference image: $name';
  }

  @override
  String get boardAddedHistoryImage => 'History image added as board reference';

  @override
  String get boardDropInternalHint => 'Release mouse to place reference image';

  @override
  String get boardDropExternalHint =>
      'Release mouse to import external reference image';

  @override
  String get boardExitAnnotation => 'Exit Annotation';

  @override
  String get boardSendAllToAi => 'Send All Annotations to AI';

  @override
  String get boardWireMissedTarget =>
      'No selection or pin hit, connection cancelled';

  @override
  String get boardToolPan => 'Pan';

  @override
  String get boardToolRect => 'Selection Box';

  @override
  String get boardToolPoint => 'Pin Anchor';

  @override
  String get boardToolAddNote => '+ Note';

  @override
  String get boardToolAddImage => '+ Reference';

  @override
  String get boardToolPasteImage => 'Paste Image (Ctrl+V)';

  @override
  String get boardToolResetView => 'Reset View';

  @override
  String get boardImageCardMainTitle => 'Main Image (Current Generation)';

  @override
  String boardImageCardRefTitle(int width, int height) {
    return 'Reference Image (${width}x$height)';
  }

  @override
  String get boardImageCardRemoveTooltip => 'Remove reference image card';

  @override
  String get boardImageResizeTooltip =>
      'Drag to resize image card (Hold Shift to lock aspect ratio)';

  @override
  String get boardImageSendToInpaint => 'Send to Inpaint';

  @override
  String get boardAnnotationDeleteRect => 'Delete selection';

  @override
  String get boardAnnotationDeletePoint => 'Delete pin';

  @override
  String get boardAnnotationResizeRect => 'Drag to resize selection';

  @override
  String get boardAnnotationSelectTooltip => 'Click to select annotation';

  @override
  String get boardWireDragSourceTooltip =>
      'Drag to connect to selection or pin';

  @override
  String get boardNoteConnected => 'Connected';

  @override
  String get boardNoteTitle => 'Note';

  @override
  String get boardNoteDisconnectTooltip => 'Disconnect wire';

  @override
  String get boardNoteDeleteTooltip => 'Delete note';

  @override
  String get boardNoteHint => 'Enter feedback or notes...';

  @override
  String get boardNoteResizeTooltip => 'Drag to resize note';

  @override
  String charPosCanvasTempBoard(int width, int height) {
    return 'Temporary Canvas · $width × $height';
  }

  @override
  String get posControlsDoneEditing => 'Done Editing';

  @override
  String get lightboxCloseTooltip => 'Close full size view';

  @override
  String get librarySearchHint => 'Search combo name, prompt, tags...';

  @override
  String get libraryDataManagement => 'Data Management';

  @override
  String get libraryExportJson => 'Export Library (JSON)';

  @override
  String get libraryImportJson => 'Import Library (JSON)';

  @override
  String get libraryManageButton => 'Manage';

  @override
  String get libraryNewCombo => 'New Prompt Combo';

  @override
  String get libraryCategorySidebarTitle => 'Categories';

  @override
  String libraryEntriesCount(int count) {
    return '$count items';
  }

  @override
  String get libraryCategoryAll => 'All';

  @override
  String get libraryExportCopied =>
      'Copied prompt library JSON to clipboard for backup or sharing';

  @override
  String libraryExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get libraryImportDialogTitle => 'Import Library JSON';

  @override
  String get libraryImportPrompt => 'Paste exported library JSON text:';

  @override
  String libraryImportSuccess(int count) {
    return 'Successfully imported $count prompt combo entries';
  }

  @override
  String libraryImportFailed(String error) {
    return 'Import failed, please check JSON format: $error';
  }

  @override
  String libraryApplyAsCharacter(String title) {
    return 'Added character card: $title';
  }

  @override
  String libraryApplyReplace(String title) {
    return 'Replaced workbench prompt: $title';
  }

  @override
  String libraryApplyAppendBoth(String title) {
    return 'Appended positive and negative prompts: $title';
  }

  @override
  String libraryApplyAppendPrompt(String title) {
    return 'Appended main prompt: $title';
  }

  @override
  String get libraryReturnToWorkbench => 'Return to Workbench';

  @override
  String get libraryDeleteDialogTitle => 'Delete Prompt Combo';

  @override
  String libraryDeleteDialogMessage(String title) {
    return 'Are you sure you want to delete prompt combo \"$title\"? This action cannot be undone.';
  }

  @override
  String libraryDeletedCombo(String title) {
    return 'Deleted prompt combo: $title';
  }

  @override
  String get libraryEmptyTitle => 'No entries in prompt library';

  @override
  String get libraryNoMatchingTitle => 'No matching prompt combos';

  @override
  String get libraryEmptyDescription =>
      'Click \"New Prompt Combo\" in top right to create your first combo';

  @override
  String get libraryNoMatchingDescription =>
      'Try changing search terms or category filters';

  @override
  String get libraryResetFilter => 'Reset filters';

  @override
  String libraryCardCopiedPrompt(String title) {
    return 'Copied prompt of \"$title\" to clipboard';
  }

  @override
  String get libraryMenuAppendToPrompt => 'Append to Workbench Prompt';

  @override
  String get libraryMenuReplacePrompt => 'Replace Workbench Prompt';

  @override
  String get libraryMenuAddAsCharacter => 'Add as Character Card';

  @override
  String get libraryMenuCopyPrompt => 'Copy Prompt';

  @override
  String get libraryMenuEdit => 'Edit';

  @override
  String get libraryCardApply => 'Apply to Workbench';

  @override
  String get libraryCardAddAsCharacterTooltip =>
      'Add as workbench character card';

  @override
  String get libraryCardAddCharacter => '+ Character';

  @override
  String get libraryCardNoPreview => 'No Preview';

  @override
  String get libraryEditCustomCategoryOption => 'Custom...';

  @override
  String libraryEditPickImageFailed(String error) {
    return 'Failed to select image: $error';
  }

  @override
  String get libraryEditAdoptedCanvasImage =>
      'Current canvas image set as preview';

  @override
  String get libraryEditCanvasNoImage => 'No generated image on canvas';

  @override
  String get libraryEditWorkspacePromptEmpty =>
      'Workbench main prompt is empty';

  @override
  String get libraryEditWorkspaceNegativeEmpty =>
      'Workbench negative prompt is empty';

  @override
  String get libraryEditTitleEmpty => 'Please enter a combo title';

  @override
  String get libraryEditPromptEmpty => 'Please enter main prompt content';

  @override
  String libraryEditUpdatedSuccess(String title) {
    return 'Updated prompt combo: $title';
  }

  @override
  String libraryEditCreatedSuccess(String title) {
    return 'Added prompt combo: $title';
  }

  @override
  String libraryEditSaveFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get libraryEditDialogTitleEdit => 'Edit Prompt Combo';

  @override
  String get libraryEditDialogTitleNew => 'New Prompt Combo';

  @override
  String get libraryEditFieldTitle => 'Title';

  @override
  String get libraryEditFieldTitleHint =>
      'e.g. Cyberpunk Catgirl / Anime Watercolor';

  @override
  String get libraryEditFieldCategory => 'Category';

  @override
  String get libraryEditFieldCustomCategoryHint =>
      'Enter custom category name (e.g. Lighting, Angle)';

  @override
  String get libraryEditFieldPrompt => 'Main Prompt';

  @override
  String get libraryEditFillFromPrompt => 'Fill from Workbench';

  @override
  String get libraryEditFieldPromptHint =>
      'Enter positive prompt (e.g. 1girl, hatsune miku, cybernetic...)';

  @override
  String get libraryEditFieldNegative => 'Negative Prompt';

  @override
  String get libraryEditCharacterOnlyBadge => 'Character category only';

  @override
  String get libraryEditFillFromNegative => 'Fill from Negative';

  @override
  String get libraryEditFieldNegativeHint =>
      'Character-specific negative tags (e.g. worst quality, bad hands...)';

  @override
  String get libraryEditFieldTags => 'Search Tags';

  @override
  String get libraryEditFieldTagsHint =>
      'For quick filtering, separated by commas (e.g. miku, watercolor, cyber)';

  @override
  String get libraryEditSaveButton => 'Save Changes';

  @override
  String get libraryEditCreateButton => 'Create Prompt Combo';

  @override
  String get libraryEditPosterTitle => 'Set Preview Image';

  @override
  String get libraryEditPickLocalImage => 'Choose Local Image';

  @override
  String get libraryEditUseCanvasImage => 'Use Current Canvas Image';

  @override
  String get libraryEditRemovePreviewImage => 'Remove Preview Image';

  @override
  String tagAcAlias(String alias) {
    return 'Alias: $alias';
  }

  @override
  String get tagBrowserTitle => 'Danbooru Tag Inspiration Library';

  @override
  String get tagBrowserSearchHint =>
      'Search 140k+ Danbooru tags in English or Chinese...';

  @override
  String tagBrowserAddedTag(String tag) {
    return 'Added tag: $tag';
  }

  @override
  String tagBrowserAddedTagWithZh(String tag, String zh) {
    return 'Added tag: $tag ($zh)';
  }

  @override
  String get tagBrowserNoMatchingTitle => 'No matching tags found';

  @override
  String get tagBrowserNoMatchingDesc =>
      'Try searching with different English or Chinese keywords';

  @override
  String get chatSessionManagementTooltip => 'Session Management';

  @override
  String get chatModelNoVisionNotice =>
      'Current model does not support image input, please switch to a multimodal model first';

  @override
  String chatMaxAttachmentsNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'At most $count images can be attached at a time',
      one: 'At most 1 image can be attached at a time',
    );
    return '$_temp0';
  }

  @override
  String get chatImageParseFailedNotice =>
      'Image parsing failed, please try another image';

  @override
  String get chatModelNoVisionBeforeSendNotice =>
      'Current model does not support image input, please switch to a multimodal model before sending';

  @override
  String get chatInputHint =>
      'Enter drawing ideas, or type /nai <prompt> for quick generation...';

  @override
  String get chatThinkingLabel => 'Thinking:';

  @override
  String get chatThinkingEffortOff => 'Off';

  @override
  String get chatThinkingEffortLow => 'Low';

  @override
  String get chatThinkingEffortMedium => 'Medium';

  @override
  String get chatThinkingEffortHigh => 'High';

  @override
  String get chatSessionUsageEmpty =>
      'No Token usage recorded for current session';

  @override
  String get chatSessionUsageTitle => 'Current session Token usage';

  @override
  String chatSessionUsageDetail(String input, String output, String total) {
    return 'Input $input · Output $output · Total $total';
  }

  @override
  String chatSessionUsageCacheRead(String cacheRead) {
    return ' · Cache read $cacheRead';
  }

  @override
  String chatSessionUsageCacheReadWithRate(String cacheRead, String rate) {
    return ' · Cache read $cacheRead ($rate%)';
  }

  @override
  String get chatToolNoOutput => '(No output)';

  @override
  String chatToolResultSummary(int count, String firstLine) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count lines · $firstLine',
      one: '1 line · $firstLine',
    );
    return '$_temp0';
  }

  @override
  String get chatThinkingProgress => 'Thinking...';

  @override
  String get chatConceiving => 'Conceiving...';

  @override
  String get chatRemoveAttachmentTooltip => 'Remove attachment';

  @override
  String get chatAddAttachmentTooltip => 'Add attachment';

  @override
  String get rewindBackTooltip => 'Back to Chat (ESC)';

  @override
  String get rewindTitle => 'Rewind Checkpoints';

  @override
  String get rewindEscExit => 'ESC to Exit';

  @override
  String get rewindDescription =>
      'Select a chat checkpoint to restore. Restoring will discard all changes and chat messages after this checkpoint.';

  @override
  String get rewindEmptyTitle =>
      'No chat checkpoints available to rewind in current session';

  @override
  String get rewindBackAction => 'Back to Chat';

  @override
  String get rewindLatestBadge => '(Latest)';

  @override
  String rewindSelectedTurn(int index) {
    return 'Selected turn #$index';
  }

  @override
  String get rewindSelectPrompt => 'Please select a turn to rewind above';

  @override
  String get rewindCancelButton => 'Cancel';

  @override
  String get rewindConfirmButton => 'Rewind to This Checkpoint';

  @override
  String get sessionRenameTitle => 'Rename Session';

  @override
  String get sessionRenameHint => 'Enter a new session name...';

  @override
  String get sessionSave => 'Save';

  @override
  String get sessionCancel => 'Cancel';

  @override
  String get sessionDeleteTitle => 'Delete Session';

  @override
  String sessionDeleteConfirm(String title) {
    return 'Are you sure you want to permanently delete session \"$title\"? This action cannot be undone.';
  }

  @override
  String get sessionDeleteConfirmButton => 'Delete';

  @override
  String sessionDateFormat(int month, int day, String time) {
    return '$month/$day $time';
  }

  @override
  String get sessionBackTooltip => 'Back to Chat';

  @override
  String get sessionTitle => 'Session Management';

  @override
  String get sessionNew => 'New Session';

  @override
  String get sessionSearchHint => 'Search history sessions...';

  @override
  String get sessionNoMatchingTitle => 'No matching sessions found';

  @override
  String get sessionEmptyTitle => 'No session history recorded';

  @override
  String get sessionCurrentBadge => 'Current';

  @override
  String get sessionRenameAction => 'Rename';

  @override
  String get sessionDeleteAction => 'Delete';

  @override
  String sessionMessageCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count messages',
      one: '1 message',
    );
    return '$_temp0';
  }

  @override
  String get askCardDefaultHeader => 'Question for User';

  @override
  String get askCardPendingConfirm => 'Pending Confirmation';

  @override
  String get askCardCancel => 'Cancel';

  @override
  String get askCardSubmit => 'Submit Answer';

  @override
  String get askCardCustomInputHint => 'Enter custom answer...';

  @override
  String get chatThinkingProcess => 'Thinking Process';

  @override
  String get canvasBadgeUnsaved => 'Unsaved';

  @override
  String get canvasBadgeUpscale => 'Upscaled';

  @override
  String get canvasBadgeInpaint => 'Inpainted';

  @override
  String get canvasBadgeAiEdit => 'AI Edited';

  @override
  String get canvasBadgeImported => 'Imported';

  @override
  String get tagCatGeneral => 'General';

  @override
  String get tagCatArtist => 'Artist';

  @override
  String get tagCatCopyright => 'Copyright';

  @override
  String get tagCatCharacter => 'Character';

  @override
  String get tagCatMeta => 'Meta';

  @override
  String get llmProtocolOpenAiChat => 'OpenAI-compatible (/chat/completions)';

  @override
  String get llmProtocolOpenAiResponses => 'Response (/responses)';

  @override
  String get llmProtocolAnthropicMessages => 'Message (/messages)';

  @override
  String get thinkingFormatAuto => 'Auto (detect by endpoint)';

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
  String get libraryCatCharacter => 'Character';

  @override
  String get libraryCatStyle => 'Style';

  @override
  String get libraryCatAttire => 'Attire';

  @override
  String get libraryCatComposition => 'Composition';

  @override
  String get libraryCatEnvironment => 'Environment';

  @override
  String get libraryCatEffect => 'Effects';

  @override
  String get libraryCatOther => 'Other';

  @override
  String get libraryCatCustom => 'Custom...';

  @override
  String get vmGenDoneUnsaved =>
      'Generation complete (unsaved, click save at the canvas bottom-right)';

  @override
  String vmGenDoneSavedTo(String path) {
    return 'Generation complete, saved to $path';
  }

  @override
  String get vmGenLocalPath => 'local storage';

  @override
  String get vmGenNoSaveDir =>
      'No local storage directory set. Configure the save path in Settings first.';

  @override
  String get vmGenSaveFailedNoTarget =>
      'Failed to save image: image not found or storage directory not writable.';

  @override
  String vmGenSavedTo(String path) {
    return 'Saved to $path';
  }

  @override
  String vmGenSaveFailed(String error) {
    return 'Failed to save image: $error';
  }

  @override
  String get vmGenAborted => 'Generation aborted';

  @override
  String get vmGenEmptyPrompt =>
      'Prompt cannot be empty. Enter a description on the left panel or in the chat first.';

  @override
  String get vmGenNoApiKey =>
      'NovelAI API Key not configured. Open Settings at the top-right.';

  @override
  String vmGenRequesting(int width, int height, int steps) {
    return 'Requesting NovelAI generation (${width}x$height, $steps steps)...';
  }

  @override
  String vmGenFailed(String error) {
    return 'Generation failed: $error';
  }

  @override
  String get vmUpscaleNoImage => 'No image on the canvas to upscale.';

  @override
  String get vmUpscaleNoApiKey => 'NovelAI API Key not configured.';

  @override
  String get vmUpscaleRunning => 'Upscaling image...';

  @override
  String vmUpscaleDoneUnsaved(int width, int height) {
    return 'Upscale complete (${width}x$height, unsaved)';
  }

  @override
  String vmUpscaleDone(int width, int height) {
    return 'Upscale complete (${width}x$height)';
  }

  @override
  String vmUpscaleFailed(String error) {
    return 'Upscale failed: $error';
  }

  @override
  String get vmChatSlashNoImage =>
      'Slash commands do not support attached images. Send a normal chat message instead.';

  @override
  String vmChatSlashFailed(String error) {
    return 'Command failed: $error';
  }

  @override
  String vmChatRetryNotice(int attempt, int max, String reason, String retry) {
    return 'Transient failure, auto-retrying ($attempt/$max): $reason · $retry';
  }

  @override
  String vmChatRetryDelayed(int seconds) {
    return 'retrying in ${seconds}s';
  }

  @override
  String get vmChatRetrySoon => 'retrying now';

  @override
  String vmChatCompacted(int before, int after) {
    return 'Context auto-compacted ($before → $after tokens). Earlier messages were replaced with a summary.';
  }

  @override
  String vmChatError(String error) {
    return 'Chat error: $error';
  }

  @override
  String get vmChatForceAborted => 'Current generation force-terminated';

  @override
  String get vmCostNoOpusQuota => 'Current account has no Opus free quota';

  @override
  String vmCostEstimate(int cost) {
    return 'Estimated cost: $cost Anlas';
  }

  @override
  String get vmCostWillCost => 'Will consume Anlas';

  @override
  String get vmCostTitle => 'Anlas Cost Request';

  @override
  String vmCostGenQuestion(String reasons, String cost) {
    return 'Generation parameters ($reasons) $cost. Confirm generation?';
  }

  @override
  String get vmCostGenConfirm => 'Confirm Generation';

  @override
  String get vmCostGenConfirmDesc =>
      'Generate with current parameters and deduct Anlas';

  @override
  String get vmCostGenCancel => 'Cancel Generation';

  @override
  String get vmCostGenCancelDesc =>
      'Cancel this generation and adjust parameters into the free range';

  @override
  String vmCostUpscaleQuestion(int width, int height, int cost) {
    return 'Upscale the ${width}x$height input image via official upscaling. Estimated cost: $cost Anlas. Confirm?';
  }

  @override
  String get vmCostUpscaleConfirm => 'Confirm Upscale';

  @override
  String get vmCostUpscaleConfirmDesc =>
      'Run official upscaling and deduct Anlas';

  @override
  String get vmCostUpscaleCancel => 'Cancel Upscale';

  @override
  String get vmCostUpscaleCancelDesc => 'Cancel this upscale operation';

  @override
  String get vmInpaintConverted => 'Annotation converted to inpaint selection';

  @override
  String vmInpaintSentToBoard(String path) {
    return 'Sent to inpaint canvas: $path';
  }

  @override
  String get vmInpaintNoImage =>
      'No base image to repair. Select or generate an image first.';

  @override
  String get vmInpaintNoMask =>
      'Select or paint the region to repair on the inpaint canvas first.';

  @override
  String get vmInpaintNoApiKey =>
      'NovelAI API Key not configured. Enter the token in Settings.';

  @override
  String get vmInpaintRunning => 'Running local inpaint...';

  @override
  String get vmInpaintDone => 'Local inpaint complete';

  @override
  String vmInpaintFailed(String error) {
    return 'Inpaint failed: $error';
  }

  @override
  String get vmAiEditNoImage =>
      'No base image to edit. Select or generate an image first.';

  @override
  String get vmAiEditNoModel =>
      'No image-editing model configured. Pick an image-model provider and model in Settings → Models.';

  @override
  String vmAiEditNoKey(String provider) {
    return 'Image-model provider \"$provider\" has no API Key configured. Fill it in Settings first.';
  }

  @override
  String get vmAiEditEmptyPrompt =>
      'Enter the AI full-image edit instruction first (inpaint page prompt, or turn off \"Reuse workbench prompt\" and fill it in).';

  @override
  String get vmAiEditRunning =>
      'Running AI full-image edit (image model processing, usually takes tens of seconds)...';

  @override
  String get vmAiEditDone => 'AI full-image edit complete';

  @override
  String vmAiEditFailed(String error) {
    return 'AI full-image edit failed: $error';
  }

  @override
  String vmSessionSwitched(String title) {
    return 'Switched session: $title';
  }

  @override
  String get vmSessionCreated => 'New session created';

  @override
  String get vmSessionDeleted => 'Session deleted';

  @override
  String get vmRewindChatAndParams =>
      'Rewound to a past moment. Later chat and parameter changes were reverted.';

  @override
  String get vmRewindChatOnly =>
      'Rewound to a past moment. Later chat and edits were reverted.';

  @override
  String get vmHistoryDeleted => 'Image deleted from history';

  @override
  String get vmHistoryCleared => 'History cleared';

  @override
  String get vmMetadataApplied => 'Image metadata applied to workbench';

  @override
  String vmPresetSwitched(String name, String description) {
    return 'Switched preset: [$name]\n$description';
  }

  @override
  String vmCharacterDefaultName(int index) {
    return 'Character $index';
  }

  @override
  String get vmNewCharacterName => 'New Character';

  @override
  String get slashHelpHeader => 'Slash command reference:';

  @override
  String get slashDescHelp => 'Show the command help list';

  @override
  String get slashDescParams =>
      'Show the workbench\'s current effective generation parameters';

  @override
  String get slashDescPreset => 'Switch the current Agent preset';

  @override
  String get slashDescSkill => 'Load and run a professional skill on demand';

  @override
  String get slashDescNai =>
      'Quick-generate an illustration, supports --landscape/--portrait/--square/--wallpaper orientation flags';

  @override
  String get slashDescUpscale => 'Upscale the current image';

  @override
  String get slashDescTag => 'Query official Danbooru tag suggestions';

  @override
  String get slashDescAccount => 'Query account tier and the V5 stamina pool';

  @override
  String get slashDescCompact =>
      'Manually compact the conversation context (earlier messages replaced by a summary, originals kept)';

  @override
  String get slashDescNew => 'Create a new blank session (optional title)';

  @override
  String get slashDescUndo =>
      'Undo the last chat turn (replies and parameter changes rolled back together)';

  @override
  String get slashDescRename => 'Rename the current session';

  @override
  String get slashDescSessions => 'List saved sessions';

  @override
  String get slashDescClear => 'Clear the chat history';

  @override
  String get slashArgsName => '<name>';

  @override
  String get slashArgsPrompt => '<prompt>';

  @override
  String get slashArgsKeyword => '<keyword>';

  @override
  String get slashArgsTitle => '<title>';

  @override
  String get slashPresetListIntro => 'Available presets:';

  @override
  String get slashPresetUsage => 'Usage: /preset <preset name or ID>';

  @override
  String slashPresetNotFound(String query) {
    return 'Preset \"$query\" not found. Type /preset to list available presets.';
  }

  @override
  String get slashSkillListIntro => 'Available skills:';

  @override
  String get slashSkillUsage => 'Usage: /skill <skill name or ID>';

  @override
  String slashSkillLoaded(
    String name,
    String description,
    String systemPrompt,
  ) {
    return '[Skill loaded] $name\n$description\n\n$systemPrompt';
  }

  @override
  String slashSkillNotFound(String query) {
    return 'Skill \"$query\" not found. Type /skill to list available skills.';
  }

  @override
  String get slashCompactNoProvider =>
      'No LLM provider configured; cannot compact the context.';

  @override
  String get slashCompactEmpty =>
      'The conversation is empty; nothing to compact.';

  @override
  String get slashCompactRunning => 'Compacting conversation context...';

  @override
  String get slashCompactNothing =>
      'Nothing to compact (needs at least two chat turns), or summary generation failed.';

  @override
  String slashCompactDone(int before, int after, String summary) {
    return 'Context compacted ($before → $after tokens). Earlier messages were replaced by the summary below; originals are kept in the chat stream and session log:\n\n$summary';
  }

  @override
  String get slashNewNoTitle =>
      'New session created. Start a fresh conversation!';

  @override
  String slashNewWithTitle(String title) {
    return 'New session created: $title';
  }

  @override
  String get slashUndoNothing =>
      'No previous chat turn to undo (nothing before the first turn).';

  @override
  String get slashRenameUsage => 'Usage: /rename <new title>';

  @override
  String get slashRenameNoSession => 'No active session to rename.';

  @override
  String slashRenamed(String title) {
    return 'Session renamed to \"$title\"';
  }

  @override
  String get slashSessionsEmpty => 'No saved sessions yet.';

  @override
  String slashSessionsHeader(int count) {
    return 'Saved sessions ($count total, sorted by recent use):';
  }

  @override
  String slashSessionMsgCount(int count) {
    return '$count messages';
  }

  @override
  String get slashSessionCurrentMarker => ' [current]';

  @override
  String slashSessionsMore(int count) {
    return '…… $count more sessions in the session manager view.';
  }

  @override
  String get slashAccountTitle => 'NovelAI account status:';

  @override
  String slashAccountTier(String tier) {
    return '• Subscription tier: $tier';
  }

  @override
  String slashAccountStamina(String percent) {
    return '• V5 stamina pool: $percent%';
  }

  @override
  String slashAccountAnlas(int total, int fixed, int purchased) {
    return '• Available Anlas: $total (gifted: $fixed, purchased: $purchased)';
  }

  @override
  String get slashAccountQuotaExhausted =>
      '• V5 stamina quota exhausted; generation will consume Anlas at full price';

  @override
  String get slashAccountFailed =>
      'Failed to query account info. Check the API Key settings.';

  @override
  String get slashTagUsage => 'Usage: /tag <keyword> (e.g. /tag silver)';

  @override
  String slashTagNotFound(String query) {
    return 'No tags found for \"$query\".';
  }

  @override
  String slashTagSuggestions(String query, String list) {
    return 'Tag suggestions (\"$query\"):\n$list';
  }

  @override
  String get slashUpscaleDone => 'Upscale executed';

  @override
  String get slashNaiUsage => 'Usage: /nai <prompt>';

  @override
  String slashNaiDone(String path, int width, int height, int seed) {
    return 'Illustration generated: $path\nSize: ${width}x$height, seed: $seed';
  }

  @override
  String get slashNaiDoneFallback => 'done';

  @override
  String slashUnknown(String cmd) {
    return 'Unknown command \"$cmd\". Type /help for available commands.';
  }

  @override
  String get vmSlashParamsTitle => 'Workbench generation parameters:';
}
