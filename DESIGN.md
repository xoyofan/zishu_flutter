# DESIGN.md — zishu_flutter 视觉真源 v0.1

> 本文件是 zishu_flutter 的**唯一视觉真源**，格式取自 Google Stitch 的 DESIGN.md。
> `AGENTS.md` 说明项目"怎么搭"，本文件说明项目"长什么样"。
>
> **变更纪律**：改任何颜色 / 字号 / 间距 / 圆角 / 阴影前，先改本文件 → 再改 token 文件
> （`lib/src/shared/presentation/design_tokens.dart`、`zishu_tokens.dart`）→ 最后改调用点。
>
> **冲突裁决**：本文件 > `docs/ui-parity/spec-tokens.md` / `spec-layout.md`（它们是推导来源与证据链）。
> 完整色板与逐项差异见 `docs/ui-parity/spec-tokens.md`，布局几何见 `docs/ui-parity/spec-layout.md`。

---

## 1. Visual Theme & Atmosphere

zishu_flutter 是**深色优先的桌面级直播客户端**，视觉语言继承自 SFVideoLive 的 Web 实现
（Vue 3 + Element Plus，Vite 深色主题），在 Flutter 里用 Widget 重新实现，不复用旧 Vue UI。

| 维度 | 取值 |
|---|---|
| 默认模式 | 深色（Windows 第一轮验收基线）；浅色已实现但同步维护，非验收重点 |
| 画布 | 近黑 `#181818`，浮层/卡片抬升一档 `#1F1F1F` |
| 强调策略 | **单强调色**：控件强调一律品牌紫 `#7C4DFF`（用户口径 2026-09-20）；金黄 `#F3D04E` 退为功能性颜色 |
| 密度 | 高密度工具型界面：字号 9–22px，行高 1.2–1.4，导航高 44/56px |
| 形态 | Fluent 风格：小圆角（4/8/12px）、hairline 边框、克制阴影、`cubic-bezier(0.16,1,0.3,1)` 动效 |
| 字体 | 微软雅黑（中文排版稳定），按链回退 |
| 禁止 | 玻璃拟态大投影、渐变滥用、多强调色、圆角 > 12px 的常规容器（pill 除外） |

三色系分工（易错，务必区分）：

| 语义 | 色系 | token |
|---|---|---|
| 直播中标识 | **绿** | `ZishuTokens.liveBadge` = `#32C874` |
| 播放页「关注」按钮 | **红** | `ZishuTokens.playFollow*` = `#582626` 系 |
| 播放页「超级关注」按钮 | **紫** | `ZishuTokens.playSuper*` = `#442D5B` 系 |

---

## 2. Color Palette & Roles

### 2.1 核心色板（深色 = Windows 验收基线）

取自 `lib/src/shared/presentation/zishu_tokens.dart` 的 `ZishuTokens.dark`，逐字一致。

| 语义名 | hex | 功能角色 |
|---|---|---|
| `background` | `#181818` | 页面画布（`--bg`） |
| `surface` | `#1F1F1F` | 卡片 / 浮层（`--bg-elevated`） |
| `surfaceSoft` | `#141414` | 更深一层底（顶栏 / 底栏，`--bg-soft`） |
| `surfaceRaised` | `#2A2A2A` | hover / 抬升层（`--dark-6`） |
| `border` | `#3A3A3A` | hairline 边框 / 分隔线（`--border`） |
| `brand` | `#F3D04E` | 品牌金黄，仅用于收藏星等功能性强调（对齐 web `--primary`） |
| `accent` | `#7C4DFF` | **控件强调色**：slider / 开关 / 复选 / 选中态 / 进度 / CTA |
| `textPrimary` | `#DEFFFFFF`（白 87%） | 主文字 / 图标 |
| `textSecondary` | `#8CFFFFFF`（白 55%） | 次级文字 / 说明 |
| `liveBadge` | `#32C874` | 直播中标识（绿） |
| `error` | `#E55050` | 错误态（对齐 web `--danger`） |
| `success` | `#67C23A` | 成功态 |
| `coverScrim` | `#B8000000` | 封面上的角标暗底（黑 72%） |
| `coverScrimText` | `#FFFFFF` | 压在 `coverScrim` 上的文字（两种主题都是白） |
| `promoBadge` | `#EBB45309` | 促销 / 画质角标底（琥珀 92%） |
| `statAudience` | `#B8DCFF` | 人气统计文字（蓝） |
| `statVip` | `#FFD4A0` | VIP 统计文字（橙） |
| `statSvip` | `#F0B8FF` | SVIP 统计文字（紫） |

播放页「关注」按钮（红系，6 态）：

| 语义名 | hex | 语义名 | hex |
|---|---|---|---|
| `playFollowBg` | `#582626` | `playFollowBorder` | `#6E4747` |
| `playFollowBgHover` | `#512626` | `playFollowText` | `#FFB8B8` |
| `playFollowBgActive` | `#4F2C2C` | `playFollowTextActive` | `#FFE0E0` |

播放页「超级关注」按钮（紫系，6 态）：

| 语义名 | hex | 语义名 | hex |
|---|---|---|---|
| `playSuperBg` | `#442D5B` | `playSuperBorder` | `#5C4D6C` |
| `playSuperBgHover` | `#402C54` | `playSuperText` | `#C9A0F0` |
| `playSuperBgActive` | `#413052` | `playSuperTextActive` | `#E9D5FF` |

on-video 层（叠在视频画面上的控件，恒定暗色语义，**不随主题翻转**，见
`design_tokens.dart` 的 `AppOnVideo`）：`scrim` `#B8000000`、`bar` `#000000`、
`text` `#DEFFFFFF`、`textMuted` `#8CFFFFFF`。

### 2.2 浅色主题（同步维护，非验收基线）

取自 `ZishuTokens.light`。深色值与旧常量逐位相同，浅色分套：

| 语义名 | light hex | 语义名 | light hex |
|---|---|---|---|
| `background` | `#F5F5F7` | `textPrimary` | `#E6121212` |
| `surface` | `#FFFFFF` | `textSecondary` | `#99616161` |
| `surfaceSoft` | `#ECECEC` | `border` | `#D9D9D9` |
| `surfaceRaised` | `#E0E0E0` | `success` | `#4CA83D` |
| `brand` | `#C9A227` | `statAudience` | `#1B6CA8` |
| `accent` | `#6A1B9A` | `statVip` | `#A8620A` |
| | | `statSvip` | `#8E3AA8` |

浅色下 `liveBadge` 仍为 `#32C874`、`error` 仍为 `#E55050`、`coverScrim` 仍为
`#B8000000`（压图角标两种主题都必须暗底白字）。`playFollow*` / `playSuper*` 在浅色下
改用浅底深字（`#FBECEC` / `#F2ECFA` 系），深色值不变。

### 2.3 平台站点色

8 个平台的品牌色定义在 `lib/src/shared/presentation/platform_brands.dart`
（`PlatformBrandCatalog`），取值与证据见 `docs/ui-parity/spec-tokens.md` §3。
平台色只用于平台 tab、卡片角标、平台图标，**不得**用于通用控件强调。

---

## 3. Typography Rules

| 项 | 值 |
|---|---|
| 字体族 | `Microsoft YaHei`（`AppTypography.family`） |
| 回退链 | `Microsoft YaHei UI` → `PingFang SC` → `Noto Sans CJK SC` → `Source Han Sans SC` → `Segoe UI` |
| 字体接线 | `app_theme.dart` 的 `textTheme.apply(fontFamily, fontFamilyFallback)` |

九档阶梯（`AppTypography`，8→22px）：

| 档位 | fontSize | 字重 | 行高 | letterSpacing | 用途 |
|---|---|---|---|---|---|
| `overline` | 9 | w600 | 1.2 | +0.5 | 分组眉标、极小角标 |
| `label` | 10 | w500 | 1.3 | +0.3 | 角标、紧凑控件标签 |
| `caption` | 11 | w400 | 1.3 | 0 | 辅助说明 |
| `bodySecondary` | 12 | w400 | 1.4 | 0 | 次级正文 |
| `body` | 13 | w400 | 1.4 | 0 | 正文默认 |
| `subtitle` | 15 | w500 | 1.35 | 0 | 卡片 / 设置项标题 |
| `title` | 16 | w600 | 1.35 | 0 | 区块标题 |
| `headline` | 18 | w600 | 1.3 | −0.1 | 弹窗 / 面板标题 |
| `display` | 22 | w600 | 1.2 | −0.3 | 页面主标题 |

**颜色不进 `AppTypography`**。Widget 一律用 `context.textTitle` / `context.textBody` /
`context.textSecondary` / `context.textCaption`（`zishu_tokens.dart` 的
`ZishuTypographyContext`），由 `ZishuTokens` 提供颜色——写死颜色会在浅色主题下白底白字。
`AppTypography.fallbackPrimary/Secondary` 只在拿不到 `BuildContext` 时兜底。

**存量待归一**：代码里仍有 `12.5 / 12.6 / 11.5 / 11.84 / 10.9 / 9.4 / 9.5 / 8.1` 等散值，
属历史遗留。新增代码不得再引入新散值；归一化分批进行，避免 golden 一次性大漂。

---

## 4. Component Stylings

### 4.1 共享组件清单

| 位置 | 内容 |
|---|---|
| `lib/src/shared/presentation/widgets/` | `async_value_view`、`compact_switch`、`cover_badges`、`empty_view`、`error_view`、`platform_badge`、`platform_icon`、`retry_button`、`section_header`、`settings_slider_row`、`state_dot`、`translated_text`（+ `widgets.dart` 汇总导出） |
| `lib/src/app/shell/` | `bottom_nav`、`category_flyout`、`follow_avatars`、`hover_overlay`、`my_category_flyout`、`platform_strip`、`theme_actions`、`top_nav`、`user_area` |
| 页面 | `features/*/views/`：`home_view`、`category_view`、`follow_view`、`play_view`、`search_view`、`anchor_view`、`timeline_view`、`settings_view`、`user_credentials_view`、`parse_benchmark_view` |

### 4.2 状态矩阵

| 状态 | 颜色来源 | 形态 |
|---|---|---|
| default | `surface` / `surfaceSoft` 底，`border` 描边 | 圆角 `AppRadius.sm`(4) 或 `md`(8) |
| hover | 底色抬到 `surfaceRaised`；动效 `AppMotion.fast`(150ms) + `AppMotion.curve` | 颜色/边框过渡，不位移 |
| active / pressed | 在 hover 基础上再压一档（如 `playFollowBgActive`） | 仍不位移 |
| selected | `accent.withValues(alpha: 0.2)` 底（见 `app_theme.dart` 的 `navigationBarTheme.indicatorColor`）；平台/分类选中另加 `AppElevation.accentGlow` | — |
| focus | `AppFocus.ring(accent)`——2px 实环 + 2px 间隙 | 外扩，不占布局 |
| disabled | `textSecondary` 文字 + 不响应指针；不额外加灰罩 | — |
| invalid | `error` = `#E55050` 描边 / 文字 | — |

**待办**：`AppFocus` 目前只有 token，组件默认聚焦态仍是 Material 默认样式。
键盘可达性是 Windows 桌面验收项，迁移需逐组件进行，不在 v0.1 范围。

### 4.3 控件全局规格（`AppControls`）

面板内滑杆等紧凑控件尺寸全局统一（用户口径 2026-09-20）：
`sliderTrackHeight = 3`、`sliderThumbRadius = 6`、`sliderRowHeight = 20`、
`labelFontSize = 11`、`rowGap = 2`。经 `app_theme.dart` 的 `sliderTheme` 全局生效，
各面板不再局部包裹同规格 `SliderTheme`。

---

## 5. Layout Principles

### 5.1 间距 / 圆角 / 动效

| 类别 | 值 |
|---|---|
| `AppSpacing` | `xs 4` / `sm 8` / `md 12` / `lg 16` / `xl 20` / `xxl 28` |
| 导航高 | `topNavHeight = 44`、`bottomNavHeight = 56` |
| 网格间距 | `gridCrossAxisSpacing = 16`、`gridMainAxisSpacing = 13.6` |
| `AppRadius` | `sm 4` / `md 8` / `lg 12` / `pill 999` |
| `AppMotion` | `fast 150ms` / `normal 250ms` / `curve Cubic(0.16, 1, 0.3, 1)` |

### 5.2 抽屉与播放侧栏

| 项 | 值 |
|---|---|
| 抽屉展开宽 | `AppDirectoryDrawer.width = 220`（`--directory-drawer-width`） |
| 抽屉收起宽 | `AppDirectoryDrawer.railWidth = 52`（`--directory-rail-width`） |
| 播放侧栏宽分档 | `playSidePanelWidthFor(width)`：< 768 → 268；768–1599 → 328；1600–1919 → 392；≥ 1920 → 425 |

> 收起态 rail 就是 **52px**，不是 28px。web 真源 `styles/main.css:39` 为
> `--directory-rail-width: 52px`；`DirectoryDrawer.vue:660` 的 `.directory-drawer`
> 直接取该变量，`AppLayout.vue:216` 的主内容 `margin-left` 取同值，
> `DirectoryDrawer.vue:976-988` 的 `.directory-drawer__rail-platform` 是 `width: 100%`
> 全宽按钮（32px 图标不会溢出）。
>
> 勘误：`docs/ui-reference/README.md:39` 提到的 28px 是**顶栏平台 tab** 在 768–1080 的
> 收缩值；该文件第 49 行曾把它误写成抽屉 rail 的宽度。`tasks-ui-refine.md` 的 T2 卡片
> 因此提出“视觉 28px”的改动，已核实为错误前提并回退（见 §11）。

### 5.3 房间网格（固定列数，非 auto-fill）

对齐 SFVideoLive `RoomGrid.vue`，实现见 `AppRoomGrid.columnsFor`：

| 视口宽 | 列数 |
|---|---|
| < 640 | 2 |
| ≥ 640 | 3 |
| ≥ 768 | 4 |
| ≥ 1024 | 5 |
| ≥ 1536 | 6 |
| ≥ 1920 | 6 |
| ≥ 2560 | 7 |

房卡封面固定 16:9（`cardWidth * 9 / 16`）。元信息区高度预算按
`metaHeightFor(base, context)` 随系统字体缩放同步放大，避免大字体下溢出。

### 5.4 4pt 栅格与例外登记

基准是 **4pt 栅格**（4/8/12/16/20/24/32px）。以下值是"逐像素复刻优先于栅格归一"的
历史决定，**登记在案、不得据此扩大例外**，证据见 `docs/ui-parity/spec-layout.md` §7：

| 值 | px | 来源 |
|---|---|---|
| `0.85rem` | 13.6 | `app-main-pad-x`、`RoomGrid` 行距 |
| `0.35rem` | 5.6 | `RoomGrid` padding、app-main 上内边距 |
| `0.65rem` | 10.4 | `controls-bar` padding |
| `0.28rem` | 4.48 | 关注 tile 列距 |
| `0.22rem` | 3.52 | page-tile body 内边距、底部栏 |
| `0.32rem` | 5.12 | 侧栏 tile padding |
| `0.36rem` / `0.45rem` | 5.76 / 7.2 | 侧栏 tile padding |
| `0.55rem` | 8.8 | 平板竖屏 strip tab |
| `1.15rem` | 18.4 | `drawer-toggle-width` |
| `70px` | 70 | `nav-width`（遗留）、page-tile avatar |
| `AppSpacing.xxl` | 28 | Flutter 侧自有值，web 真源无对应（web 用 24 / 32） |

新增间距一律取 `AppSpacing` 已有档；确需例外必须在提交说明里写明并与本表同步登记。

---

## 6. Depth & Elevation

四档，定义在 `AppElevation`（`design_tokens.dart`）。数值从原先散落的裸 `BoxShadow`
逐字搬家而来，**不得改动数值**，否则 golden 会漂。

| 档位 | 值 | 语义 |
|---|---|---|
| `AppElevation.popover` | 黑 24%、blur 16、y+4 | 下拉菜单 / flyout 浮层 |
| `AppElevation.hairline` | 黑 35%、blur 0、spread 1 | on-video 控件贴边 1px 描边 |
| `AppElevation.sheet` | 黑 55%、blur 28、x−6 | 沉浸模式侧滑面板向左投射 |
| `AppElevation.accentGlow(accent)` | 强调色 22%、blur 8、y+2 | 平台 / 分类选中态光晕 |

原则：

- **阴影只用这四档**，禁止在 Widget 里新写 `BoxShadow(...)`（守卫脚本会拦）。
- 抬升层级用"底色档位"表达优先于加大阴影：`surfaceSoft` < `background` < `surface` < `surfaceRaised`。
- 不用 Material `Card` 默认 elevation（`app_theme.dart` 已置 0）。

---

## 7. Do's and Don'ts

### Do

- Widget 里所有颜色 / 字号 / 间距 / 圆角 / 阴影都引用 token；token 缺了就**先补 token 再引用**。
- 颜色从 `context.tokens.*` 取（随主题切换），文字样式用 `context.textTitle` 等组合。
- 播放页 / 弹幕 / 面板等"压深色底"的控件用 `AppOnVideo` 语义色，不跟随主题翻转。
- 悬停态用 `AppMotion.fast` + `AppMotion.curve`，展开/收起用 `AppMotion.normal`。
- 响应式分支用 `LayoutBuilder` + `AppBreakpoints`，不引入额外自适应依赖。

### Don't

- ❌ Widget 内写裸色值（`Color(0x...)`、`Colors.xxx`）、裸数字（`fontSize: 13`、`BorderRadius.circular(6)`）、裸 `BoxShadow(...)`。
- ❌ 在 Widget 里硬编码深色基线色充当文字色（浅色主题下会白底白字）。
- ❌ `import 'package:zishu_flutter/legacy/...'` 或相对引用 `lib/legacy/`。
- ❌ 把 Web 专属 API（`dart:js_interop`、`dart:ui_web`、`package:web`、`HtmlElementView`）写进 `lib/src/`（只允许 `lib/legacy/` 或 `lib/src/platforms/web/`）。
- ❌ 在解析 package（`packages/live_parser/`）里引入 Flutter、Widget、`media-kit`、`dart:ui`、`package:web`、`dart:js_interop`。
- ❌ 把播放器 / 重试 / 选线状态机放进 UI 层；播放统一走 `LivePlayer` 抽象 + media-kit adapter。
- ❌ 用 `Map<String, dynamic>` 直接喂 UI；必须经过 `shared/domain` 的稳定 model。
- ❌ 在一个项目里混用两套外部品牌的设计系统（`awesome-design-md` 一次只选一套，且只取结构不取品牌色 / 字体 / logo）。
- ❌ 复制外部品牌的 logo、商标字形、专有插图。
- ❌ 让 `liveBadge` 用红（直播中是绿，红是「关注」按钮）。
- ❌ 常规容器用 > 12px 圆角（chip / badge / 头像用 `AppRadius.pill`）。

---

## 8. Responsive Behavior

断点（`AppBreakpoints`，与 SFVideoLive `breakpoints.ts` 同值）：

| 常量 | 值 | 语义 |
|---|---|---|
| `compact` | 640 | 2 列 → 3 列；播放框圆角归 0 |
| `phone` | 768 | 导航从底栏切到顶栏；4 列；侧栏宽降到 268 |
| `tablet` | 1024 | 5 列；播放页可并排 |
| `desktop` | 1366 | 关注页 page-tile 视口上限 |
| `wide` | 1920 | 6 列；侧栏宽 425 |

复合条件（必须照做，不要只看宽度）：

- 播放页并排 / 堆叠用复合判定：平板仅**竖屏**堆叠，横屏且短边 ≥ 768 并排；
  手机 / 触屏竖屏堆叠；电视类设备永不堆叠。
- hover 系 UI（抽屉悬停、卡片 hover）只在 `(hover: hover) and (pointer: fine)` 生效；
  触屏把控制条菜单改为底部 sheet。
- 顶栏在放不下时按「横向滚动 > icon 收缩 > 换行」优先级收缩；44px 顶栏内**禁止换行**。
- 触控目标不小于 36–48px；缩小视觉宽度时（如抽屉 rail 28px）必须靠 padding 保住热区。

窄屏（< 768）：主导航转底部 56px，平台列表变顶部单行横向 strip，播放页侧栏堆叠到视频下方。

---

## 9. Agent Prompt Guide

改这个项目的 UI 时，可直接复制：

```text
先读项目根 DESIGN.md（视觉真源）与 docs/ui-parity/spec-layout.md 对应页面章节。
所有颜色/字号/间距/圆角/阴影只引用 lib/src/shared/presentation/ 下的 token
（AppColors / ZishuTokens / AppSpacing / AppRadius / AppTypography / AppMotion /
AppElevation / AppFocus / AppOnVideo / AppControls / AppDirectoryDrawer / AppRoomGrid）。
需要新值：先加 token + 加 test/shared/design_tokens_test.dart 契约断言，再改调用点。
不要写裸 Color(0x...)、裸 fontSize、裸 BorderRadius.circular(数字)、裸 BoxShadow。
收口跑：flutter analyze（0 error）+ flutter test + dart run tool/check_design_tokens.dart。
若需要外部品牌视觉参考，用 .agents/skills/awesome-design-md/ 下 74 套 DESIGN.md，
一次只选一套，只取结构（层级/状态/密度/响应式策略），不取品牌色、字体与 logo。
```

---

## 10. 偏离登记表

有意偏离 SFVideoLive Web 真源的决定，必须登记在此，避免被后续"对齐"误改回去：

| # | 项 | Web 真源 | zishu 现状 | 原因 | 日期 |
|---|---|---|---|---|---|
| 1 | 控件强调色 | `--primary` 金黄 `#f3d04e` | `accent` 品牌紫 `#7C4DFF`（浅色 `#6A1B9A`） | 用户口径：控件强调一律品牌紫；金黄降为功能性颜色（收藏星等） | 2026-09-20 |
| 2 | 间距 `xxl` | 无对应（1.5rem=24 / 2rem=32） | `AppSpacing.xxl = 28` | Flutter 侧自有档位 | — |
| 3 | 10 处非 4pt 栅格值 | 见 §5.4 表 | 逐字保留 | 逐像素复刻优先于栅格归一 | — |
| 4 | 主题范围 | dark + light 双套，默认 dark | 双套已实现，但 Windows 第一轮只验收 dark | 收敛验收面 | — |
| 5 | 字体 | 浏览器 system-ui | 显式 `Microsoft YaHei` + 回退链 | 桌面端中文排版稳定 | — |
| 6 | 手机底栏项 | `docs/ui-reference/README.md:44` 记“首页/分类/我的分类/关注/搜索/主题” | 另有一个“我的”（挂 `/settings`，有 `nav-settings` 锚点契约）；360px 下不隐藏“我的分类”（靠 `scaleDown`） | 保留既有路由与测试契约，暂不重构；属已知差异 | 2026-09-21 |

---

## 11. 真源与漂移

**为什么要有这份文件**：本项目的视觉规范曾同时存在于 5 处
（`docs/ui-parity/spec-tokens.md`、`spec-layout.md`、`docs/implementation-plan.md` §6.1、
`design_tokens.dart` 注释、`.agents/skills/vue-ui-to-flutter/SKILL.md`），结果是**真的漂了**：

- `tasks-ui-refine.md` 把 T1（`error` 改 `#E55050`、动效 150ms/250ms、easing
  `Cubic(0.16, 1, 0.3, 1)`）标为"待处理"，但代码早已全部落地。
- 同一看板把 T5（6 张 golden 基线失败 0.97%–1.26%）列为待办，实际 6 张全部通过。

即"看板说的"和"代码做的"已经对不上。因此：

1. **本文件是唯一视觉真源**；`spec-*.md` 降级为推导来源与证据链，冲突以本文件为准。
2. 任何 token 变更 = 本文件 + token 文件 + 契约测试三处同步。
3. 裸值由 `tool/check_design_tokens.dart` 机械守卫：`lib/src/**` 里
   `raw_color` / `raw_shadow` / `raw_font_size` / `raw_radius` 四类违规不得超出
   `tool/design_token_baseline.json` 的存量基线（v0.1 时 `raw_shadow` 已归零，
   其余三类共 220 条存量待逐步清零）。
4. 外部品牌设计系统（`.agents/skills/awesome-design-md/`，74 套）只作**结构参考**，
   绝不替换本文件的色板与字体。

### 11.1 反向漂移：看板也会写错真源

上面说的是“代码已经改了、看板没跟上”。本次还遇到相反的一种：**看板写的“真源”本身是错的**。

| 卡片 | 看板主张 | 复核结果（web 真源出处） | 处置 |
|---|---|---|---|
| T2 抽屉收起态 rail | “真源 52px，但视觉 rail 约 28px”，要求布局改 28px | ❌ `main.css:39 --directory-rail-width: 52px`；`DirectoryDrawer.vue:660` 直接取该变量；rail 内按钮 `width:100%` | 回退改动，保持 52px |
| T3 房卡平台 badge | “真源 右下 = 平台 badge 与热度并列”，要求从左下移到右下 | ❌ `RoomCard.vue:262-273` `.room-card__foot-left { left:0; bottom:0 }` 内含 `.platform-cover-badge`；热度是另一个 `.cover-online-badge` | 不改代码，现状已对齐 |
| T4 手机底栏项数 | “真源 6 项（紫薯 logo/首页/分类/关注/搜索/我的）” | ⚠️ `ui-reference/README.md:44` 是“首页/分类/我的分类/关注/搜索/主题”——数字与项目都不对；但“没有动态”这一点成立 | 只移除 `nav-time`（动态），保留主题与我的分类 |

教训：**看板不是真源**。裁决前必须回到 `SFVideoLive/apps/web/src` 的 CSS/模板原文或官方截图，
中介文档（看板、实测笔记）只能当线索。这条已写入 `AGENTS.md` 的视觉真源一节。
