import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/theme/app_theme.dart';
import '../view_models/studio_view_model.dart';
import 'editable_slider.dart';
import 'pill_widgets.dart';
import 'studio_shared.dart';

/// 侧边栏页面三：局部修复与焦点特写配置页 (Notion 极简风格)
class InpaintPage extends StatefulWidget {
  final StudioViewModel viewModel;

  const InpaintPage({super.key, required this.viewModel});

  @override
  State<InpaintPage> createState() => _InpaintPageState();
}

class _InpaintPageState extends State<InpaintPage> {
  late final TextEditingController _promptController;
  late final TextEditingController _negativeController;

  @override
  void initState() {
    super.initState();
    _promptController = TextEditingController(
      text: widget.viewModel.inpaintParams.customPrompt,
    );
    _negativeController = TextEditingController(
      text: widget.viewModel.inpaintParams.customNegativePrompt,
    );
  }

  @override
  void didUpdateWidget(InpaintPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.viewModel.inpaintParams.customPrompt != _promptController.text) {
      _promptController.text = widget.viewModel.inpaintParams.customPrompt;
    }
    if (widget.viewModel.inpaintParams.customNegativePrompt !=
        _negativeController.text) {
      _negativeController.text =
          widget.viewModel.inpaintParams.customNegativePrompt;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final inpaint = vm.inpaintParams;
    final geometry = vm.inpaintGeometry;
    final isFocus = inpaint.mode == InpaintMode.focus;
    final isAiEdit = inpaint.mode == InpaintMode.aiEdit;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const PageHeader(title: '修复设置', subtitle: '局部重绘与高精度潜空间焦点特写'),
          const SizedBox(height: 16),

          // 1. 修复模式切换 (Notion Pill 选项)
          const SectionHeader('修复模式'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildModeOption(
                  mode: InpaintMode.focus,
                  label: '焦点特写',
                  subtitle: '超采样无损回贴',
                  isSelected: isFocus,
                  onTap: () => vm.setInpaintMode(InpaintMode.focus),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeOption(
                  mode: InpaintMode.standard,
                  label: '常规重绘',
                  subtitle: '整图尺度重绘',
                  isSelected: inpaint.mode == InpaintMode.standard,
                  onTap: () => vm.setInpaintMode(InpaintMode.standard),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildModeOption(
                  mode: InpaintMode.aiEdit,
                  label: 'AI 整图编辑',
                  subtitle: '外部绘图模型重绘',
                  isSelected: isAiEdit,
                  onTap: () => vm.setInpaintMode(InpaintMode.aiEdit),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // 2. 焦点几何信息卡 (Notion 极简浅灰底卡片)
          if (isFocus) ...[
            _buildGeometryCard(geometry),
            const SizedBox(height: 16),
          ],

          // 2b. AI 整图编辑绘图模型信息卡
          if (isAiEdit) ...[
            _buildAiEditCard(vm.imageEditModelInfo),
            const SizedBox(height: 16),
          ],

          // 2c. AI 整图编辑生成设置 (生图比例与分辨率，随请求透传给绘图模型)
          if (isAiEdit) ...[
            const SectionHeader('生成设置'),
            const SizedBox(height: 8),
            _buildAiEditOptionRow(
              label: '生图比例',
              child: PillDropdown<String>(
                value: inpaint.aiEditAspectRatio,
                items: const [
                  '',
                  '1:1',
                  '2:3',
                  '3:2',
                  '3:4',
                  '4:3',
                  '4:5',
                  '5:4',
                  '9:16',
                  '16:9',
                  '21:9',
                ],
                labelOf: (v) => v.isEmpty ? '跟随原图' : v,
                onChanged: vm.setInpaintAiEditAspectRatio,
              ),
            ),
            const SizedBox(height: 8),
            _buildAiEditOptionRow(
              label: '生图分辨率',
              child: PillDropdown<String>(
                value: inpaint.aiEditResolution,
                items: const ['', '1K', '2K', '4K'],
                labelOf: (v) => v.isEmpty ? '默认' : v,
                onChanged: vm.setInpaintAiEditResolution,
              ),
            ),
            const SizedBox(height: 8),
          ],

          // 3. 数值滑块调节 (NovelAI 重绘专属，AI 整图编辑不需要)
          if (isFocus && !isAiEdit) ...[
            EditableSliderInt(
              title: '外延上下文 (px)',
              value: inpaint.contextPadding.round(),
              min: 16,
              max: 192,
              onChanged: (v) => vm.setInpaintContextPadding(v.toDouble()),
            ),
            const SizedBox(height: 12),
          ],

          if (!isAiEdit) ...[
            EditableSliderDouble(
              title: '重绘强度',
              value: inpaint.strength,
              min: 0.0,
              max: 1.0,
              fractionDigits: 2,
              onChanged: vm.setInpaintStrength,
            ),
            const SizedBox(height: 12),

            EditableSliderDouble(
              title: '附加噪声',
              value: inpaint.noise,
              min: 0.0,
              max: 1.0,
              fractionDigits: 2,
              onChanged: vm.setInpaintNoise,
            ),
            const SizedBox(height: 16),
          ] else
            const SizedBox(height: 4),

          // 4. 提示词选项 (复用 / 自定义)
          SectionHeader(isAiEdit ? '修改指令设置' : '提示词设置'),
          const SizedBox(height: 8),

          _buildToggleRow(
            label: isAiEdit ? '复用主工作台正向词作为指令' : '复用主工作台正向词',
            value: inpaint.useMainPrompt,
            onChanged: vm.setInpaintUseMainPrompt,
          ),
          if (!inpaint.useMainPrompt) ...[
            const SizedBox(height: 6),
            _buildPromptInput(
              controller: _promptController,
              hint: isAiEdit
                  ? '输入自然语言修改指令，如: 把背景换成夕阳下的海滩...'
                  : '输入修复专属正向提示词...',
              onChanged: vm.setInpaintCustomPrompt,
            ),
          ],
          const SizedBox(height: 10),

          if (!isAiEdit) ...[
            _buildToggleRow(
              label: '复用主工作台负向词',
              value: inpaint.useMainNegative,
              onChanged: vm.setInpaintUseMainNegative,
            ),
            if (!inpaint.useMainNegative) ...[
              const SizedBox(height: 6),
              _buildPromptInput(
                controller: _negativeController,
                hint: '输入修复专属负向提示词...',
                onChanged: vm.setInpaintCustomNegativePrompt,
              ),
            ],
            const SizedBox(height: 20),
          ] else
            const SizedBox(height: 8),

          // 执行入口统一在左侧底部生成坞 (修复页签下显示为「开始修复」/「开始 AI 编辑」)
        ],
      ),
    );
  }

  /// AI 整图编辑选项行 (标签 + 右侧控件)
  Widget _buildAiEditOptionRow({required String label, required Widget child}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
        ),
        child,
      ],
    );
  }

  /// AI 整图编辑绘图模型信息卡 (未配置时给出引导提示)
  Widget _buildAiEditCard(
    ({String providerName, String modelName, String modelId})? info,
  ) {
    final configured = info != null;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted.withAlpha(120),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: configured ? AppTheme.border : Colors.orange.withAlpha(120),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.auto_awesome,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              const Text(
                '绘图模型',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: Colors.orange.withAlpha(100)),
                ),
                child: const Text(
                  '消耗绘图模型额度',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (configured)
            _buildInfoRow('供应商', info.providerName)
          else
            const Text(
              '未配置绘图模型。请到设置 → Models 页「AI 整图编辑」选择具备图像输出能力的模型供应商与模型 (如 nano banana / gpt-image)。',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            ),
          if (configured) ...[
            const SizedBox(height: 4),
            _buildInfoRow('模型', info.modelName),
            const SizedBox(height: 4),
            Text(
              info.modelId,
              style: const TextStyle(
                fontSize: 10.5,
                fontFamily: 'monospace',
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModeOption({
    required InpaintMode mode,
    required String label,
    required String subtitle,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? AppTheme.notionBlue.withAlpha(20)
              : AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected
                ? AppTheme.notionBlue.withAlpha(150)
                : AppTheme.border,
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                color: isSelected ? AppTheme.notionBlue : AppTheme.textPrimary,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10.5,
                color: isSelected
                    ? AppTheme.notionBlue.withAlpha(180)
                    : AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGeometryCard(InpaintGeometry geometry) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted.withAlpha(120),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.aspect_ratio_outlined,
                size: 14,
                color: AppTheme.textSecondary,
              ),
              const SizedBox(width: 6),
              const Text(
                '潜空间焦点几何',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: geometry.isOpusFree
                      ? Colors.green.withAlpha(25)
                      : Colors.orange.withAlpha(25),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                    color: geometry.isOpusFree
                        ? Colors.green.withAlpha(100)
                        : Colors.orange.withAlpha(100),
                  ),
                ),
                child: Text(
                  geometry.isOpusFree ? 'Opus 免费' : '需消耗点数',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: geometry.isOpusFree ? Colors.green : Colors.orange,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            '目标选区',
            '${geometry.focusBounds.width.round()} × ${geometry.focusBounds.height.round()} px',
          ),
          const SizedBox(height: 4),
          _buildInfoRow(
            '上下文外延',
            '${geometry.contextCrop.width.round()} × ${geometry.contextCrop.height.round()} px',
          ),
          const SizedBox(height: 4),
          _buildInfoRow(
            '请求分辨率',
            '${geometry.requestWidth} × ${geometry.requestHeight} (${geometry.scale.toStringAsFixed(2)}x 超采样)',
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
        ),
        Switch(
          value: value,
          onChanged: onChanged,
          activeThumbColor: AppTheme.notionBlue,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ],
    );
  }

  Widget _buildPromptInput({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        maxLines: 3,
        style: const TextStyle(fontSize: 12, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.all(8),
        ),
      ),
    );
  }
}
