import 'package:flutter/material.dart';

import '../../../../data/services/image_save_path_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../../core/widgets/app_transitions.dart';

/// 纯表单视图：预览/校验由草稿提供，复用设置卡片、下拉与折叠原子组件。
class ImageSaveTemplateSettings extends StatefulWidget {
  final TextEditingController controller;
  final String preview;
  final ImageSaveTemplateError? error;
  final ValueChanged<String> onInsertMacro;

  const ImageSaveTemplateSettings({
    super.key,
    required this.controller,
    required this.preview,
    required this.error,
    required this.onInsertMacro,
  });

  /// 表单与保存拦截共用同一份本地化错误说明。
  static String? errorTextOf(
    BuildContext context,
    ImageSaveTemplateError? error,
  ) {
    final l10n = context.l10n;
    return switch (error) {
      ImageSaveTemplateError.invalidMacro => l10n.settingsImageSaveInvalidMacro,
      ImageSaveTemplateError.invalidPath => l10n.settingsImageSaveInvalidPath,
      ImageSaveTemplateError.tooLong => l10n.settingsImageSaveTooLong,
      null => null,
    };
  }

  @override
  State<ImageSaveTemplateSettings> createState() =>
      _ImageSaveTemplateSettingsState();
}

class _ImageSaveTemplateSettingsState extends State<ImageSaveTemplateSettings> {
  int _errorShakeTrigger = 0;

  @override
  void didUpdateWidget(covariant ImageSaveTemplateSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.error != null && widget.error != oldWidget.error) {
      _errorShakeTrigger++;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorText = ImageSaveTemplateSettings.errorTextOf(
      context,
      widget.error,
    );
    return AppSettingTile(
      title: l10n.settingsImageSaveTemplateTitle,
      control: const SizedBox.shrink(),
      bottomChild: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              AppDropdown<String>(
                value: '',
                width: 190,
                items: [
                  AppDropdownItem(
                    value: '',
                    label: l10n.settingsImageSavePreset,
                  ),
                  AppDropdownItem(
                    value: ImageSavePathService.defaultTemplate,
                    label: l10n.settingsImageSaveDefault,
                  ),
                  AppDropdownItem(
                    value: '{date:yyyy-MM-dd}/{prefix}_{time}_{seed}',
                    label: l10n.settingsImageSaveByDate,
                  ),
                  AppDropdownItem(
                    value: '{date:yyyy-MM}/{model}/{seed}_{time}',
                    label: l10n.settingsImageSaveByModel,
                  ),
                ],
                onChanged: (value) {
                  if (value.isNotEmpty) widget.controller.text = value;
                },
              ),
              AppDropdown.simple(
                value: '',
                width: 150,
                menuWidth: 230,
                items: const [
                  '',
                  ...ImageSavePathService.macroNames,
                  'date:yyyy-MM-dd',
                  'date:yyyy-MM',
                  'date:HHmmss_SSS',
                ],
                labelOf: (value) => value.isEmpty
                    ? l10n.settingsImageSaveInsertMacro
                    : '{$value}',
                onChanged: widget.onInsertMacro,
              ),
            ],
          ),
          const SizedBox(height: 10),
          AppErrorShake(
            trigger: _errorShakeTrigger,
            child: TextField(
              key: const ValueKey('image-save-template'),
              controller: widget.controller,
              minLines: 1,
              maxLines: 3,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: ImageSavePathService.defaultTemplate,
                errorText: errorText,
                errorMaxLines: 4,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
          ),
          if (widget.error == null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.settingsImageSaveTemplatePreview,
              style: TextStyle(fontSize: 11, color: context.colors.textMuted),
            ),
            SelectableText(
              widget.preview,
              key: const ValueKey('image-save-preview'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    );
  }
}
