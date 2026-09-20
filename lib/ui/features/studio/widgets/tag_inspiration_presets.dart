import 'package:flutter/material.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../data/models/nai_special_tags.dart';

/// 预设灵感分类与精选标签 (标签灵感库数据源)
class TagInspirationGroup {
  final String title;
  final IconData icon;
  final List<(String tag, String zh)> tags;

  const TagInspirationGroup(this.title, this.icon, this.tags);

  String localizedTitle(AppLocalizations l10n) {
    final raw = title.startsWith('NAI·') ? title.substring(4) : title;
    final label = switch (raw) {
      '画质' => l10n.tagGroupQuality,
      '美学' => l10n.tagGroupAesthetic,
      '复杂度' => l10n.tagGroupComplexity,
      '年代' => l10n.tagGroupYear,
      '数据集' => l10n.tagGroupDataset,
      '透明通道' => l10n.tagGroupAlpha,
      '改名标签' => l10n.tagGroupRenamed,
      '其他' => l10n.tagGroupOther,
      '画质与美学' => l10n.tagGroupQualityAesthetics,
      '镜头与构图' => l10n.tagGroupCameraComposition,
      '光影与氛围' => l10n.tagGroupLighting,
      '表情与神情' => l10n.tagGroupExpression,
      '发型与发色' => l10n.tagGroupHair,
      '服饰与装扮' => l10n.tagGroupClothing,
      '动作与姿势' => l10n.tagGroupPose,
      '背景与场景' => l10n.tagGroupBackground,
      _ => title,
    };
    return title.startsWith('NAI·') ? 'NAI·$label' : label;
  }
}

const List<TagInspirationGroup> kTagInspirationPresets = [
  TagInspirationGroup('画质与美学', Icons.auto_awesome, [
    ('masterpiece', '杰作'),
    ('best quality', '顶级画质'),
    ('very aesthetic', '极富美感'),
    ('highres', '高分辨率'),
    ('absurdres', '超高分辨率'),
    ('ultra-detailed', '极致细节'),
    ('sharp focus', '清晰聚焦'),
  ]),
  TagInspirationGroup('镜头与构图', Icons.camera_alt_outlined, [
    ('portrait', '肖像特写'),
    ('upper body', '上半身'),
    ('cowboy shot', '七分身 (牛仔镜头)'),
    ('full body', '全身'),
    ('close-up', '面部特写'),
    ('dynamic angle', '动态构图'),
    ('from below', '仰视'),
    ('from above', '俯视'),
  ]),
  TagInspirationGroup('光影与氛围', Icons.wb_sunny_outlined, [
    ('cinematic lighting', '电影级光影'),
    ('dramatic shadows', '强烈明暗对比'),
    ('soft light', '柔和漫射光'),
    ('sunlight', '阳光透过'),
    ('volumetric lighting', '丁达尔光束'),
    ('backlighting', '逆光剪影'),
    ('glowing', '发光特效'),
    ('lens flare', '镜头光晕'),
  ]),
  TagInspirationGroup('表情与神情', Icons.sentiment_satisfied_alt, [
    ('smile', '微笑'),
    ('blush', '脸红害羞'),
    ('open mouth', '微微张嘴'),
    ('looking at viewer', '注视镜头'),
    ('wink', '单眼眨眼'),
    ('embarrassed', '害羞局促'),
    ('gentle smile', '温柔微笑'),
    ('smug', '得意轻笑'),
  ]),
  TagInspirationGroup('发型与发色', Icons.face, [
    ('long hair', '长发'),
    ('short hair', '短发'),
    ('twintails', '双马尾'),
    ('ponytail', '单马尾'),
    ('ahoge', '呆毛'),
    ('blonde hair', '金发'),
    ('black hair', '黑发'),
    ('silver hair', '银白发'),
    ('brown hair', '棕发'),
    ('blue hair', '蓝发'),
    ('pink hair', '粉发'),
  ]),
  TagInspirationGroup('服饰与装扮', Icons.checkroom_outlined, [
    ('school uniform', '水手制服'),
    ('sailor suit', '水手服'),
    ('dress', '连衣裙'),
    ('skirt', '短裙'),
    ('shirt', '衬衫'),
    ('hoodie', '连帽衫'),
    ('maid', '女仆装'),
    ('kimono', '和服'),
    ('ribbon', '缎带蝴蝶结'),
    ('gloves', '手套'),
    ('thighhighs', '过膝袜'),
  ]),
  TagInspirationGroup('动作与姿势', Icons.directions_run, [
    ('standing', '站立'),
    ('sitting', '坐姿'),
    ('lying', '躺卧'),
    ('hand on hip', '单手叉腰'),
    ('arms behind back', '双手背后'),
    ('peace sign', '比剪刀手'),
    ('holding', '手持物品'),
    ('walking', '漫步行走'),
  ]),
  TagInspirationGroup('背景与场景', Icons.landscape_outlined, [
    ('simple background', '简约背景'),
    ('white background', '纯白背景'),
    ('scenery', '唯美风景'),
    ('classroom', '学校教室'),
    ('bedroom', '温馨卧室'),
    ('outdoors', '户外自然'),
    ('night sky', '璀璨夜空'),
    ('cherry blossoms', '落樱纷飞'),
    ('cityscape', '都市街景'),
  ]),
];

/// 官方专属标签分组图标 (数据层保持 Flutter 无关，图标在 UI 层映射)
const Map<NaiSpecialTagGroup, IconData> _kNaiGroupIcons = {
  NaiSpecialTagGroup.quality: Icons.workspace_premium_outlined,
  NaiSpecialTagGroup.aesthetic: Icons.auto_awesome_outlined,
  NaiSpecialTagGroup.complexity: Icons.layers_outlined,
  NaiSpecialTagGroup.year: Icons.calendar_month_outlined,
  NaiSpecialTagGroup.dataset: Icons.dataset_outlined,
  NaiSpecialTagGroup.alpha: Icons.opacity_outlined,
  NaiSpecialTagGroup.renamed: Icons.swap_horiz_outlined,
  NaiSpecialTagGroup.other: Icons.category_outlined,
};

/// 标签灵感库实际渲染的分组清单
///
/// NovelAI 官方专属标签按文档分节置顶 (Danbooru 词库完全不含这些词条)，
/// 其后才是人工维护的通用灵感分类。
final List<TagInspirationGroup> kTagInspirationGroups = [
  for (final group in NaiSpecialTagGroup.values)
    TagInspirationGroup(
      'NAI·${group.label}',
      _kNaiGroupIcons[group] ?? Icons.auto_awesome_outlined,
      [
        for (final t
            in kNaiSpecialTagsByGroup[group] ?? const <NaiSpecialTag>[])
          // 灵感库无别名胶囊，改用 galleryZh 补齐改名标签的旧写法说明
          (t.tag, t.galleryZh),
      ],
    ),
  ...kTagInspirationPresets,
];
