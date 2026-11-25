import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../../data/models/novelai_models.dart';
import '../../../data/models/prompt_library_models.dart';
import '../../../data/services/anlas_calculator.dart';
import '../types.dart';
import 'agent_tool.dart';

/// 精准参考添加回调
typedef AddPreciseReferenceCallback =
    void Function(
      Uint8List bytes, {
      String? fileName,
      NaiPreciseRefType? type,
      bool? preferSameOutfit,
      double? strength,
      double? fidelity,
      bool replace,
    });

/// 精准参考更新回调
typedef UpdatePreciseReferenceCallback =
    void Function(
      String id, {
      NaiPreciseRefType? type,
      bool? preferSameOutfit,
      double? strength,
      double? fidelity,
      bool? enabled,
    });

/// Vibe 从字节导入回调
typedef ImportVibeFromBytesCallback =
    Future<int> Function({
      required String fileName,
      required Uint8List bytes,
      double? strength,
      double? informationExtracted,
      bool replace,
    });

/// Vibe 更新回调
typedef UpdateVibeReferenceCallback =
    void Function(
      String id, {
      double? strength,
      double? informationExtracted,
      bool? enabled,
    });

/// 从词库条目加载参考引导回调
typedef ApplyLibraryReferencesCallback =
    Future<({int appliedPreciseCount, int appliedVibeCount})> Function(
      PromptComboEntry entry, {
      bool includePrecise,
      bool includeVibe,
      bool replace,
      Set<String>? preciseRefIds,
      Set<String>? vibeRefIds,
    });

/// 构建当前工作台参考引导（精准参考 + Vibe Transfer）的可读状态报表，
/// 供 `reference_guides(action: "list")` 与 `get_studio_parameters` 共用。
String buildReferenceGuidesReport(NaiGenerationParams params) {
  final model = params.model;
  final precise = params.preciseReferences;
  final effectivePrecise = params.effectivePreciseReferences();
  final vibes = params.vibeReferences;
  final effectiveVibes = params.effectiveVibeReferences();

  if (precise.isEmpty && vibes.isEmpty) {
    return '当前未挂载任何精准参考或 Vibe Transfer。';
  }

  final buf = StringBuffer();
  buf.writeln(
    '当前模型: ${model.label} (${model.id}) | '
    '支持精准参考: ${model.supportsPreciseReference ? '是' : '否'} | '
    '支持 Vibe: ${model.supportsVibeTransfer ? '是' : '否'}',
  );

  if (params.isEffortForcedByPreciseReference &&
      params.effort == NaiEffort.medium) {
    buf.writeln('• 注意: V5 启用精准参考时已自动切换为通常档 (High effort)。');
  }

  if (precise.isNotEmpty) {
    final extraAnlas =
        effectivePrecise.length *
        AnlasCalculator.preciseReferenceCostPerImage *
        params.nSamples;
    buf.writeln(
      '精准参考 (共 ${precise.length} 张，当前模型生效 ${effectivePrecise.length} 张'
      '${extraAnlas > 0 ? '，预计额外 +$extraAnlas Anlas' : ''})：',
    );
    for (var i = 0; i < precise.length; i++) {
      final ref = precise[i];
      final effective = ref.isEffectiveFor(model);
      final name = (ref.fileName != null && ref.fileName!.trim().isNotEmpty)
          ? ref.fileName!.trim()
          : '#${i + 1}';
      final outfitHint =
          model.supportsOutfitReferences && ref.type.supportsPreferSameOutfit
          ? ', prefer_same_outfit: ${ref.preferSameOutfit}'
          : '';
      final fidelityHint = model.supportsPreciseReferenceFidelity
          ? ', fidelity: ${ref.fidelity.toStringAsFixed(2)}'
          : '';
      final status = !ref.enabled
          ? '已禁用'
          : (effective ? '生效 (${ref.resolveApiDescription(model)})' : '当前模型不生效');
      buf.writeln(
        '  - [${ref.id}] $name | type: ${ref.type.id}$outfitHint, '
        'strength: ${ref.strength.toStringAsFixed(2)}$fidelityHint | $status',
      );
    }
  }

  if (vibes.isNotEmpty) {
    final blockedByPrecise =
        model.supportsVibeTransfer && params.hasEffectivePreciseReferences;
    final pendingEncode = model.usesEncodedVibeTransfer
        ? effectiveVibes.where((v) => v.needsServerEncodingFor(model)).length
        : 0;
    final extraSlots =
        effectiveVibes.length > AnlasCalculator.vibeFreeSlotLimit
        ? effectiveVibes.length - AnlasCalculator.vibeFreeSlotLimit
        : 0;
    buf.writeln(
      'Vibe Transfer (共 ${vibes.length} 条，当前模型生效 ${effectiveVibes.length} 条'
      '${model.usesEncodedVibeTransfer ? '，强度归一化: ${params.normalizeVibeStrength ? '开' : '关'}' : ''})：',
    );
    if (blockedByPrecise) {
      buf.writeln('  • 提示: V4.5 下启用精准参考时会屏蔽 Vibe Transfer。');
    }
    if (pendingEncode > 0) {
      buf.writeln(
        '  • 待编码: $pendingEncode 条（首次生成将自动调用 /ai/encode-vibe，每条 +2 Anlas 并缓存复用）。',
      );
    }
    if (extraSlots > 0) {
      buf.writeln(
        '  • 超额槽位: 超过 4 张的部分共 $extraSlots 条（每多 1 张每张成图 +2 Anlas）。',
      );
    }
    for (final v in vibes) {
      final encStatus = model.usesEncodedVibeTransfer
          ? (v.hasValidEncodingFor(model)
                ? '已编码'
                : (v.hasRawImage ? '待编码(+2 Anlas)' : '无可用编码'))
          : (v.hasRawImage ? '原图直传' : '缺少原图');
      final status = !v.enabled
          ? '已禁用'
          : (v.isEffectiveFor(model) && !blockedByPrecise ? encStatus : '当前模型不生效');
      buf.writeln(
        '  - [${v.id}] ${v.displayName} | strength: ${v.strength.toStringAsFixed(2)}, '
        'info_extracted: ${v.informationExtracted.toStringAsFixed(2)} | $status',
      );
    }
  }

  return buf.toString().trimRight();
}

/// 统一工作台参考引导管理工具（精准参考 Precise Reference + Vibe Transfer）
class ReferenceGuidesTool extends AgentTool {
  final NaiGenerationParams Function() getCurrentParams;
  final AddPreciseReferenceCallback addPreciseReference;
  final UpdatePreciseReferenceCallback updatePreciseReference;
  final void Function(String id) removePreciseReference;
  final void Function() clearPreciseReferences;
  final ImportVibeFromBytesCallback importVibeFromBytes;
  final UpdateVibeReferenceCallback updateVibeReference;
  final void Function(String id) removeVibeReference;
  final void Function() clearVibeReferences;
  final void Function(bool value) setNormalizeVibeStrength;
  final List<NaiGeneratedImage> Function() getHistory;
  final Future<Uint8List?> Function(NaiGeneratedImage image) loadImageBytes;
  final List<PromptComboEntry> Function() getLibraryEntries;
  final ApplyLibraryReferencesCallback applyLibraryReferences;

  ReferenceGuidesTool({
    required this.getCurrentParams,
    required this.addPreciseReference,
    required this.updatePreciseReference,
    required this.removePreciseReference,
    required this.clearPreciseReferences,
    required this.importVibeFromBytes,
    required this.updateVibeReference,
    required this.removeVibeReference,
    required this.clearVibeReferences,
    required this.setNormalizeVibeStrength,
    required this.getHistory,
    required this.loadImageBytes,
    required this.getLibraryEntries,
    required this.applyLibraryReferences,
  }) : super(
         name: 'reference_guides',
         label: '参考引导管理',
         description:
             '管理工作台精准参考 (Precise Reference) 与 Vibe Transfer，支持与画板历史图及本地词库联动。\n'
             '- list: 查看当前挂载的精准参考与 Vibe 状态、参数、兼容提示与点数预估；\n'
             '- add_from_canvas: 将画板/历史中的图片挂载为精准参考或 Vibe（默认最新图 image_index=0）；\n'
             '- add_from_library: 将词库条目中保存的精准参考图和/或 Vibe 载入工作台；\n'
             '- update: 按 id 调整参考类型/prefer_same_outfit/strength/fidelity/information_extracted/enabled，或切换 normalize_vibe_strength；\n'
             '- remove: 按 id 或 ids 移除指定参考；\n'
             '- clear: 清空参考（scope: precise / vibe / all）。',
         parameters: const {
           'type': 'object',
           'properties': {
             'action': {
               'type': 'string',
               'enum': [
                 'list',
                 'add_from_canvas',
                 'add_from_library',
                 'update',
                 'remove',
                 'clear',
               ],
               'description': '操作类型',
             },
             'kind': {
               'type': 'string',
               'enum': ['precise', 'vibe'],
               'description': '目标参考类型，默认 precise (add_from_canvas)',
             },
             'image_index': {
               'type': 'integer',
               'minimum': 0,
               'description': '画板历史图索引，0 表示最新图 (add_from_canvas)',
             },
             'image_id': {
               'type': 'string',
               'description': '画板历史图 ID，优先于 image_index (add_from_canvas)',
             },
             'entry_id': {
               'type': 'string',
               'description': '词库条目 ID (add_from_library)',
             },
             'title': {
               'type': 'string',
               'description': '词库条目标题，未传 entry_id 时按标题精确匹配 (add_from_library)',
             },
             'include_precise': {
               'type': 'boolean',
               'description': '是否载入词库条目中的精准参考，默认 true (add_from_library)',
             },
             'include_vibe': {
               'type': 'boolean',
               'description': '是否载入词库条目中的 Vibe，默认 true (add_from_library)',
             },
             'ref_ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '可选：仅载入词库条目内指定 ID 的参考项 (add_from_library)',
             },
             'replace': {
               'type': 'boolean',
               'description': '是否先清空同类型已有参考再添加，默认 false',
             },
             'id': {
               'type': 'string',
               'description': '目标参考条目 ID (update / remove)',
             },
             'ids': {
               'type': 'array',
               'items': {'type': 'string'},
               'description': '批量移除的参考条目 ID 列表 (remove)',
             },
             'ref_type': {
               'type': 'string',
               'enum': ['character', 'character&style', 'style', 'outfit', 'costume'],
               'description': '精准参考类型 (add_from_canvas / update)',
             },
             'prefer_same_outfit': {
               'type': 'boolean',
               'description': 'V5 角色/角色与风格参考是否倾向保留原服装 (add_from_canvas / update)',
             },
             'strength': {
               'type': 'number',
               'description': '参考强度 (V5 精准参考 0~5.0；V4.5/Vibe 0~1.0)',
             },
             'fidelity': {
               'type': 'number',
               'description': '保真度，仅 V4.5 精准参考生效 (0~1.0)',
             },
             'information_extracted': {
               'type': 'number',
               'description': 'Vibe 信息提取度 (0.01~1.0)',
             },
             'enabled': {
               'type': 'boolean',
               'description': '启用或禁用该参考条目 (update)',
             },
             'normalize_vibe_strength': {
               'type': 'boolean',
               'description': '全局多 Vibe 强度归一化开关 (update)',
             },
             'scope': {
               'type': 'string',
               'enum': ['precise', 'vibe', 'all'],
               'description': '清空范围，默认 all (clear)',
             },
           },
           'required': ['action'],
         },
       );

  @override
  Future<ToolResult> execute(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final action = (args['action'] as String?)?.trim().toLowerCase() ?? '';
    return switch (action) {
      'list' => ToolResult(
        toolCallId: toolCallId,
        content: buildReferenceGuidesReport(getCurrentParams()),
      ),
      'add_from_canvas' => _addFromCanvas(toolCallId, args),
      'add_from_library' => _addFromLibrary(toolCallId, args),
      'update' => _update(toolCallId, args),
      'remove' => _remove(toolCallId, args),
      'clear' => _clear(toolCallId, args),
      _ => ToolResult(
        toolCallId: toolCallId,
        content:
            '错误：reference_guides 的 action 必须是 list / add_from_canvas / add_from_library / update / remove / clear。',
        isError: true,
      ),
    };
  }

  Future<ToolResult> _addFromCanvas(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final history = getHistory();
    if (history.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '画板历史为空，没有可挂载的图片。',
        isError: true,
      );
    }

    NaiGeneratedImage? target;
    final imageId = (args['image_id'] as String?)?.trim() ?? '';
    if (imageId.isNotEmpty) {
      target = history.where((img) => img.id == imageId).firstOrNull;
      if (target == null) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未在画板历史中找到 ID 为 "$imageId" 的图片。',
          isError: true,
        );
      }
    } else {
      final index = (args['image_index'] as num?)?.toInt() ?? 0;
      if (index < 0 || index >= history.length) {
        return ToolResult(
          toolCallId: toolCallId,
          content: 'image_index=$index 超出范围（当前共 ${history.length} 张历史图）。',
          isError: true,
        );
      }
      target = history[index];
    }

    final bytes = target.bytes.isNotEmpty
        ? target.bytes
        : await loadImageBytes(target);
    if (bytes == null || bytes.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '无法读取图片字节（可能已被清理）。',
        isError: true,
      );
    }

    final fileName = target.localFilePath != null
        ? p.basename(target.localFilePath!)
        : '${target.id}.png';
    final kind = (args['kind'] as String?)?.trim().toLowerCase() ?? 'precise';
    final replace = args['replace'] == true;

    if (kind == 'vibe') {
      final count = await importVibeFromBytes(
        fileName: fileName,
        bytes: bytes,
        strength: (args['strength'] as num?)?.toDouble(),
        informationExtracted: (args['information_extracted'] as num?)?.toDouble(),
        replace: replace,
      );
      if (count <= 0) {
        return ToolResult(
          toolCallId: toolCallId,
          content: '未能将画板图片导入为 Vibe Transfer。',
          isError: true,
        );
      }
      return ToolResult(
        toolCallId: toolCallId,
        content:
            '已将画板图片 ($fileName) ${replace ? '替换' : '添加'}到 Vibe Transfer（$count 条）。\n'
            '${buildReferenceGuidesReport(getCurrentParams())}',
      );
    }

    final refType = args['ref_type'] is String
        ? NaiPreciseRefType.fromId((args['ref_type'] as String).trim())
        : NaiPreciseRefType.characterAndStyle;
    addPreciseReference(
      bytes,
      fileName: fileName,
      type: refType,
      preferSameOutfit: args['prefer_same_outfit'] is bool
          ? args['prefer_same_outfit'] as bool
          : null,
      strength: (args['strength'] as num?)?.toDouble(),
      fidelity: (args['fidelity'] as num?)?.toDouble(),
      replace: replace,
    );
    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已将画板图片 ($fileName) ${replace ? '替换' : '添加'}到精准参考。\n'
          '${buildReferenceGuidesReport(getCurrentParams())}',
    );
  }

  Future<ToolResult> _addFromLibrary(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final entries = getLibraryEntries();
    final entryId = (args['entry_id'] as String?)?.trim() ?? '';
    final title = (args['title'] as String?)?.trim() ?? '';
    if (entryId.isEmpty && title.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '请提供 entry_id 或 title 以定位词库条目。',
        isError: true,
      );
    }

    PromptComboEntry? target;
    if (entryId.isNotEmpty) {
      target = entries.where((e) => e.id == entryId).firstOrNull;
    } else {
      final lower = title.toLowerCase();
      target =
          entries.where((e) => e.title.trim() == title).firstOrNull ??
          entries
              .where((e) => e.title.trim().toLowerCase() == lower)
              .firstOrNull;
    }

    if (target == null) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未在本地词库中找到指定条目（entry_id="$entryId", title="$title"）。',
        isError: true,
      );
    }
    if (!target.hasReferenceGuides) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '词库条目「${target.title}」(${target.id}) 未关联任何精准参考图或 Vibe。',
        isError: true,
      );
    }

    final includePrecise = args['include_precise'] is bool
        ? args['include_precise'] as bool
        : true;
    final includeVibe = args['include_vibe'] is bool
        ? args['include_vibe'] as bool
        : true;
    final replace = args['replace'] == true;
    Set<String>? refIdFilter;
    final rawRefIds = args['ref_ids'];
    if (rawRefIds is List && rawRefIds.isNotEmpty) {
      refIdFilter = rawRefIds
          .map((e) => e.toString().trim())
          .where((s) => s.isNotEmpty)
          .toSet();
    }

    final result = await applyLibraryReferences(
      target,
      includePrecise: includePrecise,
      includeVibe: includeVibe,
      replace: replace,
      preciseRefIds: refIdFilter,
      vibeRefIds: refIdFilter,
    );

    if (result.appliedPreciseCount == 0 && result.appliedVibeCount == 0) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未能从词库条目「${target.title}」加载任何参考图（可能本地图片缺失或过滤条件无匹配）。',
        isError: true,
      );
    }

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已从词库「${target.title}」载入参考引导（精准参考 ${result.appliedPreciseCount} 张，Vibe ${result.appliedVibeCount} 条）。\n'
          '${buildReferenceGuidesReport(getCurrentParams())}',
    );
  }

  Future<ToolResult> _update(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    var updatedGlobal = false;
    if (args['normalize_vibe_strength'] is bool) {
      setNormalizeVibeStrength(args['normalize_vibe_strength'] as bool);
      updatedGlobal = true;
    }

    final id = (args['id'] as String?)?.trim() ?? '';
    if (id.isEmpty) {
      if (updatedGlobal) {
        return ToolResult(
          toolCallId: toolCallId,
          content:
              '已更新 Vibe 全局强度归一化设置。\n${buildReferenceGuidesReport(getCurrentParams())}',
        );
      }
      return ToolResult(
        toolCallId: toolCallId,
        content: '请提供要更新的参考条目 id（或 normalize_vibe_strength）。',
        isError: true,
      );
    }

    final params = getCurrentParams();
    final isPrecise = params.preciseReferences.any((r) => r.id == id);
    final isVibe = params.vibeReferences.any((v) => v.id == id);
    if (!isPrecise && !isVibe) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到 ID 为 "$id" 的参考条目。可先调用 reference_guides(action: "list") 查看 ID。',
        isError: true,
      );
    }

    if (isPrecise) {
      updatePreciseReference(
        id,
        type: args['ref_type'] is String
            ? NaiPreciseRefType.fromId((args['ref_type'] as String).trim())
            : null,
        preferSameOutfit: args['prefer_same_outfit'] is bool
            ? args['prefer_same_outfit'] as bool
            : null,
        strength: (args['strength'] as num?)?.toDouble(),
        fidelity: (args['fidelity'] as num?)?.toDouble(),
        enabled: args['enabled'] is bool ? args['enabled'] as bool : null,
      );
    } else {
      updateVibeReference(
        id,
        strength: (args['strength'] as num?)?.toDouble(),
        informationExtracted: (args['information_extracted'] as num?)?.toDouble(),
        enabled: args['enabled'] is bool ? args['enabled'] as bool : null,
      );
    }

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已更新参考条目 [$id]。\n${buildReferenceGuidesReport(getCurrentParams())}',
    );
  }

  Future<ToolResult> _remove(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final ids = <String>{};
    final single = (args['id'] as String?)?.trim() ?? '';
    if (single.isNotEmpty) ids.add(single);
    final rawIds = args['ids'];
    if (rawIds is List) {
      for (final item in rawIds) {
        final s = item.toString().trim();
        if (s.isNotEmpty) ids.add(s);
      }
    }
    if (ids.isEmpty) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '请提供要移除的 id 或 ids。',
        isError: true,
      );
    }

    final params = getCurrentParams();
    final preciseIds = params.preciseReferences.map((r) => r.id).toSet();
    final vibeIds = params.vibeReferences.map((v) => v.id).toSet();

    var removedCount = 0;
    for (final id in ids) {
      if (preciseIds.contains(id)) {
        removePreciseReference(id);
        removedCount++;
      } else if (vibeIds.contains(id)) {
        removeVibeReference(id);
        removedCount++;
      }
    }

    if (removedCount == 0) {
      return ToolResult(
        toolCallId: toolCallId,
        content: '未找到匹配的参考条目 ID：${ids.join(', ')}。',
        isError: true,
      );
    }

    return ToolResult(
      toolCallId: toolCallId,
      content:
          '已移除 $removedCount 条参考引导。\n${buildReferenceGuidesReport(getCurrentParams())}',
    );
  }

  Future<ToolResult> _clear(
    String toolCallId,
    Map<String, dynamic> args,
  ) async {
    final scope = (args['scope'] as String?)?.trim().toLowerCase() ?? 'all';
    switch (scope) {
      case 'precise':
        clearPreciseReferences();
        return ToolResult(toolCallId: toolCallId, content: '已清空全部精准参考图。');
      case 'vibe':
        clearVibeReferences();
        return ToolResult(toolCallId: toolCallId, content: '已清空全部 Vibe Transfer。');
      case 'all':
        clearPreciseReferences();
        clearVibeReferences();
        return ToolResult(toolCallId: toolCallId, content: '已清空全部精准参考与 Vibe Transfer。');
      default:
        return ToolResult(
          toolCallId: toolCallId,
          content: 'scope 必须是 precise / vibe / all。',
          isError: true,
        );
    }
  }
}
