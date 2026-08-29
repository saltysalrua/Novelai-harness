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
      theme: AppTheme.darkTheme,
      debugShowCheckedModeBanner: false,
      home: const StudioView(),
    );
  }
}
