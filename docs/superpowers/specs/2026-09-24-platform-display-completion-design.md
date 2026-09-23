# 现有平台显示与解析字段补齐设计

**日期：** 2026-09-24  
**状态：** 已确认设计，待实施  
**范围：** 已注册的直播平台（不含新增平台）  
**目标：** 统一公共字段显示、补齐平台独有字段/徽章的消费路径，并让 `all` 聚合覆盖现有可浏览/可搜索平台

## 1. 背景与问题

当前 `zishu_flutter` 已有 10 个注册目标平台（`douyu`、`huya`、`bilibili`、`douyin`、`kuaishou`、`yy`、`twitch`、`soop`、`youtube`、`iptv`）和大部分主链路，但平台字段与 UI 消费仍分散：

- `RoomSummary` 已有 `followers`、`vip`、`diamondFans`、`promoTag`、`roomState` 等字段，但不同页面只消费其中一部分。
- 播放页桌面侧栏和移动 `PlayMetaBar` 各自维护统计映射；平台标签与列定义依赖 `site == ...` 分支。
- `SearchHit.fans` 已被斗鱼、虎牙、B站、抖音等 parser 填充，但搜索结果没有显示。
- `all` 浏览和搜索仍默认只聚合斗鱼/虎牙/B站；已注册的抖音、快手、YY、Twitch、SOOP、YouTube 没有进入相同的聚合路径。
- `xhs` 仍存在于 Flutter fixture 品牌目录，但不在真实 parser 注册表；本轮不把它伪装成已支持平台。
- IPTV parser 存在空源占位，本轮不纳入直播平台聚合和统计显示。

本设计把“字段是否存在、字段叫什么、字段如何显示”收敛到 `live_parser` 的稳定契约；UI 只消费契约和值，不新增松散 `Map<String, dynamic>`，不复制站点解析逻辑。

## 2. 目标与非目标

### 2.1 目标

1. 为现有注册站点声明公共房间统计列和平台化标签：观众/观看、贵宾、粉丝勋章、粉丝团、钻粉、超粉、大航海、会员、订阅。
2. 让桌面播放侧栏和移动播放信息条共享同一份字段解析、格式化和空值策略。
3. 补齐现有来源能够真实提供的开播时间，并沿 `RoomSummary`、关注刷新、JSON 和本地持久化链路保留。
4. 让 `all` 浏览、全平台搜索和播放页推荐按注册表能力动态纳入现有平台；单站失败隔离，继续保持可预测的请求上限。
5. 搜索结果显示平台和已有粉丝数；平台独有聊天徽章继续以 `DanmakuMessage` 的真实字段为准，缺字段时走明确的通用兜底。
6. 用参数化契约测试和 Widget 测试钉住每个已注册平台的公共字段、平台标签、缺失值和 all 聚合行为。

### 2.2 非目标

- 不新增 CC、小红书或其他平台。
- 不实现完整 `packages/live_server`、Web HTTP gateway、Android 生命周期/权限/通知。
- 不把 IPTV 源管理 UI 混入本轮；空源 IPTV 不进入 `all` 聚合。
- 不把“弹幕连接成功但没有消息”伪装成显示问题；虎牙零消息、Twitch 连接、特殊频道流失败等协议/网络问题单独登记，不用 UI 占位修复。
- 不为没有上游数据的字段填 `0`；缺数据与不支持必须可区分。
- 不改变 `DESIGN.md` 已有的色板、字号、间距、圆角和 elevation；新增 UI 只复用现有 token。

## 3. 方案与取舍

### 3.1 采用方案：共享展示契约

在 `packages/live_parser` 的纯 Dart model/contract 层增加：

- `RoomStatField`：`audience`、`vip`、`svip`。
- `RoomStatTone`：`audience`、`vip`、`svip`，只表达现有统计颜色语义。
- `RoomStatColumn`：`field`、平台化 `label`、`tone`。
- `SiteDisplaySpec`：`showFollowers`、`showStartedAt`、`roomStats`。
- `SiteRegistration.display`：每个站点注册时显式提供 `SiteDisplaySpec`。

`RoomStatField` 与 `RoomSummary` 的映射固定为：

| field | 数据来源 | 现有主题语义 |
|---|---|---|
| `audience` | `RoomSummary.online` / `RoomPayload.isLive` 对应热度 | `tokens.statAudience` |
| `vip` | `RoomSummary.vip` | `tokens.statVip` |
| `svip` | `RoomSummary.diamondFans` | `tokens.statSvip` |

`followers` 继续作为独立的“关注 N”字段，由 `showFollowers` 控制；`startedAt` 由 `showStartedAt` 控制。这样不会把没有独立颜色语义的关注数硬塞进三列统计。

### 3.2 站点声明矩阵

| 站点 | `showFollowers` | `showStartedAt` | `roomStats` |
|---|---:|---:|---|
| 斗鱼 | 是 | 是 | 观众、贵宾、钻粉 |
| 虎牙 | 是 | 否 | 观众、贵宾、超粉 |
| B站 | 是 | 否 | 观众、粉丝勋章、大航海 |
| 抖音 | 是 | 否 | 观众、粉丝团、会员 |
| SOOP | 是 | 是（`broadStart` 可用时） | 观看、订阅 |
| Twitch | 否 | 是（`stream.createdAt`） | 观众 |
| 快手 | 否 | 否 | 观众 |
| YY | 否 | 是（`startTime`） | 观众 |
| YouTube | 否 | 是（yt-dlp `release_timestamp`） | 观看 |
| IPTV | 否 | 否 | 空（不进入本轮聚合） |

声明列代表“平台有这个展示语义”；本次请求没有拿到值时仍显示 `—`。没有声明的列不渲染，避免把不存在的能力显示成空白或 `0`。

### 3.3 不采用方案

- UI 单独维护 `site` 映射表：改动小，但 parser 能力、标签和移动/桌面显示仍会漂移。
- 让每个平台自己返回任意 JSON：违反项目稳定 model 约束，难以测试和跨端复用。
- 为每个房间列表项并发刷新完整统计：会把关注/播放页的轻量查询放大成 N 倍请求，破坏现有性能边界。

## 4. 数据流与组件边界

```text
平台 API / fixtures
  -> live_parser 纯 Dart RoomSummary / RoomPayload
  -> SiteRegistration.display（平台标签与列声明）
  -> shared parser source / follow refresh / search source
  -> Flutter shared display formatter
       -> desktop _SideHeader
       -> mobile PlayMetaBar
       -> SearchResultTile
  -> existing room/follow/timeline cards
```

### 4.1 `live_parser`

- `RoomSummary` 增加可选 `DateTime? startedAt`，并更新 `toJson/fromJson`。
- 不改变既有字段名称和旧 JSON 兼容行为；缺少 `startedAt` 的旧数据读回为 `null`。
- 能从现有真实响应得到开播时间的站点补齐该字段：
  - 斗鱼：`betard.show_time`；
  - SOOP：dashboard `station.broadStart`；
  - Twitch：GQL `stream.createdAt`；
  - YY：`detail.startTime`；
  - YouTube：yt-dlp `release_timestamp`。
- 虎牙、B站、抖音、快手当前来源没有稳定的开播时间，保持 `null`，不猜测。
- `follow_provider` 的 `_mergeRefreshed`、本地 JSON 恢复/持久化保留 `startedAt`；刷新没有值时不清除已有值。

### 4.2 注册与能力

每个 `build*Registration()` 显式传入 `display`，不新增 UI 依赖。注册表提供纯 Dart 查询 helper，Flutter 通过 `live_parser` 公共导出读取，不直接 import 站点实现。

`SiteDisplaySpec` 只描述展示语义，不把 `media-kit`、Flutter 或 Web API 带入 parser。

### 4.3 all 聚合

- 浏览聚合从同一 `SiteRegistry` 派生站点集合，纳入所有 `capabilities.browse && browse != null` 的现有站点，排除 `all` 和 IPTV 空源。
- 保持稳定顺序；每站请求量有上限，单站异常只损失该站结果。
- 搜索聚合从同一注册表派生 `search != null` 且至少一个搜索能力为真的站点；不使用 UI 的 fixture 目录决定真实能力。
- 播放页相关推荐沿同一浏览能力集合筛选，避免首页已经支持而推荐仍只显示前三站。
- 不把不支持弹幕的平台伪装为支持；YY/IPTV 仍走明确 N/A 空态。

### 4.4 Flutter 展示

新增一个小型共享 formatter/helper（放在 `lib/src/features/play/widgets/` 或 `lib/src/shared/presentation/`，不引入新 package）：

- 根据 `SiteDisplaySpec` 取得列和值；
- 统一 `—`、开播时间格式和 tooltip；
- 统一 `RoomStatField` 到 `ZishuTokens.statAudience/statVip/statSvip` 的颜色映射。

具体页面：

1. **播放桌面侧栏**：保留现有头像、平台、关注/超关、提醒、网页入口；统计行改为契约驱动。
2. **播放移动信息条**：保留现有四个公共槽位的兼容性；根据平台声明在可用时显示开播/平台统计，窄屏不溢出。既有锚点 `play-meta-stat-*` 保留。
3. **搜索结果**：从 `SearchHitItem.site` 传平台标识；`SearchHit.fans` 非空时显示粉丝数；`all` 搜索不再丢失平台归属。
4. **房间卡/关注卡/时间线**：不凭空增加三列统计；确保平台、分类、状态、热度、促销、轮播和上次开播标签使用统一 formatter。平台统计只在参考真源已有的信息头/移动条显示，避免窄卡过载。
5. **主播页**：至少显示真实 `RoomSummary` 已有的平台、状态、分类、热度；fixture-only 的粉丝/视频样例不冒充真实 parser 数据。若本轮无法接入真实主播资料接口，页面明确保留 fixture 语义并在文档登记。

### 4.5 平台独有聊天显示

- 斗鱼、虎牙、B站、抖音、SOOP 继续消费各自 `DanmakuMessage.badge*`、`userLevel`、`badges` 字段。
- Twitch/快手/YY/YouTube 若消息带徽章或等级，按通用可读兜底显示；若没有字段，不生成假徽章。
- `segments` 中有真实图片 URL 的表情继续走图片内联；无 URL 的表情保留协议文本，不猜测图片地址。
- 本轮只补“已有字段没有消费/标签不稳定”的显示缺口；不把弹幕协议连接故障归入本设计。

## 5. 错误与空值策略

| 情况 | 行为 |
|---|---|
| 平台已声明统计列但本次值为空 | 渲染 `—`，Tooltip 使用平台列名 |
| 平台未声明统计列 | 不渲染该列 |
| 平台不支持搜索/浏览 | 不进入真实入口或 all 聚合；fixture 模式仅用于 UI 测试 |
| 单个平台 all 请求失败 | 保留其它平台结果，记录失败，不让全平台空态 |
| 关注刷新失败 | 保留旧摘要，不把在线状态或统计抹成离线/零 |
| 旧 JSON 无新字段 | 使用默认值，保持向后兼容 |
| 平台特有数据格式异常 | parser 抛分类错误或返回空字段；UI 不直接解析 Map |

## 6. 测试与验收

### 6.1 TDD 顺序

每个行为先写失败测试并观察 RED，再写最小实现：

1. `live_parser`：展示描述契约、各站点矩阵、`RoomSummary.startedAt` JSON round-trip/旧 JSON兼容、开播时间解析。
2. `live_parser`：all 浏览/搜索站点集合、IPTV 排除、单站失败隔离、稳定顺序。
3. Flutter：共享统计 formatter、桌面/移动同源标签、缺失值、平台搜索标识和粉丝数。
4. Flutter：平台聊天徽章/等级/表情已有字段的通用兜底。
5. 回归：现有平台 workflow、关注、播放、golden 和静态 token 守卫。

### 6.2 验收命令

```powershell
# 解析轨
cd packages/live_parser
dart pub get
dart analyze
dart test

# UI 轨
cd F:\project\zishu_flutter
flutter pub get
flutter analyze
dart run tool/check_design_tokens.dart
flutter test
flutter build windows --debug -t lib/main.dart
```

Windows 主链路改动额外执行真实解析 debug 构建；不把没有网络/凭据的在线 smoke 伪装成自动化通过。若需要推送，先确认工作树只包含本轮变更，再按项目轨道规则分 commit 推送。

## 7. 交付拆分与推送

按轨道分开提交：

1. `parser`：展示契约、`startedAt`、站点注册与聚合。
2. `ui`：共享展示 helper、播放侧栏/移动条、搜索结果显示、回归测试。
3. `docs`：本设计、实施计划、平台矩阵和验收结果。

提交说明使用简体中文；不写入 token、Cookie、临时截图或构建目录。推送前必须重新执行本轮相关测试、`flutter analyze`、`dart run tool/check_design_tokens.dart`、parser 测试和 Windows debug build，并报告真实输出。

## 8. 已知非本轮阻塞项

以下问题继续保留在既有登记中，不因本轮显示契约完成而声称已解决：

- 虎牙弹幕“已连接但零消息”；
- Twitch 弹幕连接/出口稳定性；
- 快手表情真实图片 URL 尚未从协议取得；
- YouTube 个别频道源不可播；
- 飘屏多轨重叠观感；
- CC/小红书/IPTV 源管理与完整平台新增。

这些项目若后续处理，必须另立协议/平台任务，不回写为本轮显示字段已完成。
