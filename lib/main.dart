import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'ui/core/theme/app_theme.dart';
import 'ui/features/studio/views/studio_view.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NovelAiHarnessApp());
}

class NovelAiHarnessApp extends StatelessWidget {
  const NovelAiHarnessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NovelAI Harness',
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
