part of 'studio_view_model.dart';

/// 斜杠指令分发 (/help /params /preset /skill /clear /account /tag /upscale /nai)
mixin _StudioSlashMixin on _StudioCore {
  @override
  Future<void> _handleSlashCommand(String command) async {
    final parts = command.split(' ');
    final cmd = parts[0].toLowerCase();
    final args = parts.skip(1).join(' ').trim();

    switch (cmd) {
      case '/help':
        _harness.addInfoMessage(buildSlashHelpText());
        notifyListeners();
        break;

      case '/params':
        _harness.addInfoMessage(
          buildStudioParamsReport(_params, title: '工作台当前生图参数：'),
        );
        notifyListeners();
        break;

      case '/preset':
        if (args.isEmpty) {
          final listStr = presets
              .map((p) => '• ${p.name} (${p.id})')
              .join('\n');
          _harness.addInfoMessage('可用预设列表：\n$listStr\n用法: /preset <预设名称或ID>');
        } else {
          final query = args.toLowerCase();
          final matches = presets
              .where(
                (p) =>
                    p.id.toLowerCase() == query ||
                    p.name.toLowerCase().contains(query),
              )
              .toList();
          if (matches.isEmpty) {
            _harness.addInfoMessage('未找到预设 "$args"，输入 /preset 查看可用预设。');
          } else {
            selectPreset(matches.first);
          }
        }
        notifyListeners();
        break;

      case '/skill':
        if (args.isEmpty) {
          final listStr = availableSkills
              .map((s) => '• ${s.id}: ${s.name}')
              .join('\n');
          _harness.addInfoMessage('可用技能列表：\n$listStr\n用法: /skill <技能名称或ID>');
        } else {
          final skill = _skillRegistry.get(args);
          if (skill != null) {
            _harness.addInfoMessage(
              '【Skill 已载入】${skill.name}\n${skill.description}\n\n${skill.systemPrompt}',
            );
          } else {
            _harness.addInfoMessage('未找到技能 "$args"，输入 /skill 查看可用技能。');
          }
        }
        notifyListeners();
        break;

      case '/clear':
        _harness.clearMessages();
        _sessionModelUsage = {};
        _paramJournal.reset(_params);
        await refreshSessions();
        notifyListeners();
        break;

      case '/account':
        await refreshAccountInfo();
        if (_accountInfo != null) {
          final info = _accountInfo!;
          final quotaLine = info.v5QuotaExhausted
              ? '\n• V5 体力配额已透支，生图将按正常价消耗 Anlas'
              : '';
          _harness.addInfoMessage(
            '''NovelAI 账号状态：
• 订阅等级: ${info.tierName}
• V5 专属体力池: ${info.staminaPercent.toStringAsFixed(1)}%
• 可用 Anlas: ${info.totalAnlas} (赠送: ${info.fixedAnlas}, 购买: ${info.purchasedAnlas})$quotaLine''',
          );
        } else {
          _harness.addInfoMessage('查询账号信息失败，请检查 API Key 设置。');
        }
        notifyListeners();
        break;

      case '/tag':
        if (args.isEmpty) {
          _harness.addInfoMessage('用法: /tag <关键词> (例如: /tag silver)');
          notifyListeners();
          return;
        }
        final tags = await _repository.suggestTags(
          apiKey: _config.novelAiKey,
          query: args,
        );
        if (tags.isEmpty) {
          _harness.addInfoMessage('未找到与 "$args" 相关的标签。');
        } else {
          final listStr = tags
              .take(8)
              .map((t) => '• ${t.tag} (${t.count})')
              .join('\n');
          _harness.addInfoMessage('标签联想建议 ("$args"):\n$listStr');
        }
        notifyListeners();
        break;

      case '/upscale':
        final scale = int.tryParse(args) ?? 4;
        await upscaleSelected(scale: scale);
        _harness.addInfoMessage('已执行 ${scale}x 放大');
        notifyListeners();
        break;

      case '/nai':
        if (args.isEmpty) {
          _harness.addInfoMessage('用法: /nai <提示词>');
          notifyListeners();
          return;
        }

        final parsed = parseSlashResolutionFlags(
          args,
          fallbackWidth: _params.width,
          fallbackHeight: _params.height,
        );
        // 走统一入口 updateParams：提示词随方向标志一并持久化
        updateParams(
          _params.copyWith(
            prompt: parsed.prompt,
            width: parsed.width,
            height: parsed.height,
          ),
        );
        await generateImage();
        // 生图失败时不误报完成 (此时 _selectedImage 仍是旧图)
        if (_errorMessage == null && _selectedImage != null) {
          _harness.addInfoMessage(
            '插画已生成: ${_selectedImage!.localFilePath ?? '完成'}\n尺寸: ${parsed.width}x${parsed.height}, 种子: ${_selectedImage!.seed}',
          );
        }
        notifyListeners();
        break;

      default:
        _harness.addInfoMessage('未知指令 "$cmd"，输入 /help 查看可用指令。');
        notifyListeners();
    }
  }
}
