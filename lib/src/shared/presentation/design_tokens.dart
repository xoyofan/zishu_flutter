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

  /// on-video 字幕胶囊底(黑 80%,`Color(0xCC101010)`)。
  ///
  /// 用于压在视频画面上的字幕文字底(字幕句胶囊 / 状态胶囊)。
  /// 与 [scrim]/[bar] 同属"永远暗底"语义,不随主题翻转。
  static const Color captionPillBg = Color(0xCC101010);

  /// on-video 字幕胶囊主文字(纯白),压在 [captionPillBg] 上。
  ///
  /// 与 [text] 刻意不同值:字幕是叠在**暗底**上的纯白正文,取 100% 不透明度
  /// (web 真源即 `color:#fff`),而 [text] 是 87% 的控件文字。
  static const Color captionPillText = Color(0xFFFFFFFF);

  /// on-video 字幕胶囊次级文字(白 80%):状态/提示胶囊。
  static const Color captionPillTextMuted = Color(0xCCFFFFFF);

  /// 暂停态整屏压暗遮罩(黑 35%),点击画面即恢复。
  ///
  /// 与 [scrim] 同属压视频画面的暗底语义,不随主题翻转。
  /// 刻意保留 `static final` + `Colors.black.withValues(alpha: 0.35)`(理由同
  /// `AppElevation.sheet`):换成 `0x59` 字面量在像素上可能有 1/255 的差异。
  static final Color pauseScrim = Colors.black.withValues(alpha: 0.35);
}

/// 亮饱和底(强调色 accent / 品牌金 brand / 平台品牌色)上的前景色。
///
/// 与 [AppOnVideo] 对称:这些底色由**品牌 / 平台**决定,而不是主题决定,
/// 深浅两套主题下取同一套前景,故前景是主题无关常量(深底上的前景才是随主题
/// 切换的 `ZishuTokens.textPrimary` 那类语义)。
///
/// **取值口径(2026-09-21 按实测对比度定,已裁决)**:
/// - accent 底一律用 [white]。此前 logo 字形 / 头像图标用的是黑系(原 `glyph`),
///   实测白前景在两种主题下都更优 —— 深色 accent `#7C4DFF`:白 4.81:1 vs 黑 4.36:1;
///   浅色 accent `#6A1B9A`:白 9.39:1 vs 黑 **2.24:1**(后者属无障碍缺陷)。
/// - 平台色块底用**平台色表按平台定义**的 `PlatformBrand.chipForeground`
///   (web 真源 `--platform-{id}-chip-fg`:虎牙黄底深色、斗鱼橙底白色),不要用本类;
///   只有平台未收录、底色回退到品牌金时才用 [text]。
abstract final class AppOnBright {
  /// 亮底(品牌金 `#F3D04E` 等)上的文字与线条图标(黑 87%,对齐 Material `black87`)。
  ///
  /// 仅用于**未收录平台的品牌金底**兜底:accent 底用 [white],平台色底用
  /// `PlatformBrand.chipForeground`,两者都更精确。
  static const Color text = Color(0xDD000000);

  /// 反白前景(纯白):accent 底上的字形/图标/CTA 文字 / 开关滑块 / `colorScheme.onPrimary`。
  static const Color white = Color(0xFFFFFFFF);
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

  /// 轮播(replay)亮金黄 `#F5DC70`,对齐 SFVideoLive web
  /// `apps/web/src/styles/main.css:133` 的 `--follow-state-replay-accent`。
  ///
  /// 与 `ZishuTokens.brand`(`#F3D04E`,收藏星等 web 功能性金色)同色系但
  /// **更亮一档**,是 web 真源里的独立变量,故单列而不并入 `brand`。
  /// 此前裸在 `features/follow/widgets/follow_common.dart` 的
  /// `kFollowReplayAccent`(该常量已删除)。UI 侧一律用
  /// `context.tokens.brandBright`(随主题切换);在 `lib/src` 里直接引用本常量
  /// 会被 `test/ui/light_theme_test.dart` 的静态守则拦下。
  static const Color brandBright = Color(0xFFF5DC70);

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

  /// 模态遮罩(对话框 / 抽屉的 `barrier`,黑 45%)。
  ///
  /// 深色主题的取值(浅色见 `ZishuTokens.light.barrier`)。
  ///
  /// 用 const ARGB `0x73`(115/255 ≈ 0.451)而不是 `withValues(alpha: 0.45)`:
  /// `ZishuTokens.dark` 是 const 构造,遮罩值必须是编译期常量。两者相差
  /// 1/255,且遮罩不会出现在任何 golden 里。
  static const Color modalBarrier = Color(0x73000000);
}

/// 侧栏聊天行徽章的**跨平台**口径（真源：web `ChatFanBadge.vue` /
/// `ChatUserLevelBadge.vue` 的 `<style scoped>`）。
///
/// web 的徽章尺寸全用 `em`，父级 `.chat-item` 是
/// `font-size: var(--chat-item-font-size, 14px)`，与 Flutter 侧
/// `SettingsState.defaultChatFontSize = 14` 同值 —— 所以本类每个常量都是
/// **web 的 em 值 × 14** 的折算，不是截图估值。改数值前先改 `DESIGN.md` §4.4。
abstract final class AppChatBadge {
  /// 聊天行基准字号（web `--chat-item-font-size` 默认 14）。
  static const double em = 14;

  // ---- 用户等级（`.chat-user-level`）----

  /// 通用高度 `1.48em`（斗鱼被自己的 `1.15em` 覆盖，见
  /// [AppDouyuChatBadge.levelHeight]）。
  static const double levelHeight = 1.48 * em;

  /// 通用最小宽 `1.2em`；斗鱼/B站是 `min-width: auto`，不设下限。
  static const double levelMinWidth = 1.2 * em;

  /// 斗鱼/B站文字字号 `.64em` 与左右内边距 `padding: 0 .26em`。
  static const double levelFontSize = 0.64 * em;
  static const double levelPadX = 0.26 * em;

  /// 其他平台文字字号（`1em`，没吃到 `.64em` 覆盖）与内边距 `.22em`。
  static const double levelFontSizeWide = em;
  static const double levelPadXWide = 0.22 * em;

  // ---- 粉丝牌（`.chat-fan-badge`）----

  /// 通用高 `1.28em`。
  static const double fanHeight = 1.28 * em;

  /// 有底图/渐变时的最小宽 `3.2em`（纯文字牌不设）。
  static const double fanMinWidth = 3.2 * em;

  /// 文字层 `padding: 0 .22em 0 .16em`。
  static const double fanPadRight = 0.22 * em;
  static const double fanPadLeft = 0.16 * em;

  /// 文字层列间距 `gap: .18em`。
  static const double fanGap = 0.18 * em;

  /// 粉丝牌文字 `.9em`。
  static const double fanFontSize = 0.9 * em;

  /// 粉牌文字阴影：web `.chat-fan-badge--has-bg:not(.chat-fan-badge--gradient)
  /// .chat-fan-badge__content { text-shadow: 0 0 2px rgba(0,0,0,.45),
  /// 0 1px 1px rgba(0,0,0,.35) }` —— 所有「文字压在底图上」的牌共用。
  static const List<BoxShadow> fanTextShadow = [
    BoxShadow(color: Color(0x73000000), blurRadius: 2),
    BoxShadow(
      offset: Offset(0, 1),
      blurRadius: 1,
      color: Color(0x59000000),
    ),
  ];

  /// 纯图标徽章（Twitch / YY）`1.15em`。
  static const double iconHeight = 1.15 * em;

  // ---- B 站渐变粉丝牌（`.chat-fan-badge--bilibili-composed`）----

  static const double biliFanHeight = 1.48 * em;
  static const double biliFanMinWidth = 3.5 * em;
  static const double biliFanPadX = 0.5 * em;
  static const double biliFanGap = 0.2 * em;
}

/// 虎牙官网聊天栏徽章的**布局常量**（房间 333003 实测）。
///
/// 颜色/图片一律走官方 CDN（URL 构造在 `live_parser` 的
/// `platforms/huya/huya_chat_badges.dart`，真源为虎牙官网自己的
/// `ConsumeLevelBadge` / `fans-icon` 组件）；尺寸按 `DESIGN.md` §4.4 取
/// web `ChatUserLevelBadge` / `ChatFanBadge` 的 em 折算值。
abstract final class AppHuyaChatBadge {
  // ---- 平台等级（ConsumeLevelBadge）----

  /// 等级数字相对官方图**右下角**的偏移（web `--huya` 的
  /// `.chat-user-level__huya-lv { right: .12em; bottom: .06em }`）。
  ///
  /// ⚠️ 不是"左侧菱形之后居中"：官方图（`consumeLevelBadgeV2`，90×40 @2x）
  /// 左侧菱形已含图形，web 把数字压在右下角，尺寸常量在解析包的
  /// `kHuyaConsumeLevelBadgeWidth/Height`。
  static const double levelTextRight = 0.12 * AppChatBadge.em;
  static const double levelTextBottom = 0.06 * AppChatBadge.em;

  /// 等级数字字号 `0.58em`。
  static const double levelTextFontSize = 0.58 * AppChatBadge.em;

  /// 等级胶囊**裁剪后**宽度（用户口径 2026-09-27：背景太宽，进一步收紧）。
  ///
  /// 官方 45px(90×40@2x) 宽里，左半段是宝石图标、右半段是**纯渐变空底**
  /// （专门留给叠在上面的等级数字）。此前裁到 38px 用户仍反馈太宽；现裁到
  /// 32px：保留「~20px 宝石区 + ~10px 数字位 + 2px 右余量」，正好贴住内容、
  /// 不再拖空渐变长尾。叠字仍由 Flutter 按 `levelTextRight/Bottom` 压在右下角。
  static const double levelWidthCropped = 32;

  /// 胶囊右圆角半径：裁掉右侧 7px 后右圆头已被切掉，用与左端同半径补回。
  static const double levelRadius = 10;

  // ---- 粉丝牌（fans-icon）----

  /// 胶囊高 `1.15em`（web `--huya-fan-badge-h`，比通用粉丝牌矮一档）。
  static const double fanHeight = 1.15 * AppChatBadge.em;

  /// 胶囊最小宽 `3.4em`（composed 分支）。
  static const double fanMinWidth = 3.4 * AppChatBadge.em;

  /// 胶囊圆角 `2px`（web `.chat-fan-badge--huya { border-radius: 2px }`，
  /// 不是通用胶囊的 999）。
  static const double fanRadius = 2;

  /// 内容左右内边距 `padding: 0 .28em 0 .14em`。
  static const double fanPadLeft = 0.14 * AppChatBadge.em;
  static const double fanPadRight = 0.28 * AppChatBadge.em;

  /// 身份图标（守盾 / V）边长 = 粉丝牌盒高。
  ///
  /// 官网 `.fans-icon-sf` 实测 22/26/28 × 20（高即盒高 20）。此前 V 标记按
  /// `AppFontSize.caption`(11)、盾按 `fanHeight`(16.1) 渲染，都比原尺寸小，
  /// 现统一回到盒高。
  static const double fanIdentitySize = 20;

  // ---- 定制粉丝牌（iCustomBadgeFlag==1,NewFloor 组合）----
  // 官网 `dy` CustomBadge shadow DOM 实测(2026-09-27 房间 518518):
  // Floor 80×20(空底框) / Lv 等级图 58×20(左缘贴 0,数字画在图内右段) /
  // 团名 12px 白字 400,左缘 ≈42(避开 Lv 数字区)。

  /// NewFloor 底框宽(官网 Floor 自然尺寸 160×40 @2x → 80×20)。
  static const double customFloorWidth = 80;

  /// Lv 等级数字图盒宽(官网 116×40 @2x → 58×20)。
  static const double customLevelWidth = 58;

  /// 团名左缘(官网 <i> 名字区避开 Lv 数字段,实测左缘 ~42)。
  static const double customNameLeft = 42;

  /// 团名右缘(底框右内侧留 2px)。
  static const double customNameRight = 2;

  /// 团名字号(官网 computed 12px / weight 400,与通用牌 .79em/700 不同)。
  static const double customNameFontSize = 12;

  /// 左侧圆形等级徽记直径：`min-width: 1.05em` 且自身字号 `.67em`
  /// → `1.05 × .67 × 14`。
  static const double fanLevelDisc = 1.05 * 0.67 * AppChatBadge.em;

  /// 徽记内数字字号 `.67em`。
  static const double fanLevelDiscFontSize = 0.67 * AppChatBadge.em;

  /// 徽记底色 `rgba(0,0,0,.22)`（web `.chat-fan-badge__level-disc`）。
  static const Color fanLevelDiscBg = Color(0x38000000);

  /// 徽记到团名的间距（`margin: 0 .14em 0 0`，按徽记自身 `.67em` 折算）。
  static const double fanDiscGap = 0.14 * 0.67 * AppChatBadge.em;

  /// 团名字号 `.79em`。
  static const double fanNameFontSize = 0.79 * AppChatBadge.em;

  /// 粉丝牌 7 档底色（实测胶囊中部像素主色簇；每档给深→浅两端）。
  /// 官方底图含等级圆标与团名留白，此处只取底色，结构由 Widget 表达。
  static const List<Color> fanTier1 = [Color(0xFFF4F5F8), Color(0xFFFFFFFF)];
  static const List<Color> fanTier2 = [Color(0xFF66AEDA), Color(0xFFA9D2EB)];
  static const List<Color> fanTier3 = [Color(0xFF8E98ED), Color(0xFFBFC4F4)];
  static const List<Color> fanTier4 = [Color(0xFFC56E8B), Color(0xFFDEADBD)];
  static const List<Color> fanTier5 = [Color(0xFFD153FD), Color(0xFFF65BFA)];
  static const List<Color> fanTier6 = [Color(0xFF8A43FF), Color(0xFF8A43FF)];
  static const List<Color> fanTier7 = [Color(0xFFFB9401), Color(0xFFFF5D01)];

  /// 粉丝牌底色渐变。实测分档：≤4 / 5–13 / 14–17 / 18–20 / 21–22 / 23–27 / ≥28。
  ///
  /// 第 6 档（23–27）实测只稳定采到深端 `#8A43FF`，浅端未取到足够像素，
  /// 故两端同值（平涂），不臆造浅端。
  static List<Color> fanGradient(int level) {
    if (level <= 4) return fanTier1;
    if (level <= 13) return fanTier2;
    if (level <= 17) return fanTier3;
    if (level <= 20) return fanTier4;
    if (level <= 22) return fanTier5;
    if (level <= 27) return fanTier6;
    return fanTier7;
  }
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

  /// on-video 字幕胶囊圆角(10px)。
  ///
  /// web 真源为 10px,不落在 4/8/12 三档内,故单列具名例外;
  /// **只用于字幕胶囊**,禁止扩散到常规容器(见 `DESIGN.md` §5.4 例外登记)。
  static const double captionPill = 10;

  static final BorderRadius allSm = BorderRadius.circular(sm);
  static final BorderRadius allMd = BorderRadius.circular(md);
  static final BorderRadius allLg = BorderRadius.circular(lg);
  static final BorderRadius allPill = BorderRadius.circular(pill);
  static final BorderRadius allCaptionPill = BorderRadius.circular(captionPill);
}

/// 斗鱼官网聊天栏徽章（房间 252140 实测 + web 参考实现折算）。
///
/// 斗鱼聊天列表是 `<canvas>` 渲染，**没有可解析的 DOM/CSS**，故官方侧数值
/// 由高 DPI 截图逐像素测得（每行取胶囊包围盒 + 左/中/右三处颜色中位）。
/// 结构：粉丝牌是官方 `fans/{lv}.png`（60×19，CDN `staticlive.douyucdn.cn`
/// 可构造）+ 右侧团名。官网聊天行共 4 个 `dy-*` 组件，本类只管可测的几何量；
/// 至尊大钻石（28×28）与贵族的**图标 URL 规则未确证**，UI 降级为等级数字占位
/// （见 `side_panel/chat_badges.dart` 的 `_DouyuSupremeMedal`/`_DouyuNobleChip`）。
///
/// 平台等级（LV 胶囊）在 2026-09-26 由"官网 canvas 实测口径"**改为 web 口径**
/// （`LV{level}` 自适应文字胶囊，见 `DESIGN.md` §4.4）；官网那套
/// 「小徽标 + 数字」的 32×16 全圆端胶囊与其 5 档米金/绿/蓝/靛/紫渐变已随之下线
/// （git 历史可查）。
abstract final class AppDouyuChatBadge {
  // ---- 平台等级（LV 胶囊）----

  /// 胶囊高 `1.15em`（web `.chat-user-level--douyu { height: 1.15em }`
  /// 折算 16.1）。
  static const double levelHeight = 1.15 * AppChatBadge.em;
  /// 胶囊圆角 `2px`（web `.chat-user-level--douyu { border-radius: 2px }`）。
  static const double levelRadius = 2;

  // ---- 粉丝牌 ----

  /// 粉丝牌高（实测 18；官方 PNG 为 60×19）。
  static const double fanHeight = 18;

  /// 官方 PNG 宽（`staticlive.douyucdn.cn/common/douyu/images/fans/{lv}.png`
  /// 与本地 `assets/badges/douyu/fans/{lv}.png` 同款，实测 60×19）。
  static const double fanImageWidth = 60;

  /// 团名左内缩：官方图左侧等级区宽度。
  ///
  /// 取自 web `ChatFanBadge.vue` 的斗鱼分支
  /// `.chat-fan-badge--douyu-official .chat-fan-badge__content`
  /// 的 `padding-left: 1.58em`（按聊天行 14px 折算 = 22.1px，取 22）。
  /// 旧值 24 是手写估值：叠上 12px 字号后「金咕咕」这类 3 字团名需要
  /// 24+12×3+4 = 64px > 60px 徽章，撑出徽章右缘（用户 2026-09-26 报
  /// 「长度还是不够」）。web 的 4.1em 下限正好是 1.58+0.78×3+0.18，
  /// 即按**3 字团名**与徽章同宽设计；字号同步降到 `AppFontSize.caption`。
  static const double fanTextInset = 22;

  /// 粉丝牌无图时的中性深底（与 `AppColors.border` 同值，勿重复定义）。
  static const Color fanFallbackBg = Color(0xFF3A3A3A);

  /// 团名文字阴影（彩色牌上白字必须压暗才可读；与 web 的通用
  /// `.chat-fan-badge__content` text-shadow 同值，故直接复用）。
  static const List<BoxShadow> fanTextShadow = AppChatBadge.fanTextShadow;

  // ---- 粉丝牌官方组合样式（web `dy-fan-medal` lit 组件，2026-09-27 实测）----
  //
  // 官网 2024 起粉丝牌不再是单张烘焙 PNG，而是四层组合：等级桶背景图
  // (`com_bg_{bucket}`，5 级一档，配置 `wconf.douyucdn.cn/resource/common/
  // fans_medal_web_v5.json`) + 房间自定义前缀图(`brid` 匹配) + 等级数字 +
  // 团名文本。以下常量抄自组件 shadow CSS 的 CSS 变量。

  /// 容器宽（`--container-width:68px`；实测渲染 66px，背景图 66×19）。
  static const double medalWidth = 66;

  /// 容器高（`--container-height:19px`）。
  static const double medalHeight = 19;

  /// 左区宽 = 前缀/等级数字区（`--container-gap-left:24px`）。
  static const double medalLeftZone = 24;

  /// 团名右内缩（`--container-gap-right:4px`）。
  static const double medalRightGap = 4;

  /// 房间前缀图尺寸（`--prefix-width:24px` / `--prefix-height:22px`；
  /// 底部对齐容器，顶部溢出 3px —— web 原样）。
  static const double medalPrefixWidth = 24;
  static const double medalPrefixHeight = 22;

  /// 有前缀图时等级数字盒（width 13 / height 10）。
  ///
  /// 位置 2026-09-27 官网 shadow DOM computed style 实测（room 96555，
  /// zoom 0.9 已还原）：`left: 13px; bottom: 0; top: 9px` —— **底边贴容器
  /// 底**（9+10=19），不是垂直居中；早前记录的 `--level-with-prefix-left:15`
  /// 与 computed 不符，以 computed 为准。
  static const double medalLevelSmallLeft = 13;
  static const double medalLevelSmallWidth = 13;
  static const double medalLevelSmallHeight = 10;

  /// 团名字号（web `.name` computed 12px）。
  static const double medalNameFontSize = 12;

  /// 等级数字字号：无前缀图时占满左区（web 用 per-level 小图，我们用文本
  /// 近似，盒 22×19）。2026-09-29 用户口径「小 2 号」:14 → 12(与团名
  /// 同字号,不再比正文 14 还大);有前缀图时小盒 13×10 → ~9px。
  static const double medalLevelFontSize = 12;
  static const double medalLevelSmallFontSize = 9;

  // ---- 钻粉 suffix 层（2026-09-27 官网 shadow DOM computed 实测）----

  /// 有钻粉 suffix 时容器加宽。**computed 渲染实测 84px**(2026-09-27
  /// zoom 0.9 下 hostW 75.6 还原;`--container-with-suffix-width` 的 96
  /// 与实际渲染不符,以 computed 为准)。保底值:团名超宽时按内容继续
  /// 撑开(见 medalWidthWithSuffixMax)。
  static const double medalWidthWithSuffix = 84;

  /// 团名超宽时容器撑开的上限(官网 span 内容自适应永不截断,我们用
  /// 撑开近似;超出才走 ellipsis 兜底)。
  static const double medalWidthWithSuffixMax = 140;

  /// suffix 图(钻粉钻石图 + 月数叠字)。computed 渲染实测宽 26、高 21
  /// (zoom 0.9 下 23.4 还原;源图 33×24 按该盒 fill 绘制),底边贴容器
  /// 底、**右缘贴容器右缘(gap=0)**、顶部溢出 2px(y=-2..19)。
  static const double medalSuffixWidth = 26;
  static const double medalSuffixHeight = 21;
  static const double medalSuffixRight = 0;

  /// suffix 图上的月数小字盒(computed 实测 x=68.8..84、y=7..19,即右缘
  /// 与底缘都贴容器;白字 **12px**)。
  static const double medalSuffixMonthWidth = 15;
  static const double medalSuffixMonthHeight = 12;
  static const double medalSuffixMonthFontSize = 12;

  /// 有 suffix 时团名右内缩 = suffix 宽 26 + 名字与 suffix 间隙 2。
  /// computed 实测名字右缘 x=56、suffix 左缘 x=58(容器 84 → 84-56=28);
  /// 容器因长名撑开时 suffix 恒贴最右,该 inset 对任意宽度均成立。
  static const double medalNameRightWithSuffix = 28;

  // ---- 至尊大钻石 / 贵族（官网 lit 组件 `:host` 实测）----

  /// 至尊大钻石徽章边长（官网 `dy-supreme-medal` 的 `:host` 实测 28×28，
  /// 是四个 `dy-*` 组件里唯一的高于 16px 的）。
  static const double supremeSide = 28;
}

/// 抖音聊天徽章(img-only 站,尺寸口径见 DESIGN.md §4 徽章表格)。
abstract final class AppDouyinChatBadge {
  /// honor 等级徽章高(官方实际渲染口径 2026-09-29:小于粉丝牌但不至于
  /// 太小;首版 15 用户反馈「改的也太小了」,回调 18 = 粉丝牌 21 的 ~0.86)。
  /// honor 整图与紫粉渐变文字态兜底共用。
  static const double honorHeight = 18;

  /// 粉丝牌图高(pop_super 紧凑款 60×48 → 26.2px 宽)。
  static const double fanImageHeight = 21;

  /// 粉丝牌宽图(v6 150×48 / new_badge 90×48)**裁剪显示宽**:官方模板的
  /// 内容区(数字+装饰带)只有左端 ~60 源px,右侧是纯渐变延伸底(2026-09-29
  /// 用户口径:「图是对的,只用改背景宽度」)→ cover+左对齐裁右。宽度取
  /// **整数 26**(21×60/48 = 26.25 落在半像素栅格,插值模糊发"粗糙";
  /// 2026-09-29 用户口径「不用缩放感,按实际大小」,整数物理对齐);
  /// 灰图换彩后的 60×48(比例 1.25≈26/21)基本无裁切。
  static const double fanCroppedWidth = 26;

  /// 裁切后右端补的圆角半径:素材左端是半圆头(实测 v6 图四角透明,
  /// 圆头半径 = 源高 48/2),右端裁切处必须对称补**高度一半**的圆头
  /// (21/2 = 10.5)组成完整胶囊;首版 4px 用户反馈「右侧像截断」
  /// (2026-09-29),同虎牙 consume 裁切「与左端同半径补回」口径。
  static const double fanCropEndRadius = fanImageHeight / 2;
}

/// 阴影(elevation)基线。
///
/// 三类语义 —— popover(下拉浮层)/ hairline(on-video 控件贴边描边)/
/// sheet(侧滑面板投影)—— 数值均从组件里的裸 `BoxShadow` 逐字搬家而来,
/// 外加 [accentGlow] 表达平台/分类选中态的强调色光晕。
///
/// 数值必须与来源逐字一致,否则 golden 会漂。
abstract final class AppElevation {
  /// 下拉菜单/flyout 浮层的投影(黑 24%、blur 16、y+4)。
  ///
  /// 来源:`lib/src/app/shell/category_flyout.dart:171`。
  /// 数值必须与来源逐字一致,否则 golden 会漂。
  static const List<BoxShadow> popover = [
    BoxShadow(color: Color(0x3D000000), blurRadius: 16, offset: Offset(0, 4)),
  ];

  /// on-video 控件贴边的 1px 描边(黑 35%、blur 0、spread 1)。
  ///
  /// 来源:`lib/src/features/play/widgets/player_controls.dart:738` 与 `:781`。
  /// 数值必须与来源逐字一致,否则 golden 会漂。
  static const List<BoxShadow> hairline = [
    BoxShadow(color: Color(0x59000000), blurRadius: 0, spreadRadius: 1),
  ];

  /// 沉浸模式侧滑面板向左投射的投影(黑 55%、blur 28、x-6)。
  ///
  /// 来源:`lib/src/features/play/widgets/play_immersive_side_sheet.dart:126`。
  /// 数值必须与来源逐字一致,否则 golden 会漂。
  ///
  /// 刻意保留 `static final` + `Colors.black.withValues(alpha: 0.55)`:换成
  /// `0x8C` 字面量在像素上可能有 1/255 的差异。
  static final List<BoxShadow> sheet = [
    BoxShadow(
      color: Colors.black.withValues(alpha: 0.55),
      blurRadius: 28,
      offset: const Offset(-6, 0),
    ),
  ];

  /// 平台/分类选中态的强调色光晕(强调色 22%、blur 8、y+2)。
  ///
  /// 来源:`lib/src/app/shell/platform_strip.dart:269`。
  /// 数值必须与来源逐字一致,否则 golden 会漂。
  static List<BoxShadow> accentGlow(Color accent) => [
    BoxShadow(
      color: accent.withValues(alpha: 0.22),
      blurRadius: 8,
      offset: const Offset(0, 2),
    ),
  ];
}

/// 键盘焦点环基线(Windows 桌面键盘可达性)。
///
/// 替代 Material 默认聚焦态:两圈 `BoxShadow` 拼出「2px 实环 + 2px 间隙」的
/// 外扩环,不占布局空间、不改变控件盒模型。
///
/// 本阶段只提供 token,不改组件默认焦点(避免大面积视觉变化,留给后续迁移)。
abstract final class AppFocus {
  /// 焦点环实体宽度。
  static const double ringWidth = 2;

  /// 焦点环与控件边缘之间的间隙。
  static const double ringOffset = 2;

  /// 用强调色构造焦点环:外层半透明(24%)撑出间隙,内层实色为 2px 环。
  static List<BoxShadow> ring(Color accent) => [
    BoxShadow(
      color: accent.withValues(alpha: 0.24),
      blurRadius: 0,
      spreadRadius: ringWidth + ringOffset,
    ),
    BoxShadow(color: accent, blurRadius: 0, spreadRadius: ringWidth),
  ];
}

/// 字号阶梯:全项目**唯一**的字号数值来源。
///
/// 9 档覆盖 9–22px 的全部文字需求。任何 `fontSize:` 都必须引用本类或
/// [AppTypography] 的同名 `TextStyle`（裸字面量由 `tool/check_design_tokens.dart` 拦下）。
///
/// 两者分工：[AppTypography] 给“字号 + 行高 + 字重”成组样式；本类只给数值，
/// 供需要自定义 height/weight/letterSpacing 的调用点使用。
///
/// **收敛记录（2026-09-21）**：代码里原有 **18 种**字号，含 8 / 8.1 / 9.4 / 9.5 /
/// 10.5 / 10.9 / 11.5 / 11.84 / 12.5 / 12.6 / 14.4 / 15 / 20 / 26 等散值，现全部
/// 归一到本阶梯（就近取档）4 字；两处平局按语义定档：
/// - `15 → 14`：与 subtitle 合并（两档只差 1px，无独立语义）；
/// - `20 → 22`：页面标题与头像首字母属 display 档。
abstract final class AppFontSize {
  /// 全大写眉标 / 极小角标。
  static const double overline = 9;

  /// 角标 / 紧凑控件标签。
  static const double label = 10;

  /// 辅助说明。
  static const double caption = 11;

  /// 次级正文。
  static const double bodySecondary = 12;

  /// 正文默认。
  static const double body = 13;

  /// 卡片 / 设置项标题。
  static const double subtitle = 14;

  /// 区块标题。
  static const double title = 16;

  /// 弹窗 / 面板标题。
  static const double headline = 18;

  /// 页面主标题 / 大字号数字。
  static const double display = 22;
}

/// 字号/行高/字重基线。
///
/// **不含颜色**:文字颜色统一由主题 tokens 提供(`context.textTitle` /
/// `context.textCaption` 等,见 zishu_tokens.dart)。写死颜色会让浅色主题下
/// 出现白底白字 —— 深色基线色 `AppColors.textPrimary` 只是恰好与
/// `ZishuTokens.dark` 同值。
///
/// 阶梯共 9 档,字号数值一律取自 [AppFontSize]（单一来源）：`overline`(9)/
/// `label`(10)/`caption`(11)/`bodySecondary`(12)/`body`(13)/`subtitle`(14)/
/// `title`(16)/`headline`(18)/`display`(22)。
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
    fontSize: AppFontSize.title,
    height: 1.35,
    fontWeight: FontWeight.w600,
  );

  static const TextStyle body = TextStyle(
    fontSize: AppFontSize.body,
    height: 1.4,
  );

  static const TextStyle bodySecondary = TextStyle(
    fontSize: AppFontSize.bodySecondary,
    height: 1.4,
  );

  static const TextStyle caption = TextStyle(
    fontSize: AppFontSize.caption,
    height: 1.3,
  );

  /// 最大标题档(22px/1.2/w600/-0.3):页面主标题。
  static const TextStyle display = TextStyle(
    fontSize: AppFontSize.display,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.3,
  );

  /// 区块标题档(18px/1.3/w600/-0.1):弹窗标题、面板标题。
  static const TextStyle headline = TextStyle(
    fontSize: AppFontSize.headline,
    height: 1.3,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// 次级标题档(14px/1.35/w500/0):卡片标题、设置项标题。
  static const TextStyle subtitle = TextStyle(
    fontSize: AppFontSize.subtitle,
    height: 1.35,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  /// 小标签档(10px/1.3/w500/+0.3):角标、紧凑控件标签。
  static const TextStyle label = TextStyle(
    fontSize: AppFontSize.label,
    height: 1.3,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.3,
  );

  /// 最小全大写标签档(9px/1.2/w600/+0.5):分组眉标、极小角标。
  static const TextStyle overline = TextStyle(
    fontSize: AppFontSize.overline,
    height: 1.2,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.5,
  );

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

/// 交互态叠加层(overlay)的统一取值 —— 交互四态的**唯一数值来源**。
///
/// 覆盖 `InkWell` / `Material` 按钮的 `splashColor`(按下涟漪)、`highlightColor`
/// 与 `focusColor`(键盘焦点底色),以及自绘容器的 hover/pressed 补色。
///
/// 三条决策(2026-09-21 收口三条交互轨后统一):
/// 1. 这些颜色**只在交互中出现、不参与静止渲染** —— 集中在此既统一手感又不动 golden。
/// 2. 它们是“叠在某个基色上的半透明层”,**与色相无关**:基色由调用方传入
///    (`accent` / `AppOnVideo.text` / `AppOnBright.white` / 自绘 chip 自身的前景色)。
/// 3. **焦点一律用强调色**,不用 `surfaceRaised` 这类“抬升一档的底色”——
///    后者在浅色主题下与常态几乎无差别,键盘用户看不出焦点在哪
///    (无障碍要求可见);自绘控件用 [AppFocus.ring] 外扩环,两者同为“焦点用 accent”。
///
/// “已经处在抬升面(`surfaceRaised`)上的元素 hover”不能再抬亮,退回用
/// [hoverOf] 的强调色淡层,避免“越 hover 越看不出”。
abstract final class AppStateLayer {
  /// hover:最弱的提示层。
  static const double hoverAlpha = 0.10;

  /// 按下涟漪(splash):比 hover 明显一档。
  static const double splashAlpha = 0.12;

  /// 按下底色(highlight / pressed overlay)。
  static const double pressedAlpha = 0.16;

  /// 键盘焦点:最强,必须一眼可见。
  static const double focusAlpha = 0.24;

  /// hover 层颜色(`InkWell.hoverColor` / 自绘 hover 补色)。
  static Color hoverOf(Color base) => base.withValues(alpha: hoverAlpha);

  /// 按下涟漪颜色(`InkWell.splashColor`)。
  static Color splashOf(Color base) => base.withValues(alpha: splashAlpha);

  /// 按下底色(`InkWell.highlightColor` / `overlayColor` 的 pressed 档)。
  static Color pressedOf(Color base) => base.withValues(alpha: pressedAlpha);

  /// 键盘焦点底色(`focusColor` / `overlayColor` 的 focused 档)。
  static Color focusOf(Color base) => base.withValues(alpha: focusAlpha);
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
/// 视频 popover/弹出面板内的小型控件规格(用户口径 2026-09-20:
/// 尺寸全局统一,对齐 SFVideo web `--ctrl-*` 与 el-switch/el-slider 的
/// 紧凑视觉)。视频控制条、飘屏弹幕设置等面板一律取此处,不得散落。
abstract final class AppControls {
  /// 面板内滑杆轨道高。
  static const double sliderTrackHeight = 3;

  /// 面板内滑杆圆点半径。
  static const double sliderThumbRadius = 6;

  /// 面板内滑杆行高(含触摸余量的最小盒)。
  static const double sliderRowHeight = 20;

  /// 面板内小字号(标签/数值)。
  static const double labelFontSize = 11;

  /// 面板行间距。
  static const double rowGap = 2;
}

abstract final class AppDirectoryDrawer {
  /// 展开态宽度(`--directory-drawer-width: 220px`)。
  static const double width = 220;

  /// 收起态宽度(`--directory-rail-width: 52px`)。
  ///
  /// 真源:`DirectoryDrawer.vue:660` `.directory-drawer { width: var(...) }` +
  /// `main.css:39`。内部看板曾误作「视觉 ≈28px」(那是顶栏平台 tab 的窄屏
  /// 收缩值,见 `docs/ui-reference/README.md:39`),2026-09-21 核对后废弃。
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
