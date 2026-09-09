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

  /// 直播中状态红。
  static const Color liveBadge = Color(0xFFE64B3D);

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

  /// 播放页右侧信息栏宽度。
  static const double playSidePanelWidth = 328;
}

abstract final class AppRadius {
  static const double sm = 4;
  static const double md = 8;
  static const double lg = 12;

  static final BorderRadius allSm = BorderRadius.circular(sm);
  static final BorderRadius allMd = BorderRadius.circular(md);
  static final BorderRadius allLg = BorderRadius.circular(lg);
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

/// 卡片「封面 + 元信息区」中元信息区的高度预算。
///
/// 系统大字体下文字行高线性增长,固定预算会让卡片内 Column 纵向溢出
/// (W11 实测:textScale 1.15 溢出 1dp、1.3 溢出 5.5dp)。这里按字体缩放
/// 同步放大预算,让卡片在网格中变高,而不是把文字挤出可视区。
double metaHeightFor(double base, BuildContext context) {
  final scale = MediaQuery.textScalerOf(context).scale(1.0);
  return base * (1 + (scale - 1.0) * 0.8);
}
