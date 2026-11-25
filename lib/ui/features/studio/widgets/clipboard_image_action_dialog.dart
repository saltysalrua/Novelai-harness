import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../data/models/novelai_models.dart';
import '../../../core/context_l10n.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/theme_context_extensions.dart';
import '../../../core/widgets/app_badge.dart';
import '../../../core/widgets/app_dialog_scaffold.dart';
import '../../../core/widgets/app_segmented_controls.dart';

/// 全局 Ctrl+V 粘贴剪贴板图片后的目标动作
enum ClipboardImageAction {
  /// 读取图片 AI 生成元数据
  readMetadata,

  /// 添加到侧边栏「精准参考 (Precise Reference)」
  addPreciseReference,

  /// 添加到侧边栏「Vibe Transfer」
  addVibeTransfer,

  /// 导入到工作台自由大画布 / 批注板作为参考图
  importToBoard,
}

/// 全局 Ctrl+V 粘贴图片动作选择弹窗
///
/// 展示剪贴板图片缩略图与元数据检测状态，让用户明确选择后续用途，
/// 同时支持数字键 `1~4` 快捷选择与 `ESC` 取消。
class ClipboardImageActionDialog extends StatelessWidget {
  final Uint8List imageBytes;
  final String fileName;
  final ImageMetadataResult? metadata;
  final NaiModel currentModel;

  const ClipboardImageActionDialog({
    super.key,
    required this.imageBytes,
    required this.fileName,
    required this.metadata,
    required this.currentModel,
  });

  static Future<ClipboardImageAction?> show(
    BuildContext context, {
    required Uint8List imageBytes,
    required String fileName,
    required ImageMetadataResult? metadata,
    required NaiModel currentModel,
  }) {
    return AppDialogScaffold.show<ClipboardImageAction>(
      context: context,
      builder: (_) => ClipboardImageActionDialog(
        imageBytes: imageBytes,
        fileName: fileName,
        metadata: metadata,
        currentModel: currentModel,
      ),
    );
  }

  List<_ActionSpec> _buildOptions(BuildContext context) {
    final l10n = context.l10n;
    final hasMetadata = metadata != null && metadata!.hasData;
    final supportsPrecise = currentModel.supportsPreciseReference;
    final supportsVibe = currentModel.supportsVibeTransfer;

    return [
      if (hasMetadata)
        _ActionSpec(
          action: ClipboardImageAction.readMetadata,
          icon: Icons.info_outline_rounded,
          title: l10n.pasteActionReadMetadata,
          highlight: true,
        ),
      _ActionSpec(
        action: ClipboardImageAction.addPreciseReference,
        icon: Icons.style_outlined,
        title: l10n.pasteActionPrecise,
        subtitle: supportsPrecise
            ? null
            : l10n.pasteActionPreciseUnsupportedSubtitle,
        highlight: !hasMetadata && supportsPrecise,
        muted: !supportsPrecise,
      ),
      _ActionSpec(
        action: ClipboardImageAction.addVibeTransfer,
        icon: Icons.auto_awesome_motion_outlined,
        title: l10n.pasteActionVibe,
        subtitle: supportsVibe ? null : l10n.pasteActionVibeUnsupportedSubtitle,
        highlight: !hasMetadata && !supportsPrecise && supportsVibe,
        muted: !supportsVibe,
      ),
      _ActionSpec(
        action: ClipboardImageAction.importToBoard,
        icon: Icons.dashboard_customize_outlined,
        title: l10n.pasteActionBoard,
        highlight: !hasMetadata && !supportsPrecise && !supportsVibe,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final l10n = context.l10n;
    final hasMetadata = metadata != null && metadata!.hasData;
    final options = _buildOptions(context);
    final defaultOption = options.firstWhere(
      (o) => o.highlight,
      orElse: () => options.first,
    );

    final digitKeys = <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ];
    final numpadKeys = <LogicalKeyboardKey>[
      LogicalKeyboardKey.numpad1,
      LogicalKeyboardKey.numpad2,
      LogicalKeyboardKey.numpad3,
      LogicalKeyboardKey.numpad4,
    ];

    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < options.length && i < 4; i++) ...{
          SingleActivator(digitKeys[i]): () =>
              Navigator.of(context).pop(options[i].action),
          SingleActivator(numpadKeys[i]): () =>
              Navigator.of(context).pop(options[i].action),
        },
        const SingleActivator(LogicalKeyboardKey.enter): () =>
            Navigator.of(context).pop(defaultOption.action),
        const SingleActivator(LogicalKeyboardKey.numpadEnter): () =>
            Navigator.of(context).pop(defaultOption.action),
      },
      child: AppDialogScaffold(
        title: l10n.pasteDialogTitle,
        width: 420,
        maxHeight: 520,
        minimalChrome: true,
        body: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 图片预览摘要条
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colors.mutedBackground.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(color: colors.borderSubtle),
                ),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        width: 56,
                        height: 56,
                        color: colors.cardBackground,
                        child: Image.memory(
                          imageBytes,
                          fit: BoxFit.cover,
                          cacheWidth: 180,
                          gaplessPlayback: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fileName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: colors.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          AppBadge.pill(
                            label: hasMetadata
                                ? l10n.pasteMetadataDetected
                                : l10n.pasteMetadataNone,
                            variant: hasMetadata
                                ? AppBadgeVariant.primary
                                : AppBadgeVariant.neutral,
                            fontSize: 10.5,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // 可选动作列表
              for (var i = 0; i < options.length; i++) ...[
                Opacity(
                  opacity: options[i].muted ? 0.62 : 1.0,
                  child: AppOptionCard<ClipboardImageAction>(
                    key: Key('paste_action_${options[i].action.name}'),
                    value: options[i].action,
                    isSelected: options[i].highlight,
                    icon: options[i].icon,
                    title: '${i + 1}. ${options[i].title}',
                    subtitle: options[i].subtitle,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    onSelected: (action) => Navigator.of(context).pop(action),
                  ),
                ),
                if (i < options.length - 1) const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionSpec {
  final ClipboardImageAction action;
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool highlight;
  final bool muted;

  const _ActionSpec({
    required this.action,
    required this.icon,
    required this.title,
    this.subtitle,
    this.highlight = false,
    this.muted = false,
  });
}
