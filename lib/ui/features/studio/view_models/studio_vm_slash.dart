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
        _harness.addInfoMessage(buildSlashHelpText(vmL10n));
        notifyListeners();
        break;

      case '/params':
        _harness.addInfoMessage(
          buildStudioParamsReport(_params, title: vmL10n.vmSlashParamsTitle),
        );
        notifyListeners();
        break;

      case '/preset':
        if (args.isEmpty) {
          final listStr = presets
              .map((p) => '• ${p.name} (${p.id})')
              .join('\n');
          _harness.addInfoMessage(
            '${vmL10n.slashPresetListIntro}\n$listStr\n${vmL10n.slashPresetUsage}',
          );
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
            _harness.addInfoMessage(vmL10n.slashPresetNotFound(args));
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
          _harness.addInfoMessage(
            '${vmL10n.slashSkillListIntro}\n$listStr\n${vmL10n.slashSkillUsage}',
          );
        } else {
          final skill = _skillRegistry.get(args);
          if (skill != null) {
            _harness.addInfoMessage(
              vmL10n.slashSkillLoaded(
                skill.name,
                skill.description,
                skill.systemPrompt,
              ),
            );
          } else {
            _harness.addInfoMessage(vmL10n.slashSkillNotFound(args));
          }
        }
        notifyListeners();
        break;

      case '/compact':
        {
          if (_harness.provider == null) {
            _harness.addInfoMessage(vmL10n.slashCompactNoProvider);
            notifyListeners();
            break;
          }
          if (_harness.messages.isEmpty) {
            _harness.addInfoMessage(vmL10n.slashCompactEmpty);
            notifyListeners();
            break;
          }
          _statusMessage = vmL10n.slashCompactRunning;
          notifyListeners();
          final evt = await _harness.compactContext(force: true);
          if (evt == null) {
            _statusMessage = null;
            _harness.addInfoMessage(vmL10n.slashCompactNothing);
          } else {
            _statusMessage = null;
            _harness.addInfoMessage(
              vmL10n.slashCompactDone(
                evt.tokensBefore,
                evt.tokensAfter,
                evt.summary,
              ),
            );
          }
          notifyListeners();
        }

      case '/new':
        {
          await createNewSession(title: args.isEmpty ? null : args);
          _harness.addInfoMessage(
            args.isEmpty
                ? vmL10n.slashNewNoTitle
                : vmL10n.slashNewWithTitle(args),
          );
          notifyListeners();
        }

      case '/undo':
        {
          // 撤销上一轮对话：回退到最后一条真实用户消息的前一条，
          // 回复、工具结果与同期参数修改随回溯一并回滚 (轮数上限收尾提示不算)
          final msgs = _harness.messages;
          var lastUserIdx = -1;
          for (var i = msgs.length - 1; i >= 0; i--) {
            final m = msgs[i];
            if (m.role == AgentRole.user && !m.id.startsWith('limit_')) {
              lastUserIdx = i;
              break;
            }
          }
          if (lastUserIdx <= 0) {
            _harness.addInfoMessage(vmL10n.slashUndoNothing);
            notifyListeners();
            break;
          }
          final target = msgs[lastUserIdx - 1];
          await rewindToMessage(target.id);
        }

      case '/rename':
        {
          if (args.isEmpty) {
            _harness.addInfoMessage(vmL10n.slashRenameUsage);
            notifyListeners();
            break;
          }
          final sid = currentSessionId;
          if (sid == null) {
            _harness.addInfoMessage(vmL10n.slashRenameNoSession);
          } else {
            await renameSession(sid, args);
            _harness.addInfoMessage(vmL10n.slashRenamed(args));
          }
          notifyListeners();
        }

      case '/sessions':
        {
          await refreshSessions();
          final list = sessions;
          if (list.isEmpty) {
            _harness.addInfoMessage(vmL10n.slashSessionsEmpty);
          } else {
            final buffer = StringBuffer(
              vmL10n.slashSessionsHeader(list.length),
            );
            final shown = list.take(12).toList();
            for (var i = 0; i < shown.length; i++) {
              final s = shown[i];
              final marker = s.isActive ? vmL10n.slashSessionCurrentMarker : '';
              final time = s.lastModified
                  .toIso8601String()
                  .replaceAll('T', ' ')
                  .split('.')
                  .first;
              buffer.writeln(
                '\n${i + 1}. ${s.title}$marker (${vmL10n.slashSessionMsgCount(s.messageCount)}, $time)',
              );
            }
            if (list.length > shown.length) {
              buffer.writeln(
                '\n${vmL10n.slashSessionsMore(list.length - shown.length)}',
              );
            }
            _harness.addInfoMessage(buffer.toString().trim());
          }
          notifyListeners();
        }

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
              ? '\n${vmL10n.slashAccountQuotaExhausted}'
              : '';
          _harness.addInfoMessage(
            '${vmL10n.slashAccountTitle}\n'
            '${vmL10n.slashAccountTier(info.tierName)}\n'
            '${vmL10n.slashAccountStamina(info.staminaPercent.toStringAsFixed(1))}\n'
            '${vmL10n.slashAccountAnlas(info.totalAnlas, info.fixedAnlas, info.purchasedAnlas)}'
            '$quotaLine',
          );
        } else {
          _harness.addInfoMessage(vmL10n.slashAccountFailed);
        }
        notifyListeners();
        break;

      case '/tag':
        if (args.isEmpty) {
          _harness.addInfoMessage(vmL10n.slashTagUsage);
          notifyListeners();
          return;
        }
        final tags = await _repository.suggestTags(
          apiKey: _config.novelAiKey,
          query: args,
        );
        if (tags.isEmpty) {
          _harness.addInfoMessage(vmL10n.slashTagNotFound(args));
        } else {
          final listStr = tags
              .take(8)
              .map((t) => '• ${t.tag} (${t.count})')
              .join('\n');
          _harness.addInfoMessage(vmL10n.slashTagSuggestions(args, listStr));
        }
        notifyListeners();
        break;

      case '/upscale':
        await upscaleSelected();
        _harness.addInfoMessage(vmL10n.slashUpscaleDone);
        notifyListeners();
        break;

      case '/nai':
        if (args.isEmpty) {
          _harness.addInfoMessage(vmL10n.slashNaiUsage);
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
            vmL10n.slashNaiDone(
              _selectedImage!.localFilePath ?? vmL10n.slashNaiDoneFallback,
              parsed.width,
              parsed.height,
              _selectedImage!.seed,
            ),
          );
        }
        notifyListeners();
        break;

      default:
        _harness.addInfoMessage(vmL10n.slashUnknown(cmd));
        notifyListeners();
    }
  }
}
