import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../core/theme/app_theme.dart';
import 'settings_shared.dart';

/// Defaults 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class DefaultsSettingsDraft {
  DefaultsSettingsDraft(AppConfig config)
    : model = config.defaultModel,
      sampler = config.defaultSampler,
      noiseSchedule = config.defaultNoiseSchedule,
      steps = config.defaultSteps,
      scale = config.defaultScale,
      agentMaxTurns = config.agentMaxTurns;

  NaiModel model;
  NaiSampler sampler;
  NoiseSchedule noiseSchedule;
  int steps;
  double scale;

  /// Agent 单次对话最大工具调用轮数 (1..100)
  int agentMaxTurns;
}

/// Defaults 页：启动出厂默认生图模型、采样算法与步数引导
class DefaultsSettingsTab extends StatefulWidget {
  final DefaultsSettingsDraft draft;

  const DefaultsSettingsTab({super.key, required this.draft});

  @override
  State<DefaultsSettingsTab> createState() => _DefaultsSettingsTabState();
}

class _DefaultsSettingsTabState extends State<DefaultsSettingsTab> {
  DefaultsSettingsDraft get _draft => widget.draft;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SettingsGroupTitle('Model & Sampler'),
          SettingsCard(
            title: '默认生图模型',
            subtitle: '应用启动或参数重置时的默认出厂模型',
            control: SettingsDropdown<NaiModel>(
              value: _draft.model,
              items: NaiModel.values,
              labelBuilder: (m) => m.label,
              onChanged: (val) {
                if (val != null) setState(() => _draft.model = val);
              },
            ),
          ),
          SettingsCard(
            title: '默认采样算法',
            subtitle: '生图时默认使用的降噪采样器',
            control: SettingsDropdown<NaiSampler>(
              value: _draft.sampler,
              items: NaiSampler.values,
              labelBuilder: (s) => s.label,
              onChanged: (val) {
                if (val != null) setState(() => _draft.sampler = val);
              },
            ),
          ),
          SettingsCard(
            title: '默认噪声调度',
            subtitle: '采样降噪过程中的时间步长调度算法',
            control: SettingsDropdown<NoiseSchedule>(
              value: _draft.noiseSchedule,
              items: NoiseSchedule.values,
              labelBuilder: (n) => n.label,
              onChanged: (val) {
                if (val != null) setState(() => _draft.noiseSchedule = val);
              },
            ),
          ),

          const SizedBox(height: 12),
          const SettingsGroupTitle('Default Steps & Scale'),
          SettingsCard(
            title: '默认步数 (Steps)',
            subtitle: '初始采样迭代步数',
            control: SizedBox(
              width: 160,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 16),
                    onPressed: _draft.steps > 1
                        ? () => setState(() => _draft.steps--)
                        : null,
                  ),
                  Text(
                    '${_draft.steps}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: _draft.steps < 50
                        ? () => setState(() => _draft.steps++)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          SettingsCard(
            title: '默认 CFG Scale',
            subtitle: '提示词引导强度 (当前: ${_draft.scale.toStringAsFixed(1)})',
            control: SizedBox(
              width: 180,
              child: Slider(
                value: _draft.scale,
                min: 1.0,
                max: 20.0,
                divisions: 38,
                activeColor: AppTheme.notionBlue,
                onChanged: (val) => setState(() => _draft.scale = val),
              ),
            ),
          ),

          const SizedBox(height: 12),
          const SettingsGroupTitle('Agent Loop'),
          SettingsCard(
            title: 'Agent 最大工具轮数',
            subtitle: '单次对话允许的工具链式调用轮数，达到后自动收尾总结',
            control: SizedBox(
              width: 160,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove_rounded, size: 16),
                    onPressed: _draft.agentMaxTurns > 1
                        ? () => setState(() => _draft.agentMaxTurns--)
                        : null,
                  ),
                  Text(
                    '${_draft.agentMaxTurns}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'monospace',
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add_rounded, size: 16),
                    onPressed: _draft.agentMaxTurns < 100
                        ? () => setState(() => _draft.agentMaxTurns++)
                        : null,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
