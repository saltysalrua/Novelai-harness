import 'dart:typed_data';
import '../../core/harness/skills/skills.dart';

/// 导入预览快照。取消编辑时无需清理磁盘；确认后才安装到应用目录。
class SkillPackage {
  final Skill skill;
  final Map<String, Uint8List> files;

  SkillPackage({required this.skill, required Map<String, Uint8List> files})
    : files = Map.unmodifiable({
        for (final entry in files.entries)
          entry.key: Uint8List.fromList(entry.value).asUnmodifiableView(),
      });
}
