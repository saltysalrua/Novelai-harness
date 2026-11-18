import 'package:flutter/material.dart';

import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/prompt_token_counter_service.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_collapsible_section.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_tool_chip.dart';
import '../../../core/widgets/app_transitions.dart';
import '../../../core/widgets/overlay_anchor.dart';
import '../view_models/studio_view_model.dart';
import 'prompt_editor_card.dart';
import 'prompt_panel_shared.dart';
import 'prompt_resize_handle.dart';
import 'rich_prompt_text_controller.dart';
import 'studio_shared.dart';

/// 宽屏收起左侧栏时，从画板左上角快捷悬浮条弹出的精简版提示词面板浮窗。
///
/// 聚焦高频核心编辑：正向/负向提示词（含自动补全、权重快捷操作、Token 计数与预设芯片）、
/// 存在多角色时的折叠快捷编辑，以及一键生图 / 展开完整侧栏入口。
class CompactPromptPopover extends StatefulWidget {
  final StudioViewModel viewModel;

  const CompactPromptPopover({super.key, required this.viewModel});

  /// 在触发按钮下方弹出精简提示词面板浮窗。
  static Future<void> show(
    BuildContext anchorContext, {
    required StudioViewModel viewModel,
  }) {
    return showAnchoredPopover<void>(
      context: anchorContext,
      preferAbove: false,
      gap: 6,
      minWidth: 380,
      maxWidth: 420,
      maxHeight: 580,
      builder: (_) => CompactPromptPopover(viewModel: viewModel),
    );
  }

  @override
  State<CompactPromptPopover> createState() => _CompactPromptPopoverState();
}

class _CompactPromptPopoverState extends State<CompactPromptPopover> {
  late final RichPromptTextController _promptController;
  late final RichPromptTextController _negativeController;
  int _activeTab = 0; // 0: 正向提示词, 1: 负向提示词

  @override
  void initState() {
    super.initState();
    final params = widget.viewModel.params;
    _promptController = RichPromptTextController(text: params.prompt);
    _negativeController = RichPromptTextController(text: params.negativePrompt);
  }

  @override
  void didUpdateWidget(covariant CompactPromptPopover oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFromViewModel();
  }

  void _syncFromViewModel() {
    final params = widget.viewModel.params;
    if (_promptController.text != params.prompt) {
      _promptController.text = params.prompt;
    }
    if (_negativeController.text != params.negativePrompt) {
      _negativeController.text = params.negativePrompt;
    }
  }

  @override
  void dispose() {
    _promptController.dispose();
    _negativeController.dispose();
    super.dispose();
  }

  void _updatePrompt(String value) {
    widget.viewModel.updateParams(
      widget.viewModel.params.copyWith(prompt: value),
    );
  }

  void _updateNegative(String value) {
    widget.viewModel.updateParams(
      widget.viewModel.params.copyWith(negativePrompt: value),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = widget.viewModel;
    return KeyedSubtree(
      key: const Key('compact_prompt_popover'),
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          _syncFromViewModel();
          final colors = context.colors;
          final l10n = context.l10n;
          final params = viewModel.params;
          final isComfyUi = viewModel.isComfyUiMode;

          final showCategoryColors = viewModel.config.showTagCategoryColors;
          _promptController.setHighlightOptions(
            categoryColors: showCategoryColors,
          );
          _negativeController.setHighlightOptions(
            categoryColors: showCategoryColors,
          );

          final isPromptTab = _activeTab == 0;
          final hasClearableText = isPromptTab
              ? params.prompt.trim().isNotEmpty
              : (!params.isMediumEffort &&
                    params.negativePrompt.trim().isNotEmpty);

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 顶部合并切换栏：正向/负向分段切换 + 清空 + 展开完整侧栏
              Container(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
                decoration: BoxDecoration(
                  color: colors.elevatedBackground,
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: AppSegmentedCardBar<String>(
                        scrollable: true,
                        items: [
                          AppSegmentedItem(
                            value: 'prompt',
                            label: l10n.promptsPositiveTitle,
                          ),
                          AppSegmentedItem(
                            value: 'undesired',
                            label: l10n.promptsNegativeTitle,
                          ),
                        ],
                        selectedValue: isPromptTab ? 'prompt' : 'undesired',
                        onValueChanged: (v) {
                          setState(() => _activeTab = v == 'prompt' ? 0 : 1);
                        },
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (hasClearableText)
                          ClearTextLink(
                            onTap: () {
                              if (isPromptTab) {
                                _promptController.clear();
                                _updatePrompt('');
                              } else {
                                _negativeController.clear();
                                _updateNegative('');
                              }
                            },
                          ),
                        const SizedBox(width: 4),
                        AppIconButton(
                          key: const Key('compact_prompt_open_full_button'),
                          icon: Icons.view_sidebar_outlined,
                          size: 26,
                          iconSize: 15,
                          radius: 6,
                          variant: AppIconButtonVariant.ghost,
                          tooltip: l10n.quickPromptOpenFullTooltip,
                          onPressed: () {
                            Navigator.of(context).pop();
                            viewModel.setActiveSidebarTab(
                              StudioSidebarTab.prompts,
                              expandSidebar: true,
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 主体滚动区：内嵌单卡提示词编辑 (无嵌套外框，避免窗中窗)
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      AppPageSideBySide(
                        index: _activeTab,
                        enableBlur: false,
                        child: isPromptTab
                            ? PromptEditorCard(
                                key: const Key('compact_prompt_positive_card'),
                                controller: _promptController,
                                onChanged: _updatePrompt,
                                hintText: l10n.promptsTabbedPromptHint,
                                minLines: 4,
                                maxLines: 10,
                                minHeight: 96,
                                maxHeight: 280,
                                embedded: true,
                                toolbar: buildPositivePromptToolbar(
                                  context,
                                  viewModel,
                                  _promptController,
                                ),
                                enableAutocomplete:
                                    viewModel.config.enableTagAutocomplete,
                                showTranslation:
                                    viewModel.config.showTagTranslations,
                                tokenUsage: isComfyUi
                                    ? null
                                    : PromptTokenCounterService.instance
                                          .countPositive(params),
                              )
                            : PromptEditorCard(
                                key: const Key('compact_prompt_negative_card'),
                                controller: _negativeController,
                                onChanged: _updateNegative,
                                readOnly: params.isMediumEffort,
                                hintText: params.isMediumEffort
                                    ? l10n.promptsMediumUcLocked
                                    : l10n.promptsTabbedUndesiredHint,
                                minLines: 4,
                                maxLines: 10,
                                minHeight: 96,
                                maxHeight: 280,
                                embedded: true,
                                toolbar: buildNegativePromptToolbar(
                                  context,
                                  viewModel,
                                ),
                                enableAutocomplete:
                                    viewModel.config.enableTagAutocomplete,
                                showTranslation:
                                    viewModel.config.showTagTranslations,
                                tokenUsage: isComfyUi
                                    ? null
                                    : PromptTokenCounterService.instance
                                          .countNegative(params),
                              ),
                      ),

                      if (params.characterPrompts.isNotEmpty) ...[
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: colors.borderSubtle,
                        ),
                        Padding(
                          padding: const EdgeInsets.all(10),
                          child: _CompactCharacterSection(viewModel: viewModel),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 精简浮窗中的多角色提示词折叠区 (默认收起，仅在已添加角色时展示)。
class _CompactCharacterSection extends StatelessWidget {
  final StudioViewModel viewModel;

  const _CompactCharacterSection({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final characters = viewModel.params.characterPrompts;
    final enabledCount = characters.where((c) => c.enabled).length;

    return AppCollapsibleSection(
      title: l10n.charPromptDeckTabCharacter,
      trailing: AppBadge(
        label: l10n.quickPromptCharactersCount(enabledCount, characters.length),
        variant: enabledCount > 0
            ? AppBadgeVariant.primary
            : AppBadgeVariant.neutral,
        fontSize: 10.5,
      ),
      initiallyExpanded: false,
      headerPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      contentPadding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < characters.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            _CompactCharacterItem(
              key: ValueKey<String>(characters[i].id),
              character: characters[i],
              index: i,
              viewModel: viewModel,
            ),
          ],
        ],
      ),
    );
  }
}

class _CompactCharacterItem extends StatefulWidget {
  final NaiCharacterPrompt character;
  final int index;
  final StudioViewModel viewModel;

  const _CompactCharacterItem({
    super.key,
    required this.character,
    required this.index,
    required this.viewModel,
  });

  @override
  State<_CompactCharacterItem> createState() => _CompactCharacterItemState();
}

class _CompactCharacterItemState extends State<_CompactCharacterItem> {
  late final RichPromptTextController _controller;

  @override
  void initState() {
    super.initState();
    _controller = RichPromptTextController(text: widget.character.prompt);
  }

  @override
  void didUpdateWidget(covariant _CompactCharacterItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.character.id == widget.character.id &&
        _controller.text != widget.character.prompt) {
      _controller.text = widget.character.prompt;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final character = widget.character;
    final viewModel = widget.viewModel;
    final title = character.name.trim().isNotEmpty
        ? character.name.trim()
        : l10n.charPromptDefaultName(widget.index + 1);

    _controller.setHighlightOptions(
      categoryColors: viewModel.config.showTagCategoryColors,
    );

    return Container(
      decoration: BoxDecoration(
        color: colors.canvasBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: character.enabled
              ? colors.borderDefault
              : colors.borderSubtle,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Opacity(
        opacity: character.enabled ? 1.0 : 0.6,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
              child: Row(
                children: [
                  AppBadge(
                    label: '${widget.index + 1}',
                    fontSize: 10,
                    variant: AppBadgeVariant.neutral,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  AppToolChip(
                    isSelected: character.enabled,
                    icon: character.enabled
                        ? Icons.visibility_rounded
                        : Icons.visibility_off_rounded,
                    label: character.enabled
                        ? l10n.charPromptEnable
                        : l10n.charPromptDisable,
                    fontSize: 11,
                    iconSize: 12,
                    height: 24,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    onTap: () => viewModel.updateCharacterPrompt(
                      character.copyWith(enabled: !character.enabled),
                    ),
                  ),
                ],
              ),
            ),
            Divider(height: 1, thickness: 1, color: colors.borderSubtle),
            ResizableTextField(
              controller: _controller,
              onChanged: (value) => viewModel.updateCharacterPrompt(
                character.copyWith(prompt: value),
              ),
              hintText: l10n.charPromptPromptHint,
              defaultHeight: 54,
              minHeight: 44,
              maxHeight: 140,
              enableAutocomplete: viewModel.config.enableTagAutocomplete,
              showTranslation: viewModel.config.showTagTranslations,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              style: TextStyle(
                fontSize: 13,
                height: 1.42,
                color: colors.textPrimary,
              ),
              hintStyle: TextStyle(
                fontSize: 12,
                height: 1.42,
                color: colors.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
