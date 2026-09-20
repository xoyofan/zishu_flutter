import 'package:flutter/material.dart';

import 'design_tokens.dart';

/// 主题扩展 tokens:深浅主题各一份实例,Widget 统一从 context 读,
/// 禁止在 Widget 内散落裸色值。断点/动效等非主题量仍在 design_tokens.dart。
class ZishuTokens extends ThemeExtension<ZishuTokens> {
  const ZishuTokens({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.surfaceRaised,
    required this.brand,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
    required this.border,
    required this.liveBadge,
    required this.error,
    required this.success,
    required this.coverScrim,
    required this.coverScrimText,
    required this.promoBadge,
    required this.statAudience,
    required this.statVip,
    required this.statSvip,
    required this.playFollowBg,
    required this.playFollowBgHover,
    required this.playFollowBgActive,
    required this.playFollowBorder,
    required this.playFollowText,
    required this.playFollowTextActive,
    required this.playSuperBg,
    required this.playSuperBgHover,
    required this.playSuperBgActive,
    required this.playSuperBorder,
    required this.playSuperText,
    required this.playSuperTextActive,
  });

  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color surfaceRaised;
  final Color brand;

  /// 通用控件强调色(紫霄品牌紫):slider 填充/滑块、开关、复选、选中态、
  /// 进度与 CTA 等 Material 控件 accent 统一取此处;经 `app_theme.dart` 接入
  /// `colorScheme.primary/secondary`。
  ///
  /// 与 [brand](金黄,收藏星/hover 等对齐 SFVideoLive web 的功能性颜色)刻意
  /// 分开:用户口径(2026-09-20)控件强调一律品牌紫,金色不再充当控件色。
  final Color accent;

  final Color textPrimary;
  final Color textSecondary;
  final Color border;
  final Color liveBadge;
  final Color error;
  final Color success;

  /// 封面角标暗底(热度/平台等压在封面图上的底色)——
  /// 对齐 SFVideoLive `CoverBadges.vue` 的 `rgba(0,0,0,.72)`。
  final Color coverScrim;

  /// 压在上述暗底上的文字色:两种主题都必须是白,
  /// 不能复用 textPrimary(浅色主题下它是深色,压在黑底上不可读)。
  final Color coverScrimText;

  /// 促销/画质角标底色——对齐 `.room-card__badge--promo`
  /// 的 `rgba(180, 83, 9, .92)`(琥珀)。
  final Color promoBadge;

  /// 侧栏统计文字:观众数(蓝)/VIP(橙)/SVIP(紫)。
  ///
  /// 语义色在深浅底上需要不同明度才可读,故随主题切换(而非写死一套)。
  final Color statAudience;
  final Color statVip;
  final Color statSvip;

  /// 播放页侧栏「关注」按钮(红系 chip):常态底/hover 底/已关注底/描边/文字/已关注文字。
  ///
  /// 原为 `AppColors.playFollow*` 写死深色系,现随主题切换:深色与旧常量
  /// 逐位同值(深色渲染不变),浅色改用浅底深字的可读配色。
  final Color playFollowBg;
  final Color playFollowBgHover;
  final Color playFollowBgActive;
  final Color playFollowBorder;
  final Color playFollowText;
  final Color playFollowTextActive;

  /// 播放页侧栏「超级关注」按钮(紫系 chip),分组语义同 [playFollowBg] 系列。
  final Color playSuperBg;
  final Color playSuperBgHover;
  final Color playSuperBgActive;
  final Color playSuperBorder;
  final Color playSuperText;
  final Color playSuperTextActive;

  /// SFVideoLive 深色基线(Windows 验收标准)。
  static const dark = ZishuTokens(
    background: Color(0xFF181818),
    surface: Color(0xFF1F1F1F),
    surfaceSoft: Color(0xFF141414),
    surfaceRaised: Color(0xFF2A2A2A),
    brand: Color(0xFFF3D04E),
    // 控件强调紫:Material Deep Purple Accent 200,深底上清晰且与 logo 紫调一致。
    accent: Color(0xFF7C4DFF),
    textPrimary: Color(0xDEFFFFFF),
    textSecondary: Color(0x8CFFFFFF),
    border: Color(0xFF3A3A3A),
    liveBadge: Color(0xFF32C874),
    error: Color(0xFFE55050),
    success: Color(0xFF67C23A),
    coverScrim: Color(0xB8000000),
    coverScrimText: Color(0xFFFFFFFF),
    promoBadge: Color(0xEBB45309),
    statAudience: Color(0xFFB8DCFF),
    statVip: Color(0xFFFFD4A0),
    statSvip: Color(0xFFF0B8FF),
    // 关注/超关 chip:与原 AppColors.playFollow*/playSuper* 逐位同值。
    playFollowBg: Color(0xFF582626),
    playFollowBgHover: Color(0xFF512626),
    playFollowBgActive: Color(0xFF4F2C2C),
    playFollowBorder: Color(0xFF6E4747),
    playFollowText: Color(0xFFFFB8B8),
    playFollowTextActive: Color(0xFFFFE0E0),
    playSuperBg: Color(0xFF442D5B),
    playSuperBgHover: Color(0xFF402C54),
    playSuperBgActive: Color(0xFF413052),
    playSuperBorder: Color(0xFF5C4D6C),
    playSuperText: Color(0xFFC9A0F0),
    playSuperTextActive: Color(0xFFE9D5FF),
  );

  /// 浅色主题(视觉同步,非本轮验收重点)。
  static const light = ZishuTokens(
    background: Color(0xFFF5F5F7),
    surface: Color(0xFFFFFFFF),
    surfaceSoft: Color(0xFFECECEC),
    surfaceRaised: Color(0xFFE0E0E0),
    brand: Color(0xFFC9A227),
    // 控件强调紫:低明度档(Deep Purple 800),浅底上可读。
    accent: Color(0xFF6A1B9A),
    textPrimary: Color(0xE6121212),
    textSecondary: Color(0x99616161),
    border: Color(0xFFD9D9D9),
    liveBadge: Color(0xFF32C874),
    error: Color(0xFFE55050),
    success: Color(0xFF4CA83D),
    coverScrim: Color(0xB8000000),
    coverScrimText: Color(0xFFFFFFFF),
    promoBadge: Color(0xEBB45309),
    // 浅底上取低明度同色系,保证与卡片底色有足够对比。
    statAudience: Color(0xFF1B6CA8),
    statVip: Color(0xFFA8620A),
    statSvip: Color(0xFF8E3AA8),
    // 关注/超关 chip:浅底淡色填充 + 低明度同色系文字(实机确认写死深色系
    // 在浅色下可读,但语义上应随主题;浅色值与深色分套,深色不变)。
    playFollowBg: Color(0xFFFBECEC),
    playFollowBgHover: Color(0xFFF7E1E1),
    playFollowBgActive: Color(0xFFF8E5E5),
    playFollowBorder: Color(0xFFEFC9C9),
    playFollowText: Color(0xFFA83838),
    playFollowTextActive: Color(0xFF8C2424),
    playSuperBg: Color(0xFFF2ECFA),
    playSuperBgHover: Color(0xFFECE2F5),
    playSuperBgActive: Color(0xFFEDE4F4),
    playSuperBorder: Color(0xFFDFD0EF),
    playSuperText: Color(0xFF6F3FA8),
    playSuperTextActive: Color(0xFF592C87),
  );

  @override
  ZishuTokens copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSoft,
    Color? surfaceRaised,
    Color? brand,
    Color? accent,
    Color? textPrimary,
    Color? textSecondary,
    Color? border,
    Color? liveBadge,
    Color? error,
    Color? success,
    Color? coverScrim,
    Color? coverScrimText,
    Color? promoBadge,
    Color? statAudience,
    Color? statVip,
    Color? statSvip,
    Color? playFollowBg,
    Color? playFollowBgHover,
    Color? playFollowBgActive,
    Color? playFollowBorder,
    Color? playFollowText,
    Color? playFollowTextActive,
    Color? playSuperBg,
    Color? playSuperBgHover,
    Color? playSuperBgActive,
    Color? playSuperBorder,
    Color? playSuperText,
    Color? playSuperTextActive,
  }) {
    return ZishuTokens(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      brand: brand ?? this.brand,
      accent: accent ?? this.accent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      border: border ?? this.border,
      liveBadge: liveBadge ?? this.liveBadge,
      error: error ?? this.error,
      success: success ?? this.success,
      coverScrim: coverScrim ?? this.coverScrim,
      coverScrimText: coverScrimText ?? this.coverScrimText,
      promoBadge: promoBadge ?? this.promoBadge,
      statAudience: statAudience ?? this.statAudience,
      statVip: statVip ?? this.statVip,
      statSvip: statSvip ?? this.statSvip,
      playFollowBg: playFollowBg ?? this.playFollowBg,
      playFollowBgHover: playFollowBgHover ?? this.playFollowBgHover,
      playFollowBgActive: playFollowBgActive ?? this.playFollowBgActive,
      playFollowBorder: playFollowBorder ?? this.playFollowBorder,
      playFollowText: playFollowText ?? this.playFollowText,
      playFollowTextActive: playFollowTextActive ?? this.playFollowTextActive,
      playSuperBg: playSuperBg ?? this.playSuperBg,
      playSuperBgHover: playSuperBgHover ?? this.playSuperBgHover,
      playSuperBgActive: playSuperBgActive ?? this.playSuperBgActive,
      playSuperBorder: playSuperBorder ?? this.playSuperBorder,
      playSuperText: playSuperText ?? this.playSuperText,
      playSuperTextActive: playSuperTextActive ?? this.playSuperTextActive,
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
      accent: mix(accent, other.accent),
      textPrimary: mix(textPrimary, other.textPrimary),
      textSecondary: mix(textSecondary, other.textSecondary),
      border: mix(border, other.border),
      liveBadge: mix(liveBadge, other.liveBadge),
      error: mix(error, other.error),
      success: mix(success, other.success),
      coverScrim: mix(coverScrim, other.coverScrim),
      coverScrimText: mix(coverScrimText, other.coverScrimText),
      promoBadge: mix(promoBadge, other.promoBadge),
      statAudience: mix(statAudience, other.statAudience),
      statVip: mix(statVip, other.statVip),
      statSvip: mix(statSvip, other.statSvip),
      playFollowBg: mix(playFollowBg, other.playFollowBg),
      playFollowBgHover: mix(playFollowBgHover, other.playFollowBgHover),
      playFollowBgActive: mix(playFollowBgActive, other.playFollowBgActive),
      playFollowBorder: mix(playFollowBorder, other.playFollowBorder),
      playFollowText: mix(playFollowText, other.playFollowText),
      playFollowTextActive: mix(playFollowTextActive, other.playFollowTextActive),
      playSuperBg: mix(playSuperBg, other.playSuperBg),
      playSuperBgHover: mix(playSuperBgHover, other.playSuperBgHover),
      playSuperBgActive: mix(playSuperBgActive, other.playSuperBgActive),
      playSuperBorder: mix(playSuperBorder, other.playSuperBorder),
      playSuperText: mix(playSuperText, other.playSuperText),
      playSuperTextActive: mix(playSuperTextActive, other.playSuperTextActive),
    );
  }
}

/// `context.tokens.brand` 形式的快捷读取。
extension ZishuTokensContext on BuildContext {
  ZishuTokens get tokens => Theme.of(this).extension<ZishuTokens>() ?? ZishuTokens.dark;
}

/// 排版 × 主题色:`AppTypography` 提供字号/字重/行高,tokens 提供颜色。
///
/// Widget 一律用 `context.textBody` / `context.textCaption` 这类写法,替代
/// 旧的 `AppTypography.body`(其颜色写死为深色基线,浅色主题下不可读)。
/// 深色下取值与旧常量逐位相同(见 ZishuTokens.dark),故深色渲染不变。
extension ZishuTypographyContext on BuildContext {
  TextStyle get textTitle =>
      AppTypography.title.copyWith(color: tokens.textPrimary);

  TextStyle get textBody =>
      AppTypography.body.copyWith(color: tokens.textPrimary);

  TextStyle get textSecondary =>
      AppTypography.bodySecondary.copyWith(color: tokens.textSecondary);

  TextStyle get textCaption =>
      AppTypography.caption.copyWith(color: tokens.textSecondary);
}
