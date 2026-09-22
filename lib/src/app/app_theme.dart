import 'package:flutter/material.dart';

import '../features/follow/application/settings_provider.dart';
import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/zishu_tokens.dart';

/// 应用主题:SFVideoLive 深色基线(#181818 + #f3d04e),tokens 走 ThemeExtension。
abstract final class ZishuTheme {
  /// 设置里的主题模式选择 → Flutter [ThemeMode]。
  static ThemeMode modeOf(ThemeModeChoice choice) => switch (choice) {
    ThemeModeChoice.light => ThemeMode.light,
    ThemeModeChoice.dark => ThemeMode.dark,
    ThemeModeChoice.system => ThemeMode.system,
  };

  static ThemeData dark() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return _decorate(base, ZishuTokens.dark);
  }

  static ThemeData light() {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    return _decorate(base, ZishuTokens.light);
  }

  static ThemeData _decorate(ThemeData base, ZishuTokens tokens) {
    return base.copyWith(
      scaffoldBackgroundColor: tokens.background,
      // 通用控件强调色(slider/开关/复选/进度/CTA 等)统一紫霄品牌紫
      // (tokens.accent);brand 金仅保留给收藏星等对齐 web 的功能性颜色。
      colorScheme: base.colorScheme.copyWith(
        primary: tokens.accent,
        onPrimary: AppOnBright.white,
        secondary: tokens.accent,
        surface: tokens.surface,
        onSurface: tokens.textPrimary,
        surfaceContainerHighest: tokens.surfaceRaised,
        error: tokens.error,
        outline: tokens.border,
      ),
      // 面板内滑杆全局规格(用户口径 2026-09-20,取 AppControls):轨道 3 /
      // 圆点 6。各面板不再局部包裹同规格 SliderTheme,只保留真差异
      // (如侧栏弹幕设置的 7px 圆点、控制条主滑杆的宽度布局)。
      sliderTheme: base.sliderTheme.copyWith(
        trackHeight: AppControls.sliderTrackHeight,
        thumbShape: const RoundSliderThumbShape(
          enabledThumbRadius: AppControls.sliderThumbRadius,
        ),
        overlayShape: const RoundSliderOverlayShape(
          overlayRadius: AppControls.sliderThumbRadius + 3,
        ),
      ),
      dividerColor: tokens.border,
      textTheme: base.textTheme.apply(
        bodyColor: tokens.textPrimary,
        displayColor: tokens.textPrimary,
        fontFamily: AppTypography.family,
        // 微软雅黑缺失时按回退链走(苹方/Noto CJK/Segoe UI),
        // 否则落到默认字体后中文可能变成方框。
        fontFamilyFallback: AppTypography.familyFallback,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: tokens.surfaceSoft,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(color: tokens.surface, elevation: 0),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: tokens.surface,
        side: BorderSide(color: tokens.border),
        shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: tokens.surfaceSoft,
        indicatorColor: tokens.accent.withValues(alpha: 0.2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.accent),
      // 注：Material 系控件（TextButton/IconButton/FilledButton/SegmentedButton/
      // Switch/Checkbox…）的 hover/pressed/focus 交互层**不需要在这里收口** ——
      // 上面的 `colorScheme.primary = tokens.accent` 已经让 M3 默认样式从 accent
      // 派生出了同量级的 state layer（轨 C 的审计结论）。
      //
      // 2026-09-21 实测：曾尝试在此加 `segmentedButtonTheme`（只给 overlayColor）
      // 来“统一”，结果**破坏了 SegmentedButton 的 rest 渲染**（follow_style_row
      // golden 2074px 差异——整块底色/描边都变，说明显式 theme style 并非只覆盖
      // 指定字段）。故回退：需要更明显的交互态时，**在调用点**用
      // `AppStateLayer.*Of(...)` 显式化（自绘与 Material 同源取值）。
      extensions: [tokens],
    );
  }
}
