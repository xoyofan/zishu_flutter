# tasks.md — zishu_flutter 并行执行看板

> 规则：状态 `[x]` 完成 / `[~]` 进行中 / `[ ]` 未开始 / `[!]` 阻塞。
> 每张卡限制修改范围；完成即更新本文件状态并写验证结果。
> 并行纪律：①同一时刻只有一个任务改 `pubspec.yaml` / `lib/main.dart` / `tasks.md`；
> ②`ui/` 只许 import `engine/engine.dart` barrel，禁止深入 engine 内部；
> ③每张卡自带验证命令，验证不过不得标记完成。

## 当前里程碑：M0 骨架 → M1 数据闭环 → M2 播放 → M3 核心闭环 UI

依赖 DAG：

```
G1(G 工程) ────────────────► G3(git/远端)
E1(契约模型) ─► E2(API client) ─► E3(RemoteSite+LiveSite 移植) ─► E5(engine 测试)
                          ├──► E4(弹幕通道 SSE/WS) ──┐
E2 ─► E6(播放适配器+JS内核+代理) ────────────────────┼──► U5(播放页)
U1(设计token) ─► U2(app壳) ─► U3(首页) ┐            │
                          ├──► U6(分类页) ├─► U7(设置) ─► Q1(冒烟)
                          └──► U4(控制器) ┘
```

## 轨道 G — 工程与基建（串行基座，改动共享文件）

| 卡 | 内容 | 状态 | 验证 |
|---|---|---|---|
| G1 | flutter create（web 平台）+ 目录骨架 engine/ui | [x] | pub get ✓ |
| G2 | tasks.md 看板 | [~] | — |
| G3 | git init + 首提交 + GitHub private 仓库推送 | [ ] | 远端 clone 可见 |
| G4 | tool/build-web.ps1 + tool/check.ps1（pub get→analyze→test→build web 一键门禁） | [ ] | 门禁全绿 |
| G5 | CI（GitHub Actions：analyze/test/build web） | [ ] | CI 绿（后置） |

## 轨道 E — engine：解析 + 播放 + 弹幕（可与 U 全并行）

| 卡 | 内容 | 依赖 | 状态 | 验证 |
|---|---|---|---|---|
| E1 | contracts：room/browse/search 模型（手写 fromJson，对齐 schema） | — | [x] | test/contracts_test.dart 3 例 ✓ |
| E2 | remote/stream_api_client.dart（Dio；端点对齐 web/src/api/*.ts；dart-define+config.json 双配置） | E1 | [x] | analyze ✓（build web ✓） |
| E3 | 从 pure_live 移植 LiveSite/LiveDanmaku 契约 + LiveRoom 等模型（去 GetX）→ remote_site_source implements LiveSite（缓存 RoomPayload 供 getPlayQualites/getPlayUrls）→ site 注册（douyu/huya/bilibili/douyin/kuaishou/twitch/yy/soop/youtube/xhs，iptv 按 server 能力） | E1,E2 | [ ] | flutter test：fixture 驱动的 source 单测 |
| E4 | danmaku 通道：SSE 客户端（dio 流式解析 /api/{site}/danmaku/stream）+ douyu WS 直连（web_socket_channel，复用 pure_live douyu 协议）；通道矩阵 = server /api/config/playback 优先 | E2 | [ ] | 单测：SSE 帧解析 + douyu 帧解码（用 pure_live 样本） |
| E6 | playback：UnifiedPlayer 简化契约 + WebVideoPlayerAdapter(video_player)；web/index.html 注 mpegts.js/hls.js；headers 含 Referer 的线路 → {base}/api/live-stream?url= | E2 | [ ] | Web 播 douyu(flv)/bilibili(hls) 手测记录 |
| E5 | engine 测试补齐：真实响应 fixtures（room 三态/categories 双形态/search/danmaku 帧） | E3,E4 | [ ] | flutter test 全绿 |

## 轨道 U — ui：复刻 SFVideoLive web（与 E 并行，吃 engine barrel）

| 卡 | 内容 | 依赖 | 状态 | 验证 |
|---|---|---|---|---|
| U1 | theme/design_tokens.dart（#f3d04e、平台品牌色、fluent-radius、断点 640/768/1024/1366/1920、暗色默认） | — | [x] | analyze ✓ |
| U2 | app.dart：GetMaterialApp + 70px NavigationRail + 路由表（/all、/all/category/:key、/:site/play/:id、/settings）+ URL 同步 | U1 | [~] | analyze ✓；浏览器前进后退手测 |
| U3 | views/home_view + widgets/room_card：平台筛选 chips + 房间网格 + 分页 + 平台品牌角标（对标 HomeView.vue） | U2,E3 | [ ] | 冒烟：起 streaming-server 后卡片>0 |
| U4 | controllers：home/play/category/settings GetXController（对标 usePlayer/useDanmaku 语义：generation fence、切房取消） | U2,E3 | [ ] | 控制器单测（fake client） |
| U5 | views/play_view + player_panel/player_controls/play_side_panel/danmaku_overlay（328px 侧栏、画质/线路切换、弹幕 canvas） | U4,E4,E6 | [ ] | 手测：切档/切线/弹幕滚动 |
| U6 | views/category_view：分组 chips + 分类房间网格（对标 CategoryRoomsView.vue） | U2,E3 | [ ] | 冒烟 |
| U7 | views/settings_view 最小集：主题/弹幕开关/服务器地址（持久化→shared_preferences） | U2 | [ ] | 改配置后请求生效 |
| U8 | 错误/空态组件 + toast（对标 useToast） | U2 | [ ] | 断网场景降级提示 |

## 轨道 Q — 验证（每卡完成即跑）

| 卡 | 内容 | 状态 |
|---|---|---|
| Q1 | playwright 冒烟脚本（路由→列表→播放→弹幕→设置） | [ ] |
| Q2 | 契约 fixtures 测试（capture 自 streaming-server 真实响应） | [~]（3/多 例） |
| Q3 | 门禁：pub get→analyze→test→build web（G4 脚本） | [ ] |

## 已验证记录（追加式）

| 日期 | 命令 | 结果 |
|---|---|---|
| 2026-09-08 | flutter pub get | OK（43 deps） |
| 2026-09-08 | flutter test | 3/3 passed |
| 2026-09-08 | flutter analyze | No issues |
| 2026-09-08 | flutter build web | OK（84.7s） |

## 执行模板（派发 agent 时附带）

```text
你只执行任务卡 <ID>，不要顺手做其他卡。
开始前：读 tasks.md 该卡 + 对标文件（表内标注）。
规则：只改该卡允许文件；ui 不 import engine 内部路径；验证不过不算完成。
结束输出：改动文件、验证命令与结果、遗留问题；并更新 tasks.md 该卡状态。
```
