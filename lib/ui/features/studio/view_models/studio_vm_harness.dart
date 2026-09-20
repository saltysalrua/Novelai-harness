part of 'studio_view_model.dart';

/// Agent Harness 装配 / LLM 与思考强度切换 / 预设技能工具 CRUD
mixin _StudioHarnessMixin on _StudioCore {
  bool _canCreateChatProvider(LlmProviderConfig provider) =>
      provider.apiKey.trim().isNotEmpty ||
      OpenAiCompatibleProvider.acceptsEmptyApiKey(provider.fullEndpointUrl);

  @override
  void _setupHarnessAndTools() {
    // 动态同步 SkillRegistry (先重置为内置，再注入最新自定义技能)
    _skillRegistry.resetToBuiltin();
    _skillRegistry.registerAll(_config.customSkills);

    // 配置更换使旧后台快照失效，并避免继续沿用旧模型用量。
    _harness.memoryChanged();
    // 重置工具注册表并注册全部内置工具
    _toolRegistry.clear();
    _toolRegistry.register(ContextMemoryTool(_harness));
    // Agent 生图发起前的"是否正在看最新图"快照 (与手动生图同语义，
    // 完成时叠加实时 isViewingLatest，避免新图已入历史后误报"有新图"横幅)
    var agentWasViewingLatest = false;
    _toolRegistry.register(
      NovelAiGenerateTool(
        repository: _repository,
        configService: _configService,
        getCurrentParams: () => _params,
        onBeforeGenerate: () {
          agentWasViewingLatest = isViewingLatest;
          if (_params.seedTiming == NaiSeedTiming.before) {
            _applySeedMutationBefore();
            notifyListeners();
          }
        },
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
          if (_params.seedTiming == NaiSeedTiming.after) {
            _applySeedMutationAfter(image.seed);
          }
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
    // AnySearch 网络搜索三件套 (web_search / get_search_domains / web_extract):
    // 密钥从 AppConfig 实时读取，未配置时匿名访问 (限流较低)
    String anySearchApiKeyGetter() {
      return _config.anySearchApiKey;
    }

    _toolRegistry.register(WebSearchTool(apiKeyGetter: anySearchApiKeyGetter));
    _toolRegistry.register(
      WebGetDomainsTool(apiKeyGetter: anySearchApiKeyGetter),
    );
    _toolRegistry.register(WebExtractTool(apiKeyGetter: anySearchApiKeyGetter));
    _toolRegistry.register(
      NovelAiAccountInfoTool(
        repository: _repository,
        configService: _configService,
      ),
    );
    _toolRegistry.register(AskUserTool(onAsk: _presentQuestionsToUser));
    _toolRegistry.register(
      NovelAiGetStudioParamsTool(
        getCurrentParams: () => _params,
        resolveEffectivePrompts: (params) =>
            resolveStudioEffectivePrompts(params, isComfyUi: isComfyUiMode),
      ),
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
      SetPromptLibraryPreviewTool(
        getEntries: () => promptLibraryEntries,
        updateEntry: updatePromptCombo,
        getHistory: () => _repository.history,
        // 内存缺失时从磁盘缓存回载大图字节，避免刚重启后的空字节
        loadImageBytes: ensureImageLoaded,
        savePreviewBytes: savePromptPreviewFromBytes,
        copyPreviewFromPath: savePromptPreviewFromPath,
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
        readResource: _skillPackageService.readResource,
        isModelMultimodal: () =>
            _config.activeLlmProvider.activeModel.isMultimodal,
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
    if (_canCreateChatProvider(activeLlm)) {
      final supportsThinking = activeModel.supportsThinking;
      final isReasoningActive =
          supportsThinking && _currentThinkingEffort != ThinkingEffort.none;

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
        cacheConfig: activeModel.cacheConfig,
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
    _harness.compactionEnabled = _config.agentCompactionEnabled;
    _harness.backgroundCompactionEnabled = _config.agentBackgroundCompaction;
    _harness.compactionProvider = null;
    _harness.compactionModelWindowTokens = activeModel.contextWindow;
    final summaryProvider = _config.llmProviders
        .where((p) => p.id == _config.compactionProviderId)
        .firstOrNull;
    final summaryModel = summaryProvider?.models
        .where((m) => m.id == _config.compactionModelId)
        .firstOrNull;
    if (summaryProvider != null &&
        summaryModel != null &&
        _canCreateChatProvider(summaryProvider)) {
      final compactionEffort = summaryModel.supportsThinking
          ? (summaryModel.supportsThinkingOff
                ? ThinkingEffort.none
                : summaryModel.defaultThinkingEffort)
          : null;
      _harness.compactionProvider = OpenAiCompatibleProvider(
        baseUrl: summaryProvider.fullEndpointUrl,
        apiKey: summaryProvider.apiKey,
        model: summaryModel.id,
        reasoning:
            compactionEffort != null && compactionEffort != ThinkingEffort.none,
        thinkingEffort: compactionEffort?.id,
        thinkingParamFormat: summaryProvider.thinkingParamFormat.id,
        cacheConfig: summaryModel.cacheConfig,
      );
      _harness.compactionModelWindowTokens = summaryModel.contextWindow;
    }
  }

  /// 动态调整 Agent 思考强度 (在对话工作台中随点随切)
  void setThinkingEffort(ThinkingEffort effort) {
    final normalized = _config.activeLlmProvider.activeModel
        .normalizeThinkingEffort(effort);
    if (_currentThinkingEffort == normalized) return;
    _currentThinkingEffort = normalized;
    _setupHarnessAndTools();
    _sessionLog.recordThinkingLevelChange(normalized.id);
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

  Future<T> _withSkillWrite<T>(Future<T> Function() operation) {
    final result = _skillWriteQueue.then((_) => operation());
    _skillWriteQueue = result.then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {},
    );
    return result;
  }

  Future<SkillPackage> readSkillImportFile(String path) =>
      _skillPackageService.readImportFile(path);
  Future<SkillPackage> readSkillImportDirectory(String path) =>
      _skillPackageService.readImportDirectory(path);
  Future<Uint8List> exportSkillPackage(Skill skill) =>
      _skillPackageService.exportPackage(skill);
  Future<void> writeSkillExportFile(String path, Uint8List bytes) =>
      _skillPackageService.writeExportFile(path, bytes);

  /// 确认后才安装。重名拒绝覆盖（可在编辑框改 ID），配置提交失败清理本次安装。
  Future<Skill> importSkillPackage(SkillPackage package, Skill edited) =>
      _withSkillWrite(() async {
        _checkSkillConflict(edited.id);
        if (package.skill.resourcePaths.isNotEmpty) {
          SkillPackageService.validateSkill(edited);
        }
        final installed = await _skillPackageService.install(package, edited);
        try {
          await _saveSkill(installed, requireNew: true);
          return installed;
        } catch (_) {
          await _discardSkillPackage(installed);
          rethrow;
        }
      });

  void _checkSkillConflict(String id, {String? originalId}) {
    if (id.trim().isEmpty) throw FormatException(vmL10n.skillIdEmptyError);
    final conflict = availableSkills.any(
      (s) => s.id.toLowerCase() == id.toLowerCase() && s.id != originalId,
    );
    if (conflict) throw FormatException(vmL10n.skillDuplicateId(id));
  }

  /// 编辑保留托管资源；改 ID 时同步预设引用，避免旧条目与资源丢失。
  Future<void> saveCustomSkill(
    Skill skill, {
    String? originalId,
    bool requireNew = false,
  }) => _withSkillWrite(
    () => _saveSkill(skill, originalId: originalId, requireNew: requireNew),
  );

  Future<void> _saveSkill(
    Skill skill, {
    String? originalId,
    bool requireNew = false,
  }) async {
    final oldId = requireNew ? null : (originalId ?? skill.id);
    _checkSkillConflict(skill.id, originalId: oldId);
    final old = oldId == null ? null : _skillRegistry.get(oldId);
    if (old?.isBuiltin == true && skill.id != old!.id) {
      throw FormatException(vmL10n.skillDuplicateId(skill.id));
    }
    final saved = old == null
        ? skill
        : skill.copyWith(
            packageId: old.packageId,
            resourcePaths: old.resourcePaths,
            isBuiltin: old.isBuiltin,
          );
    final customList = _config.customSkills.where((s) => s.id != oldId).toList()
      ..add(saved);
    final updatedPresets = _config.presets
        .map(
          (preset) => oldId != null && oldId != saved.id
              ? preset.copyWith(
                  enabledSkillIds: preset.enabledSkillIds
                      .map((id) => id == oldId ? saved.id : id)
                      .toList(),
                )
              : preset,
        )
        .toList();
    await _commitSkillConfig(
      _config.copyWith(customSkills: customList, presets: updatedPresets),
    );
  }

  Future<void> _commitSkillConfig(AppConfig next) async {
    final previous = _config;
    _config = next;
    try {
      await _configService.saveConfig(next);
    } catch (_) {
      if (identical(_config, next)) _config = previous;
      rethrow;
    }
    _setupHarnessAndTools();
    notifyListeners();
  }

  Future<void> _discardSkillPackage(Skill skill) async {
    try {
      await _skillPackageService.deletePackage(skill);
    } catch (error) {
      // 已提交的配置不回滚；清理失败最多遗留不可寻址的托管资源。
      debugPrint('Skill package cleanup failed: $error');
    }
  }

  /// 先提交移除配置，再清理托管包；绝不删除用户导入源。
  Future<void> deleteCustomSkill(String skillId) => _withSkillWrite(() async {
    final old = _skillRegistry.get(skillId);
    if (old == null || old.isBuiltin) return;
    await _commitSkillConfig(
      _config.copyWith(
        customSkills: _config.customSkills
            .where((s) => s.id != skillId)
            .toList(),
        presets: _config.presets
            .map(
              (preset) => preset.copyWith(
                enabledSkillIds: preset.enabledSkillIds
                    .where((id) => id != skillId)
                    .toList(),
              ),
            )
            .toList(),
      ),
    );
    if (!_config.customSkills.any((s) => s.packageId == old.packageId)) {
      await _discardSkillPackage(old);
    }
  });

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
