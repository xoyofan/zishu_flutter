import 'package:flutter/material.dart';

/// SFVideoLive 深色视觉基线的 design tokens。
/// Widget 内禁止散落裸色值/裸数字,一律引用此处。
/// on-video(叠在视频画面上的控件)恒定暗色语义,移植自 pure_live
/// `shared/presentation/design_tokens.dart` 的 AppOnVideo:这类控件永远
/// 压在深色 scrim/暗底上,颜色不随应用主题翻转。
abstract final class AppOnVideo {
  /// 控制条底部渐变 scrim 的终色(黑 72%)。
  static const Color scrim = Color(0xB8000000);

  /// 顶部房间条实底(纯黑)。
  static const Color bar = Color(0xFF000000);

  /// on-video 主文字/图标(白 87%)。
  static const Color text = Color(0xDEFFFFFF);

  /// on-video 次级文字/图标(白 55%)。
  static const Color textMuted = Color(0x8CFFFFFF);
}

abstract final class AppColors {
  /// 页面默认背景 #181818。
  static const Color background = Color(0xFF181818);

  /// 卡片/浮层等 elevated surface。
  static const Color surface = Color(0xFF1F1F1F);

  /// 更深一层的 soft surface。
  static const Color surfaceSoft = Color(0xFF141414);

  /// hover/强调等更亮一层的 soft surface。
  static const Color surfaceRaised = Color(0xFF2A2A2A);

  // 主品牌金黄已并入主题 token:控件强调见 ZishuTokens.accent(品牌紫),
  // 收藏星等 web 对齐功能色见 ZishuTokens.brand。

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

  /// 错误态红,对齐 SFVideoLive web `styles/theme.css:9`(`--danger: #e55050`)。
  ///
  /// 与主题 token(`zishu_tokens.dart` 的 `error`,同为 #E55050)保持同值 ——
  /// 历史上这里是 Element Plus 默认的 `#F56C6C`,已按真源修正。
  static const Color error = Color(0xFFE55050);

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

/// 字号/行高/字重基线。
///
/// **不含颜色**:文字颜色统一由主题 tokens 提供(`context.textTitle` /
/// `context.textCaption` 等,见 zishu_tokens.dart)。写死颜色会让浅色主题下
/// 出现白底白字 —— 深色基线色 `AppColors.textPrimary` 只是恰好与
/// `ZishuTokens.dark` 同值。
abstract final class AppTypography {
  /// 默认字体:微软雅黑(Windows 产品基线)。
  ///
  /// 参考实现是 Web,字体由浏览器/system-ui 决定;桌面端要中文排版稳定,
  /// 显式指定「微软雅黑」而非 `system-ui`。非 Windows 平台由
  /// [familyFallback] 依次回退(苹方 / Noto CJK / Segoe UI)。
  static const String family = 'Microsoft YaHei';

  /// 字体回退链:本机没有微软雅黑时按序回退,避免落到无中文的字体上。
  static const List<String> familyFallback = [
    'Microsoft YaHei UI',
    'PingFang SC',
    'Noto Sans CJK SC',
    'Source Han Sans SC',
    'Segoe UI',
  ];

  static const TextStyle title = TextStyle(
    fontSize: 16,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(fontSize: 13, height: 1.4);

  static const TextStyle bodySecondary = TextStyle(fontSize: 12, height: 1.4);

  static const TextStyle caption = TextStyle(fontSize: 11, height: 1.3);

  /// 未接入主题时的兜底色(仅在拿不到 BuildContext 的极少数场景使用)。
  static const Color fallbackPrimary = AppColors.textPrimary;
  static const Color fallbackSecondary = AppColors.textSecondary;
}

/// 动效基线,对齐 SFVideoLive web `styles/main.css:74,84,85` 的
/// `--fluent-duration-*` / `--fluent-easing`。
///
/// 改动前请确认 web 真源仍为 150ms / 250ms /
/// `cubic-bezier(0.16, 1, 0.3, 1)`;`test/shared/design_tokens_test.dart`
/// 有对应契约断言。
abstract final class AppMotion {
  /// `--fluent-duration-fast`(150ms):hover、颜色/边框过渡等微交互。
  static const Duration fast = Duration(milliseconds: 150);

  /// `--fluent-duration-normal`(250ms):展开/收起、淡入等结构性动效。
  static const Duration normal = Duration(milliseconds: 250);

  /// `--fluent-easing: cubic-bezier(0.16, 1, 0.3, 1)`。
  ///
  /// 注意**不是** `Curves.easeOutCubic`(那是 `Cubic(0.215, 0.61, 0.355, 1)`),
  /// 两者手感不同;这里显式复刻 web 的四个控制点。
  static const Curve curve = Cubic(0.16, 1, 0.3, 1);
}

/// 响应式断点,与 SFVideoLive 布局断点对齐。
abstract final class AppBreakpoints {
  static const double compact = 640;
  static const double phone = 768;
  static const double tablet = 1024;
  static const double desktop = 1366;
  static const double wide = 1920;
}

/// 左侧目录抽屉(DirectoryDrawer)尺寸,对齐 SFVideoLive
/// `DirectoryDrawer.vue` 的 CSS 变量与布局值(1rem = 16px)。
///
/// 未取整到 4pt 栅格:与参考实现逐像素复刻优先。
abstract final class AppDirectoryDrawer {
  /// 展开态宽度(`--directory-drawer-width: 220px`)。
  static const double width = 220;

  /// 收起态宽度(`--directory-rail-width: 52px`)。
  static const double railWidth = 52;

  // ---- 收藏星区(__follow-wrap / __follow-icon) ----

  /// 展开态关注行高度。
  static const double followRowHeight = 64;

  /// 展开态关注头像尺寸与重叠量。
  static const double followAvatarSize = 24;
  static const double followAvatarOverlap = 8;

  /// 星标图标尺寸(`font-size: 2.25rem`,StarFilled)。
  static const double followIconSize = 36;

  /// 星标行左内边距(`padding-left: .35rem`)。
  static const double followPadLeft = 5.6;

  // ---- 平台 tab 网格(__platform-tabs / __platform-tab) ----

  /// 单个 tab 容器边长(`width: 2.4rem` + `aspect-ratio: 1`)。
  static const double platformTabSize = 38.4;

  /// tab 内平台图标尺寸(`PlatformIcon size="md"` = 2rem)。
  static const double platformIconSize = 32;

  /// tab 水平/垂直间距(`gap: .35rem`)。
  static const double platformGap = 5.6;

  /// 平台区上下内边距(`padding: .45rem .35rem`)。
  static const double platformPadV = 7.2;
  static const double platformPadH = 5.6;

  // ---- 分类网格(__body / __cat-grid / __cat-item / __cat-name) ----

  /// 分类区水平内边距(`padding: .45rem .55rem .75rem`)。
  static const double catPadH = 8.8;
  static const double catPadTop = 7.2;
  static const double catPadBottom = 12;

  /// 分类条目行距(`gap: .16rem .22rem`)。
  static const double catGapMain = 2.56;
  static const double catGapCross = 3.52;

  /// 分类条目最小高(`min-height: 1.3rem`)。
  static const double catItemHeight = 20.8;

  /// 分类名称字号(`font-size: .72rem`)。
  static const double catFontSize = 11.5;

  // ---- 开合按钮(__toggle) ----

  /// 细长竖条按钮(`width: .85rem; height: 44px`,仅右侧圆角,贴右缘)。
  static const double toggleWidth = 13.6;
  static const double toggleHeight = 44;

  /// active 平台/分类的金色 12% 底(`--sidebar-chip-active-bg`
  /// = `color-mix(in srgb, var(--primary) 12%, var(--el-fill-color))`)。
  static double activeChipAlpha = 0.12;
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
