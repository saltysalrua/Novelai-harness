part of 'studio_view_model.dart';

/// 词组合预设库分部 (Prompt Combo Library)
mixin _StudioLibraryMixin on _StudioCore {
  /// 当前词组合条目列表 (返回已冻结快照，避免每次读取分配新列表)
  @override
  List<PromptComboEntry> get promptLibraryEntries => _promptLibraryEntries;

  /// 当前词库待整理区条目列表 (返回已冻结快照)
  @override
  List<PromptInboxItem> get promptInboxItems => _promptInboxItems;

  /// 云同步状态与配置
  bool get isSyncingPromptLibrary => _isSyncingPromptLibrary;
  String? get promptSyncStage => _promptSyncStage;
  DateTime? get lastPromptSyncAt => _lastPromptSyncAt;
  PromptLibrarySyncResult? get lastPromptSyncResult => _lastPromptSyncResult;
  String? get lastPromptSyncError => _lastPromptSyncError;
  bool get isPromptAutoSyncEnabled => _config.promptSyncAutoEnabled;
  int get promptAutoSyncIntervalMinutes =>
      promptLibrarySyncConfig.normalizedAutoSyncIntervalMinutes;
  PromptLibrarySyncConfig get promptLibrarySyncConfig => PromptLibrarySyncConfig(
    endpoint: _config.promptSyncEndpoint,
    token: _config.promptSyncToken,
    namespace: _config.promptSyncNamespace,
    autoSyncEnabled: _config.promptSyncAutoEnabled,
    autoSyncIntervalMinutes: _config.promptSyncAutoIntervalMinutes,
  );

  @visibleForTesting
  set promptAutoSyncDebounceDelayForTest(Duration delay) {
    _promptAutoSyncDebounceDelay = delay;
  }

  /// 加载词组合列表与待整理区列表
  Future<void> loadPromptLibrary() async {
    try {
      final entries = await _promptLibraryService.loadEntries();
      final inboxItems = await _promptLibraryService.loadInboxItems();
      final syncState = await _promptLibraryService.loadSyncState();
      _promptLibraryEntries = List.unmodifiable(entries);
      _promptInboxItems = List.unmodifiable(inboxItems);
      _lastPromptSyncAt = syncState.lastSyncAt;
      promptLibraryNotifier.value++;
      notifyListeners();
    } catch (_) {}
  }

  /// 词库内容变更后同步刷新内存与自动补全缓存
  Future<List<PromptComboEntry>> _reloadPromptLibrary() async {
    final entries = await _promptLibraryService.loadEntries();
    _promptLibraryEntries = List.unmodifiable(entries);
    // 词组合会注入标签自动补全建议，清掉查询缓存避免陈旧条目残留
    TagDictionaryService.instance.clearQueryCache();
    promptLibraryNotifier.value++;
    notifyListeners();
    return entries;
  }

  /// 待整理区内容变更后同步刷新内存与通知器
  Future<List<PromptInboxItem>> _reloadPromptInbox() async {
    final items = await _promptLibraryService.loadInboxItems();
    _promptInboxItems = List.unmodifiable(items);
    promptLibraryNotifier.value++;
    notifyListeners();
    return items;
  }

  /// 添加新词组合条目
  @override
  Future<PromptComboEntry> addPromptCombo(PromptComboEntry entry) async {
    final created = await _promptLibraryService.addEntry(entry);
    await _reloadPromptLibrary();
    _scheduleAutoPromptSync();
    return created;
  }

  /// 更新词组合条目
  @override
  Future<void> updatePromptCombo(PromptComboEntry entry) async {
    await _promptLibraryService.updateEntry(entry);
    await _reloadPromptLibrary();
    _scheduleAutoPromptSync();
  }

  /// 删除词组合条目
  @override
  Future<void> deletePromptCombo(String id) async {
    await _promptLibraryService.deleteEntry(id);
    await _reloadPromptLibrary();
    _scheduleAutoPromptSync();
  }

  // ------------------------- 待整理区 (Inbox) -------------------------

  /// 将画板/历史图片及其提示词（含主提示词与角色提示词，不含固定词缀）保存到词库待整理区
  Future<PromptInboxItem?> saveImageToPromptInbox(
    NaiGeneratedImage image,
  ) async {
    final bytes = await ensureImageLoaded(image) ?? image.bytes;
    String? savedImagePath;
    if (bytes.isNotEmpty) {
      final scaled = await downscalePreviewBytes(bytes);
      savedImagePath = await _promptLibraryService.savePreviewImageBytes(
        scaled,
        extension: 'png',
        prefix: 'inbox',
      );
    }

    var baseParams = image.params;
    // 外部导入图若仅有占位 prompt，尝试从原图 PNG 元数据中提取主提示词与角色提示词
    if (image.isImportedReference &&
        bytes.isNotEmpty &&
        (baseParams.prompt.trim().isEmpty ||
            baseParams.prompt.trim() == '导入参考图' ||
            baseParams.prompt.trim() == '参考图')) {
      try {
        final parsed = await ImageMetadataService.parseMetadataAsync(bytes);
        if (parsed != null && parsed.hasData) {
          final parsedChars = <NaiCharacterPrompt>[];
          for (var i = 0; i < parsed.characterPrompts.length; i++) {
            final pText = parsed.characterPrompts[i].trim();
            if (pText.isEmpty) continue;
            final ucText = i < parsed.characterNegativePrompts.length
                ? parsed.characterNegativePrompts[i].trim()
                : '';
            parsedChars.add(
              NaiCharacterPrompt(
                id: 'inbox_char_${i + 1}',
                name: vmL10n.vmCharacterDefaultName(i + 1),
                prompt: pText,
                negativePrompt: ucText,
              ),
            );
          }
          baseParams = baseParams.copyWith(
            prompt: parsed.prompt.trim(),
            negativePrompt: parsed.negativePrompt.trim(),
            characterPrompts: parsedChars,
          );
        }
      } catch (_) {}
    }

    // 显式排除固定词缀：PromptInboxItem.fromGenerationParams 只取 params.prompt / negativePrompt / enabledCharacterPrompts
    final item = PromptInboxItem.fromGenerationParams(
      baseParams,
      imagePath: savedImagePath,
    );
    if (!item.hasContent) return null;

    final created = await _promptLibraryService.addInboxItem(item);
    await _reloadPromptInbox();
    return created;
  }

  /// 更新待整理区条目（用于详情弹窗内手动编辑主/角色提示词）
  Future<void> updatePromptInboxItem(PromptInboxItem item) async {
    await _promptLibraryService.updateInboxItem(item);
    await _reloadPromptInbox();
  }

  /// 删除单条待整理区条目
  Future<void> deletePromptInboxItem(String id) async {
    await deletePromptInboxItems([id]);
  }

  /// 批量删除待整理区条目
  @override
  Future<int> deletePromptInboxItems(Iterable<String> ids) async {
    final removed = await _promptLibraryService.deleteInboxItems(ids);
    if (removed > 0) {
      await _reloadPromptInbox();
    }
    return removed;
  }

  /// 清空待整理区
  Future<void> clearPromptInbox() async {
    await _promptLibraryService.clearInboxItems();
    await _reloadPromptInbox();
  }

  // ------------------------- 待整理区后台整理 Agent -------------------------

  bool get isOrganizingInbox => _isOrganizingInbox;
  String? get inboxOrganizerStatus => _inboxOrganizerStatus;
  String? get inboxOrganizerModelLabel => _inboxOrganizerModelLabel;
  List<InboxOrganizerLogEntry> get inboxOrganizerLogs =>
      List.unmodifiable(_inboxOrganizerLogs);
  String get inboxOrganizerLiveThoughts =>
      _inboxOrganizerLiveThoughts.toString();
  String get inboxOrganizerLiveContent => _inboxOrganizerLiveContent.toString();
  bool get hasInboxOrganizerLogs =>
      _inboxOrganizerLogs.isNotEmpty ||
      _inboxOrganizerLiveThoughts.isNotEmpty ||
      _inboxOrganizerLiveContent.isNotEmpty;

  String get inboxOrganizerProviderId => _config.inboxOrganizerProviderId;
  String get inboxOrganizerModelId => _config.inboxOrganizerModelId;
  String get inboxOrganizerThinkingEffort =>
      _config.inboxOrganizerThinkingEffort;
  bool get inboxAutoRerunPreview => _config.inboxAutoRerunPreview;
  List<String> get inboxOrganizerExcludedCategories =>
      _config.inboxOrganizerExcludedCategories;
  String get inboxOrganizerPresetId => _config.inboxOrganizerPresetId;
  String get inboxOrganizerCustomInstructions =>
      _config.inboxOrganizerCustomInstructions;

  /// 解析当前后台整理模型的实际生效思考强度：
  /// - 模型不支持思考时返回 null；
  /// - 配置留空时采用该模型的默认思考强度；
  /// - 配置非空时收敛到该模型真实支持的思考档位集合。
  ThinkingEffort? resolveInboxOrganizerThinkingEffort(LlmModelConfig modelCfg) {
    if (!modelCfg.supportsThinking) return null;
    final raw = _config.inboxOrganizerThinkingEffort.trim();
    if (raw.isEmpty) return modelCfg.defaultThinkingEffort;
    return modelCfg.normalizeThinkingEffort(ThinkingEffort.fromId(raw));
  }

  /// 解析当前用于待整理区后台整理的供应商与模型（未指定或失效时跟随主模型）
  ({LlmProviderConfig provider, LlmModelConfig model, bool isFollowingMain})
  resolveInboxOrganizerModel() {
    final providerId = _config.inboxOrganizerProviderId.trim();
    final modelId = _config.inboxOrganizerModelId.trim();
    if (providerId.isNotEmpty && modelId.isNotEmpty) {
      final matchedProvider = _config.llmProviders
          .where((p) => p.id == providerId)
          .firstOrNull;
      final matchedModel = matchedProvider?.models
          .where((m) => m.id == modelId)
          .firstOrNull;
      if (matchedProvider != null && matchedModel != null) {
        return (
          provider: matchedProvider,
          model: matchedModel,
          isFollowingMain: false,
        );
      }
    }
    final activeProvider = _config.activeLlmProvider;
    return (
      provider: activeProvider,
      model: activeProvider.activeModel,
      isFollowingMain: true,
    );
  }

  /// 更新待整理区后台整理设置（独立模型/跟随主模型 + 思考强度 + 自动重跑预览图 + 禁止拆分分类 + 整理预设/自定义指令）
  Future<void> updateInboxOrganizerSettings({
    String? providerId,
    String? modelId,
    String? thinkingEffort,
    bool? autoRerunPreview,
    List<String>? excludedCategories,
    String? presetId,
    String? customInstructions,
  }) async {
    await updateConfig(
      _config.copyWith(
        inboxOrganizerProviderId: providerId,
        inboxOrganizerModelId: modelId,
        inboxOrganizerThinkingEffort: thinkingEffort,
        inboxAutoRerunPreview: autoRerunPreview,
        inboxOrganizerExcludedCategories: excludedCategories,
        inboxOrganizerPresetId: presetId,
        inboxOrganizerCustomInstructions: customInstructions,
      ),
    );
    promptLibraryNotifier.value++;
    inboxOrganizerNotifier.value++;
  }

  void _notifyInboxOrganizerThrottled() {
    if (_disposed) return;
    if (_inboxOrganizerLogFlushTimer != null) return;
    _inboxOrganizerLogFlushTimer = Timer(const Duration(milliseconds: 60), () {
      _inboxOrganizerLogFlushTimer = null;
      if (!_disposed) inboxOrganizerNotifier.value++;
    });
  }

  void _notifyInboxOrganizerNow() {
    _inboxOrganizerLogFlushTimer?.cancel();
    _inboxOrganizerLogFlushTimer = null;
    if (!_disposed) inboxOrganizerNotifier.value++;
  }

  void _appendInboxOrganizerLog(InboxOrganizerLogEntry entry) {
    _inboxOrganizerLogs.add(entry);
    if (_inboxOrganizerLogs.length > 200) {
      _inboxOrganizerLogs.removeRange(0, _inboxOrganizerLogs.length - 200);
    }
    _notifyInboxOrganizerNow();
  }

  void _flushInboxOrganizerLiveBuffers() {
    final thoughts = _inboxOrganizerLiveThoughts.toString().trim();
    if (thoughts.isNotEmpty) {
      _inboxOrganizerLogs.add(
        InboxOrganizerLogEntry(
          timestamp: DateTime.now(),
          kind: InboxOrganizerLogKind.thought,
          text: thoughts,
        ),
      );
      _inboxOrganizerLiveThoughts.clear();
    }
    final content = _inboxOrganizerLiveContent.toString().trim();
    if (content.isNotEmpty) {
      _inboxOrganizerLogs.add(
        InboxOrganizerLogEntry(
          timestamp: DateTime.now(),
          kind: InboxOrganizerLogKind.content,
          text: content,
        ),
      );
      _inboxOrganizerLiveContent.clear();
    }
  }

  /// 清空后台整理日志（运行中不清空）
  void clearInboxOrganizerLogs() {
    if (_isOrganizingInbox) return;
    _inboxOrganizerLogs.clear();
    _inboxOrganizerLiveThoughts.clear();
    _inboxOrganizerLiveContent.clear();
    _inboxOrganizerStatus = null;
    _notifyInboxOrganizerNow();
  }

  /// 中止正在进行的后台待整理区整理任务
  Future<void> abortInboxOrganizer() async {
    if (!_isOrganizingInbox) return;
    _inboxOrganizerAborted = true;
    _inboxOrganizerHarness?.abort();
    _inboxOrganizerStatus = '已请求停止整理…';
    _notifyInboxOrganizerNow();
  }

  /// 为单个词库条目后台生成专属预览图（严格经由底层 AsyncLock 串行、受 Opus 免费保护、不修改工作台也不写入画板历史）
  Future<({bool ok, String message})> _generateIsolatedLibraryPreview({
    required PromptComboEntry entry,
    required String prompt,
    String negativePrompt = '',
    List<PromptInboxCharacter> characterPrompts = const [],
    int width = 832,
    int height = 1216,
  }) async {
    final apiKey = _config.novelAiKey.trim();
    if (apiKey.isEmpty) {
      return (ok: false, message: '未配置 NovelAI API Key，无法自动重跑预览图。');
    }

    final charList = <NaiCharacterPrompt>[
      for (var i = 0; i < characterPrompts.length; i++)
        NaiCharacterPrompt(
          id: 'preview_char_$i',
          name: characterPrompts[i].name.isNotEmpty
              ? characterPrompts[i].name
              : 'Character ${i + 1}',
          prompt: characterPrompts[i].prompt,
          negativePrompt: characterPrompts[i].negativePrompt,
          enabled: true,
        ),
    ];

    final genParams = NaiGenerationParams(
      prompt: prompt,
      negativePrompt: negativePrompt.isNotEmpty
          ? negativePrompt
          : _params.negativePrompt,
      model: _params.model,
      effort: _params.effort,
      width: width,
      height: height,
      steps: _params.steps.clamp(1, 28),
      scale: _params.scale,
      cfgRescale: _params.cfgRescale,
      sampler: _params.sampler,
      noiseSchedule: _params.noiseSchedule,
      seed: -1,
      nSamples: 1,
      qualityToggle: _params.qualityToggle,
      qualityPreset: _params.qualityPreset,
      ucPresetKey: _params.ucPresetKey,
      prefixPrompt: _params.prefixPrompt,
      suffixPrompt: _params.suffixPrompt,
      applyFixedPrompts: _params.applyFixedPrompts,
      characterPrompts: charList,
      characterAiPosition: true,
    );

    final estimatedCost = AnlasCalculator.estimateGenerationCost(
      params: genParams,
      isOpus: _accountInfo?.isOpus ?? false,
      opusQuotaExhausted: _accountInfo?.v5QuotaExhausted ?? false,
    );
    if (estimatedCost != 0 && _config.opusFreeMode) {
      return (
        ok: false,
        message:
            '当前账号无法免点生成该预览图（预计消耗 $estimatedCost Anlas，已开启免点保护），已跳过重跑并保留原预览图。',
      );
    }

    try {
      final rawBytes = await _repository.generatePreviewImageBytes(
        apiKey: apiKey,
        params: genParams,
      );
      if (rawBytes == null || rawBytes.isEmpty) {
        return (ok: false, message: '预览图生成返回空字节。');
      }
      final scaled = await downscalePreviewBytes(rawBytes);
      final savedPath = await savePromptPreviewFromBytes(
        scaled,
        prefix: 'preview',
      );
      if (savedPath == null || savedPath.isEmpty) {
        return (ok: false, message: '预览图落盘失败。');
      }
      final latestEntry = _promptLibraryEntries
          .where((e) => e.id == entry.id)
          .firstOrNull;
      if (latestEntry == null) {
        return (ok: false, message: '条目「${entry.title}」已不存在。');
      }
      await updatePromptCombo(
        latestEntry.copyWith(
          previewImagePath: savedPath,
          updatedAt: DateTime.now(),
        ),
      );
      return (
        ok: true,
        message:
            '已为「${latestEntry.title}」(${latestEntry.id}) 重新生成专属预览图 (${width}x$height)。',
      );
    } catch (e) {
      return (ok: false, message: '重跑预览图失败：$e');
    }
  }

  /// 在独立后台对话中运行词库待整理区整理 Agent（不干扰主聊天会话，实时输出日志）
  Future<void> startBackgroundInboxOrganizer({
    String? inboxItemId,
    LlmProvider? overrideProviderForTest,
    bool? overrideMultimodalForTest,
  }) async {
    if (_isOrganizingInbox) return;
    if (_promptInboxItems.isEmpty) return;

    final resolved = resolveInboxOrganizerModel();
    final providerCfg = resolved.provider;
    final modelCfg = resolved.model;
    final canRun =
        overrideProviderForTest != null ||
        providerCfg.apiKey.trim().isNotEmpty ||
        OpenAiCompatibleProvider.acceptsEmptyApiKey(
          providerCfg.fullEndpointUrl,
        );

    _inboxOrganizerLogs.clear();
    _inboxOrganizerLiveThoughts.clear();
    _inboxOrganizerLiveContent.clear();
    _inboxOrganizerAborted = false;

    final providerDisplayName = providerCfg.name.isNotEmpty
        ? providerCfg.name
        : providerCfg.id;
    _inboxOrganizerModelLabel = '$providerDisplayName / ${modelCfg.name}';

    if (!canRun) {
      _inboxOrganizerStatus = '整理未启动：模型未配置 API Key';
      _appendInboxOrganizerLog(
        InboxOrganizerLogEntry(
          timestamp: DateTime.now(),
          kind: InboxOrganizerLogKind.error,
          title: '配置缺失',
          text: '请先在设置中为「$_inboxOrganizerModelLabel」填写 API Key，或切换为已配置的模型。',
          isError: true,
        ),
      );
      return;
    }

    _isOrganizingInbox = true;
    _inboxOrganizerStatus = inboxItemId != null
        ? '正在后台整理条目 $inboxItemId…'
        : '正在后台整理全部 ${_promptInboxItems.length} 项…';
    promptLibraryNotifier.value++;
    _notifyInboxOrganizerNow();

    final autoRerun = _config.inboxAutoRerunPreview;
    final multimodal = overrideMultimodalForTest ?? modelCfg.isMultimodal;
    final excludedSet = _config.inboxOrganizerExcludedCategories
        .map((c) => c.trim())
        .where((c) => c.isNotEmpty)
        .toSet();
    final allowedCategories = PromptComboCategories.defaults
        .where((c) => !excludedSet.contains(c))
        .toList(growable: false);
    final selectedPresetId = _config.inboxOrganizerPresetId.trim();
    final selectedPreset = selectedPresetId.isEmpty
        ? null
        : _config.presets
              .where((p) => p.id == selectedPresetId)
              .firstOrNull;
    final customInstructions = _config.inboxOrganizerCustomInstructions.trim();
    final resolvedThinkingEffort = resolveInboxOrganizerThinkingEffort(modelCfg);

    _appendInboxOrganizerLog(
      InboxOrganizerLogEntry(
        timestamp: DateTime.now(),
        kind: InboxOrganizerLogKind.system,
        title: '后台整理已启动',
        text:
            '模型: $_inboxOrganizerModelLabel${resolved.isFollowingMain ? ' (跟随主模型)' : ''} · '
            '${resolvedThinkingEffort != null ? '思考: ${resolvedThinkingEffort.id} · ' : ''}'
            '视觉: ${multimodal ? '支持' : '纯文本'} · '
            '自动重跑预览图: ${autoRerun ? '开启' : '关闭'}'
            '${selectedPreset != null ? ' · 预设: ${selectedPreset.name}' : ''}'
            '${customInstructions.isNotEmpty ? ' · 已附自定义指令' : ''}'
            '${excludedSet.isNotEmpty ? ' · 允许分类: ${allowedCategories.join('/')}' : ''}',
      ),
    );

    final organizerTools = ToolRegistry();
    organizerTools.register(
      PromptLibraryTool(
        getEntries: () => promptLibraryEntries,
        addEntry: addPromptCombo,
        updateEntry: updatePromptCombo,
        deleteEntry: deletePromptCombo,
        getInboxItems: () => promptInboxItems,
        deleteInboxItems: deletePromptInboxItems,
        isModelMultimodal: () => multimodal,
        excludedCategories: excludedSet.isEmpty ? null : excludedSet,
        getHistory: () => _repository.history,
        loadImageBytes: ensureImageLoaded,
        savePreviewBytes: savePromptPreviewFromBytes,
        copyPreviewFromPath: savePromptPreviewFromPath,
        snapshotWorkspacePrecise: snapshotWorkspacePreciseReferences,
        snapshotWorkspaceVibe: snapshotWorkspaceVibeReferences,
        applyEntry: applyPromptComboSelective,
      ),
    );
    if (autoRerun) {
      organizerTools.register(
        GenerateLibraryPreviewTool(
          getEntries: () => promptLibraryEntries,
          generatePreview: _generateIsolatedLibraryPreview,
        ),
      );
    }

    final enabledTools = <String>[
      PresetToolKeys.promptLibrary,
      if (autoRerun) 'generate_library_preview',
    ];

    final systemPrompt = StringBuffer()
      ..writeln('你是 NovelAI Harness 的后台词库整理助手，运行在独立后台任务中。')
      ..writeln('你的职责是将「词库待整理区」中用户收集的图片和提示词（含主提示词与多角色提示词）拆解、提炼、去重后归档到正式词库。')
      ..writeln('工作流程与规范：')
      ..writeln('1. 调用 prompt_library(action: "list_inbox") 查看待整理清单，再用 read_inbox 逐条读取完整主提示词、角色提示词和图片。')
      ..writeln('2. 调用 prompt_library(action: "search") 检查正式词库中是否已有同名或同类条目，避免重复建条，已有角色/套装可优先 update 补充。')
      ..writeln(
        excludedSet.isEmpty
            ? '3. 将有复用价值的元素拆分为独立条目（分类：角色 / 风格 / 服装 / 构图 / 环境 / 特效 / 其他），去掉杂乱质量词、无意义临时词，保留精炼有效的 Danbooru 标签；必要时可在同一条目保留主提示词 + character_prompts。'
            : '3. 【严格分类限制】用户仅允许拆分以下分类：${allowedCategories.join(' / ')}；严禁为【${excludedSet.join(' / ')}】创建词条，忽略这些维度的标签不要拆出单独条目！其余维度按需去杂提炼，保留精炼有效的 Danbooru 标签。',
      )
      ..writeln('4. 重要关联规范：关联为单向引用——如果某条「服装」「配饰」或专属构图属于某个角色，请先创建或查找到该角色条目，再仅在该服装/构图条目中通过 linked_entry_titles: ["角色标题"] 或 linked_entry_ids 单向指向对应角色（不要在角色条目上反向堆叠大量服装链接）。')
      ..writeln('5. 新增条目时可传 preview_inbox_id 复用原待整理图作初始预览图。')
      ..writeln(
        autoRerun
            ? '6. 【已开启分离后自动重跑预览图】当同一张原图被拆分成多个不同维度的条目（如角色、服装、构图、环境）时，请为拆出的独立条目依次调用 generate_library_preview 生成各自专属的清晰预览图（服装预览可结合其关联角色穿该服装，构图/环境预览用简洁主体或纯景展示），避免所有条目共用同一张杂乱原图。'
            : '6. 当前未开启自动重跑预览图，直接用 preview_inbox_id 复用原图作为预览图即可。',
      )
      ..writeln('7. 确认入库成功后，调用 prompt_library(action: "delete_inbox") 清理已整理完毕的待整理项，最后用简明中文汇报整理结果（新增/更新了哪些条目、建立了哪些关联、是否重跑了预览图）。');

    if (selectedPreset != null && selectedPreset.systemPrompt.trim().isNotEmpty) {
      systemPrompt
        ..writeln()
        ..writeln('【已选用整理预设：${selectedPreset.name}】')
        ..writeln(selectedPreset.systemPrompt.trim())
        ..writeln('（请在遵循上述预设风格与标签规范的前提下，严格执行词库工具流程与允许拆分分类限制。）');
    }
    if (customInstructions.isNotEmpty) {
      systemPrompt
        ..writeln()
        ..writeln('【用户自定义整理指令（高优先级）】')
        ..writeln(customInstructions);
    }

    final organizerPreset = AgentPreset(
      id: '_inbox_organizer_bg',
      name: '后台词库整理助手',
      description: '独立后台整理词库待整理区',
      systemPrompt: systemPrompt.toString(),
      enabledToolNames: enabledTools,
      allowMcpTools: false,
    );

    final createdProvider = overrideProviderForTest == null
        ? LlmProviderFactory.create(
            baseUrl: providerCfg.fullEndpointUrl,
            apiKey: providerCfg.apiKey,
            model: modelCfg.id,
            reasoning:
                resolvedThinkingEffort != null &&
                resolvedThinkingEffort != ThinkingEffort.none,
            thinkingEffort: resolvedThinkingEffort?.id,
            thinkingParamFormat: providerCfg.thinkingParamFormat.id,
            cacheConfig: modelCfg.cacheConfig,
            promptToolUse: providerCfg.promptToolUse,
            streaming: providerCfg.streaming,
            client: _llmHttpClient,
          )
        : null;

    final harness = AgentHarness(
      tools: organizerTools,
      provider: overrideProviderForTest ?? createdProvider,
      providerLabel: providerDisplayName,
      initialPreset: organizerPreset,
      maxTurns: _config.agentMaxTurns.clamp(12, 60),
    );
    harness.contextWindowTokens = modelCfg.contextWindow;
    harness.compactionEnabled = false;
    _inboxOrganizerHarness = harness;

    final taskPrompt = inboxItemId != null
        ? '请整理词库待整理区中 ID 为 "$inboxItemId" 的条目：调用 read_inbox 读取完整内容与图片，查重并拆解归档到正式词库，建立服装与角色等关联，${autoRerun ? '为拆分出的条目调用 generate_library_preview 重跑各自专属预览图，' : ''}最后删除该待整理项并汇报结果。'
        : '请整理词库待整理区中的全部条目：先调用 list_inbox 获取清单，逐条 read_inbox 查看提示词与图片，查重并拆解归档到正式词库，建立服装与角色等关联，${autoRerun ? '为拆分出的条目调用 generate_library_preview 重跑各自专属预览图，' : ''}最后删除已整理的待整理项并汇总汇报。';

    final completer = Completer<void>();
    var hadError = false;

    try {
      final stream = harness.send(
        taskPrompt,
        temperature: _config.llmTemperature,
      );
      _inboxOrganizerSub = stream.listen(
        (event) {
          switch (event) {
            case ThoughtDeltaEvent(:final delta):
              _inboxOrganizerLiveThoughts.write(delta);
              _notifyInboxOrganizerThrottled();
            case ContentDeltaEvent(:final delta):
              _inboxOrganizerLiveContent.write(delta);
              _notifyInboxOrganizerThrottled();
            case TurnStartEvent():
              _flushInboxOrganizerLiveBuffers();
              _notifyInboxOrganizerNow();
            case ToolCallEvent(:final toolCall):
              _flushInboxOrganizerLiveBuffers();
              var argsPreview = '';
              try {
                argsPreview = jsonEncode(toolCall.arguments);
              } catch (_) {
                argsPreview = toolCall.arguments.toString();
              }
              if (argsPreview.length > 360) {
                argsPreview = '${argsPreview.substring(0, 360)}…';
              }
              _inboxOrganizerStatus = '调用工具: ${toolCall.name}';
              _appendInboxOrganizerLog(
                InboxOrganizerLogEntry(
                  timestamp: DateTime.now(),
                  kind: InboxOrganizerLogKind.toolCall,
                  title: toolCall.name,
                  text: argsPreview,
                ),
              );
            case ToolResultEvent(:final result):
              var text = result.content.trim();
              if (text.length > 600) {
                text = '${text.substring(0, 600)}…';
              }
              if (result.imageBase64 != null && result.imageBase64!.isNotEmpty) {
                text = '$text\n[已附视觉图片]';
              }
              _appendInboxOrganizerLog(
                InboxOrganizerLogEntry(
                  timestamp: DateTime.now(),
                  kind: InboxOrganizerLogKind.toolResult,
                  title: result.isError ? '工具返回错误' : '工具执行完成',
                  text: text,
                  isError: result.isError,
                ),
              );
            case UsageEvent(:final usage):
              _usageLedger.record(
                key: 'inbox_org_${DateTime.now().microsecondsSinceEpoch}',
                provider: providerDisplayName,
                model: modelCfg.id,
                usage: usage,
              );
            case RetryEvent(:final attempt, :final maxAttempts, :final reason):
              _appendInboxOrganizerLog(
                InboxOrganizerLogEntry(
                  timestamp: DateTime.now(),
                  kind: InboxOrganizerLogKind.system,
                  title: '自动重试 ($attempt/$maxAttempts)',
                  text: reason,
                ),
              );
            case ErrorEvent(:final error):
              hadError = true;
              _flushInboxOrganizerLiveBuffers();
              _appendInboxOrganizerLog(
                InboxOrganizerLogEntry(
                  timestamp: DateTime.now(),
                  kind: InboxOrganizerLogKind.error,
                  title: '整理出错',
                  text: error,
                  isError: true,
                ),
              );
            case TurnEndEvent():
            case ThoughtSignatureEvent():
            case ReasoningSnapshotEvent():
            case CompactionEvent():
              break;
          }
        },
        onError: (Object e) {
          hadError = true;
          _flushInboxOrganizerLiveBuffers();
          _appendInboxOrganizerLog(
            InboxOrganizerLogEntry(
              timestamp: DateTime.now(),
              kind: InboxOrganizerLogKind.error,
              title: '运行异常',
              text: '$e',
              isError: true,
            ),
          );
          if (!completer.isCompleted) completer.complete();
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete();
        },
        cancelOnError: true,
      );

      await completer.future;
    } catch (e) {
      hadError = true;
      _flushInboxOrganizerLiveBuffers();
      _appendInboxOrganizerLog(
        InboxOrganizerLogEntry(
          timestamp: DateTime.now(),
          kind: InboxOrganizerLogKind.error,
          title: '启动失败',
          text: '$e',
          isError: true,
        ),
      );
    } finally {
      _flushInboxOrganizerLiveBuffers();
      await _inboxOrganizerSub?.cancel();
      _inboxOrganizerSub = null;
      harness.dispose();
      createdProvider?.close();
      if (identical(_inboxOrganizerHarness, harness)) {
        _inboxOrganizerHarness = null;
      }
      _isOrganizingInbox = false;
      _inboxOrganizerStatus = _inboxOrganizerAborted
          ? '已停止整理'
          : (hadError ? '整理异常结束' : '后台整理已完成');
      _appendInboxOrganizerLog(
        InboxOrganizerLogEntry(
          timestamp: DateTime.now(),
          kind: InboxOrganizerLogKind.system,
          title: _inboxOrganizerStatus,
          text: '剩余待整理 ${_promptInboxItems.length} 项 · 词库共 ${_promptLibraryEntries.length} 条。',
        ),
      );
      if (!_disposed) {
        promptLibraryNotifier.value++;
        _notifyInboxOrganizerNow();
        // 后台整理期间暂缓的自动云同步：全部条目与预览图落地后统一合并上传一次
        if (_pendingAutoPromptSync && _canRunAutoPromptSync) {
          _pendingAutoPromptSync = false;
          _scheduleAutoPromptSync();
        }
      }
    }
  }

  /// 保存本地预览/参考图片并返回路径
  @override
  Future<String?> savePromptPreviewFromBytes(
    Uint8List bytes, {
    String extension = 'png',
    String prefix = 'preview',
  }) async {
    return await _promptLibraryService.savePreviewImageBytes(
      bytes,
      extension: extension,
      prefix: prefix,
    );
  }

  /// 从本地路径复制预览图片并返回持久化路径
  @override
  Future<String?> savePromptPreviewFromPath(String path) async {
    return await _promptLibraryService.copyPreviewImageFromPath(path);
  }

  /// 获取当前画板图片字节用于预览图 (若存在)
  Uint8List? getCurrentCanvasImageBytes() {
    final img = _selectedImage;
    if (img != null) {
      final b = getImageBytes(img);
      if (b != null && b.isNotEmpty) return b;
    }
    return _liveProgressController.previewBytes;
  }

  static String _appendCommaSeparated(String base, String addition) {
    final trimmedAdd = addition.trim();
    if (trimmedAdd.isEmpty) return base;
    final trimmedBase = base.trim();
    if (trimmedBase.isEmpty) return trimmedAdd;
    return trimmedBase.endsWith(',') || trimmedBase.endsWith('，')
        ? '$trimmedBase $trimmedAdd'
        : '$trimmedBase, $trimmedAdd';
  }

  /// 将词组合应用到工作台
  ///
  /// - [replace]: 为 true 时替换目标字段，为 false 时在末尾追加
  /// - [asCharacter]: 为 true 且当分类为角色时，将词组合直接追加为一个新的多角色卡片
  /// - [asStyle]: 为 true 且当分类为风格时，将前置/后置词写入固定词缀并开启固定词缀开关，同时写入负面提示词
  void applyPromptCombo(
    PromptComboEntry combo, {
    bool replace = false,
    bool asCharacter = false,
    bool asStyle = false,
  }) {
    // 1. 若选择作为独立多角色添加 (仅角色分类有效)
    if (asCharacter && combo.isCharacter) {
      final currentList = List<NaiCharacterPrompt>.from(
        _params.characterPrompts,
      );
      currentList.add(
        NaiCharacterPrompt.create(
          name: combo.title.trim().isNotEmpty
              ? combo.title.trim()
              : vmL10n.vmNewCharacterName,
          prompt: combo.prompt.trim(),
          negativePrompt: combo.negativePrompt.trim(),
        ),
      );
      _setCharacterPrompts(currentList);
      notifyListeners();
      return;
    }

    // 2. 若选择作为画风应用到固定词缀与负面词 (仅风格分类有效)
    if (asStyle && combo.isStyle) {
      final incomingPrefix = combo.effectiveStylePrefix;
      final incomingSuffix = combo.suffixPrompt.trim();
      final incomingNegative = combo.negativePrompt.trim();

      var nextPrefix = _params.prefixPrompt ?? '';
      var nextSuffix = _params.suffixPrompt ?? '';
      var nextApplyFixed = _params.applyFixedPrompts;
      var nextNegative = _params.negativePrompt;

      if (incomingPrefix.isNotEmpty || incomingSuffix.isNotEmpty) {
        if (replace) {
          nextPrefix = incomingPrefix;
          nextSuffix = incomingSuffix;
        } else {
          if (incomingPrefix.isNotEmpty) {
            nextPrefix = _appendCommaSeparated(nextPrefix, incomingPrefix);
          }
          if (incomingSuffix.isNotEmpty) {
            nextSuffix = _appendCommaSeparated(nextSuffix, incomingSuffix);
          }
        }
        nextApplyFixed = true;
      }

      if (incomingNegative.isNotEmpty) {
        nextNegative = replace
            ? incomingNegative
            : _appendCommaSeparated(nextNegative, incomingNegative);
      }

      updateParams(
        _params.copyWith(
          prefixPrompt: nextPrefix,
          suffixPrompt: nextSuffix,
          applyFixedPrompts: nextApplyFixed,
          negativePrompt: nextNegative,
        ),
      );
      return;
    }

    var nextPrompt = _params.prompt;
    var nextNegativePrompt = _params.negativePrompt;

    // 3. 正向提示词应用 (风格条目未填写主提示词时合并前后缀)
    final incomingPrompt = combo.prompt.trim().isNotEmpty
        ? combo.prompt.trim()
        : (combo.isStyle
              ? [
                  combo.prefixPrompt.trim(),
                  combo.suffixPrompt.trim(),
                ].where((s) => s.isNotEmpty).join(', ')
              : '');
    if (incomingPrompt.isNotEmpty) {
      nextPrompt = replace
          ? incomingPrompt
          : _appendCommaSeparated(nextPrompt, incomingPrompt);
    }

    // 4. 负面提示词应用 (角色或风格分类且负面词不为空时生效)
    if (combo.supportsNegative && combo.negativePrompt.trim().isNotEmpty) {
      final incomingUc = combo.negativePrompt.trim();
      nextNegativePrompt = replace
          ? incomingUc
          : _appendCommaSeparated(nextNegativePrompt, incomingUc);
    }

    // 5. 多角色提示词应用 (同时带主提示词与角色提示词的条目一并写入角色卡)
    List<NaiCharacterPrompt>? nextCharacters;
    if (combo.characterPrompts.isNotEmpty) {
      final incomingChars = combo.characterPrompts
          .map(
            (c) => NaiCharacterPrompt.create(
              name: c.name.trim().isNotEmpty
                  ? c.name.trim()
                  : vmL10n.vmNewCharacterName,
              prompt: c.prompt.trim(),
              negativePrompt: c.negativePrompt.trim(),
            ),
          )
          .toList(growable: false);
      nextCharacters = replace
          ? incomingChars
          : [..._params.characterPrompts, ...incomingChars];
    }

    updateParams(
      _params.copyWith(
        prompt: nextPrompt,
        negativePrompt: nextNegativePrompt,
        characterPrompts: nextCharacters,
      ),
    );
  }

  /// 将当前工作台挂载的精准参考图落盘为词库托管条目列表
  @override
  Future<List<PromptLibraryPreciseRef>> snapshotWorkspacePreciseReferences() async {
    final result = <PromptLibraryPreciseRef>[];
    var seq = 0;
    for (final ref in _params.preciseReferences) {
      if (ref.imageBytes.isEmpty) continue;
      final savedPath = await _promptLibraryService.savePreviewImageBytes(
        ref.imageBytes,
        extension: _detectRefImageExt(ref.imageBytes, ref.fileName),
        prefix: 'ref',
      );
      if (savedPath == null || savedPath.isEmpty) continue;
      result.add(
        PromptLibraryPreciseRef(
          id: 'lib_pref_${DateTime.now().microsecondsSinceEpoch}_${++seq}',
          imagePath: savedPath,
          fileName: ref.fileName,
          type: ref.type,
          preferSameOutfit: ref.preferSameOutfit,
          strength: ref.strength,
          fidelity: ref.fidelity,
          informationExtracted: ref.informationExtracted,
          enabled: ref.enabled,
        ),
      );
    }
    return result;
  }

  /// 将当前工作台挂载的 Vibe Transfer 落盘为词库托管条目列表（完整保留编码缓存）
  @override
  Future<List<PromptLibraryVibeRef>> snapshotWorkspaceVibeReferences() async {
    final result = <PromptLibraryVibeRef>[];
    var seq = 0;
    for (final vibe in _params.vibeReferences) {
      String? rawPath;
      if (vibe.rawImageBytes != null && vibe.rawImageBytes!.isNotEmpty) {
        rawPath = await _promptLibraryService.savePreviewImageBytes(
          vibe.rawImageBytes!,
          extension: _detectRefImageExt(vibe.rawImageBytes!, vibe.displayName),
          prefix: 'vibe',
        );
      }
      String? thumbPath;
      if (vibe.thumbnailBytes != null &&
          vibe.thumbnailBytes!.isNotEmpty &&
          !identical(vibe.thumbnailBytes, vibe.rawImageBytes)) {
        thumbPath = await _promptLibraryService.savePreviewImageBytes(
          vibe.thumbnailBytes!,
          extension: _detectRefImageExt(vibe.thumbnailBytes!, null),
          prefix: 'vthumb',
        );
      }
      if ((rawPath == null || rawPath.isEmpty) && vibe.encodingsByModel.isEmpty) {
        continue;
      }
      result.add(
        PromptLibraryVibeRef(
          id: 'lib_vibe_${DateTime.now().microsecondsSinceEpoch}_${++seq}',
          displayName: vibe.displayName,
          sourceType: vibe.sourceType,
          rawImagePath: rawPath,
          thumbnailPath: thumbPath,
          encodingsByModel: Map<String, String>.from(vibe.encodingsByModel),
          encodedInfoExtractedByModel: Map<String, double>.from(
            vibe.encodedInfoExtractedByModel,
          ),
          strength: vibe.strength,
          informationExtracted: vibe.informationExtracted,
          enabled: vibe.enabled,
        ),
      );
    }
    return result;
  }

  String _detectRefImageExt(Uint8List bytes, String? fileName) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (fileName != null) {
      final ext = p.extension(fileName).replaceAll('.', '').toLowerCase();
      if (ext == 'jpeg') return 'jpg';
      if (ext == 'png' || ext == 'jpg' || ext == 'webp') return ext;
    }
    return 'png';
  }

  /// 选择性将词库条目的提示词、精准参考图与 Vibe Transfer 应用到工作台
  @override
  Future<({bool appliedPrompt, int appliedPreciseCount, int appliedVibeCount})>
  applyPromptComboSelective(
    PromptComboEntry combo, {
    bool applyPrompt = true,
    bool replacePrompt = false,
    bool asCharacter = false,
    bool asStyle = false,
    bool applyPreciseReferences = false,
    bool applyVibeReferences = false,
    bool replaceReferences = false,
    Set<String>? selectedPreciseRefIds,
    Set<String>? selectedVibeRefIds,
    bool switchToReferenceTab = false,
  }) async {
    var didApplyPrompt = false;
    if (applyPrompt && combo.hasPromptText) {
      applyPromptCombo(
        combo,
        replace: replacePrompt,
        asCharacter: asCharacter,
        asStyle: asStyle,
      );
      didApplyPrompt = true;
    }

    var appliedPreciseCount = 0;
    if (applyPreciseReferences && combo.preciseReferences.isNotEmpty) {
      final mounted = <NaiPreciseReference>[];
      for (final ref in combo.preciseReferences) {
        if (selectedPreciseRefIds != null &&
            !selectedPreciseRefIds.contains(ref.id)) {
          continue;
        }
        final path = ref.imagePath.trim();
        if (path.isEmpty) continue;
        final file = File(path);
        if (!file.existsSync()) continue;
        try {
          final bytes = await file.readAsBytes();
          if (bytes.isEmpty) continue;
          mounted.add(
            NaiPreciseReference(
              id: ref.id,
              imageBytes: bytes,
              fileName: ref.fileName ?? p.basename(path),
              type: ref.type,
              preferSameOutfit: ref.preferSameOutfit,
              strength: ref.strength,
              fidelity: ref.fidelity,
              informationExtracted: ref.informationExtracted,
              enabled: ref.enabled,
            ),
          );
        } catch (_) {}
      }
      if (mounted.isNotEmpty) {
        mountPreciseReferences(
          mounted,
          replace: replaceReferences,
          switchToTab: switchToReferenceTab && !applyVibeReferences,
        );
        appliedPreciseCount = mounted.length;
      }
    }

    var appliedVibeCount = 0;
    if (applyVibeReferences && combo.vibeReferences.isNotEmpty) {
      final mounted = <NaiVibeReference>[];
      for (final vibe in combo.vibeReferences) {
        if (selectedVibeRefIds != null &&
            !selectedVibeRefIds.contains(vibe.id)) {
          continue;
        }
        Uint8List? rawBytes;
        final rawPath = vibe.rawImagePath?.trim();
        if (rawPath != null && rawPath.isNotEmpty) {
          final file = File(rawPath);
          if (file.existsSync()) {
            try {
              final data = await file.readAsBytes();
              if (data.isNotEmpty) rawBytes = data;
            } catch (_) {}
          }
        }
        Uint8List? thumbBytes;
        final thumbPath = vibe.thumbnailPath?.trim();
        if (thumbPath != null && thumbPath.isNotEmpty) {
          final file = File(thumbPath);
          if (file.existsSync()) {
            try {
              final data = await file.readAsBytes();
              if (data.isNotEmpty) thumbBytes = data;
            } catch (_) {}
          }
        }
        if ((rawBytes == null || rawBytes.isEmpty) &&
            vibe.encodingsByModel.isEmpty) {
          continue;
        }
        mounted.add(
          NaiVibeReference(
            id: vibe.id,
            displayName: vibe.displayName,
            sourceType: vibe.sourceType,
            rawImageBytes: rawBytes,
            thumbnailBytes: thumbBytes,
            encodingsByModel: Map<String, String>.from(vibe.encodingsByModel),
            encodedInfoExtractedByModel: Map<String, double>.from(
              vibe.encodedInfoExtractedByModel,
            ),
            strength: vibe.strength,
            informationExtracted: vibe.informationExtracted,
            enabled: vibe.enabled,
          ),
        );
      }
      if (mounted.isNotEmpty) {
        mountVibeReferences(
          mounted,
          replace: replaceReferences,
          switchToTab: switchToReferenceTab && appliedPreciseCount == 0,
        );
        appliedVibeCount = mounted.length;
      }
    }

    return (
      appliedPrompt: didApplyPrompt,
      appliedPreciseCount: appliedPreciseCount,
      appliedVibeCount: appliedVibeCount,
    );
  }

  /// 导出全部词组合为 JSON
  Future<String> exportPromptLibraryJson() async {
    return await _promptLibraryService.exportToJson();
  }

  /// 从 JSON 导入词组合
  Future<int> importPromptLibraryJson(
    String jsonStr, {
    bool replaceAll = false,
  }) async {
    final count = await _promptLibraryService.importFromJson(
      jsonStr,
      replaceAll: replaceAll,
    );
    await _reloadPromptLibrary();
    if (count > 0) {
      _scheduleAutoPromptSync();
    }
    return count;
  }

  /// 保存词库云同步配置
  Future<void> savePromptSyncConfig(PromptLibrarySyncConfig syncConfig) async {
    final nextNs = syncConfig.normalizedNamespace;
    await updateConfig(
      _config.copyWith(
        promptSyncEndpoint: syncConfig.endpoint.trim(),
        promptSyncToken: syncConfig.token.trim(),
        promptSyncNamespace: nextNs,
        promptSyncAutoEnabled: syncConfig.autoSyncEnabled,
        promptSyncAutoIntervalMinutes:
            syncConfig.normalizedAutoSyncIntervalMinutes,
      ),
    );
    promptLibraryNotifier.value++;
  }

  bool get _canRunAutoPromptSync {
    final cfg = promptLibrarySyncConfig;
    return cfg.autoSyncEnabled &&
        cfg.isConfigured &&
        cfg.resolveApiUri('/api/health') != null;
  }

  void _reconfigureAutoPromptSync({bool triggerImmediateIfEnabled = false}) {
    _promptAutoSyncPeriodicTimer?.cancel();
    _promptAutoSyncPeriodicTimer = null;

    if (!_canRunAutoPromptSync) {
      _promptAutoSyncDebounceTimer?.cancel();
      _promptAutoSyncDebounceTimer = null;
      _pendingAutoPromptSync = false;
      return;
    }

    final intervalMin = promptLibrarySyncConfig.normalizedAutoSyncIntervalMinutes;
    if (intervalMin > 0) {
      _promptAutoSyncPeriodicTimer = Timer.periodic(
        Duration(minutes: intervalMin),
        (_) => unawaited(_runAutoPromptSync()),
      );
    }

    if (triggerImmediateIfEnabled) {
      unawaited(_runAutoPromptSync());
    }
  }

  void _scheduleAutoPromptSync() {
    if (_disposed || !_canRunAutoPromptSync) return;
    if (_isOrganizingInbox || _isSyncingPromptLibrary) {
      // 后台整理或已有同步进行中：合并为结束后的一次同步，避免反复触发云同步
      _pendingAutoPromptSync = true;
      return;
    }
    _promptAutoSyncDebounceTimer?.cancel();
    _promptAutoSyncDebounceTimer = Timer(_promptAutoSyncDebounceDelay, () {
      _promptAutoSyncDebounceTimer = null;
      unawaited(_runAutoPromptSync());
    });
  }

  Future<void> _runAutoPromptSync() async {
    if (_disposed || !_canRunAutoPromptSync) return;
    if (_isOrganizingInbox || _isSyncingPromptLibrary) {
      _pendingAutoPromptSync = true;
      return;
    }
    try {
      await syncPromptLibrary(mode: PromptLibrarySyncMode.merge);
    } catch (_) {
      // 后台自动同步失败静默记录到 lastPromptSyncError，不弹阻塞提示打断创作
    }
  }

  /// 测试 Cloudflare 词库云同步连接
  Future<PromptLibrarySyncHealth> testPromptLibrarySyncConnection([
    PromptLibrarySyncConfig? overrideConfig,
  ]) {
    return _promptLibrarySyncService.testConnection(
      overrideConfig ?? promptLibrarySyncConfig,
    );
  }

  /// 执行词库云同步 (支持双向增量合并 / 强制上传覆盖 / 强制拉取覆盖)
  Future<PromptLibrarySyncResult> syncPromptLibrary({
    PromptLibrarySyncMode mode = PromptLibrarySyncMode.merge,
    PromptLibrarySyncConfig? overrideConfig,
  }) async {
    final targetConfig = overrideConfig ?? promptLibrarySyncConfig;
    _promptAutoSyncDebounceTimer?.cancel();
    _promptAutoSyncDebounceTimer = null;
    _isSyncingPromptLibrary = true;
    _promptSyncStage = null;
    promptLibraryNotifier.value++;
    notifyListeners();

    try {
      final result = await _promptLibrarySyncService.sync(
        targetConfig,
        mode: mode,
        onStatus: (stage) {
          if (_disposed) return;
          _promptSyncStage = stage;
          promptLibraryNotifier.value++;
        },
      );
      _lastPromptSyncAt = result.syncedAt;
      _lastPromptSyncResult = result;
      _lastPromptSyncError = null;
      await _reloadPromptLibrary();
      return result;
    } catch (e) {
      _lastPromptSyncError = e.toString();
      rethrow;
    } finally {
      if (!_disposed) {
        _isSyncingPromptLibrary = false;
        _promptSyncStage = null;
        promptLibraryNotifier.value++;
        notifyListeners();
        if (_pendingAutoPromptSync) {
          _pendingAutoPromptSync = false;
          _scheduleAutoPromptSync();
        }
      }
    }
  }
}
