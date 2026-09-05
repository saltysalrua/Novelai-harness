import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'data/services/config_service.dart';
import 'data/services/tag_dictionary_service.dart';
import 'data/services/window_state_service.dart';
import 'l10n/app_localizations.dart';
import 'ui/core/locale/app_locale_controller.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/core/theme/theme_mode_controller.dart';
import 'ui/core/theme/ui_zoom_controller.dart';
import 'ui/features/studio/views/studio_view.dart';

/// 全局 Navigator Key，供 ViewModel 等无 context 环境弹出对话框 (如 AI 提问)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 异步预热 Danbooru 词库索引 (后台 isolate，零阻塞 UI)
  TagDictionaryService.instance.ensureLoaded();

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    await windowManager.ensureInitialized();

    final configService = ConfigService();
    final windowState = await configService.loadWindowState();

    final bool hasValidPosition =
        windowState.posX != null &&
        windowState.posY != null &&
        windowState.posX! >= -200 &&
        windowState.posY! >= -200;

    final windowOptions = WindowOptions(
      size: Size(windowState.width, windowState.height),
      minimumSize: const Size(960, 600),
      center: !hasValidPosition,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'NovelAI Harness',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (hasValidPosition) {
        await windowManager.setPosition(
          Offset(windowState.posX!, windowState.posY!),
        );
      }
      if (windowState.isMaximized) {
        await windowManager.maximize();
      }
      await windowManager.show();
      await windowManager.focus();
    });

    WindowStateService.instance.initialize();
  }

  // 启动即按持久化配置校正主题模式与 UI 缩放，避免深色用户闪亮屏、
  // 缩放用户首帧尺寸跳动 (配置加载与 StudioViewModel 的 init 各自独立，
  // 这里多解析一次换取首帧即正确)
  final bootConfig = await ConfigService().loadConfig();
  AppThemeModeController.instance.syncFromConfig(bootConfig);
  AppLocaleController.instance.syncFromConfig(bootConfig);
  AppUiZoomController.instance.syncFromConfig(bootConfig);

  runApp(const NovelAiHarnessApp());
}

class NovelAiHarnessApp extends StatelessWidget {
  const NovelAiHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeModeController.instance.mode,
      builder: (context, themeMode, _) {
        // 语言同理：根级局部监听驱动 MaterialApp.locale，切换只重建 Localizations 层。
        // null = 跟随系统，交由平台 locale 解析。
        return ValueListenableBuilder<Locale?>(
          valueListenable: AppLocaleController.instance.locale,
          builder: (context, locale, _) {
            return MaterialApp(
              title: 'NovelAI Harness',
              navigatorKey: navigatorKey,
              locale: locale,
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              // 阶段 3 主题模式实装：跟随设置页「主题模式」选择器与持久化配置；
              // MaterialApp 内建 200ms 主题动画平滑过渡，切换只重建主题层不触发全局重绘。
              themeMode: themeMode,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              debugShowCheckedModeBanner: false,
              // Windows 引擎的 accessibility bridge 在处理节点移除与重排时会原生崩溃
              // (flutter/flutter#175041, #182444)。在 Windows 上禁用 semantics 绕开崩溃。
              // UI 缩放：浏览器式整体缩放 (Ctrl+=/-/0)，布局坐标系缩小后 Transform 放大，
              // 只重建包裹层，不触发业务树重建。
              builder: (context, child) {
                // 不可变局部：闭包必须捕获原始 Navigator 子树，
                // 若捕获可变变量会在赋值后指向自身造成无限嵌套 (栈溢出)
                final Widget navigatorChild = child ?? const SizedBox.shrink();
                Widget content = ValueListenableBuilder<double>(
                  valueListenable: AppUiZoomController.instance.zoom,
                  builder: (context, zoom, _) =>
                      AppUiZoomScope(zoom: zoom, child: navigatorChild),
                );
                if (!kIsWeb &&
                    defaultTargetPlatform == TargetPlatform.windows) {
                  return ExcludeSemantics(child: content);
                }
                return content;
              },
              home: const StudioView(),
            );
          },
        );
      },
    );
  }
}
