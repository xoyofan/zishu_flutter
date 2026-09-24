# Windows 直播站点统一契约设计

**日期：** 2026-09-24
**状态：** 待用户审阅
**范围：** `packages/live_parser` 的九个真实站点及 Windows 新产品消费层；不实现 Web/Android 产品链路。

## 1. 意图与成功标准

用户希望所有站点面对同一组接口与字段：公共字段统一，不能提供的字段留空；确有平台专属信息时，Windows UI 可读取**显式类型化扩展**。统一不仅限于数据模型，也包括站点接口。请求或协议失败不能伪装成空值。

完成后：Windows 浏览、房间详情、轻量刷新共用一个房间数据模型；九站通过同一站点抽象注册；UI 对通用字段无需按站点解包；特殊字段只能按类型访问；不支持的能力有明确 N/A，网络失败仍可诊断；原有播放、恢复、弹幕、搜索能力与 JSON 兼容行为不倒退。

## 2. 当前基线和约束

- `RoomPayload`（播放详情）和 `RoomSummary`（浏览/刷新）重复房间身份、标题、主播、封面、分类、状态等字段；前者有线路与 `fetchedAt`，后者有观众、关注及各统计列。
- `RoomSummary.online` 空串兼作“不在播”判据；它与真实缺失值混淆。迁移后**唯一状态真源是 `roomState`**，列表/刷新/播放均须从真实状态赋值；绝不从统计数字是否存在推断在线。
- `RoomResolver`、`RoomRecoveryResolver`、`RoomSummaryRefresher`、`BrowseRepository`、`SearchRepository`、`DanmakuConnector` 已存在；`SiteRegistration` 通过可空部件装配站点，Windows 的 `ParserBrowseSource` / `ParserRoomSource` 按注册项访问。
- `SiteDisplaySpec` 定义站点公开的统计列；`DanmakuMessage` 是独立消息模型，不属于房间记录。保持 `live_parser` 纯 Dart，Windows UI 不引入站点解析实现；不复制九站源码。

## 3. 选择：单一房间模型 + 统一站点抽象

### 3.1 房间记录 `RoomRecord`

用一个纯 Dart 不可变类型表示浏览列表、状态刷新与播放详情的**同一种房间**，不为每站造子类。必填标识：`site`、`roomId`、`roomState`；其余公共字段按语义分组：

- 展示：`title`、`anchorName`、`sourceUrl`、`cover`、`avatar`、`category`、`cid`、`cateNo`、`promoTag`、`startedAt`。
- 统计：`audience`（替代 `online` 的展示数值）、`followers`、`vip`、`svip`（替代语义模糊的 `diamondFans`）。统计字段沿用当前格式化字符串口径，站点差异由 `SiteDisplaySpec` 决定标签；没有实际值为 `null`，有效数值 `0` 不当作缺失。详情/列表并不保证每字段都有值。
- 播放：`streams`、`availableQualities`；非播放请求或离线返回空列表，不凭空制造播放地址。`source` 与 `fetchedAt` 用于来源/诊断，在列表无此信息时可空；错误通过异常或明确错误结果表达，不用“空房间”冒充成功。
- 特有信息：`RoomExtension? extension`。仅在统一公共字段不能无损表达、且 UI 确有展示需求时新增站点专属 `sealed` 子类型；以 `site` + 版本化判别标识进行序列化，Windows 只能用类型匹配访问。JSON 边界可用 `Map<String, dynamic>`，Widget 不接收松散 Map。无实际扩展的站点为 `null`，不为九站创建空子类。

`RoomRecord` 兼容现有 `isLive`、`isReplay`、`playUrl`、`qualityByName` 等只读行为；任何“未加载”统计值保持 `null`，UI 用统一 formatter 显示「—」。`roomState == live` 即在播，即使观众数缺失。未找到房间保留显式 `notFound` 语义；网络/协议异常直接抛错。

### 3.2 站点契约 `LiveSite`

一个供九站实现的纯 Dart 抽象站点类型，包含必需的 `id`、`name`、`capabilities`、`display` 和 `resolveRoom(RoomRequest) → RoomRecord`。可选能力以**可空的类型化接口部件**暴露：浏览、搜索、弹幕、轻量刷新、恢复重解析（例如 `BrowseRepository?`、`RoomSummaryRefresher?`）；不支持返回 `null`，支持后请求失败抛异常，禁止吞错返回空列表/空房间。`SiteCapabilities` 与接口部件是否存在保持一致，注册时用契约测试核查。

缓存包装仍在注册表出口统一负责；恢复重解析必须绕开缓存重新获取地址，**不能**因为接口合并而默认委托普通缓存解析。轻量刷新不得触发签名、取流或覆盖已有已知字段为空：调用侧对同一房间按“此次提供的字段覆盖，未提供的保留”合并；真实离线状态必须覆盖旧在播状态。`SiteRegistry` 对外只返回统一站点抽象；历史 `SiteRegistration` 在迁移期可作桥接，迁移完成删除无用适配，而非永久保留双套定义。

### 3.3 Windows 消费与空值语义

公共 UI 接收 `RoomRecord`，从 `roomState` 判断状态，从 `SiteDisplaySpec` 判断列是否适用，从字段的 `null` 判断本次无值：未声明的列不显示；声明但当前无值显示「—」。平台扩展由专门组件按明确的扩展类型渲染，公共 UI 不检查 JSON 键或复制站点解析逻辑。缺能力是 N/A，缺数据是「—」，失败是错误态，三者不可互换。弹幕仍返回统一 `DanmakuMessage`，其徽章/表情按现有结构处理，不并入房间记录。

## 4. 迁移和兼容策略

1. 先钉住现有九站 fixtures、JSON round-trip、`roomState`/空值契约及 Windows 当前行为。新增 `RoomRecord` 和 `LiveSite`，建立 `RoomPayload` / `RoomSummary` 到统一记录的**临时边界适配**；不一次重写所有平台网络协议。
2. 把 Windows 浏览、详情、刷新消费者切到统一记录；替换 `online.isNotEmpty` 的在播判断为 `roomState`，检查关注排序、离线/轮播标记、数据合并和音量/播放选择。站点按批次迁移，每批用现有 fixture 验证，不以测试用假数据替代在线验收。
3. 所有站点迁完再移除旧公共模型/桥接。旧 JSON 允许省略新字段、接受原 `online` / `diamondFans` 等旧键并归一；必要时向外输出旧键供迁移期消费者使用，记录移除条件，避免破坏已持久化数据。新 JSON 的 `null` 或缺键均表示未提供，不序列化伪造的零。
4. 若站点接口实际提供了某字段但映射遗漏，属于解析缺口，应补实现及 fixture；若上游无字段，保留 `null` 并标注来源；需要额外请求的统计信息不能因为统一模型而在列表逐房强制拉取。

## 5. 验收与风险

- `packages/live_parser`: `dart analyze`、全量 `dart test`、九站能力/结果形状与旧 JSON 兼容测试；补字段空值、真零、离线、轮播、刷新保留旧值、恢复绕缓存、可选接口异常传播等定向测试。
- 根工程：两个独立 package 的 `pub get` 后 `flutter analyze`、相关 `flutter test`、`flutter build windows --debug -t lib/main.dart` 与启用真实解析的 Windows Release 构建。
- 真机：在当前版本验证至少斗鱼/虎牙浏览→详情→播放→刷新→切线/恢复；平台扩展展示需用有实际扩展值的房间验证，字段缺失时不得误显示 0；记录截图/日志，不用构建通过代替真人/真实网络验收。
- 本次结构统一**不自动修复**虎牙零弹幕、Twitch 出口、进房黑屏等独立运行故障；保留 Windows 问题矩阵，分别追踪。

## 6. 非目标

本设计不新增 Web/Android 产品入口，不改变站点上游协议，不承诺每站都有关注数/VIP/表情图，不以继承的房间子类或 `Map` 扩展换取表面统一，也不一次性新增所有可能的专属字段。
