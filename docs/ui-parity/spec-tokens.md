# SFVideo 设计 Token 规格（规格驱动复刻 · 色板与基础常量）

> 视觉真源已收敛到项目根 `DESIGN.md`；本文是推导来源与证据链，冲突时以 `DESIGN.md` 为准。

> 源：`F:/project/SFVideoLive/apps/web`（Vue 3 + Element Plus），分支 `desktop-native`
> 抽取日期：2026-09-10
> 口径：**几何 + 配色 + 断点行为 + 交互等价**，不追求逐像素（跨框架字体渲染不可对齐）

## 1. 主题架构差异（架构级，优先决策）

| 维度 | SFVideo | zishu 现状 | 影响 |
|---|---|---|---|
| 主题模式 | dark / light 双套（`[data-theme]` + `html.dark`），默认 dark（`src/utils/ui/theme.ts:4`） | 仅一套硬编码暗色（`design_tokens.dart`） | 若要 1:1 需引入主题切换；若只做暗色可暂缓 |
| 强调色 | 可换 accent（`accentPresets.ts` + `applyAccent/applyAccentHex`），默认金 `#f3d04e` | 单值 `brand` | accent 机制属增强项，非 1:1 必需 |
| 变量机制 | CSS 变量 + `color-mix()` 运行时计算 | Dart `static const` 编译期常量 | `color-mix()` 需**预计算为 hex** 后落地（本文已算好） |
| 沉浸模式 | 全屏时 `--chrome-page-bg` 置 `#000000`（`theme.ts:6,22`） | 无 | 播放页全屏需单独处理 |

**建议**：本期先落暗色完整色板；light 主题与 accent 机制作为后续项，但 token 结构需预留（避免二次重构）。

## 2. 品牌与语义色（dark 主题）

来源 `styles/theme.css:3-23`、`styles/main.css:69-85`

| CSS 变量 | 值 | zishu 现状 | 差异 |
|---|---|---|---|
| `--primary` | `#F3D04E` | `brand = #F3D04E` | ✅ 一致 |
| `--primary-hover` | `#FFE066` | 缺失 | 待补 |
| `--primary-on` | `#1A1400` | 缺失 | 待补（品牌底上的文字色） |
| `--live` | `#32C874` | `liveBadge = #E64B3D` | ❌ **色相错误**：SFVideo 直播中是**绿**，zishu 用红 |
| `--danger` | `#E55050` | `error = #F56C6C` | ⚠️ 值不同（Element 默认 vs 自定义） |
| `--bg` / `--chrome-page-bg` | `#181818` | `background = #181818` | ✅ |
| `--bg-elevated` | `#1F1F1F` | `surface = #1F1F1F` | ✅ |
| `--bg-soft` | `#141414` | `surfaceSoft = #141414` | ✅ |
| `--dark-6` / `--surface-2` | `#2A2A2A` | `surfaceRaised = #2A2A2A` | ✅ |
| `--border` | `#3A3A3A` | `border = #3A3A3A` | ✅ |
| `--text` | `rgba(255,255,255,.87)` | `textPrimary` 87% | ✅ |
| `--muted` | `rgba(255,255,255,.55)` | `textSecondary` 55% | ✅ |
| `--on-video-bg-bar` | `#141414` | 缺失 | 待补 |
| `--on-video-bg-panel` | `#1A1A1A` | 缺失 | 待补 |
| `--cover-fallback-bg` | `#2A2A2A` | 缺失 | 封面占位底色 |

## 3. 平台站点色（8 个，zishu 全部缺失）

> ⚠️ **本表列的是 web 静态 CSS 里的值，其中至少两项已被运行时覆盖，不是真源**
> （2026-09-21 实测）：web 启动时 `main.js:57` 调 `initPlatformBrandVars()`，把
> `config/platformCatalog.ts` 的 `PLATFORM_BRAND_COLORS[id].bg` 内联注入 `:root`，
> **覆盖**本表所列的静态同名变量。已确认不同值的至少两处：
> `--platform-bilibili` 静态 `#00a1d6`（蓝）→ 实际 **粉 `#fb7299`**；
> `--platform-douyu` 静态 `#ff6b00` → 实际 `#ff6a00`。
> **真源以 `platformCatalog.ts` 为准**；本表只作历史参考，不要直接照抄。
> 详见 `DESIGN.md` §2.3。

来源 `styles/theme.css:9-16`

| 变量 | 值 | 变量 | 值 |
|---|---|---|---|
| `--platform-douyu` | `#FF6B00` | `--platform-soop` | `#00A8FF` |
| `--platform-huya` | `#FFB800` | `--platform-xhs` | `#FF2442` |
| `--platform-bilibili` | `#00A1D6` | `--platform-youtube` | `#FF0000` |
| `--platform-douyin` | `#FE2C55` | `--platform-iptv` | `#2B7FFF` |

## 4. 播放页专用色（`color-mix` 已预计算为 hex）

来源 `styles/theme.css:34-45, 83-95`。`color-mix(in srgb, A x%, B)` 按 sRGB 线性加权计算，结果为**不透明**色，可直接写 Dart。

| 变量 | 计算式 | 预计算值 | 用途 |
|---|---|---|---|
| `--play-stat-audience-bg` | `#284868` 86% + `#0A0A0A` | `#243F5B` | 人气统计条底 |
| `--play-stat-audience-text` | 直接值 | `#B8DCFF` | 人气统计条字 |
| `--play-stat-vip-bg` | `#886030` 90% + `#0A0A0A` | `#7B572C` | VIP 统计条底 |
| `--play-stat-vip-text` | 直接值 | `#FFD4A0` | VIP 统计条字 |
| `--play-stat-svip-bg` | `#482868` 92% + `#0A0A0A` | `#432660` | SVIP 统计条底 |
| `--play-stat-svip-text` | 直接值 | `#F0B8FF` | SVIP 统计条字 |
| `--play-follow-bg` | `#7A3030` 68% + `#101010` | `#582626` | 关注按钮常态 |
| `--play-follow-border` | `#7A3030` 52% + `#606060` | `#6E4747` | 关注按钮描边 |
| `--play-follow-bg-hover` | `#7A3030` 58% + `#181818` | `#512626` | 关注按钮 hover |
| `--play-follow-bg-active` | `#7A3030` 48% + `#282828` | `#4F2C2C` | 关注按钮 active |
| `--play-follow-text` | 直接值 | `#FFB8B8` | 关注按钮字 |
| `--play-follow-text-active` | 直接值 | `#FFE0E0` | 关注按钮 active 字 |
| `--play-super-bg` | `#583878` 72% + `#101010` | `#442D5B` | Super 按钮常态 |
| `--play-super-border` | `#583878` 48% + `#606060` | `#5C4D6C` | Super 按钮描边 |
| `--play-super-bg-hover` | `#583878` 62% + `#181818` | `#402C54` | Super 按钮 hover |
| `--play-super-bg-active` | `#583878` 52% + `#282828` | `#413052` | Super 按钮 active |
| `--play-super-text` | 直接值 | `#C9A0F0` | Super 按钮字 |
| `--play-super-text-active` | 直接值 | `#E9D5FF` | Super 按钮 active 字 |

> 注意：`--play-follow-bg-hover` 源码行 86 写的是 `58%`，与同组其他态的 68/48 序列略有出入，按源码原值计算。

## 5. 关注页 / 侧栏 / 弹幕色

来源 `styles/theme.css:96-118`

| 变量 | 值 | 说明 |
|---|---|---|
| `--follow-online-chip-bg` | `#3A5878` | 在线徽章底 |
| `--follow-online-chip-text` | `#D0E8FF` | 在线徽章字 |
| `--follow-online-chip-live-bg` | `#345070` | 直播中徽章底 |
| `--follow-online-chip-live-text` | `#E0F0FF` | 直播中徽章字 |
| `--sidebar-bg` | `= --bg-elevated` `#1F1F1F` | 侧栏底 |
| `--sidebar-header-bg` | `#1F1F1F` 88% + `#FFFFFF` → `#3A3A3A` | 侧栏头 |
| `--sidebar-chip-bg` | `= --dark-6` `#2A2A2A` | 侧栏 chip 常态 |
| `--sidebar-chip-hover-bg` | `#2A2A2A` 80% + `#FFFFFF` → `#555555` | chip hover |
| `--sidebar-chip-active-bg` | `#2A2A2A` 70% + `#FFFFFF` → `#6A6A6A` | chip 选中 |
| `--chat-nickname-color` | `--muted` 72% + `#FFFFFF` → `#ACACAC` | 弹幕昵称 |
| `--scrollbar-thumb` | `--primary` 68% + 白 35% → `#F7DF87` | 滚动条滑块 |
| `--scrollbar-thumb-hover` | `= --primary-hover` `#FFE066` | 滑块 hover |
| `--scrollbar-track` | `transparent` | 滚动条轨道 |

## 6. 圆角 / 间距 / 动效

来源 `styles/main.css:69-85`

| 类别 | SFVideo | zishu 现状 | 差异 |
|---|---|---|---|
| radius xs | `--fluent-radius-xs` = 4px（取 `--el-border-radius-small`） | `AppRadius.sm = 4` | 值一致，命名差一级 |
| radius sm | `--fluent-radius-sm` = 8px（取 `--el-border-radius-base`） | `AppRadius.md = 8` | 同上 |
| radius md | `--fluent-radius-md` = 12px | `AppRadius.lg = 12` | 同上 |
| pill | `border-radius: 999px`（出现 7 次，用于 chip/badge/头像） | 缺失 | 需补 `AppRadius.pill` |
| duration fast | `--fluent-duration-fast` = 150ms | `AppMotion.fast = 120ms` | ⚠️ 不同 |
| duration normal | `--fluent-duration-normal` = 250ms | `AppMotion.normal = 200ms` | ⚠️ 不同 |
| easing | `--fluent-easing: cubic-bezier(0.16, 1, 0.3, 1)`（近似 easeOutExpo） | `Curves.easeOutCubic` | ⚠️ 曲线更"急停"，需自定义 |

间距体系见 `spec-layout.md`（4pt 栅格校验章节）。

## 7. 断点

来源 `src/utils/ui/breakpoints.ts:3-7`

| 常量 | 值 | zishu `AppBreakpoints` | 状态 |
|---|---|---|---|
| `BP_COMPACT` | 640 | `compact = 640` | ✅ |
| `BP_MOBILE` | 768 | `phone = 768` | ✅ |
| `BP_PLAY_STACK` | 1024 | `tablet = 1024` | ✅ |
| `BP_FOLLOW_PAGE_TILE_MAX` | 1366 | `desktop = 1366` | ✅ |
| `BP_WIDE` | 1920 | `wide = 1920` | ✅ |

**数值全部一致，差异在判定逻辑**：SFVideo 的 `matchesPlayStackLayout()` 是 `orientation: portrait` + 短边 + `isTabletLikeDevice()` + `hover` 媒体查询的复合条件（`breakpoints.ts:52-90`），zishu 目前只用 `width < 768` 近似。详见 `spec-layout.md` 断点矩阵。

## 8. 差异汇总（按优先级）

> **2026-09-21 复核：下表多数项已闭合，读之前先看这一行。**
> 1 ✅ 已修（`liveBadge = #32C874`）；2 ✅ 已补（`platform_brands.dart`）；
> 3 ✅ 已补（`playFollow*` / `playSuper*` / `playStat*Text`）；4 ✅ 已改 `#E55050`；
> 5 ✅ 已补 `AppRadius.pill = 999`；6 ✅ 已改 150/250ms + `Cubic(0.16,1,0.3,1)`；
> 7 ⚠️ **未闭合**：侧栅 chip 改用 `activeChipAlpha` alpha 混合机制（与 web 的固定 hex 不同）；
>   关注页在线徽章 / 弹幕昵称色 / 滚动条色在 `lib/src` 找不到对应实现；
> 8 ✅ 已实现 `playSidePanelWidthFor(width)`；9 ✅ 浅色主题已实现。
>
> 另：本表未记录的「播放统计第 3 列（tone=svip）全平台未实现」已登记到
> `DESIGN.md` §12.1——那不是本表的优先级项，而是整列缺失。
> 详细口径与待办见 `DESIGN.md` §10（偏离登记）与 §12（已登记未实现项）。

| # | 项 | 类型 | 影响面 | 优先级 |
|---|---|---|---|---|
| 1 | `liveBadge` 红 → 绿 `#32C874`（直播中标识；关注按钮**仍为红系**，二者不冲突） | 修正 | 全站直播标识 | P0 |
| 2 | 8 个平台站点色缺失 | 补齐 | 平台 tab / 卡片角标 | P0 |
| 3 | 播放页 follow/super/stat 三态色（18 项）缺失 | 补齐 | 播放页 | P0 |
| 4 | `error` 值统一 `#E55050` | 修正 | 全局 | P1 |
| 5 | pill 圆角 999px | 补齐 | chip/badge/头像 | P1 |
| 6 | 动效时长 150/250ms + 自定义 easing | 修正 | 全局 hover 手感 | P1 |
| 7 | 侧栏/chip/弹幕/滚动条色（13 项） | 补齐 | 侧栏与弹幕 | P1 |
| 8 | 侧栏宽度分档 268/328/392/425 | 补齐 | 播放页 | P2（见 spec-layout） |
| 9 | light 主题 + accent 机制 | 架构 | 全局 | P3（可后续） |

## 9. 视觉实测对照

交叉验证截图见 `visual-confirm.md`（`tool/screenshots/sfvideo/` 下 4 张关键截图）。要点：

- **三色系分工已确认**：直播中=绿（`--live #32C874`）、关注=红（`--play-follow-bg #582626`）、超关=紫（`--play-super-bg #442D5B`）。zishu `liveBadge` 用红是色相错误。
- **顶栏高度需分断点**：mobile 约 44-48px，desktop 约 48-52px，原 spec 引用 `main.css:223` 写 44px 只对应单一断点。
- **mobile 顶栏是双行结构**：第一行 9 平台 logo，第二行各平台下拉 tab，zishu `app_shell.dart` 当前是单行。
- **mobile 底栏实测 6 项**（紫薯logo / 首页 / 分类 / 我的 / 发现 / 搜索 / 我的），zishu U9 改造后是 4 项，需复核。
- **卡片"四象限徽章"**模板：左上分类色块 / 左下平台色块 / 右上直播中/画质 / 右下热度。`spec-layout.md` 卡片几何章节需补充。
