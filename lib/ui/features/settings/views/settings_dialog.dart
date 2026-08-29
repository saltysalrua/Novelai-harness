import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../studio/view_models/studio_view_model.dart';

class SettingsDialog extends StatefulWidget {
  final StudioViewModel viewModel;

  const SettingsDialog({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, StudioViewModel viewModel) {
    return showDialog(
      context: context,
      builder: (ctx) => SettingsDialog(viewModel: viewModel),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  late TextEditingController _naiKeyController;
  late TextEditingController _saveDirController;
  late TextEditingController _llmBaseUrlController;
  late TextEditingController _llmApiKeyController;
  late TextEditingController _llmModelController;
  late double _llmTemperature;
  late bool _opusFreeMode;

  bool _obscureNaiKey = true;
  bool _obscureLlmKey = true;

  @override
  void initState() {
    super.initState();
    final cfg = widget.viewModel.config;
    _naiKeyController = TextEditingController(text: cfg.novelAiKey);
    _saveDirController = TextEditingController(text: cfg.saveDirectory);
    _llmBaseUrlController = TextEditingController(text: cfg.llmBaseUrl);
    _llmApiKeyController = TextEditingController(text: cfg.llmApiKey);
    _llmModelController = TextEditingController(text: cfg.llmModel);
    _llmTemperature = cfg.llmTemperature;
    _opusFreeMode = cfg.opusFreeMode;
  }

  @override
  void dispose() {
    _naiKeyController.dispose();
    _saveDirController.dispose();
    _llmBaseUrlController.dispose();
    _llmApiKeyController.dispose();
    _llmModelController.dispose();
    super.dispose();
  }

  Future<void> _pickDirectory() async {
    final selected = await FilePicker.platform.getDirectoryPath();
    if (selected != null && selected.isNotEmpty) {
      setState(() {
        _saveDirController.text = selected;
      });
    }
  }

  void _handleSave() {
    final newConfig = widget.viewModel.config.copyWith(
      novelAiKey: _naiKeyController.text.trim(),
      saveDirectory: _saveDirController.text.trim(),
      opusFreeMode: _opusFreeMode,
      llmBaseUrl: _llmBaseUrlController.text.trim(),
      llmApiKey: _llmApiKeyController.text.trim(),
      llmModel: _llmModelController.text.trim(),
      llmTemperature: _llmTemperature,
    );

    widget.viewModel.updateConfig(newConfig);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Container(
        width: 540,
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题
            const Row(
              children: [
                Icon(Icons.settings_outlined, size: 18, color: AppTheme.notionBlue),
                SizedBox(width: 8),
                Text(
                  '全局参数与模型配置',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),

            // 表单内容
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. NovelAI 官方配置
                    _buildSectionHeader('NovelAI 绘图服务设置'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _naiKeyController,
                      obscureText: _obscureNaiKey,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'NovelAI API Key (pst-...)',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureNaiKey ? Icons.visibility_off : Icons.visibility,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscureNaiKey = !_obscureNaiKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _saveDirController,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: '图片本地存储目录',
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _pickDirectory,
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: AppTheme.border),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                            ),
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                          ),
                          icon: const Icon(Icons.folder_open, size: 15, color: AppTheme.textPrimary),
                          label: const Text('选择', style: TextStyle(fontSize: 12, color: AppTheme.textPrimary)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text(
                        'Opus 免点数保护',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
                      ),
                      subtitle: const Text(
                        '自动将默认参数限制在免费区间内 (像素 <= 1048576 且 步数 <= 28)',
                        style: TextStyle(fontSize: 11, color: AppTheme.textMuted),
                      ),
                      value: _opusFreeMode,
                      activeThumbColor: AppTheme.notionBlue,
                      onChanged: (val) => setState(() => _opusFreeMode = val),
                    ),
                    const SizedBox(height: 18),

                    // 2. LLM 智能助手配置
                    _buildSectionHeader('LLM 智能助手设置 (OpenAI 兼容协议)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _llmBaseUrlController,
                      style: const TextStyle(fontSize: 12),
                      decoration: const InputDecoration(
                        labelText: 'API Base URL',
                        hintText: 'https://api.deepseek.com/v1 或 https://api.openai.com/v1',
                      ),
                    ),
                    const SizedBox(height: 10),

                    TextField(
                      controller: _llmApiKeyController,
                      obscureText: _obscureLlmKey,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        labelText: 'LLM API Key',
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscureLlmKey ? Icons.visibility_off : Icons.visibility,
                            size: 16,
                            color: AppTheme.textMuted,
                          ),
                          onPressed: () =>
                              setState(() => _obscureLlmKey = !_obscureLlmKey),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _llmModelController,
                            style: const TextStyle(fontSize: 12),
                            decoration: const InputDecoration(
                              labelText: '模型名称',
                              hintText: 'deepseek-chat / gpt-4o / gemini-2.5-flash',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '创造力采样温度 (Temperature): ${_llmTemperature.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                        ),
                        Slider(
                          value: _llmTemperature,
                          min: 0.0,
                          max: 1.5,
                          divisions: 15,
                          activeColor: AppTheme.notionBlue,
                          onChanged: (val) => setState(() => _llmTemperature = val),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 底部操作按钮
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('取消', style: TextStyle(color: AppTheme.textSecondary)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.notionBlue,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppTheme.radiusButton),
                    ),
                  ),
                  onPressed: _handleSave,
                  child: const Text('保存设置', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary,
      ),
    );
  }
}
