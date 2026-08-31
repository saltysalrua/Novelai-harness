import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../studio/view_models/studio_view_model.dart';
import '../widgets/bill_settings_tab.dart';
import '../widgets/defaults_settings_tab.dart';
import '../widgets/general_settings_tab.dart';
import '../widgets/models_settings_tab.dart';
import '../widgets/presets_settings_tab.dart';

/// 全局设置弹窗：左侧导航 + 右侧配置详情 + 底部保存栏
///
/// 各标签页持有独立的草稿状态 (Draft)，由本壳统一创建、装配与聚合保存；
/// IndexedStack 保持全部页常驻，切换标签不丢输入状态。
class SettingsDialog extends StatefulWidget {
  final StudioViewModel viewModel;

  const SettingsDialog({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, StudioViewModel viewModel) {
    return showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => SettingsDialog(viewModel: viewModel),
    );
  }

  @override
  State<SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<SettingsDialog> {
  int _activeTabIndex = 0;

  late final GeneralSettingsDraft _generalDraft;
  late final ModelsSettingsDraft _modelsDraft;
  late final PresetsSettingsDraft _presetsDraft;
  late final DefaultsSettingsDraft _defaultsDraft;

  /// 标签页实例在 initState 构建一次并缓存：
  /// 1) 切换标签时 setState 传回 identical 实例，Element 层直接短路，隐藏页零重建；
  /// 2) 各页自持滚动状态，IndexedStack 仅保留激活页的滚动位置。
  late final List<Widget> _tabs;

  @override
  void initState() {
    super.initState();
    final cfg = widget.viewModel.config;
    _generalDraft = GeneralSettingsDraft(cfg);
    _modelsDraft = ModelsSettingsDraft(cfg);
    _presetsDraft = PresetsSettingsDraft(cfg);
    _defaultsDraft = DefaultsSettingsDraft(cfg);

    // 每页自行包裹滚动容器 (含原外层 28/8/28/20 内边距)，弹窗壳不再统一包 SingleChildScrollView
    _tabs = [
      GeneralSettingsTab(draft: _generalDraft),
      ModelsSettingsTab(viewModel: widget.viewModel, draft: _modelsDraft),
      PresetsSettingsTab(viewModel: widget.viewModel, draft: _presetsDraft),
      DefaultsSettingsTab(draft: _defaultsDraft),
      BillSettingsTab(viewModel: widget.viewModel),
    ];
  }

  @override
  void dispose() {
    _generalDraft.dispose();
    _modelsDraft.dispose();
    _presetsDraft.dispose();
    super.dispose();
  }

  void _handleSave() {
    _modelsDraft.syncFromForm();
    _presetsDraft.syncFromForm();

    final newConfig = widget.viewModel.config.copyWith(
      novelAiKey: _generalDraft.naiKeyController.text.trim(),
      saveDirectory: _generalDraft.saveDirController.text.trim(),
      opusFreeMode: _generalDraft.opusFreeMode,
      enableStreamPreview: _generalDraft.enableStreamPreview,
      enableTagAutocomplete: _generalDraft.enableTagAutocomplete,
      showTagTranslations: _generalDraft.showTagTranslations,
      showTagCategoryColors: _generalDraft.showTagCategoryColors,
      enableTagDictionaryAutoUpdate:
          _generalDraft.enableTagDictionaryAutoUpdate,
      enableImagePersistence: _generalDraft.enableImagePersistence,
      maxPersistentImages: _generalDraft.maxPersistentImages,
      llmProviders: _modelsDraft.providers,
      activeLlmProviderId: _modelsDraft.selectedProviderId,
      presets: _presetsDraft.presets,
      activePresetId: _presetsDraft.activePresetId,
      defaultModel: _defaultsDraft.model,
      defaultSampler: _defaultsDraft.sampler,
      defaultNoiseSchedule: _defaultsDraft.noiseSchedule,
      defaultSteps: _defaultsDraft.steps,
      defaultScale: _defaultsDraft.scale,
      agentMaxTurns: _defaultsDraft.agentMaxTurns.clamp(1, 100),
    );

    widget.viewModel.updateConfig(newConfig);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.8).clamp(520.0, 1600.0);
    final dialogHeight = (screenSize.height * 0.8).clamp(400.0, 1200.0);

    return Dialog(
      backgroundColor: AppTheme.pureWhite,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: dialogWidth,
          height: dialogHeight,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. 左侧导航栏 (Settings Categories)
              _buildSidebar(context),

              // 2. 右侧配置详情内容区
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // 右侧顶部标题栏与关闭按键
                    _buildContentHeader(context),

                    // 右侧设置项卡片列表 (缓存实例 + IndexedStack：切换零重建且不丢输入状态)
                    Expanded(
                      child: IndexedStack(
                        index: _activeTabIndex,
                        children: _tabs,
                      ),
                    ),

                    // 右侧底部保存 / 取消操作栏
                    _buildFooter(context),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 左侧导航栏
  Widget _buildSidebar(BuildContext context) {
    return Container(
      width: 200,
      decoration: const BoxDecoration(
        color: AppTheme.surfaceElevated,
        border: Border(right: BorderSide(color: AppTheme.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部小标题
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'SETTINGS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AppTheme.textMuted,
                letterSpacing: 0.8,
              ),
            ),
          ),

          // 导航选项卡
          _buildSidebarItem(
            index: 0,
            icon: Icons.tune_outlined,
            label: 'General',
          ),
          _buildSidebarItem(
            index: 1,
            icon: Icons.smart_toy_outlined,
            label: 'Models',
          ),
          _buildSidebarItem(
            index: 2,
            icon: Icons.psychology_outlined,
            label: 'Presets',
          ),
          _buildSidebarItem(
            index: 3,
            icon: Icons.layers_outlined,
            label: 'Defaults',
          ),
          _buildSidebarItem(
            index: 4,
            icon: Icons.receipt_long_outlined,
            label: 'Bill',
          ),
        ],
      ),
    );
  }

  Widget _buildSidebarItem({
    required int index,
    required IconData icon,
    required String label,
  }) {
    final isSelected = _activeTabIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: InkWell(
        onTap: () => setState(() => _activeTabIndex = index),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: isSelected
                ? AppTheme.stone.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? AppTheme.textPrimary : AppTheme.stone,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  color: isSelected
                      ? AppTheme.textPrimary
                      : AppTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 右侧顶部标头
  Widget _buildContentHeader(BuildContext context) {
    final (title, subtitle) = switch (_activeTabIndex) {
      0 => ('General', '配置 NovelAI 绘图服务凭证、本地存储目录与 Opus 免点保护。'),
      1 => ('Models', '按供应商管理大语言模型服务，在线拉取模型列表并自动匹配 models.dev 能力元数据。'),
      2 => ('Presets', '管理 Agent 预设，配置系统提示词、按需加载的 Skill 库与生图参数控制权限。'),
      3 => ('Defaults', '配置启动时的出厂默认生图模型、采样算法与步数引导。'),
      4 => ('Bill', '按周期统计各模型的 Token 用量账单，数据来自本地增量账本。'),
      _ => ('Settings', ''),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 20, 20, 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              size: 20,
              color: AppTheme.stone,
            ),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏
  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppTheme.border)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text(
              '取消',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12.5),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.notionBlue,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            onPressed: _handleSave,
            child: const Text(
              '保存设置',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
