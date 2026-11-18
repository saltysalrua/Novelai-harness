import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../models/prompt_library_models.dart';
import '../models/prompt_library_sync_models.dart';
import '../models/tag_models.dart';
import 'prompt_image_probe.dart';

/// 词组合预设库持久化与管理服务
class PromptLibraryService {
  static final PromptLibraryService instance = PromptLibraryService._();

  PromptLibraryService._();
  factory PromptLibraryService() => instance;

  String? _customStorageDir;
  List<PromptComboEntry>? _cachedEntries;
  PromptLibrarySyncState? _cachedSyncState;

  /// 获取当前已加载的词库条目内存缓存 (未显式加载时视为空)
  List<PromptComboEntry> get cachedEntries => _cachedEntries ?? const [];

  /// 获取当前已加载的同步状态内存缓存
  PromptLibrarySyncState? get cachedSyncState => _cachedSyncState;

  /// 用于测试或自定义设置的存储根目录
  void setCustomStorageDirectory(String? dir) {
    _customStorageDir = dir;
    _cachedEntries = null;
    _cachedSyncState = null;
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

  /// 获取同步状态持久化文件 (删除墓碑与图片哈希缓存)
  Future<File> _getSyncStateFile() async {
    final baseDir = _customStorageDir ?? (await _getAppSupportDir()).path;
    final dir = Directory(baseDir);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    return File(p.join(baseDir, 'prompt_library_sync_state.json'));
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

  /// 获取托管预览图目录 (供同步服务复用或清理孤儿缓存)
  Future<Directory> getPreviewDirectory() => _getPreviewDir();

  Future<Directory> _getAppSupportDir() async {
    try {
      return await getApplicationSupportDirectory();
    } catch (_) {
      return Directory.current;
    }
  }

  /// 加载所有词组合条目 (不播种任何默认数据：文件不存在或为空即空词库，
  /// 用户删除的条目不会以任何形式复活)
  Future<List<PromptComboEntry>> loadEntries() async {
    final file = await _getDataFile();
    if (!file.existsSync()) {
      // 返回可增长列表 (addEntry 等会直接在返回值上修改)
      _cachedEntries = [];
      return [];
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
        _cachedEntries = list;
        unawaited(
          PromptImageProbe.warmUpPaths(list.map((e) => e.previewImagePath)),
        );
        return list;
      }
    } catch (_) {}

    _cachedEntries = [];
    return [];
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

  /// 加载同步状态 (墓碑与本地预览图哈希缓存)
  Future<PromptLibrarySyncState> loadSyncState() async {
    if (_cachedSyncState != null) return _cachedSyncState!;
    final file = await _getSyncStateFile();
    if (!file.existsSync()) {
      _cachedSyncState = const PromptLibrarySyncState();
      return _cachedSyncState!;
    }
    try {
      final raw = await file.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        _cachedSyncState = PromptLibrarySyncState.fromJson(decoded);
        return _cachedSyncState!;
      }
    } catch (_) {}
    _cachedSyncState = const PromptLibrarySyncState();
    return _cachedSyncState!;
  }

  /// 持久化保存同步状态
  Future<void> saveSyncState(PromptLibrarySyncState state) async {
    _cachedSyncState = state;
    final file = await _getSyncStateFile();
    await file.writeAsString(jsonEncode(state.toJson()), flush: true);
  }

  /// 一次性提交云同步产物并清理孤儿托管预览图
  Future<void> applySyncOutcome({
    required List<PromptComboEntry> entries,
    required PromptLibrarySyncState syncState,
  }) async {
    await saveEntries(entries);
    await saveSyncState(syncState);
    final activePaths = entries
        .map((e) => e.previewImagePath?.trim())
        .whereType<String>()
        .where((path) => path.isNotEmpty)
        .toSet();
    await pruneOrphanedManagedPreviews(activePaths);
  }

  /// 清理托管预览目录中不再被任何活跃条目引用的文件
  Future<void> pruneOrphanedManagedPreviews(Set<String> activePaths) async {
    try {
      final previewDir = await _getPreviewDir();
      if (!previewDir.existsSync()) return;
      final normalizedActive = activePaths.map(p.normalize).toSet();
      await for (final entity in previewDir.list(followLinks: false)) {
        if (entity is! File) continue;
        final normalized = p.normalize(entity.path);
        if (!normalizedActive.contains(normalized)) {
          try {
            await entity.delete();
            PromptImageProbe.invalidate(entity.path);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  Future<void> _clearTombstonesForIds(Iterable<String> ids) async {
    final targetIds = ids.where((id) => id.isNotEmpty).toSet();
    if (targetIds.isEmpty) return;
    final state = await loadSyncState();
    if (!targetIds.any(state.tombstones.containsKey)) return;
    final nextTombstones = Map<String, DateTime>.from(state.tombstones)
      ..removeWhere((key, _) => targetIds.contains(key));
    await saveSyncState(state.copyWith(tombstones: nextTombstones));
  }

  Future<void> _recordTombstones(Iterable<String> ids) async {
    final targetIds = ids.where((id) => id.isNotEmpty).toSet();
    if (targetIds.isEmpty) return;
    final state = await loadSyncState();
    final now = DateTime.now().toUtc();
    final nextTombstones = Map<String, DateTime>.from(state.tombstones);
    for (final id in targetIds) {
      nextTombstones[id] = now;
    }
    await saveSyncState(state.copyWith(tombstones: nextTombstones));
  }

  /// 添加词组合条目
  Future<PromptComboEntry> addEntry(PromptComboEntry entry) async {
    final list = await loadEntries();
    list.insert(0, entry);
    await saveEntries(list);
    await _clearTombstonesForIds([entry.id]);
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
      PromptImageProbe.invalidate(path);
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
      await _clearTombstonesForIds([entry.id]);
      if (oldPath != null &&
          oldPath != entry.previewImagePath &&
          !list.any((e) => e.previewImagePath == oldPath)) {
        await _deleteManagedPreviewFile(oldPath);
      }
    }
  }

  /// 删除词组合条目 (同时记录删除墓碑，供多端云同步感知删除)
  Future<void> deleteEntry(String id) async {
    final list = await loadEntries();
    final idx = list.indexWhere((e) => e.id == id);
    if (idx != -1) {
      final item = list[idx];
      list.removeAt(idx);
      await saveEntries(list);
      await _recordTombstones([id]);
      final oldPath = item.previewImagePath;
      if (oldPath != null && !list.any((e) => e.previewImagePath == oldPath)) {
        await _deleteManagedPreviewFile(oldPath);
      }
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
      PromptImageProbe.recordBytes(file.path, bytes);
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
      final prevList = await loadEntries();
      final importedIds = imported.map((e) => e.id).toSet();
      final removedIds = prevList
          .map((e) => e.id)
          .where((id) => !importedIds.contains(id))
          .toList();
      await saveEntries(imported);
      await _recordTombstones(removedIds);
      await _clearTombstonesForIds(importedIds);
      return imported.length;
    } else {
      final currentList = await loadEntries();
      final currentIds = currentList.map((e) => e.id).toSet();
      final addedIds = <String>[];
      int added = 0;
      for (final item in imported) {
        if (!currentIds.contains(item.id)) {
          currentList.add(item);
          addedIds.add(item.id);
          added++;
        }
      }
      await saveEntries(currentList);
      await _clearTombstonesForIds(addedIds);
      return added;
    }
  }
}
