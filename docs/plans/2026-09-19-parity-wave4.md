# 播放域对齐 Wave 4:弹幕显示修复 + 侧栏设置重构 + 虎牙贵族(2026-09-19)

> 方法论:dispatching-parallel-agents。基线:app 533/0(合流);parser 325/10skip;analyze 双 0。

## 用户口径(4 项)
1. 虎牙 SVIP 还没显示;VIP/SVIP 图标要更好看,SVIP 用 gif 动态。
2. 飘屏弹幕开着却不显示 —— 「我只是不用显示昵称,内容还是需要显示的」(**回退去昵称改坏的 bug**)。
3. 部分主播的在播分类在关注里仍看不到(上一轮 agent_ea4b5544 修复中,并行等待)。
4. 侧栏设置的「弹幕样式」是飘屏的,去掉;集成 web 的「聊天弹幕」速度与开关逻辑。

## 轨划分(文件互斥)

| 轨 | 独占文件 | 任务 |
|---|---|---|
| 1 | `lib/src/features/danmaku/**` | 飘屏空白 bug:_buildParagraph 只遍历 span.children,buildSpan 单段化后 children=null → 零绘制。修:span.text 非空先 addText。回归测试钉住「单段 TextSpan 渲染非空宽度」。 |
| 2 | `lib/src/features/play/widgets/play_side_panel.dart`(设置区)、`lib/src/features/follow/application/settings_provider.dart`、`_ChatTab` | 侧栏设置重构:去掉「弹幕样式」入口(飘屏的,用户口径);集成 web SideSettingsTab:41-105 的聊天弹幕设置 —— 内联滑杆透明度 10-100 / 字号 12-24 / 间距 0-16 / 速度 1-10 + 「每N秒一条/全量」节流,控制**侧栏聊天区**消息渲染;settings_provider 扩展对应字段并持久化。 |
| 3 | `packages/live_parser/lib/src/platforms/huya/**`(refresher/贵族查询)、models(如需) | 虎牙 VIP/SVIP 数据:对齐 web huya-wup.ts / crates huya.rs 的贵族查询(wup 或 HTTP 兜底),refresher 提取 vip 档位文本(VIP/SVIP);聊天行消费已有 userLevel。 |

## 并行安排

- 第一波并行:轨 1 + 轨 2 + 轨 3(parser 部分;轨 2/3 无文件交集)。
- 第二波(轨 2/3 完成后):聊天行虎牙贵族徽章图片化(gif 动态 SVIP / 静态 VIP,web emblem CDN 调研)—— 依赖轨 2 的文件与轨 3 的数据。
- 并行等待:上一轮 agent_ea4b5544(refresher category 提取修复)完成后集成。

## 收尾

`_gate.py` 全量 → golden 定性 → 分轨 commit → 推送 → release 重建 → 拉起。

## 不做

徽章图片态全套(粉丝牌图片)、搜索 type 实装之外的 web 搜索细节、关注批量导入 —— 维持 backlog。
