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
`text` `#DEFFFFFF`、`textMuted` `#8CFFFFFF`，另有 `captionPillBg`、`captionPillText`、
`captionPillTextMuted`、`pauseScrim`（字幕胶囊与暂停遮罩）。

对称地，`AppOnBright` 覆盖**亮饱和底**（accent / brand / 平台品牌色）上的前景：
`glyph` `#000000`、`text` `#DD000000`、`white` `#FFFFFFFF`。
**`AppOnVideo` 与 `AppOnBright` 都是主题无关常量**（底色由画面或品牌/平台决定，
不随深浅主题变）；而随主题变化的颜色**必须**走 `ZishuTokens` —— 在 `lib/src` 的
UI 文件里写死 `AppColors.*` 会被 `test/ui/light_theme_test.dart` 的静态守则拦下。

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

平台的品牌色定义在 `lib/src/shared/presentation/platform_brands.dart`
（`PlatformBrandCatalog`），取值与证据见 `docs/ui-parity/spec-tokens.md` §3。
平台色只用于平台 tab、卡片角标、平台图标、侧栏标签，**不得**用于通用控件强调。

**单一真源**：对齐 web `config/platformCatalog.ts` 的 `PLATFORM_BRAND_COLORS[id].bg` ——
图标底色、顶栏 tab 描边/光晕、封面角标、侧栏标签**全部**用这一个值。

> ⚠️ **易踩陷阱（2026-09-21 实测踩过）**：web 的 `theme.css` / `main.css` 里还有一份
> 同名静态变量，而且**值不同**：
>
> | | 静态 CSS（theme.css:12 / main.css:146） | 色表 `platformCatalog.ts`（真源） |
> |---|---|---|
> | `--platform-bilibili` | `#00a1d6` **蓝** | `#fb7299` **粉** |
> | `--platform-douyu` | `#ff6b00` | `#ff6a00` |
>
> 但 web 启动时 `main.js:57` 会调 `initPlatformBrandVars()`
> （`utils/ui/platformBrandVars.ts`），把 `info.bg` **内联注入 `:root`**，覆盖那些静态值
> —— 注入代码自己的注释就写着“覆盖 theme.css/main.css 中**旧** 4 个平台的同名变量”。
>
> 所以：**静态 CSS 里那份是被覆盖的旧值，不是第二个真源**。哔哩实渲染色是**粉**。
> 只看 CSS 文件会得出“两个家族”的错误结论（本人据此改错过一次，见 §11.2）。

平台色块/图标上的**前景**按平台硬编码在 `PlatformBrand.chipForeground`
（web `PLATFORM_BRAND_COLORS[id].fg`）—— 虎牙 / YY 这类**亮底**用深色 `#1a1a1a`，
其余用白；“全平台”是品牌金底、web 无对应条目，按同族亮底用深色。禁止改成
“按背景亮度自动算”或“统一黑 87%”：前者会在橙色上给出深色字、后者会在黄/金底上
给出低对比度白字，两者都与真源不符。

---

## 3. Typography Rules

> 本节按 `type-scale` / `line-height-grid` / `spacing-system` 三个 skill 的规则制定（已 vendor 到
> `.agents/skills/`）。核心纪律：**字号与行高都不是手挑值**——字号来自一个声明的阶梯，
> 行高来自公式并**吸附到网格**。

### 3.1 字体族

| 项 | 值 |
|---|---|
| 字体族 | `Microsoft YaHei`（`AppTypography.family`） |
| 回退链 | `Microsoft YaHei UI` → `PingFang SC` → `Noto Sans CJK SC` → `Source Han Sans SC` → `Segoe UI` |
| 接线 | `app_theme.dart` 的 `textTheme.apply(fontFamily, fontFamilyFallback)` |

### 3.2 字号阶梯（9 档，整数 px）

**整数 px 是源头，比例是推导物**。`type-scale` skill 的取整规则：先算 px、四舍五入到整数、
**最后**才推 rem（反过来先取整 rem 会累积漂移）——本项目原先的 `8.1 / 9.4 / 10.9 / 11.84 /
12.6 / 14.4` 正是“把 web 的 rem 换算值当源头”造成的。

| 档位 | px | 阶梯区段 | 用途 |
|---|---|---|---|
| `overline` | 9 | 密集段 | 全大写眉标 / 极小角标 |
| `label` | 10 | 密集段 | 角标 / 紧凑控件标签 |
| `caption` | 11 | 密集段 | 辅助说明 |
| `bodySecondary` | 12 | 密集段 | 次级正文 |
| `body` | 13 | 密集段（基准） | 正文默认 |
| `subtitle` | 14 | 密集段上界 | 卡片 / 设置项标题 |
| `title` | 16 | 标题段 | 区块标题 |
| `headline` | 18 | 标题段 | 弹窗 / 面板标题 |
| `display` | 22 | 标题段 | 页面主标题 / 大字号数字 |

**比例声明**（两段式，属 skill 允许的 “Document the choice” 情形）：

- 密集段 `9→14`：**1px 步进**（比值 ≈ 1.08）。`type-scale` 最紧预设为 1.067（minor second，
  用于 “very dense UI”），但在 9–14px 区间直接取整会两两碰撞（违反 skill 的单调性/可区分性校验），
  故显式声明为 1px 步进。
- 标题段 `14→16→18`：**1.125（major second）**；`18→22` 为 1.222（单个跳档）。
- 上限校验：最大比值 1.222 远低于 skill 给出的产品 UI 上限 1.5 ✅

**硬规则**：

- 任何 `fontSize:` 只能取 `AppFontSize` 里的 9 个数（裸字面量由守卫拦下）。
- 新增字号 = 新增阶梯档，必须先改本节 + `AppFontSize` + 契约测试，并有比例依据。

### 3.3 行高（两轨 + 网格吸附）

`line-height-grid` skill 的公式（**不是自由乘数**）：

```
lh-ui(size)    = ceil(size × 1.20) 向上吸附到网格
lh-prose(size) = ceil(size × 1.50) 向上吸附到网格
```

- **1.20 → UI 轨**：标题 / 按钮 / 标签 / 表单元信息等单行、不需要连贯阅读的文字。
- **1.50 → prose 轨**：段落正文（聊天消息、描述、长文本）；低于 1.45 会读得累。
- **网格单位取 2px**（不是 4px）。本项目 spacing 的 minor unit 是 4，但字号密集段只有 1px 步进，
  按 4px 吸附会把 11px 字号的 lh 抬到 16px（1.45×，密集行明显变肿）。skill 明确允许按密度选
  pairing（2/4、4/8、4/16），故 type grid 取 **2px**。

Flutter 的 `TextStyle.height` 是**倍数**，所以吸附后的 px 要除回字号：`height = snappedPx / fontSize`。

| 字号 | lh-ui px | `height`(UI 轨) | lh-prose px | `height`(prose 轨) |
|---|---|---|---|---|
| 9 | 12 | 1.3333 | 16 | 1.7778 |
| 10 | 12 | 1.2000 | 16 | 1.6000 |
| 11 | 14 | 1.2727 | 18 | 1.6364 |
| 12 | 16 | 1.3333 | 18 | 1.5000 |
| 13 | 16 | 1.2308 | 20 | 1.5385 |
| 14 | 18 | 1.2857 | 22 | 1.5714 |
| 16 | 20 | 1.2500 | 24 | 1.5000 |
| 18 | 22 | 1.2222 | 28 | 1.5556 |
| 22 | 28 | 1.2727 | 34 | 1.5455 |

**何时用哪轨**：问“用户会连着读多行吗？”——会（聊天 / 描述 / 正文）用 prose；
不会（标题 / 按钮 / 标签 / 表单）用 UI。

**密集单行例外**：表格行、控制条、导航项等**永不换行**的单行容器可保留 ≤1.15 的紧行高
（不吸附）——依据是 skill 的 "When NOT to use" 明确豁免 inline / 由父级掌控行高的上下文。
此类值必须记在本节下方，不得散在各文件里。

### 3.4 字重与字间距

| 项 | 值 |
|---|---|
| 字重 | 只用 `w400 / w500 / w600 / w700`；`w800 / w900` 仅用于图示字符（如角标 `√`） |
| letterSpacing | 正字间距只给**全大写 / 极小字号**（`overline +0.5`、`label +0.3`）；负字间距只给**大标题**（`headline −0.1`、`display −0.3`）；正文与密集段一律 0 |

### 3.5 文字颜色

**颜色不进 `AppTypography`**。Widget 一律用 `context.textTitle` / `textBody` /
`textSecondary` / `textCaption`（`zishu_tokens.dart` 的 `ZishuTypographyContext`），
由 `ZishuTokens` 提供颜色——写死颜色会在浅色主题下白底白字。
`AppTypography.fallbackPrimary/Secondary` 只在拿不到 `BuildContext` 时兜底。

### 3.6 收敛记录与存量

原代码共 **18 种**字号（含 `8 / 8.1 / 9.4 / 9.5 / 10.5 / 10.9 / 11.5 / 11.84 / 12.5 / 12.6 /
14.4 / 15 / 20 / 26`），已归一到本节的 9 档。映射规则：**就近取档**，两处平局按语义定档：

- `15 → 14`：与 `subtitle` 合并（两档只差 1px，无独立语义）。
- `20 → 22`：页面标题与头像首字母属 `display` 档。

尾部边界：`8 → 9`、`26 → 22`。

> 根因：web 真源自身有 **~28 种** font-size（`.52rem`=8.32px 到 `2.4rem`=38.4px，精度到
> 0.01rem）。**“字号数量收敛”是对 web 的有意偏离**，已登记到 §10。

---

## 4. Component Stylings

### 4.1 共享组件清单

| 位置 | 内容 |
|---|---|
| `lib/src/shared/presentation/widgets/` | `async_value_view`、`compact_switch`、`cover_badges`、`empty_view`、`error_view`、`platform_badge`、`platform_icon`、`retry_button`、`section_header`、`settings_slider_row`、`state_dot`、`translated_text`（+ `widgets.dart` 汇总导出） |
| `lib/src/app/shell/` | `bottom_nav`、`category_flyout`、`follow_avatars`、`hover_overlay`、`my_category_flyout`、`platform_strip`、`theme_actions`、`top_nav`、`user_area` |
| 页面 | `features/*/views/`：`home_view`、`category_view`、`follow_view`、`play_view`、`search_view`、`anchor_view`、`timeline_view`、`settings_view`、`user_credentials_view`、`parse_benchmark_view` |

### 4.2 状态矩阵

#### 底色（表面）状态

| 状态 | 颜色来源 | 形态 |
|---|---|---|
| default | `surface` / `surfaceSoft` 底，`border` 描边 | 圆角 `AppRadius.sm`(4) 或 `md`(8) |
| hover（**底色**） | **按组件语义取，不是统一“抬升”**：导航品牌块压暗到 `surfaceSoft`（web `--bg-soft` `#141414`）、卡片/浮层抬到 `surfaceRaised`（web `--dark-6` `#2A2A2A`）、导航项 web 真源是**文字变琥珀**（`.nav-brand:hover{background:var(--bg-soft)}` / `.nav-item:hover{color:var(--amber)}`）；动效 `AppMotion.fast`(150ms) + `AppMotion.curve` | 颜色/边框过渡，**不位移、不缩放**（2026-09-21 裁决）；<br>2026-09-22 氛围分支 `ui/ambient-polish` 修订：清单 2.1 卡片 hover 允许 translateY(−2px) + `AmbientGlow.cardHover`，覆盖本条「不位移」条款，限定用于 `RoomCard` / `AnchorLiveCard` / `FollowEntryCard` / `PlayRoomCard` |
| active / pressed | 在 hover 基础上再压一档（如 `playFollowBgActive`） | 仍不位移 |
| selected | `accent.withValues(alpha: 0.2)` 底（见 `app_theme.dart` 的 `navigationBarTheme.indicatorColor`）；平台/分类选中另加 `AppElevation.accentGlow` | — |
| disabled | `textSecondary` 文字 + 不响应指针；不额外加灰罩 | — |
| invalid | `error` = `#E55050` 描边 / 文字 | — |

#### 焦点态：**一律用强调色**

两种写法，同一条原则（focus 必须是 accent，不用“只比常态亮一点”的表面色）：

| 控件类型 | 写法 |
|---|---|
| Material 系（`InkWell` / `IconButton` / `TextButton` …） | `focusColor: AppStateLayer.focusOf(accent)` |
| 自绘容器（自绘 chip / 开关等） | `FocusableActionDetector` / `FocusNode` + 聚焦时 `boxShadow: AppFocus.ring(accent)`（外扩、不占布局、不改尺寸） |

> **为何不整 `surfaceRaised`**：浅色主题下它与常态几乎无差别，键盘用户看不出焦点在哪。
> 自绘控件用外扩环是因为 `focusColor` 对非 Material 容器无效 —— 两种写法存在的原因在此。
> 本项已落地（2026-09-21）：组件层 `AppFocus.ring` 引用 0 → 12，focus 处理 0 → 48。

#### 交互叠加层：`AppStateLayer` 是唯一数值来源

`InkWell` 的 `splashColor` / `highlightColor`、Material 的 `overlayColor`、自绘容器的
hover/pressed 补色一律取 `AppStateLayer`（`design_tokens.dart`），**不再手写 alpha**：

| 角色 | alpha | 取色 |
|---|---|---|
| hover | 0.10 | `AppStateLayer.hoverOf(base)` |
| 涟漪 splash | 0.12 | `AppStateLayer.splashOf(base)` |
| 按下 pressed | 0.16 | `AppStateLayer.pressedOf(base)` |
| 焦点 focus | 0.24 | `AppStateLayer.focusOf(base)` |

`base` 是**叠加的基色**，由调用方给：普通控件用 `accent`；**on-video 控件用
`AppOnVideo.text`**（不能换成随主题切换的 token，否则浅色主题下会在暗底上叠深色）；
亮饱和底（如自绘的已关注 chip）用**该 chip 自身的前景色**（`button-states` 的“状态色由基色推导”）。

两条派生规则：

- **已经处在抬升面（`surfaceRaised`）上的元素 hover 时不能再“抬亮”**，退回
  `AppStateLayer.hoverOf(accent)` 的强调色淡层，否则“越 hover 越看不出”。
- **`overlayColor` 逐态值只能走 `.copyWith`**：`TextButton.styleFrom(...)` 等同名参数
  类型是 `Color?`（单个颜色），不收 `WidgetStateProperty`。

#### 不做全局按钮主题（实测结论）

**不要**在 `app_theme.dart` 里加 `textButtonTheme` / `iconButtonTheme` /
`segmentedButtonTheme` 等来“统一交互态”。`colorScheme.primary = tokens.accent`
已经让 M3 默认样式从 accent 派生出同量级的 state layer；而显式加 theme `style`
**并非只覆盖指定字段** —— 2026-09-21 实测：只给 `segmentedButtonTheme` 加
`overlayColor`，结果破坏了 `SegmentedButton` 的 **rest 渲染**（`follow_style_row`
golden 差 2074px，整块底色/描边都变）。需要更明显的交互态时，**在调用点**用
`AppStateLayer.*Of(...)` 显式化。

#### 控制条等 `PopupMenuButton` 的内部 InkWell

`PopupMenuButton(child:)` 的内部 `InkWell` 不暴露颜色参数，只能从 **Theme 层**切墨色
（`player_controls.dart` 的 `_onVideoInkTheme` / `_onVideoButtonStyle` 就是为此）。
这属于“只能从 Theme 层接线”的已知例外，与本节的“不要加全局按钮主题”不矛盾：
前者是 **on-video 局部子树**的 Theme 覆盖，不是全局主题。

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
| `AmbientMotion`（氛围轨） | `pageTransition 180ms` / `pulse 1.6s`（循环） / `shimmer 1.4s`（循环）；easing 复用 `AppMotion.curve`（不新造）；`reduce_motion` 降级一律走 `AmbientMotion.of(context)`（`MediaQuery.disableAnimations == true` 时返回零时长/静态档），禁止在 Widget 里散写 `Duration(...)` 裸时长 |

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

> 口径：本表记录的是 **web 真源里的例外值**（包括 `5.76` 这种从未落到 Flutter 的死条目），
> 加上 Flutter 侧自有的例外（如 `AppSpacing.xxl = 28`）。想知道某项是否真的在 Flutter 代码里生效，
> 必须 grep 具体数值，不要只看本表。

新增间距一律取 `AppSpacing` 已有档；确需例外必须在提交说明里写明并与本表同步登记。

---

## 6. Depth & Elevation

投影四档，定义在 `AppElevation`（`design_tokens.dart`）。数值从原先散落的裸 `BoxShadow`
逐字搬家而来，**不得改动数值**，否则 golden 会漂。

氛围轨（`ui/ambient-polish` 清单 §1）另有 **`AmbientGlow` 三档**（同在
`design_tokens.dart`），是 accent 派生的**外发光**而非投影。两组共七档一表登记
（`AmbientGlow` 行的格式仿 `accentGlow` 行）：

| 档位 | 值 | 语义 |
|---|---|---|
| `AppElevation.popover` | 黑 24%、blur 16、y+4 | 下拉菜单 / flyout 浮层 |
| `AppElevation.hairline` | 黑 35%、blur 0、spread 1 | on-video 控件贴边 1px 描边 |
| `AppElevation.sheet` | 黑 55%、blur 28、x−6 | 沉浸模式侧滑面板向左投射 |
| `AppElevation.accentGlow(accent)` | 强调色 22%、blur 8、y+2 | 平台 / 分类**选中态与 hover 态**光晕（同一语义：强调色外发光，不新增档位） |
| `AmbientGlow.cardHover(accent)` | 强调色 18%、blur 12 | 卡片 hover 发光（清单 2.1，氛围 hover 轨专用） |
| `AmbientGlow.ctaSheen(accent)` | 强调色 24%、blur 16 | 主 CTA 流光 / 呼吸描边（清单 2.2） |
| `AmbientGlow.halo(accent)` | 强调色 8%、blur 64 | 播放器外圈氛围光晕（清单 3.3） |

原则：

- **阴影/发光只用这七档**（`AppElevation` 四档 + `AmbientGlow` 三档），禁止在 Widget 里新写 `BoxShadow(...)`（守卫脚本会拦）；发光一律经 `AmbientGlow.*` helper 由 accent 派生。
- 毛玻璃 `BackdropFilter` 的 sigma 上限 `AmbientBlur.maxSigma = 20`（Windows 性能约束），**超限即违规**；具体用点的 sigma 必须 ≤ 本值且取自 token。
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
- ❌ 给按钮加**按压位移/缩放**（press scale）做反馈（2026-09-21 裁决禁止）：按钮反馈只走颜色 / 描边 / 阴影 / 图标，不做位移与缩放。<br>2026-09-22 氛围分支 `ui/ambient-polish` 修订（清单 2.5）：仅主 CTA `FollowButton` / `player_controls.dart` 的 `play-toggle-play` 允许 pressed 缩放 0.97，与 `AppStateLayer` 叠加，其余按钮仍禁止。
- ❌ 把平台色的两个家族混用（`accentColor` 用于图标/tab，`color` 用于角标/chip）；也禁止把平台 `chipForeground` 换成“按亮度自动算”或“统一黑 87%”（见 §2.3）。
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
| 6 | 窄屏底栏文字标签 | `responsive-chrome.css:231-233`：phone+portrait 下隐藏 `.nav-label` 与 `.nav-brand__name`，只留图标 | zishu 用 `FittedBox scaleDown` 压缩显示「我的分类」等 4 字标签 | **已裁决 2026-09-21：保留现状**。理由：它与顶栏（`NavSidebar` 窄屏收缩）属同一类“chrome 信息密度”问题，单改底栏会造成顶/底栏口径不一致；延后到「断点/壳层专项」一并处理（需重算槽位宽 + 重抓 mobile golden） | 2026-09-21 |

| 7 | 统计项缺值显示 | web `utils/browse/platformRoomStats.ts` 的 `statDisplay`：空值显示**「0」** | zishu 显示**「—」** | 数据诚实性：不伪造未取得的数值（用户口径） | 2026-09-21 |
| 8 | 统计项**有无底色** | 真播放页统计行（`SideHeader.vue` 的 `.room-stat-icon-row--*` / `.room-stat-data-line--*`）**无任何背景规则**；`--play-stat-*-bg` 的唯一消费者是 dev 徽章目录页 `apps/web/public/dev/badge-catalog.html` 的 `.play-stat-item--*` 芯片 | zishu 统计行同样无底色 | **本行已于 2026-09-21 作废**：原先我把它当成缺口（“web 有底色 chip，zishu 未实现”）是错的，底色属 dev demo 而非产品面；参见 §11.2 | 2026-09-21 |
| 9 | 字号总数 | web 真源自身有 **~28 种** font-size（`.52rem`=8.32px 到 `2.4rem`=38.4px，精度 0.01rem） | **9 档**整数 px 阶梯（`AppFontSize`），且行高按 `line-height-grid` 公式取整吸附 | 收敛字号数量、消除 0.5px 级散值；参见 §3.2/§3.6 | 2026-09-21 |
| 10 | 行高取值 | web 用无单位乘数散写（1 / 1.2 / 1.15 / 1.35 / 1.08 … 共 13 种） | 两轨公式（UI ×1.20 / prose ×1.50）吸附到 2px 网格，Flutter 侧以 `height = snappedPx / fontSize` 表达 | 让行高可推导、可校验；参见 §3.3 | 2026-09-21 |
| 11 | 紧前景色分组 | web 无对应常量 | 新增 `AppOnBright`（在 accent/brand/平台色这类**亮饱和底**上的前景：`glyph`/`text`/`white`），与 `AppOnVideo` 对称；两者都是**主题无关**常量 | 亮饱和底由品牌/平台决定、不随主题变；而深/浅底上的前景（`textPrimary` 等）必须走 `ZishuTokens` | 2026-09-21 |
| 12 | 轮播强调色 / 模态遮罩 | web 独立变量 `#f5dc70`（`.nav-item:hover` 的 `--amber`）与遮罩色 | 新增主题字段 `ZishuTokens.brandBright`（深 `#F5DC70` / 浅 `#9A7B1A`）与 `barrier`（深 `0x73000000` / 浅 `0x4D000000`） | 必须随主题切换：亮金与重遮罩在浅底上不可读/压灰；浅色取值为估算值，待 a11y 轨复核 | 2026-09-21 |

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
| T4 手机底栏项数 | “真源 6 项（紫薯 logo/首页/分类/关注/搜索/我的）”，且要求删「主题」 | ⚠️ 看板两行都错：`NavSidebar.vue` 实际是 **8 项**（品牌/首页/分类/我的分类/我的关注/搜索/切换主题/账号·登录），既有「主题」也有「我的分类」；`ui-reference/README.md:44` 的 6 项列表漏了「品牌」与「账号」 | 只移除 zishu 自加的 `nav-time`（动态）；真源根本没有该项 |
| T4 补充：360px 是否隐藏「我的分类」 | lane 据截图推断“360px 真源隐藏它，只剩 7 项” | ❌ 不成立。`nav-my-cat-wrap` 无任何 `display:none` 规则；`responsive-chrome.css:231-233` 只隐藏**文字标签**；`360x640_mobile_home.png` 实测仍是 **8 个图标** | 不改（无差异）；真正的差异是“窄屏是否显示标签”，已记入 §10 |

教训：**看板不是真源**。裁决前必须回到 `SFVideoLive/apps/web/src` 的 CSS/模板原文或官方截图，
中介文档（看板、实测笔记）只能当线索。这条已写入 `AGENTS.md` 的视觉真源一节。

### 11.2 规范本身也会写错（两处已作废）

同一个风险的**第三种形态**：不是代码漂移、也不是看板写错，而是**本规范作者自己写错的条目**。
两条都已被执行轨举证推翻，记录在案，以防后人照着错的规范去“修”代码：

| 已作废条目 | 我（规范）的原文 | 复核结果（web 出处） | 处置 |
|---|---|---|---|
| §10 第 8 条「统计项无底色」 | 断言 web 有 `--play-stat-{audience,vip,svip}-bg` 用在统计行，zishu 未实现 | ❌ 这两个变量只在 `styles/theme.css:36-41,129-134` **定义**；全仓唯一消费者是 dev 徽章目录页 `apps/web/public/dev/badge-catalog.html` 的 `.play-stat-item--*` 芯片。真播放页 `SideHeader.vue` 的 `.room-stat-icon-row--*` / `.room-stat-data-line--*` **无任何背景规则** | 条目作废；zishu 不加底色才是对齐真源 |
| §4.2 hover 规则 | 「hover 底色抬到 `surfaceRaised`」 | ❌ 过度概括。web `.nav-brand:hover{background:var(--bg-soft)}`（`#141414`，**更暗**）、`.nav-item:hover{color:var(--amber)}`（**文字变琥珀**，不是底色）、`--dark-6` `#2A2A2A` 用于卡片/浮层 | 规则改为“按组件语义取”，并补记导航项文字变色 |
| §2.3 平台色家族 | 断言“web 有两个平台色真源家族（CSS 变量 vs platformCatalog），哔哩图标用蓝、角标用粉” | ❌ **只有一个真源**。`main.js:57` 的 `initPlatformBrandVars()` 把 platformCatalog 的 `bg` 内联注入 `:root`，**覆盖**了 theme.css/main.css 的静态同名变量；哔哩的蓝 `#00a1d6` 是被覆盖的**旧值**（注入代码自己的注释就写着“覆盖…旧 4 个平台的同名变量”） | 撑回 `accentColor` 字段与三处调用（四象限、tab 光晕）；哔哩恢复**粉 `#fb7299`**；规则改为“单一真源 + 静态 CSS 是被覆盖的旧值” |

教训：**规范作者也会错**。所以“代码与规范不一致”时两种可能都要查——可能是代码漂了，
也可能是**规范写错了**。上面第二条就差点导致把已经对齐真源的顶栏 hover 改坏
（与 T2/T3 同型：都是在“修改”的旗号下把对的改成错的）。

---

## 12. 已登记的未实现项（勿当 bug 重复报）

### 12.1 播放侧栏统计第 3 列（tone = svip）全平台未实现

web 真源 `config/platformCatalog.ts` 的 `ROOM_STAT_COLUMNS` 为**每个平台**配置 2–3 个统计列，
第 3 列的 `tone` 恒为 `svip`，但**各平台语义不同**（所以它不是一个“SVIP 字段”）：

| 平台 | 列1 (audience) | 列2 (vip) | 列3 (tone=**svip**) | zishu 状态 |
|---|---|---|---|---|
| douyu | online 观众 | vip 贵宾 | **diamondFans 钻粉** | ❌ 无字段/无取数/无 UI |
| huya | online 观众 | vip 贵宾 | **diamondFans 超粉** | ❌ 同上（web 走 `wupui/getSuperFansInfo`） |
| douyin | online 观众 | fanGroup 粉丝团 | **vip 会员** | ❌ 第3列缺；且 zishu 把「会员」放进 `vip` 槽 → **列错位** |
| bilibili | online 观众 | fanGroup 粉丝勋章 | **guard 大航海** | ❌ 第3列缺 |
| xhs / youtube / soop | online | — | — | ✅（本就 1–2 列） |

- **数据模型**：`RoomSummary` 只有 `followers` / `online` / `vip`，没有第 3 列字段，
  也没有 web `PlatformRoomStats` 的 `diamondFans` / `fanGroup` / `guard` 三个字段。
- **UI**：`side_panel_header.dart` 只渲染 2 个 `_StatValue`（人气 + VIP）；移动端
  `play_meta_bar.dart` 是另一套四格（关注/开播/人气/弹幕），与此无关。
- **结论**：4 个平台的第 3 统计列全部不显示。这是“好多 SVIP 没显示”的**根因**，
  属**未实现**，不是回归（`git log -S statSvip` 显示只动过 token，从未接过 UI）。
- **死代码提醒**：`ZishuTokens.statSvip`（深/浅两套）与 `AppColors.playStatSvipText`
  已定义但**零引用**。接线前不要删，也不要误以为已实现。
- **修复范围**：① 数据模型按 web 形态扩展（已完成：`RoomSummary.diamondFans`）；
  ② 各平台取数（虎牙已实现并真机验证；douyu 钻粉 / douyin 会员 / bilibili 大航海待做）；
  ③ 第 3 列 UI（已完成：`side_panel_header.dart` 的第三个 `_StatValue`，色取 `statSvip`，无值显示「—」）。
- **不要加底色**：原先本节写的“③ 第 3 列 UI + `playStat*Bg` 底色”已作废——
  `--play-stat-*-bg` 只服务于 dev 徽章目录页，真播放页统计行无背景（见 §10 第 8 条、§11.2）。
- 取数口径证据：`packages/live_parser/lib/src/platforms/huya/huya_wup.dart:27`
  明确写着“本轮未实现，RoomSummary 无对应字段”。

### 12.2 Web 端外链打开为桩实现

`lib/src/platforms/common/open_external_url_stub.dart` 恒返回 `false`（Web 优先级靠后，
有意如此；文件内注释已说明）。Windows/Android 走各自的真实实现。

---

## 13. 验收与像素回归网

本节的规则是“改 UI 后必须跑什么”的唯一口径（配合 §9 的提示词使用）。

### 13.1 命令

```bash
flutter analyze                                    # 必须 0 issue
dart run tool/check_design_tokens.dart             # 裸值守卫，基线只允许下降
flutter test                                       # 全量（含 golden）
flutter build windows --debug -t lib/main.dart      # 主链路改动时
```

`tool/check.ps1` 把前三步（加上三个包的 `pub get` 与 legacy web 构建）串成一次性门禁。

### 13.2 golden 是正式回归网（2026-09-21 裁决）

`test/ui/follow_style_shot_test.dart` 与 `test/ui/hover_shot_test.dart` 产出全库
**仅有的 7 张 golden**（`test/ui/*.png`）。它们是改视觉时唯一能拦住“悄悄改坏像素”
的机械防线——2026-09-21 两轮共抓到 13 处真实像素变化。

- **不要删除**这两个用例（`hover_shot_test.dart` 旧注释里“生成后即删除”已作废）。
- 更新基线的**强制流程**：先 `read` 打开 `test/ui/failures/*_isolatedDiff.png` /
  `*_testImage.png` **实际看差异**，确认差异就是本次有意改动，再 `--update-goldens`。
  看不懂的差异**不要更新**，报出来。
- 注意 golden 环境的限制：VM 无中文字体（渲染为方块）、网络图被拦成占位块，
  所以 golden 校验的是**结构与间距**，不是文字内容。
- `test/ui/failures/` 是失败产物，**不要提交**（已确认其为 git 跟踪的历史遗留，
  改动只会产生噪音）。
