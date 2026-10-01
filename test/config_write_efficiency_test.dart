import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/shared_preferences');
  late Map<String, Object> stored;
  late List<String> writes;
  late ConfigService service;
  Completer<void>? blocker;
  var failNextWrite = false;

  setUp(() {
    SharedPreferences.resetStatic();
    stored = {};
    writes = [];
    service = ConfigService();
    blocker = null;
    failNextWrite = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.startsWith('getAll')) return stored;
          final args = call.arguments as Map<Object?, Object?>;
          final key = args['key']! as String;
          writes.add(key);
          await blocker?.future;
          if (failNextWrite) {
            failNextWrite = false;
            return false;
          }
          if (call.method == 'remove') {
            stored.remove(key);
          } else {
            stored[key] = args['value']!;
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    SharedPreferences.resetStatic();
  });

  test('重复保存相同配置零写入，只改一步数仅写一个字段', () async {
    const config = AppConfig();
    await service.saveConfig(config);
    expect(writes.length, greaterThan(50));
    writes.clear();
    await service.saveConfig(config);
    expect(writes, isEmpty);

    await service.saveConfig(config.copyWith(defaultSteps: 19));
    expect(writes, ['flutter.novelai_steps']);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('novelai_steps'), 19);
  });

  test('空强调色删除旧值，已为空时不重复删除', () async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('novelai_accent_seed_color', '#123456');
    await service.saveConfig(const AppConfig());
    expect(prefs.containsKey('novelai_accent_seed_color'), isFalse);
    writes.clear();
    await service.saveConfig(const AppConfig());
    expect(writes, isEmpty);
  });

  test('并行提交配置按调用顺序完成，旧快照不会覆盖新值', () async {
    await service.saveConfig(const AppConfig());
    writes.clear();
    blocker = Completer<void>();
    final first = service.saveConfig(
      const AppConfig().copyWith(defaultSteps: 17, defaultScale: 4),
    );
    final second = service.saveConfig(
      const AppConfig().copyWith(defaultSteps: 21, defaultScale: 6),
    );
    await Future<void>.delayed(Duration.zero);
    expect(writes, hasLength(1));
    blocker!.complete();
    await Future.wait([first, second]);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('novelai_steps'), 21);
    expect(prefs.getDouble('novelai_scale'), 6);
  });

  test('写入失败不会被乐观缓存跳过，再次提交可重试', () async {
    const config = AppConfig();
    await service.saveConfig(config);
    writes.clear();
    failNextWrite = true;
    final changed = config.copyWith(defaultSteps: 19);
    await expectLater(service.saveConfig(changed), throwsStateError);
    // setter 已更新内存缓存，但磁盘模拟仍为旧值。
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getInt('novelai_steps'), 19);
    expect(stored['flutter.novelai_steps'], config.defaultSteps);
    await service.saveConfig(changed);
    expect(stored['flutter.novelai_steps'], 19);
    expect(writes, ['flutter.novelai_steps', 'flutter.novelai_steps']);
  });

  test('重复保存 UI 缩放与窗口状态不重写偏好文件', () async {
    await service.saveUiZoom(1.2);
    await service.saveWindowState(
      width: 1280,
      height: 800,
      posX: 100,
      posY: 200,
    );
    writes.clear();
    await service.saveUiZoom(1.2);
    await service.saveWindowState(
      width: 1280,
      height: 800,
      posX: 100,
      posY: 200,
    );
    await service.saveWindowMaximized(false);
    expect(writes, isEmpty);
  });
}
