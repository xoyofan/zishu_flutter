# zishu_flutter 总体实施计划（Windows 优先，UI / 解析双轨并进）

> 状态：架构基线  
> 当前优先级：**Windows > Web > Android**  
> 客户端技术核心：**Flutter + media-kit**  
> 解析技术核心：**单一纯 Dart package**  
> UI 与功能目标：最终与 `SFVideoLive/web` 的布局、样式、平台范围和主要功能对齐

---

## 1. 目标与范围

本项目不是在旧 Web UI 上继续修补，而是重新建设一个 Flutter 三端客户端：

1. Windows 是第一交付端，用它完成架构、解析和完整 UI 的首轮验证。
2. Web 与 Android 复用同一套 Flutter presentation、业务模型和用例。
3. 播放统一使用 `media-kit`，平台差异放在 adapter 层。
4. 所有直播站点解析只维护一套纯 Dart 源码。
5. Windows/Android 直接调用解析 package；Flutter Web 通过 Dart `streaming-server` 使用解析 package。
6. 旧 Node `streaming-server` 和 `lib/legacy/` 是行为参考、回归基准及迁移期 fallback，不是新代码依赖方向。
7. 最终页面布局、视觉语言、平台清单和用户功能与 `SFVideoLive/web` 对齐，但实现为 Flutter Widget，不复制 Vue 组件架构。

### 1.1 当前已验证基线

- Windows Flutter runner 已建立。
- `media-kit` Windows 播放已验证可用。
- 当前 Windows 验证页可通过远程 streaming-server 自动选择斗鱼在播房间并播放 HLS。
- 旧 Web UI、旧 HTTP contracts、旧 JS 播放和弹幕实现已归档到 `lib/legacy/`。
- 新代码根目录为 `lib/src/`。

### 1.2 明确不采用

- 不采用 Rust DLL / Dart FFI 作为主解析路线。
- 不让 Flutter Web 在浏览器中直接执行站点解析。
- 不让 UI 直接依赖某个平台解析实现。
- 不在 Windows、Android、Node/Server 分别维护三套解析代码。
- 不将 `lib/legacy/` 代码逐文件原样搬回新结构。

---

## 2. 总体架构

```text
                         ┌─────────────────────────────┐
                         │ packages/live_parser (Dart) │
                         │ resolve / browse / search   │
                         │ danmaku protocol / models   │
                         └──────────────┬──────────────┘
                                        │ direct import
                 ┌──────────────────────┼──────────────────────┐
                 │                      │                      │
        Flutter Windows         Flutter Android       Dart streaming-server
        Direct Parser Gateway   Direct Parser Gateway HTTP / SSE / WebSocket
                 │                      │                      │
                 └──────────────┬───────┘                      │
                                │                              ▼
                         shared application              Flutter Web
                                │                       HTTP Parser Gateway
                                └──────────────┬───────────────┘
                                               ▼
                                       Flutter feature/UI
                                               │
                                               ▼
                                        media-kit player
```

### 2.1 解析调用路径

#### Windows（当前优先）

```text
Flutter UI
  -> application use case
  -> LiveParserGateway
  -> DirectLiveParserGateway
  -> package:live_parser
  -> 站点 API
```

不经过本地 HTTP，不需要 sidecar，不启动额外进程。

#### Android

与 Windows 相同：

```text
Flutter UI -> application -> DirectLiveParserGateway -> live_parser
```

Android 只增加权限、网络安全策略、后台生命周期等平台适配。

#### Web

```text
Flutter Web
  -> HttpLiveParserGateway
  -> Dart streaming-server
  -> package:live_parser
  -> 站点 API
```

浏览器侧只处理 HTTP/SSE/WebSocket 和 media-kit Web 播放，不直接执行解析源码，以避免 CORS、Cookie、签名环境和密钥暴露问题。

---

## 3. 目标仓库目录

建议在当前仓库建立 Dart workspace 风格的结构。第一阶段可继续单仓库，未来可独立发布 package。

```text
zishu_flutter/
├─ lib/
│  ├─ main.dart                         # Windows 默认入口
│  ├─ main_web.dart                     # 新 Flutter Web 入口
│  ├─ main_android.dart                 # 可选；也可按 platform 检测启动
│  ├─ src/
│  │  ├─ app/                           # composition root / DI / router / theme
│  │  │  ├─ app.dart
│  │  │  ├─ app_router.dart
│  │  │  ├─ app_dependencies.dart
│  │  │  └─ app_theme.dart
│  │  ├─ shared/
│  │  │  ├─ domain/                     # UI 需要的跨端实体和 repository ports
│  │  │  ├─ application/                # 用例、状态机、分页、播放编排
│  │  │  └─ presentation/               # 通用 Flutter Widget / design system
│  │  ├─ features/
│  │  │  ├─ browse/                     # 首页、分类、房间网格
│  │  │  ├─ play/                       # 播放页、控制栏、弹幕层、侧栏
│  │  │  ├─ follow/                     # 关注列表、状态、导入导出
│  │  │  ├─ search/                     # 房间/主播搜索
│  │  │  ├─ anchor/                     # 主播主页
│  │  │  ├─ timeline/                   # 时间线
│  │  │  ├─ auth/                       # 登录/注册/云同步
│  │  │  ├─ category/                   # 分类索引、跨平台分类
│  │  │  ├─ iptv/                       # M3U 与源管理
│  │  │  └─ settings/                   # 主题、播放、弹幕、诊断
│  │  ├─ platforms/
│  │  │  ├─ common/                     # media-kit 共用 adapter
│  │  │  ├─ windows/                    # Direct parser、窗口/托盘/通知/文件
│  │  │  ├─ web/                        # HTTP parser、Web 限制适配
│  │  │  └─ android/                    # Direct parser、通知/生命周期
│  │  └─ apps/
│  │     ├─ windows/
│  │     ├─ web/
│  │     └─ android/
│  └─ legacy/                           # 只回归，不被新代码 import
│
├─ packages/
│  ├─ live_parser/                      # 纯 Dart 解析核心
│  │  ├─ lib/
│  │  │  ├─ live_parser.dart            # 稳定公开 API
│  │  │  └─ src/
│  │  │     ├─ models/                  # RoomPayload、Stream、Category、Search
│  │  │     ├─ contracts/               # Parser/Browse/Search/Danmaku interfaces
│  │  │     ├─ registry/                # site capability registry
│  │  │     ├─ http/                    # 统一 HTTP、cookie、UA、retry
│  │  │     ├─ cache/                   # singleflight、TTL、catalog cache
│  │  │     ├─ platforms/
│  │  │     │  ├─ douyu/
│  │  │     │  ├─ huya/
│  │  │     │  ├─ bilibili/
│  │  │     │  ├─ douyin/
│  │  │     │  ├─ yy/
│  │  │     │  ├─ twitch/
│  │  │     │  ├─ kuaishou/
│  │  │     │  ├─ soop/
│  │  │     │  ├─ youtube/
│  │  │     │  ├─ xhs/
│  │  │     │  └─ iptv/
│  │  │     └─ danmaku/                 # 协议 codec 与会话接口
│  │  └─ test/
│  │
│  └─ live_server/                      # 纯 Dart Web 解析服务
│     ├─ bin/server.dart
│     ├─ lib/src/http/
│     ├─ lib/src/sse/
│     ├─ lib/src/ws/
│     └─ test/
│
├─ contracts/                           # JSON fixtures/schema/golden，跨宿主一致
├─ assets/catalog/                      # 平台、分类、cross-map、徽章种子
├─ docs/
│  ├─ architecture.md
│  └─ implementation-plan.md            # 本文
└─ test/
```

### 3.1 依赖规则

```text
features -> shared/domain + shared/application
platforms -> shared ports + live_parser/media-kit
apps -> app composition + features
live_server -> live_parser
live_parser -X-> Flutter
live_parser -X-> media-kit
live_parser -X-> lib/src UI
new code -X-> legacy
```

`live_parser` 允许依赖：

- `dart:async`、`dart:convert`、`dart:io`（Native/Server）
- `http` 或 `dio` 的纯 Dart API
- `crypto`、压缩、protobuf 等纯 Dart package

`live_parser` 禁止依赖：

- `flutter/*`
- Widget
- `media_kit`
- `dart:ui`
- `package:web`
- `dart:js_interop`

若部分解析代码必须使用 `dart:io`，通过 conditional import 隔离；浏览器本来也不会直接 import parser，因此首先保证 Windows、Android、Dart server 三个 Dart VM target。

---

## 4. 解析核心设计

### 4.1 公开 API

UI 和 server 不接触站点内部类，只依赖稳定 facade：

```dart
abstract interface class LiveParser {
  Future<RoomPayload> resolveRoom(RoomRequest request);
  Future<CategoryResult> fetchCategories(CategoryRequest request);
  Future<RoomListResult> fetchRooms(RoomListRequest request);
  Future<SearchResult> search(SearchRequest request);
  Stream<DanmakuEvent> connectDanmaku(DanmakuRequest request);
  Set<String> get supportedSites;
  SiteCapabilities capabilities(String site);
}
```

首版也可拆分接口，避免一个大接口：

```text
RoomResolver
BrowseRepository
SearchRepository
DanmakuConnector
FollowSnapshotProvider
```

推荐使用小接口，`LiveParserFacade` 仅负责聚合。

### 4.2 标准模型

`RoomPayload` 以 SFVideoLive `/api/room` 现有事实契约为基线，包括：

- `site`、`roomId`
- `anchorName`、`title`、`cover`、`avatar`
- `category`、`cid`
- `isLive`、`roomState`
- `streams[]`
  - 画质 `name/rate`
  - 线路 `name/url/format/headers`
- `availableQualities[]`
- `danmakuSession`
- `source`、`fetchedAt`
- 可诊断 timing/cache 字段

内部 Dart 字段使用 lowerCamelCase；HTTP server 负责转换为与旧 API 兼容的 snake_case JSON。

### 4.3 平台能力注册

每个平台声明能力，不在 UI 到处写 `if (site == ...)`：

```dart
class SiteCapabilities {
  final bool browse;
  final bool crossBrowse;
  final bool roomSearch;
  final bool anchorSearch;
  final bool danmaku;
  final bool multiQuality;
  final bool multiLine;
  final bool roomStats;
  final bool requiresCookie;
}
```

平台注册项包含：

- id、中文名、品牌色、图标
- 默认房间
- 外部房间 URL
- capabilities
- resolver/browse/search/danmaku factory

### 4.4 HTTP 基础设施

统一实现以下能力，禁止每站重复造轮子：

- 默认 UA、Referer/Origin helpers
- CookieJar，按站点隔离
- gzip/brotli 解压
- 超时、重试、取消
- singleflight 防止同房重复解析
- TTL cache
- 结构化诊断日志
- 上游错误分类：input/network/upstream/parse/rate-limit/cookie-required
- 可注入 clock/client，方便 fixture 单测

### 4.5 Dart streaming-server

目标是兼容当前 Flutter Web 已知接口：

```text
GET  /api/health
GET  /api/room
GET  /api/categories
GET  /api/rooms
GET  /api/search
GET  /api/hot-categories
GET  /api/category-cross-map
POST /api/follows/status
GET  /api/:site/danmaku
GET  /api/:site/danmaku/stream       # SSE
WS   /api/soop/danmaku/ws            # 如平台需要 relay
GET  /api/live-stream                # headers/CORS/m3u8 proxy
GET  /api/badge-image
```

建议使用 `shelf` + `shelf_router`；WebSocket 使用 `shelf_web_socket`，SSE 使用 streaming response。

迁移期运行模式：

```text
Dart native endpoint -> 新 live_parser
未迁平台 endpoint -> 旧 Node remote fallback
```

但 fallback 必须在 server adapter 层，不能进入解析 package。

---

## 5. 平台实施顺序

最终目标平台与 SFVideoLive 对齐：

| 平台 | ID | 浏览 | 搜索 | 弹幕 | 特殊依赖 | 新解析优先级 |
|---|---|---:|---:|---:|---|---:|
| 全平台聚合 | all | 是 | — | — | cross-map | P1 |
| 斗鱼 | douyu | 是 | 主播/房间 | 是 | MD5、HLS/FLV、多 CDN | P0 |
| 虎牙 | huya | 是 | 主播/房间 | 是 | anti-code、多线路 | P0 |
| 哔哩哔哩 | bilibili | 是 | 主播/房间 | 是 | WBI/弹幕 token/protobuf | P0 |
| 抖音 | douyin | 游戏分类 | 主播/房间 | 是 | a_bogus/SM3、Cookie、protobuf | P1 |
| YY | yy | 是 | 主播/房间 | 部分 | HLS、二进制弹幕 | P2 |
| Twitch | twitch | 是 | 房间 | 是 | GQL、代理、IRC | P2 |
| 快手 | kuaishou | 是 | 暂无 | 是 | 页面状态、弹幕 feed | P2 |
| SOOP | soop | 是 | 房间 | 是 | 海外 API、WS relay | P2 |
| YouTube | youtube | 是 | 暂无 | 是 | InnerTube、Cookie/Bot 门 | P3 |
| 小红书 | xhs | 是 | 暂无 | 是 | Cookie、签名/RWP | P3 |
| IPTV | iptv | 是 | — | 否 | M3U、分组、TS | P1 |
| 网易 CC | cc | 软禁用 | 房间 | 否 | 平台已停运 | 保留模型，不优先 |

### 5.1 Windows 第一阶段平台

严格控制首批范围：

1. 斗鱼：完成 resolve + recommend + category + search + danmaku。
2. 虎牙：完成同等主链路。
3. B站：完成同等主链路。
4. 全平台首页：聚合前三站。
5. IPTV：验证非直播站点型数据源与 media-kit TS/HLS 支持。

在这五项稳定前，不并行铺开高维护成本的 Cookie/签名平台。

### 5.2 单个平台完成定义

一个平台只有满足以下条件才算完成：

- 输入房间号和完整 URL 均可解析。
- 在线、离线、不存在三种状态明确。
- 原画/多画质可以列出并切换。
- 多线路可枚举、失败自动切线。
- 推荐、分类、分类房间列表可用。
- 支持项的主播/房间搜索可用。
- 弹幕能连接、重连、去重、切房不串房。
- 真实房间 Windows 连播 30 分钟无明显泄漏。
- fixture 单测与线上 smoke 都通过。

---

## 6. UI 对齐目标（参考 SFVideoLive Web）

### 6.1 视觉基线

SFVideoLive 当前视觉语言：

- 默认深色背景：`#181818`
- elevated surface：`#1f1f1f`
- soft surface：`#141414` / `#2a2a2a`
- 主品牌色：金黄 `#f3d04e`
- 主文字：约 87% 白
- 次文字：约 55% 白
- 边框：`#3a3a3a`
- 圆角：4 / 8 / 12px 三级
- Fluent 风格 motion、Mica/Acrylic 表面
- 平台品牌色：斗鱼橙、虎牙黄、B站粉/蓝、抖音红、Twitch 紫等

Flutter 中建立 `ZishuTheme` 与 design tokens，不在 Widget 内散落颜色数字：

```text
AppColors
AppSpacing
AppRadius
AppTypography
AppMotion
PlatformBrandCatalog
```

浅色主题同步实现，但 Windows 第一轮以深色高还原为验收基线。

### 6.2 响应式壳层

#### Desktop / Windows（优先）

- 顶部固定导航，高度约 44px。
- 左侧：Logo、首页、分类、我的分类。
- 中间：平台图标 Tabs。
- 右侧：我的关注、搜索、主题、账号。
- 首页可显示左侧目录 rail/drawer：收起约 52px，展开约 220px。
- 播放页不显示目录 drawer，视频占主要空间。

#### 窄屏 / Android / Web Mobile

- 主导航切换到底部约 56px。
- 平台列表改为顶部横向 strip。
- 播放页侧栏堆叠到视频下方，或在沉浸模式变为侧滑 sheet。
- 所有主要点击目标不小于 36–48px。

### 6.3 路由/页面清单

Flutter 路由语义与 SFVideoLive 对齐：

```text
/                         登录后关注，否则全平台首页
/all                      全平台首页
/all/category/:key        跨平台分类房间
/follow                   我的关注
/time                     解析耗时基准（对齐 web `TimeView.vue`：冷解析 vs 缓存命中）
/timeline                 动态时间线（本仓私有页面，web 无对应路由）
/user                     平台凭证（cookie/token 管理，web 只在 `/user` 弹登录框）
/search                   搜索已是全局对话框，该路径仅作深链兼容 → 重定向 `/all`
/:site                    平台首页
/:site/category           平台分类索引
/:site/category/:cid      分类房间
/:site/anchor/:id         主播主页
/:site/play/:id           播放页
/settings                 Flutter 新增独立设置页或对话框
```

Windows 使用 `go_router`（见 7.0）。路由参数只保存 site/id/cid，不在 route 中传大型对象。

### 6.4 页面布局与功能

#### A. 全平台首页 / 平台首页

- 平台 Tabs。
- 房间卡片自适应网格。
- 卡片包含封面、平台角标、直播状态、标题、主播、分类、在线数据、促销标签。
- 无限滚动/分页。
- 下拉刷新用于触摸端，Windows 提供刷新按钮/F5。
- 卡片 hover 预取房间信息；点击进入播放。
- 不支持浏览的平台展示房间号/URL 直达输入。

#### B. 分类索引

- 大类 Tabs + 子分类网格。
- 我的分类收藏与管理。
- 跨平台热门分类。
- 目录 drawer 快速切换平台和分区。
- 分类图标本地缓存，失败显示稳定占位图。

#### C. 分类房间列表

- 标题、分类信息、平台色。
- 房间网格与分页/无限滚动。
- 支持返回分类索引和 drawer 快切。

#### D. 播放页

布局：

```text
顶部应用导航
┌──────────────────────────────┬──────────────┐
│ 房间标题/分类/返回            │              │
├──────────────────────────────┤ 弹幕/关注/设置 │
│                              │ 侧栏          │
│       media-kit 视频          │              │
│       + 弹幕 overlay          │              │
│       + 自定义控制条          │              │
└──────────────────────────────┴──────────────┘
```

功能目标：

- 播放/暂停、音量、静音。
- 清晰度与 CDN 线路切换。
- 刷新/重解析。
- 全屏、网页全屏语义、画中画（平台支持时）。
- 播放进度语义针对直播调整，显示延迟/追帧状态而非普通 VOD 为主。
- media-kit 错误分类、自动切线路、有限重试。
- 弹幕 overlay 开关、字号、速度、透明度、区域、密度设置。
- 右侧聊天列表，展示昵称、颜色、粉丝牌、用户等级、表情。
- 房间信息、分类跳转、在线/贵宾/粉丝团等平台统计。
- 关注、特别关注、开播提醒。
- 关注房间推荐 Tab。
- 桌面侧栏可折叠；全屏时转沉浸式侧面 sheet。
- 切房 generation fence，旧请求、旧弹幕、旧播放事件不得污染新房间。
- 保持声音会话，切房时遵循用户静音选择。

#### E. 我的关注

- 开播、回放、离线排序。
- 卡片/Tile/Row 三种展示密度。
- 平台筛选。
- 批量导入、批量删除。
- 批量开启/关闭提醒。
- 刷新状态和封面。
- 特别关注视觉区分。
- 登录后云同步，未登录可使用本地关注。

#### F. 搜索

- 全局弹窗/命令面板入口。
- 平台切换。
- 主播搜索、房间搜索。
- 房间号或完整 URL 直接进入。
- 键盘上下选择、Enter 打开、Esc 关闭。
- 最近访问与历史搜索（Flutter 可在后续补充）。

#### G. 主播主页

- 头像、昵称、平台、关注状态。
- 当前直播状态和进入直播间。
- 主播历史/相关房间（平台支持时）。

#### H. 时间线

- 按开播时间或事件时间排列关注动态。
- 平台筛选。
- 与开播提醒及关注状态共用数据源。

#### I. 账号与同步

- 登录、注册、退出。
- 本地关注与云端关注同步。
- 偏好同步。
- 远程 `data-server` 与解析 server 完全分离。

#### J. IPTV

- M3U URL/文件导入。
- 源增删改、刷新。
- group-title 分类。
- HLS/FLV/MPEG-TS 播放。
- 无弹幕，播放侧栏替换为频道列表/EPG（如后续支持）。

### 6.5 Windows 交互增强

- 窗口最小尺寸与自适应断点。
- 键盘：Space 播放、M 静音、F 全屏、方向键音量、Esc 退出沉浸、Ctrl+K 搜索、F5 刷新。
- 鼠标 hover、滚轮音量可配置。
- 单实例。
- 系统托盘与关闭行为设置。
- Windows 通知用于开播提醒。
- 窗口尺寸、位置和最大化状态持久化。
- 文件选择器用于 M3U/关注导入。

---

## 7. UI 工程设计

### 7.0 技术栈选型（2026-09-09 确认）

| 职责 | 方案 | 采纳状态 |
|---|---|---|
| UI 基础 | Flutter Material 3 | 已采用 |
| 视觉系统 | ThemeData + ThemeExtension（`ZishuTokens` 承载 SFVideoLive 色彩/间距/圆角/平台品牌色，深浅主题各一份实例） | 立即采用 |
| 状态管理 | Riverpod（`AsyncValue` 承载加载/错误/数据三态；controller 放 `features/*/application/`） | 立即采用 |
| 路由 | go_router（路由语义仍按 6.3；route 参数只存 site/id/cid） | 立即采用 |
| HTTP | dio（UI/server 请求侧沿用） | 已采用 |
| 播放 | media-kit + `LivePlayer` 抽象 | 已采用 |
| 图片缓存 | cached_network_image（封面/头像，配占位与错误占位 widget） | 立即采用 |
| 数据模型 | 契约模型（`live_parser`）**手写** fromJson/toJson，不引入 codegen；UI 本地持久化实体在 M4 引 Drift 时再评估 freezed | 决议 |
| 本地数据库 | Drift（关注、历史、搜索记录、缓存、设置） | M4 引入 |
| 简单配置 | shared_preferences（主题、音量、布局偏好） | U7 引入 |
| 桌面窗口 | window_manager（尺寸/位置/最大化/关闭行为） | M4 引入 |
| 文件选择 | file_picker（M3U、关注导入） | M4 引入 |
| 日志 | `logging` 或自建 facade（解析/播放/弹幕诊断共用字段规范见 11.3） | M2 引入 |
| UI 组件预览 | Widgetbook（可选） | 暂缓 |
| 测试 | flutter_test + golden test | 样式稳定后引入 |

> 决议理由：`live_parser` 是纯 Dart 契约包且为三端单一真源，引入 build_runner 会增加三端与 server 的代码生成链路；契约模型字段已稳定且手写量可控。freezed 的不可变/union 价值在 UI 侧由 Riverpod `AsyncValue` 与 Drift 生成模型覆盖。

### 7.1 状态管理

使用 **Riverpod**（`flutter_riverpod`），不让 Widget 直接持有网络和播放器编排。

状态分层：

```text
Gateway/Repository -> UseCase -> Controller/Notifier -> Widget
```

控制器以 Riverpod provider 暴露；`AsyncValue` 表达 loading/error/data，Widget 不写 try/catch 业务分支。

关键 controller：

- `BrowseController(site, category)`
- `PlayController(site, roomId)`
- `PlayerController`
- `DanmakuController`
- `FollowController`
- `FollowStatusController`
- `SearchController`
- `ThemeController`
- `SettingsController`

播放页必须继续拆分：房间解析、media-kit 会话、弹幕、统计、关注、布局/控制条不能堆进单个 State。

### 7.2 media-kit adapter

业务层只依赖：

```dart
abstract interface class LivePlayer {
  Stream<PlayerSnapshot> get snapshots;
  Future<void> open(StreamLine line);
  Future<void> play();
  Future<void> pause();
  Future<void> setVolume(double value);
  Future<void> setMuted(bool value);
  Future<void> dispose();
}
```

`MediaKitLivePlayer` 放在 `platforms/common/playback/`。Widget 可以使用 `VideoController` 的 view adapter，但不直接承担重试、选线和状态机。

### 7.3 图片与资源

- 平台图标、Logo、粉丝牌 fallback、用户等级素材从 SFVideoLive catalog 同步。
- 网络封面统一走 `cached_network_image`：磁盘缓存、占位图、错误占位与防盗链 headers。
- Web 需要通过 server 的 image proxy 处理不能直连的图片。
- Windows/Android 可以直接带 headers 获取，仍统一走 ImageRepository。

---

## 8. 双轨并行开发方式

解析轨与 UI 轨通过 contracts/fixtures 解耦，不互相等待。

### 8.1 P 轨：Parser

```text
P0  package 骨架 + contracts + fixtures
P1  斗鱼完整链路
P2  虎牙完整链路
P3  B站完整链路
P4  cross browse + catalog
P5  IPTV
P6  抖音
P7  长尾平台
P8  Dart streaming-server
P9  弹幕与平台增强
```

### 8.2 U 轨：UI

```text
U0  design tokens + app shell + router
U1  顶部导航 + 平台 tabs + drawer
U2  房间卡片 + 首页网格（fixture repository）
U3  分类页
U4  播放页 shell + media-kit adapter
U5  自定义控制条 + 画质/线路
U6  弹幕 overlay + 聊天侧栏（fixture stream）
U7  关注页
U8  搜索/主播/时间线
U9  响应式 Web/Android 适配
```

### 8.3 轨道交汇点

| Gate | Parser 交付 | UI 交付 | 验收 |
|---|---|---|---|
| G0 | Dart models + JSON fixtures | design system + app shell | UI 完全用 fixtures 运行 |
| G1 | 斗鱼 resolve/recommend | 首页 + 播放页 | Windows 斗鱼浏览→播放 |
| G2 | 斗鱼 categories/search/danmaku | 分类/搜索/弹幕 | Windows 斗鱼功能闭环 |
| G3 | 虎牙+B站 | 平台 tabs/cross home | 三平台切换稳定 |
| G4 | Dart server API | Flutter Web HTTP gateway | 新 Web 主链路可用 |
| G5 | follow snapshot/catalog | 关注/时间线 | Windows 功能接近 SFVideoLive |
| G6 | Android direct parser | 响应式与生命周期 | Android APK 主链路可用 |

UI 轨使用 `FixtureLiveRepository`，Parser 轨使用 golden tests，因此二者可以真正并行。

---

## 9. 里程碑（Windows 优先）

### M0：架构冻结与基线整理

- 建 `packages/live_parser`。
- 定义公开 models/interfaces/errors。
- 把当前临时 `StreamingServerClient` 包到 gateway 后面。
- 建 Flutter design tokens 和路由壳。
- 清除文档中“Windows 直调 Dart 源码放 app 内”的模糊表述，统一为 package。

验收：`flutter analyze`、现有播放 smoke 通过；新代码无 legacy import。

### M1：Windows 斗鱼最小闭环

- Dart 实现斗鱼推荐、分类、房间解析、画质/线路。
- Windows 改为 direct gateway，不再请求远程 streaming-server 完成斗鱼解析。
- 首页采用 SFVideoLive 风格房间网格。
- 点击卡片进入 media-kit 播放页。
- 播放页完成基本控制和手动房间输入。

验收：断开远程 streaming-server 后 Windows 仍能浏览斗鱼并播放。

### M2：Windows 斗鱼完整闭环

- 搜索、弹幕、切画质、切线路。
- 关注本地存储。
- 播放页右侧聊天/设置/关注推荐框架。
- 全屏、侧栏折叠、快捷键。

验收：斗鱼连续播放 30 分钟；切换 10 个房间无串房、无明显资源增长。

### M3：Windows 三平台

- 虎牙、B站 parser。
- 平台 tabs、分类、搜索与弹幕。
- 全平台聚合首页前三站。
- 统一 platform capability 和品牌资源。

验收：三平台浏览、搜索、播放、弹幕均可用。

### M4：关注与完整导航

- 关注页面三种布局。
- 批量导入/删除/提醒。
- 主播页、时间线、我的分类。
- data-server 登录和云同步。
- Windows 开播通知。

验收：Windows 产品主功能达到 SFVideoLive 的日常使用范围。

### M5：Dart streaming-server + Flutter Web

- 搭建 `packages/live_server`。
- 兼容核心 `/api` 契约。
- 新 Flutter Web UI 复用同一 features。
- Web 图片/流代理和 SSE/WS。
- 旧 Node server 对未迁平台 fallback。

验收：Flutter Web 可完成与 Windows 相同的前三平台主链路。

### M6：Android

- direct parser adapter。
- media-kit Android libs。
- 移动端导航、播放堆叠布局、沉浸横屏。
- 生命周期、通知、权限、网络安全配置。

验收：真机安装、浏览、播放、弹幕、切后台恢复。

### M7：平台补齐和旧链路退役

- 抖音、YY、Twitch、快手、SOOP、YouTube、小红书、IPTV 完整对齐。
- 达到 SFVideoLive 平台能力矩阵。
- Dart server 覆盖全部新平台后，Node server 退为归档/紧急 fallback。
- 删除不再需要的 legacy Web 构建门，但保留历史 tag。

---

## 10. 测试与质量门

### 10.1 Parser 测试

每个平台具备：

1. URL/房间号输入归一单测。
2. 上游 JSON/HTML fixture 解析单测。
3. 签名算法固定向量测试。
4. 在线/离线/不存在测试。
5. 画质与线路映射测试。
6. 超时、429、结构变化错误测试。
7. 网络 smoke（非每次 CI 强制）。

### 10.2 Golden parity

迁移期间对同一房间分别调用：

- 旧 Node streaming-server
- 新 Dart live_parser / live_server

结构化比较：

- 房间元信息
- 是否开播
- 画质集合
- 线路格式和数量
- 播放 URL host/path 形态
- 分类列表
- 搜索结果关键字段

签名 URL 不比较完整 query 字符串，只比较必要语义。

### 10.3 Flutter 测试

- design token 和组件 golden test。
- 路由测试。
- controller 状态测试。
- 首页 fixture widget test。
- 播放编排测试使用 fake player，不在 VM test 初始化真实 media-kit NativePlayer。
- Windows 集成 smoke 使用真实 media-kit。

### 10.4 必过命令

```powershell
flutter analyze
flutter test
flutter build windows --debug -t lib/main.dart

# Parser
cd packages/live_parser
dart analyze
dart test

# Web 阶段
cd packages/live_server
dart analyze
dart test
flutter build web -t lib/main_web.dart
```

### 10.5 运行质量

- 真实直播连播 30/120 分钟。
- 每个平台连续切房 10 次。
- 网络断开/恢复。
- 解析 URL 过期后的自动刷新。
- 睡眠/唤醒。
- Windows 最小化/恢复。
- 高 DPI 100/125/150/200%。
- 1366×768、1920×1080、2560×1440、窄窗口布局。

---

## 11. 数据、配置与安全

### 11.1 配置分离

```text
解析配置：UA、站点 timeout、cache TTL
用户偏好：主题、音量、弹幕、画质习惯
用户数据：关注、账号 token
敏感配置：平台 Cookie、代理凭据
```

不得把长期 Cookie 或 token 提交到 Git。

### 11.2 本地数据目录

Windows 建议：

```text
%APPDATA%/zishu_flutter/
├─ settings.json
├─ follows.json
├─ cache/
├─ catalog/
├─ cookies/
└─ logs/
```

便携模式后续可支持 `<exe>/data/`，但不能通过“相对入口若干级”猜路径。

### 11.3 日志

统一结构化日志字段：

```text
time level subsystem site room operation elapsed errorKind message
```

默认脱敏 URL query、Cookie、token、签名参数。

---

## 12. 风险与处理

| 风险 | 处理 |
|---|---|
| Dart 中移植复杂签名成本高 | 先无高风险签名平台；保留旧 server fallback；签名做独立模块和向量测试 |
| 上游接口频繁变化 | fixture + 真实 smoke + 错误分类；按站点独立发布修复 |
| UI 与 parser 双轨接口漂移 | contracts package/fixture 先行；Gate 验收；UI 不依赖临时 JSON Map |
| media-kit 平台行为差异 | LivePlayer abstraction；各平台真实集成测试 |
| Web CORS/Cookie/headers | 全部经 Dart live_server；浏览器不直接解析 |
| 弹幕协议复杂且高频 | codec 与 transport 分离；Isolate 解析；有界队列与去重 |
| 新 UI 范围过大 | Windows 斗鱼闭环优先；按 M0-M7 顺序，不先铺所有空页面 |
| 旧代码诱导反向依赖 | CI 检查 `lib/src` 禁止 import `legacy` |
| 授权风险 | 从 AGPL 项目复制的代码/算法需保留来源并按整体分发许可处理 |

---

## 13. 下一步执行清单

文档确认后，立即启动下面两条并行轨道。

### Parser 轨第一批

1. 创建 `packages/live_parser`。
2. 建 `RoomPayload/StreamQuality/StreamLine/RoomSummary/SiteCapabilities`。
3. 建 `RoomResolver/BrowseRepository/SearchRepository/DanmakuConnector`。
4. 从 SFVideoLive 的斗鱼实现整理 fixture 和算法清单，不直接耦合 server 路由。
5. 实现斗鱼推荐 API。
6. 实现斗鱼房间元信息、HLS/FLV 与多档线路。
7. 建旧 Node vs Dart parity script。

### UI 轨第一批

1. 建 `ZishuTheme`，采用 SFVideoLive 的 `#181818 + #f3d04e` 基线。
2. 建 `AppShell`：44px 顶部导航、平台 tabs、工具区。
3. 建 `RoomCard`、自适应 `RoomGrid`，先使用 fixture repository。
4. 将当前播放验证页拆成 `PlayFeature`、`MediaKitLivePlayer`、`PlayController`。
5. 建 SFVideoLive 风格播放布局：视频主区 + 右侧 328px panel。
6. 保持现有斗鱼播放 smoke 始终可运行。

### 第一交汇目标

```text
Windows 启动
  -> SFVideoLive 风格首页
  -> 展示 Dart parser 获取的斗鱼在播卡片
  -> 点击房间
  -> media-kit 播放
  -> 可切画质/线路
```

达到该目标前，Web 和 Android 只维护架构可编译骨架，不抢占 Windows 主线资源。
