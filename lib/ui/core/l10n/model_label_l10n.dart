/// 数据模型枚举 → 本地化展示文案的 UI 扩展层 (阶段 4C 数据层文案解耦)。
///
/// 数据层 (lib/data/models) 只保留纯结构化枚举/常量，不再携带面向用户的
/// 中文字符串；本文件集中接管所有「模型枚举 → 界面文案」的映射，供
/// Widget 与 ViewModel 共用。持久化数据域字符串 (如词组合自定义分类名、
/// 后端原始错误、Agent prompt 文本) 一律原样透传，不做翻译。
library;

import 'package:flutter/widgets.dart';

import '../../../l10n/app_localizations.dart';
import '../../../data/models/llm_models.dart';
import '../../../data/models/nai_image_result.dart';
import '../../../data/models/prompt_library_models.dart';
import '../../../data/models/tag_models.dart';
import '../context_l10n.dart';

/// 历史缩略图角标文案 (未保存/放大/修复/AI 编辑/导入)，普通生成图返回 null。
String? historyBadgeLabelOf(
  AppLocalizations l10n,
  NaiImageProvenance? provenance,
) => switch (provenance) {
  null => null,
  NaiImageProvenance.unsaved => l10n.canvasBadgeUnsaved,
  NaiImageProvenance.upscaled => l10n.canvasBadgeUpscale,
  NaiImageProvenance.inpainted => l10n.canvasBadgeInpaint,
  NaiImageProvenance.aiEdited => l10n.canvasBadgeAiEdit,
  NaiImageProvenance.imported => l10n.canvasBadgeImported,
};

/// Danbooru 标签分类胶囊文案 (通用/画师/作品/角色/元数据)。
String tagCategoryLabelOf(
  AppLocalizations l10n,
  DanbooruTagCategory category,
) => switch (category) {
  DanbooruTagCategory.general => l10n.tagCatGeneral,
  DanbooruTagCategory.artist => l10n.tagCatArtist,
  DanbooruTagCategory.copyright => l10n.tagCatCopyright,
  DanbooruTagCategory.character => l10n.tagCatCharacter,
  DanbooruTagCategory.meta => l10n.tagCatMeta,
};

/// LLM 接口协议展示名。
String llmProtocolLabelOf(AppLocalizations l10n, LlmProtocol protocol) =>
    switch (protocol) {
      LlmProtocol.openAiChat => l10n.llmProtocolOpenAiChat,
      LlmProtocol.openAiResponses => l10n.llmProtocolOpenAiResponses,
      LlmProtocol.anthropicMessages => l10n.llmProtocolAnthropicMessages,
    };

/// 思考参数请求格式展示名。
String thinkingParamFormatLabelOf(
  AppLocalizations l10n,
  ThinkingParamFormat format,
) => switch (format) {
  ThinkingParamFormat.auto => l10n.thinkingFormatAuto,
  ThinkingParamFormat.openai => l10n.thinkingFormatOpenai,
  ThinkingParamFormat.deepseek => l10n.thinkingFormatDeepseek,
  ThinkingParamFormat.qwen => l10n.thinkingFormatQwen,
  ThinkingParamFormat.qwenChatTemplate => l10n.thinkingFormatQwenChatTemplate,
  ThinkingParamFormat.zai => l10n.thinkingFormatZai,
  ThinkingParamFormat.openrouter => l10n.thinkingFormatOpenrouter,
  ThinkingParamFormat.together => l10n.thinkingFormatTogether,
};

/// 词组合预设分类展示名。
///
/// 分类名是持久化数据域字符串 (默认分类以中文常量 [PromptComboCategories] 存档)，
/// 这里仅对已知默认分类与「全部 / 自定义」哨兵做本地化映射，
/// 用户自定义分类名原样透传。
String comboCategoryLabelOf(AppLocalizations l10n, String category) {
  final normalized = category.trim();
  return switch (normalized) {
    '全部' => l10n.libraryCategoryAll,
    PromptComboCategories.character => l10n.libraryCatCharacter,
    PromptComboCategories.style => l10n.libraryCatStyle,
    PromptComboCategories.attire => l10n.libraryCatAttire,
    PromptComboCategories.composition => l10n.libraryCatComposition,
    PromptComboCategories.environment => l10n.libraryCatEnvironment,
    PromptComboCategories.effect => l10n.libraryCatEffect,
    PromptComboCategories.other => l10n.libraryCatOther,
    _ => category,
  };
}

/// 便捷扩展：直接从 BuildContext 取各枚举的本地化文案。
extension ModelLabelL10nContext on BuildContext {
  /// 历史角标文案
  String? historyBadgeLabel(NaiImageProvenance? provenance) =>
      historyBadgeLabelOf(l10n, provenance);

  /// 标签分类文案
  String tagCategoryLabel(DanbooruTagCategory category) =>
      tagCategoryLabelOf(l10n, category);

  /// LLM 协议文案
  String llmProtocolLabel(LlmProtocol protocol) =>
      llmProtocolLabelOf(l10n, protocol);

  /// 思考参数格式文案
  String thinkingParamFormatLabel(ThinkingParamFormat format) =>
      thinkingParamFormatLabelOf(l10n, format);

  /// 词组合分类文案
  String comboCategoryLabel(String category) =>
      comboCategoryLabelOf(l10n, category);
}
