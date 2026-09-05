import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../../data/services/tag_dictionary_update_service.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';
import 'settings_shared.dart';

/// General 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class GeneralSettingsDraft {
  GeneralSettingsDraft(AppConfig config)
    : naiKeyController = TextEditingController(text: config.novelAiKey),
      saveDirController = TextEditingController(text: config.saveDirectory),
      opusFreeMode = config.opusFreeMode,
      themeMode = config.themeMode,
      uiZoom = config.uiZoom,
      enableStreamPreview = config.enableStreamPreview,
      enableTagAutocomplete = config.enableTagAutocomplete,
      showTagTranslations = config.showTagTranslations,
      showTagCategoryColors = config.showTagCategoryColors,
      enableTagDictionaryAutoUpdate = config.enableTagDictionaryAutoUpdate,
      enableImagePersistence = config.enableImagePersistence,
      maxPersistentImages = config.maxPersistentImages,
      autoSaveImages = config.autoSaveImages;

  final TextEditingController naiKeyController;
  final TextEditingController saveDirController;
  bool opusFreeMode;

  /// 主题模式偏好 (跟随系统/亮色/深色)，保存时由 SettingsDialog 聚合进 AppConfig
  AppThemeModePreference themeMode;

  /// 全局 UI 缩放 (浏览器式整体缩放)，保存时聚合进 AppConfig
  double uiZoom;
  bool enableStreamPreview;
  bool enableTagAutocomplete;
  bool showTagTranslations;
  bool showTagCategoryColors;
  bool enableTagDictionaryAutoUpdate;
  bool enableImagePersistence;
  int maxPersistentImages;
  bool autoSaveImages;

  void dispose() {
    naiKeyController.dispose();
    saveDirController.dispose();
  }
}

/// General 页：主题模式、NovelAI 服务凭证、本地存储、标签补全与保护开关
///
/// 阶段 3 垂直切片：旧 SettingsCard/SettingsDropdown/SettingsActionButton
/// 全部替换为原子组件 (AppSettingTile + AppDropdown + AppActionButton)。
class GeneralSettingsTab extends StatefulWidget {
  final GeneralSettingsDraft draft;

  const GeneralSettingsTab({super.key, required this.draft});

  @override
  State<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<GeneralSettingsTab> {
  GeneralSettingsDraft get _draft => widget.draft;

  TagDictMeta? _dictMeta;
  bool _dictUpdating = false;
  String _dictStatus = '';

  @override
  void initState() {
    super.initState();
    _refreshDictInfo();
  }

  Future<void> _refreshDictInfo() async {
    final meta = await TagDictionaryUpdateService.instance.loadMeta();
    if (!mounted) return;
    setState(() => _dictMeta = meta);
  }

  Future<void> _updateDictionary() async {
    if (_dictUpdating) return;
    setState(() {
      _dictUpdating = true;
      _dictStatus = '';
    });
    try {
      final result = await TagDictionaryUpdateService.instance.updateNow(
        onStatus: (stage) {
          if (mounted) setState(() => _dictStatus = stage);
        },
      );
      if (!mounted) return;
      setState(() => _dictStatus = result.message);
      await _refreshDictInfo();
    } catch (e) {
      if (mounted) {
        setState(() => _dictStatus = '更新失败: $e');
      }
    } finally {
      if (mounted) setState(() => _dictUpdating = false);
    }
  }

  String _dictInfoText() {
    final count = TagDictionaryService.instance.count;
    final meta = _dictMeta;
    if (meta != null) {
      final date = DateFormat('yyyy-MM-dd HH:mm').format(meta.installedAt);
      return '在线词库 ${meta.entryCount} 条 · 更新于 $date';
    }
    return count > 0 ? '内置词库 $count 条' : '内置词库 (加载中)';
  }

  Future<void> _pickDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null && selected.isNotEmpty && mounted) {
      setState(() => _draft.saveDirController.text = selected);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionHeader(title: 'Appearance'),
          AppSettingTile(
            title: '主题模式',
            subtitle: '切换亮色/深色工作台外观，深色采用 Notion 极简暗调色板',
            control: AppDropdown.simple(
              value: _draft.themeMode,
              items: AppThemeModePreference.values,
              labelOf: (mode) => switch (mode) {
                AppThemeModePreference.system => '跟随系统',
                AppThemeModePreference.light => '亮色',
                AppThemeModePreference.dark => '深色',
              },
              width: 130,
              onChanged: (mode) => setState(() => _draft.themeMode = mode),
            ),
          ),
          AppSettingTile(
            title: '界面缩放',
            subtitle: '整体缩放工作台界面；快捷键 Ctrl + = / Ctrl + - 步进，Ctrl + 0 重置',
            control: AppDropdown<double>.simple(
              value: _draft.uiZoom,
              items: const [0.8, 0.9, 1.0, 1.1, 1.25, 1.5, 1.75],
              labelOf: (zoom) => '${(zoom * 100).round()}%',
              width: 110,
              onChanged: (zoom) => setState(() => _draft.uiZoom = zoom),
            ),
          ),
          const SizedBox(height: 12),
          const AppSectionHeader(title: 'NovelAI Service'),
          AppSettingTile(
            title: 'NovelAI API Key',
            subtitle: '官方 API 凭证 (pst-...)，用于图像生成与体力池同步',
            control: SettingsKeyField(
              controller: _draft.naiKeyController,
              hintText: 'pst-...',
            ),
          ),
          AppSettingTile(
            title: '本地存储目录',
            subtitle: '生成的高清图像与元数据自动保存至此路径',
            control: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 220,
                  height: 36,
                  child: TextField(
                    controller: _draft.saveDirController,
                    style: const TextStyle(fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: '存储路径...',
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                AppActionButton(
                  icon: Icons.folder_open_rounded,
                  label: '选择',
                  onPressed: _pickDirectory,
                ),
              ],
            ),
          ),
          AppSettingTile.switchTile(
            title: '自动保存生成图片',
            subtitle: _draft.autoSaveImages
                ? '生成图片自动写入本地存储目录 (按导出设置处理元数据与水印)'
                : '生成图片先存入缓存目录 (无水印)，在画板右下角点击保存按钮手动保存；超出历史上限的缓存图片自动删除',
            value: _draft.autoSaveImages,
            onChanged: (val) => setState(() => _draft.autoSaveImages = val),
          ),
          AppSettingTile.switchTile(
            title: '实时生图预览',
            subtitle: '生图过程中接收并实时渲染中间去噪步数预览图 (Stream Preview)',
            value: _draft.enableStreamPreview,
            onChanged: (val) =>
                setState(() => _draft.enableStreamPreview = val),
          ),
          AppSettingTile.switchTile(
            title: '图片历史持久化',
            subtitle: '应用重启后自动恢复画板历史中的生成图片记录',
            value: _draft.enableImagePersistence,
            onChanged: (val) =>
                setState(() => _draft.enableImagePersistence = val),
          ),
          if (_draft.enableImagePersistence)
            AppSettingTile(
              title: '可持久化图像上限',
              subtitle: '限制本地画板历史中保留的最大图片数量',
              control: AppDropdown.simple(
                value:
                    [20, 50, 100, 200, 500].contains(_draft.maxPersistentImages)
                    ? _draft.maxPersistentImages
                    : 50,
                items: const [20, 50, 100, 200, 500],
                labelOf: (count) => '$count 张',
                width: 110,
                onChanged: (count) =>
                    setState(() => _draft.maxPersistentImages = count),
              ),
            ),
          const SizedBox(height: 12),
          const AppSectionHeader(title: 'Danbooru Tag Autocomplete'),
          AppSettingTile.switchTile(
            title: '标签智能自动补全',
            subtitle: '输入提示词时自动弹出 32万+ Danbooru 词库悬浮联想建议',
            value: _draft.enableTagAutocomplete,
            onChanged: (val) =>
                setState(() => _draft.enableTagAutocomplete = val),
          ),
          AppSettingTile(
            title: '词库在线更新',
            subtitle: _dictUpdating
                ? _dictStatus
                : (_dictStatus.isNotEmpty ? _dictStatus : _dictInfoText()),
            control: _dictUpdating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : AppActionButton(
                    icon: Icons.cloud_download_rounded,
                    label: '立即更新',
                    onPressed: _updateDictionary,
                  ),
          ),
          AppSettingTile.switchTile(
            title: '启动时自动检查更新',
            subtitle: '每日一次后台拉取最新词库 (ffdkj 每日构建，含新标签与中文翻译)',
            value: _draft.enableTagDictionaryAutoUpdate,
            onChanged: (val) =>
                setState(() => _draft.enableTagDictionaryAutoUpdate = val),
          ),
          AppSettingTile.switchTile(
            title: '显示标签中文释义',
            subtitle: '在补全候选词列表与灵感库中展示对应的中文翻译释义',
            value: _draft.showTagTranslations,
            onChanged: (val) =>
                setState(() => _draft.showTagTranslations = val),
          ),
          AppSettingTile.switchTile(
            title: '标签分类着色高亮',
            subtitle: '在提示词输入框中对画师、角色、作品、通用等标签施加分类色彩高亮',
            value: _draft.showTagCategoryColors,
            onChanged: (val) =>
                setState(() => _draft.showTagCategoryColors = val),
          ),
          const SizedBox(height: 12),
          const AppSectionHeader(title: 'Protection'),
          AppSettingTile.switchTile(
            title: 'Opus 免点数保护',
            subtitle: '自动将默认参数限制在免费区间内 (像素 <= 1048576 且 步数 <= 28)',
            value: _draft.opusFreeMode,
            onChanged: (val) => setState(() => _draft.opusFreeMode = val),
          ),
        ],
      ),
    );
  }
}
