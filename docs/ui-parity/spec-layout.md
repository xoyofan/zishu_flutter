# SFVideoLive Web → zishu_flutter 布局几何规格（spec-layout）

> 视觉真源已收敛到项目根 `DESIGN.md`；本文是推导来源与证据链，冲突时以 `DESIGN.md` 为准。

> 抽取范围：SFVideoLive `web` 前端的**可量化布局几何**规格，用于 Flutter（Windows 优先）1:1 复刻。
> 口径：仅记录源码中明确写出的数值；推断值标注「推断」并给依据；源码未声明写「未声明」。
> rem 默认根字号 16px（1rem = 16px），4pt 栅格判定基准为 4/8/12/16/20/24/32px。
> 参考实现分支 `feat/flutter-native-windows`。

---

## 1. 全局骨架

页面骨架由 `AppLayout.vue` + `main.css` 的 `:root` 令牌定义。桌面端导航为**顶部 sticky 条**（非左侧栏），左侧仅 `directory-rail`/`directory-drawer` 用于分类抽屉（仅首页类路由）。

| 项 | 值 | 来源(文件:行) | 备注 |
|---|---|---|---|
| 应用根高度 | `100dvh`（回退 `100vh`） | main.css:52-53 | 经 `--app-height` |
| 导航条高度（令牌 nav-height） | `56px` | main.css:17 | 移动/窄屏默认 |
| 导航条高度（≥768px 覆盖） | `44px` | main.css:223 | 桌面顶栏高度 |
| 导航栏合成高度 nav-chrome-height | `calc(nav-height + nav-safe-bottom)` | main.css:38 | 移动端 |
| 导航栏合成高度（≥768px） | `calc(nav-height + nav-safe-top)` | main.css:224 | 桌面端 |
| 顶栏安全区 nav-safe-top | `env(safe-area-inset-top, 0px)` | main.css:18 | 手机竖屏覆盖为 `max(env(safe-area-inset-top,0px), 28px)`（responsive-chrome.css:97） |
| 内容区左右内边距 --app-main-pad-x | `0.85rem`（≈13.6px） | main.css:51 | 非播放页 |
| 内容区上下内边距 | `0 var(--app-main-pad-x) var(--nav-chrome-height)` | AppLayout.vue:135 | 底部留白=导航栏高度（避让底栏） |
| 内容区最大宽度 | 未声明 | — | 全宽布局，仅受 `--app-main-pad-x` 约束，无居中 max-width 包裹 |
| 内容区是否居中 | 否 | AppLayout.vue:127-136 | 全宽填充，无 `margin:auto` |
| 桌面首页左留白（抽屉收起） | `margin-left: var(--directory-rail-width)` = `52px` | AppLayout.vue:216, main.css:39 | 仅 `app-main--home-drawer` |
| 桌面首页左留白（抽屉展开） | `margin-left: var(--directory-drawer-width)` = `220px` | AppLayout.vue:220, main.css:40 | |
| 播放页内容区内边距 | `padding: 0 0 0`（左右底归零，`--app-main-pad-x:0`） | AppLayout.vue:166-171 | 播放页自行管理 |
| 房间卡片栅格列数（桌面 1920 档） | `--room-grid-cols-wide: 6`（抽屉开→5） | AppLayout.vue:117,122-125 | 仅控制 1920+ 档 |
| 房间卡片栅格列数（≥2560 档） | `--room-grid-cols-wide-extra: 7`（抽屉开→6） | AppLayout.vue:119,122-125 | |
| 顶栏 logo 尺寸 | `28px`（移动）/ `30px`（≥768） | NavSidebar.vue:508-514,767-770 | |
| 品牌名字号 | `.88rem` 隐藏 / `1.02rem`（≥768 显示） | NavSidebar.vue:516-522,772-775 | |
| 平台条高度令牌 | `calc(var(--nav-safe-top) + 3.25rem)` | main.css:218 | 见 §分类页/响应式 |

> 说明：`--nav-width: 70px`（main.css:16）已定义但当前布局未作为左侧栏宽度使用（桌面导航改为顶栏），列为遗留令牌。

---

## 2. 首页（HomeView + RoomGrid + RoomCard）

房间栅格 `RoomGrid.vue` 用固定列数媒体查询（非 `auto-fill`）。

| 项 | 值 | 来源(文件:行) | 备注 |
|---|---|---|---|
| 栅格 display | `grid` | RoomGrid.vue:117 | |
| 栅格行/列间距 | 行 `0.85rem`（≈13.6px）/ 列 `1rem`（16px） | RoomGrid.vue:118 | 列间距落在 4pt 栅格；行间距不在 |
| 栅格左右内边距 | `0 0.35rem 0.35rem`（列内边距≈5.6px） | RoomGrid.vue:119 | |
| 默认列数（<640） | `repeat(2, minmax(0,1fr))` | RoomGrid.vue:120 | |
| ≥640 列数 | `repeat(3, …)` | RoomGrid.vue:125 | |
| ≥768 列数 | `repeat(4, …)` | RoomGrid.vue:131 | |
| ≥1024 列数 | `repeat(5, …)` | RoomGrid.vue:137 | |
| ≥1536 列数 | `repeat(6, …)` | RoomGrid.vue:143 | |
| ≥1920 列数 | `repeat(var(--room-grid-cols-wide,6), …)` | RoomGrid.vue:149 | =6（抽屉开 5） |
| ≥2560 列数 | `repeat(var(--room-grid-cols-wide-extra,7), …)` | RoomGrid.vue:155 | =7（抽屉开 6） |
| 卡片封面宽高比 | `16 / 9` | RoomCard.vue:195 | 默认 |
| 卡片封面宽高比（抖音首页） | `311 / 233` | RoomCard.vue:201 | 抖音特化 |
| 卡片整体边框 | `2px solid transparent` | RoomCard.vue:171 | 选中/直播/录播改色 |
| 卡片内边距（body） | `6px 8px 8px` | RoomCard.vue:299 | |
| 标题区高度/截断 | 字号 `0.9rem`，行高 `1.35`，单行 `nowrap`+省略 | RoomCard.vue:302-309 | 单行截断 |
| 元信息行上间距 | `4px`，内部 `gap 6px` | RoomCard.vue:316-322 | |
| 主播名字号 | `0.78rem`（≈12.5px）行高 `1.2` | RoomCard.vue:324-333 | 单行省略 |
| 标签字号/内边距 | `0.64rem`，`1px 5px`，圆角 `3px` | RoomCard.vue:342-352 | |
| 直播/录播角标圆角 | `0 0 8px 0` | RoomCard.vue:251 | 左上贴角 |
| 分类角标最大宽 | `70%` | RoomCard.vue:257 | |
| 封面 bottom-left 角标最大宽 | `72%`，圆角 `0 8px 0 0` | RoomCard.vue:262-273 | |
| 选中勾尺寸 | `20×20px`，圆角 `4px`，距顶/右 `6px` | RoomCard.vue:224-234 | |
| 离线遮罩内边距/字号 | `6px 8px`，`13px` | RoomCard.vue:284-296 | |
| 卡片 hover 行为 | 未声明显式位移/缩放 | RoomCard.vue:7 `shadow="hover"` | 仅 Element Plus 默认 hover 阴影，无位移/scale |
| 进入房间直输页最大宽 | `28rem` 居中 `margin:2rem auto` | HomeView.vue:180-181 | 仅「无推荐列表平台」直输页，非常规网格 |

> 注意：Flutter `room_grid.dart` 注释称对齐 `repeat(auto-fill, minmax(240px,1fr))`，但**实际 web 用固定列数断点**，且 `maxCardWidth=280`、间距 `AppSpacing.md=12px`；与 web 的 `0.85rem×1rem` 间距不一致——复刻需二选一对齐（见 §Flutter 映射）。

---

## 3. 分类页（Category）

分类页无独立卡片网格（复用 RoomGrid），重点在平台/分组 Tab 与页面内边距。

| 项 | 值 | 来源(文件:行) | 备注 |
|---|---|---|---|
| 分类页主区滚动 | `overflow-y:auto; overflow-x:hidden; overscroll-behavior:contain` | category-page.css:3-9 | |
| 分组 Tab 上外边距 | `0.72rem` | category-page.css:32-34 | |
| 平台 Tab 头部隐藏时 body 上内边距 | `0.52rem` | category-page.css:36-38 | |
| 平台 Tab nav-wrap 下内边距 | `0.28rem` | category-page.css:40-42 | |
| 分组 Tab nav-wrap 上下内边距 | `0.12rem` | category-page.css:44-47 | |
| 分组项最小高度 | `1.35rem`，行高 `1.1` | category-page.css:49-55 | |
| 内容区最大宽度 | 未声明 | — | 同首页全宽 |
| 内容区居中 | 否 | AppLayout.vue | |

---

## 4. 关注页（FollowView + FollowRoomTileView）

关注页列表使用「page-tile」卡片网格（宽屏/平板）或行列表（窄屏），列数由 JS 按 `300–400px` 列宽推算。

| 项 | 值 | 来源(文件:行) | 备注 |
|---|---|---|---|
| page-tile 卡片最小高度 | `5.28rem`（≈84.5px） | main.css:31, FollowRoomTileView.vue:777,792 | |
| page-tile 列宽下限 | `300px` | main.css:28 | `--follow-page-tile-col-floor` |
| page-tile 列宽上限 | `400px` | main.css:27 | `--follow-page-tile-col-max` |
| page-tile 列间距 | `0.28rem`（≈4.48px） | main.css:30 | `--follow-page-tile-col-gap` |
| page-tile 列表左右内边距 | `0.5rem` | main.css:29 | `--follow-page-tile-list-pad-x` |
| page-tile 头像尺寸 | `70px` | main.css:32, FollowRoomTileView.vue:755 | |
| page-tile 头像顶部偏移 | `0.38rem` | main.css:33 | |
| page-tile 第一行高度 | `1.05rem` | main.css:34 | |
| page-tile 底栏高度 | `1.28rem` | main.css:35 | |
| page-tile 标题字号 | `0.8125rem` | main.css:36 | |
| page-tile 元信息 chip 高度 | `1.34rem` | main.css:37 | |
| 侧栏 tile 网格（默认） | `repeat(2, minmax(0,1fr))` | FollowRoomTileView.vue:691-700 | gap `.32rem .28rem`，padding `.32rem .36rem .45rem` |
| 侧栏 tile 网格（容器≥400px） | `repeat(4, …)` | FollowRoomTileView.vue:702-706 | `@container follow-sidebar-list (min-width:400px)` |
| 侧栏 page-tile 网格 | `repeat(var(--tile-page-col-count,2), …)`，`grid-auto-rows: minmax(min-h,auto)` | FollowRoomTileView.vue:708-719 | 列数 JS 计算（300–400px 约束） |
| page-tile 卡片圆角 | `var(--fluent-radius-sm)` = `8px` | FollowRoomTileView.vue:742 | |
| page-tile body 内边距 | `0.22rem 0.28rem 0.16rem` | FollowRoomTileView.vue:793 | |
| page-tile 底栏最小高/内边距 | `min-height:1.28rem`，`padding .14rem .22rem .16rem` | FollowRoomTileView.vue:920-922 | |
| 非 page-tile 卡片最小高 | `4.25rem`，`padding .18rem .22rem .14rem` | FollowRoomTileView.vue:948-963 | |
| 关注标题字号 | `0.75rem` 行高 `1.25`（单行省略） | FollowRoomTileView.vue:509-516 | |
| 平台标签字号/内边距 | `0.52rem`，`0.16rem 0.28rem`，圆角 `4px` | FollowRoomTileView.vue:384-394 | |
| 卡片 hover | `filter: brightness(1.08)` | FollowRoomTileView.vue:418-420 | 无位移/缩放 |
| 行列表列宽 | `300–400px/列` | main.css:22-24 | `--follow-row-col-floor/max`，gap `0.28rem` |
| 行列表左右内边距 | `0.5rem` | main.css:25 | |
| 关注页容器 | `max-width: none`; 部分区块 `justify-content:center` | FollowView.vue:280,298 | 网格容器居中但其内容全宽 |

---

## 5. 播放页（PlayView + play-layout.css + PlayerControls）

播放页由 `play-layout`（main + side）与覆盖式控制条组成。侧栏宽度令牌 `--play-sidebar-width`。

| 项 | 值 | 来源(文件:行) | 备注 |
|---|---|---|---|
| 侧栏宽（并排，默认） | `328px` | main.css:46 | `--play-sidebar-width` |
| 侧栏宽（≤767px，窄并排） | `268px` | main.css:231 | |
| 侧栏宽（1600–1919） | `392px` | main.css:237 | |
| 侧栏宽（≥1920） | `425px` | main.css:243 | |
| 堆叠态侧栏宽 | `100%`（覆盖变量） | main.css:43-44 注释 | stack 下 `.play-side--stack` width:100% |
| 视频区:侧栏关系 | 并排 `flex-direction:row`；堆叠 `column` | play-layout.css:13-27 | |
| 并排阈值 | `@media (min-width:1024px)` 且非 stack；或 `@media (min-width:768px) and (orientation:landscape)` 且非 stack | play-layout.css:13-43 | 复合：宽度+方向+非 stack |
| 堆叠态视频高（≤1024） | `aspect-ratio:16/9`，`width:100%` | play-layout.css:57-65 | |
| 堆叠态视频高（≤1024 横屏） | `max-height: min(56vh, calc(100vw*9/16))` | play-layout.css:68-71 | |
| 堆叠态侧栏最小高（≤1024 横屏） | `min(38vh, 20rem)` | play-layout.css:73-75 | |
| 视频舞台圆角（常规） | `border-radius:12px` | play-layout.css:92 | |
| 视频舞台圆角（≤640 或全屏） | `0` | play-layout.css:199,122 | |
| 视频区 aspect-ratio | `16 / 9` | play-layout.css:179 | `.video-shell` |
| 全屏态差异 | `flex-direction:row!important`，`border-radius:0`，`aspect-ratio:unset`，`max-height:none` | play-layout.css:105-133,135-174 | |
| 房间头高（Flutter 侧已实现） | `44px` | play_view.dart:164-165 | 对齐 web 顶栏 44px |
| 控制条容器 padding（常规） | `.player-controls` `0.35rem 0.5rem 0.5rem` | PlayerControls.vue:495 | |
| 控制条 `.controls-bar` padding | `0.28rem 0.65rem`，底 `max(.22rem, env(safe-area-inset-bottom))` | PlayerControls.vue:522-523 | |
| 控制条最大高 | `3.1rem`（≈49.6px）；全屏 `none` | PlayerControls.vue:526,843-846 | |
| 控制条按钮尺寸 | `height 2.55rem / min-width 2.55rem`，`padding 0 0.55rem`，字号 `0.92rem` | PlayerControls.vue:550-557 | |
| 控制条图标字号 | `1.38rem`（--ctrl-icon-size） | PlayerControls.vue:517,639 | |
| 音量条尺寸 | `96×22px`，轨道高 `4px`，滑块 `14px` | PlayerControls.vue:599-628 | |
| 窄视频区（容器≤680px）控制条 | padding `.28rem .4rem`，max-h `3rem`，按钮 `2.25×2.1rem` 字号 `0.8rem` | PlayerControls.vue:696-750 | `@container video (max-width:680px)` |
| 极窄视频区（容器≤420px）控制条 | padding `.2rem .22rem`，max-h `2.65rem`，按钮 `1.95×1.72rem` 字号 `0.74rem` | PlayerControls.vue:845-895 | `@container video (max-width:420px)` |
| 音量条（窄） | `52×18px`（≤680）/ `48×16px`（≤420） | PlayerControls.vue:764-770,915-921 | |
| 移动底部 sheet | `max-width:32rem`，`max-height:min(70vh,28rem)` | PlayerControls.vue:798-807 | |
| 抽屉开关按钮尺寸 | `width:1.15rem`（≈18.4px），`height:40px`，圆角 `var(--drawer-toggle-radius)=8px` | main.css:47-50, play.css:52-57 | |
| 沉浸侧栏抽屉宽 | `var(--play-sidebar-width,320px)`；手机 `min(侧栏宽,88vw)` | play.css:158-164 | `play-immersive-side__drawer` |

> 堆叠判定（复合）见 §6 断点矩阵；`play-layout--stack` 类由 `matchesPlayStackLayout()` 注入。

---

## 6. 断点矩阵与复合条件

断点常量（`breakpoints.ts:3-8`）：`BP_COMPACT=640`、`BP_MOBILE=768`、`BP_PLAY_STACK=1024`、`BP_FOLLOW_PAGE_TILE_MAX=1366`、`BP_WIDE=1920`。

| 断点/条件 | 布局切换 | 来源 | 备注 |
|---|---|---|---|
| `≤640` (BP_COMPACT) | 房间网格 2 列；播放框圆角 0 | RoomGrid.vue:120, play-layout.css:198-200 | |
| `≥640` | 房间网格 3 列 | RoomGrid.vue:123-127 | |
| `≥768` (BP_MOBILE) | 房间网格 4 列；导航变顶栏 `44px`；app-main 仅左右内边距 | RoomGrid.vue:129-133, main.css:221-226, NavSidebar.vue:729-742, AppLayout.vue:201-214 | |
| `≥768` 且横屏 | 播放页并排（非 stack） | play-layout.css:29-43 | 复合：宽度+横屏+非 stack |
| `≤767` | 侧栏宽降至 `268px` | main.css:228-233 | |
| `≥1024` (BP_PLAY_STACK) | 房间网格 5 列；播放页并排（非 stack） | RoomGrid.vue:135-139, play-layout.css:13-27 | |
| `≤1024`（堆叠） | 侧栏 tile 网格 `repeat(auto-fill, minmax(min(100%,var(--grid-tile-min)),1fr))` | play.css:167-173 | `--grid-tile-min=9.5rem`（main.css:20） |
| `≤640`（堆叠） | 侧栏 tile 网格强制 `repeat(2,…)` | play.css:175-181 | |
| `≥1536` | 房间网格 6 列 | RoomGrid.vue:141-145 | |
| `1600–1919` | 播放侧栏宽 `392px` | main.css:235-239 | |
| `≥1920` (BP_WIDE) | 房间网格 `repeat(6,…)`（抽屉开 5）；播放侧栏宽 `425px` | RoomGrid.vue:147-151, main.css:241-245 | |
| `≥2560` | 房间网格 7 列（抽屉开 6） | RoomGrid.vue:153-157 | |
| 平板（iPad 类）竖屏 | `matchesPlayStackLayout()=true` → 播放页堆叠 | breakpoints.ts:52-54 | `isTabletLikeDevice` 判定 |
| 平板横屏 | 并排（不堆叠）；短边≥768 不堆叠 | breakpoints.ts:55-58 | 排除 1280×720 笔记本（hover+pointer:fine） |
| 手机竖屏播放 | `play-layout--stack`，视频 `42vh`（横屏时） | responsive-chrome.css:48-72 | 复合：phone+landscape |
| 关注页 page-tile 视口 | `w≤1024` 或 `h≤1024` 或 iPad 类（排除 hover 桌面） | breakpoints.ts:25-41 | 复合：尺寸+设备类型+hover |
| hover UI 启用 | `(hover:hover) and (pointer:fine)` | breakpoints.ts:75-77 | 控制悬停态（抽屉/卡片 hover） |
| 电视/大屏 | `isTvLikeDevice()` 强制不堆叠、无横竖屏按钮 | breakpoints.ts:79-101 | UA/触摸点判定 |
| 手机全屏竖屏回退 | `shouldUseLandscapeFallback()` = phone+portrait | breakpoints.ts:133-135 | 视觉旋转 90° |
| 触屏播放 sheet | `useTouchPlayerSheets()` = 非 hover UI | breakpoints.ts:137-140 | 控制条菜单改底部 sheet |

> 关键复合逻辑：`matchesPlayStackLayout()`（breakpoints.ts:47-67）——平板仅竖屏堆叠；横屏且短边≥768 并排；否则 `max-width:1024` 堆叠；手机/APK 竖屏触屏堆叠；`isTvLikeDevice` 永不堆叠。

---

## 7. 间距体系（4pt 栅格校验）

下表为源码**显式声明**的代表性 padding/margin/gap/尺寸值（rem 按 16px 折算），校验是否落在 4pt 栅格。

| 值（源码） | 折算 px | 落在 4pt 栅格？ | 来源 |
|---|---|---|---|
| `0.25rem` | 4 | ✓ | 多处（圆角/小内边距） |
| `0.5rem` | 8 | ✓ | 普遍 |
| `0.75rem` | 12 | ✓ | 普遍 |
| `1rem` | 16 | ✓ | RoomGrid 列距:118；圆角 lg 等价 |
| `1.25rem` | 20 | ✓ | |
| `1.5rem` | 24 | ✓ | |
| `2rem` | 32 | ✓ | |
| `44px` | 44 | ✓ | nav-height≥768 |
| `48px` | 48 | ✓ | nav-item |
| `52px` | 52 | ✓ | directory-rail |
| `56px` | 56 | ✓ | nav-height |
| `220px` | 220 | ✓ | directory-drawer |
| `240px`(推断) | 240 | ✓ | 注释 minmax(240px) |
| `280px`(Flutter) | 280 | ✓ | room_grid.dart:18 |
| `320px`/`328px` | 320/328 | ✓/✓ | play-sidebar 默认/Flutter |
| `0.85rem` | **13.6** | ✗ 例外 | app-main-pad-x:main.css:51；RoomGrid 行距:118 |
| `0.35rem` | **5.6** | ✗ 例外 | RoomGrid padding:119；app-main 上内边距:135 |
| `0.65rem` | **10.4** | ✗ 例外 | controls-bar padding:522 |
| `0.28rem` | **4.48** | ✗ 例外 | 关注 tile 列距:main.css:30；多处 gap |
| `0.22rem` | **3.52** | ✗ 例外 | page-tile body 内边距:793；底部栏:922 |
| `0.32rem` | **5.12** | ✗ 例外 | 侧栏 tile padding:695 |
| `0.36rem`/`0.45rem` | **5.76/7.2** | ✗ 例外 | 侧栏 tile padding:695 |
| `0.55rem` | **8.8** | ✗ 例外 | 平板竖屏 strip tab:responsive-chrome.css:559 |
| `1.15rem` | **18.4** | ✗ 例外 | drawer-toggle-width:main.css:47 |
| `70px` | **70** | ✗ 例外 | nav-width:main.css:16（遗留）；page-tile avatar:main.css:32 |
| `9.5rem`（=152px） | 152 | ✓ | --grid-tile-min:main.css:20 |

**例外汇总（未落在 4pt 栅格）：** `0.85rem(13.6)`、`0.35rem(5.6)`、`0.65rem(10.4)`、`0.28rem(4.48)`、`0.22rem(3.52)`、`0.32rem(5.12)`、`0.36rem/0.45rem(5.76/7.2)`、`0.55rem(8.8)`、`1.15rem(18.4)`、以及 `70px`。其余多为 0.25rem 整数倍（4/8/12/16/20/24/32px）符合栅格。

> Flutter 侧 `AppSpacing` 仅提供 `4/8/12/16/20/28(xxl)`——其中 `28` 在 web 中无直接对应值；web 用 `1.5rem=24`、`2rem=32`。复刻时建议把上述例外（尤其 `0.85rem` 内容内边距、`0.28rem` 关注列距、`70px` 头像）按需折算或就近对齐到已有 token。

---

## 8. Flutter 映射建议

依据 `design_tokens.dart` / `play_view.dart` / `room_grid.dart`，给出关键规格落点。

| Web 规格 | zishu Flutter 落点 | 建议 |
|---|---|---|
| 导航条高 `44px` | `AppSpacing.topNavHeight = 44` | 已对齐；播放页房间头 `SizedBox(height:44)`（play_view.dart:164）复用 |
| 底部导航 `56px` | `AppSpacing.bottomNavHeight = 56` | 已对齐（nav-chrome-height 移动端 56） |
| 播放侧栏 `328px` | `AppSpacing.playSidePanelWidth = 328` | 已对齐；宽度随断点变化（268/328/392/425）需在 `play_view.dart` 按 `AppBreakpoints` 切换，目前仅用固定 328 |
| 内容区左右内边距 `0.85rem` | 无直接 token（例外值） | 建议新增 `AppSpacing.contentPadX`（≈14）或就近用 `AppSpacing.lg(16)`；当前 play_view 用 `AppSpacing.lg`（play_view.dart:104-109） |
| 房间封面 `16/9` | `room_grid.dart:92` `cardWidth*9/16` | 已对齐 |
| 房间网格列数（断点） | `room_grid.dart` 用 `width/maxCardWidth` 动态列数 | **不一致**：web 是固定列数断点（2/3/4/5/6/7），Flutter 是连续 `maxCardWidth=280`。建议改为按 `AppBreakpoints`（640/768/1024/1536/1920/2560）映射固定列数，与 web 等价 |
| 房间网格间距 `0.85rem×1rem` | `AppSpacing.md=12`（行/列同） | **不一致**：web 行 13.6/列 16。建议行用新 token ≈14，列用 `lg=16` |
| 卡片圆角 | `AppRadius.lg=12`（视频框）/ `md=8`（page-tile） | 已对齐（play 框 12px，page-tile 8px） |
| 控制条按钮高 `2.55rem` | 未声明 | 建议在播放控件 widget 内新增常量；窄区 2.25/1.95rem 可用 `AppSpacing` 派生 |
| 音量条 `96×22` / 轨道 `4px` | 播放控件 widget | 未读控件实现，建议新增 `AppSpacing`/局部常量 |
| 关注 page-tile `5.28rem/70px 头像` | 关注页关注列表 widget（未读） | 建议新增 `followTileMinH`、`followAvatarSize=70` 常量（注意 70 不在 4pt 栅格） |
| 分类页 Tab 内边距 `0.72/0.28/0.12rem` | 分类页 widget（未读） | 建议就近对齐 `AppSpacing`（`sm/lg` 等） |
| 抽屉开关 `1.15rem×40px` | 播放侧栏开关 widget（未读） | `40px` 在栅格；`1.15rem(18.4)` 例外，建议就近 `AppSpacing.md`+微调 |

**整体建议：**
1. 播放侧栏宽度在 `play_view.dart` 目前固定 328，需按 `AppBreakpoints`（phone/tablet/desktop/wide）接入 268/328/392/425 四档；堆叠阈值 `size.width<768` 已与 `BP_MOBILE` 对齐，但 web 的 `matchesPlayStackLayout` 还含 orientation/设备类型复合，Flutter 目前未覆盖（仅 `stackSidePanel = width<phone`）。
2. RoomGrid 列数策略建议从「连续 maxCardWidth」改为「断点固定列数」，与 web §6 矩阵一致，避免不同宽度下的列数漂移。
3. 间距：优先用已有 `AppSpacing`；对 §7 列出的例外值（0.85/0.35/0.65/0.28/0.22rem、70px）新增命名常量或在设计评审中决定就近取值。
