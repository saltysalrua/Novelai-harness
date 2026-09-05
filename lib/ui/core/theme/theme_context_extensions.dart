import 'package:flutter/material.dart';
import '../../../data/models/tag_models.dart';
import 'app_colors_extension.dart';
import 'app_tokens.dart';

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

  /// 当前主题亮度 (供 [AppShadows] 亮暗自适应阴影使用)
  Brightness get themeBrightness => Theme.of(this).brightness;

  /// 卡片微弱浮起阴影 (亮暗自适应)
  List<BoxShadow> get shadowSubtle =>
      AppShadows.subtle(Colors.black, brightness: themeBrightness);

  /// 浮动弹出层阴影 (亮暗自适应)
  List<BoxShadow> get shadowElevated =>
      AppShadows.elevated(Colors.black, brightness: themeBrightness);

  /// 模态弹窗阴影 (亮暗自适应)
  List<BoxShadow> get shadowDialog =>
      AppShadows.dialog(Colors.black, brightness: themeBrightness);

  /// Danbooru 标签分类语义色 (UI 分类色统一事实源)
  ///
  /// 富文本高亮、分类胶囊等一律经此映射取色；general 分类回落正文色。
  Color tagCategoryColor(DanbooruTagCategory category) {
    final palette = colors;
    return switch (category) {
      DanbooruTagCategory.artist => palette.tagArtist,
      DanbooruTagCategory.character => palette.tagCharacter,
      DanbooruTagCategory.copyright => palette.tagCopyright,
      DanbooruTagCategory.meta => palette.tagMeta,
      DanbooruTagCategory.general => palette.textPrimary,
    };
  }
}
