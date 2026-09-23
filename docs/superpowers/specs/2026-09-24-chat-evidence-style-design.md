# 真实网页聊天样式与徽章表情接线设计

**日期：** 2026-09-24  
**状态：** 已确认设计，待实施  
**范围：** 现有已注册平台的聊天弹幕显示；不新增平台  
**证据源：** `F:/project/SFVideoLive/apps/web/src` 源码 + 本地 Vite 预览实际渲染

## 1. 真实网页取证

已在 `SFVideoLive/apps/web` 运行 `npm run preview -- --host 127.0.0.1 --port 8083`，先加载根路由后通过 History API 进入 `/douyu/play/5720533`，等待真实聊天连接并读取 DOM/computed style。临时截图保存在本机 `/tmp/sfvideo-chat-live.png`，不提交构建产物或临时图片。

实际渲染到的聊天项（同一页面的一条实时消息）：

- `.chat-item`：`font-size: 14px`、`line-height: 1.48`、正文主色 `rgba(255,255,255,.87)`。
- 斗鱼用户等级：`LV13`，约 `26.47×16.09px`，`border-radius: 2px`，文字约 `8.96px`，`margin-right: 1.96px`，`vertical-align: 1.96px`，背景 `linear-gradient(90deg, rgb(5,150,105), rgb(16,185,129))`。
- `.chat-item__badges` 使用 `display: contents`，所以等级、粉丝牌、大航海与用户名/正文处在同一段富文本流中。
- `SideChatTab.vue` 对所有徽章/等级/表情图片统一应用 `filter: brightness(1.14) contrast(1.08) saturate(1.1)`。
- 实际页面同时显示 `弹幕已连接`、聊天正文和等级徽章；这证明样式与真实消息字段必须一起接线，不能只做静态占位图。

## 2. Web 源码中的样式真源

| 能力 | Web 真源 | 关键规则 |
|---|---|---|
| 聊天行布局 | `apps/web/src/components/play/play-side/SideChatTab.vue` | `display: contents`；昵称/正文同一行；徽章顺序为用户等级 → 粉丝牌 → guard |
| 粉丝牌 | `components/chat/ChatFanBadge.vue` | 平台分支、图片失败回退、tooltip、尺寸和垂直对齐 |
| 用户等级 | `components/chat/ChatUserLevelBadge.vue` | 抖音 honor、B站 wealth、虎牙 VIP emblem；文字回退与图片回退 |
| 虎牙超粉 | `components/chat/ChatHuyaSuperFanBadge.vue` | `vFlag` 控制，金色斜体 `V` 或 `vLogo` 图片 |
| 富文本表情 | `components/chat/DanmakuRichText.vue` | emoji 有 URL 时 `<img>`，无 URL 时保留 `[名称]` 文本 |
| 平台开关 | `apps/web/src/config/platformCatalog.ts` | `CHAT_FAN_BADGE_IMG_ONLY_SITES`、`CHAT_FAN_BADGE_HIDE_LEVEL_SITES`、等级 kind/overlay 标志 |
| 资源优先级 | `utils/badges/platformBadgeStatic.ts`、`badgeImage.ts` | 本地静态资源 → 平台/协议 URL → CDN；逐级失败后文字/通用图回退 |

## 3. 平台显示矩阵

| 平台 | 粉丝牌真实样式 | 用户等级真实样式 | 表情/其它 |
|---|---|---|---|
| 斗鱼 | `bnn/bn` 团名、`bl/bnnl` 等级、`bimg` 协议图；无图用 `fans/{1..50}.png`；图上叠团名，不再叠等级数字 | `level/lv` 的 `LV N` 渐变文字胶囊，阈值 `[50,40,30,20,10]` | 当前协议无独立图片段，文本原样保留 |
| 虎牙 | 优先房间定制图；无可信图时按 7 档渐变条 + 等级圆盘 + 团名 | `DecorationInfo 11200` 优先 `v2` emblem；失败按消费等级渐变；图上叠白色等级数字 | `vFlag>0` 额外显示超粉 `V`/`vLogo` |
| B站 | `medal` 新协议优先，渐变 `to left`、边框/文字/等级色；无渐变用 `medal-frame.png` + 文字 | `info[4]` UL 渐变文字；`wealth` 有协议 key 时使用动态 wealth 图 | `guard_level=1..3` 独立显示总督/提督/舰长；表情 URL 走 `segments` |
| 抖音 | 等级 1..20 官方粉丝牌整图；失败红橙渐变圆盘 | `payGrade.field6`；honor 1..75 整图，失败紫粉渐变 | protobuf image piece 生成 emoji segment；无 URL 保留 `[名称]` |
| SOOP | `flag1` 位域生成订阅、管理员、铁粉、粉丝团，顺序固定；订阅图/本地分档图 + 月份角标 | 协议无数字用户等级，不伪造 UL | `0109 SVC_OGQ_EMOTICON` 生成真实图片 segment；保留现有并行改动 |
| Twitch | IRC `badges` 解析 broadcaster/moderator/subscriber/vip 等原生图；只显示图不叠文字 | 无统一 UL 字段 | IRC `emotes` 生成确定性 CDN image segment |
| 快手 | 协议当前只给文本，无可靠公开图片 URL；不猜图 | 无稳定等级字段 | `[贊]` 等文本原样保留，并登记为待抓包项 |
| YouTube | 无统一粉丝牌 | 无统一等级 | 官方 emoji/短代码只显示真实 Unicode 或原文本，不伪造图片 |
| YY/IPTV | 当前不提供可消费的聊天徽章能力 | — | 不渲染空壳徽章 |

## 4. 稳定模型增补

在 `packages/live_parser` 的纯 Dart model 中做向后兼容扩展：

1. `DanmakuBadge` 增加：
   - `iconUrl`：协议/官方图标 URL；
   - `vFlag`、`vLogo`：虎牙超粉标记；
   - 保留现有 `url` 作为 SOOP 订阅图/通用徽章 URL。
2. `DanmakuMessage` 增加：
   - `guard`：B站大航海等独立身份徽章，使用 `DanmakuBadge?`；
   - `userLevelIconUrl`、`userLevelBadgeStyle`、`userLevelIsPolished`、`userLevelColor`：不破坏现有 `userLevel: int`。
3. `DanmakuSegment` 增加可选 `name`，供图片 `alt`、Tooltip 和无 URL 文本回退使用；不改变现有 `text/url` 构造器语义。
4. 所有字段默认值保持空/0，旧 fixture 和旧 JSON 解析继续通过。

## 5. Parser 接线

### 5.1 斗鱼

从 STT 同步提取 `bn/bnn`、`bl/bnnl`、`bimg/bimgurl/badgeimg`、`bc`，填充 `badges` 单项和旧兼容字段；用户等级继续取 `level/lv`，不带图片 URL（Web 已确认 CDN 图不可用）。

### 5.2 虎牙

在 Tars decoration 读取中补 `BadgeInfo` tag 12/13/17，生成 `vFlag/vLogo`；`ConsumeLevelBadgeInfo` 读取 tag 1/2/3，填充 `userLevelIconUrl/userLevelBadgeStyle/userLevelIsPolished`。解析异常仍只丢徽章，不丢正文。

### 5.3 B站

从新 `info[0][15].user.medal` 与旧结构提取 medal；从 `guard_level` 1..3 生成 `DanmakuBadge(kind: 'guard', name: 总督/提督/舰长, color: ...)`；从 wealth 字段提取动态 icon URL。没有 guard/wealth 时保持空，不从用户等级猜测。

### 5.4 抖音

扩展 `DouyinChatItem`：保留 `payGrade` 等级，同时从 badge repeated field 提取粉丝牌 URL、等级、名称；从协议图标提取 honor URL/wealth 信息，填充新增用户等级字段。没有可靠 URL 时只显示等级/文字回退。

### 5.5 Twitch

解析 IRC tags 的 `badges` 字符串，按 Web 优先级选择/保留可识别徽章，填入 `DanmakuBadge(kind: 'twitch', url: ...)`；解析 `emotes` 时给 `DanmakuSegment.emoji` 写入 `name` 与 CDN URL。

### 5.6 SOOP

纳入当前并行的 `0109` 表情帧实现：校验字段、生成 `DanmakuSegment.emoji`、保留订阅/管理员/铁粉/粉丝团顺序；为该分支补 parser fixture 测试，避免只靠代码审阅。

## 6. Flutter 展示

### 6.1 聊天行

`chat_row.dart` 继续使用单段 `Text.rich`，顺序固定为：

```text
UserLevelBadge → FanBadge(s) → GuardBadge → 昵称：正文
```

`ChatRowData` 传递 `guard`、用户等级图标/样式字段；徽章和正文仍保持同一段落流，确保第二行从最左侧开始。

### 6.2 粉丝牌

扩展 `ChatBadgeImage` 接受协议/官方 URL，按“本地资产 → 协议 URL → 官方 CDN → 文字回退”加载；平台分支复用 Web 的尺寸、圆角、渐变、遮罩和 tooltip。Twitch 只渲染原生图片，不追加虚构文字。

### 6.3 用户等级与 guard

- 斗鱼/B站 UL 使用真实等级渐变文字；
- 抖音 honor、虎牙 emblem、虎牙消费等级、B站 wealth 使用协议 URL 优先、静态资源其次；
- 虎牙超粉 V 独立渲染；
- B站 guard 使用 Web 的小号描边文字 chip；
- 所有图片统一应用 Web 的 brightness/contrast/saturate filter。

### 6.4 表情

聊天行已有 `WidgetSpan` 图片能力，补 `name` tooltip/alt；SOOP `0109`、Twitch emote、抖音/B站有 URL 的 segment 均显示图片；快手/无 URL 情况保留文本，不生成占位图。

飘屏 Canvas 仍遵守现有纯文本绘制约束，本轮优先保证**聊天侧栏**与 Web `DanmakuRichText` 一致；飘屏图片化另立 Canvas 图片缓存任务，不用不可测的临时方案混入本轮。

## 7. TDD 与验收

### Parser

- 斗鱼：协议 `bimg/bc` → badge 字段；
- 虎牙：vFlag/vLogo、badgeStyle/isPolished；
- B站：wealth/guard + medal 优先级；
- 抖音：badge URL/name + honor URL；
- Twitch：IRC badges/emotes；
- SOOP：`0109` 表情帧和已有 0005 徽章回归；
- 所有测试先 RED，再实现。

### Flutter Widget

建立聊天样式矩阵测试，注入每平台一条 `DanmakuMessage`，断言：

- 徽章顺序、等级文本、tooltip；
- 斗鱼/虎牙/B站/抖音本地或协议图分支；
- 虎牙超粉 V；
- B站 guard；
- SOOP 多徽章 + 表情图片；
- Twitch badge/emote；
- 缺图回退文字；
- 图片 filter、尺寸和聊天行不溢出。

### 实际网页对照

保留一份取证记录（源码路径、路由、computed style、临时截图路径），不把临时截图或外部服务凭据提交到 Git。若 Web 预览或上游不可用，测试使用已记录 fixture，不把网络失败标成 PASS。

## 8. 推送与边界

本轮只改 `packages/live_parser` 弹幕模型/解析和 `lib/src/features/play` 聊天显示/测试；平台目录、房间统计、聚合和既有 UI token 不因本增补重复重写。完成后分别提交 parser/UI/文档，运行 parser analyze/test、根 analyze、design token guard、Flutter test、Windows debug build，再推送 `master`。

明确不声称修复：虎牙零消息、Twitch 弹幕连接、快手表情 URL 缺失、YouTube 个别源失败。这些是协议/网络问题，留在问题登记中，不用静态徽章或假图片掩盖。
