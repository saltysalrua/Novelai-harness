import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/prompt_library_models.dart';
import '../models/tag_models.dart';

/// 词组合预设库持久化与管理服务
class PromptLibraryService {
  static final PromptLibraryService instance = PromptLibraryService._();

  PromptLibraryService._();
  factory PromptLibraryService() => instance;

  String? _customStorageDir;
  List<PromptComboEntry>? _cachedEntries;

  /// 获取当前已加载的词库条目内存缓存 (未显式加载时回退内置列表)
  List<PromptComboEntry> get cachedEntries => _cachedEntries ?? builtinPresets;

  /// 用于测试或自定义设置的存储根目录
  void setCustomStorageDirectory(String? dir) {
    _customStorageDir = dir;
  }

  /// 获取存储词库数据的目标文件
  Future<File> _getDataFile() async {
    final baseDir = _customStorageDir ?? (await _getAppSupportDir()).path;
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(baseDir, 'prompt_library.json'));
  }

  /// 获取本地预览图存储目录
  Future<Directory> _getPreviewDir() async {
    final baseDir = _customStorageDir ?? (await _getAppSupportDir()).path;
    final dir = Directory(p.join(baseDir, 'prompt_previews'));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return dir;
  }

  Future<Directory> _getAppSupportDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return Directory.current;
    }
  }

  /// 内置开箱即用高质量预设种子数据
  List<PromptComboEntry> get builtinPresets {
    final now = DateTime(2026, 1, 1);
    return [
      // 角色
      PromptComboEntry(
        id: 'builtin_char_miku',
        title: '初音未来 (Hatsune Miku)',
        category: PromptComboCategories.character,
        prompt:
            '1girl, hatsune miku, vocaloid, aqua eyes, aqua hair, very long hair, twin tails, hair ornament, black sleeveless shirt, teal necktie, pleated skirt, detached sleeves, futuristic headset, masterpiece, best quality',
        negativePrompt:
            'worst quality, lowres, bad anatomy, bad hands, extra digits, missing fingers',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['vocaloid', 'miku', 'twintails', 'anime'],
      ),
      PromptComboEntry(
        id: 'builtin_char_cyber_cat',
        title: '赛博朋克猫耳少女',
        category: PromptComboCategories.character,
        prompt:
            '1girl, solo, cat ears, cybernetics, glowing neon accents, futuristic techwear jacket, high ponytail, dynamic lighting, rainy city reflection, depth of field, masterpiece',
        negativePrompt:
            'ugly, deformed, disfigured, extra limbs, bad proportions, distorted face',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['cyberpunk', 'cat_ears', 'techwear', 'futuristic'],
      ),
      PromptComboEntry(
        id: 'builtin_char_magical_girl',
        title: '星空魔法少女',
        category: PromptComboCategories.character,
        prompt:
            '1girl, magical girl, ethereal starry dress, glowing magic wand, floating ribbons, sparkles, cosmic aura, twilight sky, dreamy soft lighting, floating hair',
        negativePrompt:
            'low quality, text, watermark, mutated limbs, bad hands, dark gloomy',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['magical_girl', 'stars', 'wand', 'ethereal'],
      ),

      // 风格
      PromptComboEntry(
        id: 'builtin_style_watercolor',
        title: '日系二次元水彩风',
        category: PromptComboCategories.style,
        prompt:
            'watercolor style, delicate paint splashes, soft pastel colors, loose edges, paper texture, airy atmosphere, artistic illustration, semi-transparent glaze',
        negativePrompt: '',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['watercolor', 'artistic', 'pastel'],
      ),
      PromptComboEntry(
        id: 'builtin_style_80s_retro',
        title: '80年代赛璐璐复古风',
        category: PromptComboCategories.style,
        prompt:
            'retro anime style, 1980s cel animation, grainy film texture, vintage aesthetic, bold outlines, saturated colors, classic anime look, nostalgic atmosphere',
        negativePrompt: '',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['retro', 'vintage', '80s', 'cel_animation'],
      ),
      PromptComboEntry(
        id: 'builtin_style_cinematic',
        title: '电影级厚涂光影',
        category: PromptComboCategories.style,
        prompt:
            'cinematic lighting, dramatic rim light, volumetric dust particles, highly detailed digital painting, rich color depth, high contrast, atmospheric perspective',
        negativePrompt: '',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['cinematic', 'lighting', 'masterpiece'],
      ),

      // 服装
      PromptComboEntry(
        id: 'builtin_attire_techwear',
        title: '机能战术机动服',
        category: PromptComboCategories.attire,
        prompt:
            'tactical techwear, tactical harness, oversized hooded jacket, cargo straps, utility belts, high-collar, futuristic accessories, sleek aesthetic',
        negativePrompt: '',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['techwear', 'tactical', 'fashion'],
      ),
      PromptComboEntry(
        id: 'builtin_attire_kimono',
        title: '华丽传统和服',
        category: PromptComboCategories.attire,
        prompt:
            'traditional ornate kimono, intricate gold floral embroidery, wide flowing sleeves, layered obi sash, decorative floral hairpins, elegant draped fabric',
        negativePrompt: '',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['kimono', 'traditional', 'japan'],
      ),

      // 构图
      PromptComboEntry(
        id: 'builtin_comp_low_angle',
        title: '动态极低视角仰拍',
        category: PromptComboCategories.composition,
        prompt:
            'dynamic low angle, dramatic upward perspective, wide foreshortening, action pose, floating particles, strong vertical depth, powerful composition',
        negativePrompt: '',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['low_angle', 'dynamic', 'action'],
      ),
      PromptComboEntry(
        id: 'builtin_comp_fisheye',
        title: '超广角鱼眼镜头',
        category: PromptComboCategories.composition,
        prompt:
            'fisheye lens view, ultra-wide angle, curved horizon, exaggerated perspective, expansive background environment, barrel distortion',
        negativePrompt: '',
        createdAt: now,
        updatedAt: now,
        isBuiltin: true,
        tags: ['fisheye', 'wide_angle', 'perspective'],
      ),
    ];
  }

  /// 加载所有词组合条目 (首次为空时自动初始化内置预设)
  Future<List<PromptComboEntry>> loadEntries() async {
    final file = await _getDataFile();
    if (!file.existsSync()) {
      final initialList = builtinPresets;
      await saveEntries(initialList);
      _cachedEntries = initialList;
      return initialList;
    }

    try {
      final text = await file.readAsString();
      final decoded = jsonDecode(text);
      if (decoded is List) {
        final list = <PromptComboEntry>[];
        for (final item in decoded) {
          if (item is Map<String, dynamic>) {
            try {
              list.add(PromptComboEntry.fromJson(item));
            } catch (_) {}
          }
        }
        if (list.isEmpty) {
          final initialList = builtinPresets;
          await saveEntries(initialList);
          _cachedEntries = initialList;
          return initialList;
        }
        _cachedEntries = list;
        return list;
      }
    } catch (_) {}

    _cachedEntries = builtinPresets;
    return builtinPresets;
  }

  /// 持久化保存词组合列表
  Future<void> saveEntries(List<PromptComboEntry> entries) async {
    _cachedEntries = List.from(entries);
    final file = await _getDataFile();
    final jsonList = entries.map((e) => e.toJson()).toList();
    await file.writeAsString(jsonEncode(jsonList), flush: true);
  }

  /// 搜索词库中的所有词组合条目 (含角色与非角色) 并转换为自动补全建议 (TagSuggestion)
  /// 角色分类同样只提取主提示词作为 insertText，使用同等标准打分参与公平排序
  List<TagSuggestion> searchAsSuggestions(String query, {int limit = 5}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final entries = cachedEntries;
    if (entries.isEmpty) return const [];

    final results = <TagSuggestion>[];

    for (final entry in entries) {
      final titleLower = entry.title.toLowerCase();
      final categoryLower = entry.category.toLowerCase();

      double score = 0.0;
      if (titleLower == q) {
        score = 1500.0; // 完全精确匹配 (与 Danbooru 精确匹配同分)
      } else if (titleLower.startsWith(q)) {
        score = 1000.0; // 名称前缀匹配
      } else if (entry.tags.any((t) => t.toLowerCase() == q)) {
        score = 900.0; // 标签完全匹配
      } else if (entry.tags.any((t) => t.toLowerCase().startsWith(q)) &&
          q.length >= 3) {
        score = 600.0; // 标签前缀匹配
      } else if (titleLower.contains(q) && q.length >= 2) {
        score = 450.0; // 名称包含匹配
      } else if (categoryLower.startsWith(q) && q.length >= 2) {
        score = 400.0; // 分类前缀匹配
      }

      if (score > 0) {
        // 辅助描述：若有 tags 则展示 tags，否则展示分类与部分提示词
        final desc = entry.tags.isNotEmpty
            ? entry.tags.join(', ')
            : '${entry.category} · ${entry.prompt}';

        results.add(
          TagSuggestion(
            tag: entry.title,
            category: entry.isCharacter
                ? DanbooruTagCategory.character
                : DanbooruTagCategory.meta,
            customCategoryLabel: entry.category,
            translation: desc,
            insertText: entry.prompt, // 角色分类同样只添加主提示词
            isPromptCombo: true,
            score: score,
            postCount: 0,
          ),
        );
      }
    }

    results.sort((a, b) => b.score.compareTo(a.score));
    if (results.length > limit) {
      return results.sublist(0, limit);
    }
    return results;
  }

  /// 添加词组合条目
  Future<PromptComboEntry> addEntry(PromptComboEntry entry) async {
    final list = await loadEntries();
    list.insert(0, entry);
    await saveEntries(list);
    return entry;
  }

  /// 仅当预览图位于本地托管预览目录内才删除 (导入的外部 JSON 可能携带任意路径，
  /// 不能信任其中的 previewImagePath 指向的文件)
  Future<void> _deleteManagedPreviewFile(String? path) async {
    if (path == null || path.isEmpty) return;
    try {
      final previewDir = await _getPreviewDir();
      if (!p.isWithin(previewDir.path, path)) return;
      final imgFile = File(path);
      if (imgFile.existsSync()) {
        imgFile.deleteSync();
      }
    } catch (_) {}
  }

  /// 更新词组合条目 (预览图被更换时自动清理旧托管文件，避免孤儿文件堆积)
  Future<void> updateEntry(PromptComboEntry entry) async {
    final list = await loadEntries();
    final idx = list.indexWhere((e) => e.id == entry.id);
    if (idx != -1) {
      final oldPath = list[idx].previewImagePath;
      list[idx] = entry;
      await saveEntries(list);
      if (oldPath != null && oldPath != entry.previewImagePath) {
        await _deleteManagedPreviewFile(oldPath);
      }
    }
  }

  /// 删除词组合条目
  Future<void> deleteEntry(String id) async {
    final list = await loadEntries();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final item = list[idx];
      list.removeAt(idx);
      await saveEntries(list);
      await _deleteManagedPreviewFile(item.previewImagePath);
    }
  }

  /// 保存图片字节到本地预览图目录并返回持久化路径
  Future<String?> savePreviewImageBytes(
    Uint8List bytes, {
    String extension = 'png',
  }) async {
    if (bytes.isEmpty) return null;
    try {
      final previewDir = await _getPreviewDir();
      final hash = md5.convert(bytes).toString().substring(0, 12);
      final filename =
          'preview_${DateTime.now().millisecondsSinceEpoch}_$hash.$extension';
      final file = File(p.join(previewDir.path, filename));
      await file.writeAsBytes(bytes);
      return file.path;
    } catch (_) {
      return null;
    }
  }

  /// 将外部图片文件复制到本地安全预览图目录
  Future<String?> copyPreviewImageFromPath(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) return null;
    try {
      final bytes = await sourceFile.readAsBytes();
      final ext = p.extension(sourcePath).replaceAll('.', '').toLowerCase();
      return await savePreviewImageBytes(
        bytes,
        extension: ext.isNotEmpty ? ext : 'png',
      );
    } catch (_) {
      return null;
    }
  }

  /// 导出为 JSON 字符串
  Future<String> exportToJson() async {
    final list = await loadEntries();
    return jsonEncode(list.map((e) => e.toJson()).toList());
  }

  /// 从 JSON 字符串导入词组合条目
  Future<int> importFromJson(String jsonStr, {bool replaceAll = false}) async {
    final decoded = jsonDecode(jsonStr);
    if (decoded is! List) return 0;

    final imported = <PromptComboEntry>[];
    for (final item in decoded) {
      if (item is Map<String, dynamic>) {
        try {
          imported.add(PromptComboEntry.fromJson(item));
        } catch (_) {}
      }
    }

    if (imported.isEmpty) return 0;

    if (replaceAll) {
      await saveEntries(imported);
      return imported.length;
    } else {
      final currentList = await loadEntries();
      final currentIds = currentList.map((e) => e.id).toSet();
      int added = 0;
      for (final item in imported) {
        if (!currentIds.contains(item.id)) {
          currentList.add(item);
          added++;
        }
      }
      await saveEntries(currentList);
      return added;
    }
  }
}
