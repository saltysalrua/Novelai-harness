import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:window_manager/window_manager.dart';
import 'data/services/config_service.dart';
import 'data/services/tag_dictionary_service.dart';
import 'data/services/window_state_service.dart';
import 'l10n/app_localizations.dart';
import 'ui/core/theme/app_theme.dart';
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

    final bool hasValidPosition = windowState.posX != null &&
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

  runApp(const NovelAiHarnessApp());
}

class NovelAiHarnessApp extends StatelessWidget {
  const NovelAiHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NovelAI Harness',
      navigatorKey: navigatorKey,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
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
      builder: (context, child) {
        if (!kIsWeb && defaultTargetPlatform == TargetPlatform.windows) {
          return ExcludeSemantics(child: child);
        }
        return child ?? const SizedBox.shrink();
      },
      home: const StudioView(),
    );
  }
}
