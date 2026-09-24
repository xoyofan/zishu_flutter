/// 设计 token —— 对齐 SFVideoLive web/src/styles/theme.css 与 main.css。
///
/// 所有值来自源 CSS 变量，改这里不改别处。
library;

import 'package:flutter/material.dart';

/// 品牌与语义色（theme.css:4-17）。
abstract final class ZishuColors {
  static const primary = Color(0xFFF3D04E); // --primary
  static const primaryHover = Color(0xFFFFE066); // --primary-hover
  static const primaryOn = Color(0xFF1A1400); // --primary-on（primary 上的文字色）
  static const live = Color(0xFF32C874); // --live（在播徽标）

  /// 各平台品牌色（--platform-*，theme.css:10-17）。
  static const platform = <String, Color>{
    'douyu': Color(0xFFFF6B00),
    'huya': Color(0xFFFFB800),
    'bilibili': Color(0xFF00A1D6),
    'douyin': Color(0xFFFE2C55),
    'soop': Color(0xFF00A8FF),
    'xhs': Color(0xFFFF2442),
    'youtube': Color(0xFFFF0000),
  };

  static Color platformOf(String site) => platform[site] ?? primary;
}

/// 布局尺寸（main.css 布局 token）。
abstract final class ZishuDims {
  static const double navWidth = 70; // --nav-width
  static const double playSidebarWidth =
      328; // --play-sidebar-width（≥1600 加宽另调）
  static const double radiusXs = 4; // --fluent-radius-xs
  static const double radiusSm = 8; // --fluent-radius-sm
  static const double radiusMd = 12; // --fluent-radius-md
}

/// 响应式断点（utils/ui/breakpoints.ts:3-8）。
abstract final class ZishuBreakpoints {
  static const double compact = 640; // BP_COMPACT
  static const double mobile = 768; // BP_MOBILE
  static const double playStack = 1024; // BP_PLAY_STACK（播放页侧栏是否堆叠）
  static const double followTileMax = 1366; // BP_FOLLOW_PAGE_TILE_MAX
  static const double wide = 1920; // BP_WIDE

  static bool isCompact(double width) => width < compact;
  static bool isMobile(double width) => width < mobile;
  static bool stackPlaySidebar(double width) => width < playStack;
}

/// 主题构建：默认暗色（web 默认 mode:"dark"）。
class ZishuTheme {
  static ThemeData dark() => _base(Brightness.dark);

  static ThemeData light() => _base(Brightness.light);

  static ThemeData _base(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: ZishuColors.primary,
      brightness: brightness,
      primary: ZishuColors.primary,
      onPrimary: ZishuColors.primaryOn,
      secondary: ZishuColors.live,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: brightness == Brightness.dark
          ? const Color(0xFF121212)
          : const Color(0xFFF7F7F8),
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZishuDims.radiusSm),
        ),
      ),
    );
  }
}
