import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/theme/app_theme.dart';
import 'settings_shared.dart';

/// General 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class GeneralSettingsDraft {
  GeneralSettingsDraft(AppConfig config)
    : naiKeyController = TextEditingController(text: config.novelAiKey),
      saveDirController = TextEditingController(text: config.saveDirectory),
      opusFreeMode = config.opusFreeMode,
      enableStreamPreview = config.enableStreamPreview;

  final TextEditingController naiKeyController;
  final TextEditingController saveDirController;
  bool opusFreeMode;
  bool enableStreamPreview;

  void dispose() {
    naiKeyController.dispose();
    saveDirController.dispose();
  }
}

/// General 页：NovelAI 服务凭证、本地存储与保护开关
class GeneralSettingsTab extends StatefulWidget {
  final GeneralSettingsDraft draft;

  const GeneralSettingsTab({super.key, required this.draft});

  @override
  State<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<GeneralSettingsTab> {
  GeneralSettingsDraft get _draft => widget.draft;

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
