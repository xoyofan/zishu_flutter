import 'package:flutter/material.dart';

import '../shared/presentation/design_tokens.dart';
import '../shared/presentation/zishu_tokens.dart';

/// 应用主题:SFVideoLive 深色基线(#181818 + #f3d04e),tokens 走 ThemeExtension。
abstract final class ZishuTheme {
  static ThemeData dark() {
    final base = ThemeData(brightness: Brightness.dark, useMaterial3: true);
    return _decorate(base, ZishuTokens.dark);
  }

  static ThemeData light() {
    final base = ThemeData(brightness: Brightness.light, useMaterial3: true);
    return _decorate(base, ZishuTokens.light);
  }

  static ThemeData _decorate(ThemeData base, ZishuTokens tokens) {
    final dark = base.brightness == Brightness.dark;
    return base.copyWith(
      scaffoldBackgroundColor: tokens.background,
      colorScheme: base.colorScheme.copyWith(
        primary: tokens.brand,
        onPrimary: dark ? Colors.black87 : Colors.white,
        secondary: tokens.brand,
        surface: tokens.surface,
        onSurface: tokens.textPrimary,
        surfaceContainerHighest: tokens.surfaceRaised,
        error: tokens.error,
        outline: tokens.border,
      ),
      dividerColor: tokens.border,
      textTheme: base.textTheme.apply(
        bodyColor: tokens.textPrimary,
        displayColor: tokens.textPrimary,
        fontFamily: AppTypography.family,
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
        indicatorColor: tokens.brand.withValues(alpha: 0.2),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.brand),
      extensions: [tokens],
    );
  }
}
