import 'package:flutter/material.dart';

/// SFVideoLive 深色视觉基线的 design tokens。
/// Widget 内禁止散落裸色值/裸数字,一律引用此处。
abstract final class AppColors {
  /// 页面默认背景 #181818。
  static const Color background = Color(0xFF181818);

  /// 卡片/浮层等 elevated surface。
  static const Color surface = Color(0xFF1F1F1F);

  /// 更深一层的 soft surface。
  static const Color surfaceSoft = Color(0xFF141414);

  /// hover/强调等更亮一层的 soft surface。
  static const Color surfaceRaised = Color(0xFF2A2A2A);

  /// 主品牌色:金黄。
  static const Color brand = Color(0xFFF3D04E);

  static const Color textPrimary = Color(0xDEFFFFFF); // white 87%
  static const Color textSecondary = Color(0x8CFFFFFF); // white 55%
  static const Color border = Color(0xFF3A3A3A);

  /// 直播中状态绿(对齐 SFVideoLive `--live #32C874`)。
  ///
  /// 注意与播放页「关注」按钮的红系(`--play-follow-*`)区分:直播中是绿色,
  /// 关注按钮才是红色。
  static const Color liveBadge = Color(0xFF32C874);

  static const Color playFollowBg = Color(0xFF582626);
  static const Color playFollowBorder = Color(0xFF6E4747);
  static const Color playFollowText = Color(0xFFFFB8B8);
  static const Color playFollowBgHover = Color(0xFF512626);
  static const Color playFollowBgActive = Color(0xFF4F2C2C);
  static const Color playFollowTextActive = Color(0xFFFFE0E0);

  static const Color playSuperBg = Color(0xFF442D5B);
  static const Color playSuperBorder = Color(0xFF5C4D6C);
  static const Color playSuperText = Color(0xFFC9A0F0);
  static const Color playSuperBgHover = Color(0xFF402C54);
  static const Color playSuperBgActive = Color(0xFF413052);
  static const Color playSuperTextActive = Color(0xFFE9D5FF);

  static const Color playStatAudienceText = Color(0xFFB8DCFF);
  static const Color playStatVipText = Color(0xFFFFD4A0);
  static const Color playStatSvipText = Color(0xFFF0B8FF);

  static const Color error = Color(0xFFF56C6C);
  static const Color success = Color(0xFF67C23A);
}

abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;

  /// 顶部应用导航高度(SFVideoLive 约 44px)。
  static const double topNavHeight = 44;

  /// 底部导航高度(窄屏)。
  static const double bottomNavHeight = 56;

  /// 播放页右侧信息栏宽度(768–1599 档的默认值)。
  static const double playSidePanelWidth = 328;

  /// 播放页侧栏宽度分档,对齐 SFVideoLive `main.css:228-244`。
  ///
  /// | 视口宽 | 侧栏宽 |
  /// |---|---|
  /// | ≤767(并排时,如手机横屏) | 268 |
  /// | 768–1599 | 328 |
  /// | 1600–1919 | 392 |
  /// | ≥1920 | 425 |
  static double playSidePanelWidthFor(double width) {
    if (width < AppBreakpoints.phone) return 268;
    if (width < 1600) return playSidePanelWidth;
    if (width < AppBreakpoints.wide) return 392;
    return 425;
  }

  /// 房间网格列间距,对齐 `RoomGrid.vue:118`(1rem)。
  static const double gridCrossAxisSpacing = 16;

  /// 房间网格行间距,对齐 `RoomGrid.vue:118`(0.85rem ≈ 13.6px)。
  ///
  /// 未取整到 4pt 栅格:复刻优先保证与参考实现行距一致。
  static const double gridMainAxisSpacing = 13.6;
}

abstract final class AppRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;

  /// 胶囊圆角,对齐 SFVideoLive `border-radius: 999px`
  /// (chip / badge / 头像,源码中出现 7 次)。
  static const double pill = 999;

  static final BorderRadius allSm = BorderRadius.circular(sm);
  static final BorderRadius allMd = BorderRadius.circular(md);
  static final BorderRadius allLg = BorderRadius.circular(lg);
  static final BorderRadius allPill = BorderRadius.circular(pill);
}

abstract final class AppTypography {
  static const String family = 'system-ui';

  static const TextStyle title = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static const TextStyle body = TextStyle(
    fontSize: 13,
    height: 1.4,
    color: AppColors.textPrimary,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: 12,
    height: 1.4,
    color: AppColors.textSecondary,
  );

  static const TextStyle caption = TextStyle(
    fontSize: 11,
    height: 1.3,
    color: AppColors.textSecondary,
  );
}

abstract final class AppMotion {
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration normal = Duration(milliseconds: 200);

  static const Curve curve = Curves.easeOutCubic;
}

/// 响应式断点,与 SFVideoLive 布局断点对齐。
abstract final class AppBreakpoints {
  static const double compact = 640;
  static const double phone = 768;
  static const double tablet = 1024;
  static const double desktop = 1366;
  static const double wide = 1920;
}

/// 房间网格的**固定列数**,对齐 SFVideoLive `RoomGrid.vue:120-155`。
///
/// 参考实现用断点媒体查询切列数(非 `auto-fill`):
///
/// | 视口宽 | 列数 |
/// |---|---|
/// | <640 | 2 |
/// | ≥640 | 3 |
/// | ≥768 | 4 |
/// | ≥1024 | 5 |
/// | ≥1536 | 6 |
/// | ≥1920 | 6(`--room-grid-cols-wide`) |
/// | ≥2560 | 7(`--room-grid-cols-wide-extra`) |
abstract final class AppRoomGrid {
  static const double extraWide = 2560;

  static int columnsFor(double width) {
    if (width < AppBreakpoints.compact) return 2;
    if (width < AppBreakpoints.phone) return 3;
    if (width < AppBreakpoints.tablet) return 4;
    if (width < 1536) return 5;
    if (width < AppBreakpoints.wide) return 6;
    if (width < extraWide) return 6;
    return 7;
  }
}

/// 卡片「封面 + 元信息区」中元信息区的高度预算。
///
/// 系统大字体下文字行高线性增长,固定预算会让卡片内 Column 纵向溢出
/// (W11 实测:textScale 1.15 溢出 1dp、1.3 溢出 5.5dp)。这里按字体缩放
/// 同步放大预算,让卡片在网格中变高,而不是把文字挤出可视区。
double metaHeightFor(double base, BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  return base * (1 + (scale - 1.0) * 0.8);
}
