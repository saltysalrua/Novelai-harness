import '../../core/harness/skills/skill_format_exception.dart';
import 'dart:convert';
import 'dart:io';
import 'dart:io' as io show ZLibDecoder;
import 'dart:isolate';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import '../../core/harness/skills/skills.dart';
import '../models/skill_package.dart';

/// 标准技能包的唯一文件边界：安全解包、托管存储、资源读取和无损导出。
/// 从不执行脚本，也不把文档中的 allowed-tools 当作权限。
class SkillPackageService {
  static const maxPackageBytes = 32 * 1024 * 1024;
  static const maxFileBytes = 8 * 1024 * 1024;
  static const maxFiles = 512;
  static const maxInstructionBytes = 256 * 1024;

  /// 标准规范：小写字母、数字与连字符，不能以连字符开头或结尾。
  static final skillIdPattern = RegExp(
    r'^[a-z0-9](?:[a-z0-9-]{0,62}[a-z0-9])?$',
  );
  final Future<Directory> Function() _rootDirectory;

  SkillPackageService({Future<Directory> Function()? rootDirectory})
    : _rootDirectory = rootDirectory ?? _defaultRoot;

  static Future<Directory> _defaultRoot() async => Directory(
    p.join((await getApplicationSupportDirectory()).path, 'skill_packages'),
  );

  Future<SkillPackage> readImportFile(String path) async {
    final bytes = await _readBounded(File(path), maxPackageBytes);
    final name = p.basename(path);
    return Isolate.run(() => decodeImport(bytes, name));
  }

  /// .skill 是 ZIP 容器的常用扩展名；Markdown 继续兼容单文件导入。
  static SkillPackage decodeImport(Uint8List bytes, String filename) {
    if (bytes.length > maxPackageBytes) {
      throw const SkillFormatException(
        SkillFormatError.packageTooLarge,
        '技能包不能超过 32 MiB。',
      );
    }
    if (p.extension(filename).toLowerCase() == '.md') {
      if (bytes.length > maxInstructionBytes) {
        throw const SkillFormatException(
          SkillFormatError.instructionsTooLarge,
          'SKILL.md 不能超过 256 KiB。',
        );
      }
      final skill = Skill.fromSkillMd(
        utf8.decode(bytes),
        defaultId: p.basenameWithoutExtension(filename).toLowerCase() == 'skill'
            ? 'imported-skill'
            : p.basenameWithoutExtension(filename),
      );
      return SkillPackage(skill: skill, files: {'SKILL.md': bytes});
    }
    if (!['.zip', '.skill'].contains(p.extension(filename).toLowerCase())) {
      throw const SkillFormatException(
        SkillFormatError.fileType,
        '请选择 .zip、.skill 或 .md 文件。',
      );
    }
    try {
      // 直接检查中央目录，避免 ZipDecoder 自动解压符号链接与合并同名项。
      final directory = ZipDirectory.read(InputStream(bytes));
      if (directory.fileHeaders.length > maxFiles * 2) {
        throw const SkillFormatException(
          SkillFormatError.tooManyEntries,
          '技能包条目过多。',
        );
      }
      final paths = <String>{};
      final files = <String, Uint8List>{};
      var total = 0;
      for (final header in directory.fileHeaders) {
        final name = header.filename;
        final isDirectory = name.endsWith('/');
        final path = validatePath(
          isDirectory ? name.substring(0, name.length - 1) : name,
        );
        final mode = (header.externalFileAttributes ?? 0) >> 16;
        final type = mode & 0xf000;
        if (type != 0 && type != 0x8000 && type != 0x4000) {
          throw const SkillFormatException(
            SkillFormatError.specialFile,
            '技能包不允许链接或特殊文件。',
          );
        }
        if (!paths.add(path.toLowerCase())) {
          throw SkillFormatException(
            SkillFormatError.duplicatePath,
            '技能包存在重复路径：$path',
            detail: path,
          );
        }
        if (isDirectory || type == 0x4000) continue;
        if (_ignoredPath(path)) continue;
        final size = header.uncompressedSize ?? -1;
        if (size < 0 ||
            size > maxFileBytes ||
            (total += size) > maxPackageBytes ||
            files.length >= maxFiles) {
          throw const SkillFormatException(
            SkillFormatError.sizeLimit,
            '技能包超出限制：单文件 8 MiB、总量 32 MiB、512 个文件。',
          );
        }
        final file = header.file;
        if (file == null || (file.flags & 1) != 0) {
          throw const SkillFormatException(
            SkillFormatError.encrypted,
            '不支持加密或损坏的技能包。',
          );
        }
        final compressed = file.rawContent?.toUint8List();
        if (compressed == null) {
          throw const SkillFormatException(
            SkillFormatError.missingData,
            '技能包文件数据缺失。',
          );
        }
        final Uint8List content;
        switch (file.compressionMethod) {
          case ZipFile.zipCompressionStore:
            content = Uint8List.fromList(compressed);
          case ZipFile.zipCompressionDeflate:
            // 按输出块限制实际大小，不信任 ZIP 声称的未压缩长度。
            final output = _LimitedByteSink(size);
            final sink = io.ZLibDecoder(
              raw: true,
            ).startChunkedConversion(output);
            for (var start = 0; start < compressed.length; start += 4096) {
              sink.add(
                compressed.sublist(
                  start,
                  (start + 4096).clamp(0, compressed.length),
                ),
              );
            }
            sink.close();
            content = output.bytes.takeBytes();
          default:
            throw const SkillFormatException(
              SkillFormatError.compression,
              '技能包仅支持 ZIP Store / Deflate 压缩。',
            );
        }
        if (content.length != size || getCrc32(content) != header.crc32) {
          throw const SkillFormatException(
            SkillFormatError.checksum,
            '技能包长度或 CRC 校验失败。',
          );
        }
        files[path] = content;
      }
      return _fromFiles(files);
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const SkillFormatException(
        SkillFormatError.invalidZip,
        '无法读取 ZIP 技能包，请检查文件是否完整。',
      );
    }
  }

  Future<SkillPackage> readImportDirectory(String path) async {
    if (await FileSystemEntity.type(path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const SkillFormatException(
        SkillFormatError.directory,
        '请选择普通技能文件夹，不能选择链接。',
      );
    }
    final root = Directory(await Directory(path).resolveSymbolicLinks());
    final files = <String, Uint8List>{};
    final directories = <Directory>[root];
    final seen = <String>{};
    var total = 0;
    var count = 0;
    while (directories.isNotEmpty) {
      final directory = directories.removeLast();
      await for (final entity in directory.list(followLinks: false)) {
        if (++count > maxFiles * 2) {
          throw const SkillFormatException(
            SkillFormatError.tooManyEntries,
            '技能包条目过多。',
          );
        }
        final relative = p
            .relative(entity.path, from: root.path)
            .split(p.separator)
            .join('/');
        final key = validatePath(relative);
        if (_ignoredPath(key)) continue;
        if (!seen.add(key.toLowerCase())) {
          throw SkillFormatException(
            SkillFormatError.duplicatePath,
            '技能包存在重复路径：$key',
            detail: key,
          );
        }
        if (entity is Link) {
          throw const SkillFormatException(
            SkillFormatError.linkFile,
            '技能包不允许链接文件。',
          );
        }
        final resolved = await entity.resolveSymbolicLinks();
        if (!p.isWithin(root.path, resolved)) {
          throw const SkillFormatException(
            SkillFormatError.pathEscape,
            '技能包路径越界。',
          );
        }
        if (entity is Directory) {
          directories.add(entity);
        } else if (entity is File) {
          final bytes = await _readBounded(entity, maxFileBytes);
          total += bytes.length;
          if (total > maxPackageBytes || files.length >= maxFiles) {
            throw const SkillFormatException(
              SkillFormatError.packageLimit,
              '技能包不能超过 32 MiB 或 512 个文件。',
            );
          }
          files[key] = bytes;
        } else {
          throw const SkillFormatException(
            SkillFormatError.specialEntry,
            '技能包不允许特殊文件。',
          );
        }
      }
    }
    return _fromFiles(files);
  }

  static bool _ignoredPath(String path) => path
      .split('/')
      .any((part) => ['.git', '__MACOSX', '.DS_Store'].contains(part));

  static SkillPackage _fromFiles(Map<String, Uint8List> files) {
    final entries = files.keys
        .where((key) => p.posix.basename(key) == 'SKILL.md')
        .toList();
    if (entries.length != 1) {
      throw const SkillFormatException(
        SkillFormatError.oneEntry,
        '请选择包含一个 SKILL.md 的技能目录或压缩包；多个技能请分别导入。',
      );
    }
    final entry = entries.single;
    final bytes = files[entry]!;
    if (bytes.length > maxInstructionBytes) {
      throw const SkillFormatException(
        SkillFormatError.instructionsTooLarge,
        'SKILL.md 不能超过 256 KiB。',
      );
    }
    final skill = Skill.fromSkillMd(utf8.decode(bytes), defaultId: '');
    validateSkill(skill);
    final prefix = entry.substring(0, entry.length - 'SKILL.md'.length);
    final selected = <String, Uint8List>{
      for (final item in files.entries)
        if (item.key.startsWith(prefix))
          item.key.substring(prefix.length): item.value,
    };
    _validateFileTree(selected);
    return SkillPackage(
      skill: skill.copyWith(resourcePaths: _resourcePaths(selected)),
      files: selected,
    );
  }

  static void validateSkill(Skill skill) {
    if (!skillIdPattern.hasMatch(skill.id)) {
      throw const SkillFormatException(
        SkillFormatError.invalidId,
        '技能标识应为 1–64 位小写字母、数字与连字符，不能以连字符开头或结尾。',
      );
    }
    if (skill.description.trim().isEmpty || skill.description.length > 1024) {
      throw const SkillFormatException(
        SkillFormatError.description,
        '标准技能 description 必须为 1–1024 个字符。',
      );
    }
  }

  static List<String> _resourcePaths(Map<String, Uint8List> files) =>
      files.keys.where((name) => name != 'SKILL.md').toList()..sort();

  static void _validateFileTree(Map<String, Uint8List> files) {
    var total = 0;
    final names = <String>{};
    for (final entry in files.entries) {
      final path = validatePath(entry.key).toLowerCase();
      if (!names.add(path)) {
        throw SkillFormatException(
          SkillFormatError.duplicateFile,
          '重复的技能文件：${entry.key}',
          detail: entry.key,
        );
      }
      if (entry.value.length > maxFileBytes ||
          (total += entry.value.length) > maxPackageBytes ||
          files.length > maxFiles) {
        throw const SkillFormatException(
          SkillFormatError.fileLimit,
          '技能包超出文件大小或数量限制。',
        );
      }
    }
    for (final path in names) {
      var parent = p.posix.dirname(path);
      while (parent != '.') {
        if (names.contains(parent)) {
          throw const SkillFormatException(
            SkillFormatError.treeConflict,
            '技能包文件和目录路径冲突。',
          );
        }
        parent = p.posix.dirname(parent);
      }
    }
  }

  /// 使用跨平台保守规则，拒绝 ../、绝对路径、Windows ADS/设备名及大小写别名。
  static String validatePath(String path) {
    if (path.isEmpty ||
        path.contains('\\') ||
        path.startsWith('/') ||
        utf8.encode(path).length > 240) {
      throw const SkillFormatException(
        SkillFormatError.relativePath,
        '无效的技能包相对路径。',
      );
    }
    final parts = path.split('/');
    if (parts.length > 12) {
      throw const SkillFormatException(
        SkillFormatError.pathDepth,
        '技能包目录层级过深。',
      );
    }
    for (final part in parts) {
      if (part.isEmpty ||
          part == '.' ||
          part == '..' ||
          part.endsWith('.') ||
          part.endsWith(' ') ||
          RegExp(r'[\x00-\x1f\x7f<>:"|?*]').hasMatch(part) ||
          RegExp(
            r'^(con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\.|$)',
            caseSensitive: false,
          ).hasMatch(part)) {
        throw SkillFormatException(
          SkillFormatError.unsafePath,
          '不安全的技能包路径：$path',
          detail: path,
        );
      }
    }
    return path;
  }

  Future<Skill> install(SkillPackage package, Skill edited) async {
    validateSkill(edited);
    final files = {
      ...package.files,
      'SKILL.md': utf8.encode(edited.toSkillMd()),
    };
    final normalized = files.map(
      (key, bytes) => MapEntry(key, Uint8List.fromList(bytes)),
    );
    _validateFileTree(normalized);
    if (normalized['SKILL.md']!.length > maxInstructionBytes) {
      throw const SkillFormatException(
        SkillFormatError.instructionsTooLarge,
        'SKILL.md 不能超过 256 KiB。',
      );
    }
    final root = await _rootDirectory();
    await root.create(recursive: true);
    // createTemp 原子分配目录，无覆盖旧包或用户源文件的可能。
    final directory = await root.createTemp('pkg_');
    try {
      for (final entry in normalized.entries) {
        final file = File(p.joinAll([directory.path, ...entry.key.split('/')]));
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.value, flush: true);
      }
      return edited.copyWith(
        isBuiltin: false,
        packageId: p.basename(directory.path),
        resourcePaths: List.unmodifiable(_resourcePaths(normalized)),
      );
    } catch (_) {
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<Directory> _packageDirectory(String id) async {
    if (!RegExp(r'^pkg_[a-zA-Z0-9]+$').hasMatch(id)) {
      throw const SkillFormatException(
        SkillFormatError.storageId,
        '无效的技能存储标识。',
      );
    }
    final root = await _rootDirectory();
    final directory = Directory(p.join(root.path, id));
    if (await FileSystemEntity.type(directory.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const SkillFormatException(
        SkillFormatError.missingPackage,
        '技能包文件缺失，请重新导入。',
      );
    }
    if (!p.isWithin(
      await root.resolveSymbolicLinks(),
      await directory.resolveSymbolicLinks(),
    )) {
      throw const SkillFormatException(SkillFormatError.pathEscape, '技能包路径越界。');
    }
    return directory;
  }

  Future<Uint8List> readResource(Skill skill, String path) async {
    validatePath(path);
    if (path == 'SKILL.md') return utf8.encode(skill.toSkillMd());
    if (skill.packageId == null || !skill.resourcePaths.contains(path)) {
      throw const SkillFormatException(
        SkillFormatError.missingResource,
        '未找到该技能包内的资源。',
      );
    }
    final directory = await _packageDirectory(skill.packageId!);
    var target = directory.path;
    for (final part in path.split('/')) {
      target = p.join(target, part);
      if (await FileSystemEntity.type(target, followLinks: false) ==
          FileSystemEntityType.link) {
        throw const SkillFormatException(
          SkillFormatError.readLink,
          '不能读取技能包内的链接。',
        );
      }
    }
    final file = File(target);
    if (!p.isWithin(
      await directory.resolveSymbolicLinks(),
      await file.resolveSymbolicLinks(),
    )) {
      throw const SkillFormatException(
        SkillFormatError.resourceEscape,
        '技能资源路径越界。',
      );
    }
    return _readBounded(file, maxFileBytes);
  }

  Future<Uint8List> exportPackage(Skill skill) async {
    final files = <String, Uint8List>{
      'SKILL.md': utf8.encode(skill.toSkillMd()),
    };
    for (final path in skill.resourcePaths) {
      files[path] = await readResource(skill, path);
    }
    _validateFileTree(files);
    // 旧版自由命名技能也能导出；安全目录名只影响容器，不改写技能 ID。
    final folder = skillIdPattern.hasMatch(skill.id) ? skill.id : 'skill';
    return Isolate.run(() {
      final archive = Archive();
      for (final entry in files.entries) {
        archive.addFile(
          ArchiveFile('$folder/${entry.key}', entry.value.length, entry.value),
        );
      }
      return Uint8List.fromList(ZipEncoder().encode(archive)!);
    });
  }

  /// 路径来自系统保存对话框，覆盖确认由对话框负责；移动端由插件写 bytes。
  Future<void> writeExportFile(String path, Uint8List bytes) async {
    await File(path).writeAsBytes(bytes, flush: true);
  }

  Future<void> deletePackage(Skill skill) async {
    if (skill.packageId == null) return;
    final directory = await _packageDirectory(skill.packageId!);
    await directory.delete(recursive: true);
  }

  static Future<Uint8List> _readBounded(File file, int limit) async {
    if (await file.length() > limit) {
      throw const SkillFormatException(
        SkillFormatError.readSize,
        '文件超过技能包大小限制。',
      );
    }
    final sink = _LimitedByteSink(limit);
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    return sink.bytes.takeBytes();
  }
}

class _LimitedByteSink implements Sink<List<int>> {
  final int limit;
  final bytes = BytesBuilder(copy: false);
  _LimitedByteSink(this.limit);

  @override
  void add(List<int> data) {
    if (bytes.length + data.length > limit) {
      throw const SkillFormatException(
        SkillFormatError.unpackedSize,
        '解压文件超过大小限制。',
      );
    }
    bytes.add(data);
  }

  @override
  void close() {}
}
