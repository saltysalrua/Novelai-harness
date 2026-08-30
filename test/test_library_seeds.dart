import 'package:novelai_harness/data/models/prompt_library_models.dart';

/// 测试共用的词库种子条目 (复制自旧内置预设内容，供需要词库数据的测试显式播种)。
///
/// 词库服务不再内置任何默认条目，需要「初音未来 / 水彩风」等数据的测试
/// 必须在 setUp 里显式调用 saveEntries 播种。
List<PromptComboEntry> seedLibraryEntries() {
  final now = DateTime(2026, 1, 1);
  return [
    PromptComboEntry(
      id: 'seed_char_miku',
      title: '初音未来 (Hatsune Miku)',
      category: PromptComboCategories.character,
      prompt:
          '1girl, hatsune miku, vocaloid, aqua eyes, aqua hair, very long hair, twin tails, hair ornament, black sleeveless shirt, teal necktie, pleated skirt, detached sleeves, futuristic headset, masterpiece, best quality',
      negativePrompt:
          'worst quality, lowres, bad anatomy, bad hands, extra digits, missing fingers',
      createdAt: now,
      updatedAt: now,
      tags: ['vocaloid', 'miku', 'twintails', 'anime'],
    ),
    PromptComboEntry(
      id: 'seed_style_watercolor',
      title: '日系二次元水彩风',
      category: PromptComboCategories.style,
      prompt:
          'watercolor style, delicate paint splashes, soft pastel colors, loose edges, paper texture, airy atmosphere, artistic illustration, semi-transparent glaze',
      createdAt: now,
      updatedAt: now,
      tags: ['watercolor', 'artistic', 'pastel'],
    ),
  ];
}