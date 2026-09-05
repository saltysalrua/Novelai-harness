import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI Harness'**
  String get appTitle;

  /// No description provided for @generateImage.
  ///
  /// In zh, this message translates to:
  /// **'生成图片'**
  String get generateImage;

  /// No description provided for @startInpaint.
  ///
  /// In zh, this message translates to:
  /// **'开始修复'**
  String get startInpaint;

  /// No description provided for @startAiEdit.
  ///
  /// In zh, this message translates to:
  /// **'开始 AI 编辑'**
  String get startAiEdit;

  /// No description provided for @abortGeneration.
  ///
  /// In zh, this message translates to:
  /// **'终止生成'**
  String get abortGeneration;

  /// No description provided for @opusFree.
  ///
  /// In zh, this message translates to:
  /// **'Opus 免费'**
  String get opusFree;

  /// No description provided for @needAnlas.
  ///
  /// In zh, this message translates to:
  /// **'需点数'**
  String get needAnlas;

  /// No description provided for @v5Stamina.
  ///
  /// In zh, this message translates to:
  /// **'V5 体力'**
  String get v5Stamina;

  /// No description provided for @tabParameters.
  ///
  /// In zh, this message translates to:
  /// **'参数设置'**
  String get tabParameters;

  /// No description provided for @tabPrompts.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get tabPrompts;

  /// No description provided for @tabInpaint.
  ///
  /// In zh, this message translates to:
  /// **'局部修复'**
  String get tabInpaint;

  /// No description provided for @tabLibrary.
  ///
  /// In zh, this message translates to:
  /// **'词库'**
  String get tabLibrary;

  /// No description provided for @history.
  ///
  /// In zh, this message translates to:
  /// **'历史记录'**
  String get history;

  /// No description provided for @settings.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settings;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确定'**
  String get confirm;

  /// No description provided for @clear.
  ///
  /// In zh, this message translates to:
  /// **'清空'**
  String get clear;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @copy.
  ///
  /// In zh, this message translates to:
  /// **'复制'**
  String get copy;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @import.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get import;

  /// No description provided for @export.
  ///
  /// In zh, this message translates to:
  /// **'导出'**
  String get export;

  /// No description provided for @settingsSectionAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsSectionAppearance;

  /// No description provided for @settingsThemeMode.
  ///
  /// In zh, this message translates to:
  /// **'主题模式'**
  String get settingsThemeMode;

  /// No description provided for @settingsThemeModeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换亮色/深色工作台外观，深色采用 Notion 极简暗调色板'**
  String get settingsThemeModeSubtitle;

  /// No description provided for @themeModeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get themeModeSystem;

  /// No description provided for @themeModeLight.
  ///
  /// In zh, this message translates to:
  /// **'亮色'**
  String get themeModeLight;

  /// No description provided for @themeModeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get themeModeDark;

  /// No description provided for @settingsLanguage.
  ///
  /// In zh, this message translates to:
  /// **'语言'**
  String get settingsLanguage;

  /// No description provided for @settingsLanguageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'切换界面显示语言；现阶段设置页优先接入，其余界面将分模块逐步迁移'**
  String get settingsLanguageSubtitle;

  /// No description provided for @localeSystem.
  ///
  /// In zh, this message translates to:
  /// **'跟随系统'**
  String get localeSystem;

  /// No description provided for @localeChinese.
  ///
  /// In zh, this message translates to:
  /// **'中文'**
  String get localeChinese;

  /// No description provided for @localeEnglish.
  ///
  /// In zh, this message translates to:
  /// **'English'**
  String get localeEnglish;

  /// No description provided for @settingsUiZoom.
  ///
  /// In zh, this message translates to:
  /// **'界面缩放'**
  String get settingsUiZoom;

  /// No description provided for @settingsUiZoomSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'整体缩放工作台界面；快捷键 Ctrl + = / Ctrl + - 步进，Ctrl + 0 重置'**
  String get settingsUiZoomSubtitle;

  /// No description provided for @settingsSectionNovelaiService.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI Service'**
  String get settingsSectionNovelaiService;

  /// No description provided for @settingsApiKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI API Key'**
  String get settingsApiKeyTitle;

  /// No description provided for @settingsApiKeySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'官方 API 凭证 (pst-...)，用于图像生成与体力池同步'**
  String get settingsApiKeySubtitle;

  /// No description provided for @settingsSaveDirTitle.
  ///
  /// In zh, this message translates to:
  /// **'本地存储目录'**
  String get settingsSaveDirTitle;

  /// No description provided for @settingsSaveDirSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生成的高清图像与元数据自动保存至此路径'**
  String get settingsSaveDirSubtitle;

  /// No description provided for @settingsSaveDirHint.
  ///
  /// In zh, this message translates to:
  /// **'存储路径...'**
  String get settingsSaveDirHint;

  /// No description provided for @settingsChooseButton.
  ///
  /// In zh, this message translates to:
  /// **'选择'**
  String get settingsChooseButton;

  /// No description provided for @settingsAutoSaveTitle.
  ///
  /// In zh, this message translates to:
  /// **'自动保存生成图片'**
  String get settingsAutoSaveTitle;

  /// No description provided for @settingsAutoSaveSubtitleOn.
  ///
  /// In zh, this message translates to:
  /// **'生成图片自动写入本地存储目录 (按导出设置处理元数据与水印)'**
  String get settingsAutoSaveSubtitleOn;

  /// No description provided for @settingsAutoSaveSubtitleOff.
  ///
  /// In zh, this message translates to:
  /// **'生成图片先存入缓存目录 (无水印)，在画板右下角点击保存按钮手动保存；超出历史上限的缓存图片自动删除'**
  String get settingsAutoSaveSubtitleOff;

  /// No description provided for @settingsStreamPreviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'实时生图预览'**
  String get settingsStreamPreviewTitle;

  /// No description provided for @settingsStreamPreviewSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生图过程中接收并实时渲染中间去噪步数预览图 (Stream Preview)'**
  String get settingsStreamPreviewSubtitle;

  /// No description provided for @settingsImagePersistenceTitle.
  ///
  /// In zh, this message translates to:
  /// **'图片历史持久化'**
  String get settingsImagePersistenceTitle;

  /// No description provided for @settingsImagePersistenceSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'应用重启后自动恢复画板历史中的生成图片记录'**
  String get settingsImagePersistenceSubtitle;

  /// No description provided for @settingsMaxImagesTitle.
  ///
  /// In zh, this message translates to:
  /// **'可持久化图像上限'**
  String get settingsMaxImagesTitle;

  /// No description provided for @settingsMaxImagesSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'限制本地画板历史中保留的最大图片数量'**
  String get settingsMaxImagesSubtitle;

  /// No description provided for @settingsImageCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 张'**
  String settingsImageCount(int count);

  /// No description provided for @settingsSectionTagAutocomplete.
  ///
  /// In zh, this message translates to:
  /// **'Danbooru Tag Autocomplete'**
  String get settingsSectionTagAutocomplete;

  /// No description provided for @settingsTagAutocompleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'标签智能自动补全'**
  String get settingsTagAutocompleteTitle;

  /// No description provided for @settingsTagAutocompleteSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'输入提示词时自动弹出 32万+ Danbooru 词库悬浮联想建议'**
  String get settingsTagAutocompleteSubtitle;

  /// No description provided for @settingsDictUpdateTitle.
  ///
  /// In zh, this message translates to:
  /// **'词库在线更新'**
  String get settingsDictUpdateTitle;

  /// No description provided for @settingsDictUpdateNowButton.
  ///
  /// In zh, this message translates to:
  /// **'立即更新'**
  String get settingsDictUpdateNowButton;

  /// No description provided for @settingsDictAutoCheckTitle.
  ///
  /// In zh, this message translates to:
  /// **'启动时自动检查更新'**
  String get settingsDictAutoCheckTitle;

  /// No description provided for @settingsDictAutoCheckSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'每日一次后台拉取最新词库 (ffdkj 每日构建，含新标签与中文翻译)'**
  String get settingsDictAutoCheckSubtitle;

  /// No description provided for @settingsTagTranslationsTitle.
  ///
  /// In zh, this message translates to:
  /// **'显示标签中文释义'**
  String get settingsTagTranslationsTitle;

  /// No description provided for @settingsTagTranslationsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在补全候选词列表与灵感库中展示对应的中文翻译释义'**
  String get settingsTagTranslationsSubtitle;

  /// No description provided for @settingsTagColorsTitle.
  ///
  /// In zh, this message translates to:
  /// **'标签分类着色高亮'**
  String get settingsTagColorsTitle;

  /// No description provided for @settingsTagColorsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在提示词输入框中对画师、角色、作品、通用等标签施加分类色彩高亮'**
  String get settingsTagColorsSubtitle;

  /// No description provided for @dictOnlineInfo.
  ///
  /// In zh, this message translates to:
  /// **'在线词库 {count} 条 · 更新于 {date}'**
  String dictOnlineInfo(int count, String date);

  /// No description provided for @dictBuiltinInfo.
  ///
  /// In zh, this message translates to:
  /// **'内置词库 {count} 条'**
  String dictBuiltinInfo(int count);

  /// No description provided for @dictBuiltinLoading.
  ///
  /// In zh, this message translates to:
  /// **'内置词库 (加载中)'**
  String get dictBuiltinLoading;

  /// No description provided for @settingsSectionProtection.
  ///
  /// In zh, this message translates to:
  /// **'保护'**
  String get settingsSectionProtection;

  /// No description provided for @settingsOpusTitle.
  ///
  /// In zh, this message translates to:
  /// **'Opus 免点数保护'**
  String get settingsOpusTitle;

  /// No description provided for @settingsOpusSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'自动将默认参数限制在免费区间内 (像素 <= 1048576 且 步数 <= 28)'**
  String get settingsOpusSubtitle;

  /// No description provided for @dictUpdateFailed.
  ///
  /// In zh, this message translates to:
  /// **'更新失败: {error}'**
  String dictUpdateFailed(String error);

  /// No description provided for @settingsModelSettings.
  ///
  /// In zh, this message translates to:
  /// **'模型设置'**
  String get settingsModelSettings;

  /// No description provided for @settingsDeleteModel.
  ///
  /// In zh, this message translates to:
  /// **'删除模型'**
  String get settingsDeleteModel;

  /// No description provided for @settingsModelBadgeThinking.
  ///
  /// In zh, this message translates to:
  /// **'思考'**
  String get settingsModelBadgeThinking;

  /// No description provided for @settingsModelBadgeMultimodal.
  ///
  /// In zh, this message translates to:
  /// **'多模态'**
  String get settingsModelBadgeMultimodal;

  /// No description provided for @settingsModelBadgeImageOutput.
  ///
  /// In zh, this message translates to:
  /// **'绘图'**
  String get settingsModelBadgeImageOutput;

  /// No description provided for @settingsModelBadgeContext.
  ///
  /// In zh, this message translates to:
  /// **'{tokens} 上下文'**
  String settingsModelBadgeContext(String tokens);

  /// No description provided for @settingsAddModel.
  ///
  /// In zh, this message translates to:
  /// **'添加模型'**
  String get settingsAddModel;

  /// No description provided for @settingsModelIdEmptyError.
  ///
  /// In zh, this message translates to:
  /// **'模型 ID 不能为空'**
  String get settingsModelIdEmptyError;

  /// No description provided for @settingsModelDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'显示名称'**
  String get settingsModelDisplayName;

  /// No description provided for @settingsModelDisplayNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如 DeepSeek R1'**
  String get settingsModelDisplayNameHint;

  /// No description provided for @settingsModelId.
  ///
  /// In zh, this message translates to:
  /// **'模型 ID'**
  String get settingsModelId;

  /// No description provided for @settingsModelIdHint.
  ///
  /// In zh, this message translates to:
  /// **'发送给 API 的模型标识'**
  String get settingsModelIdHint;

  /// No description provided for @settingsModelTemperature.
  ///
  /// In zh, this message translates to:
  /// **'温度 (Temperature)'**
  String get settingsModelTemperature;

  /// No description provided for @settingsModelReasoning.
  ///
  /// In zh, this message translates to:
  /// **'深度思考 (Reasoning)'**
  String get settingsModelReasoning;

  /// No description provided for @settingsModelThinkingEffort.
  ///
  /// In zh, this message translates to:
  /// **'思考等级'**
  String get settingsModelThinkingEffort;

  /// No description provided for @settingsModelMultimodal.
  ///
  /// In zh, this message translates to:
  /// **'多模态 (图像输入)'**
  String get settingsModelMultimodal;

  /// No description provided for @settingsModelImageOutput.
  ///
  /// In zh, this message translates to:
  /// **'图像输出 (绘图模型)'**
  String get settingsModelImageOutput;

  /// No description provided for @settingsModelContextWindow.
  ///
  /// In zh, this message translates to:
  /// **'上下文窗口 (tokens)'**
  String get settingsModelContextWindow;

  /// No description provided for @settingsModelMaxTokens.
  ///
  /// In zh, this message translates to:
  /// **'最大输出 (tokens)'**
  String get settingsModelMaxTokens;

  /// No description provided for @settingsAdd.
  ///
  /// In zh, this message translates to:
  /// **'添加'**
  String get settingsAdd;

  /// No description provided for @settingsCustomProviderDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'自定义供应商'**
  String get settingsCustomProviderDefaultName;

  /// No description provided for @settingsNewProviderDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'新供应商 {index}'**
  String settingsNewProviderDefaultName(int index);

  /// No description provided for @settingsFetchModelsEnterBaseUrl.
  ///
  /// In zh, this message translates to:
  /// **'请先填写有效的 API 基础 URL'**
  String get settingsFetchModelsEnterBaseUrl;

  /// No description provided for @settingsFetchModelsSuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功拉取 {count} 个模型'**
  String settingsFetchModelsSuccess(int count);

  /// No description provided for @settingsFetchModelsSuccessWithEnriched.
  ///
  /// In zh, this message translates to:
  /// **'成功拉取 {count} 个模型，{enrichedCount} 个已匹配 models.dev 元数据'**
  String settingsFetchModelsSuccessWithEnriched(int count, int enrichedCount);

  /// No description provided for @settingsEndpointUrlNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置 URL'**
  String get settingsEndpointUrlNotConfigured;

  /// No description provided for @settingsFullEndpoint.
  ///
  /// In zh, this message translates to:
  /// **'完整接口地址: {endpoint}'**
  String settingsFullEndpoint(String endpoint);

  /// No description provided for @settingsSectionProviderSelection.
  ///
  /// In zh, this message translates to:
  /// **'Provider Selection'**
  String get settingsSectionProviderSelection;

  /// No description provided for @settingsSectionProviderProfile.
  ///
  /// In zh, this message translates to:
  /// **'Provider Profile & Endpoint'**
  String get settingsSectionProviderProfile;

  /// No description provided for @settingsSectionModels.
  ///
  /// In zh, this message translates to:
  /// **'Models'**
  String get settingsSectionModels;

  /// No description provided for @settingsSectionImageEdit.
  ///
  /// In zh, this message translates to:
  /// **'AI 整图编辑'**
  String get settingsSectionImageEdit;

  /// No description provided for @settingsCurrentProvider.
  ///
  /// In zh, this message translates to:
  /// **'当前供应商'**
  String get settingsCurrentProvider;

  /// No description provided for @settingsCurrentProviderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择要配置的 AI 服务商，或添加自定义供应商'**
  String get settingsCurrentProviderSubtitle;

  /// No description provided for @settingsNewProviderButton.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get settingsNewProviderButton;

  /// No description provided for @settingsDeleteCurrentProviderTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除当前供应商'**
  String get settingsDeleteCurrentProviderTooltip;

  /// No description provided for @settingsProviderName.
  ///
  /// In zh, this message translates to:
  /// **'供应商名称'**
  String get settingsProviderName;

  /// No description provided for @settingsProviderNameSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'在界面与下拉菜单中显示的自定义标识'**
  String get settingsProviderNameSubtitle;

  /// No description provided for @settingsProviderNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如 DeepSeek / OpenAI / 本地 Ollama'**
  String get settingsProviderNameHint;

  /// No description provided for @settingsApiEndpointAndProtocol.
  ///
  /// In zh, this message translates to:
  /// **'API 接口与协议'**
  String get settingsApiEndpointAndProtocol;

  /// No description provided for @settingsApiEndpointAndProtocolSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'服务基础 URL 与对应的通讯协议格式'**
  String get settingsApiEndpointAndProtocolSubtitle;

  /// No description provided for @settingsLlmApiKeyTitle.
  ///
  /// In zh, this message translates to:
  /// **'LLM API Key'**
  String get settingsLlmApiKeyTitle;

  /// No description provided for @settingsLlmApiKeySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'访问该供应商所需的身份密钥'**
  String get settingsLlmApiKeySubtitle;

  /// No description provided for @settingsThinkingParamFormat.
  ///
  /// In zh, this message translates to:
  /// **'思考参数格式'**
  String get settingsThinkingParamFormat;

  /// No description provided for @settingsThinkingParamFormatSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'不同供应商用不同字段开关思维链，格式不匹配时思考会被静默丢弃；中转站请按其上游格式指定'**
  String get settingsThinkingParamFormatSubtitle;

  /// No description provided for @settingsModelsListTitle.
  ///
  /// In zh, this message translates to:
  /// **'模型列表'**
  String get settingsModelsListTitle;

  /// No description provided for @settingsModelsListSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'点击卡片切换当前模型，设置按钮调整模型参数与能力档案'**
  String get settingsModelsListSubtitle;

  /// No description provided for @settingsFetchingModels.
  ///
  /// In zh, this message translates to:
  /// **'拉取中...'**
  String get settingsFetchingModels;

  /// No description provided for @settingsFetchModelsOnline.
  ///
  /// In zh, this message translates to:
  /// **'在线拉取模型'**
  String get settingsFetchModelsOnline;

  /// No description provided for @settingsImageEditModelTitle.
  ///
  /// In zh, this message translates to:
  /// **'绘图模型'**
  String get settingsImageEditModelTitle;

  /// No description provided for @settingsImageEditModelSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'修复页「AI 整图编辑」使用的供应商与模型 (仅列出绘图模型)，独立于对话 LLM；需选择具备图像输出能力的模型 (如 nano banana / gpt-image)'**
  String get settingsImageEditModelSubtitle;

  /// No description provided for @settingsDropdownNotConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置'**
  String get settingsDropdownNotConfigured;

  /// No description provided for @settingsDropdownNoModelSelected.
  ///
  /// In zh, this message translates to:
  /// **'未选择模型'**
  String get settingsDropdownNoModelSelected;

  /// No description provided for @settingsImageEditUnrecognizedModel.
  ///
  /// In zh, this message translates to:
  /// **'{modelId} (未识别为绘图模型)'**
  String settingsImageEditUnrecognizedModel(String modelId);

  /// No description provided for @settingsImageEditTip.
  ///
  /// In zh, this message translates to:
  /// **'整图编辑不消耗 Anlas 点数，计费走绘图模型供应商；未识别到能力的模型可在模型设置中手动开启「图像输出」'**
  String get settingsImageEditTip;

  /// No description provided for @settingsSearchModelHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索模型名称或 ID'**
  String get settingsSearchModelHint;

  /// No description provided for @settingsModelSortDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认顺序'**
  String get settingsModelSortDefault;

  /// No description provided for @settingsModelSortNameAsc.
  ///
  /// In zh, this message translates to:
  /// **'名称 A-Z'**
  String get settingsModelSortNameAsc;

  /// No description provided for @settingsModelSortNameDesc.
  ///
  /// In zh, this message translates to:
  /// **'名称 Z-A'**
  String get settingsModelSortNameDesc;

  /// No description provided for @settingsFilterImageOnly.
  ///
  /// In zh, this message translates to:
  /// **'仅绘图模型'**
  String get settingsFilterImageOnly;

  /// No description provided for @settingsFilterImageOnlyTooltip.
  ///
  /// In zh, this message translates to:
  /// **'仅显示具备图像输出能力的模型 (如 nano banana / gpt-image)'**
  String get settingsFilterImageOnlyTooltip;

  /// No description provided for @settingsModelCount.
  ///
  /// In zh, this message translates to:
  /// **'{current} / {total} 个模型'**
  String settingsModelCount(int current, int total);

  /// No description provided for @settingsNoModelsInProvider.
  ///
  /// In zh, this message translates to:
  /// **'当前供应商暂无模型'**
  String get settingsNoModelsInProvider;

  /// No description provided for @settingsNoModelsInProviderDesc.
  ///
  /// In zh, this message translates to:
  /// **'点击上方\"在线拉取模型\"或\"添加模型\"'**
  String get settingsNoModelsInProviderDesc;

  /// No description provided for @settingsNoMatchingModels.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配 \"{query}\" 的模型'**
  String settingsNoMatchingModels(String query);

  /// No description provided for @settingsBadgeBuiltin.
  ///
  /// In zh, this message translates to:
  /// **'内置'**
  String get settingsBadgeBuiltin;

  /// No description provided for @settingsBadgeCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get settingsBadgeCustom;

  /// No description provided for @settingsSectionPresetSelection.
  ///
  /// In zh, this message translates to:
  /// **'Preset Selection'**
  String get settingsSectionPresetSelection;

  /// No description provided for @settingsSectionPresetProfile.
  ///
  /// In zh, this message translates to:
  /// **'Preset Profile & System Prompt'**
  String get settingsSectionPresetProfile;

  /// No description provided for @settingsSectionAvailableSkills.
  ///
  /// In zh, this message translates to:
  /// **'Available Skills'**
  String get settingsSectionAvailableSkills;

  /// No description provided for @settingsSectionEnabledTools.
  ///
  /// In zh, this message translates to:
  /// **'Enabled Tools'**
  String get settingsSectionEnabledTools;

  /// No description provided for @settingsSectionModifiableParams.
  ///
  /// In zh, this message translates to:
  /// **'Modifiable Parameters'**
  String get settingsSectionModifiableParams;

  /// No description provided for @presetCurrentPreset.
  ///
  /// In zh, this message translates to:
  /// **'当前预设'**
  String get presetCurrentPreset;

  /// No description provided for @presetCurrentPresetSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'选择要配置的 Agent 预设（系统提示词、可用技能、工具与参数权限）'**
  String get presetCurrentPresetSubtitle;

  /// No description provided for @presetBadgeActiveDefault.
  ///
  /// In zh, this message translates to:
  /// **'当前默认'**
  String get presetBadgeActiveDefault;

  /// No description provided for @presetSetAsActiveDefault.
  ///
  /// In zh, this message translates to:
  /// **'设为当前默认'**
  String get presetSetAsActiveDefault;

  /// No description provided for @presetNewButton.
  ///
  /// In zh, this message translates to:
  /// **'新建'**
  String get presetNewButton;

  /// No description provided for @presetDeleteTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除此预设'**
  String get presetDeleteTooltip;

  /// No description provided for @presetDefaultCustomName.
  ///
  /// In zh, this message translates to:
  /// **'自定义预设'**
  String get presetDefaultCustomName;

  /// No description provided for @presetNewName.
  ///
  /// In zh, this message translates to:
  /// **'新预设 {index}'**
  String presetNewName(int index);

  /// No description provided for @presetNewDescription.
  ///
  /// In zh, this message translates to:
  /// **'自定义 Agent 预设描述'**
  String get presetNewDescription;

  /// No description provided for @presetNewSystemPrompt.
  ///
  /// In zh, this message translates to:
  /// **'你是由 NovelAI Harness 驱动的绘画创作助手。'**
  String get presetNewSystemPrompt;

  /// No description provided for @presetDuplicateName.
  ///
  /// In zh, this message translates to:
  /// **'{name} (副本)'**
  String presetDuplicateName(String name);

  /// No description provided for @presetExportSkillSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已复制 Skill [{name}] 为标准 SKILL.md 至剪贴板'**
  String presetExportSkillSuccess(String name);

  /// No description provided for @presetBuiltinNotice.
  ///
  /// In zh, this message translates to:
  /// **'内置预设为出厂定义，每次启动以代码为准自动刷新，不支持直接修改。需要定制请先点击「复制」生成副本。'**
  String get presetBuiltinNotice;

  /// No description provided for @presetDisplayName.
  ///
  /// In zh, this message translates to:
  /// **'预设显示名称'**
  String get presetDisplayName;

  /// No description provided for @presetDisplayNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如 V5 自然语言架构师'**
  String get presetDisplayNameHint;

  /// No description provided for @presetDescription.
  ///
  /// In zh, this message translates to:
  /// **'预设描述'**
  String get presetDescription;

  /// No description provided for @presetDescriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'如 擅长 V5 自然语言散文提示词...'**
  String get presetDescriptionHint;

  /// No description provided for @presetSystemPrompt.
  ///
  /// In zh, this message translates to:
  /// **'系统提示词 (System Prompt - 作为对话首要根基指令)'**
  String get presetSystemPrompt;

  /// No description provided for @presetSystemPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入 AI 助手的核心人设与工作流指引...'**
  String get presetSystemPromptHint;

  /// No description provided for @presetImportSkill.
  ///
  /// In zh, this message translates to:
  /// **'导入 SKILL.md'**
  String get presetImportSkill;

  /// No description provided for @presetNewSkill.
  ///
  /// In zh, this message translates to:
  /// **'新建 Skill'**
  String get presetNewSkill;

  /// No description provided for @presetNewCustomTool.
  ///
  /// In zh, this message translates to:
  /// **'新建自定义工具'**
  String get presetNewCustomTool;

  /// No description provided for @presetParamPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词'**
  String get presetParamPrompt;

  /// No description provided for @presetParamNegativePrompt.
  ///
  /// In zh, this message translates to:
  /// **'负向提示词'**
  String get presetParamNegativePrompt;

  /// No description provided for @presetParamModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get presetParamModel;

  /// No description provided for @presetParamResolution.
  ///
  /// In zh, this message translates to:
  /// **'分辨率'**
  String get presetParamResolution;

  /// No description provided for @presetParamWidth.
  ///
  /// In zh, this message translates to:
  /// **'宽度'**
  String get presetParamWidth;

  /// No description provided for @presetParamHeight.
  ///
  /// In zh, this message translates to:
  /// **'高度'**
  String get presetParamHeight;

  /// No description provided for @presetParamSteps.
  ///
  /// In zh, this message translates to:
  /// **'步数'**
  String get presetParamSteps;

  /// No description provided for @presetParamScale.
  ///
  /// In zh, this message translates to:
  /// **'CFG'**
  String get presetParamScale;

  /// No description provided for @presetParamCfgRescale.
  ///
  /// In zh, this message translates to:
  /// **'CFG Rescale'**
  String get presetParamCfgRescale;

  /// No description provided for @presetParamSampler.
  ///
  /// In zh, this message translates to:
  /// **'采样器'**
  String get presetParamSampler;

  /// No description provided for @presetParamNoiseSchedule.
  ///
  /// In zh, this message translates to:
  /// **'噪声调度'**
  String get presetParamNoiseSchedule;

  /// No description provided for @presetParamQualityPreset.
  ///
  /// In zh, this message translates to:
  /// **'质量标签'**
  String get presetParamQualityPreset;

  /// No description provided for @presetParamCharacterAiPosition.
  ///
  /// In zh, this message translates to:
  /// **'角色定位模式'**
  String get presetParamCharacterAiPosition;

  /// No description provided for @skillTooltipExport.
  ///
  /// In zh, this message translates to:
  /// **'导出为 SKILL.md'**
  String get skillTooltipExport;

  /// No description provided for @skillTooltipEdit.
  ///
  /// In zh, this message translates to:
  /// **'查看与编辑 Skill'**
  String get skillTooltipEdit;

  /// No description provided for @skillTooltipDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除 Skill'**
  String get skillTooltipDelete;

  /// No description provided for @skillNoDescription.
  ///
  /// In zh, this message translates to:
  /// **'暂无描述'**
  String get skillNoDescription;

  /// No description provided for @skillDialogImportTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入标准 SKILL.md'**
  String get skillDialogImportTitle;

  /// No description provided for @skillDialogNewTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建 Skill'**
  String get skillDialogNewTitle;

  /// No description provided for @skillDialogEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑 Skill ({name})'**
  String skillDialogEditTitle(String name);

  /// No description provided for @skillEditorTabStructured.
  ///
  /// In zh, this message translates to:
  /// **'结构化编辑'**
  String get skillEditorTabStructured;

  /// No description provided for @skillEditorTabRaw.
  ///
  /// In zh, this message translates to:
  /// **'SKILL.md 源码'**
  String get skillEditorTabRaw;

  /// No description provided for @skillCopySkillMd.
  ///
  /// In zh, this message translates to:
  /// **'复制 SKILL.md'**
  String get skillCopySkillMd;

  /// No description provided for @skillCopySuccess.
  ///
  /// In zh, this message translates to:
  /// **'已复制标准 SKILL.md 内容至剪贴板'**
  String get skillCopySuccess;

  /// No description provided for @skillSave.
  ///
  /// In zh, this message translates to:
  /// **'保存 Skill'**
  String get skillSave;

  /// No description provided for @skillFieldId.
  ///
  /// In zh, this message translates to:
  /// **'标识'**
  String get skillFieldId;

  /// No description provided for @skillFieldIdHint.
  ///
  /// In zh, this message translates to:
  /// **'如 v5-architect'**
  String get skillFieldIdHint;

  /// No description provided for @skillFieldName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get skillFieldName;

  /// No description provided for @skillFieldNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如 V5 自然语言架构师'**
  String get skillFieldNameHint;

  /// No description provided for @skillFieldDescription.
  ///
  /// In zh, this message translates to:
  /// **'技能描述'**
  String get skillFieldDescription;

  /// No description provided for @skillFieldDescriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'简要说明该技能擅长处理的任务场景...'**
  String get skillFieldDescriptionHint;

  /// No description provided for @skillFieldPrompt.
  ///
  /// In zh, this message translates to:
  /// **'技能指令'**
  String get skillFieldPrompt;

  /// No description provided for @skillFieldDisableInvocation.
  ///
  /// In zh, this message translates to:
  /// **'禁止自动调用'**
  String get skillFieldDisableInvocation;

  /// No description provided for @skillFieldPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入该技能加载后生效的完整提示词与规范...'**
  String get skillFieldPromptHint;

  /// No description provided for @skillRawEditorHelp.
  ///
  /// In zh, this message translates to:
  /// **'粘贴或编辑标准 SKILL.md (含 YAML Frontmatter 与 Markdown Body)：'**
  String get skillRawEditorHelp;

  /// No description provided for @skillIdEmptyError.
  ///
  /// In zh, this message translates to:
  /// **'Skill 标识 (ID) 不能为空'**
  String get skillIdEmptyError;

  /// No description provided for @toolTooltipEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑工具'**
  String get toolTooltipEdit;

  /// No description provided for @toolTooltipInspectSchema.
  ///
  /// In zh, this message translates to:
  /// **'查看 Schema'**
  String get toolTooltipInspectSchema;

  /// No description provided for @toolTooltipDelete.
  ///
  /// In zh, this message translates to:
  /// **'删除自定义工具'**
  String get toolTooltipDelete;

  /// No description provided for @toolNoDescription.
  ///
  /// In zh, this message translates to:
  /// **'暂无工具描述'**
  String get toolNoDescription;

  /// No description provided for @toolDialogSchemaTitle.
  ///
  /// In zh, this message translates to:
  /// **'工具 Schema ({label})'**
  String toolDialogSchemaTitle(String label);

  /// No description provided for @toolDialogNewTitle.
  ///
  /// In zh, this message translates to:
  /// **'新建自定义工具'**
  String get toolDialogNewTitle;

  /// No description provided for @toolDialogEditTitle.
  ///
  /// In zh, this message translates to:
  /// **'编辑自定义工具 ({label})'**
  String toolDialogEditTitle(String label);

  /// No description provided for @toolFieldId.
  ///
  /// In zh, this message translates to:
  /// **'标识'**
  String get toolFieldId;

  /// No description provided for @toolFieldIdHint.
  ///
  /// In zh, this message translates to:
  /// **'如 custom_tool'**
  String get toolFieldIdHint;

  /// No description provided for @toolFieldName.
  ///
  /// In zh, this message translates to:
  /// **'名称'**
  String get toolFieldName;

  /// No description provided for @toolFieldNameHint.
  ///
  /// In zh, this message translates to:
  /// **'如 自定义工具'**
  String get toolFieldNameHint;

  /// No description provided for @toolFieldDescription.
  ///
  /// In zh, this message translates to:
  /// **'工具描述'**
  String get toolFieldDescription;

  /// No description provided for @toolFieldDescriptionHint.
  ///
  /// In zh, this message translates to:
  /// **'清楚描述该工具的作用与使用时机...'**
  String get toolFieldDescriptionHint;

  /// No description provided for @toolFieldSchema.
  ///
  /// In zh, this message translates to:
  /// **'参数 Schema'**
  String get toolFieldSchema;

  /// No description provided for @toolCopySchema.
  ///
  /// In zh, this message translates to:
  /// **'复制 Schema'**
  String get toolCopySchema;

  /// No description provided for @toolCopySchemaSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已复制 Schema JSON 至剪贴板'**
  String get toolCopySchemaSuccess;

  /// No description provided for @toolFieldOutputTemplate.
  ///
  /// In zh, this message translates to:
  /// **'输出模板'**
  String get toolFieldOutputTemplate;

  /// No description provided for @toolFieldOutputTemplateHint.
  ///
  /// In zh, this message translates to:
  /// **'如：已成功执行并构建结果：{placeholder}'**
  String toolFieldOutputTemplateHint(String placeholder);

  /// No description provided for @toolSave.
  ///
  /// In zh, this message translates to:
  /// **'保存工具'**
  String get toolSave;

  /// No description provided for @toolNameEmptyError.
  ///
  /// In zh, this message translates to:
  /// **'工具名称 (Name) 不能为空'**
  String get toolNameEmptyError;

  /// No description provided for @toolSchemaParseError.
  ///
  /// In zh, this message translates to:
  /// **'Schema JSON 解析失败: {error}'**
  String toolSchemaParseError(String error);

  /// No description provided for @settingsSaveButton.
  ///
  /// In zh, this message translates to:
  /// **'保存设置'**
  String get settingsSaveButton;

  /// No description provided for @settingsSubtitleGeneral.
  ///
  /// In zh, this message translates to:
  /// **'配置 NovelAI 绘图服务凭证、本地存储目录与 Opus 免点保护。'**
  String get settingsSubtitleGeneral;

  /// No description provided for @settingsSubtitleModels.
  ///
  /// In zh, this message translates to:
  /// **'按供应商管理大语言模型服务，在线拉取模型列表并自动匹配 models.dev 能力元数据。'**
  String get settingsSubtitleModels;

  /// No description provided for @settingsSubtitlePresets.
  ///
  /// In zh, this message translates to:
  /// **'管理 Agent 预设，配置系统提示词、按需加载的 Skill 库与生图参数控制权限。'**
  String get settingsSubtitlePresets;

  /// No description provided for @settingsSubtitleDefaults.
  ///
  /// In zh, this message translates to:
  /// **'配置启动时的出厂默认生图模型、采样算法与步数引导。'**
  String get settingsSubtitleDefaults;

  /// No description provided for @settingsSubtitleBill.
  ///
  /// In zh, this message translates to:
  /// **'按周期统计各模型的 Token 用量账单，数据来自本地增量账本。'**
  String get settingsSubtitleBill;

  /// No description provided for @settingsSectionModelAndSampler.
  ///
  /// In zh, this message translates to:
  /// **'Model & Sampler'**
  String get settingsSectionModelAndSampler;

  /// No description provided for @settingsDefaultModelTitle.
  ///
  /// In zh, this message translates to:
  /// **'默认生图模型'**
  String get settingsDefaultModelTitle;

  /// No description provided for @settingsDefaultModelSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'应用启动或参数重置时的默认出厂模型'**
  String get settingsDefaultModelSubtitle;

  /// No description provided for @settingsDefaultSamplerTitle.
  ///
  /// In zh, this message translates to:
  /// **'默认采样算法'**
  String get settingsDefaultSamplerTitle;

  /// No description provided for @settingsDefaultSamplerSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生图时默认使用的降噪采样器'**
  String get settingsDefaultSamplerSubtitle;

  /// No description provided for @settingsDefaultNoiseScheduleTitle.
  ///
  /// In zh, this message translates to:
  /// **'默认噪声调度'**
  String get settingsDefaultNoiseScheduleTitle;

  /// No description provided for @settingsDefaultNoiseScheduleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'采样降噪过程中的时间步长调度算法'**
  String get settingsDefaultNoiseScheduleSubtitle;

  /// No description provided for @settingsSectionDefaultStepsAndScale.
  ///
  /// In zh, this message translates to:
  /// **'Default Steps & Scale'**
  String get settingsSectionDefaultStepsAndScale;

  /// No description provided for @settingsDefaultStepsTitle.
  ///
  /// In zh, this message translates to:
  /// **'默认步数 (Steps)'**
  String get settingsDefaultStepsTitle;

  /// No description provided for @settingsDefaultStepsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'初始采样迭代步数'**
  String get settingsDefaultStepsSubtitle;

  /// No description provided for @settingsDefaultScaleTitle.
  ///
  /// In zh, this message translates to:
  /// **'默认 CFG Scale'**
  String get settingsDefaultScaleTitle;

  /// No description provided for @settingsDefaultScaleSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'提示词引导强度 (当前: {scale})'**
  String settingsDefaultScaleSubtitle(String scale);

  /// No description provided for @settingsSectionAgentLoop.
  ///
  /// In zh, this message translates to:
  /// **'Agent Loop'**
  String get settingsSectionAgentLoop;

  /// No description provided for @settingsAgentMaxTurnsTitle.
  ///
  /// In zh, this message translates to:
  /// **'Agent 最大工具轮数'**
  String get settingsAgentMaxTurnsTitle;

  /// No description provided for @settingsAgentMaxTurnsSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'单次对话允许的工具链式调用轮数，达到后自动收尾总结'**
  String get settingsAgentMaxTurnsSubtitle;

  /// No description provided for @settingsSectionUsageBill.
  ///
  /// In zh, this message translates to:
  /// **'Usage Bill'**
  String get settingsSectionUsageBill;

  /// No description provided for @billPeriodToday.
  ///
  /// In zh, this message translates to:
  /// **'今天'**
  String get billPeriodToday;

  /// No description provided for @billPeriodLast7Days.
  ///
  /// In zh, this message translates to:
  /// **'近 7 天'**
  String get billPeriodLast7Days;

  /// No description provided for @billPeriodLast30Days.
  ///
  /// In zh, this message translates to:
  /// **'近 30 天'**
  String get billPeriodLast30Days;

  /// No description provided for @billPeriodAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get billPeriodAll;

  /// No description provided for @billSummaryRequestsAndTokens.
  ///
  /// In zh, this message translates to:
  /// **'{requests} 次请求 · 总计 {tokens} tokens'**
  String billSummaryRequestsAndTokens(int requests, String tokens);

  /// No description provided for @billEmptyRecords.
  ///
  /// In zh, this message translates to:
  /// **'该周期内暂无用量记录'**
  String get billEmptyRecords;

  /// No description provided for @billTableHeaderModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get billTableHeaderModel;

  /// No description provided for @billTableHeaderRequests.
  ///
  /// In zh, this message translates to:
  /// **'请求数'**
  String get billTableHeaderRequests;

  /// No description provided for @billTableHeaderInput.
  ///
  /// In zh, this message translates to:
  /// **'输入'**
  String get billTableHeaderInput;

  /// No description provided for @billTableHeaderOutput.
  ///
  /// In zh, this message translates to:
  /// **'输出'**
  String get billTableHeaderOutput;

  /// No description provided for @billTableHeaderCacheRead.
  ///
  /// In zh, this message translates to:
  /// **'缓存读'**
  String get billTableHeaderCacheRead;

  /// No description provided for @billTableHeaderHitRate.
  ///
  /// In zh, this message translates to:
  /// **'命中率'**
  String get billTableHeaderHitRate;

  /// No description provided for @billTableHeaderTotal.
  ///
  /// In zh, this message translates to:
  /// **'总计'**
  String get billTableHeaderTotal;

  /// No description provided for @billTableTotalRow.
  ///
  /// In zh, this message translates to:
  /// **'总计'**
  String get billTableTotalRow;

  /// No description provided for @paramsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'参数设置'**
  String get paramsPageTitle;

  /// No description provided for @paramsPageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'模型、分辨率与采样属性调节'**
  String get paramsPageSubtitle;

  /// No description provided for @paramsSectionModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get paramsSectionModel;

  /// No description provided for @paramsSteps.
  ///
  /// In zh, this message translates to:
  /// **'Steps'**
  String get paramsSteps;

  /// No description provided for @paramsPromptGuidance.
  ///
  /// In zh, this message translates to:
  /// **'Prompt Guidance'**
  String get paramsPromptGuidance;

  /// No description provided for @paramsSectionSeed.
  ///
  /// In zh, this message translates to:
  /// **'Seed'**
  String get paramsSectionSeed;

  /// No description provided for @paramsSeedHint.
  ///
  /// In zh, this message translates to:
  /// **'Enter a seed'**
  String get paramsSeedHint;

  /// No description provided for @paramsSeedTooltip.
  ///
  /// In zh, this message translates to:
  /// **'种子设置 ({mode} · {timing})'**
  String paramsSeedTooltip(String mode, String timing);

  /// No description provided for @paramsSeedModeRandomShort.
  ///
  /// In zh, this message translates to:
  /// **'随机'**
  String get paramsSeedModeRandomShort;

  /// No description provided for @paramsSeedModeIncreaseShort.
  ///
  /// In zh, this message translates to:
  /// **'递增'**
  String get paramsSeedModeIncreaseShort;

  /// No description provided for @paramsSeedModeFixedShort.
  ///
  /// In zh, this message translates to:
  /// **'固定'**
  String get paramsSeedModeFixedShort;

  /// No description provided for @paramsSeedTimingBefore.
  ///
  /// In zh, this message translates to:
  /// **'生成前'**
  String get paramsSeedTimingBefore;

  /// No description provided for @paramsSeedTimingAfter.
  ///
  /// In zh, this message translates to:
  /// **'生成后'**
  String get paramsSeedTimingAfter;

  /// No description provided for @paramsSectionSampler.
  ///
  /// In zh, this message translates to:
  /// **'Sampler'**
  String get paramsSectionSampler;

  /// No description provided for @paramsSeedModeGroup.
  ///
  /// In zh, this message translates to:
  /// **'种子模式'**
  String get paramsSeedModeGroup;

  /// No description provided for @paramsSeedModeRandomTitle.
  ///
  /// In zh, this message translates to:
  /// **'1. Random (随机)'**
  String get paramsSeedModeRandomTitle;

  /// No description provided for @paramsSeedModeRandomSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生图时自动生成全新随机种子'**
  String get paramsSeedModeRandomSubtitle;

  /// No description provided for @paramsSeedModeIncreaseTitle.
  ///
  /// In zh, this message translates to:
  /// **'2. Increase (递增)'**
  String get paramsSeedModeIncreaseTitle;

  /// No description provided for @paramsSeedModeIncreaseSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生图时种子数值自动 +1'**
  String get paramsSeedModeIncreaseSubtitle;

  /// No description provided for @paramsSeedModeFixedTitle.
  ///
  /// In zh, this message translates to:
  /// **'3. Fixed (固定)'**
  String get paramsSeedModeFixedTitle;

  /// No description provided for @paramsSeedModeFixedSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'保持当前设置的种子数值不变'**
  String get paramsSeedModeFixedSubtitle;

  /// No description provided for @paramsSeedTimingGroup.
  ///
  /// In zh, this message translates to:
  /// **'生成控制'**
  String get paramsSeedTimingGroup;

  /// No description provided for @paramsSeedRandomizeNow.
  ///
  /// In zh, this message translates to:
  /// **'立即随机种子'**
  String get paramsSeedRandomizeNow;

  /// No description provided for @paramsSeedResetRandom.
  ///
  /// In zh, this message translates to:
  /// **'清空重置为随机 (-1)'**
  String get paramsSeedResetRandom;

  /// No description provided for @paramsSectionAdvanced.
  ///
  /// In zh, this message translates to:
  /// **'Advanced Settings'**
  String get paramsSectionAdvanced;

  /// No description provided for @paramsPromptGuidanceRescale.
  ///
  /// In zh, this message translates to:
  /// **'Prompt Guidance Rescale'**
  String get paramsPromptGuidanceRescale;

  /// No description provided for @paramsSectionNoiseSchedule.
  ///
  /// In zh, this message translates to:
  /// **'Noise Schedule'**
  String get paramsSectionNoiseSchedule;

  /// No description provided for @paramsStripMetadata.
  ///
  /// In zh, this message translates to:
  /// **'删除元数据'**
  String get paramsStripMetadata;

  /// No description provided for @paramsStripMetadataSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'导出与复制时抹除所有生成参数与隐写'**
  String get paramsStripMetadataSubtitle;

  /// No description provided for @paramsAddWatermark.
  ///
  /// In zh, this message translates to:
  /// **'添加水印'**
  String get paramsAddWatermark;

  /// No description provided for @paramsAddWatermarkSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'仅在复制/下载时生效，UI 画板不显示'**
  String get paramsAddWatermarkSubtitle;

  /// No description provided for @paramsKeepOriginalImage.
  ///
  /// In zh, this message translates to:
  /// **'保持原图像'**
  String get paramsKeepOriginalImage;

  /// No description provided for @paramsKeepOriginalImageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'生图落盘时额外保存一份纯净原图 (_raw.png)'**
  String get paramsKeepOriginalImageSubtitle;

  /// No description provided for @resolutionTitle.
  ///
  /// In zh, this message translates to:
  /// **'分辨率'**
  String get resolutionTitle;

  /// No description provided for @resolutionOrientationLandscape.
  ///
  /// In zh, this message translates to:
  /// **'Landscape'**
  String get resolutionOrientationLandscape;

  /// No description provided for @resolutionOrientationPortrait.
  ///
  /// In zh, this message translates to:
  /// **'Portrait'**
  String get resolutionOrientationPortrait;

  /// No description provided for @resolutionOrientationSquare.
  ///
  /// In zh, this message translates to:
  /// **'Square'**
  String get resolutionOrientationSquare;

  /// No description provided for @resolutionOrientationSquareDisabled.
  ///
  /// In zh, this message translates to:
  /// **'Square (Wallpaper 暂无 1:1 比例)'**
  String get resolutionOrientationSquareDisabled;

  /// No description provided for @resolutionSwapTooltip.
  ///
  /// In zh, this message translates to:
  /// **'Swap'**
  String get resolutionSwapTooltip;

  /// No description provided for @watermarkPickImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择图片失败: {error}'**
  String watermarkPickImageFailed(String error);

  /// No description provided for @watermarkPositionTopLeft.
  ///
  /// In zh, this message translates to:
  /// **'左上'**
  String get watermarkPositionTopLeft;

  /// No description provided for @watermarkPositionTopRight.
  ///
  /// In zh, this message translates to:
  /// **'右上'**
  String get watermarkPositionTopRight;

  /// No description provided for @watermarkPositionCenter.
  ///
  /// In zh, this message translates to:
  /// **'居中'**
  String get watermarkPositionCenter;

  /// No description provided for @watermarkPositionBottomLeft.
  ///
  /// In zh, this message translates to:
  /// **'左下'**
  String get watermarkPositionBottomLeft;

  /// No description provided for @watermarkPositionBottomRight.
  ///
  /// In zh, this message translates to:
  /// **'右下'**
  String get watermarkPositionBottomRight;

  /// No description provided for @watermarkSmartPositionApplied.
  ///
  /// In zh, this message translates to:
  /// **'已按低信息区域智能选位'**
  String get watermarkSmartPositionApplied;

  /// No description provided for @watermarkSmartPositionNoImage.
  ///
  /// In zh, this message translates to:
  /// **'画板暂无图片，无法智能选位'**
  String get watermarkSmartPositionNoImage;

  /// No description provided for @watermarkPositionTitle.
  ///
  /// In zh, this message translates to:
  /// **'水印位置'**
  String get watermarkPositionTitle;

  /// No description provided for @watermarkSmartPositionTooltip.
  ///
  /// In zh, this message translates to:
  /// **'智能选位：分析当前画板图像，把水印放到细节最少的区域'**
  String get watermarkSmartPositionTooltip;

  /// No description provided for @watermarkPositionPillTooltip.
  ///
  /// In zh, this message translates to:
  /// **'在画板上拖动定位水印 (或按 ESC 退出)'**
  String get watermarkPositionPillTooltip;

  /// No description provided for @watermarkPositionPillLabel.
  ///
  /// In zh, this message translates to:
  /// **'位置: {position}'**
  String watermarkPositionPillLabel(String position);

  /// No description provided for @watermarkAutoPosition.
  ///
  /// In zh, this message translates to:
  /// **'自动选位'**
  String get watermarkAutoPosition;

  /// No description provided for @watermarkAutoPositionSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'每次合成时分析图像，自动放入信息量最低的区域'**
  String get watermarkAutoPositionSubtitle;

  /// No description provided for @watermarkAutoContrast.
  ///
  /// In zh, this message translates to:
  /// **'自动对比度'**
  String get watermarkAutoContrast;

  /// No description provided for @watermarkAutoContrastSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'按水印下方背景亮度自动加深或提亮，保证可见'**
  String get watermarkAutoContrastSubtitle;

  /// No description provided for @watermarkScalePercent.
  ///
  /// In zh, this message translates to:
  /// **'水印缩放 (%)'**
  String get watermarkScalePercent;

  /// No description provided for @watermarkOpacityPercent.
  ///
  /// In zh, this message translates to:
  /// **'不透明度 (%)'**
  String get watermarkOpacityPercent;

  /// No description provided for @watermarkMarginPercent.
  ///
  /// In zh, this message translates to:
  /// **'边距比例 (%)'**
  String get watermarkMarginPercent;

  /// No description provided for @watermarkBlindTitle.
  ///
  /// In zh, this message translates to:
  /// **'盲水印'**
  String get watermarkBlindTitle;

  /// No description provided for @watermarkBlindSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'频域隐形水印，肉眼不可见；粘贴图片到元数据弹窗可提取'**
  String get watermarkBlindSubtitle;

  /// No description provided for @watermarkBlindEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get watermarkBlindEnable;

  /// No description provided for @watermarkBlindTextHint.
  ///
  /// In zh, this message translates to:
  /// **'签名 / 版权信息文本'**
  String get watermarkBlindTextHint;

  /// No description provided for @watermarkBlindStrength.
  ///
  /// In zh, this message translates to:
  /// **'盲水印强度'**
  String get watermarkBlindStrength;

  /// No description provided for @watermarkLoadedImage.
  ///
  /// In zh, this message translates to:
  /// **'已加载水印图片'**
  String get watermarkLoadedImage;

  /// No description provided for @watermarkEffectiveOnExport.
  ///
  /// In zh, this message translates to:
  /// **'仅在复制/下载时合成生效'**
  String get watermarkEffectiveOnExport;

  /// No description provided for @watermarkChangeImageTooltip.
  ///
  /// In zh, this message translates to:
  /// **'更换图片'**
  String get watermarkChangeImageTooltip;

  /// No description provided for @watermarkClearImageTooltip.
  ///
  /// In zh, this message translates to:
  /// **'清除水印图片'**
  String get watermarkClearImageTooltip;

  /// No description provided for @watermarkSelectLocalImage.
  ///
  /// In zh, this message translates to:
  /// **'点击选择本地水印图片 (PNG/JPG)'**
  String get watermarkSelectLocalImage;

  /// No description provided for @watermarkOverlayScale.
  ///
  /// In zh, this message translates to:
  /// **'缩放: {scale}%'**
  String watermarkOverlayScale(String scale);

  /// No description provided for @watermarkOverlayPosition.
  ///
  /// In zh, this message translates to:
  /// **'位置: {x}%, {y}%'**
  String watermarkOverlayPosition(int x, int y);

  /// No description provided for @promptsPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'提示词管理'**
  String get promptsPageTitle;

  /// No description provided for @promptsPageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'正向提示词、负面排除词与全局固定词缀'**
  String get promptsPageSubtitle;

  /// No description provided for @promptsCorePromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入核心提示词或自然语言散文描述，如: 1girl, solo, silver hair, masterpiece...'**
  String get promptsCorePromptHint;

  /// No description provided for @promptsSwitchToTabbedMode.
  ///
  /// In zh, this message translates to:
  /// **'切换为标签页模式'**
  String get promptsSwitchToTabbedMode;

  /// No description provided for @promptsCustomUndesiredHint.
  ///
  /// In zh, this message translates to:
  /// **'输入自定义排除词，如: bad hands, blurry, extra limbs...'**
  String get promptsCustomUndesiredHint;

  /// No description provided for @promptsSwitchToStackedMode.
  ///
  /// In zh, this message translates to:
  /// **'切换为垂直并排模式'**
  String get promptsSwitchToStackedMode;

  /// No description provided for @promptsTabbedPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入核心提示词或自然语言散文描述，如: 1girl, solo, silver hair...'**
  String get promptsTabbedPromptHint;

  /// No description provided for @promptsTabbedUndesiredHint.
  ///
  /// In zh, this message translates to:
  /// **'排除不需要的特征与缺陷，如: lowres, bad anatomy, bad hands...'**
  String get promptsTabbedUndesiredHint;

  /// No description provided for @promptsResizePromptTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整提示词输入区高度 (双击重置)'**
  String get promptsResizePromptTooltip;

  /// No description provided for @promptsIncreaseWeightTooltip.
  ///
  /// In zh, this message translates to:
  /// **'增加标签数值权重 (Ctrl+↑，格式 x.x::tag::)'**
  String get promptsIncreaseWeightTooltip;

  /// No description provided for @promptsDecreaseWeightTooltip.
  ///
  /// In zh, this message translates to:
  /// **'降低标签数值权重 (Ctrl+↓，格式 x.x::tag::)'**
  String get promptsDecreaseWeightTooltip;

  /// No description provided for @promptsToggleDisabledTooltip.
  ///
  /// In zh, this message translates to:
  /// **'切换禁用状态 (Ctrl+/)'**
  String get promptsToggleDisabledTooltip;

  /// No description provided for @promptsFormatTooltip.
  ///
  /// In zh, this message translates to:
  /// **'格式化与SD语法转换 (Ctrl+Shift+F)'**
  String get promptsFormatTooltip;

  /// No description provided for @promptsTagBrowserTooltip.
  ///
  /// In zh, this message translates to:
  /// **'打开 Danbooru 标签灵感库'**
  String get promptsTagBrowserTooltip;

  /// No description provided for @promptsAffixesHint.
  ///
  /// In zh, this message translates to:
  /// **'全局固定前置与后置词缀'**
  String get promptsAffixesHint;

  /// No description provided for @charPromptDeckTabCharacter.
  ///
  /// In zh, this message translates to:
  /// **'多角色提示词'**
  String get charPromptDeckTabCharacter;

  /// No description provided for @charPromptDeckTabAffixes.
  ///
  /// In zh, this message translates to:
  /// **'固定词缀'**
  String get charPromptDeckTabAffixes;

  /// No description provided for @charPromptEnabled.
  ///
  /// In zh, this message translates to:
  /// **'已启用'**
  String get charPromptEnabled;

  /// No description provided for @charPromptDisabled.
  ///
  /// In zh, this message translates to:
  /// **'已停用'**
  String get charPromptDisabled;

  /// No description provided for @charPromptPositionAi.
  ///
  /// In zh, this message translates to:
  /// **'AI 自动'**
  String get charPromptPositionAi;

  /// No description provided for @charPromptPositionCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义'**
  String get charPromptPositionCustom;

  /// No description provided for @charPromptIsolationHint.
  ///
  /// In zh, this message translates to:
  /// **'独立角色物理隔离'**
  String get charPromptIsolationHint;

  /// No description provided for @charPromptUnsupportedModel.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持角色提示词 (仅 V4 及以上模型生效)，下方配置将保留但不会参与生成。'**
  String get charPromptUnsupportedModel;

  /// No description provided for @charPromptEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无独立角色提示词'**
  String get charPromptEmptyTitle;

  /// No description provided for @charPromptEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角「女 / 男 / 其他」预设按钮即可开启多角色防串色隔离生图'**
  String get charPromptEmptyDescription;

  /// No description provided for @charPromptExitCanvasEditTooltip.
  ///
  /// In zh, this message translates to:
  /// **'退出画板位置编辑'**
  String get charPromptExitCanvasEditTooltip;

  /// No description provided for @charPromptEnterCanvasEditTooltip.
  ///
  /// In zh, this message translates to:
  /// **'在中间画板编辑角色位置'**
  String get charPromptEnterCanvasEditTooltip;

  /// No description provided for @charPromptCanvasEditing.
  ///
  /// In zh, this message translates to:
  /// **'编辑中'**
  String get charPromptCanvasEditing;

  /// No description provided for @charPromptCanvasEdit.
  ///
  /// In zh, this message translates to:
  /// **'画板编辑'**
  String get charPromptCanvasEdit;

  /// No description provided for @charPromptAddFemaleTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加女角色 (初始提示词 girl)'**
  String get charPromptAddFemaleTooltip;

  /// No description provided for @charPromptAddMaleTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加男角色 (初始提示词 boy)'**
  String get charPromptAddMaleTooltip;

  /// No description provided for @charPromptAddOtherTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加其他角色 (初始提示词留空)'**
  String get charPromptAddOtherTooltip;

  /// No description provided for @charPromptLimitReached.
  ///
  /// In zh, this message translates to:
  /// **'已达上限'**
  String get charPromptLimitReached;

  /// No description provided for @charPromptGenderFemale.
  ///
  /// In zh, this message translates to:
  /// **'女'**
  String get charPromptGenderFemale;

  /// No description provided for @charPromptGenderMale.
  ///
  /// In zh, this message translates to:
  /// **'男'**
  String get charPromptGenderMale;

  /// No description provided for @charPromptGenderOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get charPromptGenderOther;

  /// No description provided for @charPromptDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'角色 {index}'**
  String charPromptDefaultName(int index);

  /// No description provided for @charPromptNameHint.
  ///
  /// In zh, this message translates to:
  /// **'角色名称 (可选)'**
  String get charPromptNameHint;

  /// No description provided for @charPromptSaveToLibraryTooltip.
  ///
  /// In zh, this message translates to:
  /// **'保存角色到词库'**
  String get charPromptSaveToLibraryTooltip;

  /// No description provided for @charPromptDeleteTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除该角色'**
  String get charPromptDeleteTooltip;

  /// No description provided for @charPromptEnable.
  ///
  /// In zh, this message translates to:
  /// **'启用'**
  String get charPromptEnable;

  /// No description provided for @charPromptDisable.
  ///
  /// In zh, this message translates to:
  /// **'停用'**
  String get charPromptDisable;

  /// No description provided for @charPromptPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'角色正向提示词，如: 1girl, silver hair, twintails, smile...'**
  String get charPromptPromptHint;

  /// No description provided for @charPromptResizePromptTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整正向提示词高度 (双击重置)'**
  String get charPromptResizePromptTooltip;

  /// No description provided for @charPromptNegativePromptHint.
  ///
  /// In zh, this message translates to:
  /// **'角色负面提示词 (可选)，如: bad hands, blurry...'**
  String get charPromptNegativePromptHint;

  /// No description provided for @charPromptResizeNegativeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整负面提示词高度 (双击重置)'**
  String get charPromptResizeNegativeTooltip;

  /// No description provided for @affixPrefixTitle.
  ///
  /// In zh, this message translates to:
  /// **'前置词 (放置于主提示词最前)'**
  String get affixPrefixTitle;

  /// No description provided for @affixResizePrefixTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整前置词高度 (双击重置)'**
  String get affixResizePrefixTooltip;

  /// No description provided for @affixSuffixTitle.
  ///
  /// In zh, this message translates to:
  /// **'后缀词 (放置于主提示词最后)'**
  String get affixSuffixTitle;

  /// No description provided for @affixResizeSuffixTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整后缀词高度 (双击重置)'**
  String get affixResizeSuffixTooltip;

  /// No description provided for @annotHistoryTitle.
  ///
  /// In zh, this message translates to:
  /// **'History '**
  String get annotHistoryTitle;

  /// No description provided for @annotHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'无图片'**
  String get annotHistoryEmpty;

  /// No description provided for @annotHistoryAddedAsReference.
  ///
  /// In zh, this message translates to:
  /// **'已将历史图片添加为大画布参考图'**
  String get annotHistoryAddedAsReference;

  /// No description provided for @annotHistoryImportTooltip.
  ///
  /// In zh, this message translates to:
  /// **'导入本地图片为参考图'**
  String get annotHistoryImportTooltip;

  /// No description provided for @annotHistoryImportImage.
  ///
  /// In zh, this message translates to:
  /// **'导入图片'**
  String get annotHistoryImportImage;

  /// No description provided for @inpaintPageTitle.
  ///
  /// In zh, this message translates to:
  /// **'修复设置'**
  String get inpaintPageTitle;

  /// No description provided for @inpaintPageSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'局部重绘与高精度潜空间焦点特写'**
  String get inpaintPageSubtitle;

  /// No description provided for @inpaintSectionMode.
  ///
  /// In zh, this message translates to:
  /// **'修复模式'**
  String get inpaintSectionMode;

  /// No description provided for @inpaintModeFocus.
  ///
  /// In zh, this message translates to:
  /// **'焦点特写'**
  String get inpaintModeFocus;

  /// No description provided for @inpaintModeFocusSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'超采样无损回贴'**
  String get inpaintModeFocusSubtitle;

  /// No description provided for @inpaintModeStandard.
  ///
  /// In zh, this message translates to:
  /// **'常规重绘'**
  String get inpaintModeStandard;

  /// No description provided for @inpaintModeStandardSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'整图尺度重绘'**
  String get inpaintModeStandardSubtitle;

  /// No description provided for @inpaintModeAiEdit.
  ///
  /// In zh, this message translates to:
  /// **'AI 整图编辑'**
  String get inpaintModeAiEdit;

  /// No description provided for @inpaintModeAiEditSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'外部绘图模型重绘'**
  String get inpaintModeAiEditSubtitle;

  /// No description provided for @inpaintAiEditAspectRatio.
  ///
  /// In zh, this message translates to:
  /// **'生图比例'**
  String get inpaintAiEditAspectRatio;

  /// No description provided for @inpaintAiEditFollowSource.
  ///
  /// In zh, this message translates to:
  /// **'跟随原图'**
  String get inpaintAiEditFollowSource;

  /// No description provided for @inpaintAiEditResolution.
  ///
  /// In zh, this message translates to:
  /// **'生图分辨率'**
  String get inpaintAiEditResolution;

  /// No description provided for @inpaintAiEditDefaultResolution.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get inpaintAiEditDefaultResolution;

  /// No description provided for @inpaintContextPadding.
  ///
  /// In zh, this message translates to:
  /// **'外延上下文 (px)'**
  String get inpaintContextPadding;

  /// No description provided for @inpaintStrength.
  ///
  /// In zh, this message translates to:
  /// **'重绘强度'**
  String get inpaintStrength;

  /// No description provided for @inpaintNoise.
  ///
  /// In zh, this message translates to:
  /// **'附加噪声'**
  String get inpaintNoise;

  /// No description provided for @inpaintSectionInstruction.
  ///
  /// In zh, this message translates to:
  /// **'修改指令设置'**
  String get inpaintSectionInstruction;

  /// No description provided for @inpaintSectionPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词设置'**
  String get inpaintSectionPrompt;

  /// No description provided for @inpaintReuseMainPromptAsInstruction.
  ///
  /// In zh, this message translates to:
  /// **'复用主工作台正向词作为指令'**
  String get inpaintReuseMainPromptAsInstruction;

  /// No description provided for @inpaintReuseMainPrompt.
  ///
  /// In zh, this message translates to:
  /// **'复用主工作台正向词'**
  String get inpaintReuseMainPrompt;

  /// No description provided for @inpaintCustomInstruction.
  ///
  /// In zh, this message translates to:
  /// **'自定义修改指令'**
  String get inpaintCustomInstruction;

  /// No description provided for @inpaintCustomPrompt.
  ///
  /// In zh, this message translates to:
  /// **'修复专属正向词'**
  String get inpaintCustomPrompt;

  /// No description provided for @inpaintInstructionHint.
  ///
  /// In zh, this message translates to:
  /// **'输入自然语言修改指令，如: 把背景换成夕阳下的海滩...'**
  String get inpaintInstructionHint;

  /// No description provided for @inpaintPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入修复专属正向提示词...'**
  String get inpaintPromptHint;

  /// No description provided for @inpaintMainPrompt.
  ///
  /// In zh, this message translates to:
  /// **'主工作台正向词'**
  String get inpaintMainPrompt;

  /// No description provided for @inpaintMainNegativePrompt.
  ///
  /// In zh, this message translates to:
  /// **'主工作台负向词'**
  String get inpaintMainNegativePrompt;

  /// No description provided for @inpaintReuseMainNegative.
  ///
  /// In zh, this message translates to:
  /// **'复用主工作台负向词'**
  String get inpaintReuseMainNegative;

  /// No description provided for @inpaintCustomNegative.
  ///
  /// In zh, this message translates to:
  /// **'修复专属负向词'**
  String get inpaintCustomNegative;

  /// No description provided for @inpaintNegativePromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入修复专属负向提示词...'**
  String get inpaintNegativePromptHint;

  /// No description provided for @inpaintImageModel.
  ///
  /// In zh, this message translates to:
  /// **'绘图模型'**
  String get inpaintImageModel;

  /// No description provided for @inpaintConsumeQuota.
  ///
  /// In zh, this message translates to:
  /// **'消耗绘图模型额度'**
  String get inpaintConsumeQuota;

  /// No description provided for @inpaintProvider.
  ///
  /// In zh, this message translates to:
  /// **'供应商'**
  String get inpaintProvider;

  /// No description provided for @inpaintModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get inpaintModel;

  /// No description provided for @inpaintNoModelConfigured.
  ///
  /// In zh, this message translates to:
  /// **'未配置绘图模型。请到设置 → Models 页「AI 整图编辑」选择具备图像输出能力的模型供应商与模型 (如 nano banana / gpt-image)。'**
  String get inpaintNoModelConfigured;

  /// No description provided for @inpaintLatentFocusGeometry.
  ///
  /// In zh, this message translates to:
  /// **'潜空间焦点几何'**
  String get inpaintLatentFocusGeometry;

  /// No description provided for @inpaintRequiresPoints.
  ///
  /// In zh, this message translates to:
  /// **'需消耗点数'**
  String get inpaintRequiresPoints;

  /// No description provided for @inpaintTargetSelection.
  ///
  /// In zh, this message translates to:
  /// **'目标选区'**
  String get inpaintTargetSelection;

  /// No description provided for @inpaintContextCrop.
  ///
  /// In zh, this message translates to:
  /// **'上下文外延'**
  String get inpaintContextCrop;

  /// No description provided for @inpaintRequestResolution.
  ///
  /// In zh, this message translates to:
  /// **'请求分辨率'**
  String get inpaintRequestResolution;

  /// No description provided for @inpaintSupersample.
  ///
  /// In zh, this message translates to:
  /// **'{scale}x 超采样'**
  String inpaintSupersample(String scale);

  /// No description provided for @inpaintReusedLabel.
  ///
  /// In zh, this message translates to:
  /// **'已复用 {label}'**
  String inpaintReusedLabel(String label);

  /// No description provided for @inpaintReusedPromptEmpty.
  ///
  /// In zh, this message translates to:
  /// **'（内容为空，可至提示词管理页配置）'**
  String get inpaintReusedPromptEmpty;

  /// No description provided for @inpaintOverlayEmptyHint.
  ///
  /// In zh, this message translates to:
  /// **'生成或选择一张图片后即可开始局部修复'**
  String get inpaintOverlayEmptyHint;

  /// No description provided for @inpaintOverlayContextCrop.
  ///
  /// In zh, this message translates to:
  /// **'上下文外延 +{padding}px'**
  String inpaintOverlayContextCrop(int padding);

  /// No description provided for @inpaintOverlayInProgress.
  ///
  /// In zh, this message translates to:
  /// **'局部修复中...'**
  String get inpaintOverlayInProgress;

  /// No description provided for @inpaintOverlayAiEditHint.
  ///
  /// In zh, this message translates to:
  /// **'AI 整图编辑 · 整张图片重绘，无需框选区域'**
  String get inpaintOverlayAiEditHint;

  /// No description provided for @inpaintToolRect.
  ///
  /// In zh, this message translates to:
  /// **'框选'**
  String get inpaintToolRect;

  /// No description provided for @inpaintToolBrush.
  ///
  /// In zh, this message translates to:
  /// **'画笔'**
  String get inpaintToolBrush;

  /// No description provided for @inpaintToolEraser.
  ///
  /// In zh, this message translates to:
  /// **'橡皮'**
  String get inpaintToolEraser;

  /// No description provided for @inpaintClearMask.
  ///
  /// In zh, this message translates to:
  /// **'清除蒙版'**
  String get inpaintClearMask;

  /// No description provided for @canvasImportedReference.
  ///
  /// In zh, this message translates to:
  /// **'已导入参考图: {fileName}'**
  String canvasImportedReference(String fileName);

  /// No description provided for @canvasDropTargetTitle.
  ///
  /// In zh, this message translates to:
  /// **'松开鼠标导入图片 (自动识别生成元数据)'**
  String get canvasDropTargetTitle;

  /// No description provided for @canvasCopiedRawImage.
  ///
  /// In zh, this message translates to:
  /// **'已复制原图像到剪贴板'**
  String get canvasCopiedRawImage;

  /// No description provided for @canvasCopiedImage.
  ///
  /// In zh, this message translates to:
  /// **'已复制图像到剪贴板'**
  String get canvasCopiedImage;

  /// No description provided for @canvasCopyImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'复制图像失败'**
  String get canvasCopyImageFailed;

  /// No description provided for @canvasActionAddAnnotation.
  ///
  /// In zh, this message translates to:
  /// **'添加批注'**
  String get canvasActionAddAnnotation;

  /// No description provided for @canvasActionViewAnnotation.
  ///
  /// In zh, this message translates to:
  /// **'查看批注 ({count})'**
  String canvasActionViewAnnotation(int count);

  /// No description provided for @canvasActionSendToInpaint.
  ///
  /// In zh, this message translates to:
  /// **'发送到修复'**
  String get canvasActionSendToInpaint;

  /// No description provided for @canvasActionUpscale.
  ///
  /// In zh, this message translates to:
  /// **'超分放大'**
  String get canvasActionUpscale;

  /// No description provided for @canvasActionCopyImage.
  ///
  /// In zh, this message translates to:
  /// **'复制图像'**
  String get canvasActionCopyImage;

  /// No description provided for @canvasActionCopyRawImage.
  ///
  /// In zh, this message translates to:
  /// **'复制原图像'**
  String get canvasActionCopyRawImage;

  /// No description provided for @canvasActionCopyPrompt.
  ///
  /// In zh, this message translates to:
  /// **'复制提示词'**
  String get canvasActionCopyPrompt;

  /// No description provided for @canvasCopiedPrompt.
  ///
  /// In zh, this message translates to:
  /// **'已复制提示词到剪贴板'**
  String get canvasCopiedPrompt;

  /// No description provided for @canvasActionReuseParams.
  ///
  /// In zh, this message translates to:
  /// **'复用参数'**
  String get canvasActionReuseParams;

  /// No description provided for @canvasAppliedParams.
  ///
  /// In zh, this message translates to:
  /// **'已应用该图参数至左侧面板'**
  String get canvasAppliedParams;

  /// No description provided for @canvasActionViewLightbox.
  ///
  /// In zh, this message translates to:
  /// **'查看大图'**
  String get canvasActionViewLightbox;

  /// No description provided for @canvasActionDeleteFromHistory.
  ///
  /// In zh, this message translates to:
  /// **'从历史记录删除'**
  String get canvasActionDeleteFromHistory;

  /// No description provided for @canvasDeletedFromHistory.
  ///
  /// In zh, this message translates to:
  /// **'已从历史记录删除图片'**
  String get canvasDeletedFromHistory;

  /// No description provided for @canvasActionClearHistory.
  ///
  /// In zh, this message translates to:
  /// **'清空历史记录'**
  String get canvasActionClearHistory;

  /// No description provided for @canvasClearedHistory.
  ///
  /// In zh, this message translates to:
  /// **'已清空历史记录'**
  String get canvasClearedHistory;

  /// No description provided for @canvasClearHistoryAutoSaveMessage.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空画板历史中的 {count} 张图片吗？仅清空界面记录，本地已保存的图片文件会保留，此操作无法撤销。'**
  String canvasClearHistoryAutoSaveMessage(int count);

  /// No description provided for @canvasClearHistoryManualSaveMessage.
  ///
  /// In zh, this message translates to:
  /// **'确定要清空历史中的 {count} 张图片吗？缓存中未保存的图片会被删除，已手动保存到存储目录的文件会保留，此操作无法撤销。'**
  String canvasClearHistoryManualSaveMessage(int count);

  /// No description provided for @canvasHistoryEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史'**
  String get canvasHistoryEmpty;

  /// No description provided for @canvasCopySeedTooltip.
  ///
  /// In zh, this message translates to:
  /// **'点击复制随机种子'**
  String get canvasCopySeedTooltip;

  /// No description provided for @canvasCopiedSeed.
  ///
  /// In zh, this message translates to:
  /// **'已复制种子到剪贴板'**
  String get canvasCopiedSeed;

  /// No description provided for @canvasEnterAnnotationTooltip.
  ///
  /// In zh, this message translates to:
  /// **'进入画板批注模式 (圈选/锚点/整图)'**
  String get canvasEnterAnnotationTooltip;

  /// No description provided for @canvasAnnotate.
  ///
  /// In zh, this message translates to:
  /// **'批注'**
  String get canvasAnnotate;

  /// No description provided for @canvasAnnotateWithCount.
  ///
  /// In zh, this message translates to:
  /// **'批注 ({count})'**
  String canvasAnnotateWithCount(int count);

  /// No description provided for @canvasSaveButtonTooltip.
  ///
  /// In zh, this message translates to:
  /// **'保存当前图片到本地存储目录 (按导出设置处理元数据与水印)'**
  String get canvasSaveButtonTooltip;

  /// No description provided for @canvasSavedImage.
  ///
  /// In zh, this message translates to:
  /// **'已保存: {path}'**
  String canvasSavedImage(String path);

  /// No description provided for @canvasSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败，请检查存储目录设置'**
  String get canvasSaveFailed;

  /// No description provided for @canvasSaveImage.
  ///
  /// In zh, this message translates to:
  /// **'保存图片'**
  String get canvasSaveImage;

  /// No description provided for @canvasUnseenLatestBanner.
  ///
  /// In zh, this message translates to:
  /// **'已生成新图片 · 点击查看最新'**
  String get canvasUnseenLatestBanner;

  /// No description provided for @canvasOpenHistoryTooltip.
  ///
  /// In zh, this message translates to:
  /// **'展开历史记录'**
  String get canvasOpenHistoryTooltip;

  /// No description provided for @canvasEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'画板暂无图像'**
  String get canvasEmptyTitle;

  /// No description provided for @canvasEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'可在左侧配置参数后生成图片，历史记录将以垂直图像流展示'**
  String get canvasEmptyDescription;

  /// No description provided for @metadataBlindWatermarkContent.
  ///
  /// In zh, this message translates to:
  /// **'盲水印内容'**
  String get metadataBlindWatermarkContent;

  /// No description provided for @metadataBlindWatermarkNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未检测到盲水印'**
  String get metadataBlindWatermarkNotFound;

  /// No description provided for @metadataDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'图像元数据读取'**
  String get metadataDialogTitle;

  /// No description provided for @metadataPromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'正向提示词 (Prompt)'**
  String get metadataPromptTitle;

  /// No description provided for @metadataCopiedPrompt.
  ///
  /// In zh, this message translates to:
  /// **'已复制正向提示词'**
  String get metadataCopiedPrompt;

  /// No description provided for @metadataNegativePromptTitle.
  ///
  /// In zh, this message translates to:
  /// **'负向提示词 (Negative Prompt)'**
  String get metadataNegativePromptTitle;

  /// No description provided for @metadataCopiedNegativePrompt.
  ///
  /// In zh, this message translates to:
  /// **'已复制负向提示词'**
  String get metadataCopiedNegativePrompt;

  /// No description provided for @metadataDimensionAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动'**
  String get metadataDimensionAuto;

  /// No description provided for @metadataDimensions.
  ///
  /// In zh, this message translates to:
  /// **'尺寸: {width} x {height}'**
  String metadataDimensions(String width, String height);

  /// No description provided for @metadataModelUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知模型'**
  String get metadataModelUnknown;

  /// No description provided for @metadataSamplerDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get metadataSamplerDefault;

  /// No description provided for @metadataModelAndSampler.
  ///
  /// In zh, this message translates to:
  /// **'模型: {model}  ·  采样: {sampler}'**
  String metadataModelAndSampler(String model, String sampler);

  /// No description provided for @metadataSeedLabel.
  ///
  /// In zh, this message translates to:
  /// **'种子: {seed}'**
  String metadataSeedLabel(String seed);

  /// No description provided for @metadataCharacterPromptsTitle.
  ///
  /// In zh, this message translates to:
  /// **'多角色提示词 (Character Prompts)'**
  String get metadataCharacterPromptsTitle;

  /// No description provided for @metadataCharacterIndex.
  ///
  /// In zh, this message translates to:
  /// **'角色 {index}'**
  String metadataCharacterIndex(int index);

  /// No description provided for @metadataNegativePrefix.
  ///
  /// In zh, this message translates to:
  /// **'负向: {negative}'**
  String metadataNegativePrefix(String negative);

  /// No description provided for @metadataParametersTitle.
  ///
  /// In zh, this message translates to:
  /// **'生成参数'**
  String get metadataParametersTitle;

  /// No description provided for @metadataParamModel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get metadataParamModel;

  /// No description provided for @metadataParamUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知'**
  String get metadataParamUnknown;

  /// No description provided for @metadataParamSampler.
  ///
  /// In zh, this message translates to:
  /// **'采样算法'**
  String get metadataParamSampler;

  /// No description provided for @metadataParamDefault.
  ///
  /// In zh, this message translates to:
  /// **'默认'**
  String get metadataParamDefault;

  /// No description provided for @metadataParamSteps.
  ///
  /// In zh, this message translates to:
  /// **'步数'**
  String get metadataParamSteps;

  /// No description provided for @metadataParamSeed.
  ///
  /// In zh, this message translates to:
  /// **'种子 (Seed)'**
  String get metadataParamSeed;

  /// No description provided for @metadataParamSeedRandom.
  ///
  /// In zh, this message translates to:
  /// **'随机'**
  String get metadataParamSeedRandom;

  /// No description provided for @metadataParamNoiseSchedule.
  ///
  /// In zh, this message translates to:
  /// **'噪声调度'**
  String get metadataParamNoiseSchedule;

  /// No description provided for @metadataParamQualityPreset.
  ///
  /// In zh, this message translates to:
  /// **'质量预设'**
  String get metadataParamQualityPreset;

  /// No description provided for @metadataParamUcPreset.
  ///
  /// In zh, this message translates to:
  /// **'UC 预设'**
  String get metadataParamUcPreset;

  /// No description provided for @metadataParamTransparentBg.
  ///
  /// In zh, this message translates to:
  /// **'透明背景'**
  String get metadataParamTransparentBg;

  /// No description provided for @metadataParamEnabled.
  ///
  /// In zh, this message translates to:
  /// **'开启'**
  String get metadataParamEnabled;

  /// No description provided for @metadataRawJsonTitle.
  ///
  /// In zh, this message translates to:
  /// **'原始元数据 (Raw JSON / Text)'**
  String get metadataRawJsonTitle;

  /// No description provided for @metadataCopyRawTooltip.
  ///
  /// In zh, this message translates to:
  /// **'复制原始文本'**
  String get metadataCopyRawTooltip;

  /// No description provided for @metadataCopiedRaw.
  ///
  /// In zh, this message translates to:
  /// **'已复制原始元数据'**
  String get metadataCopiedRaw;

  /// No description provided for @metadataExtractBlindWatermark.
  ///
  /// In zh, this message translates to:
  /// **'提取盲水印'**
  String get metadataExtractBlindWatermark;

  /// No description provided for @metadataImportAsReference.
  ///
  /// In zh, this message translates to:
  /// **'作为参考图导入'**
  String get metadataImportAsReference;

  /// No description provided for @metadataImportedReference.
  ///
  /// In zh, this message translates to:
  /// **'已导入参考图'**
  String get metadataImportedReference;

  /// No description provided for @metadataApplyToWorkbench.
  ///
  /// In zh, this message translates to:
  /// **'应用全部参数到工作台'**
  String get metadataApplyToWorkbench;

  /// No description provided for @dockAbortWithSteps.
  ///
  /// In zh, this message translates to:
  /// **'终止生成 ({current}/{total})'**
  String dockAbortWithSteps(int current, int total);

  /// No description provided for @dockGenerateWithCost.
  ///
  /// In zh, this message translates to:
  /// **'生成图片 ({cost} Anlas)'**
  String dockGenerateWithCost(int cost);

  /// No description provided for @dockGenerateNeedPoints.
  ///
  /// In zh, this message translates to:
  /// **'生成图片 (需点数)'**
  String get dockGenerateNeedPoints;

  /// No description provided for @dockNoAccountInfo.
  ///
  /// In zh, this message translates to:
  /// **'未获取账号信息 (请检查 API Key)'**
  String get dockNoAccountInfo;

  /// No description provided for @dockAiEditing.
  ///
  /// In zh, this message translates to:
  /// **'AI 编辑中...'**
  String get dockAiEditing;

  /// No description provided for @dockInpainting.
  ///
  /// In zh, this message translates to:
  /// **'修复中...'**
  String get dockInpainting;

  /// No description provided for @dockRefreshTooltip.
  ///
  /// In zh, this message translates to:
  /// **'刷新体力与点数'**
  String get dockRefreshTooltip;

  /// No description provided for @sidebarTabParameters.
  ///
  /// In zh, this message translates to:
  /// **'参数'**
  String get sidebarTabParameters;

  /// No description provided for @sidebarTabInpaint.
  ///
  /// In zh, this message translates to:
  /// **'修复'**
  String get sidebarTabInpaint;

  /// No description provided for @sidebarSettingsTooltip.
  ///
  /// In zh, this message translates to:
  /// **'全局配置 (API Key / 存储 / LLM)'**
  String get sidebarSettingsTooltip;

  /// No description provided for @promptResizeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖动调整高度 (双击重置)'**
  String get promptResizeTooltip;

  /// No description provided for @studioClipboardImageDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'剪贴板图片.png'**
  String get studioClipboardImageDefaultName;

  /// No description provided for @studioImportedReference.
  ///
  /// In zh, this message translates to:
  /// **'已导入参考图'**
  String get studioImportedReference;

  /// No description provided for @boardPastedImage.
  ///
  /// In zh, this message translates to:
  /// **'已粘贴图片至大画布'**
  String get boardPastedImage;

  /// No description provided for @boardImportedReferenceNamed.
  ///
  /// In zh, this message translates to:
  /// **'已导入参考图: {name}'**
  String boardImportedReferenceNamed(String name);

  /// No description provided for @boardAddedHistoryImage.
  ///
  /// In zh, this message translates to:
  /// **'已将历史图片添加为大画布参考图'**
  String get boardAddedHistoryImage;

  /// No description provided for @boardDropInternalHint.
  ///
  /// In zh, this message translates to:
  /// **'松开鼠标放置参考图'**
  String get boardDropInternalHint;

  /// No description provided for @boardDropExternalHint.
  ///
  /// In zh, this message translates to:
  /// **'松开鼠标导入外部参考图'**
  String get boardDropExternalHint;

  /// No description provided for @boardExitAnnotation.
  ///
  /// In zh, this message translates to:
  /// **'退出批注'**
  String get boardExitAnnotation;

  /// No description provided for @boardSendAllToAi.
  ///
  /// In zh, this message translates to:
  /// **'发送全部批注到 AI'**
  String get boardSendAllToAi;

  /// No description provided for @boardWireMissedTarget.
  ///
  /// In zh, this message translates to:
  /// **'未命中选区/图钉，已取消连线'**
  String get boardWireMissedTarget;

  /// No description provided for @boardToolPan.
  ///
  /// In zh, this message translates to:
  /// **'漫游'**
  String get boardToolPan;

  /// No description provided for @boardToolRect.
  ///
  /// In zh, this message translates to:
  /// **'圈选选区'**
  String get boardToolRect;

  /// No description provided for @boardToolPoint.
  ///
  /// In zh, this message translates to:
  /// **'图钉锚点'**
  String get boardToolPoint;

  /// No description provided for @boardToolAddNote.
  ///
  /// In zh, this message translates to:
  /// **'+ 便利贴'**
  String get boardToolAddNote;

  /// No description provided for @boardToolAddImage.
  ///
  /// In zh, this message translates to:
  /// **'+ 参考图'**
  String get boardToolAddImage;

  /// No description provided for @boardToolPasteImage.
  ///
  /// In zh, this message translates to:
  /// **'粘贴图 (Ctrl+V)'**
  String get boardToolPasteImage;

  /// No description provided for @boardToolResetView.
  ///
  /// In zh, this message translates to:
  /// **'适应视口'**
  String get boardToolResetView;

  /// No description provided for @boardImageCardMainTitle.
  ///
  /// In zh, this message translates to:
  /// **'主图 (当前生成图)'**
  String get boardImageCardMainTitle;

  /// No description provided for @boardImageCardRefTitle.
  ///
  /// In zh, this message translates to:
  /// **'参考图 ({width}x{height})'**
  String boardImageCardRefTitle(int width, int height);

  /// No description provided for @boardImageCardRemoveTooltip.
  ///
  /// In zh, this message translates to:
  /// **'移除参考图卡片'**
  String get boardImageCardRemoveTooltip;

  /// No description provided for @boardImageResizeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖拽调节图片卡片大小 (按住 Shift 锁定宽高比)'**
  String get boardImageResizeTooltip;

  /// No description provided for @boardImageSendToInpaint.
  ///
  /// In zh, this message translates to:
  /// **'发送到修复'**
  String get boardImageSendToInpaint;

  /// No description provided for @boardAnnotationDeleteRect.
  ///
  /// In zh, this message translates to:
  /// **'删除选区'**
  String get boardAnnotationDeleteRect;

  /// No description provided for @boardAnnotationDeletePoint.
  ///
  /// In zh, this message translates to:
  /// **'删除锚点'**
  String get boardAnnotationDeletePoint;

  /// No description provided for @boardAnnotationResizeRect.
  ///
  /// In zh, this message translates to:
  /// **'拖拽调节选区大小'**
  String get boardAnnotationResizeRect;

  /// No description provided for @boardAnnotationSelectTooltip.
  ///
  /// In zh, this message translates to:
  /// **'点击选中该批注'**
  String get boardAnnotationSelectTooltip;

  /// No description provided for @boardWireDragSourceTooltip.
  ///
  /// In zh, this message translates to:
  /// **'按住拖出连线到选区/图钉'**
  String get boardWireDragSourceTooltip;

  /// No description provided for @boardNoteConnected.
  ///
  /// In zh, this message translates to:
  /// **'已连线'**
  String get boardNoteConnected;

  /// No description provided for @boardNoteTitle.
  ///
  /// In zh, this message translates to:
  /// **'便签'**
  String get boardNoteTitle;

  /// No description provided for @boardNoteDisconnectTooltip.
  ///
  /// In zh, this message translates to:
  /// **'断开连线'**
  String get boardNoteDisconnectTooltip;

  /// No description provided for @boardNoteDeleteTooltip.
  ///
  /// In zh, this message translates to:
  /// **'删除便签'**
  String get boardNoteDeleteTooltip;

  /// No description provided for @boardNoteHint.
  ///
  /// In zh, this message translates to:
  /// **'输入修改意见...'**
  String get boardNoteHint;

  /// No description provided for @boardNoteResizeTooltip.
  ///
  /// In zh, this message translates to:
  /// **'拖拽调节便签大小'**
  String get boardNoteResizeTooltip;

  /// No description provided for @charPosCanvasTempBoard.
  ///
  /// In zh, this message translates to:
  /// **'临时画板 · {width} × {height}'**
  String charPosCanvasTempBoard(int width, int height);

  /// No description provided for @posControlsDoneEditing.
  ///
  /// In zh, this message translates to:
  /// **'完成编辑'**
  String get posControlsDoneEditing;

  /// No description provided for @lightboxCloseTooltip.
  ///
  /// In zh, this message translates to:
  /// **'关闭大图展示'**
  String get lightboxCloseTooltip;

  /// No description provided for @librarySearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索词组合名称、提示词、标签...'**
  String get librarySearchHint;

  /// No description provided for @libraryDataManagement.
  ///
  /// In zh, this message translates to:
  /// **'数据管理'**
  String get libraryDataManagement;

  /// No description provided for @libraryExportJson.
  ///
  /// In zh, this message translates to:
  /// **'导出词库 (JSON)'**
  String get libraryExportJson;

  /// No description provided for @libraryImportJson.
  ///
  /// In zh, this message translates to:
  /// **'导入词库 (JSON)'**
  String get libraryImportJson;

  /// No description provided for @libraryManageButton.
  ///
  /// In zh, this message translates to:
  /// **'管理'**
  String get libraryManageButton;

  /// No description provided for @libraryNewCombo.
  ///
  /// In zh, this message translates to:
  /// **'新建词组合'**
  String get libraryNewCombo;

  /// No description provided for @libraryCategorySidebarTitle.
  ///
  /// In zh, this message translates to:
  /// **'标签分类'**
  String get libraryCategorySidebarTitle;

  /// No description provided for @libraryEntriesCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String libraryEntriesCount(int count);

  /// No description provided for @libraryCategoryAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get libraryCategoryAll;

  /// No description provided for @libraryExportCopied.
  ///
  /// In zh, this message translates to:
  /// **'已复制词库 JSON 数据到剪贴板，可粘贴备份或分享'**
  String get libraryExportCopied;

  /// No description provided for @libraryExportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导出失败: {error}'**
  String libraryExportFailed(String error);

  /// No description provided for @libraryImportDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'导入词库 JSON'**
  String get libraryImportDialogTitle;

  /// No description provided for @libraryImportPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请粘贴导出的词库 JSON 文本：'**
  String get libraryImportPrompt;

  /// No description provided for @libraryImportSuccess.
  ///
  /// In zh, this message translates to:
  /// **'成功导入 {count} 个新词组合条目'**
  String libraryImportSuccess(int count);

  /// No description provided for @libraryImportFailed.
  ///
  /// In zh, this message translates to:
  /// **'导入失败，请检查 JSON 格式: {error}'**
  String libraryImportFailed(String error);

  /// No description provided for @libraryApplyAsCharacter.
  ///
  /// In zh, this message translates to:
  /// **'已添加角色卡片: {title}'**
  String libraryApplyAsCharacter(String title);

  /// No description provided for @libraryApplyReplace.
  ///
  /// In zh, this message translates to:
  /// **'已替换工作台提示词: {title}'**
  String libraryApplyReplace(String title);

  /// No description provided for @libraryApplyAppendBoth.
  ///
  /// In zh, this message translates to:
  /// **'已追加正负提示词: {title}'**
  String libraryApplyAppendBoth(String title);

  /// No description provided for @libraryApplyAppendPrompt.
  ///
  /// In zh, this message translates to:
  /// **'已追加主提示词: {title}'**
  String libraryApplyAppendPrompt(String title);

  /// No description provided for @libraryReturnToWorkbench.
  ///
  /// In zh, this message translates to:
  /// **'返回工作台'**
  String get libraryReturnToWorkbench;

  /// No description provided for @libraryDeleteDialogTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除词组合'**
  String get libraryDeleteDialogTitle;

  /// No description provided for @libraryDeleteDialogMessage.
  ///
  /// In zh, this message translates to:
  /// **'确定要删除词组合「{title}」吗？此操作无法撤销。'**
  String libraryDeleteDialogMessage(String title);

  /// No description provided for @libraryDeletedCombo.
  ///
  /// In zh, this message translates to:
  /// **'已删除词组合: {title}'**
  String libraryDeletedCombo(String title);

  /// No description provided for @libraryEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'词库暂无条目'**
  String get libraryEmptyTitle;

  /// No description provided for @libraryNoMatchingTitle.
  ///
  /// In zh, this message translates to:
  /// **'没有匹配的词组合'**
  String get libraryNoMatchingTitle;

  /// No description provided for @libraryEmptyDescription.
  ///
  /// In zh, this message translates to:
  /// **'点击右上角「新建词组合」创建您的第一个专属提示词组合'**
  String get libraryEmptyDescription;

  /// No description provided for @libraryNoMatchingDescription.
  ///
  /// In zh, this message translates to:
  /// **'请尝试更换搜索词或分类筛选条件'**
  String get libraryNoMatchingDescription;

  /// No description provided for @libraryResetFilter.
  ///
  /// In zh, this message translates to:
  /// **'重置筛选条件'**
  String get libraryResetFilter;

  /// No description provided for @libraryCardCopiedPrompt.
  ///
  /// In zh, this message translates to:
  /// **'已复制「{title}」提示词到剪贴板'**
  String libraryCardCopiedPrompt(String title);

  /// No description provided for @libraryMenuAppendToPrompt.
  ///
  /// In zh, this message translates to:
  /// **'追加到工作台提示词'**
  String get libraryMenuAppendToPrompt;

  /// No description provided for @libraryMenuReplacePrompt.
  ///
  /// In zh, this message translates to:
  /// **'替换工作台提示词'**
  String get libraryMenuReplacePrompt;

  /// No description provided for @libraryMenuAddAsCharacter.
  ///
  /// In zh, this message translates to:
  /// **'添加为多角色卡片'**
  String get libraryMenuAddAsCharacter;

  /// No description provided for @libraryMenuCopyPrompt.
  ///
  /// In zh, this message translates to:
  /// **'复制提示词'**
  String get libraryMenuCopyPrompt;

  /// No description provided for @libraryMenuEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get libraryMenuEdit;

  /// No description provided for @libraryCardApply.
  ///
  /// In zh, this message translates to:
  /// **'应用到工作台'**
  String get libraryCardApply;

  /// No description provided for @libraryCardAddAsCharacterTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加为工作台多角色卡片'**
  String get libraryCardAddAsCharacterTooltip;

  /// No description provided for @libraryCardAddCharacter.
  ///
  /// In zh, this message translates to:
  /// **'+ 角色'**
  String get libraryCardAddCharacter;

  /// No description provided for @libraryCardNoPreview.
  ///
  /// In zh, this message translates to:
  /// **'无预览图'**
  String get libraryCardNoPreview;

  /// No description provided for @libraryEditCustomCategoryOption.
  ///
  /// In zh, this message translates to:
  /// **'自定义...'**
  String get libraryEditCustomCategoryOption;

  /// No description provided for @libraryEditPickImageFailed.
  ///
  /// In zh, this message translates to:
  /// **'选择图片失败: {error}'**
  String libraryEditPickImageFailed(String error);

  /// No description provided for @libraryEditAdoptedCanvasImage.
  ///
  /// In zh, this message translates to:
  /// **'已采用当前画板图像作为预览图'**
  String get libraryEditAdoptedCanvasImage;

  /// No description provided for @libraryEditCanvasNoImage.
  ///
  /// In zh, this message translates to:
  /// **'画板当前暂无生成的图像'**
  String get libraryEditCanvasNoImage;

  /// No description provided for @libraryEditWorkspacePromptEmpty.
  ///
  /// In zh, this message translates to:
  /// **'工作台主提示词为空'**
  String get libraryEditWorkspacePromptEmpty;

  /// No description provided for @libraryEditWorkspaceNegativeEmpty.
  ///
  /// In zh, this message translates to:
  /// **'工作台负面提示词为空'**
  String get libraryEditWorkspaceNegativeEmpty;

  /// No description provided for @libraryEditTitleEmpty.
  ///
  /// In zh, this message translates to:
  /// **'请输入词组合名称'**
  String get libraryEditTitleEmpty;

  /// No description provided for @libraryEditPromptEmpty.
  ///
  /// In zh, this message translates to:
  /// **'请输入主提示词内容'**
  String get libraryEditPromptEmpty;

  /// No description provided for @libraryEditUpdatedSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已更新词组合: {title}'**
  String libraryEditUpdatedSuccess(String title);

  /// No description provided for @libraryEditCreatedSuccess.
  ///
  /// In zh, this message translates to:
  /// **'已添加词组合: {title}'**
  String libraryEditCreatedSuccess(String title);

  /// No description provided for @libraryEditSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存失败: {error}'**
  String libraryEditSaveFailed(String error);

  /// No description provided for @libraryEditDialogTitleEdit.
  ///
  /// In zh, this message translates to:
  /// **'编辑词组合'**
  String get libraryEditDialogTitleEdit;

  /// No description provided for @libraryEditDialogTitleNew.
  ///
  /// In zh, this message translates to:
  /// **'新建词组合'**
  String get libraryEditDialogTitleNew;

  /// No description provided for @libraryEditFieldTitle.
  ///
  /// In zh, this message translates to:
  /// **'组合名称'**
  String get libraryEditFieldTitle;

  /// No description provided for @libraryEditFieldTitleHint.
  ///
  /// In zh, this message translates to:
  /// **'例如：赛博朋克猫耳少女 / 日系水彩插画'**
  String get libraryEditFieldTitleHint;

  /// No description provided for @libraryEditFieldCategory.
  ///
  /// In zh, this message translates to:
  /// **'分类'**
  String get libraryEditFieldCategory;

  /// No description provided for @libraryEditFieldCustomCategoryHint.
  ///
  /// In zh, this message translates to:
  /// **'输入自定义分类名称 (如：光影、视角)'**
  String get libraryEditFieldCustomCategoryHint;

  /// No description provided for @libraryEditFieldPrompt.
  ///
  /// In zh, this message translates to:
  /// **'主提示词'**
  String get libraryEditFieldPrompt;

  /// No description provided for @libraryEditFillFromPrompt.
  ///
  /// In zh, this message translates to:
  /// **'填入工作台主词'**
  String get libraryEditFillFromPrompt;

  /// No description provided for @libraryEditFieldPromptHint.
  ///
  /// In zh, this message translates to:
  /// **'输入正向提示词 (如: 1girl, hatsune miku, cybernetic...)'**
  String get libraryEditFieldPromptHint;

  /// No description provided for @libraryEditFieldNegative.
  ///
  /// In zh, this message translates to:
  /// **'负面提示词'**
  String get libraryEditFieldNegative;

  /// No description provided for @libraryEditCharacterOnlyBadge.
  ///
  /// In zh, this message translates to:
  /// **'仅角色分类可用'**
  String get libraryEditCharacterOnlyBadge;

  /// No description provided for @libraryEditFillFromNegative.
  ///
  /// In zh, this message translates to:
  /// **'填入工作台负向词'**
  String get libraryEditFillFromNegative;

  /// No description provided for @libraryEditFieldNegativeHint.
  ///
  /// In zh, this message translates to:
  /// **'角色专有负面词 (如: worst quality, bad hands, mutated...)'**
  String get libraryEditFieldNegativeHint;

  /// No description provided for @libraryEditFieldTags.
  ///
  /// In zh, this message translates to:
  /// **'检索标签 (Tags)'**
  String get libraryEditFieldTags;

  /// No description provided for @libraryEditFieldTagsHint.
  ///
  /// In zh, this message translates to:
  /// **'用于快速筛选，用逗号分隔 (例如：miku, 水彩, 二次元, 赛博)'**
  String get libraryEditFieldTagsHint;

  /// No description provided for @libraryEditSaveButton.
  ///
  /// In zh, this message translates to:
  /// **'保存修改'**
  String get libraryEditSaveButton;

  /// No description provided for @libraryEditCreateButton.
  ///
  /// In zh, this message translates to:
  /// **'创建词组合'**
  String get libraryEditCreateButton;

  /// No description provided for @libraryEditPosterTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置预览图'**
  String get libraryEditPosterTitle;

  /// No description provided for @libraryEditPickLocalImage.
  ///
  /// In zh, this message translates to:
  /// **'选择本地图片'**
  String get libraryEditPickLocalImage;

  /// No description provided for @libraryEditUseCanvasImage.
  ///
  /// In zh, this message translates to:
  /// **'使用画板当前图'**
  String get libraryEditUseCanvasImage;

  /// No description provided for @libraryEditRemovePreviewImage.
  ///
  /// In zh, this message translates to:
  /// **'移除预览图'**
  String get libraryEditRemovePreviewImage;

  /// No description provided for @tagAcAlias.
  ///
  /// In zh, this message translates to:
  /// **'别名: {alias}'**
  String tagAcAlias(String alias);

  /// No description provided for @tagBrowserTitle.
  ///
  /// In zh, this message translates to:
  /// **'Danbooru 标签灵感库'**
  String get tagBrowserTitle;

  /// No description provided for @tagBrowserSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'输入英文或中文搜索 14万+ Danbooru 标签...'**
  String get tagBrowserSearchHint;

  /// No description provided for @tagBrowserAddedTag.
  ///
  /// In zh, this message translates to:
  /// **'已添加标签: {tag}'**
  String tagBrowserAddedTag(String tag);

  /// No description provided for @tagBrowserAddedTagWithZh.
  ///
  /// In zh, this message translates to:
  /// **'已添加标签: {tag} ({zh})'**
  String tagBrowserAddedTagWithZh(String tag, String zh);

  /// No description provided for @tagBrowserNoMatchingTitle.
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配标签'**
  String get tagBrowserNoMatchingTitle;

  /// No description provided for @tagBrowserNoMatchingDesc.
  ///
  /// In zh, this message translates to:
  /// **'请尝试输入其他英文或中文关键词检索'**
  String get tagBrowserNoMatchingDesc;

  /// No description provided for @chatSessionManagementTooltip.
  ///
  /// In zh, this message translates to:
  /// **'会话管理'**
  String get chatSessionManagementTooltip;

  /// No description provided for @chatModelNoVisionNotice.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持图片输入，请先切换到多模态模型'**
  String get chatModelNoVisionNotice;

  /// No description provided for @chatMaxAttachmentsNotice.
  ///
  /// In zh, this message translates to:
  /// **'一次最多附带 {count} 张图片'**
  String chatMaxAttachmentsNotice(int count);

  /// No description provided for @chatImageParseFailedNotice.
  ///
  /// In zh, this message translates to:
  /// **'图片解析失败，请换一张图片重试'**
  String get chatImageParseFailedNotice;

  /// No description provided for @chatModelNoVisionBeforeSendNotice.
  ///
  /// In zh, this message translates to:
  /// **'当前模型不支持图片输入，发送前请切换到多模态模型'**
  String get chatModelNoVisionBeforeSendNotice;

  /// No description provided for @chatInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入绘画构思，或输入 /nai <词> 快速生图...'**
  String get chatInputHint;

  /// No description provided for @chatThinkingLabel.
  ///
  /// In zh, this message translates to:
  /// **'思考:'**
  String get chatThinkingLabel;

  /// No description provided for @chatThinkingEffortOff.
  ///
  /// In zh, this message translates to:
  /// **'关'**
  String get chatThinkingEffortOff;

  /// No description provided for @chatThinkingEffortLow.
  ///
  /// In zh, this message translates to:
  /// **'低'**
  String get chatThinkingEffortLow;

  /// No description provided for @chatThinkingEffortMedium.
  ///
  /// In zh, this message translates to:
  /// **'中'**
  String get chatThinkingEffortMedium;

  /// No description provided for @chatThinkingEffortHigh.
  ///
  /// In zh, this message translates to:
  /// **'高'**
  String get chatThinkingEffortHigh;

  /// No description provided for @chatSessionUsageEmpty.
  ///
  /// In zh, this message translates to:
  /// **'当前会话暂无 Token 用量记录'**
  String get chatSessionUsageEmpty;

  /// No description provided for @chatSessionUsageTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前会话 Token 用量'**
  String get chatSessionUsageTitle;

  /// No description provided for @chatSessionUsageDetail.
  ///
  /// In zh, this message translates to:
  /// **'输入 {input} · 输出 {output} · 总计 {total}'**
  String chatSessionUsageDetail(String input, String output, String total);

  /// No description provided for @chatSessionUsageCacheRead.
  ///
  /// In zh, this message translates to:
  /// **' · 缓存读 {cacheRead}'**
  String chatSessionUsageCacheRead(String cacheRead);

  /// No description provided for @chatSessionUsageCacheReadWithRate.
  ///
  /// In zh, this message translates to:
  /// **' · 缓存读 {cacheRead} ({rate}%)'**
  String chatSessionUsageCacheReadWithRate(String cacheRead, String rate);

  /// No description provided for @chatToolNoOutput.
  ///
  /// In zh, this message translates to:
  /// **'(无输出)'**
  String get chatToolNoOutput;

  /// No description provided for @chatToolResultSummary.
  ///
  /// In zh, this message translates to:
  /// **'{count} 行 · {firstLine}'**
  String chatToolResultSummary(int count, String firstLine);

  /// No description provided for @chatThinkingProgress.
  ///
  /// In zh, this message translates to:
  /// **'正在思考...'**
  String get chatThinkingProgress;

  /// No description provided for @chatConceiving.
  ///
  /// In zh, this message translates to:
  /// **'构思中...'**
  String get chatConceiving;

  /// No description provided for @chatRemoveAttachmentTooltip.
  ///
  /// In zh, this message translates to:
  /// **'移除附件'**
  String get chatRemoveAttachmentTooltip;

  /// No description provided for @chatAddAttachmentTooltip.
  ///
  /// In zh, this message translates to:
  /// **'添加附件'**
  String get chatAddAttachmentTooltip;

  /// No description provided for @rewindBackTooltip.
  ///
  /// In zh, this message translates to:
  /// **'返回对话 (ESC)'**
  String get rewindBackTooltip;

  /// No description provided for @rewindTitle.
  ///
  /// In zh, this message translates to:
  /// **'回溯历史时刻'**
  String get rewindTitle;

  /// No description provided for @rewindEscExit.
  ///
  /// In zh, this message translates to:
  /// **'ESC 退出'**
  String get rewindEscExit;

  /// No description provided for @rewindDescription.
  ///
  /// In zh, this message translates to:
  /// **'选择要回退到的对话时刻。确认后将撤销此时刻之后的所有修改与对话记录。'**
  String get rewindDescription;

  /// No description provided for @rewindEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'当前会话暂无历史对话轮次可回溯'**
  String get rewindEmptyTitle;

  /// No description provided for @rewindBackAction.
  ///
  /// In zh, this message translates to:
  /// **'返回对话'**
  String get rewindBackAction;

  /// No description provided for @rewindLatestBadge.
  ///
  /// In zh, this message translates to:
  /// **'(最新时刻)'**
  String get rewindLatestBadge;

  /// No description provided for @rewindSelectedTurn.
  ///
  /// In zh, this message translates to:
  /// **'已选择第 #{index} 轮对话'**
  String rewindSelectedTurn(int index);

  /// No description provided for @rewindSelectPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请在上方列表中选择要回退的轮次'**
  String get rewindSelectPrompt;

  /// No description provided for @rewindCancelButton.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get rewindCancelButton;

  /// No description provided for @rewindConfirmButton.
  ///
  /// In zh, this message translates to:
  /// **'回到此时刻'**
  String get rewindConfirmButton;

  /// No description provided for @sessionRenameTitle.
  ///
  /// In zh, this message translates to:
  /// **'重命名会话'**
  String get sessionRenameTitle;

  /// No description provided for @sessionRenameHint.
  ///
  /// In zh, this message translates to:
  /// **'请输入会话新名称...'**
  String get sessionRenameHint;

  /// No description provided for @sessionSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get sessionSave;

  /// No description provided for @sessionCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get sessionCancel;

  /// No description provided for @sessionDeleteTitle.
  ///
  /// In zh, this message translates to:
  /// **'删除会话'**
  String get sessionDeleteTitle;

  /// No description provided for @sessionDeleteConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确定要永久删除会话 \"{title}\" 吗？此操作无法撤销。'**
  String sessionDeleteConfirm(String title);

  /// No description provided for @sessionDeleteConfirmButton.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get sessionDeleteConfirmButton;

  /// No description provided for @sessionDateFormat.
  ///
  /// In zh, this message translates to:
  /// **'{month}月{day}日 {time}'**
  String sessionDateFormat(int month, int day, String time);

  /// No description provided for @sessionBackTooltip.
  ///
  /// In zh, this message translates to:
  /// **'返回对话'**
  String get sessionBackTooltip;

  /// No description provided for @sessionTitle.
  ///
  /// In zh, this message translates to:
  /// **'会话管理'**
  String get sessionTitle;

  /// No description provided for @sessionNew.
  ///
  /// In zh, this message translates to:
  /// **'新建会话'**
  String get sessionNew;

  /// No description provided for @sessionSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索历史会话...'**
  String get sessionSearchHint;

  /// No description provided for @sessionNoMatchingTitle.
  ///
  /// In zh, this message translates to:
  /// **'未找到匹配的会话'**
  String get sessionNoMatchingTitle;

  /// No description provided for @sessionEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'暂无历史会话记录'**
  String get sessionEmptyTitle;

  /// No description provided for @sessionCurrentBadge.
  ///
  /// In zh, this message translates to:
  /// **'当前'**
  String get sessionCurrentBadge;

  /// No description provided for @sessionRenameAction.
  ///
  /// In zh, this message translates to:
  /// **'重命名'**
  String get sessionRenameAction;

  /// No description provided for @sessionDeleteAction.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get sessionDeleteAction;

  /// No description provided for @sessionMessageCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条'**
  String sessionMessageCount(int count);

  /// No description provided for @askCardDefaultHeader.
  ///
  /// In zh, this message translates to:
  /// **'向用户提问'**
  String get askCardDefaultHeader;

  /// No description provided for @askCardPendingConfirm.
  ///
  /// In zh, this message translates to:
  /// **'待确认'**
  String get askCardPendingConfirm;

  /// No description provided for @askCardCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get askCardCancel;

  /// No description provided for @askCardSubmit.
  ///
  /// In zh, this message translates to:
  /// **'提交回答'**
  String get askCardSubmit;

  /// No description provided for @askCardCustomInputHint.
  ///
  /// In zh, this message translates to:
  /// **'输入自定义回答...'**
  String get askCardCustomInputHint;

  /// No description provided for @chatThinkingProcess.
  ///
  /// In zh, this message translates to:
  /// **'思考过程'**
  String get chatThinkingProcess;

  /// No description provided for @canvasBadgeUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'未保存'**
  String get canvasBadgeUnsaved;

  /// No description provided for @canvasBadgeUpscale.
  ///
  /// In zh, this message translates to:
  /// **'放大'**
  String get canvasBadgeUpscale;

  /// No description provided for @canvasBadgeInpaint.
  ///
  /// In zh, this message translates to:
  /// **'修复'**
  String get canvasBadgeInpaint;

  /// No description provided for @canvasBadgeAiEdit.
  ///
  /// In zh, this message translates to:
  /// **'AI 编辑'**
  String get canvasBadgeAiEdit;

  /// No description provided for @canvasBadgeImported.
  ///
  /// In zh, this message translates to:
  /// **'导入'**
  String get canvasBadgeImported;

  /// No description provided for @tagCatGeneral.
  ///
  /// In zh, this message translates to:
  /// **'通用'**
  String get tagCatGeneral;

  /// No description provided for @tagCatArtist.
  ///
  /// In zh, this message translates to:
  /// **'画师'**
  String get tagCatArtist;

  /// No description provided for @tagCatCopyright.
  ///
  /// In zh, this message translates to:
  /// **'作品'**
  String get tagCatCopyright;

  /// No description provided for @tagCatCharacter.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get tagCatCharacter;

  /// No description provided for @tagCatMeta.
  ///
  /// In zh, this message translates to:
  /// **'元数据'**
  String get tagCatMeta;

  /// No description provided for @llmProtocolOpenAiChat.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI 兼容 (/chat/completions)'**
  String get llmProtocolOpenAiChat;

  /// No description provided for @llmProtocolOpenAiResponses.
  ///
  /// In zh, this message translates to:
  /// **'Response (/responses)'**
  String get llmProtocolOpenAiResponses;

  /// No description provided for @llmProtocolAnthropicMessages.
  ///
  /// In zh, this message translates to:
  /// **'Message (/messages)'**
  String get llmProtocolAnthropicMessages;

  /// No description provided for @thinkingFormatAuto.
  ///
  /// In zh, this message translates to:
  /// **'自动 (按端点识别)'**
  String get thinkingFormatAuto;

  /// No description provided for @thinkingFormatOpenai.
  ///
  /// In zh, this message translates to:
  /// **'OpenAI (reasoning_effort)'**
  String get thinkingFormatOpenai;

  /// No description provided for @thinkingFormatDeepseek.
  ///
  /// In zh, this message translates to:
  /// **'DeepSeek (thinking)'**
  String get thinkingFormatDeepseek;

  /// No description provided for @thinkingFormatQwen.
  ///
  /// In zh, this message translates to:
  /// **'Qwen (enable_thinking)'**
  String get thinkingFormatQwen;

  /// No description provided for @thinkingFormatQwenChatTemplate.
  ///
  /// In zh, this message translates to:
  /// **'Qwen Chat Template'**
  String get thinkingFormatQwenChatTemplate;

  /// No description provided for @thinkingFormatZai.
  ///
  /// In zh, this message translates to:
  /// **'Z.ai (thinking + clear_thinking)'**
  String get thinkingFormatZai;

  /// No description provided for @thinkingFormatOpenrouter.
  ///
  /// In zh, this message translates to:
  /// **'OpenRouter (reasoning.effort)'**
  String get thinkingFormatOpenrouter;

  /// No description provided for @thinkingFormatTogether.
  ///
  /// In zh, this message translates to:
  /// **'Together (reasoning.enabled)'**
  String get thinkingFormatTogether;

  /// No description provided for @libraryCatCharacter.
  ///
  /// In zh, this message translates to:
  /// **'角色'**
  String get libraryCatCharacter;

  /// No description provided for @libraryCatStyle.
  ///
  /// In zh, this message translates to:
  /// **'风格'**
  String get libraryCatStyle;

  /// No description provided for @libraryCatAttire.
  ///
  /// In zh, this message translates to:
  /// **'服装'**
  String get libraryCatAttire;

  /// No description provided for @libraryCatComposition.
  ///
  /// In zh, this message translates to:
  /// **'构图'**
  String get libraryCatComposition;

  /// No description provided for @libraryCatEnvironment.
  ///
  /// In zh, this message translates to:
  /// **'环境'**
  String get libraryCatEnvironment;

  /// No description provided for @libraryCatEffect.
  ///
  /// In zh, this message translates to:
  /// **'特效'**
  String get libraryCatEffect;

  /// No description provided for @libraryCatOther.
  ///
  /// In zh, this message translates to:
  /// **'其他'**
  String get libraryCatOther;

  /// No description provided for @libraryCatCustom.
  ///
  /// In zh, this message translates to:
  /// **'自定义...'**
  String get libraryCatCustom;

  /// No description provided for @vmGenDoneUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'生图完成 (未保存，可点击画板右下角保存)'**
  String get vmGenDoneUnsaved;

  /// No description provided for @vmGenDoneSavedTo.
  ///
  /// In zh, this message translates to:
  /// **'生图完成，已保存在 {path}'**
  String vmGenDoneSavedTo(String path);

  /// No description provided for @vmGenLocalPath.
  ///
  /// In zh, this message translates to:
  /// **'本地'**
  String get vmGenLocalPath;

  /// No description provided for @vmGenNoSaveDir.
  ///
  /// In zh, this message translates to:
  /// **'未设置本地存储目录，请先在设置中配置保存路径。'**
  String get vmGenNoSaveDir;

  /// No description provided for @vmGenSaveFailedNoTarget.
  ///
  /// In zh, this message translates to:
  /// **'保存图片失败：未找到图片或存储目录不可写。'**
  String get vmGenSaveFailedNoTarget;

  /// No description provided for @vmGenSavedTo.
  ///
  /// In zh, this message translates to:
  /// **'已保存到 {path}'**
  String vmGenSavedTo(String path);

  /// No description provided for @vmGenSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'保存图片失败: {error}'**
  String vmGenSaveFailed(String error);

  /// No description provided for @vmGenAborted.
  ///
  /// In zh, this message translates to:
  /// **'已终止生成'**
  String get vmGenAborted;

  /// No description provided for @vmGenEmptyPrompt.
  ///
  /// In zh, this message translates to:
  /// **'提示词不能为空，请先在左侧或对话框中输入描述。'**
  String get vmGenEmptyPrompt;

  /// No description provided for @vmGenNoApiKey.
  ///
  /// In zh, this message translates to:
  /// **'未配置 NovelAI API Key，请点击右上角设置。'**
  String get vmGenNoApiKey;

  /// No description provided for @vmGenRequesting.
  ///
  /// In zh, this message translates to:
  /// **'正在请求 NovelAI 生图 ({width}x{height}, {steps}步)...'**
  String vmGenRequesting(int width, int height, int steps);

  /// No description provided for @vmGenFailed.
  ///
  /// In zh, this message translates to:
  /// **'生图失败: {error}'**
  String vmGenFailed(String error);

  /// No description provided for @vmUpscaleNoImage.
  ///
  /// In zh, this message translates to:
  /// **'当前画板中无图片可供放大。'**
  String get vmUpscaleNoImage;

  /// No description provided for @vmUpscaleNoApiKey.
  ///
  /// In zh, this message translates to:
  /// **'未配置 NovelAI API Key。'**
  String get vmUpscaleNoApiKey;

  /// No description provided for @vmUpscaleRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在执行图像超分放大...'**
  String get vmUpscaleRunning;

  /// No description provided for @vmUpscaleDoneUnsaved.
  ///
  /// In zh, this message translates to:
  /// **'放大完成 ({width}x{height}，未保存)'**
  String vmUpscaleDoneUnsaved(int width, int height);

  /// No description provided for @vmUpscaleDone.
  ///
  /// In zh, this message translates to:
  /// **'放大完成 ({width}x{height})'**
  String vmUpscaleDone(int width, int height);

  /// No description provided for @vmUpscaleFailed.
  ///
  /// In zh, this message translates to:
  /// **'放大失败: {error}'**
  String vmUpscaleFailed(String error);

  /// No description provided for @vmChatSlashNoImage.
  ///
  /// In zh, this message translates to:
  /// **'斜杠指令不支持附带图片，请直接发送对话消息'**
  String get vmChatSlashNoImage;

  /// No description provided for @vmChatSlashFailed.
  ///
  /// In zh, this message translates to:
  /// **'指令执行失败: {error}'**
  String vmChatSlashFailed(String error);

  /// No description provided for @vmChatRetryNotice.
  ///
  /// In zh, this message translates to:
  /// **'请求失败自动重试 ({attempt}/{max}): {reason} · {retry}'**
  String vmChatRetryNotice(int attempt, int max, String reason, String retry);

  /// No description provided for @vmChatRetryDelayed.
  ///
  /// In zh, this message translates to:
  /// **'{seconds} 秒后重试'**
  String vmChatRetryDelayed(int seconds);

  /// No description provided for @vmChatRetrySoon.
  ///
  /// In zh, this message translates to:
  /// **'即将重试'**
  String get vmChatRetrySoon;

  /// No description provided for @vmChatCompacted.
  ///
  /// In zh, this message translates to:
  /// **'上下文已自动压缩 ({before} → {after} tokens)，更早消息已摘要替换'**
  String vmChatCompacted(int before, int after);

  /// No description provided for @vmChatError.
  ///
  /// In zh, this message translates to:
  /// **'对话异常: {error}'**
  String vmChatError(String error);

  /// No description provided for @vmChatForceAborted.
  ///
  /// In zh, this message translates to:
  /// **'已强制终止当前生成'**
  String get vmChatForceAborted;

  /// No description provided for @vmCostNoOpusQuota.
  ///
  /// In zh, this message translates to:
  /// **'当前账号无 Opus 免费额度'**
  String get vmCostNoOpusQuota;

  /// No description provided for @vmCostEstimate.
  ///
  /// In zh, this message translates to:
  /// **'预计消耗 {cost} Anlas 点数'**
  String vmCostEstimate(int cost);

  /// No description provided for @vmCostWillCost.
  ///
  /// In zh, this message translates to:
  /// **'将消耗 Anlas 点数'**
  String get vmCostWillCost;

  /// No description provided for @vmCostTitle.
  ///
  /// In zh, this message translates to:
  /// **'点数消耗申请'**
  String get vmCostTitle;

  /// No description provided for @vmCostGenQuestion.
  ///
  /// In zh, this message translates to:
  /// **'本次生图参数（{reasons}）{cost}。是否确认生成？'**
  String vmCostGenQuestion(String reasons, String cost);

  /// No description provided for @vmCostGenConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认生成'**
  String get vmCostGenConfirm;

  /// No description provided for @vmCostGenConfirmDesc.
  ///
  /// In zh, this message translates to:
  /// **'使用当前参数直接生图并扣除点数'**
  String get vmCostGenConfirmDesc;

  /// No description provided for @vmCostGenCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消生图'**
  String get vmCostGenCancel;

  /// No description provided for @vmCostGenCancelDesc.
  ///
  /// In zh, this message translates to:
  /// **'取消本次生成，调整参数至免费区间'**
  String get vmCostGenCancelDesc;

  /// No description provided for @vmCostUpscaleQuestion.
  ///
  /// In zh, this message translates to:
  /// **'将输入尺寸 {width}x{height} 的图片执行官方超分放大，预计消耗 {cost} Anlas 点数。是否确认放大？'**
  String vmCostUpscaleQuestion(int width, int height, int cost);

  /// No description provided for @vmCostUpscaleConfirm.
  ///
  /// In zh, this message translates to:
  /// **'确认放大'**
  String get vmCostUpscaleConfirm;

  /// No description provided for @vmCostUpscaleConfirmDesc.
  ///
  /// In zh, this message translates to:
  /// **'执行官方超分并扣除点数'**
  String get vmCostUpscaleConfirmDesc;

  /// No description provided for @vmCostUpscaleCancel.
  ///
  /// In zh, this message translates to:
  /// **'取消放大'**
  String get vmCostUpscaleCancel;

  /// No description provided for @vmCostUpscaleCancelDesc.
  ///
  /// In zh, this message translates to:
  /// **'取消本次超分操作'**
  String get vmCostUpscaleCancelDesc;

  /// No description provided for @vmInpaintConverted.
  ///
  /// In zh, this message translates to:
  /// **'已将批注转换为修复选区'**
  String get vmInpaintConverted;

  /// No description provided for @vmInpaintSentToBoard.
  ///
  /// In zh, this message translates to:
  /// **'已发送到修复画板: {path}'**
  String vmInpaintSentToBoard(String path);

  /// No description provided for @vmInpaintNoImage.
  ///
  /// In zh, this message translates to:
  /// **'未找到可供修复的底图，请先选择或生成图片。'**
  String get vmInpaintNoImage;

  /// No description provided for @vmInpaintNoMask.
  ///
  /// In zh, this message translates to:
  /// **'请先在修复画板框选或用画笔绘制待修复区域。'**
  String get vmInpaintNoMask;

  /// No description provided for @vmInpaintNoApiKey.
  ///
  /// In zh, this message translates to:
  /// **'未配置 NovelAI API Key，请在设置中输入 Token。'**
  String get vmInpaintNoApiKey;

  /// No description provided for @vmInpaintRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在执行局部修复...'**
  String get vmInpaintRunning;

  /// No description provided for @vmInpaintDone.
  ///
  /// In zh, this message translates to:
  /// **'局部修复完成'**
  String get vmInpaintDone;

  /// No description provided for @vmInpaintFailed.
  ///
  /// In zh, this message translates to:
  /// **'修复失败: {error}'**
  String vmInpaintFailed(String error);

  /// No description provided for @vmAiEditNoImage.
  ///
  /// In zh, this message translates to:
  /// **'未找到可供编辑的底图，请先选择或生成图片。'**
  String get vmAiEditNoImage;

  /// No description provided for @vmAiEditNoModel.
  ///
  /// In zh, this message translates to:
  /// **'未配置 AI 整图编辑的绘图模型，请在设置 → Models 页选择绘图模型供应商与模型。'**
  String get vmAiEditNoModel;

  /// No description provided for @vmAiEditNoKey.
  ///
  /// In zh, this message translates to:
  /// **'绘图模型供应商「{provider}」未配置 API Key，请先在设置中填写。'**
  String vmAiEditNoKey(String provider);

  /// No description provided for @vmAiEditEmptyPrompt.
  ///
  /// In zh, this message translates to:
  /// **'请先输入 AI 整图编辑的修改指令 (修复页提示词设置，或关闭「复用主工作台正向词」后填写)。'**
  String get vmAiEditEmptyPrompt;

  /// No description provided for @vmAiEditRunning.
  ///
  /// In zh, this message translates to:
  /// **'AI 整图编辑中 (绘图模型处理中，通常需要数十秒)...'**
  String get vmAiEditRunning;

  /// No description provided for @vmAiEditDone.
  ///
  /// In zh, this message translates to:
  /// **'AI 整图编辑完成'**
  String get vmAiEditDone;

  /// No description provided for @vmAiEditFailed.
  ///
  /// In zh, this message translates to:
  /// **'AI 整图编辑失败: {error}'**
  String vmAiEditFailed(String error);

  /// No description provided for @vmSessionSwitched.
  ///
  /// In zh, this message translates to:
  /// **'已切换会话: {title}'**
  String vmSessionSwitched(String title);

  /// No description provided for @vmSessionCreated.
  ///
  /// In zh, this message translates to:
  /// **'已创建新会话'**
  String get vmSessionCreated;

  /// No description provided for @vmSessionDeleted.
  ///
  /// In zh, this message translates to:
  /// **'会话已删除'**
  String get vmSessionDeleted;

  /// No description provided for @vmRewindChatAndParams.
  ///
  /// In zh, this message translates to:
  /// **'已回到历史时刻，后续对话与参数修改已撤回'**
  String get vmRewindChatAndParams;

  /// No description provided for @vmRewindChatOnly.
  ///
  /// In zh, this message translates to:
  /// **'已回到历史时刻，后续对话与修改已撤回'**
  String get vmRewindChatOnly;

  /// No description provided for @vmHistoryDeleted.
  ///
  /// In zh, this message translates to:
  /// **'已从历史记录删除图片'**
  String get vmHistoryDeleted;

  /// No description provided for @vmHistoryCleared.
  ///
  /// In zh, this message translates to:
  /// **'已清空历史记录'**
  String get vmHistoryCleared;

  /// No description provided for @vmMetadataApplied.
  ///
  /// In zh, this message translates to:
  /// **'已应用图片元数据至工作台'**
  String get vmMetadataApplied;

  /// No description provided for @vmPresetSwitched.
  ///
  /// In zh, this message translates to:
  /// **'已切换为预设: 【{name}】\n{description}'**
  String vmPresetSwitched(String name, String description);

  /// No description provided for @vmCharacterDefaultName.
  ///
  /// In zh, this message translates to:
  /// **'角色 {index}'**
  String vmCharacterDefaultName(int index);

  /// No description provided for @vmNewCharacterName.
  ///
  /// In zh, this message translates to:
  /// **'新角色'**
  String get vmNewCharacterName;

  /// No description provided for @slashHelpHeader.
  ///
  /// In zh, this message translates to:
  /// **'快捷指令说明：'**
  String get slashHelpHeader;

  /// No description provided for @slashDescHelp.
  ///
  /// In zh, this message translates to:
  /// **'查看指令帮助列表'**
  String get slashDescHelp;

  /// No description provided for @slashDescParams.
  ///
  /// In zh, this message translates to:
  /// **'查看工作台当前生效的生图参数'**
  String get slashDescParams;

  /// No description provided for @slashDescPreset.
  ///
  /// In zh, this message translates to:
  /// **'切换当前 Agent 预设'**
  String get slashDescPreset;

  /// No description provided for @slashDescSkill.
  ///
  /// In zh, this message translates to:
  /// **'按需加载并执行专业技能'**
  String get slashDescSkill;

  /// No description provided for @slashDescNai.
  ///
  /// In zh, this message translates to:
  /// **'快速生成插画，支持 --landscape/--portrait/--square/--wallpaper 方向标志'**
  String get slashDescNai;

  /// No description provided for @slashDescUpscale.
  ///
  /// In zh, this message translates to:
  /// **'超分放大当前图片'**
  String get slashDescUpscale;

  /// No description provided for @slashDescTag.
  ///
  /// In zh, this message translates to:
  /// **'查询 Danbooru 官方标签联想'**
  String get slashDescTag;

  /// No description provided for @slashDescAccount.
  ///
  /// In zh, this message translates to:
  /// **'查询账号等级与 V5 专属体力池'**
  String get slashDescAccount;

  /// No description provided for @slashDescCompact.
  ///
  /// In zh, this message translates to:
  /// **'手动压缩对话上下文 (摘要替换更早消息，原始消息仍保留)'**
  String get slashDescCompact;

  /// No description provided for @slashDescNew.
  ///
  /// In zh, this message translates to:
  /// **'新建一个空白会话 (可附带标题)'**
  String get slashDescNew;

  /// No description provided for @slashDescUndo.
  ///
  /// In zh, this message translates to:
  /// **'撤销上一轮对话 (回复与参数修改一并回滚)'**
  String get slashDescUndo;

  /// No description provided for @slashDescRename.
  ///
  /// In zh, this message translates to:
  /// **'重命名当前会话'**
  String get slashDescRename;

  /// No description provided for @slashDescSessions.
  ///
  /// In zh, this message translates to:
  /// **'列出已保存的会话'**
  String get slashDescSessions;

  /// No description provided for @slashDescClear.
  ///
  /// In zh, this message translates to:
  /// **'清空对话历史'**
  String get slashDescClear;

  /// No description provided for @slashArgsName.
  ///
  /// In zh, this message translates to:
  /// **'<名称>'**
  String get slashArgsName;

  /// No description provided for @slashArgsPrompt.
  ///
  /// In zh, this message translates to:
  /// **'<提示词>'**
  String get slashArgsPrompt;

  /// No description provided for @slashArgsKeyword.
  ///
  /// In zh, this message translates to:
  /// **'<关键词>'**
  String get slashArgsKeyword;

  /// No description provided for @slashArgsTitle.
  ///
  /// In zh, this message translates to:
  /// **'<标题>'**
  String get slashArgsTitle;

  /// No description provided for @slashPresetListIntro.
  ///
  /// In zh, this message translates to:
  /// **'可用预设列表：'**
  String get slashPresetListIntro;

  /// No description provided for @slashPresetUsage.
  ///
  /// In zh, this message translates to:
  /// **'用法: /preset <预设名称或ID>'**
  String get slashPresetUsage;

  /// No description provided for @slashPresetNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到预设 \"{query}\"，输入 /preset 查看可用预设。'**
  String slashPresetNotFound(String query);

  /// No description provided for @slashSkillListIntro.
  ///
  /// In zh, this message translates to:
  /// **'可用技能列表：'**
  String get slashSkillListIntro;

  /// No description provided for @slashSkillUsage.
  ///
  /// In zh, this message translates to:
  /// **'用法: /skill <技能名称或ID>'**
  String get slashSkillUsage;

  /// No description provided for @slashSkillLoaded.
  ///
  /// In zh, this message translates to:
  /// **'【Skill 已载入】{name}\n{description}\n\n{systemPrompt}'**
  String slashSkillLoaded(String name, String description, String systemPrompt);

  /// No description provided for @slashSkillNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到技能 \"{query}\"，输入 /skill 查看可用技能。'**
  String slashSkillNotFound(String query);

  /// No description provided for @slashCompactNoProvider.
  ///
  /// In zh, this message translates to:
  /// **'未配置 LLM 提供商，无法压缩上下文。'**
  String get slashCompactNoProvider;

  /// No description provided for @slashCompactEmpty.
  ///
  /// In zh, this message translates to:
  /// **'当前对话为空，无需压缩上下文。'**
  String get slashCompactEmpty;

  /// No description provided for @slashCompactRunning.
  ///
  /// In zh, this message translates to:
  /// **'正在压缩对话上下文...'**
  String get slashCompactRunning;

  /// No description provided for @slashCompactNothing.
  ///
  /// In zh, this message translates to:
  /// **'上下文没有可压缩的内容 (需要至少两轮对话)，或摘要生成失败。'**
  String get slashCompactNothing;

  /// No description provided for @slashCompactDone.
  ///
  /// In zh, this message translates to:
  /// **'上下文压缩完成 ({before} → {after} tokens)。更早的消息已替换为以下摘要，原始消息仍保留在对话流与会话记录中：\n\n{summary}'**
  String slashCompactDone(int before, int after, String summary);

  /// No description provided for @slashNewNoTitle.
  ///
  /// In zh, this message translates to:
  /// **'已创建新会话，开始新的对话吧。'**
  String get slashNewNoTitle;

  /// No description provided for @slashNewWithTitle.
  ///
  /// In zh, this message translates to:
  /// **'已创建新会话: {title}'**
  String slashNewWithTitle(String title);

  /// No description provided for @slashUndoNothing.
  ///
  /// In zh, this message translates to:
  /// **'没有可撤销的上一轮对话 (首轮之前的消息不存在)。'**
  String get slashUndoNothing;

  /// No description provided for @slashRenameUsage.
  ///
  /// In zh, this message translates to:
  /// **'用法: /rename <新标题>'**
  String get slashRenameUsage;

  /// No description provided for @slashRenameNoSession.
  ///
  /// In zh, this message translates to:
  /// **'当前没有活跃会话，无法重命名。'**
  String get slashRenameNoSession;

  /// No description provided for @slashRenamed.
  ///
  /// In zh, this message translates to:
  /// **'会话已重命名为 \"{title}\"'**
  String slashRenamed(String title);

  /// No description provided for @slashSessionsEmpty.
  ///
  /// In zh, this message translates to:
  /// **'暂无已保存的会话。'**
  String get slashSessionsEmpty;

  /// No description provided for @slashSessionsHeader.
  ///
  /// In zh, this message translates to:
  /// **'已保存的会话 (共 {count} 个，按最近使用排序)：'**
  String slashSessionsHeader(int count);

  /// No description provided for @slashSessionMsgCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 条消息'**
  String slashSessionMsgCount(int count);

  /// No description provided for @slashSessionCurrentMarker.
  ///
  /// In zh, this message translates to:
  /// **' [当前]'**
  String get slashSessionCurrentMarker;

  /// No description provided for @slashSessionsMore.
  ///
  /// In zh, this message translates to:
  /// **'…… 其余 {count} 个会话请打开会话管理视图查看。'**
  String slashSessionsMore(int count);

  /// No description provided for @slashAccountTitle.
  ///
  /// In zh, this message translates to:
  /// **'NovelAI 账号状态：'**
  String get slashAccountTitle;

  /// No description provided for @slashAccountTier.
  ///
  /// In zh, this message translates to:
  /// **'• 订阅等级: {tier}'**
  String slashAccountTier(String tier);

  /// No description provided for @slashAccountStamina.
  ///
  /// In zh, this message translates to:
  /// **'• V5 专属体力池: {percent}%'**
  String slashAccountStamina(String percent);

  /// No description provided for @slashAccountAnlas.
  ///
  /// In zh, this message translates to:
  /// **'• 可用 Anlas: {total} (赠送: {fixed}, 购买: {purchased})'**
  String slashAccountAnlas(int total, int fixed, int purchased);

  /// No description provided for @slashAccountQuotaExhausted.
  ///
  /// In zh, this message translates to:
  /// **'• V5 体力配额已透支，生图将按正常价消耗 Anlas'**
  String get slashAccountQuotaExhausted;

  /// No description provided for @slashAccountFailed.
  ///
  /// In zh, this message translates to:
  /// **'查询账号信息失败，请检查 API Key 设置。'**
  String get slashAccountFailed;

  /// No description provided for @slashTagUsage.
  ///
  /// In zh, this message translates to:
  /// **'用法: /tag <关键词> (例如: /tag silver)'**
  String get slashTagUsage;

  /// No description provided for @slashTagNotFound.
  ///
  /// In zh, this message translates to:
  /// **'未找到与 \"{query}\" 相关的标签。'**
  String slashTagNotFound(String query);

  /// No description provided for @slashTagSuggestions.
  ///
  /// In zh, this message translates to:
  /// **'标签联想建议 (\"{query}\"):\n{list}'**
  String slashTagSuggestions(String query, String list);

  /// No description provided for @slashUpscaleDone.
  ///
  /// In zh, this message translates to:
  /// **'已执行超分放大'**
  String get slashUpscaleDone;

  /// No description provided for @slashNaiUsage.
  ///
  /// In zh, this message translates to:
  /// **'用法: /nai <提示词>'**
  String get slashNaiUsage;

  /// No description provided for @slashNaiDone.
  ///
  /// In zh, this message translates to:
  /// **'插画已生成: {path}\n尺寸: {width}x{height}, 种子: {seed}'**
  String slashNaiDone(String path, int width, int height, int seed);

  /// No description provided for @slashNaiDoneFallback.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get slashNaiDoneFallback;

  /// No description provided for @slashUnknown.
  ///
  /// In zh, this message translates to:
  /// **'未知指令 \"{cmd}\"，输入 /help 查看可用指令。'**
  String slashUnknown(String cmd);

  /// No description provided for @vmSlashParamsTitle.
  ///
  /// In zh, this message translates to:
  /// **'工作台当前生图参数：'**
  String get vmSlashParamsTitle;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
