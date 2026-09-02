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
enum _ModelSortMode {
  defaultOrder('默认顺序'),
  nameAsc('名称 A-Z'),
  nameDesc('名称 Z-A');

  const _ModelSortMode(this.label);
  final String label;
}

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

  /// 头部：供应商选择 / 端点表单 / 拉取操作区 (不含模型网格)
  Widget _buildHeaderSections() {
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
          // 端点预览只随 URL 输入局部刷新，不触发整页 setState
          bottomChild: ListenableBuilder(
            listenable: _draft.baseUrlController,
            builder: (context, _) {
              final fullEndpoint = _calculateFullEndpoint(
                _draft.baseUrlController.text,
                _draft.protocol,
              );
              return Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
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
              );
            },
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
        const SizedBox(height: 12),
        // 4. AI 整图编辑绘图模型 (独立于对话 LLM 的供应商与模型选择)
        const SettingsGroupTitle('AI 整图编辑'),
        SettingsCard(
          title: '绘图模型',
          subtitle:
              '修复页「AI 整图编辑」使用的供应商与模型 (仅列出绘图模型)，独立于对话 LLM；需选择具备图像输出能力的模型 (如 nano banana / gpt-image)',
          control: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SettingsIdDropdown(
                value: _draft.imageEditProviderId,
                items: [
                  const DropdownMenuItem<String>(value: '', child: Text('未配置')),
                  ..._draft.providers.map(
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
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _draft.setImageEditProvider(val));
                  }
                },
              ),
              const SizedBox(width: 8),
              SettingsIdDropdown(
                value: _draft.imageEditModelId,
                items: [
                  const DropdownMenuItem<String>(
                    value: '',
                    child: Text('未选择模型'),
                  ),
                  ..._draft.imageEditProviderModels.map(
                    (m) => DropdownMenuItem<String>(
                      value: m.id,
                      child: Text(
                        m.name,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  // 防悬挂兜底：当前选中的模型被改掉能力或删除时仍保留下拉项，
                  // 避免 DropdownButton value 不在 items 里断言
                  if (_draft.imageEditModelId.isNotEmpty &&
                      !_draft.imageEditProviderModels.any(
                        (m) => m.id == _draft.imageEditModelId,
                      ))
                    DropdownMenuItem<String>(
                      value: _draft.imageEditModelId,
                      child: Text(
                        '${_draft.imageEditModelId} (未识别为绘图模型)',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() => _draft.setImageEditModel(val));
                  }
                },
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
            child: const Row(
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: AppTheme.notionBlue,
                ),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '整图编辑不消耗 Anlas 点数，计费走绘图模型供应商；未识别到能力的模型可在模型设置中手动开启「图像输出」',
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppTheme.textSecondary,
                    ),
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
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 0),
          sliver: SliverToBoxAdapter(child: _buildHeaderSections()),
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
    final total = widget.provider.models.length;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
            width: 280,
            height: 36,
            child: TextField(
              controller: _searchController,
              style: const TextStyle(fontSize: 12),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索模型名称或 ID',
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  size: 16,
                  color: AppTheme.stone,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          size: 14,
                          color: AppTheme.stone,
                        ),
                        tooltip: '清空搜索',
                        onPressed: () => _searchController.clear(),
                      ),
                filled: true,
                fillColor: AppTheme.paperWarmth,
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
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
          ),
          const SizedBox(width: 8),
          SettingsDropdown<_ModelSortMode>(
            value: _sortMode,
            items: _ModelSortMode.values,
            labelBuilder: (m) => m.label,
            onChanged: (val) {
              if (val != null) setState(() => _sortMode = val);
            },
          ),
          const SizedBox(width: 8),
          // 仅绘图模型过滤 (快速定位图像输出能力的模型)
          Tooltip(
            message: '仅显示具备图像输出能力的模型 (如 nano banana / gpt-image)',
            child: InkWell(
              onTap: () => setState(() => _imageOnly = !_imageOnly),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: _imageOnly
                      ? AppTheme.notionBlue.withValues(alpha: 0.12)
                      : AppTheme.paperWarmth,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: _imageOnly
                        ? AppTheme.notionBlue.withValues(alpha: 0.4)
                        : AppTheme.border,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.auto_awesome,
                      size: 13,
                      color: _imageOnly ? AppTheme.notionBlue : AppTheme.stone,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '仅绘图模型',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: _imageOnly
                            ? AppTheme.notionBlue
                            : AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const Spacer(),
          Text(
            '$visibleCount / $total 个模型',
            style: const TextStyle(fontSize: 11.5, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final models = widget.provider.models;

    // 供应商没有任何模型
    if (models.isEmpty) {
      return SliverToBoxAdapter(
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
      );
    }

    final visible = _visibleModels;
    final canDelete = models.length > 1;

    return SliverMainAxisGroup(
      slivers: [
        SliverToBoxAdapter(child: _buildToolbar(visible.length)),
        if (visible.isEmpty)
          SliverToBoxAdapter(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
              decoration: BoxDecoration(
                color: AppTheme.paperWarmth,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppTheme.border),
              ),
              child: Text(
                '没有匹配 "${_searchController.text.trim()}" 的模型',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
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
