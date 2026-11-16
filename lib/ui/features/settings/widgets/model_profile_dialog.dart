import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_number_slider.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import 'model_cache_settings.dart';
import 'settings_shared.dart';

/// 模型设置弹窗的返回结果
class ModelProfileResult {
  /// true 表示用户请求删除该模型
  final bool delete;

  /// 保存后的模型配置 (delete 为 true 时为 null)
  final LlmModelConfig? model;

  const ModelProfileResult._(this.delete, this.model);

  const ModelProfileResult.saved(LlmModelConfig model) : this._(false, model);

  const ModelProfileResult.deleted() : this._(true, null);
}

/// 单个模型的详细设置弹窗
///
/// 采用 Notion 极简一体无分割线布局：柔底分组区块、低噪无框输入框、
/// 能力开关与思考等级联动揭示。
class ModelProfileDialog extends StatefulWidget {
  final LlmModelConfig model;
  final bool isNew;
  final bool canDelete;

  const ModelProfileDialog({
    super.key,
    required this.model,
    this.isNew = false,
    this.canDelete = true,
  });

  static Future<ModelProfileResult?> show(
    BuildContext context, {
    required LlmModelConfig model,
    bool isNew = false,
    bool canDelete = true,
  }) {
    return AppDialogScaffold.show<ModelProfileResult>(
      context: context,
      builder: (ctx) =>
          ModelProfileDialog(model: model, isNew: isNew, canDelete: canDelete),
    );
  }

  @override
  State<ModelProfileDialog> createState() => _ModelProfileDialogState();
}

class _ModelProfileDialogState extends State<ModelProfileDialog> {
  late final TextEditingController _nameController;
  late final TextEditingController _idController;
  late final TextEditingController _contextController;
  late final TextEditingController _maxTokensController;
  late final SmoothWheelScrollController _scrollController;
  late bool _reasoning;
  late bool _supportsThinkingOff;
  late bool _multimodal;
  late bool _imageOutput;
  late double _temperature;
  late Set<ThinkingEffort> _levels;
  late LlmCacheConfig _cacheConfig;
  String? _idError;
  int _idShakeTrigger = 0;

  @override
  void initState() {
    super.initState();
    final m = widget.model;
    _nameController = TextEditingController(text: m.name);
    _idController = TextEditingController(text: m.id);
    _contextController = TextEditingController(
      text: m.contextWindow > 0 ? '${m.contextWindow}' : '',
    );
    _maxTokensController = TextEditingController(
      text: m.maxTokens > 0 ? '${m.maxTokens}' : '',
    );
    _scrollController = SmoothWheelScrollController();
    _reasoning = m.reasoning || m.supportedThinkingLevels.isNotEmpty;
    _supportsThinkingOff = m.supportsThinkingOff;
    _multimodal = m.isMultimodal;
    _imageOutput = m.imageOutput;
    _temperature = m.temperature;
    _cacheConfig = m.cacheConfig;
    _levels = {...m.supportedThinkingLevels};
    if (_reasoning && _levels.isEmpty) {
      _levels = {ThinkingEffort.high};
    }
    _idController.addListener(() {
      if (_idError != null) setState(() => _idError = null);
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _nameController.dispose();
    _idController.dispose();
    _contextController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  void _toggleLevel(ThinkingEffort level) {
    setState(() {
      if (level == ThinkingEffort.none) {
        _supportsThinkingOff = !_supportsThinkingOff;
        return;
      }
      if (_levels.contains(level)) {
        _levels.remove(level);
      } else {
        _levels.add(level);
      }
    });
  }

  void _save() {
    final id = _idController.text.trim();
    if (id.isEmpty) {
      setState(() {
        _idError = context.l10n.settingsModelIdEmptyError;
        _idShakeTrigger++;
      });
      return;
    }

    final contextWindow =
        int.tryParse(_contextController.text.trim()) ?? 128000;
    final maxTokens = int.tryParse(_maxTokensController.text.trim()) ?? 8192;
    final name = _nameController.text.trim().isEmpty
        ? id
        : _nameController.text.trim();

    final levels = _reasoning
        ? ([
            ThinkingEffort.low,
            ThinkingEffort.medium,
            ThinkingEffort.high,
            ThinkingEffort.xhigh,
            ThinkingEffort.max,
          ].where(_levels.contains).toList())
        : const <ThinkingEffort>[];

    Navigator.of(context).pop(
      ModelProfileResult.saved(
        LlmModelConfig(
          id: id,
          name: name,
          reasoning: _reasoning,
          input: _multimodal ? const ['text', 'image'] : const ['text'],
          supportedThinkingLevels: levels,
          preferredThinkingEffort: widget.model.preferredThinkingEffortFor(
            levels,
          ),
          supportsThinkingOff: _supportsThinkingOff,
          contextWindow: contextWindow <= 0 ? 128000 : contextWindow,
          maxTokens: maxTokens <= 0 ? 8192 : maxTokens,
          temperature: _temperature,
          imageOutput: _imageOutput,
          cacheConfig: _cacheConfig,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;

    return AppDialogScaffold(
      minimalChrome: true,
      title: widget.isNew ? l10n.settingsAddModel : l10n.settingsModelSettings,
      subtitle: !widget.isNew && widget.model.id.isNotEmpty
          ? widget.model.id
          : null,
      width: 540,
      maxHeight: 700,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 430;
          return SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. 基础标识 (名称 + 模型 ID)
                _buildBasicFields(context, isNarrow: isNarrow),
                const SizedBox(height: AppSpacing.lg),

                // 2. 模型能力 (软底分组)
                SettingsFieldLabel(label: l10n.settingsModelSectionCapabilities),
                const SizedBox(height: 6),
                SettingsSoftContainer(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _SwitchRow(
                        label: l10n.settingsModelReasoning,
                        value: _reasoning,
                        onChanged: (v) => setState(() => _reasoning = v),
                      ),
                      AppPanelReveal(
                        visible: _reasoning,
                        enableBlur: false,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8, bottom: 4),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.settingsModelThinkingEffort,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: colors.textMuted,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: [
                                  for (final level in const [
                                    ThinkingEffort.none,
                                    ThinkingEffort.low,
                                    ThinkingEffort.medium,
                                    ThinkingEffort.high,
                                    ThinkingEffort.xhigh,
                                    ThinkingEffort.max,
                                  ])
                                    _buildLevelChip(
                                      level,
                                      level == ThinkingEffort.none
                                          ? _supportsThinkingOff
                                          : _levels.contains(level),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SwitchRow(
                        label: l10n.settingsModelMultimodal,
                        value: _multimodal,
                        onChanged: (v) => setState(() => _multimodal = v),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      _SwitchRow(
                        label: l10n.settingsModelImageOutput,
                        value: _imageOutput,
                        onChanged: (v) => setState(() => _imageOutput = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // 3. 采样与上下文限制
                SettingsFieldLabel(label: l10n.settingsModelSectionParameters),
                const SizedBox(height: 6),
                SettingsSoftContainer(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.settingsModelTemperature,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      AppNumberSlider(
                        value: _temperature,
                        min: 0.0,
                        max: 1.5,
                        step: 0.05,
                        fractionDigits: 2,
                        onChanged: (v) => setState(() => _temperature = v),
                      ),
                      const SizedBox(height: AppSpacing.md),
                      _buildLimitFields(context, isNarrow: isNarrow),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),

                // 4. 提示词缓存
                SettingsFieldLabel(label: l10n.settingsModelSectionCache),
                const SizedBox(height: 6),
                ModelCacheSettings(
                  value: _cacheConfig,
                  embedded: true,
                  onChanged: (value) => setState(() => _cacheConfig = value),
                ),
              ],
            ),
          );
        },
      ),
      footerLeading: (!widget.isNew && widget.canDelete)
          ? InkWell(
              onTap: () =>
                  Navigator.of(context).pop(const ModelProfileResult.deleted()),
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.delete_outline_rounded,
                      size: 15,
                      color: colors.error,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      l10n.settingsDeleteModel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w500,
                        color: colors.error,
                      ),
                    ),
                  ],
                ),
              ),
            )
          : null,
      actions: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: widget.isNew ? l10n.settingsAdd : l10n.save,
          variant: AppActionButtonVariant.primary,
          onPressed: _save,
        ),
      ],
    );
  }

  Widget _buildBasicFields(BuildContext context, {required bool isNarrow}) {
    final l10n = context.l10n;
    final nameField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsFieldLabel(label: l10n.settingsModelDisplayName),
        const SizedBox(height: 6),
        _buildTextField(
          controller: _nameController,
          hint: l10n.settingsModelDisplayNameHint,
        ),
      ],
    );

    final idField = AppErrorShake(
      trigger: _idShakeTrigger,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsFieldLabel(label: l10n.settingsModelId),
          const SizedBox(height: 6),
          _buildTextField(
            controller: _idController,
            hint: l10n.settingsModelIdHint,
            errorText: _idError,
            mono: true,
          ),
        ],
      ),
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [nameField, const SizedBox(height: 10), idField],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: nameField),
        const SizedBox(width: 12),
        Expanded(child: idField),
      ],
    );
  }

  Widget _buildLimitFields(BuildContext context, {required bool isNarrow}) {
    final colors = context.colors;
    final l10n = context.l10n;

    final contextField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsModelContextWindow,
          style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
        ),
        const SizedBox(height: 5),
        _buildTextField(
          controller: _contextController,
          hint: '128000',
          mono: true,
          digitsOnly: true,
          fillColor: colors.cardBackground,
        ),
      ],
    );

    final maxTokensField = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.settingsModelMaxTokens,
          style: TextStyle(fontSize: 11.5, color: colors.textSecondary),
        ),
        const SizedBox(height: 5),
        _buildTextField(
          controller: _maxTokensController,
          hint: '8192',
          mono: true,
          digitsOnly: true,
          fillColor: colors.cardBackground,
        ),
      ],
    );

    if (isNarrow) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [contextField, const SizedBox(height: 10), maxTokensField],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: contextField),
        const SizedBox(width: 12),
        Expanded(child: maxTokensField),
      ],
    );
  }

  Widget _buildLevelChip(ThinkingEffort level, bool selected) {
    final colors = context.colors;
    final l10n = context.l10n;
    return AppToolChip(
      label: switch (level) {
        ThinkingEffort.none => l10n.chatThinkingEffortNone,
        ThinkingEffort.low => l10n.chatThinkingEffortLow,
        ThinkingEffort.medium => l10n.chatThinkingEffortMedium,
        ThinkingEffort.high => l10n.chatThinkingEffortHigh,
        ThinkingEffort.xhigh => l10n.chatThinkingEffortXHigh,
        ThinkingEffort.max => l10n.chatThinkingEffortMax,
      },
      isSelected: selected,
      variant: AppToolChipVariant.tinted,
      unselectedBackgroundColor: colors.cardBackground,
      onTap: () => _toggleLevel(level),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    String? errorText,
    bool mono = false,
    bool digitsOnly = false,
    Color? fillColor,
  }) {
    return TextField(
      controller: controller,
      style: TextStyle(fontSize: 12, fontFamily: mono ? 'monospace' : null),
      inputFormatters: digitsOnly
          ? [FilteringTextInputFormatter.digitsOnly]
          : null,
      decoration: settingsSoftInputDecoration(
        context,
        hintText: hint,
        errorText: errorText,
        fillColor: fillColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 11,
          vertical: 9,
        ),
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SwitchRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12.5, color: colors.textPrimary),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}
