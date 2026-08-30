import 'package:flutter/material.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/config_service.dart';
import '../../../../data/services/llm_model_fetcher.dart';
import '../../../core/theme/app_theme.dart';
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
  }

  late final List<LlmProviderConfig> providers;
  late String selectedProviderId;
  late final TextEditingController nameController;
  late final TextEditingController baseUrlController;
  late final TextEditingController apiKeyController;
  late LlmProtocol protocol;

  /// 思考参数请求格式 (不同供应商用不同字段开关思维链)
  late ThinkingParamFormat thinkingParamFormat;

  // 在线拉取状态
  bool isFetchingModels = false;
  String? fetchStatusMessage;
  bool isFetchSuccess = false;

  LlmProviderConfig get currentProvider => providers.firstWhere(
    (p) => p.id == selectedProviderId,
    orElse: () => providers.first,
  );

  /// 将表单内容写回当前供应商条目 (切换 / 保存 / 拉取前调用)
  void syncFromForm() {
    final idx = providers.indexWhere((p) => p.id == selectedProviderId);
    if (idx >= 0) {
      providers[idx] = providers[idx].copyWith(
        name: nameController.text.trim().isEmpty
            ? '自定义供应商'
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
  void switchProvider(String newProviderId) {
    if (newProviderId == selectedProviderId) return;
    syncFromForm();
    loadProviderToForm(providers.firstWhere((p) => p.id == newProviderId));
  }

  /// 新建供应商并载入表单
  void addNewProvider() {
    syncFromForm();
    final newProvider = LlmProviderConfig(
      id: 'provider_${DateTime.now().millisecondsSinceEpoch}',
      name: '新供应商 ${providers.length + 1}',
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

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _draft.baseUrlController.addListener(_onFieldChanged);
    _draft.nameController.addListener(_onFieldChanged);
  }

  @override
  void dispose() {
    _draft.baseUrlController.removeListener(_onFieldChanged);
    _draft.nameController.removeListener(_onFieldChanged);
    super.dispose();
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
    _draft.syncFromForm();
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
    final baseUrl = _draft.baseUrlController.text.trim();
    final apiKey = _draft.apiKeyController.text.trim();

    if (baseUrl.isEmpty) {
      setState(() {
        _draft.isFetchSuccess = false;
        _draft.fetchStatusMessage = '请先填写有效的 API 基础 URL';
      });
      return;
    }

    setState(() {
      _draft.isFetchingModels = true;
      _draft.fetchStatusMessage = null;
    });

    try {
      _draft.syncFromForm();
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
        _draft.fetchStatusMessage =
            '成功拉取 ${result.models.length} 个模型'
            '${result.enrichedCount > 0 ? '，${result.enrichedCount} 个已匹配 models.dev 元数据' : ''}';
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
    final fullEndpoint = _calculateFullEndpoint(
      _draft.baseUrlController.text,
      _draft.protocol,
    );
    final currentProvider = _draft.currentProvider;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. 供应商切换与管理
        const SettingsGroupTitle('Provider Selection'),
        SettingsCard(
          title: '当前供应商',
          subtitle: '选择要配置的 AI 服务商，或添加自定义供应商',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SettingsIdDropdown(
                value: _draft.selectedProviderId,
                items: _draft.providers
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
                  if (val != null) {
                    setState(() => _draft.switchProvider(val));
                  }
                },
              ),
              const SizedBox(width: 8),
              SettingsActionButton(
                icon: Icons.add_rounded,
                label: '新建',
                onPressed: () => setState(() => _draft.addNewProvider()),
              ),
              if (_draft.providers.length > 1) ...[
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    size: 18,
                    color: AppTheme.stone,
                  ),
                  tooltip: '删除当前供应商',
                  onPressed: () =>
                      setState(() => _draft.deleteCurrentProvider()),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(height: 12),
        // 2. 供应商基本信息与端点
        const SettingsGroupTitle('Provider Profile & Endpoint'),
        SettingsCard(
          title: '供应商名称',
          subtitle: '在界面与下拉菜单中显示的自定义标识',
          control: SizedBox(
            width: 240,
            height: 36,
            child: TextField(
              controller: _draft.nameController,
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
        SettingsCard(
          title: 'API 接口与协议',
          subtitle: '服务基础 URL 与对应的通讯协议格式',
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
                    value: _draft.protocol,
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
                        setState(() => _draft.protocol = val);
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
        SettingsCard(
          title: 'LLM API Key',
          subtitle: '访问该供应商所需的身份密钥',
          control: SettingsKeyField(
            controller: _draft.apiKeyController,
            hintText: 'sk-...',
            width: 260,
          ),
        ),
        SettingsCard(
          title: '思考参数格式',
          subtitle: '不同供应商用不同字段开关思维链，格式不匹配时思考会被静默丢弃；中转站请按其上游格式指定',
          control: SettingsDropdown<ThinkingParamFormat>(
            value: _draft.thinkingParamFormat,
            items: ThinkingParamFormat.values,
            labelBuilder: (f) => f.label,
            onChanged: (val) {
              if (val != null) {
                setState(() => _draft.thinkingParamFormat = val);
              }
            },
          ),
        ),

        const SizedBox(height: 12),
        // 3. 模型列表与在线拉取
        const SettingsGroupTitle('Models'),
        SettingsCard(
          title: '模型列表',
          subtitle: '点击卡片切换当前模型，设置按钮调整模型参数与能力档案',
          control: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 在线拉取模型按钮
              ElevatedButton.icon(
                onPressed: _draft.isFetchingModels
                    ? null
                    : _fetchRemoteModelsOnline,
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
                icon: _draft.isFetchingModels
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
                  _draft.isFetchingModels ? '拉取中...' : '在线拉取模型',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              SettingsActionButton(
                icon: Icons.add_rounded,
                label: '添加模型',
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
                        ? AppTheme.success.withValues(alpha: 0.1)
                        : AppTheme.error.withValues(alpha: 0.08),
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
                            ? AppTheme.success
                            : AppTheme.error,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          _draft.fetchStatusMessage!,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: _draft.isFetchSuccess
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
                    onSelect: (m) =>
                        setState(() => _draft.setActiveModel(m.id)),
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
}
