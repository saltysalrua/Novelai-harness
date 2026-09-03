// 一次性恢复工具：从保存目录中的 PNG 元数据重建 image_history.json。
//
// 适用场景：历史上「图片历史持久化」被关闭时，image_history.json 被删除，
// 但图片文件本身仍在磁盘上且携带完整的 NovelAI Comment 元数据。
//
// 运行方式 (借 flutter test 宿主编译，可复用 lib 内全部服务)：
//   flutter test tool/recover_image_history.dart
//
// 行为：
//   1. 从应用 SharedPreferences JSON 读取 save_dir 与 max_persistent_images；
//   2. 扫描 save_dir 根目录的 nai_*.png (跳过 cache/ 与 board_refs/)，
//      成对存在的 _raw.png 让位于同名正式文件，仅有 _raw 时直接采用；
//   3. 解析每张图的 Comment 元数据 → 反向还原 NaiGenerationParams，
//      从文件名推导 超分/修复/AI编辑 角标；
//   4. 按修改时间倒序截取上限数量，写出 image_history.json。

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/image_metadata_service.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('recover image_history.json from disk PNGs', () async {
    final home =
        Platform.environment['USERPROFILE'] ?? Platform.environment['HOME']!;
    final prefsFile = File(
      p.join(
        home,
        'AppData',
        'Roaming',
        'com.novelai.harness',
        'novelai_harness',
        'shared_preferences.json',
      ),
    );
    expect(prefsFile.existsSync(), isTrue, reason: '未找到应用配置文件');
    final prefs =
        jsonDecode(prefsFile.readAsStringSync()) as Map<String, dynamic>;

    final saveDir = prefs['flutter.novelai_save_dir'] as String? ?? '';
    final maxImages =
        int.tryParse('${prefs['flutter.novelai_max_persistent_images']}') ?? 50;
    expect(saveDir.isNotEmpty, isTrue, reason: '配置中未设置保存目录');
    stdout.writeln('保存目录: $saveDir (上限 $maxImages 张)');

    final dir = Directory(saveDir);
    expect(dir.existsSync(), isTrue, reason: '保存目录不存在');

    // 1. 收集候选文件：根目录下的 nai_*.png
    final allPngs = dir
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('nai_'))
        .where((f) => f.path.endsWith('.png'))
        .toList();
    // 2. _raw 成对时让位：去掉与正式文件同名的 _raw
    final basenames = allPngs.map((f) => p.basename(f.path)).toSet();
    final candidates =
        allPngs.where((f) {
          final name = p.basename(f.path);
          if (!name.endsWith('_raw.png')) return true;
          final twin =
              '${name.substring(0, name.length - '_raw.png'.length)}.png';
          return !basenames.contains(twin);
        }).toList()..sort(
          (a, b) => b.lastModifiedSync().compareTo(a.lastModifiedSync()),
        );

    stdout.writeln('候选图片: ${candidates.length} 张');

    final entries = <Map<String, dynamic>>[];
    final usedIds = <String>{};

    for (final file in candidates) {
      if (entries.length >= maxImages) break;
      final name = p.basename(file.path);

      Uint8List bytes;
      try {
        bytes = file.readAsBytesSync();
      } catch (_) {
        continue;
      }

      // 解析元数据；正式文件被脱敏时回退到 _raw 双胞胎
      var meta = ImageMetadataService.parseMetadata(bytes);
      if (meta == null || !meta.hasData) {
        if (name.endsWith('_raw.png')) continue;
        final rawTwin = File(
          p.join(
            dir.path,
            '${name.substring(0, name.length - '.png'.length)}_raw.png',
          ),
        );
        if (!rawTwin.existsSync()) continue;
        try {
          meta = ImageMetadataService.parseMetadata(rawTwin.readAsBytesSync());
        } catch (_) {
          continue;
        }
        if (meta == null || !meta.hasData) continue;
      }

      final rawJson = meta.rawJson.isNotEmpty
          ? (jsonDecode(meta.rawJson) as Map<String, dynamic>)
          : <String, dynamic>{};

      final paramsJson = <String, dynamic>{
        'prompt': meta.prompt,
        'negativePrompt': meta.negativePrompt,
        'model': meta.model,
        'width': meta.width,
        'height': meta.height,
        'steps': meta.steps,
        'scale': meta.scale,
        'cfgRescale': meta.cfgRescale,
        'sampler': meta.sampler,
        'noiseSchedule': meta.noiseSchedule,
        'seed': meta.seed ?? -1,
        'nSamples': rawJson['n_samples'],
        'qualityToggle': meta.qualityToggle,
        'qualityPreset': meta.qualityPreset,
        'ucPresetKey': meta.ucPreset,
        'transparentBg': meta.transparentBackground,
        'characterPrompts': [
          for (var i = 0; i < meta.characterPrompts.length; i++)
            if (meta.characterPrompts[i].trim().isNotEmpty)
              NaiCharacterPrompt(
                id: 'recov${i.toRadixString(16).padLeft(4, '0')}',
                name: '角色 ${i + 1}',
                prompt: meta.characterPrompts[i],
              ).toJson(),
        ],
      };

      final params = NaiGenerationParams.fromJson(paramsJson);

      var id = '${file.lastModifiedSync().millisecondsSinceEpoch}';
      var dedupe = 0;
      while (usedIds.contains(id)) {
        dedupe++;
        id = '${file.lastModifiedSync().millisecondsSinceEpoch}_$dedupe';
      }
      usedIds.add(id);

      entries.add({
        'id': id,
        'localFilePath': file.path,
        'params': params.toJson(),
        'createdAt': file.lastModifiedSync().toIso8601String(),
        'seed': meta.seed ?? -1,
        'isOpusFree': params.isOpusFree,
        'annotations': <dynamic>[],
        if (name.startsWith('nai_inpaint_')) 'isInpainted': true,
        if (name.contains('_upscaled_')) 'isUpscaled': true,
        if (name.startsWith('nai_ai_edit_')) 'isAiEdited': true,
      });
    }

    stdout.writeln('成功解析: ${entries.length} 条');

    final historyFile = File(p.join(saveDir, 'image_history.json'));
    historyFile.writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert(entries),
      flush: true,
    );
    stdout.writeln('已写出: ${historyFile.path}');
    expect(entries, isNotEmpty, reason: '没有可恢复的图片记录');
  });
}
