import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'data/services/config_service.dart';
import 'data/services/tag_dictionary_service.dart';
import 'data/services/window_state_service.dart';
import 'l10n/app_localizations.dart';
import 'ui/core/context_l10n.dart';
import 'ui/core/locale/app_locale_controller.dart';
import 'ui/core/theme/app_accent_controller.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/core/theme/theme_mode_controller.dart';
import 'ui/core/theme/ui_zoom_controller.dart';
import 'ui/core/widgets/custom_title_bar.dart';
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
      minimumSize: const Size(
        ConfigService.minWindowWidth,
        ConfigService.minWindowHeight,
      ),
      center: !hasValidPosition,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: defaultTargetPlatform == TargetPlatform.macOS,
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

    await WindowStateService.instance.initialize();
  }

  // 启动即按持久化配置校正主题模式与 UI 缩放，避免深色用户闪亮屏、
  // 缩放用户首帧尺寸跳动 (配置加载与 StudioViewModel 的 init 各自独立，
  // 这里多解析一次换取首帧即正确)。
  // 安卓存储目录探测失败会让 loadConfig 显式抛错：降级到带重试的
  // [_BootFailureApp] 轻量错误页，而不是在 runApp 之前直接崩溃黑屏。
  if (await _syncControllersFromBootConfig()) {
    runApp(const NovelAiHarnessApp());
  } else {
    runApp(const _BootFailureApp());
  }
}

/// 加载启动配置并同步全局控制器：任何异常都降级为 false，由 [main]
/// 展示重试错误页，不让主 isolate 在首帧前直接终止。
Future<bool> _syncControllersFromBootConfig() async {
  try {
    final configService = ConfigService();
    final bootConfig = await configService.loadConfig();
    AppThemeModeController.instance.syncFromConfig(bootConfig);
    AppAccentController.instance.syncFromConfig(bootConfig);
    AppLocaleController.instance.syncFromConfig(bootConfig);
    AppUiZoomController.instance.syncFromConfig(bootConfig);
    return true;
  } catch (error, stackTrace) {
    debugPrint('Boot config load failed: $error\n$stackTrace');
    return false;
  }
}

/// 启动配置加载失败的轻量降级页：展示原因提示并支持原地重试，
/// 重试成功后用正式应用整树替换当前错误页。
/// 预主题阶段，直接用内置中性色，不依赖未同步的主题控制器。
class _BootFailureApp extends StatefulWidget {
  const _BootFailureApp();

  @override
  State<_BootFailureApp> createState() => _BootFailureAppState();
}

class _BootFailureAppState extends State<_BootFailureApp> {
  bool _retrying = false;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    if (await _syncControllersFromBootConfig()) {
      runApp(const NovelAiHarnessApp());
      return;
    }
    if (mounted) setState(() => _retrying = false);
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) {
          final l10n = context.l10n;
          return Scaffold(
            backgroundColor: const Color(0xFF191919),
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.error_outline_rounded,
                    size: 44,
                    color: Color(0xFFE2B714),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.bootLoadFailedTitle,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFE9E9E7),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.bootLoadFailedHint,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF9B9B97),
                    ),
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _retrying ? null : _retry,
                    child: _retrying
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(l10n.bootRetry),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class NovelAiHarnessApp extends StatelessWidget {
  const NovelAiHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppThemeModeController.instance.mode,
      builder: (context, themeMode, _) {
        // 强调色同理：根级局部监听驱动 MaterialApp.theme/darkTheme，
        // MD3 自适应取色切换只重建主题层 (MaterialApp 内建 200ms 平滑切色)
        return ValueListenableBuilder<AccentThemeState>(
          valueListenable: AppAccentController.instance.state,
          builder: (context, accent, _) {
            // 语言同理：根级局部监听驱动 MaterialApp.locale，切换只重建 Localizations 层。
            // null = 跟随系统，交由平台 locale 解析。
            return ValueListenableBuilder<Locale?>(
              valueListenable: AppLocaleController.instance.locale,
              builder: (context, locale, _) {
                return MaterialApp(
                  title: 'NovelAI Harness',
                  navigatorKey: navigatorKey,
                  locale: locale,
                  theme: AppTheme.lightThemeFor(accent),
                  darkTheme: AppTheme.darkThemeFor(accent),
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
                  // Keep the existing Windows accessibility workaround
                  // (#175041, #182444). macOS exposes the application tree;
                  // native bridge limitations and validation are in MACOS.md.
                  // UI 缩放：浏览器式整体缩放 (Ctrl+=/-/0)，布局坐标系缩小后 Transform 放大，
                  // 只重建包裹层，不触发业务树重建。
                  builder: (context, child) {
                    // 不可变局部：闭包必须捕获原始 Navigator 子树，
                    // 若捕获可变变量会在赋值后指向自身造成无限嵌套 (栈溢出)
                    final Widget navigatorChild =
                        child ?? const SizedBox.shrink();
                    Widget content = ValueListenableBuilder<double>(
                      valueListenable: AppUiZoomController.instance.zoom,
                      builder: (context, zoom, _) =>
                          AppUiZoomScope(zoom: zoom, child: navigatorChild),
                    );
                    if (!kIsWeb &&
                        defaultTargetPlatform == TargetPlatform.macOS) {
                      // Native traffic lights use macOS logical points, so
                      // keep window chrome outside application UI scaling.
                      content = Column(
                        children: [
                          const CustomTitleBar(),
                          Expanded(child: content),
                        ],
                      );
                    }
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
      },
    );
  }
}
