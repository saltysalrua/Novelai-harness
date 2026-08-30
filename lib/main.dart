import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'data/services/tag_dictionary_service.dart';
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

    const windowOptions = WindowOptions(
      size: Size(1380, 860),
      minimumSize: Size(960, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
      title: 'NovelAI Harness',
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });
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
