part of 'studio_view_model.dart';

/// 多角色提示词编辑与画板定位
mixin _StudioCharactersMixin on _StudioCore {
  /// 整体替换角色提示词列表 (Agent 工具与 UI 卡片共用入口)
  @override
  void _setCharacterPrompts(List<NaiCharacterPrompt> characters) {
    updateParams(_params.copyWith(characterPrompts: characters));
  }

  /// 当前模型的角色提示词数量上限 (V5=22，V4/V4.5=6，v3=0 不支持)
  int get characterPromptLimit => _params.model.maxCharacterPrompts;

  /// 当前角色提示词是否已达当前模型上限
  bool get isCharacterPromptFull =>
      _params.model.maxCharacterPrompts == 0 ||
      _params.characterPrompts.length >= _params.model.maxCharacterPrompts;

  /// 是否正在画板上交互式编辑角色位置
  bool get isEditingCharacterPositions => _isEditingCharacterPositions;

  /// 当前选中的角色 ID (用于高亮锚点及左侧卡片)
  String? get selectedCharacterId => _selectedCharacterId;

  /// 开启或关闭角色位置画板编辑模式
  void setEditingCharacterPositions(bool editing) {
    if (_isEditingCharacterPositions == editing) return;
    _isEditingCharacterPositions = editing;
    if (editing) {
      if (_params.characterAiPosition) {
        _params = _params.copyWith(characterAiPosition: false);
        _configService.saveCharacterAiPosition(false);
      }
      if ((_selectedCharacterId == null ||
              !_params.characterPrompts.any(
                (c) => c.id == _selectedCharacterId,
              )) &&
          _params.characterPrompts.isNotEmpty) {
        _selectedCharacterId = _params.characterPrompts.first.id;
      }
    }
    notifyListeners();
  }

  /// 选中指定角色
  void selectCharacterId(String? id) {
    if (_selectedCharacterId == id) return;
    _selectedCharacterId = id;
    notifyListeners();
  }

  /// 循环切换选中角色 (用于画板滚轮与键盘左右键快捷切换，delta: -1 向前，+1 向后)
  void cycleSelectedCharacter(int delta) {
    final characters = _params.characterPrompts;
    if (characters.length <= 1) return;

    final currentIndex = characters.indexWhere(
      (c) => c.id == _selectedCharacterId,
    );
    final baseIndex = currentIndex >= 0 ? currentIndex : 0;

    // Dart 的 % 对正除数恒返回非负结果，天然支持负向回绕
    final targetIndex = (baseIndex + delta) % characters.length;

    selectCharacterId(characters[targetIndex].id);
  }

  /// 更新指定角色的坐标 (自动切换到自定义定位，并按模型能力支持自由坐标或 5x5 网格量化)
  void updateCharacterCoordinates(String id, double x, double y) {
    final model = _params.model;
    final finalX = model.supportsFreeCharacterPositioning
        ? x.clamp(0.0, 1.0)
        : NaiCharacterPositionLayout.gridQuantize(x);
    final finalY = model.supportsFreeCharacterPositioning
        ? y.clamp(0.0, 1.0)
        : NaiCharacterPositionLayout.gridQuantize(y);

    final updated = [
      for (final c in _params.characterPrompts)
        if (c.id == id)
          c.copyWith(
            useCustomPosition: true,
            positionX: finalX,
            positionY: finalY,
          )
        else
          c,
    ];

    updateParams(
      _params.copyWith(characterPrompts: updated, characterAiPosition: false),
    );
  }

  /// 切换全局角色位置模式 (AI 自动布局 / 自定义定位)
  void setCharacterAiPosition(bool aiPosition) {
    if (aiPosition && _isEditingCharacterPositions) {
      _isEditingCharacterPositions = false;
    }
    updateParams(_params.copyWith(characterAiPosition: aiPosition));
  }

  /// 添加一个角色提示词 (UI 入口，自动命名)
  ///
  /// [gender] 官方三预设之一 (女/男/其他)：传入后按当前模型填充初始正向
  /// 提示词与默认负面 lowres, aliasing, ；留空则保持空白角色，
  /// 与旧版无性别按钮行为一致。
  void addCharacterPrompt({
    String? name,
    NaiCharacterGender? gender,
    String? prompt,
    String? negativePrompt,
  }) {
    if (isCharacterPromptFull) return;
    final initialPrompt =
        prompt ??
        (gender == null ? '' : _params.model.initialCharacterPrompt(gender));
    final initialNegative =
        negativePrompt ??
        (gender == null ? '' : NaiCharacterPrompt.presetNegativePrompt);
    final character = NaiCharacterPrompt.create(
      name: name ?? '角色 ${_params.characterPrompts.length + 1}',
      prompt: initialPrompt,
      negativePrompt: initialNegative,
    );
    _selectedCharacterId = character.id;
    _setCharacterPrompts([..._params.characterPrompts, character]);
  }

  /// 更新单个角色提示词 (按 ID 替换)
  void updateCharacterPrompt(NaiCharacterPrompt updated) {
    _setCharacterPrompts([
      for (final c in _params.characterPrompts)
        if (c.id == updated.id) updated else c,
    ]);
  }

  /// 删除单个角色提示词 (按 ID)
  void removeCharacterPrompt(String id) {
    final remaining = _params.characterPrompts
        .where((c) => c.id != id)
        .toList();
    if (_selectedCharacterId == id) {
      _selectedCharacterId = remaining.isNotEmpty ? remaining.first.id : null;
    }
    _setCharacterPrompts(remaining);
  }
}
