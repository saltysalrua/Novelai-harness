import '../../../../core/harness/presets/agent_preset.dart';
import '../../../../core/harness/skills/skills.dart';
import '../../../../core/harness/tools/studio_params_tool.dart'
    show buildStudioParamsReport, resolveStudioEffectivePrompts;
import '../../../../core/harness/types.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/session_log_service.dart';
import '../../../../l10n/app_localizations.dart' show AppLocalizations;
import 'slash_command_catalog.dart';

/// 斜杠指令分发器宿主契约，解耦指令解析执行与 StudioViewModel 全貌。
abstract interface class SlashCommandHost {
  AppLocalizations get l10n;
  NaiGenerationParams get params;
  bool get isComfyUiMode;
  List<AgentPreset> get presets;
  List<Skill> get availableSkills;
  Skill? findSkill(String id);
  bool get hasProvider;
  bool get hasMessages;
  List<AgentMessage> get messages;
  String? get currentSessionId;
  List<SessionInfo> get sessions;
  NaiAccountInfo? get accountInfo;
  String get novelAiKey;
  String? get errorMessage;
  NaiGeneratedImage? get selectedImage;

  void addInfoMessage(String text);
  void setStatusMessage(String? message);
  void notifyView();
  void selectPreset(AgentPreset preset);
  Future<CompactionEvent?> compactContext({bool force = false});
  Future<void> createNewSession({String? title});
  Future<void> rewindToMessage(String messageId);
  Future<void> renameSession(String sessionId, String newTitle);
  Future<void> refreshSessions();
  void clearChatState();
  Future<void> refreshAccountInfo();
  Future<List<NaiTagSuggestion>> suggestTags({
    required String apiKey,
    required String query,
  });
  Future<void> upscaleSelected();
  void updateParams(NaiGenerationParams newParams);
  Future<void> generateImage();
}

/// Studio 斜杠指令无状态分发器：统一处理内置 `/help`..`/nai` 命令。
final class SlashCommandDispatcher {
  SlashCommandDispatcher._();

  /// 解析并执行一条以 `/` 开头的指令，结果通过 [host] 回写对话流与状态。
  static Future<void> dispatch(String command, SlashCommandHost host) async {
    final parts = command.split(' ');
    final cmd = parts[0].toLowerCase();
    final args = parts.skip(1).join(' ').trim();
    final l10n = host.l10n;

    switch (cmd) {
      case '/help':
        host.addInfoMessage(buildSlashHelpText(l10n));
        host.notifyView();

      case '/params':
        host.addInfoMessage(
          buildStudioParamsReport(
            host.params,
            title: l10n.vmSlashParamsTitle,
            effectivePrompts: resolveStudioEffectivePrompts(
              host.params,
              isComfyUi: host.isComfyUiMode,
            ),
          ),
        );
        host.notifyView();

      case '/preset':
        _handlePreset(args, host, l10n);
        host.notifyView();

      case '/skill':
        _handleSkill(args, host, l10n);
        host.notifyView();

      case '/compact':
        await _handleCompact(host, l10n);

      case '/new':
        await host.createNewSession(title: args.isEmpty ? null : args);
        host.addInfoMessage(
          args.isEmpty ? l10n.slashNewNoTitle : l10n.slashNewWithTitle(args),
        );
        host.notifyView();

      case '/undo':
        await _handleUndo(host, l10n);

      case '/rename':
        await _handleRename(args, host, l10n);

      case '/sessions':
        await _handleSessions(host, l10n);

      case '/clear':
        host.clearChatState();
        await host.refreshSessions();
        host.notifyView();

      case '/account':
        await _handleAccount(host, l10n);

      case '/tag':
        await _handleTag(args, host, l10n);

      case '/upscale':
        await host.upscaleSelected();
        host.addInfoMessage(l10n.slashUpscaleDone);
        host.notifyView();

      case '/nai':
        await _handleNai(args, host, l10n);

      default:
        host.addInfoMessage(l10n.slashUnknown(cmd));
        host.notifyView();
    }
  }

  static void _handlePreset(
    String args,
    SlashCommandHost host,
    AppLocalizations l10n,
  ) {
    if (args.isEmpty) {
      final listStr = host.presets
          .map((p) => '• ${p.name} (${p.id})')
          .join('\n');
      host.addInfoMessage(
        '${l10n.slashPresetListIntro}\n$listStr\n${l10n.slashPresetUsage}',
      );
      return;
    }
    final query = args.toLowerCase();
    final matches = host.presets
        .where(
          (p) =>
              p.id.toLowerCase() == query ||
              p.name.toLowerCase().contains(query),
        )
        .toList();
    if (matches.isEmpty) {
      host.addInfoMessage(l10n.slashPresetNotFound(args));
    } else {
      host.selectPreset(matches.first);
    }
  }

  static void _handleSkill(
    String args,
    SlashCommandHost host,
    AppLocalizations l10n,
  ) {
    if (args.isEmpty) {
      final listStr = host.availableSkills
          .map((s) => '• ${s.id}: ${s.name}')
          .join('\n');
      host.addInfoMessage(
        '${l10n.slashSkillListIntro}\n$listStr\n${l10n.slashSkillUsage}',
      );
      return;
    }
    final skill = host.findSkill(args);
    if (skill != null) {
      host.addInfoMessage(
        l10n.slashSkillLoaded(skill.name, skill.description, skill.systemPrompt),
      );
    } else {
      host.addInfoMessage(l10n.slashSkillNotFound(args));
    }
  }

  static Future<void> _handleCompact(
    SlashCommandHost host,
    AppLocalizations l10n,
  ) async {
    if (!host.hasProvider) {
      host.addInfoMessage(l10n.slashCompactNoProvider);
      host.notifyView();
      return;
    }
    if (!host.hasMessages) {
      host.addInfoMessage(l10n.slashCompactEmpty);
      host.notifyView();
      return;
    }
    host.setStatusMessage(l10n.slashCompactRunning);
    host.notifyView();
    final evt = await host.compactContext(force: true);
    host.setStatusMessage(null);
    if (evt == null) {
      host.addInfoMessage(l10n.slashCompactNothing);
    } else {
      host.addInfoMessage(
        l10n.slashCompactDone(evt.tokensBefore, evt.tokensAfter, evt.summary),
      );
    }
    host.notifyView();
  }

  static Future<void> _handleUndo(
    SlashCommandHost host,
    AppLocalizations l10n,
  ) async {
    // 撤回最后一条真实用户消息到输入框，不自动发送。
    // 该条之后的回复、工具结果与同期参数修改一并回滚。
    final msgs = host.messages;
    var lastUserIdx = -1;
    for (var i = msgs.length - 1; i >= 0; i--) {
      final m = msgs[i];
      if (m.role == AgentRole.user && !m.id.startsWith('limit_')) {
        lastUserIdx = i;
        break;
      }
    }
    if (lastUserIdx < 0) {
      host.addInfoMessage(l10n.slashUndoNothing);
      host.notifyView();
      return;
    }
    await host.rewindToMessage(msgs[lastUserIdx].id);
  }

  static Future<void> _handleRename(
    String args,
    SlashCommandHost host,
    AppLocalizations l10n,
  ) async {
    if (args.isEmpty) {
      host.addInfoMessage(l10n.slashRenameUsage);
      host.notifyView();
      return;
    }
    final sid = host.currentSessionId;
    if (sid == null) {
      host.addInfoMessage(l10n.slashRenameNoSession);
    } else {
      await host.renameSession(sid, args);
      host.addInfoMessage(l10n.slashRenamed(args));
    }
    host.notifyView();
  }

  static Future<void> _handleSessions(
    SlashCommandHost host,
    AppLocalizations l10n,
  ) async {
    await host.refreshSessions();
    final list = host.sessions;
    if (list.isEmpty) {
      host.addInfoMessage(l10n.slashSessionsEmpty);
    } else {
      final buffer = StringBuffer(l10n.slashSessionsHeader(list.length));
      final shown = list.take(12).toList();
      for (var i = 0; i < shown.length; i++) {
        final s = shown[i];
        final marker = s.isActive ? l10n.slashSessionCurrentMarker : '';
        final time = s.lastModified
            .toIso8601String()
            .replaceAll('T', ' ')
            .split('.')
            .first;
        buffer.writeln(
          '\n${i + 1}. ${s.title}$marker (${l10n.slashSessionMsgCount(s.messageCount)}, $time)',
        );
      }
      if (list.length > shown.length) {
        buffer.writeln('\n${l10n.slashSessionsMore(list.length - shown.length)}');
      }
      host.addInfoMessage(buffer.toString().trim());
    }
    host.notifyView();
  }

  static Future<void> _handleAccount(
    SlashCommandHost host,
    AppLocalizations l10n,
  ) async {
    await host.refreshAccountInfo();
    final info = host.accountInfo;
    if (info != null) {
      final quotaLine = info.v5QuotaExhausted
          ? '\n${l10n.slashAccountQuotaExhausted}'
          : '';
      host.addInfoMessage(
        '${l10n.slashAccountTitle}\n'
        '${l10n.slashAccountTier(info.tierName)}\n'
        '${l10n.slashAccountStamina(info.staminaPercent.toStringAsFixed(1))}\n'
        '${l10n.slashAccountAnlas(info.totalAnlas, info.fixedAnlas, info.purchasedAnlas)}'
        '$quotaLine',
      );
    } else {
      host.addInfoMessage(l10n.slashAccountFailed);
    }
    host.notifyView();
  }

  static Future<void> _handleTag(
    String args,
    SlashCommandHost host,
    AppLocalizations l10n,
  ) async {
    if (args.isEmpty) {
      host.addInfoMessage(l10n.slashTagUsage);
      host.notifyView();
      return;
    }
    final tags = await host.suggestTags(
      apiKey: host.novelAiKey,
      query: args,
    );
    if (tags.isEmpty) {
      host.addInfoMessage(l10n.slashTagNotFound(args));
    } else {
      final listStr = tags
          .take(8)
          .map((t) => '• ${t.tag} (${t.count})')
          .join('\n');
      host.addInfoMessage(l10n.slashTagSuggestions(args, listStr));
    }
    host.notifyView();
  }

  static Future<void> _handleNai(
    String args,
    SlashCommandHost host,
    AppLocalizations l10n,
  ) async {
    if (args.isEmpty) {
      host.addInfoMessage(l10n.slashNaiUsage);
      host.notifyView();
      return;
    }

    final parsed = parseSlashResolutionFlags(
      args,
      fallbackWidth: host.params.width,
      fallbackHeight: host.params.height,
    );
    // 走统一入口 updateParams：提示词随方向标志一并持久化
    host.updateParams(
      host.params.copyWith(
        prompt: parsed.prompt,
        width: parsed.width,
        height: parsed.height,
      ),
    );
    await host.generateImage();
    // 生图失败时不误报完成 (此时 selectedImage 仍是旧图)
    final selected = host.selectedImage;
    if (host.errorMessage == null && selected != null) {
      host.addInfoMessage(
        l10n.slashNaiDone(
          selected.localFilePath ?? l10n.slashNaiDoneFallback,
          parsed.width,
          parsed.height,
          selected.seed,
        ),
      );
    }
    host.notifyView();
  }
}
