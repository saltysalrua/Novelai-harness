import 'package:flutter/material.dart';

import '../../../../data/services/image_save_path_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_setting_tile.dart';

/// 纯表单视图：预览/校验由草稿提供，复用设置卡片、下拉与折叠原子组件。
class ImageSaveTemplateSettings extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final errorText = errorTextOf(context, error);
    return AppSettingTile(
      title: l10n.settingsImageSaveTemplateTitle,
      subtitle: l10n.settingsImageSaveTemplateSubtitle,
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
                  if (value.isNotEmpty) controller.text = value;
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
                onChanged: onInsertMacro,
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('image-save-template'),
            controller: controller,
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
          if (error == null) ...[
            const SizedBox(height: 8),
            Text(
              l10n.settingsImageSaveTemplatePreview,
              style: TextStyle(fontSize: 11, color: context.colors.textMuted),
            ),
            SelectableText(
              preview,
              key: const ValueKey('image-save-preview'),
              style: const TextStyle(fontSize: 12),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            l10n.settingsImageSaveTemplateHelp,
            style: TextStyle(fontSize: 12, color: context.colors.textSecondary),
          ),
          AppCollapsibleSection(
            title: l10n.settingsImageSaveMacros,
            isCard: false,
            child: Text(
              l10n.settingsImageSaveMacroHelp,
              style: TextStyle(
                fontSize: 12,
                color: context.colors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
