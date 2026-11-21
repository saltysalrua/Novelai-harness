import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'data/services/config_service.dart';
import 'data/services/media_store_service.dart';
import 'data/services/tag_dictionary_service.dart';
import 'data/services/window_state_service.dart';
import 'l10n/app_localizations.dart';
import 'ui/core/context_l10n.dart';
import 'ui/core/locale/app_locale_controller.dart';
import 'ui/core/theme/app_accent_controller.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/core/theme/frame_rate_controller.dart';
import 'ui/core/theme/theme_mode_controller.dart';
import 'ui/core/theme/ui_zoom_controller.dart';
import 'ui/core/widgets/custom_title_bar.dart';
import 'ui/features/studio/views/studio_view.dart';

/// 全局 Navigator Key，供 ViewModel 等无 context 环境弹出对话框 (如 AI 提问)
final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  AppWidgetsFlutterBinding.ensureInitialized();

  // 异步预热 Danbooru 词库索引 (后台 isolate，零阻塞 UI)
  unawaited(TagDictionaryService.instance.ensureLoaded());

  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    await windowManager.ensureInitialized();

    final configService = ConfigService.shared;
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
  // 安卓存储目录探测失败会让 loadConfig 显式抛错：降级到带重试与权限引导的
  // [_BootFailureApp] 轻量错误页，而不是在 runApp 之前直接崩溃黑屏。
  final bootError = await _syncControllersFromBootConfig();
  if (bootError == null) {
    runApp(const NovelAiHarnessApp());
  } else {
    runApp(_BootFailureApp(initialError: bootError));
  }
}

/// 加载启动配置并同步全局控制器：返回 null 表示成功，否则返回原始异常对象，
/// 供 [_BootFailureApp] 展示诊断信息、权限引导与降级进入能力。
Future<Object?> _syncControllersFromBootConfig({
  bool tolerateStorageDirectoryFailure = false,
}) async {
  try {
    final bootConfig = tolerateStorageDirectoryFailure
        ? await ConfigService.shared.loadConfigTolerant()
        : await ConfigService.shared.loadConfig();
    AppThemeModeController.instance.syncFromConfig(bootConfig);
    AppAccentController.instance.syncFromConfig(bootConfig);
    AppLocaleController.instance.syncFromConfig(bootConfig);
    AppUiZoomController.instance.syncFromConfig(bootConfig);
    AppFrameRateController.instance.syncFromConfig(bootConfig);
    return null;
  } catch (error, stackTrace) {
    debugPrint('Boot config load failed: $error\n$stackTrace');
    return error;
  }
}

/// 启动配置加载失败的轻量降级页：展示原因提示、Android 存储权限引导、
/// 原地重试以及降级进入工作台能力，避免用户被永久挡在应用门外。
/// 预主题阶段，直接用内置中性色，不依赖未同步的主题控制器。
class _BootFailureApp extends StatefulWidget {
  const _BootFailureApp({this.initialError});

  final Object? initialError;

  @override
  State<_BootFailureApp> createState() => _BootFailureAppState();
}

class _BootFailureAppState extends State<_BootFailureApp> {
  bool _retrying = false;
  bool _requestingPermission = false;
  bool _permissionDenied = false;
  late Object? _error = widget.initialError;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  Future<void> _retry() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    final error = await _syncControllersFromBootConfig();
    if (error == null) {
      runApp(const NovelAiHarnessApp());
      return;
    }
    if (mounted) {
      setState(() {
        _error = error;
        _retrying = false;
      });
    }
  }

  Future<void> _grantPermission() async {
    if (_requestingPermission) return;
    setState(() => _requestingPermission = true);
    final granted = _permissionDenied
        ? await MediaStoreService.instance.openAppSettings().then(
            (_) => MediaStoreService.instance.hasStoragePermission(),
          )
        : await MediaStoreService.instance.requestStoragePermission();
    if (!mounted) return;
    setState(() {
      _requestingPermission = false;
      _permissionDenied = !granted;
    });
    if (granted) {
      await _retry();
    }
  }

  Future<void> _continueAnyway() async {
    if (_retrying) return;
    setState(() => _retrying = true);
    await _syncControllersFromBootConfig(
      tolerateStorageDirectoryFailure: true,
    );
    runApp(const NovelAiHarnessApp());
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
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
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
                        textAlign: TextAlign.center,
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
                      if (_error != null) ...[
                        const SizedBox(height: 14),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF232323),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: const Color(0xFF333333),
                            ),
                          ),
                          child: SelectableText(
                            _error.toString(),
                            maxLines: 4,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFFB5B5B0),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        alignment: WrapAlignment.center,
                        children: [
                          FilledButton(
                            onPressed: _retrying ? null : _retry,
                            child: _retrying
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(l10n.bootRetry),
                          ),
                          if (_isAndroid)
                            OutlinedButton(
                              onPressed: (_retrying || _requestingPermission)
                                  ? null
                                  : _grantPermission,
                              child: Text(
                                _permissionDenied
                                    ? l10n.bootOpenSettings
                                    : l10n.bootGrantPermission,
                              ),
                            ),
                          TextButton(
                            onPressed: _retrying ? null : _continueAnyway,
                            child: Text(l10n.bootContinueAnyway),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
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
