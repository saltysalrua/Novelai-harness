import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/models/nai_account_info.dart';
import 'package:novelai_harness/data/repositories/novelai_repository.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/data/services/notification_history_service.dart';
import 'package:novelai_harness/main.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/ui/features/studio/view_models/studio_view_model.dart';
import 'package:novelai_harness/ui/features/studio/views/studio_view.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAccountRepository extends NovelAiRepository {
  bool shouldFail = false;

  @override
  Future<NaiAccountInfo> fetchAccountInfo({required String apiKey}) async {
    if (shouldFail) {
      throw Exception('connection refused');
    }
    return const NaiAccountInfo(
      tierName: 'Opus',
      tier: 3,
      active: true,
      staminaPercent: 100.0,
      timeUntilNextPercent: 0,
      totalAnlas: 10000,
      fixedAnlas: 10000,
      purchasedAnlas: 0,
      taskPriority: 0,
      unlimitedFree: true,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'NotificationHistoryService persists up to 100 records and supports read/remove/clear',
    () async {
      final tempDir = Directory.systemTemp.createTempSync('notif_history_svc_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      final service = NotificationHistoryService();
      await service.init(baseDir: tempDir.path);

      for (var i = 0; i < 105; i++) {
        service.record(
          message: 'msg $i',
          level: i.isEven ? AppNoticeLevel.error : AppNoticeLevel.warning,
          source: AppNoticeSource.generation,
        );
      }

      expect(service.records, hasLength(100));
      expect(service.records.first.message, 'msg 104');
      expect(service.records.last.message, 'msg 5');
      expect(service.unreadCount, 100);
      await service.flush();

      final reloaded = NotificationHistoryService();
      await reloaded.init(baseDir: tempDir.path);
      expect(reloaded.records, hasLength(100));
      expect(reloaded.records.first.message, 'msg 104');
      expect(reloaded.records.last.message, 'msg 5');
      expect(reloaded.unreadCount, 100);

      expect(reloaded.markAllRead(), isTrue);
      expect(reloaded.unreadCount, 0);
      expect(reloaded.markAllRead(), isFalse);

      final firstId = reloaded.records.first.id;
      expect(reloaded.remove(firstId), isTrue);
      expect(reloaded.records, hasLength(99));

      expect(reloaded.clear(), isTrue);
      expect(reloaded.records, isEmpty);
      await reloaded.flush();
    },
  );

  test(
    'StudioViewModel.refreshAccountInfo(showError: true) clears stale accountInfo and records error',
    () async {
      SharedPreferences.setMockInitialValues({
        'novelai_key': 'test-key',
        'novelai_locale_preference': 'zh',
        'novelai_enable_tag_dictionary_auto_update': false,
        'novelai_enable_image_persistence': false,
        'llm_api_key': '',
      });
      final sessionDir = Directory.systemTemp.createTempSync(
        'notif_history_vm_',
      );
      final repo = _FakeAccountRepository();
      final vm = StudioViewModel(
        repository: repo,
        sessionLogBaseDir: sessionDir.path,
      );
      addTearDown(() async {
        vm.bannerController.clear();
        await vm.flushPendingSaves();
        vm.dispose();
        if (sessionDir.existsSync()) {
          sessionDir.deleteSync(recursive: true);
        }
      });

      await vm.init();
      expect(vm.accountInfo?.tierName, 'Opus');
      expect(vm.notificationHistory, isEmpty);

      repo.shouldFail = true;
      await vm.refreshAccountInfo(showError: true);

      expect(vm.accountInfo, isNull);
      expect(vm.errorMessage, contains('connection refused'));
      expect(vm.notificationHistory, isNotEmpty);
      expect(vm.notificationHistory.first.source, AppNoticeSource.account);
      expect(
        vm.notificationHistory.first.message,
        contains('connection refused'),
      );
      expect(vm.unreadNotificationCount, greaterThanOrEqualTo(1));
    },
  );

  testWidgets(
    'StudioView shows floating banner without shifting layout and NotificationCenterPopover reads & clears history',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'novelai_locale_preference': 'zh',
        'novelai_enable_tag_dictionary_auto_update': false,
        'novelai_enable_image_persistence': false,
        'novelai_key': '',
        'llm_api_key': '',
      });
      AppLocaleController.instance.syncFromConfig(
        const AppConfig(localePreference: AppLocalePreference.zh),
      );
      addTearDown(AppLocaleController.instance.resetForTest);

      await tester.pumpWidget(const NovelAiHarnessApp());
      await tester.pumpAndSettle();

      final vm = StudioView.testViewModelHook;
      expect(vm, isNotNull);
      addTearDown(() => vm!.bannerController.clear());

      final bellFinder = find.byKey(const Key('sidebar_notifications_button'));
      expect(bellFinder, findsOneWidget);
      final beforeRect = tester.getRect(bellFinder);

      vm!.reportError('模拟生图失败: HTTP 500', source: AppNoticeSource.generation);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(
        find.byKey(const Key('studio_floating_banner_stack')),
        findsOneWidget,
      );
      expect(find.text('模拟生图失败: HTTP 500'), findsOneWidget);
      expect(tester.getRect(bellFinder).top, beforeRect.top);
      expect(vm.unreadNotificationCount, 1);

      await tester.tap(bellFinder);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('notification_center_popover')),
        findsOneWidget,
      );
      expect(vm.unreadNotificationCount, 0);

      await tester.tap(
        find.byKey(const Key('notification_center_clear_all')),
      );
      await tester.pumpAndSettle();

      expect(vm.notificationHistory, isEmpty);
      expect(vm.bannerController.items, isEmpty);
    },
  );
}
