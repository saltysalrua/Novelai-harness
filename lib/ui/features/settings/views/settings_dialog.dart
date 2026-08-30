import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/agent_tool.dart';
import '../../../../core/harness/types.dart';
import '../../../core/theme/app_theme.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/llm_model_fetcher.dart';
import '../../../../data/services/usage_ledger_service.dart';
import '../../studio/view_models/studio_view_model.dart';
import '../widgets/model_card.dart';
import '../widgets/model_profile_dialog.dart';
import '../widgets/skill_card.dart';
import '../widgets/skill_editor_dialog.dart';
import '../widgets/tool_card.dart';
import '../widgets/tool_editor_dialog.dart';

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

  // NovelAI & General Controllers
  late TextEditingController _naiKeyController;
  late TextEditingController _saveDirController;
  late bool _opusFreeMode;
  late bool _enableStreamPreview;

  // LLM Providers State
  late List<LlmProviderConfig> _providers;
  late String _selectedProviderId;
  late TextEditingController _providerNameController;
  late TextEditingController _llmBaseUrlController;
  late TextEditingController _llmApiKeyController;
  late LlmProtocol _selectedProtocol;

  // Online Fetch State
  final LlmModelFetcher _modelFetcher = LlmModelFetcher();
  bool _isFetchingModels = false;
  String? _fetchStatusMessage;
  bool _isFetchSuccess = false;

  // Presets State
  late List<AgentPreset> _presets;
  late String _selectedPresetId;
  late String _activePresetId;
  late TextEditingController _presetNameController;
  late TextEditingController _presetDescController;
  late TextEditingController _presetPromptController;

  // Defaults State
  late NaiModel _defaultModel;
  late NaiSampler _defaultSampler;
  late NoiseSchedule _defaultNoiseSchedule;
  late int _defaultSteps;
  late double _defaultScale;

  // Bill State
  BillPeriod _billPeriod = BillPeriod.today;

  bool _obscureNaiKey = true;
  bool _obscureLlmKey = true;

  @override
  void initState() {
    super.initState();
    final cfg = widget.viewModel.config;

    _naiKeyController = TextEditingController(text: cfg.novelAiKey);
    _saveDirController = TextEditingController(text: cfg.saveDirectory);
    _opusFreeMode = cfg.opusFreeMode;
    _enableStreamPreview = cfg.enableStreamPreview;

    // 初始化供应商列表
    _providers =
        (cfg.llmProviders.isNotEmpty
                ? cfg.llmProviders
                : LlmProviderConfig.defaultProviders)
            .map((p) => p.copyWith())
            .toList();

    _selectedProviderId = cfg.activeLlmProviderId;
    if (!_providers.any((p) => p.id == _selectedProviderId)) {
      _selectedProviderId = _providers.first.id;
    }

    final activeProvider = _providers.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => _providers.first,
    );

    _providerNameController = TextEditingController(text: activeProvider.name);
    _llmBaseUrlController = TextEditingController(text: activeProvider.baseUrl);
    _llmApiKeyController = TextEditingController(text: activeProvider.apiKey);
    _selectedProtocol = activeProvider.protocol;

    _llmBaseUrlController.addListener(_onFieldChanged);
    _providerNameController.addListener(_onFieldChanged);

    // 初始化预设列表
    _presets = (cfg.presets.isNotEmpty ? cfg.presets : BuiltinPresets.all)
        .map((p) => p.copyWith())
        .toList();
    _activePresetId = cfg.activePresetId;
    if (!_presets.any((p) => p.id == _activePresetId)) {
      _activePresetId = _presets.first.id;
    }
    _selectedPresetId = _activePresetId;

    final currentSelectedPreset = _presets.firstWhere(
      (p) => p.id == _selectedPresetId,
      orElse: () => _presets.first,
    );

    _presetNameController = TextEditingController(
      text: currentSelectedPreset.name,
    );
    _presetDescController = TextEditingController(
      text: currentSelectedPreset.description,
    );
    _presetPromptController = TextEditingController(
      text: currentSelectedPreset.systemPrompt,
    );

    _presetNameController.addListener(_onFieldChanged);
    _presetDescController.addListener(_onFieldChanged);
    _presetPromptController.addListener(_onFieldChanged);

    _defaultModel = cfg.defaultModel;
    _defaultSampler = cfg.defaultSampler;
    _defaultNoiseSchedule = cfg.defaultNoiseSchedule;
    _defaultSteps = cfg.defaultSteps;
    _defaultScale = cfg.defaultScale;
  }

  void _syncActivePresetFromForm() {
    final idx = _presets.indexWhere((p) => p.id == _selectedPresetId);
    if (idx >= 0) {
      _presets[idx] = _presets[idx].copyWith(
        name: _presetNameController.text.trim().isEmpty
            ? '自定义预设'
            : _presetNameController.text.trim(),
        description: _presetDescController.text.trim(),
        systemPrompt: _presetPromptController.text.trim(),
      );
    }
  }

  void _loadPresetToForm(AgentPreset preset) {
    _selectedPresetId = preset.id;
    _presetNameController.text = preset.name;
    _presetDescController.text = preset.description;
    _presetPromptController.text = preset.systemPrompt;
  }

  void _switchPreset(String newPresetId) {
    if (newPresetId == _selectedPresetId) return;
    _syncActivePresetFromForm();
    final target = _presets.firstWhere(
      (p) => p.id == newPresetId,
      orElse: () => _presets.first,
    );
    setState(() {
      _loadPresetToForm(target);
    });
  }

  void _setActivePreset(String presetId) {
    if (_activePresetId == presetId) return;
    setState(() {
      _activePresetId = presetId;
    });
  }

  void _addNewPreset() {
    _syncActivePresetFromForm();
    final newId = 'preset_${DateTime.now().millisecondsSinceEpoch}';
    final allTools = widget.viewModel.availableTools
        .map((t) => t.name)
        .toList();
    final newPreset = AgentPreset(
      id: newId,
      name: '新预设 ${_presets.length + 1}',
      description: '自定义 Agent 预设描述',
      systemPrompt: '你是由 NovelAI Harness 驱动的绘画创作助手。',
      enabledSkillIds: const ['v5-architect'],
      enabledToolNames: allTools,
      allowedModifiableParams: PresetParamKeys.all,
      isBuiltin: false,
    );

    setState(() {
      _presets.add(newPreset);
      _loadPresetToForm(newPreset);
    });
  }

  void _duplicatePreset(AgentPreset preset) {
    _syncActivePresetFromForm();
    final clone = preset.copyWith(
      id: 'preset_${DateTime.now().millisecondsSinceEpoch}',
      name: '${preset.name} (副本)',
      isBuiltin: false,
    );
    setState(() {
      _presets.add(clone);
      _loadPresetToForm(clone);
    });
  }

  void _deletePreset(String presetId) {
    if (_presets.length <= 1) return;
    _syncActivePresetFromForm();
    setState(() {
      _presets.removeWhere((p) => p.id == presetId);
      if (_selectedPresetId == presetId) {
        _loadPresetToForm(_presets.first);
      }
      if (_activePresetId == presetId) {
        _activePresetId = _presets.first.id;
      }
    });
  }

  void _toggleSkillInSelectedPreset(String skillId, bool enable) {
    _syncActivePresetFromForm();
    final idx = _presets.indexWhere((p) => p.id == _selectedPresetId);
    if (idx < 0) return;
    final current = _presets[idx];
    final skills = current.enabledSkillIds.toList();
    if (enable) {
      if (!skills.contains(skillId)) skills.add(skillId);
    } else {
      skills.remove(skillId);
    }
    setState(() {
      _presets[idx] = current.copyWith(enabledSkillIds: skills);
    });
  }

  void _toggleToolInSelectedPreset(String toolName, bool enable) {
    _syncActivePresetFromForm();
    final idx = _presets.indexWhere((p) => p.id == _selectedPresetId);
    if (idx < 0) return;
    final current = _presets[idx];
    final tools = current.enabledToolNames.toList();
    if (enable) {
      if (!tools.contains(toolName)) tools.add(toolName);
    } else {
      tools.remove(toolName);
    }
    setState(() {
      _presets[idx] = current.copyWith(enabledToolNames: tools);
    });
  }

  void _toggleParamInSelectedPreset(String paramKey, bool enable) {
    _syncActivePresetFromForm();
    final idx = _presets.indexWhere((p) => p.id == _selectedPresetId);
    if (idx < 0) return;
    final current = _presets[idx];
    final params = current.allowedModifiableParams.toList();
    if (enable) {
      if (!params.contains(paramKey)) params.add(paramKey);
    } else {
      params.remove(paramKey);
    }
    setState(() {
      _presets[idx] = current.copyWith(allowedModifiableParams: params);
    });
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _llmBaseUrlController.removeListener(_onFieldChanged);
    _providerNameController.removeListener(_onFieldChanged);
    _presetNameController.removeListener(_onFieldChanged);
    _presetDescController.removeListener(_onFieldChanged);
    _presetPromptController.removeListener(_onFieldChanged);

    _naiKeyController.dispose();
    _saveDirController.dispose();
    _providerNameController.dispose();
    _llmBaseUrlController.dispose();
    _llmApiKeyController.dispose();
    _presetNameController.dispose();
    _presetDescController.dispose();
    _presetPromptController.dispose();
    super.dispose();
  }

  void _syncActiveProviderFromForm() {
    final idx = _providers.indexWhere((p) => p.id == _selectedProviderId);
    if (idx >= 0) {
      _providers[idx] = _providers[idx].copyWith(
        name: _providerNameController.text.trim().isEmpty
            ? '自定义供应商'
            : _providerNameController.text.trim(),
        baseUrl: _llmBaseUrlController.text.trim(),
        protocol: _selectedProtocol,
        apiKey: _llmApiKeyController.text.trim(),
      );
    }
  }

  void _loadProviderToForm(LlmProviderConfig provider) {
    _selectedProviderId = provider.id;
    _providerNameController.text = provider.name;
    _llmBaseUrlController.text = provider.baseUrl;
    _selectedProtocol = provider.protocol;
    _llmApiKeyController.text = provider.apiKey;
    _fetchStatusMessage = null;
  }

  void _switchProvider(String newProviderId) {
    if (newProviderId == _selectedProviderId) return;
    _syncActiveProviderFromForm();
    final target = _providers.firstWhere((p) => p.id == newProviderId);
    setState(() {
      _loadProviderToForm(target);
    });
  }

  void _addNewProvider() {
    _syncActiveProviderFromForm();
    final newId = 'provider_${DateTime.now().millisecondsSinceEpoch}';
    final newProvider = LlmProviderConfig(
      id: newId,
      name: '新供应商 ${_providers.length + 1}',
      baseUrl: 'https://api.openai.com/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'gpt-4o',
      models: const [
        LlmModelConfig(
          id: 'gpt-4o',
          name: 'GPT-4o',
          reasoning: false,
          temperature: 0.7,
        ),
      ],
    );

    setState(() {
      _providers.add(newProvider);
      _loadProviderToForm(newProvider);
    });
  }

  void _deleteCurrentProvider() {
    if (_providers.length <= 1) return;
    setState(() {
      _providers.removeWhere((p) => p.id == _selectedProviderId);
      _loadProviderToForm(_providers.first);
    });
  }

  /// 点击模型卡片，切换为当前生效模型
  void _setActiveModel(String modelId) {
    final pIdx = _providers.indexWhere((p) => p.id == _selectedProviderId);
    if (pIdx < 0 || _providers[pIdx].activeModelId == modelId) return;
    setState(() {
      _providers[pIdx] = _providers[pIdx].copyWith(activeModelId: modelId);
    });
  }

  /// 点击卡片设置按钮，编辑单个模型档案
  Future<void> _editModel(LlmModelConfig model) async {
    final pIdx = _providers.indexWhere((p) => p.id == _selectedProviderId);
    if (pIdx < 0) return;
    final provider = _providers[pIdx];

    final result = await ModelProfileDialog.show(
      context,
      model: model,
      canDelete: provider.models.length > 1,
    );
    if (!mounted || result == null) return;

    setState(() {
      if (result.delete) {
        _removeModelInternal(pIdx, model.id);
      } else {
        final updated = result.model!;
        final models = provider.models
            .where((m) => m.id != updated.id || m.id == model.id)
            .map((m) => m.id == model.id ? updated : m)
            .toList();
        var activeId = provider.activeModelId;
        if (activeId == model.id) activeId = updated.id;
        _providers[pIdx] = provider.copyWith(
          models: models,
          activeModelId: activeId,
        );
      }
    });
  }

  /// 添加新模型
  Future<void> _addModel() async {
    _syncActiveProviderFromForm();
    final pIdx = _providers.indexWhere((p) => p.id == _selectedProviderId);
    if (pIdx < 0) return;

    final result = await ModelProfileDialog.show(
      context,
      model: const LlmModelConfig(id: '', name: ''),
      isNew: true,
      canDelete: false,
    );
    if (!mounted || result == null || result.delete || result.model == null) {
      return;
    }

    setState(() {
      final provider = _providers[pIdx];
      final newModel = result.model!;
      final models = [
        ...provider.models.where((m) => m.id != newModel.id),
        newModel,
      ];
      _providers[pIdx] = provider.copyWith(
        models: models,
        activeModelId: newModel.id,
      );
    });
  }

  /// 删除指定模型 (至少保留一个)
  void _deleteModel(String modelId) {
    final pIdx = _providers.indexWhere((p) => p.id == _selectedProviderId);
    if (pIdx < 0) return;
    setState(() {
      _removeModelInternal(pIdx, modelId);
    });
  }

  void _removeModelInternal(int pIdx, String modelId) {
    final provider = _providers[pIdx];
    if (provider.models.length <= 1) return;
    final filtered = provider.models.where((m) => m.id != modelId).toList();
    if (filtered.length == provider.models.length) return;
    _providers[pIdx] = provider.copyWith(
      models: filtered,
      activeModelId: provider.activeModelId == modelId
          ? filtered.first.id
          : provider.activeModelId,
    );
  }

  /// 在线拉取远程供应商模型列表
  Future<void> _fetchRemoteModelsOnline() async {
    final baseUrl = _llmBaseUrlController.text.trim();
    final apiKey = _llmApiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      setState(() {
        _isFetchSuccess = false;
        _fetchStatusMessage = '请先填写有效的 API 基础 URL';
      });
      return;
    }

    setState(() {
      _isFetchingModels = true;
      _fetchStatusMessage = null;
    });

    try {
      _syncActiveProviderFromForm();
      final pIdx = _providers.indexWhere((p) => p.id == _selectedProviderId);
      final existingModels = pIdx >= 0
          ? _providers[pIdx].models
          : const <LlmModelConfig>[];

      final result = await _modelFetcher.fetchRemoteModels(
        baseUrl: baseUrl,
        protocol: _selectedProtocol,
        apiKey: apiKey,
        existingModels: existingModels,
      );

      if (pIdx >= 0) {
        // 尝试保留之前选中的模型，若不在列表中则选中首个
        final previousId = _providers[pIdx].activeModelId;
        final targetActiveId = result.models.any((m) => m.id == previousId)
            ? previousId
            : result.models.first.id;

        _providers[pIdx] = _providers[pIdx].copyWith(
          models: result.models,
          activeModelId: targetActiveId,
        );

        // 拉取结果立即写盘持久化，避免忘记点保存导致模型列表丢失
        await widget.viewModel.persistLlmProviders(
          _providers,
          _selectedProviderId,
        );
      }

      if (!mounted) return;
      setState(() {
        _isFetchingModels = false;
        _isFetchSuccess = true;
        _fetchStatusMessage =
            '成功拉取 ${result.models.length} 个模型'
            '${result.enrichedCount > 0 ? '，${result.enrichedCount} 个已匹配 models.dev 元数据' : ''}';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingModels = false;
        _isFetchSuccess = false;
        _fetchStatusMessage = '$e';
      });
    }
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
    _syncActiveProviderFromForm();
    _syncActivePresetFromForm();

    final newConfig = widget.viewModel.config.copyWith(
      novelAiKey: _naiKeyController.text.trim(),
      saveDirectory: _saveDirController.text.trim(),
      opusFreeMode: _opusFreeMode,
      enableStreamPreview: _enableStreamPreview,
      llmProviders: _providers,
      activeLlmProviderId: _selectedProviderId,
      presets: _presets,
      activePresetId: _activePresetId,
      defaultModel: _defaultModel,
      defaultSampler: _defaultSampler,
      defaultNoiseSchedule: _defaultNoiseSchedule,
      defaultSteps: _defaultSteps,
      defaultScale: _defaultScale,
    );

    widget.viewModel.updateConfig(newConfig);
    Navigator.of(context).pop();
  }

  String _calculateFullEndpoint(String baseUrl, LlmProtocol protocol) {
    var base = baseUrl.trim();
    if (base.isEmpty) return '未配置 URL';
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final path = protocol.defaultPath;
    if (base.endsWith(path)) return base;
    return '$base$path';
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

                    // 右侧滚动设置项卡片列表
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(28, 8, 28, 20),
                        child: _buildActiveTabContent(),
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
    String title;
    String subtitle;

    switch (_activeTabIndex) {
      case 0:
        title = 'General';
        subtitle = '配置 NovelAI 绘图服务凭证、本地存储目录与 Opus 免点保护。';
        break;
      case 1:
        title = 'Models';
        subtitle = '按供应商管理大语言模型服务，在线拉取模型列表并自动匹配 models.dev 能力元数据。';
        break;
      case 2:
        title = 'Presets';
        subtitle = '管理 Agent 预设，配置系统提示词、按需加载的 Skill 库与生图参数控制权限。';
        break;
      case 3:
        title = 'Defaults';
        subtitle = '配置启动时的出厂默认生图模型、采样算法与步数引导。';
        break;
      case 4:
        title = 'Bill';
        subtitle = '按周期统计各模型的 Token 用量账单，数据来自本地增量账本。';
        break;
      default:
        title = 'Settings';
        subtitle = '';
    }

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

  /// 当前选中的设置页内容
  Widget _buildActiveTabContent() {
    switch (_activeTabIndex) {
      case 0:
        return _buildGeneralTab();
      case 1:
        return _buildModelsTab();
      case 2:
        return _buildPresetsTab();
      case 3:
        return _buildDefaultsTab();
      case 4:
        return _buildBillTab();
      default:
        return const SizedBox.shrink();
    }
  }

  /// Tab 2: Presets 预设管理设置 (对齐 Models 页总选择+小卡片架构)
  Widget _buildPresetsTab() {
    _syncActivePresetFromForm();
    final currentPreset = _presets.firstWhere(
      (p) => p.id == _selectedPresetId,
      orElse: () => _presets.first,
    );
    final isSelectedActive = currentPreset.id == _activePresetId;

    final availableSkills = widget.viewModel.availableSkills;
    final availableTools = widget.viewModel.availableTools;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 顶部总选择与管理坞 (Preset Selection Bar - 对齐 Models Tab)
        _buildGroupTitle('Preset Selection'),
        _buildSettingCard(
          title: '当前预设',
          subtitle: '选择要配置的 Agent 预设（系统提示词、可用技能、工具与参数权限）',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 预设下拉选择框
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.paperWarmth,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedPresetId,
                    items: _presets
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p.id,
                            child: Row(
                              children: [
                                Text(
                                  p.name,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppTheme.textPrimary,
                                  ),
                                ),
                                if (p.id == _activePresetId) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 5,
                                      vertical: 1.5,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.notionBlue,
                                      borderRadius: BorderRadius.circular(3),
                                    ),
                                    child: const Text(
                                      '当前默认',
                                      style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.white,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _switchPreset(val);
                    },
                    icon: const Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: AppTheme.stone,
                    ),
                    dropdownColor: AppTheme.pureWhite,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 设为默认按钮
              if (!isSelectedActive)
                OutlinedButton(
                  onPressed: () => _setActivePreset(currentPreset.id),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: const Text(
                    '设为当前默认',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),

              const SizedBox(width: 6),

              // 新建预设按钮
              OutlinedButton.icon(
                onPressed: _addNewPreset,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: AppTheme.textPrimary,
                ),
                label: const Text(
                  '新建',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),

              const SizedBox(width: 6),

              // 复制按钮
              OutlinedButton.icon(
                onPressed: () => _duplicatePreset(currentPreset),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(
                  Icons.copy_rounded,
                  size: 14,
                  color: AppTheme.textPrimary,
                ),
                label: const Text(
                  '复制',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),

              // 删除按钮 (多于1个且非内置时可删)
              if (_presets.length > 1 && !currentPreset.isBuiltin) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: Colors.redAccent,
                  ),
                  tooltip: '删除此预设',
                  onPressed: () => _deletePreset(currentPreset.id),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 2. 预设基础信息与系统提示词
        _buildGroupTitle('Preset Profile & System Prompt'),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '预设显示名称',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _presetNameController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '如 V5 自然语言架构师',
                            filled: true,
                            fillColor: AppTheme.paperWarmth,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: AppTheme.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: AppTheme.border,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 6,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '预设描述',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _presetDescController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            hintText: '如 擅长 V5 自然语言散文提示词...',
                            filled: true,
                            fillColor: AppTheme.paperWarmth,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: AppTheme.border,
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(6),
                              borderSide: const BorderSide(
                                color: AppTheme.border,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                '系统提示词 (System Prompt - 作为对话首要根基指令)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                ),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _presetPromptController,
                maxLines: 6,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
                decoration: InputDecoration(
                  hintText: '输入 AI 助手的核心人设与工作流指引...',
                  filled: true,
                  fillColor: AppTheme.paperWarmth,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(6),
                    borderSide: const BorderSide(color: AppTheme.border),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // 3. 可用 Skill 库 (Pi 标准按需加载小卡片组)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildGroupTitle('Available Skills'),
            Row(
              children: [
                OutlinedButton.icon(
                  onPressed: _openImportSkillDialog,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: const Icon(Icons.file_upload_outlined, size: 14),
                  label: const Text(
                    '导入 SKILL.md',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                OutlinedButton.icon(
                  onPressed: _openNewSkillDialog,
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: AppTheme.border),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  icon: const Icon(Icons.add_rounded, size: 15),
                  label: const Text(
                    '新建 Skill',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: availableSkills.map((skill) {
            final isEnabled = currentPreset.enabledSkillIds.contains(skill.id);
            return SkillCard(
              skill: skill,
              isEnabled: isEnabled,
              onToggle: (val) => _toggleSkillInSelectedPreset(skill.id, val),
              onEdit: (s) => _openEditSkillDialog(s),
              onExport: (s) => _exportSkillMd(s),
              onDelete: !skill.isBuiltin ? () => _deleteSkill(skill.id) : null,
            );
          }).toList(),
        ),

        const SizedBox(height: 18),

        // 4. 开放工具库 (Enabled Tools 小卡片组)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _buildGroupTitle('Enabled Tools'),
            OutlinedButton.icon(
              onPressed: _openNewToolDialog,
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: AppTheme.border),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
              icon: const Icon(Icons.add_rounded, size: 15),
              label: const Text(
                '新建自定义工具',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: availableTools.map((tool) {
            final isEnabled = currentPreset.isToolEnabled(tool.name);
            return ToolCard(
              tool: tool,
              isEnabled: isEnabled,
              onToggle: (val) => _toggleToolInSelectedPreset(tool.name, val),
              onInspectSchema: (t) => _openInspectToolSchemaDialog(t),
              onEditCustomTool: tool is CustomAgentTool
                  ? (t) => _openEditToolDialog(t)
                  : null,
              onDelete: !tool.isBuiltin ? () => _deleteTool(tool.name) : null,
            );
          }).toList(),
        ),

        const SizedBox(height: 18),

        // 5. 生图参数控制权限 (Modifiable Parameters)
        _buildGroupTitle('Modifiable Parameters'),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.pureWhite,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.border),
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PresetParamKeys.all.map((key) {
              final isAllowed = currentPreset.isParamModifiable(key);
              final label = PresetParamKeys.getLabel(key);
              return FilterChip(
                label: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isAllowed ? FontWeight.w600 : FontWeight.normal,
                    color: isAllowed
                        ? AppTheme.notionBlue
                        : AppTheme.textPrimary,
                  ),
                ),
                selected: isAllowed,
                onSelected: (val) => _toggleParamInSelectedPreset(key, val),
                backgroundColor: AppTheme.surfaceVariant,
                selectedColor: AppTheme.notionBlue.withValues(alpha: 0.12),
                checkmarkColor: AppTheme.notionBlue,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(6),
                  side: BorderSide(
                    color: isAllowed
                        ? AppTheme.notionBlue.withValues(alpha: 0.5)
                        : AppTheme.border,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Future<void> _openNewSkillDialog() async {
    final result = await showDialog<Skill>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => const SkillEditorDialog(),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomSkill(result);
      _toggleSkillInSelectedPreset(result.id, true);
    }
  }

  Future<void> _openImportSkillDialog() async {
    final result = await showDialog<Skill>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => const SkillEditorDialog(isImportMode: true),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomSkill(result);
      _toggleSkillInSelectedPreset(result.id, true);
    }
  }

  Future<void> _openEditSkillDialog(Skill skill) async {
    final result = await showDialog<Skill>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => SkillEditorDialog(skill: skill),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomSkill(result);
      setState(() {});
    }
  }

  void _exportSkillMd(Skill skill) {
    Clipboard.setData(ClipboardData(text: skill.toSkillMd()));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制 Skill [${skill.name}] 为标准 SKILL.md 至剪贴板'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _deleteSkill(String skillId) async {
    await widget.viewModel.deleteCustomSkill(skillId);
    _toggleSkillInSelectedPreset(skillId, false);
  }

  Future<void> _openNewToolDialog() async {
    final result = await showDialog<CustomAgentTool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => const ToolEditorDialog(),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomTool(result);
      _toggleToolInSelectedPreset(result.name, true);
    }
  }

  void _openInspectToolSchemaDialog(AgentTool tool) {
    showDialog(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) =>
          ToolEditorDialog(tool: tool, isReadOnlySchemaView: true),
    );
  }

  Future<void> _openEditToolDialog(CustomAgentTool tool) async {
    final result = await showDialog<CustomAgentTool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => ToolEditorDialog(tool: tool),
    );
    if (result != null && mounted) {
      await widget.viewModel.saveCustomTool(result);
      setState(() {});
    }
  }

  Future<void> _deleteTool(String toolName) async {
    await widget.viewModel.deleteCustomTool(toolName);
    _toggleToolInSelectedPreset(toolName, false);
  }

  /// Tab 0: General 通用设置
  Widget _buildGeneralTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupTitle('NovelAI Service'),
        _buildSettingCard(
          title: 'NovelAI API Key',
          subtitle: '官方 API 凭证 (pst-...)，用于图像生成与体力池同步',
          control: SizedBox(
            width: 250,
            height: 36,
            child: TextField(
              controller: _naiKeyController,
              obscureText: _obscureNaiKey,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'pst-...',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureNaiKey ? Icons.visibility_off : Icons.visibility,
                    size: 15,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () =>
                      setState(() => _obscureNaiKey = !_obscureNaiKey),
                ),
              ),
            ),
          ),
        ),
        _buildSettingCard(
          title: '本地存储目录',
          subtitle: '生成的高清图像与元数据自动保存至此路径',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 220,
                height: 36,
                child: TextField(
                  controller: _saveDirController,
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
              OutlinedButton.icon(
                onPressed: _pickDirectory,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(
                  Icons.folder_open_rounded,
                  size: 15,
                  color: AppTheme.textPrimary,
                ),
                label: const Text(
                  '选择',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
        ),

        _buildSettingCard(
          title: '实时生图预览',
          subtitle: '生图过程中接收并实时渲染中间去噪步数预览图 (Stream Preview)',
          control: Switch(
            value: _enableStreamPreview,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) => setState(() => _enableStreamPreview = val),
          ),
        ),

        const SizedBox(height: 12),
        _buildGroupTitle('Protection'),
        _buildSettingCard(
          title: 'Opus 免点数保护',
          subtitle: '自动将默认参数限制在免费区间内 (像素 <= 1048576 且 步数 <= 28)',
          control: Switch(
            value: _opusFreeMode,
            activeThumbColor: AppTheme.notionBlue,
            onChanged: (val) => setState(() => _opusFreeMode = val),
          ),
        ),
      ],
    );
  }

  /// Tab 1: Models AI 助手多供应商与多模型设置
  Widget _buildModelsTab() {
    final fullEndpoint = _calculateFullEndpoint(
      _llmBaseUrlController.text,
      _selectedProtocol,
    );

    final currentProvider = _providers.firstWhere(
      (p) => p.id == _selectedProviderId,
      orElse: () => _providers.first,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 供应商切换与管理
        _buildGroupTitle('Provider Selection'),
        _buildSettingCard(
          title: '当前供应商',
          subtitle: '选择要配置的 AI 服务商，或添加自定义供应商',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 供应商选择下拉框
              Container(
                height: 34,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.paperWarmth,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedProviderId,
                    items: _providers
                        .map(
                          (p) => DropdownMenuItem<String>(
                            value: p.id,
                            child: Text(
                              p.name,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) _switchProvider(val);
                    },
                    icon: const Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: AppTheme.stone,
                    ),
                    dropdownColor: AppTheme.pureWhite,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 新建供应商按钮
              OutlinedButton.icon(
                onPressed: _addNewProvider,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(
                  Icons.add_rounded,
                  size: 15,
                  color: AppTheme.textPrimary,
                ),
                label: const Text(
                  '新建',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),

              // 删除按钮 (多于1个时显示)
              if (_providers.length > 1) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppTheme.stone,
                  ),
                  tooltip: '删除当前供应商',
                  onPressed: _deleteCurrentProvider,
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),
        // 2. 供应商基本信息与端点
        _buildGroupTitle('Provider Profile & Endpoint'),
        _buildSettingCard(
          title: '供应商名称',
          subtitle: '在界面与下拉菜单中显示的自定义标识',
          control: SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: _providerNameController,
              style: const TextStyle(fontSize: 12),
              decoration: const InputDecoration(
                hintText: '如 DeepSeek / OpenAI / 本地 Ollama',
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ),
        _buildSettingCard(
          title: 'API 接口与协议',
          subtitle: '服务基础 URL 与对应的通讯协议格式',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // URL 输入框
              SizedBox(
                width: 250,
                height: 36,
                child: TextField(
                  controller: _llmBaseUrlController,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    hintText: 'https://api.deepseek.com/v1',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),

              // 协议下拉框
              Container(
                height: 36,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                decoration: BoxDecoration(
                  color: AppTheme.paperWarmth,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: AppTheme.border),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<LlmProtocol>(
                    value: _selectedProtocol,
                    items: LlmProtocol.values
                        .map(
                          (protocol) => DropdownMenuItem<LlmProtocol>(
                            value: protocol,
                            child: Text(
                              protocol.label,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedProtocol = val);
                      }
                    },
                    icon: const Icon(
                      Icons.unfold_more_rounded,
                      size: 16,
                      color: AppTheme.stone,
                    ),
                    dropdownColor: AppTheme.pureWhite,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
          bottomChild: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.paperWarmth,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppTheme.borderSubtle),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.link_rounded,
                  size: 14,
                  color: AppTheme.notionBlue,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '完整接口地址: $fullEndpoint',
                    style: const TextStyle(
                      fontSize: 11.5,
                      fontFamily: 'monospace',
                      color: AppTheme.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
        _buildSettingCard(
          title: 'LLM API Key',
          subtitle: '访问该供应商所需的身份密钥',
          control: SizedBox(
            width: 260,
            height: 36,
            child: TextField(
              controller: _llmApiKeyController,
              obscureText: _obscureLlmKey,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: 'sk-...',
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureLlmKey ? Icons.visibility_off : Icons.visibility,
                    size: 15,
                    color: AppTheme.textMuted,
                  ),
                  onPressed: () =>
                      setState(() => _obscureLlmKey = !_obscureLlmKey),
                ),
              ),
            ),
          ),
        ),

        const SizedBox(height: 12),
        // 3. 模型列表与在线拉取
        _buildGroupTitle('Models'),
        _buildSettingCard(
          title: '模型列表',
          subtitle: '点击卡片切换当前模型，设置按钮调整模型参数与能力档案',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 在线拉取模型按钮
              ElevatedButton.icon(
                onPressed: _isFetchingModels ? null : _fetchRemoteModelsOnline,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.surfaceElevated,
                  foregroundColor: AppTheme.textPrimary,
                  elevation: 0,
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: _isFetchingModels
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppTheme.notionBlue,
                        ),
                      )
                    : const Icon(
                        Icons.cloud_download_outlined,
                        size: 15,
                        color: AppTheme.notionBlue,
                      ),
                label: Text(
                  _isFetchingModels ? '拉取中...' : '在线拉取模型',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),

              // 添加自定义模型
              OutlinedButton.icon(
                onPressed: _addModel,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: AppTheme.border),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: const Icon(
                  Icons.add_rounded,
                  size: 14,
                  color: AppTheme.textPrimary,
                ),
                label: const Text(
                  '添加模型',
                  style: TextStyle(fontSize: 12, color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          bottomChild: _fetchStatusMessage != null
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _isFetchSuccess
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isFetchSuccess
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 14,
                        color: _isFetchSuccess
                            ? AppTheme.success
                            : AppTheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _fetchStatusMessage!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _isFetchSuccess
                                ? AppTheme.success
                                : AppTheme.error,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),

        // 模型卡片网格
        if (currentProvider.models.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.paperWarmth,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: const Text(
                '当前供应商暂无模型，点击上方"在线拉取模型"或"添加模型"',
                style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
              ),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: 4, bottom: 12),
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: [
                for (final model in currentProvider.models)
                  ModelCard(
                    model: model,
                    isSelected: model.id == currentProvider.activeModelId,
                    onSelect: (m) => _setActiveModel(m.id),
                    onEdit: _editModel,
                    onDelete: currentProvider.models.length > 1
                        ? () => _deleteModel(model.id)
                        : null,
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Tab 3: Bill Token 用量账单
  Widget _buildBillTab() {
    final summary = widget.viewModel.buildBillSummary(_billPeriod);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupTitle('Usage Bill'),

        // 周期切换胶囊组
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              for (final period in BillPeriod.values) ...[
                InkWell(
                  onTap: () => setState(() => _billPeriod = period),
                  borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: _billPeriod == period
                          ? AppTheme.notionBlue
                          : AppTheme.pureWhite,
                      borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      border: Border.all(
                        color: _billPeriod == period
                            ? AppTheme.notionBlue
                            : AppTheme.border,
                      ),
                    ),
                    child: Text(
                      period.label,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: _billPeriod == period
                            ? Colors.white
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              const Spacer(),
              Text(
                '${summary.requests} 次请求 · 总计 ${UsageLedgerService.formatTokens(summary.usage.total)} tokens',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: AppTheme.textMuted,
                ),
              ),
            ],
          ),
        ),

        // 账单表格
        if (summary.models.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: const Center(
              child: Text(
                '该周期内暂无用量记录',
                style: TextStyle(fontSize: 12.5, color: AppTheme.textMuted),
              ),
            ),
          )
        else
          _buildBillTable(summary),
      ],
    );
  }

  /// 账单表格 (对齐 pi-bill 的列: Model / Reqs / Input / Output / Cache R / Total)
  Widget _buildBillTable(BillSummary summary) {
    const headerStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: AppTheme.textMuted,
    );
    const cellStyle = TextStyle(fontSize: 11.5, color: AppTheme.textPrimary);
    const totalStyle = TextStyle(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      color: AppTheme.textPrimary,
    );

    String fmt(int v) => UsageLedgerService.formatTokens(v);

    TableRow buildRow(
      List<String> cells, {
      TextStyle style = cellStyle,
      Color? background,
      bool topBorder = false,
    }) {
      return TableRow(
        decoration: BoxDecoration(
          color: background,
          border: topBorder
              ? const Border(top: BorderSide(color: AppTheme.border))
              : null,
        ),
        children: cells
            .map(
              (c) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                child: Text(c, style: style),
              ),
            )
            .toList(),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(AppTheme.radiusButton),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.6),
          1: FlexColumnWidth(1),
          2: FlexColumnWidth(1.1),
          3: FlexColumnWidth(1.1),
          4: FlexColumnWidth(1.1),
          5: FlexColumnWidth(1.1),
          6: FlexColumnWidth(1),
        },
        children: [
          buildRow(
            const ['模型', '请求数', '输入', '输出', '缓存读', '命中率', '总计'],
            style: headerStyle,
            background: AppTheme.paperWarmth,
          ),
          for (final model in summary.models)
            buildRow([
              model.name,
              model.requests.toString(),
              fmt(model.usage.input),
              fmt(model.usage.output),
              fmt(model.usage.cacheRead),
              _hitRateLabel(model.usage),
              fmt(model.usage.total),
            ]),
          buildRow(
            [
              'Total',
              summary.requests.toString(),
              fmt(summary.usage.input),
              fmt(summary.usage.output),
              fmt(summary.usage.cacheRead),
              _hitRateLabel(summary.usage),
              fmt(summary.usage.total),
            ],
            style: totalStyle,
            background: AppTheme.paperWarmth,
            topBorder: true,
          ),
        ],
      ),
    );
  }

  /// 缓存命中率单元格文案 (无数据时显示 -)
  String _hitRateLabel(TokenUsage usage) {
    final rate = usage.cacheHitRate;
    return rate == null ? '-' : '${(rate * 100).toStringAsFixed(1)}%';
  }

  /// Tab 2: Defaults 出厂默认预设
  Widget _buildDefaultsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildGroupTitle('Model & Sampler'),
        _buildSettingCard(
          title: '默认生图模型',
          subtitle: '应用启动或参数重置时的默认出厂模型',
          control: _buildDropdown<NaiModel>(
            value: _defaultModel,
            items: NaiModel.values,
            labelBuilder: (m) => m.label,
            onChanged: (val) {
              if (val != null) setState(() => _defaultModel = val);
            },
          ),
        ),
        _buildSettingCard(
          title: '默认采样算法',
          subtitle: '生图时默认使用的降噪采样器',
          control: _buildDropdown<NaiSampler>(
            value: _defaultSampler,
            items: NaiSampler.values,
            labelBuilder: (s) => s.label,
            onChanged: (val) {
              if (val != null) setState(() => _defaultSampler = val);
            },
          ),
        ),
        _buildSettingCard(
          title: '默认噪声调度',
          subtitle: '采样降噪过程中的时间步长调度算法',
          control: _buildDropdown<NoiseSchedule>(
            value: _defaultNoiseSchedule,
            items: NoiseSchedule.values,
            labelBuilder: (n) => n.label,
            onChanged: (val) {
              if (val != null) setState(() => _defaultNoiseSchedule = val);
            },
          ),
        ),

        const SizedBox(height: 12),
        _buildGroupTitle('Default Steps & Scale'),
        _buildSettingCard(
          title: '默认步数 (Steps)',
          subtitle: '初始采样迭代步数',
          control: SizedBox(
            width: 160,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_rounded, size: 16),
                  onPressed: _defaultSteps > 1
                      ? () => setState(() => _defaultSteps--)
                      : null,
                ),
                Text(
                  '$_defaultSteps',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    fontFamily: 'monospace',
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_rounded, size: 16),
                  onPressed: _defaultSteps < 50
                      ? () => setState(() => _defaultSteps++)
                      : null,
                ),
              ],
            ),
          ),
        ),
        _buildSettingCard(
          title: '默认 CFG Scale',
          subtitle: '提示词引导强度 (当前: ${_defaultScale.toStringAsFixed(1)})',
          control: SizedBox(
            width: 180,
            child: Slider(
              value: _defaultScale,
              min: 1.0,
              max: 20.0,
              divisions: 38,
              activeColor: AppTheme.notionBlue,
              onChanged: (val) => setState(() => _defaultScale = val),
            ),
          ),
        ),
      ],
    );
  }

  /// 小节标题
  Widget _buildGroupTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppTheme.textPrimary,
        ),
      ),
    );
  }

  /// 统一设置项卡片 (对齐参考设计，支持可选 bottomChild)
  Widget _buildSettingCard({
    required String title,
    required String subtitle,
    required Widget control,
    Widget? bottomChild,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.pureWhite,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              control,
            ],
          ),
          if (bottomChild != null) ...[const SizedBox(height: 8), bottomChild],
        ],
      ),
    );
  }

  /// 统一圆角下拉选择框
  Widget _buildDropdown<T>({
    required T value,
    required List<T> items,
    required String Function(T) labelBuilder,
    required ValueChanged<T?> onChanged,
  }) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppTheme.paperWarmth,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppTheme.border),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(
                    labelBuilder(item),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
              )
              .toList(),
          onChanged: onChanged,
          icon: const Icon(
            Icons.unfold_more_rounded,
            size: 16,
            color: AppTheme.stone,
          ),
          dropdownColor: AppTheme.pureWhite,
          borderRadius: BorderRadius.circular(8),
        ),
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
