import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/tag_dictionary_service.dart';
import '../../../../data/services/tag_dictionary_update_service.dart';
import '../../../core/theme/app_theme.dart';
import 'settings_shared.dart';

/// General 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class GeneralSettingsDraft {
  GeneralSettingsDraft(AppConfig config)
    : naiKeyController = TextEditingController(text: config.novelAiKey),
      saveDirController = TextEditingController(text: config.saveDirectory),
      opusFreeMode = config.opusFreeMode,
      enableStreamPreview = config.enableStreamPreview,
      enableTagAutocomplete = config.enableTagAutocomplete,
      showTagTranslations = config.showTagTranslations,
      showTagCategoryColors = config.showTagCategoryColors,
      enableTagDictionaryAutoUpdate = config.enableTagDictionaryAutoUpdate,
      enableImagePersistence = config.enableImagePersistence,
      maxPersistentImages = config.maxPersistentImages;

  final TextEditingController naiKeyController;
  final TextEditingController saveDirController;
  bool opusFreeMode;
  bool enableStreamPreview;
  bool enableTagAutocomplete;
  bool showTagTranslations;
  bool showTagCategoryColors;
  bool enableTagDictionaryAutoUpdate;
  bool enableImagePersistence;
  int maxPersistentImages;

  void dispose() {
    naiKeyController.dispose();
    saveDirController.dispose();
  }
}

/// General 页：NovelAI 服务凭证、本地存储、标签补全与保护开关
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SettingsGroupTitle('NovelAI Service'),
        SettingsCard(
          title: 'NovelAI API Key',
          subtitle: '官方 API 凭证 (pst-...)，用于图像生成与体力池同步',
          control: SettingsKeyField(
            controller: _draft.naiKeyController,
            hintText: 'pst-...',
          ),
        ),
        SettingsCard(
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
              SettingsActionButton(
                icon: Icons.folder_open_rounded,
                label: '选择',
                onPressed: _pickDirectory,
              ),
            ],
          ),
        ),
        SettingsCard(
          title: '实时生图预览',
          subtitle: '生图过程中接收并实时渲染中间去噪步数预览图 (Stream Preview)',
          control: Switch(
            value: _draft.enableStreamPreview,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) =>
                setState(() => _draft.enableStreamPreview = val),
          ),
        ),
        SettingsCard(
          title: '图片历史持久化',
          subtitle: '应用重启后自动恢复画板历史中的生成图片记录',
          control: Switch(
            value: _draft.enableImagePersistence,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) =>
                setState(() => _draft.enableImagePersistence = val),
          ),
        ),
        if (_draft.enableImagePersistence)
          SettingsCard(
            title: '可持久化图像上限',
            subtitle: '限制本地画板历史中保留的最大图片数量',
            control: SettingsDropdown<int>(
              value: [20, 50, 100, 200, 500].contains(_draft.maxPersistentImages)
                  ? _draft.maxPersistentImages
                  : 50,
              items: const [20, 50, 100, 200, 500],
              labelBuilder: (count) => '$count 张',
              onChanged: (val) {
                if (val != null) {
                  setState(() => _draft.maxPersistentImages = val);
                }
              },
            ),
          ),
        const SizedBox(height: 12),
        const SettingsGroupTitle('Danbooru Tag Autocomplete'),
        SettingsCard(
          title: '标签智能自动补全',
          subtitle: '输入提示词时自动弹出 32万+ Danbooru 词库悬浮联想建议',
          control: Switch(
            value: _draft.enableTagAutocomplete,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) =>
                setState(() => _draft.enableTagAutocomplete = val),
          ),
        ),
        SettingsCard(
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
              : SettingsActionButton(
                  icon: Icons.cloud_download_rounded,
                  label: '立即更新',
                  onPressed: _updateDictionary,
                ),
        ),
        SettingsCard(
          title: '启动时自动检查更新',
          subtitle: '每日一次后台拉取最新词库 (ffdkj 每日构建，含新标签与中文翻译)',
          control: Switch(
            value: _draft.enableTagDictionaryAutoUpdate,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) =>
                setState(() => _draft.enableTagDictionaryAutoUpdate = val),
          ),
        ),
        SettingsCard(
          title: '显示标签中文释义',
          subtitle: '在补全候选词列表与灵感库中展示对应的中文翻译释义',
          control: Switch(
            value: _draft.showTagTranslations,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) =>
                setState(() => _draft.showTagTranslations = val),
          ),
        ),
        SettingsCard(
          title: '标签分类着色高亮',
          subtitle: '在提示词输入框中对画师、角色、作品、通用等标签施加分类色彩高亮',
          control: Switch(
            value: _draft.showTagCategoryColors,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) =>
                setState(() => _draft.showTagCategoryColors = val),
          ),
        ),
        const SizedBox(height: 12),
        const SettingsGroupTitle('Protection'),
        SettingsCard(
          title: 'Opus 免点数保护',
          subtitle: '自动将默认参数限制在免费区间内 (像素 <= 1048576 且 步数 <= 28)',
          control: Switch(
            value: _draft.opusFreeMode,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) => setState(() => _draft.opusFreeMode = val),
          ),
        ),
      ],
    );
  }
}
