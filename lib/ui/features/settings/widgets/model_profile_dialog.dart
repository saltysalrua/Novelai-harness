import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';

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
/// 编辑显示名称、模型 ID、温度、深度思考、思考等级、多模态、
/// 上下文窗口与最大输出 tokens；在线拉取的能力元数据对不上号时可手动修正。
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
    return showDialog<ModelProfileResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.4),
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
  late bool _reasoning;
  late bool _multimodal;
  late double _temperature;
  late Set<ThinkingEffort> _levels;
  String? _idError;

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
    _reasoning = m.reasoning || m.supportedThinkingLevels.isNotEmpty;
    _multimodal = m.isMultimodal;
    _temperature = m.temperature;
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
    _nameController.dispose();
    _idController.dispose();
    _contextController.dispose();
    _maxTokensController.dispose();
    super.dispose();
  }

  void _toggleLevel(ThinkingEffort level) {
    setState(() {
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
      setState(() => _idError = '模型 ID 不能为空');
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
          contextWindow: contextWindow <= 0 ? 128000 : contextWindow,
          maxTokens: maxTokens <= 0 ? 8192 : maxTokens,
          temperature: _temperature,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 标题栏
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.isNew ? '添加模型' : '模型设置',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.close_rounded,
                      size: 18,
                      color: AppTheme.stone,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldRow(
                      label: '显示名称',
                      child: _buildTextField(
                        controller: _nameController,
                        hint: '如 DeepSeek R1',
                      ),
                    ),
                    _buildFieldRow(
                      label: '模型 ID',
                      child: _buildTextField(
                        controller: _idController,
                        hint: '发送给 API 的模型标识',
                        errorText: _idError,
                        mono: true,
                      ),
                    ),
                    _buildFieldRow(
                      label: '温度 (Temperature)',
                      child: SizedBox(
                        width: 190,
                        child: Row(
                          children: [
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(
                                  context,
                                ).copyWith(trackHeight: 3),
                                child: Slider(
                                  value: _temperature,
                                  min: 0.0,
                                  max: 1.5,
                                  divisions: 30,
                                  activeColor: AppTheme.notionBlue,
                                  onChanged: (v) =>
                                      setState(() => _temperature = v),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: 36,
                              child: Text(
                                _temperature.toStringAsFixed(2),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: 'monospace',
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    _buildFieldRow(
                      label: '深度思考 (Reasoning)',
                      child: Switch(
                        value: _reasoning,
                        activeThumbColor: AppTheme.notionBlue,
                        onChanged: (v) => setState(() => _reasoning = v),
                      ),
                    ),
                    if (_reasoning)
                      Padding(
                        padding: const EdgeInsets.only(left: 0, bottom: 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              '思考等级',
                              style: TextStyle(
                                fontSize: 11.5,
                                color: AppTheme.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              children:
                                  [
                                        ThinkingEffort.low,
                                        ThinkingEffort.medium,
                                        ThinkingEffort.high,
                                      ]
                                      .map(
                                        (level) => _buildLevelChip(
                                          level,
                                          _levels.contains(level),
                                        ),
                                      )
                                      .toList(),
                            ),
                          ],
                        ),
                      ),
                    _buildFieldRow(
                      label: '多模态 (图像输入)',
                      child: Switch(
                        value: _multimodal,
                        activeThumbColor: AppTheme.notionBlue,
                        onChanged: (v) => setState(() => _multimodal = v),
                      ),
                    ),
                    _buildFieldRow(
                      label: '上下文窗口 (tokens)',
                      child: _buildTextField(
                        controller: _contextController,
                        hint: '128000',
                        mono: true,
                        digitsOnly: true,
                        width: 160,
                      ),
                    ),
                    _buildFieldRow(
                      label: '最大输出 (tokens)',
                      child: _buildTextField(
                        controller: _maxTokensController,
                        hint: '8192',
                        mono: true,
                        digitsOnly: true,
                        width: 160,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // 底部操作栏
            Container(
              padding: const EdgeInsets.fromLTRB(20, 8, 16, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppTheme.border)),
              ),
              child: Row(
                children: [
                  if (!widget.isNew && widget.canDelete)
                    TextButton(
                      onPressed: () => Navigator.of(
                        context,
                      ).pop(const ModelProfileResult.deleted()),
                      child: const Text(
                        '删除模型',
                        style: TextStyle(color: AppTheme.error, fontSize: 12.5),
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text(
                      '取消',
                      style: TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12.5,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.notionBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 9,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    onPressed: _save,
                    child: Text(
                      widget.isNew ? '添加' : '保存',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLevelChip(ThinkingEffort level, bool selected) {
    return InkWell(
      onTap: () => _toggleLevel(level),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: selected
              ? AppTheme.notionBlue.withValues(alpha: 0.12)
              : AppTheme.paperWarmth,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected
                ? AppTheme.notionBlue.withValues(alpha: 0.4)
                : AppTheme.border,
          ),
        ),
        child: Text(
          level.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected ? AppTheme.notionBlue : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildFieldRow({required String label, required Widget child}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String hint,
    String? errorText,
    bool mono = false,
    bool digitsOnly = false,
    double? width,
  }) {
    return SizedBox(
      height: 36,
      width: width,
      child: TextField(
        controller: controller,
        style: TextStyle(fontSize: 12, fontFamily: mono ? 'monospace' : null),
        inputFormatters: digitsOnly
            ? [FilteringTextInputFormatter.digitsOnly]
            : null,
        decoration: InputDecoration(
          hintText: hint,
          errorText: errorText,
          errorStyle: const TextStyle(fontSize: 10, height: 1),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
        ),
      ),
    );
  }
}
