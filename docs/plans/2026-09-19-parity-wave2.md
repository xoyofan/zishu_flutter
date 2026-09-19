# 播放域对齐 Wave 2:superpowers 并行计划(2026-09-19)

> 方法论:dispatching-parallel-agents(独立域识别 → 聚焦任务卡 → 同响应并行派发 → 主代理集成验证)。
> 基线:app 508/0;parser 301/10skip;analyze 双 0。
> 真源:F:\project\SFVideoLive(crates/live-parser 为最新;services/streaming-server 次之;apps/web 为 UI 基准)。

## 轨 A(parser 健壮性)—— 独占:packages/live_parser/lib/src/platforms/{soop,yy}/**、registry 缓存层、catalog(不改 models.dart/contracts.dart)

| 任务 | web 真源 | 验收 |
|---|---|---|
| A1 分类缓存空壳分组校验 | commit e389570(虎牙分类不显示的根因:空壳分组被持久化) | 缓存读取时校验 groups 非空且 items 非空,空壳作废重拉;测试 +1 |
| A2 soop opcode 白名单 | commit 768f8cd | soop danmaku 只放行聊天/系统白名单 opcode,未知帧丢弃;测试 +1 |
| A3 YY 弹幕禁用 | commit 2b2f66f(官方游客 WS 协议失效) | YY danmaku session 连接即进 disconnected(能力标记不支持),UI 开关禁用链路不炸;测试 +1 |

## 轨 B(播放体验提速)—— 独占:lib/src/features/play/application/play_provider.dart、lib/src/platforms/common/playback/**(media_kit 配置/取流优选)

| 任务 | web 真源 | 验收 |
|---|---|---|
| B1 起播 FLV 优选 | commit 45241d2/a074399(斗鱼首帧 2.3s→1.0s) | 同画质多线路时首选 FLV 格式线路起播(现有 preferredLine 语义之上加格式权重);不破坏既有画质/线路选择测试 |
| B2 HLS 回放缓冲上限 60s | commit 7515cff | media-kit/mpv 配置 demuxer-max-bytes/cache 上限(对齐 60s 语义);真实链路不回归(单测以配置注入断言) |

## 轨 C(UI 死角)—— 独占:lib/src/features/play/widgets/play_side_panel.dart(仅 _SideHeader 区)、lib/src/features/browse/widgets/room_card.dart

| 任务 | web 真源 | 验收 |
|---|---|---|
| C1 侧栏头通知铃铛接通 | SideHeader.vue:373-416(bell/bell-off + amber 态) | 死按钮 `onPressed:(){}` → 切换 remindOn(关注条目已有的开播提醒字段,settings/follow 链路已存在);无关注条目时保持占位 |
| C2 侧栏头外链按钮接通 | SideHeader.vue:397-421 | 打开房间 web 页(payload.url / room_id 拼 web url,launchUrl);payload 无 url 时禁用 |
| C3 房间卡 tags | commit 07e673a(主播名+tags 并排,twitch localizedName 前 3) | RoomSummary 已有 tags 字段则展示;无字段则记录契约缺口并跳过(不扩契约) |

## 轨 D(契约补全,主代理自留)—— 独占:packages/live_parser models.dart/contracts.dart + platforms/huya/danmaku.dart、bilibili/danmaku.dart、search 链路

| 任务 | web 真源 | 验收 |
|---|---|---|
| D1 DanmakuMessage.id | backlog:huya sMessageId / bilibili id_str | 契约加 id(String,空=未提供);huya/bilibili 提取;session 内 _chatDedup 优先按 id 去重(空 id 回落 user+text);测试 +2 |
| D2 搜索 type 分流(评估,可推迟) | web SearchDialog type=anchors/rooms | 只做契约调研与设计注记;若 SearchRequest 无服务端配套则本轮不动,记录方案 |

## 收尾(主代理)

`_gate.py` 全量 → 分轨提交(每轨独立 commit)→ 推送 → release 重建 → schtasks 拉起。

## 本轮不做

单清晰度档解析(resolve 契约面宽)、twitch emote、徽章图片态、搜索 type 实装、关注批量导入、pad-x 全局替换 —— 记录于 backlog。
