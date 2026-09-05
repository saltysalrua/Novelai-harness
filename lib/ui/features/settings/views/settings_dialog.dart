import 'package:flutter/material.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_nav_tile.dart';
import '../../studio/view_models/studio_view_model.dart';
import '../widgets/bill_settings_tab.dart';
import '../widgets/defaults_settings_tab.dart';
import '../widgets/general_settings_tab.dart';
import '../widgets/models_settings_tab.dart';
import '../widgets/presets_settings_tab.dart';

/// 全局设置弹窗：左侧导航 + 右侧配置详情 + 底部保存栏
///
/// 各标签页持有独立的草稿状态 (Draft)，由本壳统一创建、装配与聚合保存；
/// IndexedStack 首次激活时懒构建标签页，构建后缓存实例，切换标签不丢输入状态。
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

  /// 标签页首次激活时懒构建并缓存：
  /// 1) 未访问页以 SizedBox.shrink() 占位，弹窗首帧只构建当前激活页，避免重页同步挤入首帧；
  /// 2) 访问过的页回投 identical 缓存实例，Element 层短路零重建，滚动位置与输入状态不丢。
  late final List<Widget Function()> _tabBuilders;
  final List<Widget?> _builtTabs = List<Widget?>.filled(5, null);

  @override
  void initState() {
    super.initState();
    final cfg = widget.viewModel.config;
    _generalDraft = GeneralSettingsDraft(cfg);
    _modelsDraft = ModelsSettingsDraft(cfg);
    _presetsDraft = PresetsSettingsDraft(cfg);
    _defaultsDraft = DefaultsSettingsDraft(cfg);

    // 每页自行包裹滚动容器 (含原外层 28/8/28/20 内边距)，弹窗壳不再统一包 SingleChildScrollView
    _tabBuilders = [
      () => GeneralSettingsTab(draft: _generalDraft),
      () => ModelsSettingsTab(viewModel: widget.viewModel, draft: _modelsDraft),
      () =>
          PresetsSettingsTab(viewModel: widget.viewModel, draft: _presetsDraft),
      () => DefaultsSettingsTab(draft: _defaultsDraft),
      () => BillSettingsTab(viewModel: widget.viewModel),
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
      themeMode: _generalDraft.themeMode,
      uiZoom: _generalDraft.uiZoom,
      enableStreamPreview: _generalDraft.enableStreamPreview,
      enableTagAutocomplete: _generalDraft.enableTagAutocomplete,
      showTagTranslations: _generalDraft.showTagTranslations,
      showTagCategoryColors: _generalDraft.showTagCategoryColors,
      enableTagDictionaryAutoUpdate:
          _generalDraft.enableTagDictionaryAutoUpdate,
      enableImagePersistence: _generalDraft.enableImagePersistence,
      maxPersistentImages: _generalDraft.maxPersistentImages,
      autoSaveImages: _generalDraft.autoSaveImages,
      llmProviders: _modelsDraft.providers,
      activeLlmProviderId: _modelsDraft.selectedProviderId,
      imageEditProviderId: _modelsDraft.imageEditProviderId,
      imageEditModelId: _modelsDraft.imageEditModelId,
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
    final colors = context.colors;
    final screenSize = MediaQuery.sizeOf(context);
    final dialogWidth = (screenSize.width * 0.8).clamp(520.0, 1600.0);
    final dialogHeight = (screenSize.height * 0.8).clamp(400.0, 1200.0);

    return Dialog(
      backgroundColor: colors.cardBackground,
      insetPadding: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colors.borderDefault),
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

                    // 右侧设置项卡片列表 (懒构建 + 缓存实例 + IndexedStack：首帧只建激活页，切页零重建且不丢输入状态)
                    Expanded(
                      child: IndexedStack(
                        index: _activeTabIndex,
                        children: List.generate(5, (i) {
                          if (i == _activeTabIndex) {
                            _builtTabs[i] ??= _tabBuilders[i]();
                          }
                          return _builtTabs[i] ?? const SizedBox.shrink();
                        }),
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
    final colors = context.colors;
    return Container(
      width: 200,
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        border: Border(right: BorderSide(color: colors.borderDefault)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 顶部小标题
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
            child: Text(
              'SETTINGS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: colors.textMuted,
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
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: AppNavTile(
        title: label,
        icon: icon,
        isSelected: _activeTabIndex == index,
        onTap: () => setState(() => _activeTabIndex = index),
      ),
    );
  }

  /// 右侧顶部标头
  Widget _buildContentHeader(BuildContext context) {
    final colors = context.colors;
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
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                    letterSpacing: -0.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(fontSize: 13, color: colors.textSecondary),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close_rounded, size: 20, color: colors.textMuted),
            tooltip: '关闭',
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// 底部操作栏
  Widget _buildFooter(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: colors.borderDefault)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(
              '取消',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.primary,
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
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
