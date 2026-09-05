import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/llm_model_fetcher.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../core/context_l10n.dart';
import '../../../core/l10n/model_label_l10n.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_search_field.dart';
import '../../../core/widgets/app_section_header.dart';
import '../../../core/widgets/app_setting_tile.dart';
import '../../../core/widgets/app_tool_chip.dart';
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
          temperature: 0.7,
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
        : result.models.first.id;
    providers[idx] = providers[idx].copyWith(
      models: result.models,
      activeModelId: targetActiveId,
    );
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
enum _ModelSortMode { defaultOrder, nameAsc, nameDesc }

/// Models 页：多供应商管理、端点配置与模型卡片网格
///
/// 性能设计：
/// 1. 整页为 CustomScrollView —— 头部卡片区是普通 sliver，模型网格是
///    SliverGrid.builder 懒构建，几百个模型也只构建视口内的一屏卡片；
/// 2. 网格区独立成 [_ModelGridSection] 并套 RepaintBoundary，搜索/排序
///    的 setState 不会外溢到头部表单，头部输入框敲字也不再触发全页重建
///    (端点预览改用 ListenableBuilder 局部监听)；
/// 3. 搜索与排序状态由网格区自持，切换供应商时草稿整体重建，状态自然复位。
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

  /// 在线拉取远程供应商模型列表
  Future<void> _fetchRemoteModelsOnline() async {
    final l10n = context.l10n;
    final baseUrl = _draft.baseUrlController.text.trim();
    final apiKey = _draft.apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      setState(() {
        _draft.isFetchSuccess = false;
        _draft.fetchStatusMessage = l10n.settingsFetchModelsEnterBaseUrl;
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
      setState(() {
        _draft.isFetchingModels = false;
        _draft.isFetchSuccess = true;
        _draft.fetchStatusMessage = result.enrichedCount > 0
            ? l10n.settingsFetchModelsSuccessWithEnriched(
                result.models.length,
                result.enrichedCount,
              )
            : l10n.settingsFetchModelsSuccess(result.models.length);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _draft.isFetchingModels = false;
        _draft.isFetchSuccess = false;
        _draft.fetchStatusMessage = '$e';
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

  /// 头部：供应商选择 / 端点表单 / 拉取操作区 (不含模型网格)
  Widget _buildHeaderSections(AppLocalizations l10n) {
    final colors = context.colors;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 供应商切换与管理
        AppSectionHeader(title: l10n.settingsSectionProviderSelection),
        AppSettingTile(
          title: l10n.settingsCurrentProvider,
          subtitle: l10n.settingsCurrentProviderSubtitle,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppDropdown<String>(
                value: _draft.selectedProviderId,
                width: 200,
                items: _draft.providers
                    .map((p) => AppDropdownItem(value: p.id, label: p.name))
                    .toList(),
                onChanged: (val) => setState(
                  () => _draft.switchProvider(
                    val,
                    l10n.settingsCustomProviderDefaultName,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              AppActionButton(
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
              if (_draft.providers.length > 1) ...[
                const SizedBox(width: 4),
                AppIconButton(
                  icon: Icons.delete_outline_rounded,
                  iconSize: 18,
                  variant: AppIconButtonVariant.ghost,
                  tooltip: l10n.settingsDeleteCurrentProviderTooltip,
                  onPressed: () =>
                      setState(() => _draft.deleteCurrentProvider()),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),
        // 2. 供应商基本信息与端点
        AppSectionHeader(title: l10n.settingsSectionProviderProfile),
        AppSettingTile(
          title: l10n.settingsProviderName,
          subtitle: l10n.settingsProviderNameSubtitle,
          control: SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: _draft.nameController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                hintText: l10n.settingsProviderNameHint,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
            ),
          ),
        ),
        AppSettingTile(
          title: l10n.settingsApiEndpointAndProtocol,
          subtitle: l10n.settingsApiEndpointAndProtocolSubtitle,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 250,
                height: 36,
                child: TextField(
                  controller: _draft.baseUrlController,
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
              AppDropdown<LlmProtocol>(
                value: _draft.protocol,
                variant: AppDropdownVariant.compact,
                width: 170,
                items: LlmProtocol.values
                    .map(
                      (protocol) => AppDropdownItem(
                        value: protocol,
                        label: llmProtocolLabelOf(l10n, protocol),
                      ),
                    )
                    .toList(),
                onChanged: (val) => setState(() => _draft.protocol = val),
              ),
            ],
          ),
          // 端点预览只随 URL 输入局部刷新，不触发整页 setState
          bottomChild: ListenableBuilder(
            listenable: _draft.baseUrlController,
            builder: (context, _) {
              final fullEndpoint = _calculateFullEndpoint(
                _draft.baseUrlController.text,
                _draft.protocol,
                l10n.settingsEndpointUrlNotConfigured,
              );
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colors.mutedBackground,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Row(
                  children: [
                    Icon(Icons.link_rounded, size: 14, color: colors.primary),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        l10n.settingsFullEndpoint(fullEndpoint),
                        style: TextStyle(
                          fontSize: 12,
                          fontFamily: 'monospace',
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        AppSettingTile(
          title: l10n.settingsLlmApiKeyTitle,
          subtitle: l10n.settingsLlmApiKeySubtitle,
          control: SettingsKeyField(
            controller: _draft.apiKeyController,
            hintText: 'sk-...',
            width: 260,
          ),
        ),
        AppSettingTile(
          title: l10n.settingsThinkingParamFormat,
          subtitle: l10n.settingsThinkingParamFormatSubtitle,
          control: AppDropdown<ThinkingParamFormat>(
            value: _draft.thinkingParamFormat,
            width: 220,
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
        ),

        const SizedBox(height: 12),
        // 3. 模型列表与在线拉取
        AppSectionHeader(title: l10n.settingsSectionModels),
        AppSettingTile(
          title: l10n.settingsModelsListTitle,
          subtitle: l10n.settingsModelsListSubtitle,
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 在线拉取模型按钮
              ElevatedButton.icon(
                onPressed: _draft.isFetchingModels
                    ? null
                    : _fetchRemoteModelsOnline,
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.cardBackground,
                  foregroundColor: colors.textPrimary,
                  elevation: 0,
                  side: BorderSide(color: colors.borderDefault),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                icon: _draft.isFetchingModels
                    ? SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colors.primary,
                        ),
                      )
                    : Icon(
                        Icons.cloud_download_outlined,
                        size: 15,
                        color: colors.primary,
                      ),
                label: Text(
                  _draft.isFetchingModels
                      ? l10n.settingsFetchingModels
                      : l10n.settingsFetchModelsOnline,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AppActionButton(
                icon: Icons.add_rounded,
                label: l10n.settingsAddModel,
                iconSize: 14,
                onPressed: _addModel,
              ),
            ],
          ),
          bottomChild: _draft.fetchStatusMessage != null
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _draft.isFetchSuccess
                        ? colors.success.withValues(alpha: 0.1)
                        : colors.error.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _draft.isFetchSuccess
                            ? Icons.check_circle_outline_rounded
                            : Icons.error_outline_rounded,
                        size: 14,
                        color: _draft.isFetchSuccess
                            ? colors.success
                            : colors.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _draft.fetchStatusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _draft.isFetchSuccess
                                ? colors.success
                                : colors.error,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        ),
        const SizedBox(height: 12),
        // 4. AI 整图编辑绘图模型 (独立于对话 LLM 的供应商与模型选择)
        AppSectionHeader(title: l10n.settingsSectionImageEdit),
        AppSettingTile(
          title: l10n.settingsImageEditModelTitle,
          subtitle: l10n.settingsImageEditModelSubtitle,
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppDropdown<String>(
                value: _draft.imageEditProviderId,
                width: 200,
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
              const SizedBox(width: 8),
              AppDropdown<String>(
                value: _draft.imageEditModelId,
                width: 240,
                items: [
                  AppDropdownItem(
                    value: '',
                    label: l10n.settingsDropdownNoModelSelected,
                  ),
                  ..._draft.imageEditProviderModels.map(
                    (m) => AppDropdownItem(value: m.id, label: m.name),
                  ),
                  // 防悬挂兜底：当前选中的模型被改掉能力或删除时仍保留下拉项，
                  // 避免下拉选中值从条目中消失 (AppDropdown 内部亦有同型兜底)
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
          bottomChild: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: colors.mutedBackground,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: colors.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    l10n.settingsImageEditTip,
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 网格区紧跟其后 (间距由网格区内部控制)
        const SizedBox(height: 4),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
          sliver: SliverToBoxAdapter(child: _buildHeaderSections(l10n)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 20),
          sliver: _ModelGridSection(
            provider: _draft.currentProvider,
            onSelect: (m) => setState(() => _draft.setActiveModel(m.id)),
            onEdit: _editModel,
            onDelete: _deleteModel,
          ),
        ),
      ],
    );
  }
}

/// 模型网格区：搜索框 + 排序下拉 + 计数 + 虚拟化 SliverGrid
///
/// 作为 sliver 嵌入外层 CustomScrollView；自持搜索/排序状态，
/// 输入搜索词时只有本区 setState，头部表单完全不受影响。
class _ModelGridSection extends StatefulWidget {
  final LlmProviderConfig provider;
  final ValueChanged<LlmModelConfig> onSelect;
  final ValueChanged<LlmModelConfig> onEdit;
  final ValueChanged<String> onDelete;

  const _ModelGridSection({
    required this.provider,
    required this.onSelect,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_ModelGridSection> createState() => _ModelGridSectionState();
}

class _ModelGridSectionState extends State<_ModelGridSection> {
  final TextEditingController _searchController = TextEditingController();
  _ModelSortMode _sortMode = _ModelSortMode.defaultOrder;

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
    final imageOnly = _imageOnly;
    var filtered = query.isEmpty || imageOnly
        ? List<LlmModelConfig>.of(widget.provider.models)
        : widget.provider.models
              .where(
                (m) =>
                    m.name.toLowerCase().contains(query) ||
                    m.id.toLowerCase().contains(query),
              )
              .toList();
    if (imageOnly) {
      filtered = filtered.where((m) => m.imageOutput).toList();
    }
    return switch (_sortMode) {
      _ModelSortMode.defaultOrder => filtered,
      _ModelSortMode.nameAsc => [
        ...filtered,
      ]..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())),
      _ModelSortMode.nameDesc => [
        ...filtered,
      ]..sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())),
    };
  }

  /// 搜索 / 排序 / 计数工具条
  Widget _buildToolbar(int visibleCount) {
    final colors = context.colors;
    final l10n = context.l10n;
    final total = widget.provider.models.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            child: AppSearchField(
              controller: _searchController,
              hintText: l10n.settingsSearchModelHint,
              debounceDuration: Duration.zero,
              onChanged: (_) {},
            ),
          ),
          const SizedBox(width: 8),
          AppDropdown<_ModelSortMode>(
            value: _sortMode,
            variant: AppDropdownVariant.compact,
            width: 150,
            items: _ModelSortMode.values
                .map(
                  (m) => AppDropdownItem(
                    value: m,
                    label: switch (m) {
                      _ModelSortMode.defaultOrder =>
                        l10n.settingsModelSortDefault,
                      _ModelSortMode.nameAsc => l10n.settingsModelSortNameAsc,
                      _ModelSortMode.nameDesc => l10n.settingsModelSortNameDesc,
                    },
                  ),
                )
                .toList(),
            onChanged: (val) => setState(() => _sortMode = val),
          ),
          const SizedBox(width: 8),
          // 仅绘图模型过滤 (快速定位图像输出能力的模型)
          AppToolChip(
            icon: Icons.auto_awesome,
            iconSize: 13,
            fontSize: 11,
            label: l10n.settingsFilterImageOnly,
            isSelected: _imageOnly,
            variant: AppToolChipVariant.tinted,
            tooltip: l10n.settingsFilterImageOnlyTooltip,
            onTap: () => setState(() => _imageOnly = !_imageOnly),
          ),
          const Spacer(),
          Text(
            l10n.settingsModelCount(visibleCount, total),
            style: TextStyle(fontSize: 12, color: colors.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final models = widget.provider.models;

    // 供应商没有任何模型
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
              final crossAxisCount = (constraints.crossAxisExtent / 288)
                  .floor()
                  .clamp(1, 8);
              return SliverGrid.builder(
                addAutomaticKeepAlives: false,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: crossAxisCount,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 2.6,
                ),
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final model = visible[index];
                  return ModelCard(
                    model: model,
                    isSelected: model.id == widget.provider.activeModelId,
                    onSelect: widget.onSelect,
                    onEdit: widget.onEdit,
                    onDelete: canDelete
                        ? () => widget.onDelete(model.id)
                        : null,
                  );
                },
              );
            },
          ),
      ],
    );
  }
}
