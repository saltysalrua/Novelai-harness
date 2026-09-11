import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/novelai_models.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/window_state_service.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  late WindowStateService service;
  late ConfigService config;
  late List<String> events;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    events = [];
    config = ConfigService();
    service = WindowStateService.forTesting(configService: config);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          events.add(call.method);
          return switch (call.method) {
            'isMaximized' || 'isFullScreen' => false,
            'getBounds' => {
              'width': 1280.0,
              'height': 800.0,
              'x': 100.0,
              'y': 200.0,
            },
            _ => null,
          };
        });
  });

  tearDown(() {
    service.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test('系统关闭被拦截，参数落盘前不得销毁窗口，重复请求合并', () async {
    await service.initialize();
    expect(events, contains('setPreventClose'));
    final blocker = Completer<void>();
    service.beforeClose = () async {
      events.add('parameters-start');
      await blocker.future;
      events.add('parameters-saved');
    };
    service.onWindowClose();
    final closing = service.closeWindow();
    expect(identical(closing, service.closeWindow()), isTrue);
    expect(events.where((e) => e == 'parameters-start'), hasLength(1));
    expect(events, isNot(contains('destroy')));
    blocker.complete();
    await closing;
    expect(
      events.indexOf('parameters-saved'),
      lessThan(events.indexOf('destroy')),
    );
    expect(events.where((e) => e == 'destroy'), hasLength(1));
    final window = await config.loadWindowState();
    expect(window.width, 1280);
    expect(window.height, 800);
  });

  test('保存失败保持窗口，后续关闭可以重试', () async {
    service.beforeClose = () async => throw StateError('模拟写盘失败');
    await expectLater(service.closeWindow(), throwsStateError);
    expect(events, isNot(contains('destroy')));
    service.beforeClose = () async => events.add('retry-saved');
    await service.closeWindow();
    expect(events.indexOf('retry-saved'), lessThan(events.indexOf('destroy')));
  });

  test('参数刚修改立即关窗也保存最终分辨率和 CFG', () async {
    final vm = StudioViewModel(configService: config);
    addTearDown(vm.dispose);
    service.beforeClose = vm.flushPendingParameterSave;
    vm.updateParams(vm.params.copyWith(width: 1536, height: 1024, scale: 8.4));
    await service.closeWindow();
    final restored = await ConfigService().loadStudioParameters(
      const NaiGenerationParams(prompt: ''),
    );
    expect(restored.generation.width, 1536);
    expect(restored.generation.height, 1024);
    expect(restored.generation.scale, 8.4);
    expect(events, contains('destroy'));
  });
}
