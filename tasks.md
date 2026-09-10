# tasks.md — zishu_flutter 并行执行看板

> 规则:状态 `[x]` 完成 / `[~]` 进行中 / `[ ]` 未开始 / `[!]` 阻塞。
> 完成即更新本文件状态并写验证结果;验证不过不得标记完成。

## 并行分工(2026-09-09 起,双会话)

| 会话 | 轨道 | 独占修改范围 | 验证命令 |
|---|---|---|---|
| UI 会话 | U 轨 + 接线 | `lib/src/**`、`lib/main.dart`、根 `pubspec.yaml`、`docs/**` | `flutter analyze` / `flutter test` / `flutter build windows --debug -t lib/main.dart`(仓库根) |
| 解析会话 | P 轨 | `packages/live_parser/**`(含该包自身 pubspec) | `cd packages/live_parser && dart analyze && dart test` |

- 两个范围**零交集**;`tasks.md` 更新由 UI 会话统一维护(解析会话把结果写在回复里带回)。
- 解析会话必须保持 `dart analyze` 随时全绿,否则 UI 会话的 `flutter analyze` 会被连坐。
- 根 `pubspec.yaml` 的 `live_parser` path 依赖已由 UI 会话接好,解析会话无需且禁改。
- 2026-09-10 起 UI 侧再按**文件级隔离**拆多轨并行(斗鱼+直播页收敛),分工见下方「收敛轨 A」;其中 `play_view.dart`/`play_side_panel.dart`/`lib/src/shared/application/providers.dart` 三个装配文件**只允许收口人改**。

## 当前里程碑:M0(架构冻结)→ M1(Windows 斗鱼最小闭环)→ M2(斗鱼完整闭环)

对应 `docs/implementation-plan.md` §9;Gate 验收见 §8.3。

## 解析轨 P(Parser)

| 卡 | 内容 | 依赖 | 状态 | 验证 |
|---|---|---|---|---|
| P0 | package 骨架 + 契约层:models(RoomPayload/StreamQuality/StreamLine/RoomSummary/CategoryResult/SearchResult/SiteCapabilities)+ contracts(RoomResolver/BrowseRepository/SearchRepository/SiteRegistry)+ ParserHttp(可注入 client) | — | [x] 契约层已建(UI 会话产出,解析会话只读续建) | `dart analyze` 0 issue ✓ |
| P1 | 斗鱼完整链路:URL/房间号归一、betard、getEncryption 白名单 md5 auth(TTL 缓存)、getH5PlayV1 多 CDN 多画质、hlsH5Preview、三态判定、registry 注册 | P0 | [x] 解析会话产出,2026-09-09 盘点入库 | dart test(fixtures) ✓ |
| P2 | 斗鱼 browse:cate/list 分类 + rkc/directory/mixList 首页/分类房间列表 | P1 | [x] 同上 | dart test ✓ |
| P3 | 斗鱼 search:searchUser + searchShow | P1 | [x] 同上 | dart test ✓ |
| P4 | cross browse + catalog(全平台聚合首页数据) | P1-P3 | [x] 同上 | dart test ✓ |
| P5 | IPTV(M3U 解析,验证非直播站点型数据源) | P0 | [x] 同上 | dart test ✓ |
| P6 | 抖音(a_bogus/SM3、Cookie、protobuf) | P1 | [ ] 未开始 | dart test |
| P7 | 长尾平台:虎牙、B站、YY、Twitch、快手、SOOP、YouTube、小红书 | P4 | [~] 虎牙(tars/anti_code)/B站(wbi)/Twitch/**YY(resolve+browse+search,提交 e2007a4)** 已实现;YY 弹幕未做;快手/SOOP/YouTube/小红书未做 | dart test + 平台完成定义(implementation-plan 5.2) |
| P8 | Dart streaming-server(live_server:shelf + SSE/WS,snake_case 兼容层) | P4 | [ ] 未开始 | dart test + flutter build web |
| P9 | 弹幕协议 codec 与会话(douyu WS 等) | P1 | [~] douyu/bilibili codec 已实现;会话管理待验 | dart test |

> 2026-09-09 盘点:`packages/live_parser` 实测 dart analyze 0 issue、dart test 167 passed + 5 skipped(fixtures 全离线),P 轨状态按实际产出同步(解析会话此前未回写看板)。

> P1-P3 即"Windows 第一阶段平台"的斗鱼部分(implementation-plan 5.1);虎牙/B站随 P7,但 M3 里程碑要求其与 P1 同等主链路。

## UI 轨 U(UI)

| 卡 | 内容 | 依赖 | 状态 | 验证 |
|---|---|---|---|---|
| U0 | design tokens + ZishuTheme:`ZishuTokens` ThemeExtension(深/浅)+ AppSpacing/AppRadius/AppTypography/AppBreakpoints/AppMotion + PlatformBrandCatalog | — | [x] | analyze 0 issue |
| U1 | AppShell:44px 顶部导航、平台 tabs、右侧工具区,go_router 导航(context.go) | U0 | [x] | analyze;nav-* 锚点测试进行中 |
| U2 | RoomCard + RoomGrid 自适应网格(CachedNetworkImage + tokens 化)+ fixture 数据源 | U1 | [x] | analyze;room-card 锚点测试进行中 |
| U3 | 分类页(分组 tabs + 子分类网格 + 分类房间分页) | U2 | [x] category_view 已建(测试进行中) | 冒烟 |
| U4 | Riverpod 接线:BrowseController(分页/refresh)/PlayController(generation fence)/SearchController(防抖+直达)/Follow/Settings/Anchor/Timeline 全部 AsyncNotifier 化 | U2 | [x] | 各 feature provider 已落 |
| U5 | 播放页:LivePlayer 抽象 + MediaKitLivePlayer + 四态舞台(解析中/失败/fixture 占位/真实画面)+ 控制条 + 画质/线路条 + 328px 侧栏 | U4 | [x] 布局与编排完成;真实播放接线在 G1 | 手测:切档/切线(G1 后) |
| U6 | 弹幕 overlay + 聊天侧栏(静态样例已入侧栏;真弹幕等 P9/G2) | U4 | [~] fixture 版 | 手测 |
| U7 | 关注页(三密度/批量/特别关注)+ 设置页(shared_preferences 持久化) | U4 | [x] | follow/settings 锚点测试进行中 |
| U8 | 搜索(防抖/直达/键盘)+ 主播页 + 时间线 + ErrorView/EmptyView/AsyncValueView 通用组件 | U4 | [x] | search/anchor/timeline 锚点测试进行中 |
| U9 | 响应式 Web/Android 适配(底部导航、窄屏布局、平台 tab icon-only 收缩) | U1-U8 | [x] 全部落地:<768 底部导航(顶导航不渲染,nav-* 迁移)、平台 tab 768-1023 icon-only+Tooltip / >=1024 点+文字、首页 chips Wrap 多行、播放页 <768 侧栏堆叠 + 横屏手机 sheet 化、控制条窄屏收缩;W12 六用例全部转绿 | flutter test 153 passed / 0 skipped |

## 收敛轨 A(斗鱼 + 直播页,2026-09-10 起)

目标:把「斗鱼 + 直播页」从**"能看但数据是假的"**收敛到 M2 真实闭环。前提结论(2026-09-10 实测):
- 斗鱼读链路已通:分类/房间解析在 `--dart-define=ZISHU_REAL_PARSER=true` 下即可跑;斗鱼是唯一 `capabilities.danmaku=true` 且解析最完整的平台(13 个文件)。
- 缺口集中在**直播页消费层**,不是斗鱼解析。
- **当前 exe 实跑 fixture**(首页 10 房间与 `kFixtureRooms` 逐条一致),开关是编译期常量 `useRealParser`,默认 false。

### A 轨文件隔离分工

**A0 是串行前置**:先拆装配文件,之后各轨零交集。冲突红线:`play_view.dart`、`play_side_panel.dart`、`providers.dart`、`main.dart` 只有**收口人**能改。

| 轨 | 独占文件(只改这些) | 卡 | 验证 |
|---|---|---|---|
| A0 拆分/冻结(串行前置) | `lib/src/features/play/views/play_view.dart`、`.../widgets/play_side_panel.dart`(+ 其派生新文件) | A0 | `flutter analyze` + 既有 play/layout/danmaku 用例全绿(纯搬迁,行为不变) |
| A1 搜索接线 | `lib/src/features/search/**`、`lib/src/shared/application/search_source.dart`(新) | A1 | 注入 fake SearchRepository 的 widget test;开关关闭时 fixture 用例仍绿 |
| A2 弹幕 | `lib/src/features/danmaku/**`(全新目录)、`lib/src/features/play/widgets/play_side_chat_tab.dart` | A2-A4 | 叠加层/设置/聊天单测;`danmaku_test` 改为断言真实会话 |
| A3 播放器能力 | `lib/src/platforms/common/playback/**`、`.../play/widgets/player_controls.dart`、`.../play/application/play_provider.dart` | A5-A7 | 全屏/沉浸/快捷键/点帧用例 |
| A4 侧栏信息与设置 | `.../play/widgets/play_side_header.dart`、`play_side_settings_tab.dart`、`play_side_follow_tab.dart`、`play_side_recommend_tab.dart`、`lib/src/features/follow/application/follow_provider.dart` | A8-A10 | 关注落库/设置生效/推荐列表用例 |
| A5 导航能力过滤 | `lib/src/shared/presentation/platform_brands.dart`、`lib/src/app/app_shell.dart` | A11 | 未实现平台不渲染或不进去 |
| 集成收口(串行) | `play_view.dart`、`play_side_panel.dart`、`providers.dart`、`lib/main.dart` | A12 | `flutter analyze` + `flutter test` 全量 + `build windows --debug` |
| P 轨(解析会话) | `packages/live_parser/**` | A13 | `dart analyze` + `dart test` |

### A 轨卡片

| 卡 | 内容 | 依赖 | 状态 | 验证 |
|---|---|---|---|---|
| A0 | 拆播放页装配:`play_side_panel.dart` 拆出 `play_side_header.dart`/`play_side_chat_tab.dart`/`play_side_follow_tab.dart`/`play_side_recommend_tab.dart`/`play_side_settings_tab.dart`(仅留 TabBar 装配);`play_view.dart` 拆出 `play_stage.dart`(舞台+错误卡+占位)/`play_room_header.dart`;新增 `play_contracts.dart` 冻结跨轨接口(弹幕会话、播放器能力、侧栏回调签名) | — | [ ] | analyze + 既有用例全绿 |
| A1 | 搜索接真实解析:新增 `SearchSource` + `searchSourceProvider`;`search_provider.dart` 走 `SearchRepository`(房间 t=120 + 主播 t=1 合并去重),`kFixtureRooms` 降级为开关关闭时的兜底;保留房间号/douyu 链接直达 | A0 | [ ] | 注入 fake 的 widget test |
| A2 | 弹幕叠加层:`features/danmaku/` canvas 叠加层(多轨道分配、O(1) 碰撞防重叠、速度随画布宽度、颜色归一+描边、富文本) | A0,P9 | [ ] | 单测 + 手测 |
| A3 | 弹幕设置面板:显示开关 / 透明度 10-100 / 字号 12-36 / 速度 1-10 / 显示区域 5 档;持久化 | A2 | [ ] | 单测 |
| A4 | 侧栏聊天接真实弹幕:消费同一 `DanmakuSession`,含连接状态、自动滚底、N 条新消息跳底、重连;**把 `danmaku_test` 从"断言硬编码 `_chatSamples`"改为断言真实会话**(消除假绿) | A2 | [ ] | `danmaku_test` 改后仍绿 |
| A5 | 全屏:`MediaKitLivePlayer.toggleFullscreen` 实装(现为空实现)+ 控制条状态联动 | A0 | [ ] | 手测 + 用例 |
| A6 | 沉浸模式 + 静音提示:全屏隐藏侧栏、自动隐藏控件、点右热区唤侧栏、横屏锁定 | A5 | [ ] | 手测 |
| A7 | 播放器细节:Space/M/F 快捷键 + 点帧播放/暂停 + 控制条补「刷新视频」「弹幕开关」「清晰度/线路下拉」+ `settingsProvider.defaultQuality` 生效(现永远选 `streams.first`) | A0 | [ ] | 用例 |
| A8 | 侧栏关注落库:关注/超关接 follow provider 并持久化(现为页内 `setState`,切页即丢;`PlayView` 未传回调) | A0 | [ ] | 用例 |
| A9 | 侧栏设置接线:线路格式/聊天开关/透明度/字号接 `settingsProvider` 并真正生效(现全是 `value` 写死 + `onChanged: (_) {}` 死控件) | A0 | [ ] | 用例 |
| A10 | 推荐 Tab:用 `browse.fetchRooms(cid)` 拉同分类直播间(现为空态提示) | A0 | [ ] | 用例 |
| A11 | 导航能力过滤:按 `buildSiteRegistry().supportedSites` 过滤 `navPlatforms`,避免真实解析下点抖音/快手/SOOP/小红书/YouTube 抛 `StateError('站点 X 不支持分类浏览')` | A0 | [ ] | 用例 |
| A12 | 集成收口:装配层接线(把 A1-A11 挂回 `play_view`/`play_side_panel`/`providers`)+ 全量门禁 + 打开 define 的 Windows 真实验收 | A1-A11 | [ ] | analyze + test 全量 + build windows + 真机观感 |
| A13(P) ✅ | 解析侧配合(已完成,提交 `2f3709d`):① **死键修复**——`availableQualities` 改为从真实 `streams` 反推(此前按 `multirates` 全量生成;某档全部线路取流失败时该档仍留在列表里,但 `streams` 已无同名项 → UI 点该 chip 静默无反应);② `RoomPayload` 增补可空 `startedAt`,斗鱼取 betard `show_time`——**人气/关注数无单房间接口(`ol` 只在分类列表接口),故不提供;拿不到即 null,不伪造**;③ 附带修复**搜索恒 0 条**:斗鱼 japi 搜索缺设备标识 cookie `dy_did` 时返回 `{error:9,"搜索过于频繁"}` 且 `data` 为空,现自动补随机 32 位十六进制 did,并让上游 `error != 0` 抛 `ParserHttpException` 而非静默返回空结果(**搜索聚合层必须按平台 try/catch**) | A0 | [x] | `dart analyze` 0 issue + `dart test` 187 passed + 斗鱼在线 smoke 全绿 |

> 假绿警示:`test/ui/workflows/danmaku_test.dart` 断言「弹幕条目 >0」,但数据源是硬编码 `_chatSamples`(12 条),**当前是通过状态但不是真弹幕**;A4 未完成前该用例不能作为弹幕能力证据。

## 测试轨 W(workflows)

平台 workflow(参数化)+ 全局 UI workflow + 移动设备矩阵的并行执行看板独立维护在 `tasks-workflows.md`;W0(锚点+基线测试)进行中,批次 1-3 待派发。

## 接线(Gate)

| 卡 | 内容 | 依赖 | 状态 | 验证 |
|---|---|---|---|---|
| G1 | Windows direct gateway:DirectLiveParserGateway(BrowseSource/RoomSource 的 live_parser 实现)替换 fixture;首页斗鱼卡片→点击→media-kit 播放→切画质/线路 | P1,U4,U5 | [ ] | 断开远程 server 后 Windows 浏览+播放斗鱼(implementation-plan M1 验收) |
| G2 | 斗鱼搜索/弹幕接入 UI | P3,P9,U6 | [ ] | Windows 斗鱼功能闭环(M2) |

## 技术栈决议(2026-09-09 用户确认)

- 立即采用:Material 3、ThemeExtension 视觉系统、Riverpod、go_router、cached_network_image(dio/media-kit 沿用)。
- 按里程碑引入:Drift(M4)、shared_preferences(U7)、window_manager/file_picker(M4)、logging facade(M2)、Widgetbook 暂缓、golden test 样式稳定后。
- **freezed/json_serializable 不进 `live_parser`**:契约模型手写(纯 Dart 包、三端单一真源、避免 build_runner 链路);UI 侧 union 状态由 Riverpod `AsyncValue` 承载,本地实体 M4 引 Drift 时再评估。
- 详见 `docs/implementation-plan.md` §7.0。

## 架构决议(2026-09-08 用户确认)

- 解析在 streaming-server 定义(单一真源)的历史决议已被 **live_parser 直连架构**取代:Windows/Android 直连纯 Dart 解析 package,Web 经 Dart streaming-server;旧 Node server 仅迁移期 fallback。
- 新代码使用 `lib/src/shared/`(共享模型/接口/用例)、`lib/src/platforms/`(adapter)、`lib/src/apps/`(三端 UI);旧代码归档 `lib/legacy/`,禁止反向依赖。

## 已验证记录(追加式)

| 日期 | 命令 | 结果 |
|---|---|---|
| 2026-09-08 | flutter pub get | OK(43 deps) |
| 2026-09-08 | flutter test | 3/3 passed |
| 2026-09-08 | flutter analyze | No issues |
| 2026-09-08 | flutter build web | OK(84.7s) |
| 2026-09-08 | tool/check.ps1 全量门禁 | pub get/analyze/test(79)/build web(124.7s) 全绿 |
| 2026-09-08 | tool/e7_run.mjs douyu/63136 E2E | PASS:1080p 播放 4s currentTime 连续增长 + 25 条弹幕 + 无错误态 |
| 2026-09-09 | UI 样式基线落盘后 flutter analyze | No issues(0 issue) |
| 2026-09-09 | flutter test | 80/80 passed |
| 2026-09-09 | W13 门禁 flutter analyze | No issues(0 issue) |
| 2026-09-09 | W13 门禁 flutter test 全量 | 147 passed / 6 skipped(W12 占位) / 0 failed |
| 2026-09-09 | W13 门禁 flutter build windows --debug -t lib/main.dart | OK(47.6s) |
| 2026-09-09 | W9 mobile_phones + W11 mobile_accessibility(修复后) | 8/8 passed(修复前 W9 4/4 失败、W11 2/4 失败) |
| 2026-09-09 | U9 门禁 flutter analyze | No issues(0 issue) |
| 2026-09-09 | U9 门禁 flutter test 全量 | 153 passed / 0 skipped(W12 六用例转绿) / 0 failed |
| 2026-09-09 | U9 门禁 flutter build windows --debug -t lib/main.dart | OK(14.7s) |
| 2026-09-10 | P 轨 YY 门禁 `dart analyze` | No issues(0 issue) |
| 2026-09-10 | P 轨 YY 门禁 `dart test` | 183 passed / 6 skipped / 0 failed(上轮 167+5) |
| 2026-09-10 | P 轨 YY 真实链路 smoke(`--run-skipped --plain-name YY`) | PASS:首页 22490906 live→qualities[超清,高清,流畅]→分类[娱乐,游戏,其他]→搜索 5 条 |
| 2026-09-10 | 真实解析开关核查(启动 Debug exe + 窗口取证) | 首页 10 房间与 `kFixtureRooms` 逐条一致 → **当前构建仍是 fixture 模式**;`useRealParser` 默认 false 且为编译期常量 |
| 2026-09-10 | P 轨 A13 门禁 `dart analyze` / `dart test` | No issues(0 issue);187 passed / 6 skipped / 0 failed(183 → +4 单测) |
| 2026-09-10 | P 轨 A13 斗鱼在线 smoke(`--run-skipped --plain-name 斗鱼`) | PASS:首页 36252 live → qualities[原画1080P60,蓝光4M,超清,高清] → startedAt=2026-09-10T16:29:28 → 搜索 5 条(修复前 0 条) → 分类 5 组 → 弹幕 29 条/30s |
| 2026-09-10 | UI 复刻(顶栏/平台条/播放侧栏/首页左栏)门禁 `flutter analyze` | No issues(0 issue) |
| 2026-09-10 | UI 复刻门禁 `flutter test` 全量 | 156 passed / 2 failed(latency_test 并行负载抖动)/ 0 skipped |
| 2026-09-10 | `latency_test` 单独复跑 | 5/5 passed(bilibili median=591ms、douyu reentry 433ms ≤ budget 1678ms)→ 全量 2 失败确认为负载抖动非回归 |
| 2026-09-10 | UI 复刻门禁 `flutter build windows --debug -t lib/main.dart` | OK |

### UI 复刻收口明细(2026-09-10)

在 `241c163`(顶栏/平台条/播放侧栏 1:1)基础上按对比截图补齐 P0-P2 缺口,4 条文件级互斥轨并行:

| 轨 | 文件 | 内容 |
|---|---|---|
| T1 顶栏/底栏 | `lib/src/app/app_shell.dart` | 桌面 `_TopNav` 居中平台 tab(34×34 品牌色描边+阴影)、右侧工具区(关注/搜索/主题/设置/头像);移动 `_PlatformStrip` 6×2 图标网格;`_BottomNav` 扩为 7 项 |
| T2 播放页沉浸 | `lib/src/features/play/views/play_view.dart` | 去掉外层 padding/圆角边框,视频区 `Stack` 全幅;`PlayerControlsBar`+`QualityLineBar` 作为底部渐变叠层;`_RoomHeader` 居中标题 |
| T3 侧栏 | `lib/src/features/play/widgets/play_side_panel.dart` | 新增 `PlaybackStatus`(播放中/静音/已暂停)状态条(半角括号、禁全角冒号);信息头高度按 `MediaQuery.textScalerOf` 缩放防大字体溢出 |
| T4 首页左栏 | `lib/src/features/browse/views/home_view.dart` + 新增 `widgets/browse_sidebar.dart` | 桌面常驻左栏(平台图标网格 + 分类树),锚点 `home-platform-chip-{id}`;窄屏不渲染 |

收口修复(跨轨破坏):

- **网格列数改按视口断点**:`room_grid.dart` 原按 `LayoutBuilder` 容器宽取列,左栏使 800 视口内容区退到 640 档 → 3 列,与参考 `RoomGrid.vue:120-157` 的 `@media`(视口)口径不符。改为列数取 `MediaQuery.sizeOf(context).width`,卡片物理宽仍按容器算 → 800→4、1024→5(对齐 `mobile_tablets_test.gridColumnsScale`)。
- **左栏宽度对齐**:参考 `drawerPref` 默认 `open:true`(`--directory-drawer-width: 220px`),`BrowseSidebar.width` 140→220。
- **重复 Tooltip**:`browse_sidebar.dart` 的平台 chip 与顶栏 tab 同名 Tooltip,U9 收缩用例断言已限定 `platform-tab-douyu` 祖先链,无需改代码。

遗留(未纳入本轮):

- 首页左栏为固定 220px,未实装参考的可折叠 rail(52px↔220px,`drawer-toggle`);
- 左栏平台图标布局为 3 列,参考为 2 列;
- 真实截图复核受阻:本环境下 GUI 进程落在**非交互 window station**,`PrintWindow` 返回白帧、全屏 `ImageGrab` 只见桌面壁纸(见 `.workbuddy/memory`),故改以测试契约(gridColumnsScale / browse_sidebar / responsive_skip)作为验收证据。

### W13 修复明细(2026-09-09)

三处固定宽度是 W9/W11 失败的共同根因,按 `AppBreakpoints` 收缩后转绿:

| 位置 | 问题 | 修复 |
|---|---|---|
| `lib/src/app/app_shell.dart` `_TopNav` | 固定内容约 420dp(Logo+首页+分类+3 工具按钮+padding),360/375/393/412 宽分别溢出 60/45/27/8dp,并把右侧工具按钮挤出视口 | <640:Logo 仅图标、隐藏「分类」;平台 tab <768 仅品牌色点;锚点 nav-home/follow/search/settings 全断点保留 |
| `lib/src/features/play/views/play_view.dart` | Row + 固定 328dp 侧栏把视频区压到 3dp(360dp 下),控制条随之溢出 230-285dp | <768 改 Column 堆叠:视频区 flex 3 + 侧栏 flex 2 |
| `lib/src/features/play/widgets/player_controls.dart` | 4 按钮(192)+ 音量滑杆(96)= 288dp 固定需求,窄屏必然溢出 | <768 隐藏滑杆与延迟文案,用 Spacer 保持按钮右对齐 |
| `lib/src/shared/presentation/design_tokens.dart`(新增 `metaHeightFor`)+ 两处网格 | 卡片元信息区高度预算固定,大字体 1.15/1.3 下纵向溢出 1dp/5.5dp | 文本区预算按 `MediaQuery.textScalerOf` 同步放大,卡片在网格中变高 |

已知遗留:横屏 `follow@iPhone15Landscape(852×393)` 仍有 lib 溢出,W10 以 drain 方式容忍(用例通过),待 U9 横屏 sheet 落地后修。

### U9 落地明细(2026-09-09,W12 六用例转绿,U9 验收完成)

| 模块 | 实现 |
|---|---|
| `app_shell.dart` | <768 顶导航不渲染,新增 56px `_BottomNav`(首页/关注/搜索/设置,nav-* 锚点迁移);平台 tab 768-1023 icon-only + Tooltip(平台名)、>=1024 色点+文字;顶导航 tab 持有 W12 契约 key `platform-tab-{site}` |
| `home_view.dart` | 平台筛选 chips 横向 ListView → `Wrap` 多行(360 宽全部挂载);key 按断点切换:<768 用 `platform-tab-*`,>=768 用 `home-platform-chip-*`(与顶导航 tabs 不冲突) |
| `play_view.dart` | 横屏手机(宽>=768 且高<600)取消 328px 常驻右栏,`play-side-panel-toggle` 改为底部 sheet 滑出(sheet 宽近全屏) |
| 测试同步 | `responsive_skip_test` 移除 4 组 skip 并调整 nav-home 断言(迁移底部);`navigation_test`/`browse_home_test` 首页 chips key 改 `home-platform-chip-*`;`mobile_tablets_test` landscapePlayPriority 第 4 步改 U9 口径(隐藏 + sheet 交互验证);`layout_test`/`browse_home_test`/`platform_workflow` 的 pump 改为直接写 `tester.view`(**关键修复**:`setSurfaceSize` 只改渲染 surface,MediaQuery 仍报 800×600,断点判定全失灵) |
| 横屏 follow 溢出遗留 | U9 横屏 sheet 已落地,但 `follow@iPhone15Landscape` 的 follow_entry_card 溢出仍存在(W10 drain 容忍),待 follow 三密度在横屏的布局优化 |

## 历史归档

旧 engine/ui 双 package 时代的 G/E/U/Q 轨道卡与记录见 git 历史(tasks.md @ 32465d3 及之前);其中 E1-E4/E7、U1/U2 的成果已被新架构吸收(live_parser 契约层、design tokens、AppShell)。
