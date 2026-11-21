// 跨进程互斥的统一质量门禁入口 (dart run tool/gates.dart)
//
// 背景：多 Agent / 多 IDE 会话共用同一 worktree 时，两个全量 `flutter test`
// 并发执行会竞态共享 `.dart_tool/flutter_build` 内核产物并触发 Windows 文件锁
// 报错。本脚本用 [File.createSync] 的 `exclusive: true` (POSIX O_EXCL /
// Windows CREATE_NEW) 实现跨进程互斥锁，把所有门禁执行天然串行化——
// 即使两个 Agent 同时调用，后者也会自动排队等待，而非互相破坏。
//
// 用法：
//   dart run tool/gates.dart            # 全量门禁：dart analyze + flutter test + cloudflare
//   dart run tool/gates.dart analyze    # 仅静态检查
//   dart run tool/gates.dart test       # 仅全量测试
//   dart run tool/gates.dart test test/app_card_test.dart ...  # 指定测试文件
//   dart run tool/gates.dart cloudflare # 仅运行 Cloudflare Worker 同步服务测试
//
// 退出码：0 = 全绿；1 = 门禁未通过；2 = 等锁超时；130 = 收到中断信号退出。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String kLockFilePath = '.dart_tool/gates.lock';
const String kCloudflareDir = 'cloudflare/prompt-library-sync';
const String kCloudflareTestRelPath = 'test/worker.test.mjs';

/// 锁持有超过该时长且无进展时视为陈旧锁 (进程崩溃残留)，自动抢占清除
const Duration kStaleLockThreshold = Duration(minutes: 20);

/// 等锁总超时：超时放弃并报错，避免无限悬挂
const Duration kLockWaitTimeout = Duration(minutes: 30);

/// 锁文件心跳续期间隔，避免超长测试被误判为陈旧锁
const Duration kLockHeartbeatInterval = Duration(seconds: 30);

final DateTime _scriptStart = DateTime.now();
Process? _activeProcess;

Future<void> main(List<String> args) async {
  final String mode = args.isNotEmpty ? args.first : 'all';

  await _acquireLock();
  final heartbeat = _startLockHeartbeat();
  final signalSubs = <StreamSubscription<ProcessSignal>>[];
  var cleanedUp = false;

  Future<void> cleanup() async {
    if (cleanedUp) return;
    cleanedUp = true;
    heartbeat.cancel();
    for (final sub in signalSubs) {
      await sub.cancel();
    }
    _releaseLock();
  }

  void handleSignal(ProcessSignal signal) {
    stderr.writeln('\n[gates] 收到中断信号 (${signal.name})，正在终止子进程并释放门禁锁…');
    try {
      _activeProcess?.kill();
    } catch (_) {}
    heartbeat.cancel();
    _releaseLock();
    exit(130);
  }

  signalSubs.add(ProcessSignal.sigint.watch().listen(handleSignal));
  if (!Platform.isWindows) {
    signalSubs.add(ProcessSignal.sigterm.watch().listen(handleSignal));
  }

  int exitCode;
  try {
    switch (mode) {
      case 'all':
        final hasCloudflare = File(
          '$kCloudflareDir/$kCloudflareTestRelPath',
        ).existsSync();
        final totalGates = hasCloudflare ? 3 : 2;
        final okAnalyze = await _runGate(
          '门禁 1/$totalGates · dart analyze',
          'dart',
          ['analyze'],
        );
        if (!okAnalyze) {
          exitCode = 1;
          break;
        }
        final okTest = await _runGate(
          '门禁 2/$totalGates · flutter test (全量)',
          'flutter',
          ['test'],
        );
        if (!okTest) {
          exitCode = 1;
          break;
        }
        if (hasCloudflare) {
          final okCf = await _runCloudflareGate(
            '门禁 3/$totalGates · cloudflare worker test',
          );
          exitCode = okCf ? 0 : 1;
        } else {
          exitCode = 0;
        }
      case 'analyze':
        exitCode = await _runGate('门禁 · dart analyze', 'dart', ['analyze'])
            ? 0
            : 1;
      case 'test':
        exitCode =
            await _runGate(
              '门禁 · flutter test${args.length > 1 ? ' (范围: ${args.skip(1).join(' ')})' : ' (全量)'}',
              'flutter',
              ['test', ...args.skip(1)],
            )
            ? 0
            : 1;
      case 'cloudflare':
        exitCode =
            await _runCloudflareGate('门禁 · cloudflare worker test') ? 0 : 1;
      default:
        stderr.writeln('未知模式: $mode');
        stderr.writeln(
          '用法: dart run tool/gates.dart [all|analyze|test [路径...]|cloudflare]',
        );
        exitCode = 1;
    }
  } finally {
    // 注意：exit() 不会执行 finally，因此锁的释放必须在 exit 之前完成
    await cleanup();
  }
  exit(exitCode);
}

Timer _startLockHeartbeat() {
  return Timer.periodic(kLockHeartbeatInterval, (_) {
    try {
      final lockFile = File(kLockFilePath);
      if (lockFile.existsSync()) {
        lockFile.setLastModifiedSync(DateTime.now());
      }
    } catch (_) {}
  });
}

Future<bool> _runCloudflareGate(String title) {
  return _runGate(
    title,
    'node',
    const ['--test', kCloudflareTestRelPath],
    workingDirectory: kCloudflareDir,
  );
}

/// 原子获取跨进程互斥锁
///
/// 用 [File.createSync] 的 `exclusive: true` (POSIX O_EXCL / Windows
/// CREATE_NEW) 做原子独占创建；注意 Directory.createSync 对已存在目录
/// 静默成功，无独占语义，不可用作锁。
Future<void> _acquireLock() async {
  final lockFile = File(kLockFilePath);
  final stopwatch = Stopwatch()..start();
  DateTime lastNotice = DateTime.now();

  while (true) {
    try {
      Directory('.dart_tool').createSync(recursive: true);
      // 原子独占：文件已存在时抛 FileSystemException
      lockFile.createSync(exclusive: true);
      lockFile.writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert({
          'pid': pid,
          'acquiredAt': DateTime.now().toIso8601String(),
          'host': Platform.localHostname,
        }),
      );
      return;
    } on FileSystemException {
      // 已被其他进程持有：先判陈旧 (持有方崩溃残留)，再排队等待
      if (_isStaleLock(lockFile)) {
        stderr.writeln('[gates] 检测到陈旧锁 (持有方疑似已退出)，自动清除重试');
        _tryDelete(lockFile);
        continue;
      }
      if (stopwatch.elapsed > kLockWaitTimeout) {
        stderr.writeln(
          '[gates] 等待门禁锁超时 (${kLockWaitTimeout.inMinutes} 分钟)，放弃执行',
        );
        exit(2);
      }
      final now = DateTime.now();
      if (now.difference(lastNotice) >= const Duration(seconds: 15)) {
        final owner = _readLockOwner();
        stderr.writeln(
          '[gates] 门禁正被其他进程持有 (pid=${owner?['pid']} @ ${owner?['acquiredAt']})，排队等待中… '
          '已等 ${stopwatch.elapsed.inSeconds}s',
        );
        lastNotice = now;
      }
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
  }
}

/// 锁文件超过阈值未更新则视为陈旧 (持有方崩溃残留)
bool _isStaleLock(File lockFile) {
  try {
    if (!lockFile.existsSync()) return false;
    final modified = lockFile.lastModifiedSync();
    return DateTime.now().difference(modified) > kStaleLockThreshold;
  } catch (_) {
    return false;
  }
}

Map<String, dynamic>? _readLockOwner() {
  try {
    return jsonDecode(File(kLockFilePath).readAsStringSync())
        as Map<String, dynamic>;
  } catch (_) {
    return null;
  }
}

void _tryDelete(File f) {
  try {
    f.deleteSync();
  } catch (_) {
    // 删除失败 (另一进程恰好也在抢占) 交给下一轮循环重试
  }
}

void _releaseLock() {
  _tryDelete(File(kLockFilePath));
}

/// 顺序执行一道门禁并实时透传输出；返回是否通过
Future<bool> _runGate(
  String title,
  String executable,
  List<String> args, {
  String? workingDirectory,
}) async {
  final elapsed = Stopwatch()..start();
  stdout.writeln('');
  stdout.writeln('━━━ $title ━━━');

  final process = await Process.start(
    executable,
    args,
    workingDirectory: workingDirectory,
    runInShell: true,
  );
  _activeProcess = process;
  try {
    const decoder = Utf8Codec(allowMalformed: true);
    await Future.wait<void>([
      process.stdout
          .transform(decoder.decoder)
          .transform(const LineSplitter())
          .forEach(stdout.writeln),
      process.stderr
          .transform(decoder.decoder)
          .transform(const LineSplitter())
          .forEach(stderr.writeln),
    ]);
    final code = await process.exitCode;

    final seconds = (elapsed.elapsedMilliseconds / 1000).toStringAsFixed(1);
    final ok = code == 0;
    stdout.writeln(
      ok
          ? '✅ PASS · $title · ${seconds}s · 总耗时 ${DateTime.now().difference(_scriptStart).inSeconds}s'
          : '❌ FAIL · $title · ${seconds}s · 退出码 $code',
    );
    return ok;
  } finally {
    if (identical(_activeProcess, process)) {
      _activeProcess = null;
    }
  }
}
