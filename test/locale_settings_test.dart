import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:novelai_harness/data/services/config_service.dart';
import 'package:novelai_harness/l10n/app_localizations.dart';
import 'package:novelai_harness/ui/core/locale/app_locale_controller.dart';
import 'package:novelai_harness/ui/features/settings/widgets/general_settings_tab.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AppLocalePreference 解析与存储', () {
    test('未知/缺失存储值一律回退跟随系统 (保持旧行为)', () {
      expect(parseLocalePreference(null), AppLocalePreference.system);
      expect(parseLocalePreference(''), AppLocalePreference.system);
      expect(parseLocalePreference('garbage'), AppLocalePreference.system);
      expect(parseLocalePreference('zh'), AppLocalePreference.zh);
      expect(parseLocalePreference('en'), AppLocalePreference.en);
      expect(parseLocalePreference('system'), AppLocalePreference.system);
    });

    test('枚举 ↔ 存储字符串往返一致', () {
      for (final locale in AppLocalePreference.values) {
        expect(parseLocalePreference(localePreferenceStorage(locale)), locale);
      }
    });

    test('AppConfig 默认出厂为跟随系统', () {
      expect(const AppConfig().localePreference, AppLocalePreference.system);
    });

    test('copyWith 透传 localePreference', () {
      const config = AppConfig();
      expect(
        config
            .copyWith(localePreference: AppLocalePreference.en)
            .localePreference,
        AppLocalePreference.en,
      );
      // 不传时保持原值
      expect(
        config
            .copyWith(localePreference: AppLocalePreference.en)
            .copyWith()
            .localePreference,
        AppLocalePreference.en,
      );
    });
  });

  group('AppLocalePreference 持久化', () {
    test('saveConfig → loadConfig 往返不丢失', () async {
      SharedPreferences.setMockInitialValues({});
      final service = ConfigService();
      await service.saveConfig(
        const AppConfig(localePreference: AppLocalePreference.en),
      );
      final loaded = await service.loadConfig();
      expect(loaded.localePreference, AppLocalePreference.en);
    });

    test('旧版本无 locale 键时回退跟随系统默认', () async {
      // 模拟老用户磁盘状态：只有其它键，没有 novelai_locale_preference
      SharedPreferences.setMockInitialValues({'novelai_opus_free_mode': false});
      final loaded = await ConfigService().loadConfig();
      expect(loaded.localePreference, AppLocalePreference.system);
    });
  });

  group('AppLocaleController', () {
    setUp(() {
      AppLocaleController.instance.resetForTest();
    });

    test('偏好枚举映射到 Locale (system → null 跟随系统)', () {
      expect(
        AppLocaleController.mapPreference(AppLocalePreference.system),
        isNull,
      );
      expect(
        AppLocaleController.mapPreference(AppLocalePreference.zh),
        const Locale('zh'),
      );
      expect(
        AppLocaleController.mapPreference(AppLocalePreference.en),
        const Locale('en'),
      );
    });

    test('syncFromConfig 值变化时才通知监听者', () {
      final controller = AppLocaleController.instance;
      expect(controller.locale.value, isNull);

      var notifications = 0;
      void listener() => notifications++;
      controller.locale.addListener(listener);

      // 值未变化 → 不触发通知
      controller.syncFromConfig(const AppConfig());
      expect(notifications, 0);

      // 值变化 → 恰好一次通知
      controller.syncFromConfig(
        const AppConfig(localePreference: AppLocalePreference.en),
      );
      expect(controller.locale.value, const Locale('en'));
      expect(notifications, 1);

      controller.locale.removeListener(listener);
    });
  });

  group('GeneralSettingsTab 双语试点 (阶段 4A)', () {
    // 页面较长，放大测试表面避免 DropdownButton 菜单超默认视口
    Future<void> pumpTab(
      WidgetTester tester, {
      Locale locale = const Locale('zh'),
      AppConfig config = const AppConfig(),
    }) async {
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final draft = GeneralSettingsDraft(config);
      addTearDown(draft.dispose);
      await tester.pumpWidget(
        MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneralSettingsTab(draft: draft),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('zh locale 渲染中文文案', (tester) async {
      await pumpTab(tester);
      expect(find.text('主题模式'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('保护'), findsOneWidget);
      expect(find.text('语言'), findsOneWidget);
      expect(find.text('本地存储目录'), findsOneWidget);
      expect(find.text('Opus 免点数保护'), findsOneWidget);
    });

    testWidgets('en locale 渲染英文文案 (长英文布局不溢出)', (tester) async {
      await pumpTab(tester, locale: const Locale('en'));
      expect(find.text('Theme Mode'), findsOneWidget);
      expect(find.text('Language'), findsOneWidget);
      expect(find.text('Local Storage Directory'), findsOneWidget);
      expect(find.text('Opus Free-Tier Protection'), findsOneWidget);
      // 通用 Material 组件文案随 locale 切换 (证明 delegates 生效)
    });

    testWidgets('语言下拉切换更新草稿值', (tester) async {
      final draft = GeneralSettingsDraft(const AppConfig());
      addTearDown(draft.dispose);
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('zh'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: SingleChildScrollView(
              child: GeneralSettingsTab(draft: draft),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(draft.localePreference, AppLocalePreference.system);

      // 语言下拉当前显示「跟随系统」，展开并选择 English
      await tester.tap(find.byType(DropdownButton<AppLocalePreference>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('English').last);
      await tester.pumpAndSettle();

      expect(draft.localePreference, AppLocalePreference.en);
    });
  });
}
