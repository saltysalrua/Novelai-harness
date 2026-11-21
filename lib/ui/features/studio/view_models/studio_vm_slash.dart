part of 'studio_view_model.dart';

/// 斜杠指令分发 (/help /params /preset /skill /clear /account /tag /upscale /nai)
mixin _StudioSlashMixin on _StudioCore {
  void _notifyFromSlash() => notifyListeners();

  @override
  Future<void> _handleSlashCommand(String command) =>
      SlashCommandDispatcher.dispatch(command, _StudioSlashHost(this));
}

class _StudioSlashHost implements SlashCommandHost {
  _StudioSlashHost(this._vm);

  final _StudioSlashMixin _vm;

  @override
  AppLocalizations get l10n => _vm.vmL10n;

  @override
  NaiGenerationParams get params => _vm._params;

  @override
  bool get isComfyUiMode => _vm.isComfyUiMode;

  @override
  List<AgentPreset> get presets => _vm.presets;

  @override
  List<Skill> get availableSkills => _vm.availableSkills;

  @override
  Skill? findSkill(String id) => _vm._skillRegistry.get(id);

  @override
  bool get hasProvider => _vm._harness.provider != null;

  @override
  bool get hasMessages => _vm._harness.messages.isNotEmpty;

  @override
  List<AgentMessage> get messages => _vm._harness.messages;

  @override
  String? get currentSessionId => _vm.currentSessionId;

  @override
  List<SessionInfo> get sessions => _vm.sessions;

  @override
  NaiAccountInfo? get accountInfo => _vm._accountInfo;

  @override
  String get novelAiKey => _vm._config.novelAiKey;

  @override
  String? get errorMessage => _vm._errorMessage;

  @override
  NaiGeneratedImage? get selectedImage => _vm._selectedImage;

  @override
  void addInfoMessage(String text) => _vm._harness.addInfoMessage(text);

  @override
  void setStatusMessage(String? message) => _vm._statusMessage = message;

  @override
  void notifyView() => _vm._notifyFromSlash();

  @override
  void selectPreset(AgentPreset preset) => _vm.selectPreset(preset);

  @override
  Future<CompactionEvent?> compactContext({bool force = false}) =>
      _vm._harness.compactContext(force: force);

  @override
  Future<void> createNewSession({String? title}) =>
      _vm.createNewSession(title: title);

  @override
  Future<void> rewindToMessage(String messageId) =>
      _vm.rewindToMessage(messageId);

  @override
  Future<void> renameSession(String sessionId, String newTitle) =>
      _vm.renameSession(sessionId, newTitle);

  @override
  Future<void> refreshSessions() => _vm.refreshSessions();

  @override
  void clearChatState() {
    _vm._harness.clearMessages();
    _vm._sessionModelUsage = {};
    _vm._paramJournal.reset(_vm._params);
  }

  @override
  Future<void> refreshAccountInfo() => _vm.refreshAccountInfo();

  @override
  Future<List<NaiTagSuggestion>> suggestTags({
    required String apiKey,
    required String query,
  }) => _vm._repository.suggestTags(apiKey: apiKey, query: query);

  @override
  Future<void> upscaleSelected() => _vm.upscaleSelected();

  @override
  void updateParams(NaiGenerationParams newParams) =>
      _vm.updateParams(newParams);

  @override
  Future<void> generateImage() => _vm.generateImage();
}
