import 'package:flutter/material.dart';
import 'app_colors_extension.dart';

/// BuildContext 主题与色彩扩展语法糖
extension ThemeContextX on BuildContext {
  /// 当前主题下的语义调色板
  AppColorsExtension get colors {
    return Theme.of(this).extension<AppColorsExtension>() ??
        (Theme.of(this).brightness == Brightness.dark
            ? AppColorsExtension.dark
            : AppColorsExtension.light);
  }

  /// 当前文字排版规范
  TextTheme get typography => Theme.of(this).textTheme;

  /// 当前是否为深色模式
  bool get isDarkMode => Theme.of(this).brightness == Brightness.dark;
}
