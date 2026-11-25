import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:pasteboard/pasteboard.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../../data/services/anlas_calculator.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_action_button.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_drop_target_overlay.dart';
import '../../../core/widgets/app_dropdown.dart';
import '../../../core/widgets/app_empty_state.dart';
import '../../../core/widgets/app_icon_button.dart';
import '../../../core/widgets/app_number_slider.dart';
import '../../../core/widgets/app_page_stack.dart';
import '../../../core/widgets/app_segmented_controls.dart';
import '../../../core/widgets/app_toast.dart';
import '../../../core/widgets/app_toggle_controls.dart';
import '../view_models/studio_view_model.dart';
import 'studio_shared.dart';

/// 侧边栏「参考」统一工作区：精准参考 (Precise Reference) ↔ Vibe Transfer
///
/// - **精准参考**：支持 V5 (角色 / 角色与风格 / 风格 / 服装 + 倾向相同服装 + 强度 0~5.0)
///   与 V4.5 (角色 / 角色与风格 / 风格 + 强度 0~1.0 + 保真度 0~1.0)。
/// - **Vibe Transfer**：支持 V4 / V4.5 (编码式，支持 `.naiv4vibe` / `.naiv4vibebundle` /
///   内嵌 PNG / 原图服务端编码 + 强度归一化) 与 V3 (原图 448×448 直传)；
///   V5 官网暂未开放，V4.5 下与精准参考互斥。
class PreciseReferencePage extends StatefulWidget {
  final StudioViewModel viewModel;

  const PreciseReferencePage({super.key, required this.viewModel});

  @override
  State<PreciseReferencePage> createState() => _PreciseReferencePageState();
}

class _PreciseReferencePageState extends State<PreciseReferencePage> {
  static const Set<String> _imageExtensions = {
    'png',
    'jpg',
    'jpeg',
    'webp',
    'bmp',
  };

  static const Set<String> _vibeExtensions = {
    ..._imageExtensions,
    'naiv4vibe',
    'naiv4vibebundle',
  };

  bool _isDragging = false;

  bool get _isVibeSubTab => widget.viewModel.referenceSubTab == 1;

  Future<void> _pickFiles() async {
    final isVibe = _isVibeSubTab;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: (isVibe ? _vibeExtensions : _imageExtensions)
            .toList(),
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;

      for (final file in result.files) {
        Uint8List? bytes = file.bytes;
        if ((bytes == null || bytes.isEmpty) &&
            file.path != null &&
            file.path!.isNotEmpty) {
          final diskFile = File(file.path!);
          if (await diskFile.exists()) {
            bytes = await diskFile.readAsBytes();
          }
        }
        if (bytes == null || bytes.isEmpty) continue;

        if (isVibe) {
          await widget.viewModel.importVibeReferencesFromFile(
            fileName: file.name,
            bytes: bytes,
          );
        } else {
          widget.viewModel.addPreciseReferenceFromBytes(
            bytes,
            fileName: file.name,
          );
        }
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, message: '$e', tone: AppToastTone.error);
    }
  }

  Future<void> _pasteFromClipboard() async {
    final isVibe = _isVibeSubTab;
    try {
      final bytes = await Pasteboard.image;
      if (bytes != null && bytes.isNotEmpty) {
        if (isVibe) {
          await widget.viewModel.importVibeReferencesFromFile(
            fileName: 'clipboard.png',
            bytes: bytes,
          );
        } else {
          widget.viewModel.addPreciseReferenceFromBytes(
            bytes,
            fileName: 'clipboard.png',
          );
        }
        return;
      }
      final files = await Pasteboard.files();
      final allowed = isVibe ? _vibeExtensions : _imageExtensions;
      var imported = 0;
      for (final path in files) {
        final ext = path.split('.').last.toLowerCase();
        if (!allowed.contains(ext)) continue;
        final file = File(path);
        if (await file.exists()) {
          final data = await file.readAsBytes();
          if (data.isEmpty) continue;
          final name = file.uri.pathSegments.isNotEmpty
              ? file.uri.pathSegments.last
              : 'pasted.$ext';
          if (isVibe) {
            imported += await widget.viewModel.importVibeReferencesFromFile(
              fileName: name,
              bytes: data,
            );
          } else {
            widget.viewModel.addPreciseReferenceFromBytes(data, fileName: name);
            imported++;
          }
        }
      }
      if (imported == 0 && mounted) {
        showAppToast(
          context,
          message: context.l10n.referenceClipboardEmpty,
          tone: AppToastTone.info,
        );
      }
    } catch (e) {
      if (!mounted) return;
      showAppToast(context, message: '$e', tone: AppToastTone.error);
    }
  }

  Future<void> _addCurrentCanvasImage() async {
    final selected = widget.viewModel.selectedImage;
    if (selected == null) return;
    if (_isVibeSubTab) {
      await widget.viewModel.sendImageToVibeTransfer(selected);
    } else {
      await widget.viewModel.sendImageToPreciseReference(selected);
    }
  }

  Future<void> _handleDropFiles(DropDoneDetails details) async {
    if (_isDragging) {
      setState(() => _isDragging = false);
    }
    final isVibe = _isVibeSubTab;
    final allowed = isVibe ? _vibeExtensions : _imageExtensions;

    for (final file in details.files) {
      final name = file.name;
      final lower = name.toLowerCase();
      final ext = lower.contains('.') ? lower.split('.').last : '';
      // 若直接拖入 .naiv4vibe / .naiv4vibebundle，无论当前在哪个子页签都自动导入 Vibe 并切换
      final isExplicitVibeFile =
          ext == 'naiv4vibe' ||
          ext == 'naiv4vibebundle' ||
          lower.contains('.naiv4vibebundle');
      if (!isExplicitVibeFile && ext.isNotEmpty && !allowed.contains(ext)) {
        continue;
      }
      try {
        final bytes = await file.readAsBytes();
        if (bytes.isEmpty) continue;
        if (isVibe || isExplicitVibeFile) {
          await widget.viewModel.importVibeReferencesFromFile(
            fileName: name,
            bytes: bytes,
            switchToTab: isExplicitVibeFile,
          );
        } else {
          widget.viewModel.addPreciseReferenceFromBytes(bytes, fileName: name);
        }
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return DropTarget(
      onDragEntered: (_) {
        if (!_isDragging && mounted) setState(() => _isDragging = true);
      },
      onDragExited: (_) {
        if (_isDragging && mounted) setState(() => _isDragging = false);
      },
      onDragDone: _handleDropFiles,
      child: Stack(
        children: [
          ListenableBuilder(
            // 保活隐藏页暂停订阅，避免后台重复重建
            listenable: Listenable.merge([
              if (TickerMode.valuesOf(context).enabled) widget.viewModel,
            ]),
            builder: (context, _) {
              final vm = widget.viewModel;
              final subTab = vm.referenceSubTab;
              final preciseCount = vm.effectivePreciseReferenceCount;
              final vibeCount = vm.effectiveVibeReferenceCount;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // 1. 顶部固定子功能切换：精准参考 ↔ Vibe Transfer
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.lg,
                      AppSpacing.md,
                    ),
                    child: AppSegmentedCardBar<int>(
                      items: [
                        AppSegmentedItem<int>(
                          key: const Key('reference_subtab_precise'),
                          value: 0,
                          icon: Icons.style_outlined,
                          label: preciseCount > 0
                              ? '${l10n.tabReference} ($preciseCount)'
                              : l10n.tabReference,
                        ),
                        AppSegmentedItem<int>(
                          key: const Key('reference_subtab_vibe'),
                          value: 1,
                          icon: Icons.auto_awesome_motion_outlined,
                          label: vibeCount > 0
                              ? '${l10n.vibeTabTitle} ($vibeCount)'
                              : l10n.vibeTabTitle,
                        ),
                      ],
                      selectedValue: subTab,
                      expand: true,
                      itemPadding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 5,
                      ),
                      fontSize: 12,
                      iconSize: 13.5,
                      onValueChanged: vm.setReferenceSubTab,
                    ),
                  ),

                  // 2. 独立保活双槽页签：复用工作台标准水平轻滑动效，
                  //    杜绝跨页 Column 错位复用触发 AppStaggerReveal 逐级向上缩。
                  Expanded(
                    child: AppPageStack(
                      index: subTab,
                      itemCount: 2,
                      itemBuilder: (context, index) => SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.lg,
                          0,
                          AppSpacing.lg,
                          AppSpacing.lg,
                        ),
                        child: index == 0
                            ? _buildPreciseBody(context, vm)
                            : _buildVibeBody(context, vm),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),

          // 拖拽导入覆层
          AppDropTargetOverlay(
            isDragging: _isDragging,
            icon: _isVibeSubTab
                ? Icons.auto_awesome_motion_outlined
                : Icons.style_outlined,
            title: _isVibeSubTab ? l10n.vibeDropTitle : l10n.referenceDropTitle,
            subtitle: _isVibeSubTab
                ? l10n.vibeDropSubtitle
                : l10n.referenceDropSubtitle,
          ),
        ],
      ),
    );
  }

  Widget _buildPreciseBody(BuildContext context, StudioViewModel vm) {
    final colors = context.colors;
    final l10n = context.l10n;
    final params = vm.params;
    final model = params.model;
    final refs = vm.preciseReferences;
    final activeCount = vm.effectivePreciseReferenceCount;
    final extraCost =
        activeCount *
        AnlasCalculator.preciseReferenceCostPerImage *
        params.nSamples;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 页首标题 + 额外点数胶囊 + 清空按钮
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PageHeader(
                title: l10n.tabReference,
                subtitle: l10n.referencePageSubtitle,
              ),
            ),
            if (extraCost > 0 && !vm.isComfyUiMode) ...[
              const SizedBox(width: 8),
              AppBadge.pill(
                label: l10n.referenceCostPerGen(extraCost),
                variant: AppBadgeVariant.warning,
                fontSize: 10.5,
              ),
            ],
            if (refs.isNotEmpty) ...[
              const SizedBox(width: 6),
              ClearTextLink(onTap: vm.clearPreciseReferences),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // 上下文能力提示条
        if (vm.isComfyUiMode) ...[
          _NoticeBanner(
            icon: Icons.info_outline_rounded,
            text: l10n.referenceComfyModeHint,
            toneColor: colors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else if (!model.supportsPreciseReference) ...[
          _NoticeBanner(
            icon: Icons.warning_amber_rounded,
            text: l10n.referenceUnsupportedModelHint,
            toneColor: colors.warning,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else ...[
          if (params.isEffortForcedByPreciseReference &&
              params.effort == NaiEffort.medium) ...[
            _NoticeBanner(
              icon: Icons.bolt_rounded,
              text: l10n.paramsEffortForcedByReferenceHint,
              toneColor: colors.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (model.isV5 && activeCount > 0) ...[
            _NoticeBanner(
              icon: Icons.info_outline_rounded,
              text: l10n.referenceV5InpaintHint,
              toneColor: colors.textSecondary,
            ),
            const SizedBox(height: AppSpacing.md),
          ],
        ],

        // 快捷添加按钮组
        _buildImportActionBar(context, vm, isVibe: false),
        const SizedBox(height: AppSpacing.lg),

        // 空状态或参考图卡片列表
        if (refs.isEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.mutedBackground.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: AppEmptyState(
              icon: Icons.style_outlined,
              title: l10n.referenceEmptyTitle,
              description: l10n.referenceEmptyDescription,
              isCompact: true,
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < refs.length; i++) ...[
                _PreciseReferenceCard(
                  key: ValueKey(refs[i].id),
                  index: i,
                  reference: refs[i],
                  model: model,
                  onChanged: ({
                    NaiPreciseRefType? type,
                    bool? preferSameOutfit,
                    double? strength,
                    double? fidelity,
                    bool? enabled,
                  }) {
                    vm.updatePreciseReference(
                      refs[i].id,
                      type: type,
                      preferSameOutfit: preferSameOutfit,
                      strength: strength,
                      fidelity: fidelity,
                      enabled: enabled,
                    );
                  },
                  onRemove: () => vm.removePreciseReference(refs[i].id),
                ),
                if (i < refs.length - 1) const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildVibeBody(BuildContext context, StudioViewModel vm) {
    final colors = context.colors;
    final l10n = context.l10n;
    final params = vm.params;
    final model = params.model;
    final vibes = vm.vibeReferences;
    final activeVibes = vm.effectiveVibeReferences;
    final blockedByPrecise =
        model.supportsVibeTransfer && params.hasEffectivePreciseReferences;

    final extraSlotCount =
        activeVibes.length > AnlasCalculator.vibeFreeSlotLimit
        ? activeVibes.length - AnlasCalculator.vibeFreeSlotLimit
        : 0;
    final slotCost =
        extraSlotCount *
        AnlasCalculator.vibeExtraSlotCostPerImage *
        params.nSamples;
    final pendingEncodeCount = model.usesEncodedVibeTransfer
        ? activeVibes.where((v) => v.needsServerEncodingFor(model)).length
        : 0;
    final totalExtraCost =
        slotCost + pendingEncodeCount * AnlasCalculator.vibeEncodeCostPerImage;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 页首标题 + 额外点数胶囊 + 清空按钮
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: PageHeader(
                title: l10n.vibeTabTitle,
                subtitle: l10n.vibePageSubtitle,
              ),
            ),
            if (totalExtraCost > 0 && !vm.isComfyUiMode) ...[
              const SizedBox(width: 8),
              AppBadge.pill(
                label: l10n.referenceCostPerGen(totalExtraCost),
                variant: AppBadgeVariant.warning,
                fontSize: 10.5,
              ),
            ],
            if (vibes.isNotEmpty) ...[
              const SizedBox(width: 6),
              ClearTextLink(onTap: vm.clearVibeReferences),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.md),

        // 状态与兼容提示条
        if (vm.isComfyUiMode) ...[
          _NoticeBanner(
            icon: Icons.info_outline_rounded,
            text: l10n.referenceComfyModeHint,
            toneColor: colors.textSecondary,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else if (!model.supportsVibeTransfer) ...[
          _NoticeBanner(
            icon: Icons.warning_amber_rounded,
            text: l10n.vibeUnsupportedModelHint,
            toneColor: colors.warning,
          ),
          const SizedBox(height: AppSpacing.md),
        ] else ...[
          if (blockedByPrecise) ...[
            _NoticeBanner(
              icon: Icons.warning_amber_rounded,
              text: l10n.vibeBlockedByPreciseHint,
              toneColor: colors.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          if (extraSlotCount > 0) ...[
            _NoticeBanner(
              icon: Icons.payments_outlined,
              text: l10n.vibeOverFourCostHint(slotCost),
              toneColor: colors.warning,
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],

        // 快捷添加按钮组
        _buildImportActionBar(context, vm, isVibe: true),
        const SizedBox(height: AppSpacing.md),

        // V4 / V4.5 全局强度归一化开关 (仅编码式 Vibe 且存在条目时显示)
        if (vibes.isNotEmpty && model.usesEncodedVibeTransfer) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: colors.mutedBackground.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.vibeNormalizeStrengths,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                AppSwitch(
                  value: vm.normalizeVibeStrength,
                  width: 34,
                  height: 20,
                  onChanged: vm.setNormalizeVibeStrength,
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
        ],

        // 空状态或 Vibe 卡片列表
        if (vibes.isEmpty)
          Container(
            width: double.infinity,
            decoration: BoxDecoration(
              color: colors.mutedBackground.withValues(alpha: 0.45),
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(color: colors.borderSubtle),
            ),
            child: AppEmptyState(
              icon: Icons.auto_awesome_motion_outlined,
              title: l10n.vibeEmptyTitle,
              description: l10n.vibeEmptyDescription,
              isCompact: true,
            ),
          )
        else
          Column(
            children: [
              for (var i = 0; i < vibes.length; i++) ...[
                _VibeReferenceCard(
                  key: ValueKey(vibes[i].id),
                  vibe: vibes[i],
                  model: model,
                  isEncoding: vm.isEncodingVibe(vibes[i].id),
                  onChanged: ({
                    double? strength,
                    double? informationExtracted,
                    bool? enabled,
                  }) {
                    vm.updateVibeReference(
                      vibes[i].id,
                      strength: strength,
                      informationExtracted: informationExtracted,
                      enabled: enabled,
                    );
                  },
                  onEncodeNow: () => vm.encodeVibeReference(vibes[i].id),
                  onRemove: () => vm.removeVibeReference(vibes[i].id),
                ),
                if (i < vibes.length - 1) const SizedBox(height: AppSpacing.md),
              ],
            ],
          ),
      ],
    );
  }

  Widget _buildImportActionBar(
    BuildContext context,
    StudioViewModel vm, {
    required bool isVibe,
  }) {
    final l10n = context.l10n;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.sm,
      children: [
        AppActionButton(
          label: isVibe ? l10n.vibePickFile : l10n.referencePickImage,
          icon: isVibe
              ? Icons.file_upload_outlined
              : Icons.add_photo_alternate_outlined,
          variant: AppActionButtonVariant.primary,
          onPressed: _pickFiles,
        ),
        if (!kIsWeb)
          AppActionButton(
            label: l10n.referencePasteImage,
            icon: Icons.content_paste_rounded,
            variant: AppActionButtonVariant.outlined,
            onPressed: _pasteFromClipboard,
          ),
        if (vm.selectedImage != null)
          AppActionButton(
            label: l10n.referenceUseCanvasImage,
            icon: Icons.image_outlined,
            variant: AppActionButtonVariant.outlined,
            onPressed: _addCurrentCanvasImage,
          ),
      ],
    );
  }
}

/// 单张精准参考图卡片 (无业务状态，纯参数驱动)
class _PreciseReferenceCard extends StatelessWidget {
  final int index;
  final NaiPreciseReference reference;
  final NaiModel model;
  final void Function({
    NaiPreciseRefType? type,
    bool? preferSameOutfit,
    double? strength,
    double? fidelity,
    bool? enabled,
  }) onChanged;
  final VoidCallback onRemove;

  const _PreciseReferenceCard({
    super.key,
    required this.index,
    required this.reference,
    required this.model,
    required this.onChanged,
    required this.onRemove,
  });

  String _typeLabel(BuildContext context, NaiPreciseRefType type) {
    final l10n = context.l10n;
    return switch (type) {
      NaiPreciseRefType.character => l10n.referenceTypeCharacter,
      NaiPreciseRefType.characterAndStyle =>
        l10n.referenceTypeCharacterAndStyle,
      NaiPreciseRefType.style => l10n.referenceTypeStyle,
      NaiPreciseRefType.outfit => l10n.referenceTypeOutfit,
    };
  }

  IconData _typeIcon(NaiPreciseRefType type) {
    return switch (type) {
      NaiPreciseRefType.character => Icons.person_outline_rounded,
      NaiPreciseRefType.characterAndStyle => Icons.auto_awesome_outlined,
      NaiPreciseRefType.style => Icons.brush_outlined,
      NaiPreciseRefType.outfit => Icons.checkroom_outlined,
    };
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final supportsOutfit = model.supportsOutfitReferences;
    final supportsFidelity = model.supportsPreciseReferenceFidelity;
    final strengthMax = model.preciseReferenceStrengthMax;
    final isOutfitIgnored =
        reference.type.requiresOutfitSupport && !supportsOutfit;

    final availableTypes = <NaiPreciseRefType>[
      NaiPreciseRefType.character,
      NaiPreciseRefType.characterAndStyle,
      NaiPreciseRefType.style,
      if (supportsOutfit || reference.type == NaiPreciseRefType.outfit)
        NaiPreciseRefType.outfit,
    ];

    final showPreferSameOutfit =
        supportsOutfit && reference.type.supportsPreferSameOutfit;

    final title =
        (reference.fileName != null && reference.fileName!.trim().isNotEmpty)
        ? reference.fileName!.trim()
        : l10n.referenceImageItemTitle(index + 1);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: reference.enabled ? colors.borderDefault : colors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 顶部：缩略图 + 名称 + 开关 + 删除
          Row(
            children: [
              _ThumbnailButton(
                bytes: reference.imageBytes,
                enabled: reference.enabled,
                fallbackIcon: Icons.style_outlined,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: reference.enabled
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    AppBadge.pill(
                      label: _typeLabel(context, reference.type),
                      variant: reference.enabled && !isOutfitIgnored
                          ? AppBadgeVariant.primary
                          : AppBadgeVariant.neutral,
                      fontSize: 10,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AppSwitch(
                value: reference.enabled,
                width: 34,
                height: 20,
                onChanged: (v) => onChanged(enabled: v),
              ),
              const SizedBox(width: 6),
              AppIconButton(
                icon: Icons.close_rounded,
                size: 26,
                iconSize: 15,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.delete,
                onPressed: onRemove,
              ),
            ],
          ),

          if (isOutfitIgnored) ...[
            const SizedBox(height: AppSpacing.sm),
            _NoticeBanner(
              icon: Icons.warning_amber_rounded,
              text: l10n.referenceOutfitUnsupportedBadge,
              toneColor: colors.warning,
            ),
          ],

          const SizedBox(height: AppSpacing.md),

          // 参考类型选择
          AppDropdown<NaiPreciseRefType>(
            value: reference.type,
            enabled: reference.enabled,
            variant: AppDropdownVariant.compact,
            searchable: false,
            items: availableTypes
                .map(
                  (t) => AppDropdownItem<NaiPreciseRefType>(
                    value: t,
                    label: _typeLabel(context, t),
                    icon: _typeIcon(t),
                  ),
                )
                .toList(),
            onChanged: (v) => onChanged(type: v),
          ),

          // V5: 倾向相同服装开关 (仅 Character / Character & Style)
          if (showPreferSameOutfit) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.referencePreferSameOutfit,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: reference.enabled
                          ? colors.textSecondary
                          : colors.textMuted,
                    ),
                  ),
                ),
                AppSwitch(
                  value: reference.preferSameOutfit,
                  width: 34,
                  height: 20,
                  onChanged: reference.enabled
                      ? (v) => onChanged(preferSameOutfit: v)
                      : null,
                ),
              ],
            ),
          ],

          const SizedBox(height: AppSpacing.md),

          // 参考强度滑块 (V5: 0~5.0, V4.5: 0~1.0, 均支持输入框负值/超限)
          AppNumberSlider(
            title: l10n.referenceStrength,
            value: reference.strength,
            min: 0.0,
            max: strengthMax,
            step: 0.05,
            fractionDigits: 2,
            enabled: reference.enabled,
            allowNegativeInput: true,
            uncapInput: true,
            onChanged: (v) => onChanged(strength: v),
          ),

          // 保真度滑块 (仅 V4.5 显示；V5 已移除，强制 fidelity = 1.0)
          if (supportsFidelity) ...[
            const SizedBox(height: AppSpacing.md),
            AppNumberSlider(
              title: l10n.referenceFidelity,
              value: reference.fidelity,
              min: 0.0,
              max: 1.0,
              step: 0.05,
              fractionDigits: 2,
              enabled: reference.enabled,
              allowNegativeInput: true,
              uncapInput: true,
              onChanged: (v) => onChanged(fidelity: v),
            ),
          ],
        ],
      ),
    );
  }
}

/// 单条 Vibe Transfer 卡片 (无业务状态，纯参数驱动)
class _VibeReferenceCard extends StatelessWidget {
  final NaiVibeReference vibe;
  final NaiModel model;
  final bool isEncoding;
  final void Function({
    double? strength,
    double? informationExtracted,
    bool? enabled,
  }) onChanged;
  final VoidCallback onEncodeNow;
  final VoidCallback onRemove;

  const _VibeReferenceCard({
    super.key,
    required this.vibe,
    required this.model,
    required this.isEncoding,
    required this.onChanged,
    required this.onEncodeNow,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final isEncodedMode = model.usesEncodedVibeTransfer;
    final hasEncoding = vibe.hasValidEncodingFor(model);
    final needsEncode = vibe.needsServerEncodingFor(model);
    final missingForModel =
        model.supportsVibeTransfer && !vibe.isEffectiveFor(model) && vibe.enabled;

    final String statusLabel;
    final AppBadgeVariant statusVariant;
    if (!model.supportsVibeTransfer) {
      statusLabel = l10n.vibeStatusUnsupported;
      statusVariant = AppBadgeVariant.neutral;
    } else if (!isEncodedMode) {
      statusLabel = vibe.hasRawImage
          ? l10n.vibeStatusRawV3
          : l10n.vibeStatusMissingSource;
      statusVariant = vibe.hasRawImage
          ? AppBadgeVariant.primary
          : AppBadgeVariant.warning;
    } else if (hasEncoding) {
      statusLabel = l10n.vibeStatusEncoded;
      statusVariant = AppBadgeVariant.success;
    } else if (vibe.hasRawImage) {
      statusLabel = l10n.vibeStatusNeedsEncode;
      statusVariant = AppBadgeVariant.warning;
    } else {
      statusLabel = l10n.vibeStatusMissingModelEncoding;
      statusVariant = AppBadgeVariant.warning;
    }

    // 只有持有原图时才允许修改信息提取度 (纯预编码文件固定只读)
    final canEditInfo = vibe.enabled && vibe.hasRawImage;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: colors.cardBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: vibe.enabled ? colors.borderDefault : colors.borderSubtle,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _ThumbnailButton(
                bytes: vibe.previewBytes,
                enabled: vibe.enabled,
                fallbackIcon: Icons.auto_awesome_motion_outlined,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      vibe.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: vibe.enabled
                            ? colors.textPrimary
                            : colors.textMuted,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        AppBadge.pill(
                          label: statusLabel,
                          variant: vibe.enabled
                              ? statusVariant
                              : AppBadgeVariant.neutral,
                          fontSize: 10,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              AppSwitch(
                value: vibe.enabled,
                width: 34,
                height: 20,
                onChanged: (v) => onChanged(enabled: v),
              ),
              const SizedBox(width: 6),
              AppIconButton(
                icon: Icons.close_rounded,
                size: 26,
                iconSize: 15,
                variant: AppIconButtonVariant.ghost,
                tooltip: l10n.delete,
                onPressed: onRemove,
              ),
            ],
          ),

          if (needsEncode && vibe.enabled) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                AppActionButton(
                  label: isEncoding ? l10n.vibeEncodingNow : l10n.vibeEncodeNow,
                  icon: Icons.memory_rounded,
                  variant: AppActionButtonVariant.outlined,
                  isLoading: isEncoding,
                  onPressed: isEncoding ? null : onEncodeNow,
                ),
              ],
            ),
          ],

          if (missingForModel) ...[
            const SizedBox(height: AppSpacing.sm),
            _NoticeBanner(
              icon: Icons.warning_amber_rounded,
              text: isEncodedMode
                  ? l10n.vibeMissingEncodingHint
                  : l10n.vibeV3MissingImageHint,
              toneColor: colors.warning,
            ),
          ],

          const SizedBox(height: AppSpacing.md),

          // 参考强度滑块 (0.0 ~ 1.0，支持负值或超限输入)
          AppNumberSlider(
            title: l10n.referenceStrength,
            value: vibe.strength,
            min: 0.0,
            max: 1.0,
            step: 0.05,
            fractionDigits: 2,
            enabled: vibe.enabled,
            allowNegativeInput: true,
            uncapInput: true,
            onChanged: (v) => onChanged(strength: v),
          ),

          const SizedBox(height: AppSpacing.md),

          // 信息提取度滑块 (0.01 ~ 1.0；纯预编码无原图时锁定)
          AppNumberSlider(
            title: l10n.vibeInfoExtracted,
            value: vibe.informationExtracted,
            min: 0.01,
            max: 1.0,
            step: 0.05,
            fractionDigits: 2,
            enabled: canEditInfo,
            onChanged: (v) => onChanged(informationExtracted: v),
          ),
        ],
      ),
    );
  }
}

class _ThumbnailButton extends StatelessWidget {
  final Uint8List? bytes;
  final bool enabled;
  final IconData fallbackIcon;

  const _ThumbnailButton({
    required this.bytes,
    required this.enabled,
    required this.fallbackIcon,
  });

  void _showPreview(BuildContext context, Uint8List data) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(24),
        child: GestureDetector(
          onTap: () => Navigator.of(dialogContext).pop(),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.md),
              child: Image.memory(data, fit: BoxFit.contain),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final data = bytes;
    final hasImage = data != null && data.isNotEmpty;

    final box = Opacity(
      opacity: enabled ? 1.0 : 0.45,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          width: 52,
          height: 52,
          color: colors.mutedBackground,
          alignment: Alignment.center,
          child: hasImage
              ? Image.memory(
                  data,
                  fit: BoxFit.cover,
                  width: 52,
                  height: 52,
                  gaplessPlayback: true,
                  cacheWidth: 160,
                )
              : Icon(fallbackIcon, size: 22, color: colors.textMuted),
        ),
      ),
    );

    if (!hasImage) return box;
    return GestureDetector(
      onTap: () => _showPreview(context, data),
      child: MouseRegion(cursor: SystemMouseCursors.click, child: box),
    );
  }
}

class _NoticeBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color toneColor;

  const _NoticeBanner({
    required this.icon,
    required this.text,
    required this.toneColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: toneColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: toneColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 15, color: toneColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.4,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
