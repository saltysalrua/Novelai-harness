import 'dart:convert';

import '../../core/harness/presets/agent_preset.dart';

enum PresetImportError {
  invalidJson,
  invalidField,
  unknownTool,
  unknownParameter,
}

class PresetImportException implements Exception {
  final PresetImportError code;
  final String detail;
  const PresetImportException(this.code, [this.detail = '']);
}

/// Portable presets are stricter than legacy saved configuration: missing
/// permissions must never fall back to the legacy full-access defaults.
class PresetTransferService {
  static List<AgentPreset> decode(
    String source, {
    required Iterable<AgentPreset> existing,
    required Iterable<String> availableToolNames,
  }) {
    Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException {
      throw const PresetImportException(PresetImportError.invalidJson);
    }
    final entries = decoded is List ? decoded : [decoded];
    if (entries.isEmpty) {
      throw const PresetImportException(PresetImportError.invalidJson);
    }
    final ids = existing.map((p) => p.id).toSet();
    final tools = availableToolNames.toSet();
    final result = <AgentPreset>[];
    for (final entry in entries) {
      if (entry is! Map<String, dynamic>) {
        throw const PresetImportException(PresetImportError.invalidJson);
      }
      for (final key in ['id', 'name', 'description', 'systemPrompt']) {
        final value = entry[key];
        if (value is! String ||
            ((key == 'id' || key == 'name') && value.trim().isEmpty)) {
          throw PresetImportException(PresetImportError.invalidField, key);
        }
      }
      for (final key in [
        'enabledSkillIds',
        'enabledToolNames',
        'allowedModifiableParams',
      ]) {
        final value = entry[key];
        if (value is! List ||
            value.any((v) => v is! String || v.trim().isEmpty)) {
          throw PresetImportException(PresetImportError.invalidField, key);
        }
      }
      final preset = AgentPreset.fromJson({...entry, 'isBuiltin': false});
      for (final tool in preset.enabledToolNames) {
        if (!tools.contains(tool)) {
          throw PresetImportException(PresetImportError.unknownTool, tool);
        }
      }
      for (final parameter in preset.allowedModifiableParams) {
        if (!PresetParamKeys.all.contains(parameter)) {
          throw PresetImportException(
            PresetImportError.unknownParameter,
            parameter,
          );
        }
      }
      var id = preset.id;
      var suffix = 2;
      while (!ids.add(id)) {
        id = '${preset.id}-$suffix';
        suffix++;
      }
      result.add(preset.copyWith(id: id));
    }
    return result;
  }

  static String encode(AgentPreset preset) => const JsonEncoder.withIndent(
    '  ',
  ).convert(preset.copyWith(isBuiltin: false).toJson());
}
