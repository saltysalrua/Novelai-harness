import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/window_state_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('ConfigService Window State Persistence Tests', () {
    test('loads default window state when no preferences exist', () async {
      final configService = ConfigService();
      final state = await configService.loadWindowState();

      expect(state.width, 1380.0);
      expect(state.height, 860.0);
      expect(state.posX, isNull);
      expect(state.posY, isNull);
      expect(state.isMaximized, isFalse);
    });

    test('clamps window size if saved size is smaller than minimum limits', () async {
      SharedPreferences.setMockInitialValues({
        'novelai_window_width': 500.0,
        'novelai_window_height': 300.0,
        'novelai_window_pos_x': 100.0,
        'novelai_window_pos_y': 150.0,
        'novelai_window_maximized': false,
      });

      final configService = ConfigService();
      final state = await configService.loadWindowState();

      expect(state.width, 960.0); // Clamped to minWidth 960
      expect(state.height, 600.0); // Clamped to minHeight 600
      expect(state.posX, 100.0);
      expect(state.posY, 150.0);
      expect(state.isMaximized, isFalse);
    });

    test('saves and loads custom window size and position', () async {
      final configService = ConfigService();

      await configService.saveWindowState(
        width: 1440.0,
        height: 900.0,
        posX: 120.0,
        posY: 80.0,
        isMaximized: false,
      );

      final state = await configService.loadWindowState();
      expect(state.width, 1440.0);
      expect(state.height, 900.0);
      expect(state.posX, 120.0);
      expect(state.posY, 80.0);
      expect(state.isMaximized, isFalse);
    });

    test('saves and updates window maximized state independently', () async {
      final configService = ConfigService();

      await configService.saveWindowState(
        width: 1200.0,
        height: 800.0,
        posX: 50.0,
        posY: 60.0,
        isMaximized: false,
      );

      // Maximize window
      await configService.saveWindowMaximized(true);

      var state = await configService.loadWindowState();
      expect(state.width, 1200.0);
      expect(state.height, 800.0);
      expect(state.posX, 50.0);
      expect(state.posY, 60.0);
      expect(state.isMaximized, isTrue);

      // Restore / Unmaximize window
      await configService.saveWindowMaximized(false);

      state = await configService.loadWindowState();
      expect(state.width, 1200.0);
      expect(state.height, 800.0);
      expect(state.isMaximized, isFalse);
    });
  });

  group('WindowStateService Debounce and Lifecycle Tests', () {
    test('schedules debounced save on resize and move events', () {
      final configService = ConfigService();
      final service = WindowStateService.forTesting(configService: configService);

      expect(service.hasPendingSave, isFalse);

      service.onWindowResize();
      expect(service.hasPendingSave, isTrue);

      service.onWindowMove();
      expect(service.hasPendingSave, isTrue);

      service.dispose();
      expect(service.hasPendingSave, isFalse);
    });

    test('cancels pending save and updates maximized state on maximize', () async {
      final configService = ConfigService();
      final service = WindowStateService.forTesting(configService: configService);

      service.onWindowResize();
      expect(service.hasPendingSave, isTrue);

      service.onWindowMaximize();
      expect(service.hasPendingSave, isFalse);
      await service.lastSaveFuture;

      final state = await configService.loadWindowState();
      expect(state.isMaximized, isTrue);

      service.dispose();
    });

    test('updates maximized state to false on unmaximize and restore', () async {
      final configService = ConfigService();
      await configService.saveWindowMaximized(true);

      final service = WindowStateService.forTesting(configService: configService);

      service.onWindowUnmaximize();
      expect(service.hasPendingSave, isTrue);
      await service.lastSaveFuture;

      var state = await configService.loadWindowState();
      expect(state.isMaximized, isFalse);

      await configService.saveWindowMaximized(true);
      service.onWindowRestore();
      expect(service.hasPendingSave, isTrue);
      await service.lastSaveFuture;

      state = await configService.loadWindowState();
      expect(state.isMaximized, isFalse);

      service.dispose();
    });

    test('flushPendingSave executes and resets pending timer', () async {
      final configService = ConfigService();
      final service = WindowStateService.forTesting(configService: configService);

      service.onWindowResized();
      expect(service.hasPendingSave, isTrue);

      await service.flushPendingSave();
      expect(service.hasPendingSave, isFalse);

      service.dispose();
    });
  });
}
