import 'package:flutter/material.dart';

/// 主题扩展 tokens:深浅主题各一份实例,Widget 统一从 context 读,
/// 禁止在 Widget 内散落裸色值。断点/动效等非主题量仍在 design_tokens.dart。
class ZishuTokens extends ThemeExtension<ZishuTokens> {
  const ZishuTokens({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceRaised,
    required this.brand,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.liveBadge,
    required this.error,
    required this.success,
  });

  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceRaised;
  final Color brand;
  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color liveBadge;
  final Color error;
  final Color success;

  /// SFVideoLive 深色基线(Windows 验收标准)。
  static const dark = ZishuTokens(
    background: Color(0xFF181818),
    surface: Color(0xFF1F1F1F),
    surfaceSoft: Color(0xFF141414),
    surfaceRaised: Color(0xFF2A2A2A),
    brand: Color(0xFFF3D04E),
    textPrimary: Color(0xDEFFFFFF),
    textSecondary: Color(0x8CFFFFFF),
    border: Color(0xFF3A3A3A),
    liveBadge: Color(0xFFE64B3D),
    error: Color(0xFFF56C6C),
    success: Color(0xFF67C23A),
  );

  /// 浅色主题(视觉同步,非本轮验收重点)。
  static const light = ZishuTokens(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceSoft: Color(0xFFECECEC),
    surfaceRaised: Color(0xFFE0E0E0),
    brand: Color(0xFFC9A227),
    textPrimary: Color(0xE6121212),
    textSecondary: Color(0x99616161),
    border: Color(0xFFD9D9D9),
    liveBadge: Color(0xFFE64B3D),
    error: Color(0xFFD64541),
    success: Color(0xFF4CA83D),
  );

  @override
  ZishuTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSoft,
    Color? surfaceRaised,
    Color? brand,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? liveBadge,
    Color? error,
    Color? success,
  }) {
    return ZishuTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      brand: brand ?? this.brand,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      liveBadge: liveBadge ?? this.liveBadge,
      error: error ?? this.error,
      success: success ?? this.success,
    );
  }

  @override
  ZishuTokens lerp(ThemeExtension<ZishuTokens>? other, double t) {
    if (other is! ZishuTokens) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t)!;
    return ZishuTokens(
      background: mix(background, other.background),
      surface: mix(surface, other.surface),
      surfaceSoft: mix(surfaceSoft, other.surfaceSoft),
      surfaceRaised: mix(surfaceRaised, other.surfaceRaised),
      brand: mix(brand, other.brand),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      border: mix(border, other.border),
      liveBadge: mix(liveBadge, other.liveBadge),
      error: mix(error, other.error),
      success: mix(success, other.success),
    );
  }
}

/// `context.tokens.brand` 形式的快捷读取。
extension ZishuTokensContext on BuildContext {
  ZishuTokens get tokens => Theme.of(this).extension<ZishuTokens>() ?? ZishuTokens.dark;
}
