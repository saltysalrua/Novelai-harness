import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../data/models/nai_precise_reference.dart';
import '../../../../data/models/prompt_library_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_segmented_controls.dart';

/// 词库条目选择性应用结果
class PromptComboApplySelection {
  final bool applyPrompt;
  final bool replacePrompt;
  final bool asCharacter;
  final bool asStyle;
  final Set<String> selectedPreciseRefIds;
  final Set<String> selectedVibeRefIds;
  final bool replaceReferences;

  const PromptComboApplySelection({
    required this.applyPrompt,
    this.replacePrompt = false,
    this.asCharacter = false,
    this.asStyle = false,
    this.selectedPreciseRefIds = const {},
    this.selectedVibeRefIds = const {},
    this.replaceReferences = false,
  });

  bool get hasAnySelection =>
      applyPrompt ||
      selectedPreciseRefIds.isNotEmpty ||
      selectedVibeRefIds.isNotEmpty;
}

enum _PromptApplyMode { append, replace, asCharacter, asStyleReplace, asStyleAppend }

/// 词库条目选择性应用弹窗：允许自由勾选「提示词 / 精准参考 / Vibe Transfer」及追加或替换模式。
class PromptComboApplyDialog extends StatefulWidget {
  final PromptComboEntry combo;

  const PromptComboApplyDialog({super.key, required this.combo});

  static Future<PromptComboApplySelection?> show(
    BuildContext context, {
    required PromptComboEntry combo,
  }) {
    return AppDialogScaffold.show<PromptComboApplySelection>(
      context: context,
      builder: (ctx) => PromptComboApplyDialog(combo: combo),
    );
  }

  @override
  State<PromptComboApplyDialog> createState() => _PromptComboApplyDialogState();
}

class _PromptComboApplyDialogState extends State<PromptComboApplyDialog> {
  late bool _applyPrompt;
  late _PromptApplyMode _promptMode;
  late final Set<String> _selectedPreciseIds;
  late final Set<String> _selectedVibeIds;
  bool _replaceReferences = false;

  PromptComboEntry get _combo => widget.combo;

  @override
  void initState() {
    super.initState();
    _applyPrompt = _combo.hasPromptText;
    _promptMode = _combo.isStyle
        ? _PromptApplyMode.asStyleReplace
        : _PromptApplyMode.append;
    _selectedPreciseIds = _combo.preciseReferences
        .where((r) => r.enabled)
        .map((r) => r.id)
        .toSet();
    if (_selectedPreciseIds.isEmpty && _combo.preciseReferences.isNotEmpty) {
      _selectedPreciseIds.addAll(_combo.preciseReferences.map((r) => r.id));
    }
    _selectedVibeIds = _combo.vibeReferences
        .where((v) => v.enabled)
        .map((v) => v.id)
        .toSet();
    if (_selectedVibeIds.isEmpty && _combo.vibeReferences.isNotEmpty) {
      _selectedVibeIds.addAll(_combo.vibeReferences.map((v) => v.id));
    }
  }

  bool get _hasAnySelection =>
      (_applyPrompt && _combo.hasPromptText) ||
      _selectedPreciseIds.isNotEmpty ||
      _selectedVibeIds.isNotEmpty;

  String _refTypeLabel(BuildContext context, NaiPreciseRefType type) {
    final l10n = context.l10n;
    return switch (type) {
      NaiPreciseRefType.character => l10n.referenceTypeCharacter,
      NaiPreciseRefType.characterAndStyle =>
          l10n.referenceTypeCharacterAndStyle,
      NaiPreciseRefType.style => l10n.referenceTypeStyle,
      NaiPreciseRefType.outfit => l10n.referenceTypeOutfit,
    };
  }

  void _confirm() {
    if (!_hasAnySelection) return;
    final replacePrompt =
        _promptMode == _PromptApplyMode.replace ||
        _promptMode == _PromptApplyMode.asStyleReplace;
    final asCharacter = _promptMode == _PromptApplyMode.asCharacter;
    final asStyle =
        _promptMode == _PromptApplyMode.asStyleReplace ||
        _promptMode == _PromptApplyMode.asStyleAppend;
    Navigator.of(context).pop(
      PromptComboApplySelection(
        applyPrompt: _applyPrompt && _combo.hasPromptText,
        replacePrompt: replacePrompt,
        asCharacter: asCharacter,
        asStyle: asStyle,
        selectedPreciseRefIds: Set<String>.from(_selectedPreciseIds),
        selectedVibeRefIds: Set<String>.from(_selectedVibeIds),
        replaceReferences: _replaceReferences,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final hasAnyRefSelected =
        _selectedPreciseIds.isNotEmpty || _selectedVibeIds.isNotEmpty;

    return AppDialogScaffold(
      title: l10n.librarySelectiveApplyTitle(_combo.title),
      width: 480,
      minimalChrome: true,
      body: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 520),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              // 1. 提示词勾选区块
              if (_combo.hasPromptText) ...[
                _SectionCard(
                  checked: _applyPrompt,
                  title: l10n.librarySelectiveApplyPromptSection,
                  subtitle: _combo.displayPromptSummary,
                  onToggle: () => setState(() => _applyPrompt = !_applyPrompt),
                  footer: _applyPrompt ? _buildPromptModeSelector(context) : null,
                ),
                const SizedBox(height: 10),
              ],

              // 2. 精准参考勾选区块
              if (_combo.hasPreciseReferences) ...[
                _buildRefGroupHeader(
                  context,
                  icon: Icons.style_outlined,
                  title: l10n.librarySelectiveApplyPreciseSection(
                    _combo.preciseReferences.length,
                  ),
                  allSelected:
                      _selectedPreciseIds.length ==
                      _combo.preciseReferences.length,
                  onToggleAll: () {
                    setState(() {
                      if (_selectedPreciseIds.length ==
                          _combo.preciseReferences.length) {
                        _selectedPreciseIds.clear();
                      } else {
                        _selectedPreciseIds
                          ..clear()
                          ..addAll(_combo.preciseReferences.map((r) => r.id));
                      }
                    });
                  },
                ),
                const SizedBox(height: 6),
                for (final ref in _combo.preciseReferences) ...[
                  _SelectableAssetTile(
                    checked: _selectedPreciseIds.contains(ref.id),
                    imagePath: ref.imagePath,
                    title:
                        (ref.fileName != null && ref.fileName!.trim().isNotEmpty)
                        ? ref.fileName!.trim()
                        : _refTypeLabel(context, ref.type),
                    badges: [
                      _refTypeLabel(context, ref.type),
                      '${l10n.referenceStrength} ${ref.strength.toStringAsFixed(2)}',
                    ],
                    onTap: () {
                      setState(() {
                        if (!_selectedPreciseIds.remove(ref.id)) {
                          _selectedPreciseIds.add(ref.id);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                ],
                const SizedBox(height: 4),
              ],

              // 3. Vibe Transfer 勾选区块
              if (_combo.hasVibeReferences) ...[
                _buildRefGroupHeader(
                  context,
                  icon: Icons.auto_awesome_motion_outlined,
                  title: l10n.librarySelectiveApplyVibeSection(
                    _combo.vibeReferences.length,
                  ),
                  allSelected:
                      _selectedVibeIds.length == _combo.vibeReferences.length,
                  onToggleAll: () {
                    setState(() {
                      if (_selectedVibeIds.length ==
                          _combo.vibeReferences.length) {
                        _selectedVibeIds.clear();
                      } else {
                        _selectedVibeIds
                          ..clear()
                          ..addAll(_combo.vibeReferences.map((v) => v.id));
                      }
                    });
                  },
                ),
                const SizedBox(height: 6),
                for (final vibe in _combo.vibeReferences) ...[
                  _SelectableAssetTile(
                    checked: _selectedVibeIds.contains(vibe.id),
                    imagePath: vibe.displayImagePath,
                    title: vibe.displayName,
                    badges: [
                      if (vibe.encodingsByModel.isNotEmpty)
                        l10n.vibeStatusEncoded,
                      '${l10n.referenceStrength} ${vibe.strength.toStringAsFixed(2)}',
                    ],
                    onTap: () {
                      setState(() {
                        if (!_selectedVibeIds.remove(vibe.id)) {
                          _selectedVibeIds.add(vibe.id);
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 6),
                ],
              ],

              // 4. 参考图追加 / 替换方式
              if (hasAnyRefSelected) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.elevatedBackground,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.librarySelectiveApplyRefModeLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      AppSegmentedPillBar<bool>(
                        variant: AppPillVariant.soft,
                        selectedValue: _replaceReferences,
                        onValueChanged: (v) =>
                            setState(() => _replaceReferences = v),
                        itemPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        items: [
                          AppSegmentedItem<bool>(
                            value: false,
                            label: l10n.librarySelectiveApplyModeAppend,
                          ),
                          AppSegmentedItem<bool>(
                            value: true,
                            label: l10n.librarySelectiveApplyModeReplace,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        AppActionButton(
          label: l10n.cancel,
          variant: AppActionButtonVariant.ghost,
          onPressed: () => Navigator.of(context).pop(),
        ),
        const SizedBox(width: 8),
        AppActionButton(
          label: l10n.librarySelectiveApplyConfirm,
          icon: Icons.bolt_outlined,
          variant: AppActionButtonVariant.primary,
          onPressed: _hasAnySelection ? _confirm : null,
        ),
      ],
    );
  }

  Widget _buildPromptModeSelector(BuildContext context) {
    final l10n = context.l10n;
    final items = _combo.isStyle
        ? [
            AppSegmentedItem<_PromptApplyMode>(
              value: _PromptApplyMode.asStyleReplace,
              label: l10n.libraryMenuApplyStyleReplace,
            ),
            AppSegmentedItem<_PromptApplyMode>(
              value: _PromptApplyMode.asStyleAppend,
              label: l10n.libraryMenuApplyStyleAppend,
            ),
            AppSegmentedItem<_PromptApplyMode>(
              value: _PromptApplyMode.append,
              label: l10n.librarySelectiveApplyModeAppend,
            ),
          ]
        : [
            AppSegmentedItem<_PromptApplyMode>(
              value: _PromptApplyMode.append,
              label: l10n.librarySelectiveApplyModeAppend,
            ),
            AppSegmentedItem<_PromptApplyMode>(
              value: _PromptApplyMode.replace,
              label: l10n.librarySelectiveApplyModeReplace,
            ),
            if (_combo.isCharacter)
              AppSegmentedItem<_PromptApplyMode>(
                value: _PromptApplyMode.asCharacter,
                label: l10n.libraryCardAddCharacter,
              ),
          ];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: AppSegmentedPillBar<_PromptApplyMode>(
        scrollable: true,
        variant: AppPillVariant.soft,
        selectedValue: _promptMode,
        onValueChanged: (v) => setState(() => _promptMode = v),
        itemPadding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        items: items,
      ),
    );
  }

  Widget _buildRefGroupHeader(
    BuildContext context, {
    required IconData icon,
    required String title,
    required bool allSelected,
    required VoidCallback onToggleAll,
  }) {
    final colors = context.colors;
    final l10n = context.l10n;
    return Row(
      children: [
        Icon(icon, size: 14, color: colors.textSecondary),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
          ),
        ),
        GestureDetector(
          onTap: onToggleAll,
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            child: Text(
              allSelected
                  ? l10n.librarySelectiveApplyUnselectAll
                  : l10n.librarySelectiveApplySelectAll,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w500,
                color: colors.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final bool checked;
  final String title;
  final String subtitle;
  final VoidCallback onToggle;
  final Widget? footer;

  const _SectionCard({
    required this.checked,
    required this.title,
    required this.subtitle,
    required this.onToggle,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.elevatedBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: checked
              ? colors.primary.withValues(alpha: 0.45)
              : colors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  checked
                      ? Icons.check_box_rounded
                      : Icons.check_box_outline_blank_rounded,
                  size: 18,
                  color: checked ? colors.primary : colors.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          height: 1.35,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          ?footer,
        ],
      ),
    );
  }
}

class _SelectableAssetTile extends StatelessWidget {
  final bool checked;
  final String? imagePath;
  final String title;
  final List<String> badges;
  final VoidCallback onTap;

  const _SelectableAssetTile({
    required this.checked,
    required this.imagePath,
    required this.title,
    required this.badges,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final path = imagePath?.trim();
    final hasFile = path != null && path.isNotEmpty && File(path).existsSync();

    return Material(
      color: colors.elevatedBackground,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: checked
                  ? colors.primary.withValues(alpha: 0.45)
                  : colors.borderSubtle,
            ),
          ),
          child: Row(
            children: [
              Icon(
                checked
                    ? Icons.check_box_rounded
                    : Icons.check_box_outline_blank_rounded,
                size: 18,
                color: checked ? colors.primary : colors.textMuted,
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Container(
                  width: 36,
                  height: 36,
                  color: colors.mutedBackground,
                  child: hasFile
                      ? Image(
                          image: ResizeImage(
                            FileImage(File(path)),
                            width: 96,
                            height: 96,
                            policy: ResizeImagePolicy.fit,
                          ),
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => Icon(
                            Icons.image_not_supported_outlined,
                            size: 16,
                            color: colors.textMuted,
                          ),
                        )
                      : Icon(
                          Icons.auto_awesome_motion_outlined,
                          size: 16,
                          color: colors.textMuted,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        for (final b in badges)
                          AppBadge.pill(
                            label: b,
                            variant: AppBadgeVariant.neutral,
                            fontSize: 10,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
