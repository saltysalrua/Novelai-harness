import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/llm_model_fetcher.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/app_motion.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_card.dart';
import '../../../core/widgets/app_confirm_dialog.dart';
import '../../../core/widgets/app_control_flow.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../../core/widgets/app_skeleton.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/smooth_scroll_controller.dart';
import '../../studio/view_models/studio_view_model.dart';
import 'model_card.dart';
import 'model_profile_dialog.dart';
import 'settings_shared.dart';

/// Models 页草稿状态 (父级 SettingsDialog 持有，保存时统一聚合)
class ModelsSettingsDraft {
  ModelsSettingsDraft(AppConfig config) {
    providers =
        (config.llmProviders.isNotEmpty
                ? config.llmProviders
                : LlmProviderConfig.defaultProviders)
            .map((p) => p.copyWith())
            .toList();
    selectedProviderId = config.activeLlmProviderId;
    if (!providers.any((p) => p.id == selectedProviderId)) {
      selectedProviderId = providers.first.id;
    }
    final active = currentProvider;
    nameController = TextEditingController(text: active.name);
    baseUrlController = TextEditingController(text: active.baseUrl);
    apiKeyController = TextEditingController(text: active.apiKey);
    protocol = active.protocol;
    thinkingParamFormat = active.thinkingParamFormat;
    promptToolUse = active.promptToolUse;
    streaming = active.streaming;
    imageEditProviderId = config.imageEditProviderId;
    imageEditModelId = config.imageEditModelId;
    _validateImageEditSelection();
  }

  late final List<LlmProviderConfig> providers;
  late String selectedProviderId;
  late final TextEditingController nameController;
  late final TextEditingController baseUrlController;
  late final TextEditingController apiKeyController;
  late LlmProtocol protocol;

  /// 思考参数请求格式 (不同供应商用不同字段开关思维链)
  late ThinkingParamFormat thinkingParamFormat;
  late bool promptToolUse;
  late bool streaming;

  /// AI 整图编辑：绘图模型供应商与模型 ID (独立于对话 LLM)
  late String imageEditProviderId;
  late String imageEditModelId;

  // 在线拉取状态
  bool isFetchingModels = false;
  String? fetchStatusMessage;
  bool isFetchSuccess = false;

  LlmProviderConfig get currentProvider => providers.firstWhere(
    (p) => p.id == selectedProviderId,
    orElse: () => providers.first,
  );

  /// 将表单内容写回当前供应商条目 (切换 / 保存 / 拉取前调用)
  void syncFromForm([String? fallbackName]) {
    final idx = providers.indexWhere((p) => p.id == selectedProviderId);
    if (idx >= 0) {
      providers[idx] = providers[idx].copyWith(
        name: nameController.text.trim().isEmpty
            ? (fallbackName ?? '自定义供应商')
            : nameController.text.trim(),
        baseUrl: baseUrlController.text.trim(),
        protocol: protocol,
        apiKey: apiKeyController.text.trim(),
        thinkingParamFormat: thinkingParamFormat,
        promptToolUse: promptToolUse,
        streaming: streaming,
      );
    }
  }

  /// 载入指定供应商到表单
  void loadProviderToForm(LlmProviderConfig provider) {
    selectedProviderId = provider.id;
    nameController.text = provider.name;
    baseUrlController.text = provider.baseUrl;
    protocol = provider.protocol;
    apiKeyController.text = provider.apiKey;
    thinkingParamFormat = provider.thinkingParamFormat;
    promptToolUse = provider.promptToolUse;
    streaming = provider.streaming;
    fetchStatusMessage = null;
  }

  /// 切换当前编辑的供应商，切换前自动同步表单
  void switchProvider(String newProviderId, [String? fallbackName]) {
    if (newProviderId == selectedProviderId) return;
    syncFromForm(fallbackName);
    loadProviderToForm(providers.firstWhere((p) => p.id == newProviderId));
  }

  /// 新建供应商并载入表单
  void addNewProvider({String? defaultName, String? fallbackName}) {
    syncFromForm(fallbackName);
    final newProvider = LlmProviderConfig(
      id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      name: defaultName ?? '新供应商 ${providers.length + 1}',
      baseUrl: 'https://api.openai.com/v1',
      protocol: LlmProtocol.openAiChat,
      apiKey: '',
      activeModelId: 'gpt-4o',
      models: const [
        LlmModelConfig(
          id: 'gpt-4o',
          name: 'GPT-4o',
          reasoning: false,
          temperature: 1.0,
        ),
      ],
    );
    providers.add(newProvider);
    loadProviderToForm(newProvider);
  }

  /// 删除当前编辑的供应商 (至少保留一个)
  bool deleteCurrentProvider() {
    if (providers.length <= 1) return false;
    providers.removeWhere((p) => p.id == selectedProviderId);
    loadProviderToForm(providers.first);
    _validateImageEditSelection();
    return true;
  }

  /// 点击模型卡片，切换为当前生效模型
  void setActiveModel(String modelId) {
    final idx = providers.indexWhere((p) => p.id == selectedProviderId);
    if (idx < 0 || providers[idx].activeModelId == modelId) return;
    providers[idx] = providers[idx].copyWith(activeModelId: modelId);
  }

  /// 添加或替换同 ID 模型，并置为当前生效模型
  void upsertModel(LlmModelConfig newModel) {
    final idx = providers.indexWhere((p) => p.id == selectedProviderId);
    if (idx < 0) return;
    final provider = providers[idx];
    final models = [
      ...provider.models.where((m) => m.id != newModel.id),
      newModel,
    ];
    providers[idx] = provider.copyWith(
      models: models,
      activeModelId: newModel.id,
    );
  }

  /// 用编辑结果替换旧模型 (保留生效模型指向)
  void replaceModel(LlmModelConfig oldModel, LlmModelConfig updated) {
    final idx = providers.indexWhere((p) => p.id == selectedProviderId);
    if (idx < 0) return;
    final provider = providers[idx];
    final models = provider.models
        .where((m) => m.id != updated.id || m.id == oldModel.id)
        .map((m) => m.id == oldModel.id ? updated : m)
        .toList();
    var activeId = provider.activeModelId;
    if (activeId == oldModel.id) activeId = updated.id;
    providers[idx] = provider.copyWith(models: models, activeModelId: activeId);
  }

  /// 删除指定模型 (至少保留一个)
  void removeModel(String modelId) {
    final idx = providers.indexWhere((p) => p.id == selectedProviderId);
    if (idx < 0) return;
    final provider = providers[idx];
    if (provider.models.length <= 1) return;
    final filtered = provider.models.where((m) => m.id != modelId).toList();
    if (filtered.length == provider.models.length) return;
    providers[idx] = provider.copyWith(
      models: filtered,
      activeModelId: provider.activeModelId == modelId
          ? filtered.first.id
          : provider.activeModelId,
    );
  }

  /// 应用在线拉取结果 (尽量保留之前生效的模型指向)
  void applyFetchResult(RemoteModelFetchResult result) {
    final idx = providers.indexWhere((p) => p.id == selectedProviderId);
    if (idx < 0) return;
    final previousId = providers[idx].activeModelId;
    final targetActiveId = result.models.any((m) => m.id == previousId)
        ? previousId
        : (result.models.isNotEmpty ? result.models.first.id : '');
    providers[idx] = providers[idx].copyWith(
      models: result.models,
      activeModelId: targetActiveId,
    );
    _validateImageEditSelection();
  }

  void dispose() {
    nameController.dispose();
    baseUrlController.dispose();
    apiKeyController.dispose();
  }

  /// AI 整图编辑供应商下的模型列表 (仅显示具备图像输出能力的绘图模型)
  List<LlmModelConfig> get imageEditProviderModels {
    final provider = providers.where((p) => p.id == imageEditProviderId);
    if (provider.isEmpty) return const [];
    return provider.first.models.where((m) => m.imageOutput).toList();
  }

  /// 校验绘图模型选择：供应商不存在或模型不存在时自动回落到首个可用候选
  void _validateImageEditSelection() {
    final provider = providers.where((p) => p.id == imageEditProviderId);
    if (provider.isEmpty) {
      imageEditProviderId = '';
      imageEditModelId = '';
      return;
    }
    final models = provider.first.models;
    if (!models.any((m) => m.id == imageEditModelId)) {
      // 优先回落到具备图像输出能力的模型，否则清空模型选择
      final imageModel = models.where((m) => m.imageOutput).firstOrNull;
      imageEditModelId = imageModel?.id ?? '';
    }
  }

  /// 切换 AI 整图编辑供应商 (模型选择自动校验回落)
  void setImageEditProvider(String providerId) {
    imageEditProviderId = providerId;
    imageEditModelId = '';
    _validateImageEditSelection();
  }

  /// 选择 AI 整图编辑模型
  void setImageEditModel(String modelId) {
    imageEditModelId = modelId;
  }
}

/// 模型网格排序方式
enum ModelSortMode {
  nameAsc,
  nameDesc,
  contextDesc,
  maxTokensDesc,
  thinkingFirst,
  multimodalFirst,
  imageOutputFirst,
  defaultOrder,
}

int _compareModelNameAsc(LlmModelConfig a, LlmModelConfig b) {
  final nameCmp = a.name.trim().toLowerCase().compareTo(
    b.name.trim().toLowerCase(),
  );
  if (nameCmp != 0) return nameCmp;
  return a.id.toLowerCase().compareTo(b.id.toLowerCase());
}

/// 按指定排序方式整理模型列表，不修改原列表
List<LlmModelConfig> sortLlmModels(
  List<LlmModelConfig> models,
  ModelSortMode mode,
) {
  if (mode == ModelSortMode.defaultOrder) {
    return List<LlmModelConfig>.of(models);
  }
  final sorted = List<LlmModelConfig>.of(models);
  sorted.sort((a, b) {
    final primary = switch (mode) {
      ModelSortMode.defaultOrder => 0,
      ModelSortMode.nameAsc => _compareModelNameAsc(a, b),
      ModelSortMode.nameDesc => _compareModelNameAsc(b, a),
      ModelSortMode.contextDesc => b.contextWindow.compareTo(a.contextWindow),
      ModelSortMode.maxTokensDesc => b.maxTokens.compareTo(a.maxTokens),
      ModelSortMode.thinkingFirst => (b.supportsThinking ? 1 : 0).compareTo(
        a.supportsThinking ? 1 : 0,
      ),
      ModelSortMode.multimodalFirst => (b.isMultimodal ? 1 : 0).compareTo(
        a.isMultimodal ? 1 : 0,
      ),
      ModelSortMode.imageOutputFirst => (b.imageOutput ? 1 : 0).compareTo(
        a.imageOutput ? 1 : 0,
      ),
    };
    return primary != 0 ? primary : _compareModelNameAsc(a, b);
  });
  return sorted;
}

/// Models 页：多供应商管理、端点配置与模型卡片网格
class ModelsSettingsTab extends StatefulWidget {
  final StudioViewModel viewModel;
  final ModelsSettingsDraft draft;

  const ModelsSettingsTab({
    super.key,
    required this.viewModel,
    required this.draft,
  });

  @override
  State<ModelsSettingsTab> createState() => _ModelsSettingsTabState();
}

class _ModelsSettingsTabState extends State<ModelsSettingsTab> {
  ModelsSettingsDraft get _draft => widget.draft;
  final LlmModelFetcher _modelFetcher = LlmModelFetcher();
  late final SmoothWheelScrollController _scrollController;
  int _fetchErrorShakeTrigger = 0;
  String _cachedFetchStatus = '';
  bool _cachedFetchSuccess = false;

  @override
  void initState() {
    super.initState();
    _scrollController = SmoothWheelScrollController();
    _draft.nameController.addListener(_onProviderNameChanged);
  }

  @override
  void dispose() {
    _draft.nameController.removeListener(_onProviderNameChanged);
    _scrollController.dispose();
    _modelFetcher.close();
    super.dispose();
  }

  void _onProviderNameChanged() {
    if (!mounted) return;
    setState(() {
      _draft.syncFromForm(context.l10n.settingsCustomProviderDefaultName);
    });
  }

  /// 编辑单个模型档案
  Future<void> _editModel(LlmModelConfig model) async {
    final provider = _draft.currentProvider;
    final result = await ModelProfileDialog.show(
      context,
      model: model,
      canDelete: provider.models.length > 1,
    );
    if (!mounted || result == null) return;

    setState(() {
      if (result.delete) {
        _draft.removeModel(model.id);
      } else {
        _draft.replaceModel(model, result.model!);
      }
    });
  }

  /// 添加新模型
  Future<void> _addModel() async {
    final l10n = context.l10n;
    _draft.syncFromForm(l10n.settingsCustomProviderDefaultName);
    final result = await ModelProfileDialog.show(
      context,
      model: const LlmModelConfig(id: '', name: ''),
      isNew: true,
      canDelete: false,
    );
    if (!mounted || result == null || result.delete || result.model == null) {
      return;
    }

    setState(() => _draft.upsertModel(result.model!));
  }

  /// 删除指定模型 (至少保留一个)
  void _deleteModel(String modelId) {
    setState(() => _draft.removeModel(modelId));
  }

  /// 删除当前供应商前二次确认，防止误触丢失全部模型与密钥
  Future<void> _confirmDeleteProvider() async {
    if (_draft.providers.length <= 1) return;
    final l10n = context.l10n;
    final current = _draft.currentProvider;
    final confirmed = await showAppConfirmDialog(
      context,
      title: l10n.settingsConfirmDeleteProviderTitle,
      message: l10n.settingsConfirmDeleteProviderMessage(current.name),
      confirmLabel: l10n.delete,
      isDestructive: true,
    );
    if (confirmed == true && mounted) {
      setState(() => _draft.deleteCurrentProvider());
    }
  }

  /// 在线拉取远程供应商模型列表
  Future<void> _fetchRemoteModelsOnline() async {
    final l10n = context.l10n;
    final baseUrl = _draft.baseUrlController.text.trim();
    final apiKey = _draft.apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      setState(() {
        _draft.isFetchSuccess = false;
        _draft.fetchStatusMessage = l10n.settingsFetchModelsEnterBaseUrl;
        _cachedFetchSuccess = false;
        _cachedFetchStatus = _draft.fetchStatusMessage!;
        _fetchErrorShakeTrigger++;
      });
      return;
    }

    setState(() {
      _draft.isFetchingModels = true;
      _draft.fetchStatusMessage = null;
    });

    try {
      _draft.syncFromForm(l10n.settingsCustomProviderDefaultName);
      final existingModels = _draft.currentProvider.models;

      final result = await _modelFetcher.fetchRemoteModels(
        baseUrl: baseUrl,
        protocol: _draft.protocol,
        apiKey: apiKey,
        existingModels: existingModels,
      );

      _draft.applyFetchResult(result);

      // 拉取结果立即写盘持久化，避免忘记点保存导致模型列表丢失
      await widget.viewModel.persistLlmProviders(
        _draft.providers,
        _draft.selectedProviderId,
      );

      if (!mounted) return;
      final statusMsg = result.enrichedCount > 0
          ? l10n.settingsFetchModelsSuccessWithEnriched(
              result.models.length,
              result.enrichedCount,
            )
          : l10n.settingsFetchModelsSuccess(result.models.length);
      setState(() {
        _draft.isFetchingModels = false;
        _draft.isFetchSuccess = true;
        _draft.fetchStatusMessage = statusMsg;
        _cachedFetchSuccess = true;
        _cachedFetchStatus = statusMsg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _draft.isFetchingModels = false;
        _draft.isFetchSuccess = false;
        _draft.fetchStatusMessage = '$e';
        _cachedFetchSuccess = false;
        _cachedFetchStatus = _draft.fetchStatusMessage!;
        _fetchErrorShakeTrigger++;
      });
    }
  }

  /// 计算完整接口地址预览
  String _calculateFullEndpoint(
    String baseUrl,
    LlmProtocol protocol,
    String emptyLabel,
  ) {
    var base = baseUrl.trim();
    if (base.isEmpty) return emptyLabel;
    if (base.endsWith('/')) {
      base = base.substring(0, base.length - 1);
    }
    final path = protocol.defaultPath;
    if (base.endsWith(path)) return base;
    return '$base$path';
  }

  /// 头部：供应商快捷切换条 / 统一配置卡片 / 整图编辑 / 模型列表工具栏
  Widget _buildHeaderSections(AppLocalizations l10n) {
    final colors = context.colors;
    if (_draft.fetchStatusMessage != null) {
      _cachedFetchStatus = _draft.fetchStatusMessage!;
      _cachedFetchSuccess = _draft.isFetchSuccess;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 供应商快捷选择条 (一键切换 + 新建)
        AppSectionHeader(
          title: l10n.settingsSectionProviderSelection,
          subtitle: l10n.settingsCurrentProviderSubtitle,
          trailing: AppActionButton(
            icon: Icons.add_rounded,
            label: l10n.settingsNewProviderButton,
            onPressed: () => setState(
              () => _draft.addNewProvider(
                defaultName: l10n.settingsNewProviderDefaultName(
                  _draft.providers.length + 1,
                ),
                fallbackName: l10n.settingsCustomProviderDefaultName,
              ),
            ),
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _draft.providers.map((p) {
            final isSelected = p.id == _draft.selectedProviderId;
            return _ProviderPill(
              name: p.name,
              modelCount: p.models.length,
              isSelected: isSelected,
              onTap: () => setState(
                () => _draft.switchProvider(
                  p.id,
                  l10n.settingsCustomProviderDefaultName,
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 18),

        // 2. 当前供应商信息与连接配置 (收拢进单一 Notion 轻噪卡片)
        AppSectionHeader(
          title: l10n.settingsSectionProviderProfile,
          trailing: _draft.providers.length > 1
              ? AppIconButton(
                  icon: Icons.delete_outline_rounded,
                  iconSize: 17,
                  size: 30,
                  variant: AppIconButtonVariant.ghost,
                  iconColor: colors.error,
                  tooltip: l10n.settingsDeleteCurrentProviderTooltip,
                  onPressed: _confirmDeleteProvider,
                )
              : null,
        ),
        AppCard(
          padding: const EdgeInsets.all(16),
          radius: AppRadius.lg,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final twoCol = constraints.maxWidth >= 480;

              final nameField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsFieldLabel(label: l10n.settingsProviderName),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _draft.nameController,
                      style: const TextStyle(fontSize: 12),
                      decoration: settingsSoftInputDecoration(
                        context,
                        hintText: l10n.settingsProviderNameHint,
                      ),
                    ),
                  ),
                ],
              );

              final keyField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsFieldLabel(label: l10n.settingsLlmApiKeyTitle),
                  const SizedBox(height: 6),
                  SettingsKeyField(
                    controller: _draft.apiKeyController,
                    hintText: 'sk-...',
                    width: null,
                    soft: true,
                  ),
                ],
              );

              final urlField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsFieldLabel(label: l10n.settingsApiEndpointAndProtocol),
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 36,
                    child: TextField(
                      controller: _draft.baseUrlController,
                      style: const TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                      decoration: settingsSoftInputDecoration(
                        context,
                        hintText: 'https://api.deepseek.com/v1',
                      ),
                    ),
                  ),
                ],
              );

              final protocolField = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SettingsFieldLabel(label: l10n.settingsThinkingParamFormat),
                  const SizedBox(height: 6),
                  AppDropdown<ThinkingParamFormat>(
                    value: _draft.thinkingParamFormat,
                    isExpanded: true,
                    items: ThinkingParamFormat.values
                        .map(
                          (f) => AppDropdownItem(
                            value: f,
                            label: thinkingParamFormatLabelOf(l10n, f),
                          ),
                        )
                        .toList(),
                    onChanged: (val) =>
                        setState(() => _draft.thinkingParamFormat = val),
                  ),
                ],
              );

              final protocolSelect = AppDropdown<LlmProtocol>(
                value: _draft.protocol,
                isExpanded: true,
                items: LlmProtocol.values
                    .map(
                      (protocol) => AppDropdownItem(
                        value: protocol,
                        label: llmProtocolLabelOf(l10n, protocol),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _draft.protocol = val),
              );

              final behaviorToggles = SettingsSoftContainer(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 9,
                ),
                child: twoCol
                    ? Row(
                        children: [
                          Expanded(
                            child: _InlineSwitchItem(
                              key: const ValueKey('streaming_toggle'),
                              label: l10n.settingsStreaming,
                              value: _draft.streaming,
                              onChanged: (value) =>
                                  setState(() => _draft.streaming = value),
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: _InlineSwitchItem(
                              key: const ValueKey('prompt_tool_use_toggle'),
                              label: l10n.settingsPromptToolUse,
                              value: _draft.promptToolUse,
                              onChanged: (value) =>
                                  setState(() => _draft.promptToolUse = value),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        children: [
                          _InlineSwitchItem(
                            key: const ValueKey('streaming_toggle'),
                            label: l10n.settingsStreaming,
                            value: _draft.streaming,
                            onChanged: (value) =>
                                setState(() => _draft.streaming = value),
                          ),
                          const SizedBox(height: 8),
                          _InlineSwitchItem(
                            key: const ValueKey('prompt_tool_use_toggle'),
                            label: l10n.settingsPromptToolUse,
                            value: _draft.promptToolUse,
                            onChanged: (value) =>
                                setState(() => _draft.promptToolUse = value),
                          ),
                        ],
                      ),
              );

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (twoCol) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: nameField),
                        const SizedBox(width: 12),
                        Expanded(child: keyField),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(flex: 6, child: urlField),
                        const SizedBox(width: 12),
                        Expanded(flex: 4, child: protocolSelect),
                      ],
                    ),
                  ] else ...[
                    nameField,
                    const SizedBox(height: 10),
                    keyField,
                    const SizedBox(height: 10),
                    urlField,
                    const SizedBox(height: 8),
                    protocolSelect,
                  ],
                  const SizedBox(height: 8),

                  // 完整接口地址实时预览条 (局部监听，零表单重建)
                  ListenableBuilder(
                    listenable: _draft.baseUrlController,
                    builder: (context, _) {
                      final hasUrl =
                          _draft.baseUrlController.text.trim().isNotEmpty;
                      final fullEndpoint = _calculateFullEndpoint(
                        _draft.baseUrlController.text,
                        _draft.protocol,
                        l10n.settingsEndpointUrlNotConfigured,
                      );
                      return SettingsSoftContainer(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.link_rounded,
                              size: 14,
                              color: colors.primary,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                l10n.settingsFullEndpoint(fullEndpoint),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontFamily: 'monospace',
                                  color: colors.textSecondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (hasUrl)
                              InkWell(
                                onTap: () {
                                  Clipboard.setData(
                                    ClipboardData(text: fullEndpoint),
                                  );
                                  showAppToast(
                                    context,
                                    message: l10n.settingsEndpointCopied,
                                    tone: AppToastTone.success,
                                    duration: const Duration(
                                      milliseconds: 1400,
                                    ),
                                  );
                                },
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(4),
                                  child: Icon(
                                    Icons.copy_rounded,
                                    size: 13,
                                    color: colors.textMuted,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  if (twoCol)
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(flex: 4, child: protocolField),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 6,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SettingsFieldLabel(
                                label: l10n.settingsSectionProviderBehavior,
                              ),
                              const SizedBox(height: 6),
                              behaviorToggles,
                            ],
                          ),
                        ),
                      ],
                    )
                  else ...[
                    protocolField,
                    const SizedBox(height: 10),
                    SettingsFieldLabel(
                      label: l10n.settingsSectionProviderBehavior,
                    ),
                    const SizedBox(height: 6),
                    behaviorToggles,
                  ],
                ],
              );
            },
          ),
        ),

        const SizedBox(height: 18),

        // 3. AI 整图编辑绘图模型 (独立于对话 LLM 的供应商与模型选择)
        AppSectionHeader(title: l10n.settingsSectionImageEdit),
        AppSettingTile(
          title: l10n.settingsImageEditModelTitle,
          subtitle: l10n.settingsImageEditTip,
          control: AppControlFlow(
            alignment: WrapAlignment.end,
            children: [
              AppDropdown<String>(
                value: _draft.imageEditProviderId,
                width: 190,
                items: [
                  AppDropdownItem(
                    value: '',
                    label: l10n.settingsDropdownNotConfigured,
                  ),
                  ..._draft.providers.map(
                    (p) => AppDropdownItem(value: p.id, label: p.name),
                  ),
                ],
                onChanged: (val) =>
                    setState(() => _draft.setImageEditProvider(val)),
              ),
              AppDropdown<String>(
                value: _draft.imageEditModelId,
                width: 230,
                items: [
                  AppDropdownItem(
                    value: '',
                    label: l10n.settingsDropdownNoModelSelected,
                  ),
                  ..._draft.imageEditProviderModels.map(
                    (m) => AppDropdownItem(value: m.id, label: m.name),
                  ),
                  // 防悬挂兜底：当前选中的模型被改掉能力或删除时仍保留下拉项
                  if (_draft.imageEditModelId.isNotEmpty &&
                      !_draft.imageEditProviderModels.any(
                        (m) => m.id == _draft.imageEditModelId,
                      ))
                    AppDropdownItem(
                      value: _draft.imageEditModelId,
                      label: l10n.settingsImageEditUnrecognizedModel(
                        _draft.imageEditModelId,
                      ),
                    ),
                ],
                onChanged: (val) =>
                    setState(() => _draft.setImageEditModel(val)),
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // 4. 模型列表与在线拉取
        AppSectionHeader(
          title: l10n.settingsSectionModels,
          subtitle: l10n.settingsModelsListSubtitle,
          trailing: AppControlFlow(
            children: [
              AppActionButton(
                icon: Icons.cloud_download_outlined,
                label: _draft.isFetchingModels
                    ? l10n.settingsFetchingModels
                    : l10n.settingsFetchModelsOnline,
                iconSize: 14,
                isLoading: _draft.isFetchingModels,
                onPressed: _draft.isFetchingModels
                    ? null
                    : _fetchRemoteModelsOnline,
              ),
              AppActionButton(
                icon: Icons.add_rounded,
                label: l10n.settingsAddModel,
                iconSize: 14,
                onPressed: _addModel,
              ),
            ],
          ),
        ),
        AppPanelReveal(
          visible: _draft.isFetchingModels || _draft.fetchStatusMessage != null,
          enableBlur: false,
          child: AppErrorShake(
            trigger: _fetchErrorShakeTrigger,
            child: Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: _draft.isFetchingModels
                    ? colors.primaryTint
                    : (_cachedFetchSuccess
                          ? colors.success.withValues(alpha: 0.1)
                          : colors.errorSurface),
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
              child: Row(
                children: [
                  if (_draft.isFetchingModels) ...[
                    const AppMatrixDotLoader(
                      dotSize: 2.0,
                      gap: 1.5,
                      variant: AppMatrixDotVariant.scan,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppShimmerText(
                        text: l10n.settingsFetchingModels,
                        style: TextStyle(fontSize: 12, color: colors.primary),
                      ),
                    ),
                  ] else ...[
                    if (_cachedFetchSuccess)
                      AppSuccessCheck(
                        key: ValueKey<String>('ok_$_cachedFetchStatus'),
                        size: 14,
                        color: colors.success,
                      )
                    else
                      Icon(
                        Icons.error_outline_rounded,
                        size: 14,
                        color: colors.error,
                      ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _cachedFetchStatus,
                        style: TextStyle(
                          fontSize: 12,
                          color: _cachedFetchSuccess
                              ? colors.success
                              : colors.error,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return LayoutBuilder(
      builder: (context, constraints) {
        final hPad = constraints.maxWidth < 560 ? 16.0 : 28.0;
        return CustomScrollView(
          controller: _scrollController,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hPad, 8, hPad, 0),
              sliver: SliverToBoxAdapter(child: _buildHeaderSections(l10n)),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(hPad, 0, hPad, 20),
              sliver: _ModelGridSection(
                key: ValueKey<String>(_draft.selectedProviderId),
                provider: _draft.currentProvider,
                isFetching: _draft.isFetchingModels,
                onSelect: (m) => setState(() => _draft.setActiveModel(m.id)),
                onEdit: _editModel,
                onDelete: _deleteModel,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// 顶部供应商快捷切换胶囊
class _ProviderPill extends StatefulWidget {
  final String name;
  final int modelCount;
  final bool isSelected;
  final VoidCallback onTap;

  const _ProviderPill({
    required this.name,
    required this.modelCount,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_ProviderPill> createState() => _ProviderPillState();
}

class _ProviderPillState extends State<_ProviderPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final bg = widget.isSelected
        ? colors.primaryTint
        : (_hovered
              ? colors.mutedBackground.withValues(alpha: 0.8)
              : colors.elevatedBackground);
    final border = widget.isSelected
        ? colors.primary.withValues(alpha: 0.5)
        : colors.borderDefault;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: AppMotion.resolveDuration(context, AppMotionDurations.quick),
          curve: AppMotionCurves.smoothOut,
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: border),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: widget.isSelected
                      ? colors.primary
                      : colors.textMuted.withValues(alpha: 0.4),
                ),
              ),
              const SizedBox(width: 7),
              Text(
                widget.name,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.isSelected
                      ? FontWeight.w600
                      : FontWeight.w500,
                  color: widget.isSelected ? colors.primary : colors.textPrimary,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: widget.isSelected
                      ? colors.primary.withValues(alpha: 0.14)
                      : colors.cardBackground,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Text(
                  '${widget.modelCount}',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: widget.isSelected
                        ? colors.primary
                        : colors.textMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InlineSwitchItem extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _InlineSwitchItem({
    super.key,
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
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          AppSwitch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

/// 模型网格区：搜索框 + 排序下拉 + 计数 + 虚拟化 SliverGrid
class _ModelGridSection extends StatefulWidget {
  final LlmProviderConfig provider;
  final bool isFetching;
  final ValueChanged<LlmModelConfig> onSelect;
  final ValueChanged<LlmModelConfig> onEdit;
  final ValueChanged<String> onDelete;

  const _ModelGridSection({
    super.key,
    required this.provider,
    required this.isFetching,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ModelGridSection> createState() => _ModelGridSectionState();
}

class _ModelGridSectionState extends State<_ModelGridSection> {
  final TextEditingController _searchController = TextEditingController();
  ModelSortMode _sortMode = ModelSortMode.nameAsc;

  /// 仅显示绘图模型 (图像输出能力) 过滤开关
  bool _imageOnly = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  /// 按搜索词过滤 + 绘图过滤 + 按排序模式整理后的可见模型列表
  List<LlmModelConfig> get _visibleModels {
    final query = _searchController.text.trim().toLowerCase();
    var filtered = query.isEmpty
        ? widget.provider.models
        : widget.provider.models.where(
            (m) =>
                m.name.toLowerCase().contains(query) ||
                m.id.toLowerCase().contains(query),
          );
    if (_imageOnly) {
      filtered = filtered.where((m) => m.imageOutput);
    }
    return sortLlmModels(filtered.toList(), _sortMode);
  }

  String _sortModeLabel(AppLocalizations l10n, ModelSortMode mode) =>
      switch (mode) {
        ModelSortMode.nameAsc => l10n.settingsModelSortNameAsc,
        ModelSortMode.nameDesc => l10n.settingsModelSortNameDesc,
        ModelSortMode.contextDesc => l10n.settingsModelSortContextDesc,
        ModelSortMode.maxTokensDesc => l10n.settingsModelSortMaxTokensDesc,
        ModelSortMode.thinkingFirst => l10n.settingsModelSortThinkingFirst,
        ModelSortMode.multimodalFirst => l10n.settingsModelSortMultimodalFirst,
        ModelSortMode.imageOutputFirst =>
          l10n.settingsModelSortImageOutputFirst,
        ModelSortMode.defaultOrder => l10n.settingsModelSortDefault,
      };

  IconData _sortModeIcon(ModelSortMode mode) => switch (mode) {
    ModelSortMode.nameAsc => Icons.sort_by_alpha_rounded,
    ModelSortMode.nameDesc => Icons.sort_by_alpha_rounded,
    ModelSortMode.contextDesc => Icons.straighten_outlined,
    ModelSortMode.maxTokensDesc => Icons.notes_rounded,
    ModelSortMode.thinkingFirst => Icons.psychology_outlined,
    ModelSortMode.multimodalFirst => Icons.visibility_outlined,
    ModelSortMode.imageOutputFirst => Icons.auto_awesome,
    ModelSortMode.defaultOrder => Icons.format_list_bulleted_rounded,
  };

  Widget _buildToolbar(int visibleCount) {
    final colors = context.colors;
    final l10n = context.l10n;
    final total = widget.provider.models.length;

    Widget buildSearch({required bool fillWidth}) => SizedBox(
      width: fillWidth ? double.infinity : 260,
      child: AppSearchField(
        controller: _searchController,
        hintText: l10n.settingsSearchModelHint,
        debounceDuration: Duration.zero,
        onChanged: (_) {},
      ),
    );
    final sortDropdown = AppDropdown<ModelSortMode>(
      value: _sortMode,
      variant: AppDropdownVariant.compact,
      width: 164,
      menuWidth: 204,
      searchable: false,
      items: ModelSortMode.values
          .map(
            (m) => AppDropdownItem(
              value: m,
              icon: _sortModeIcon(m),
              label: _sortModeLabel(l10n, m),
            ),
          )
          .toList(),
      onChanged: (val) => setState(() => _sortMode = val),
    );
    final imageOnlyChip = AppToolChip(
      icon: Icons.auto_awesome,
      iconSize: 13,
      fontSize: 11,
      label: l10n.settingsFilterImageOnly,
      isSelected: _imageOnly,
      variant: AppToolChipVariant.tinted,
      tooltip: l10n.settingsFilterImageOnlyTooltip,
      onTap: () => setState(() => _imageOnly = !_imageOnly),
    );
    final countText = Text(
      l10n.settingsModelCount(visibleCount, total),
      style: TextStyle(fontSize: 12, color: colors.textMuted),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth >= 640) {
            return Row(
              children: [
                buildSearch(fillWidth: false),
                const SizedBox(width: 8),
                sortDropdown,
                const SizedBox(width: 8),
                imageOnlyChip,
                const Spacer(),
                countText,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildSearch(fillWidth: true),
              const SizedBox(height: 8),
              AppControlFlow(
                children: [sortDropdown, imageOnlyChip, countText],
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final models = widget.provider.models;

    if (models.isEmpty && widget.isFetching) {
      return SliverLayoutBuilder(
        builder: (context, constraints) {
          final crossAxisCount = (constraints.crossAxisExtent / 276)
              .floor()
              .clamp(1, 8);
          return SliverGrid.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: crossAxisCount,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              mainAxisExtent: 98,
            ),
            itemCount: 3,
            itemBuilder: (context, _) =>
                const AppSkeletonBox(height: 98, radius: AppRadius.md),
          );
        },
      );
    }

    if (models.isEmpty) {
      return SliverToBoxAdapter(
        child: AppEmptyState(
          icon: Icons.view_in_ar_outlined,
          title: l10n.settingsNoModelsInProvider,
          description: l10n.settingsNoModelsInProviderDesc,
          isCompact: true,
        ),
      );
    }

    final visible = _visibleModels;
    final canDelete = models.length > 1;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _buildToolbar(visible.length)),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: AppEmptyState(
              icon: Icons.search_off_rounded,
              title: l10n.settingsNoMatchingModels(
                _searchController.text.trim(),
              ),
              isCompact: true,
            ),
          )
        else
          SliverLayoutBuilder(
            builder: (context, constraints) {
              final crossAxisCount = (constraints.crossAxisExtent / 276)
                  .floor()
                  .clamp(1, 8);
              final rowCount = (visible.length / crossAxisCount).ceil();
              // 按行虚拟化并自适应内容高度：普通卡片保持紧凑，多徽章折行卡片按行撑开不溢出
              return SliverList.builder(
                addAutomaticKeepAlives: false,
                itemCount: rowCount,
                itemBuilder: (context, rowIndex) {
                  final startIndex = rowIndex * crossAxisCount;
                  return Padding(
                    padding: EdgeInsets.only(
                      bottom: rowIndex < rowCount - 1 ? 10 : 0,
                    ),
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (var col = 0; col < crossAxisCount; col++) ...[
                            if (col > 0) const SizedBox(width: 10),
                            Expanded(
                              child: startIndex + col < visible.length
                                  ? ModelCard(
                                      model: visible[startIndex + col],
                                      isSelected:
                                          visible[startIndex + col].id ==
                                          widget.provider.activeModelId,
                                      onSelect: widget.onSelect,
                                      onEdit: widget.onEdit,
                                      onDelete: canDelete
                                          ? () => widget.onDelete(
                                              visible[startIndex + col].id,
                                            )
                                          : null,
                                    )
                                  : const SizedBox.shrink(),
                            ),
                          ],
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
      ],
    );
  }
}
