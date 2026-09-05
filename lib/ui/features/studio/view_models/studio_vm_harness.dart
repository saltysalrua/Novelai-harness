part of 'studio_view_model.dart';

/// Agent Harness 装配 / LLM 与思考强度切换 / 预设技能工具 CRUD
mixin _StudioHarnessMixin on _StudioCore {
  @override
  void _setupHarnessAndTools() {
    // 动态同步 SkillRegistry (先重置为内置，再注入最新自定义技能)
    _skillRegistry.resetToBuiltin();
    _skillRegistry.registerAll(_config.customSkills);

    // 重置工具注册表并注册全部内置工具
    _toolRegistry.clear();
    // Agent 生图发起前的"是否正在看最新图"快照 (与手动生图同语义，
    // 完成时叠加实时 isViewingLatest，避免新图已入历史后误报"有新图"横幅)
    var agentWasViewingLatest = false;
    _toolRegistry.register(
      NovelAiGenerateTool(
        repository: _repository,
        configService: _configService,
        getCurrentParams: () => _params,
        onBeforeGenerate: () => agentWasViewingLatest = isViewingLatest,
        onProgress: (progress) {
          if (progress.isFinal) {
            _liveProgressController.complete();
          } else {
            // 首帧把生成中状态点亮 (结构变化全局通知一次)，
            // 后续中间帧只驱动画板占位卡/缩略图/按钮局部刷新
            if (!_isGenerating) {
              _isGenerating = true;
              notifyListeners();
            }
            _liveProgressController.updateFrame(
              previewBytes: progress.previewImage,
              currentStep: progress.currentStep,
              totalSteps: progress.totalSteps,
              progress: progress.progress,
            );
          }
        },
        onGenerated: (image) {
          _isGenerating = false;
          _liveProgressController.clear();
          _applyGeneratedImage(
            image,
            // 发起前在看最新，或生成期间滚回顶部看预览，都视为正在看最新
            wasViewingLatest: agentWasViewingLatest || isViewingLatest,
          );
          notifyListeners();
          refreshAccountInfo();
        },
        onConfirmPaidGeneration: _confirmPaidGeneration,
        getAccountInfo: () => _accountInfo,
      ),
    );
    _toolRegistry.register(
      NovelAiUpscaleTool(
        repository: _repository,
        configService: _configService,
        onUpscaled: (image) {
          _selectedImage = image;
          notifyListeners();
        },
        getAccountInfo: () => _accountInfo,
        onConfirmPaidUpscale: _confirmPaidUpscale,
      ),
    );
    _toolRegistry.register(
      NovelAiInpaintTool(
        repository: _repository,
        configService: _configService,
        getCurrentParams: () => _params,
        onBeforeGenerate: () => agentWasViewingLatest = isViewingLatest,
        onProgress: (progress) {
          if (progress.isFinal) {
            _liveProgressController.complete();
          } else {
            // 首帧把生成中状态点亮 (结构变化全局通知一次)，
            // 后续中间帧只驱动画板占位卡/缩略图/按钮局部刷新
            if (!_isGenerating) {
              _isGenerating = true;
              notifyListeners();
            }
            _liveProgressController.updateFrame(
              previewBytes: progress.previewImage,
              currentStep: progress.currentStep,
              totalSteps: progress.totalSteps,
              progress: progress.progress,
            );
          }
        },
        onGenerated: (image) {
          _isGenerating = false;
          _liveProgressController.clear();
          _applyGeneratedImage(
            image,
            wasViewingLatest: agentWasViewingLatest || isViewingLatest,
          );
          notifyListeners();
          refreshAccountInfo();
        },
        onConfirmPaidGeneration: _confirmPaidGeneration,
        getAccountInfo: () => _accountInfo,
      ),
    );
    _toolRegistry.register(NovelAiInpaintGeometryTool(repository: _repository));
    _toolRegistry.register(
      AiEditImageTool(
        repository: _repository,
        configService: _configService,
        onBeforeGenerate: () => agentWasViewingLatest = isViewingLatest,
        onGenerated: (image) {
          _isGenerating = false;
          _liveProgressController.clear();
          _applyGeneratedImage(
            image,
            wasViewingLatest: agentWasViewingLatest || isViewingLatest,
          );
          notifyListeners();
        },
      ),
    );
    _toolRegistry.register(
      NovelAiSuggestTagsTool(
        repository: _repository,
        configService: _configService,
      ),
    );
    _toolRegistry.register(DanbooruSearchTagsTool());
    _toolRegistry.register(DanbooruRelatedTagsTool());
    _toolRegistry.register(DanbooruRecommendArtistsTool());
    _toolRegistry.register(
      NovelAiAccountInfoTool(
        repository: _repository,
        configService: _configService,
      ),
    );
    _toolRegistry.register(AskUserTool(onAsk: _presentQuestionsToUser));
    _toolRegistry.register(
      NovelAiGetStudioParamsTool(getCurrentParams: () => _params),
    );
    _toolRegistry.register(
      NovelAiUpdateParamsTool(
        getCurrentParams: () => _params,
        onUpdateParams: updateParams,
        permissionChecker: (key) =>
            _harness.currentPreset.isParamModifiable(key),
      ),
    );
    _toolRegistry.register(
      NovelAiListCharacterPromptsTool(
        getCharacterPrompts: () => _params.characterPrompts,
        getAiPosition: () => _params.characterAiPosition,
      ),
    );
    _toolRegistry.register(
      NovelAiAddCharacterPromptTool(
        getCharacterPrompts: () => _params.characterPrompts,
        updateCharacterPrompts: _setCharacterPrompts,
        getCharacterLimit: () => _params.model.maxCharacterPrompts,
      ),
    );
    _toolRegistry.register(
      NovelAiUpdateCharacterPromptTool(
        getCharacterPrompts: () => _params.characterPrompts,
        updateCharacterPrompts: _setCharacterPrompts,
      ),
    );
    _toolRegistry.register(
      NovelAiRemoveCharacterPromptTool(
        getCharacterPrompts: () => _params.characterPrompts,
        updateCharacterPrompts: _setCharacterPrompts,
      ),
    );
    _toolRegistry.register(
      ViewCanvasImageTool(
        getHistory: () => _repository.history,
        isModelMultimodal: () =>
            _config.activeLlmProvider.activeModel.isMultimodal,
      ),
    );
    // Agent 批注增删改查四件套工具：写入口统一走 board.replaceImageAnnotations
    // (阶段4D 试点：BoardController 域内方法，同步仓库持久化与大画布)
    _toolRegistry.register(
      ViewImageAnnotationsTool(
        getHistory: () => _repository.history,
        isModelMultimodal: () =>
            _config.activeLlmProvider.activeModel.isMultimodal,
      ),
    );
    _toolRegistry.register(
      AddImageAnnotationTool(
        getHistory: () => _repository.history,
        writeAnnotations: board.replaceImageAnnotations,
      ),
    );
    _toolRegistry.register(
      UpdateImageAnnotationTool(
        getHistory: () => _repository.history,
        writeAnnotations: board.replaceImageAnnotations,
      ),
    );
    _toolRegistry.register(
      RemoveImageAnnotationTool(
        getHistory: () => _repository.history,
        writeAnnotations: board.replaceImageAnnotations,
      ),
    );
    _toolRegistry.register(
      ClearImageAnnotationsTool(
        getHistory: () => _repository.history,
        writeAnnotations: board.replaceImageAnnotations,
      ),
    );
    _toolRegistry.register(
      SearchPromptLibraryTool(getEntries: () => promptLibraryEntries),
    );
    _toolRegistry.register(
      AddPromptLibraryEntryTool(
        getEntries: () => promptLibraryEntries,
        addEntry: addPromptCombo,
      ),
    );
    _toolRegistry.register(
      UpdatePromptLibraryEntryTool(
        getEntries: () => promptLibraryEntries,
        updateEntry: updatePromptCombo,
      ),
    );
    _toolRegistry.register(
      DeletePromptLibraryEntryTool(
        getEntries: () => promptLibraryEntries,
        deleteEntry: deletePromptCombo,
      ),
    );
    _toolRegistry.register(
      LoadSkillTool(
        // 仅允许加载当前预设开放的技能，防止越权读取
        skillResolver: (name) {
          final skill = _skillRegistry.get(name);
          if (skill == null) return null;
          return _harness.currentPreset.enabledSkillIds.contains(skill.id)
              ? skill
              : null;
        },
        availableSkillIds: () =>
            _harness.currentPreset.enabledSkillIds.toList(),
      ),
    );

    // 注册自定义扩展工具
    for (final customTool in _config.customTools) {
      _toolRegistry.register(customTool);
    }

    // 配置 LLM Provider
    final activeLlm = _config.activeLlmProvider;
    final activeModel = activeLlm.activeModel;
    // 供应商标识优先用用户设定的名称 (id 可能是迁移生成的 provider_时间戳)
    _harness.providerLabel = activeLlm.name.isNotEmpty
        ? activeLlm.name
        : activeLlm.id;
    if (activeLlm.apiKey.isNotEmpty) {
      final supportsThinking = activeModel.supportsThinking;
      final isReasoningActive =
          supportsThinking && _currentThinkingEffort != ThinkingEffort.off;

      _harness.provider = OpenAiCompatibleProvider(
        baseUrl: activeLlm.fullEndpointUrl,
        apiKey: activeLlm.apiKey,
        model: activeModel.id,
        reasoning: isReasoningActive,
        // 思考等级始终透传 (含 off)：Qwen/DeepSeek/Z.ai 等格式的端点
        // 关闭思考也需要显式发送 disabled 参数，不能靠省略字段
        thinkingEffort: supportsThinking ? _currentThinkingEffort.id : null,
        // 思考参数格式 (对齐 pi thinkingFormat 兼容矩阵，中转站可手动指定)
        thinkingParamFormat: activeLlm.thinkingParamFormat.id,
      );
    } else {
      _harness.provider = null;
    }

    // 动态同步当前生效预设实例到 _harness (确保工具白名单与参数权限始终与配置保持一致)
    final targetPresetId = _config.activePresetId;
    final activePreset = _config.presets.firstWhere(
      (p) => p.id == targetPresetId,
      orElse: () => _config.presets.firstWhere(
        (p) => p.id == _harness.currentPreset.id,
        orElse: () => _config.presets.isNotEmpty
            ? _config.presets.first
            : BuiltinPresets.v5Architect,
      ),
    );
    _harness.setPreset(activePreset);

    // 长程配置：单次对话最大工具轮数 (设置页 Defaults 可调)
    _harness.maxTurns = _config.agentMaxTurns;
    // 上下文压缩窗口：按当前模型卡片的上下文窗口自适应触发
    _harness.contextWindowTokens = activeModel.contextWindow;
  }

  /// 动态调整 Agent 思考强度 (在对话工作台中随点随切)
  void setThinkingEffort(ThinkingEffort effort) {
    if (_currentThinkingEffort == effort) return;
    _currentThinkingEffort = effort;
    _setupHarnessAndTools();
    _sessionLog.recordThinkingLevelChange(effort.id);
    notifyListeners();
  }

  /// 动态切换当前生效的大模型 (在对话工作台中即时切换)
  void switchActiveModel(String modelId) {
    final activeProvider = _config.activeLlmProvider;
    if (!activeProvider.models.any((m) => m.id == modelId)) return;

    final updatedProviders = _config.llmProviders.map((p) {
      if (p.id == activeProvider.id) {
        return p.copyWith(activeModelId: modelId);
      }
      return p;
    }).toList();

    _config = _config.copyWith(llmProviders: updatedProviders);
    final targetModel = activeProvider.models.firstWhere(
      (m) => m.id == modelId,
    );
    _currentThinkingEffort = targetModel.defaultThinkingEffort;

    _configService.saveConfig(_config);
    _sessionLog.recordModelChange(activeProvider.id, modelId);
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 动态切换当前生效的供应商
  void switchActiveProvider(String providerId) {
    if (!_config.llmProviders.any((p) => p.id == providerId)) return;
    _config = _config.copyWith(activeLlmProviderId: providerId);
    _currentThinkingEffort =
        _config.activeLlmProvider.activeModel.defaultThinkingEffort;

    _configService.saveConfig(_config);
    _sessionLog.recordModelChange(
      providerId,
      _config.activeLlmProvider.activeModel.id,
    );
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 立即持久化 LLM 供应商列表 (设置对话框在线拉取后写盘，避免忘记点保存丢失)
  Future<void> persistLlmProviders(
    List<LlmProviderConfig> providers,
    String activeProviderId,
  ) async {
    _config = _config.copyWith(
      llmProviders: providers,
      activeLlmProviderId: activeProviderId,
    );
    _currentThinkingEffort =
        _config.activeLlmProvider.activeModel.defaultThinkingEffort;

    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }

  // ------------------------- 预设管理 -------------------------

  /// 切换 Agent 当前预设
  @override
  void selectPreset(AgentPreset preset) {
    _harness.setPreset(preset);
    _config = _config.copyWith(activePresetId: preset.id);
    _configService.saveConfig(_config);
    _harness.addInfoMessage(
      vmL10n.vmPresetSwitched(preset.name, preset.description),
    );
    notifyListeners();
  }

  /// 保存/更新预设配置
  Future<void> savePreset(AgentPreset preset) async {
    final currentList = presets.toList();
    final index = currentList.indexWhere((p) => p.id == preset.id);
    if (index >= 0) {
      currentList[index] = preset;
    } else {
      currentList.add(preset);
    }
    _config = _config.copyWith(presets: currentList);
    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 删除自定义预设
  Future<void> deletePreset(String presetId) async {
    if (presets.length <= 1) return;
    final currentList = presets.where((p) => p.id != presetId).toList();
    var activeId = _config.activePresetId;
    if (activeId == presetId) {
      activeId = currentList.first.id;
    }
    _config = _config.copyWith(presets: currentList, activePresetId: activeId);
    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }

  // ------------------------- 技能管理 -------------------------

  /// 保存/更新自定义技能
  Future<void> saveCustomSkill(Skill skill) async {
    final customList = _config.customSkills.toList();
    final idx = customList.indexWhere((s) => s.id == skill.id);
    if (idx >= 0) {
      customList[idx] = skill;
    } else {
      customList.add(skill);
    }
    _config = _config.copyWith(customSkills: customList);
    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 删除自定义技能
  Future<void> deleteCustomSkill(String skillId) async {
    final customList = _config.customSkills
        .where((s) => s.id != skillId)
        .toList();
    _config = _config.copyWith(customSkills: customList);
    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 从标准 SKILL.md 导入技能
  Future<Skill> importSkillFromMd(String mdContent, {String? defaultId}) async {
    final skill = Skill.fromSkillMd(mdContent, defaultId: defaultId);
    await saveCustomSkill(skill);
    return skill;
  }

  // ------------------------- 自定义工具管理 -------------------------

  /// 保存/更新自定义扩展工具
  Future<void> saveCustomTool(CustomAgentTool tool) async {
    final customTools = _config.customTools.toList();
    final idx = customTools.indexWhere((t) => t.name == tool.name);
    if (idx >= 0) {
      customTools[idx] = tool;
    } else {
      customTools.add(tool);
    }
    _config = _config.copyWith(customTools: customTools);
    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }

  /// 删除自定义扩展工具
  Future<void> deleteCustomTool(String toolName) async {
    final customTools = _config.customTools
        .where((t) => t.name != toolName)
        .toList();
    _config = _config.copyWith(customTools: customTools);
    await _configService.saveConfig(_config);
    _setupHarnessAndTools();
    notifyListeners();
  }
}
