# 三端进度与缺口盘点（2026-09-24，HEAD `438f743`）

> 范围：静态核对当前源码、构建配置及既有验收记录；本轮未重新运行全量测试，也未把“启动 exe”当作逐功能验收。优先级按仓库约定 Windows > Web > Android。`tasks.md` / `todo.md` 含历史未勾选项，判断时以当前源码、较新的 `docs/ui-parity/platform-display-matrix.md` 和 `docs/testing/windows-public-function-matrix.md` 为准。

## 总览

| 目标端 | 当前可确认 | 离交付最关键的差距 |
|---|---|---|
| Windows | `lib/main.dart` → `WindowsApp`，Flutter UI、直连 `live_parser`、`media-kit`；先前 9 站真实 smoke 有记录；本会话已编译并启动真实解析 Release exe | 解决真实播放/弹幕的未关闭故障，补长播与最新版本回归；不能将构建成功等同验收完成 |
| Web（新 Flutter UI） | `web/` 有静态壳；`lib/src/platforms/web/streaming_server_client.dart` 有早期 HTTP 客户端 | `lib/src/apps/web/` 仅 `.gitkeep`，没有新 Web 入口；没有 Dart `streaming-server` 包，也没有新 UI 的完整 server adapter、Web 播放/弹幕链路 |
| Android | 共用 Widgets 有手机/平板响应式测试 | 根目录没有 `android/` Flutter 工程；`lib/src/apps/android/` 和 `lib/src/platforms/android/` 仅 `.gitkeep`；`pubspec.yaml` 仅配置 Windows 视频 libs，尚无 APK/实机验收 |

## 共享解析能力（不是“9 站全能力等价”）

`packages/live_parser` 当前注册 9 站，`docs/ui-parity/platform-display-matrix.md` 列出：斗鱼、虎牙、B站、抖音、快手、YY、Twitch、SOOP、YouTube。快手、YouTube 无搜索；YY 无弹幕；Twitch 是单线路，这些要按能力声明显示 N/A，不应伪造。IPTV、CC 已移除，小红书不在真实入口，**不列为待补平台**。目前 `A11` 导航过滤已由 `438f743` 实现，旧文档把它列为待办已过期。

## Windows：优先关闭的缺口

1. **P0：真实播放稳定性与当前版本验收。** `todo.md` 记录进房黑屏（`BUG-WIN-VIDEO-001`，暂停再播放可恢复）和恢复数秒后自动停止的单次报告。先取 `playback.log`、锁定房间/线路/发生时间，再修复并回归。`docs/superpowers/specs/2026-09-20-windows-closure-design.md` 的斗鱼/虎牙各至少 10 分钟长播、启动首帧与窗口恢复验收，不能由本轮 release build/启动替代。
2. **P0：弹幕可靠性。** `docs/testing/windows-public-function-matrix.md` 记录斗鱼切房返回不自动重连（`BUG-WIN-DANMAKU-002`）、虎牙连接但零消息（003）、Twitch 连接失败/网络 BLOCKED（004）。优先复现并区分协议错误和网络出口问题；其余站有既有收流证据，但不是本次版本重新实测。
3. **P1：播放状态一致性。** 验收矩阵中 `VOL-001` 的“无记忆新房间继承上一房间音量”真实 FAIL（`BUG-WIN-VOLUME-002`），自动化却 PASS；先补能失败的回归用例再修。断流恢复音量、连续切房、PiP/全屏销毁等仍有 `NOT_RUN` 真机用例。
4. **P1：字段与表情。** 多站关注数/VIP/徽章等级等不齐（`PARSER-GAP-001`）；快手表情真实 URL、Twitch emote 图片等尚未闭环（`PARSER-GAP-002`）。现有 `RoomStatColumn`/空值契约已做到“缺数据为 —、未声明不显示”，不能将展示契约完成误作解析齐全。YY 弹幕和快手搜索是新增能力候选，不应作为当前能力 bug。
5. **P2：体验与文档。** 个别 YouTube 频道源不可播、飘屏多轨重叠；桌面 1920×1080 播放页工具栏/全屏抽屉与视觉对齐尚有历史待办。`tasks.md`/`todo.md` 多处旧状态与现状冲突，需核实后清理。
6. **构建口径。** `providers.dart` 的 `ZISHU_REAL_PARSER` 缺省为 `false`（fixture）。`.github/workflows/release-windows.yml` 已显式传 `true`，手动构建也必须带 `--dart-define=ZISHU_REAL_PARSER=true`；“默认打包带解析、记入 AGENTS.md”目前尚未落地于 AGENTS（不能声称已改）。安装/分发应打包完整 `build/windows/x64/runner/Release/`，不是只复制 exe。

## Web：先补主链路，不是继续做纯视觉对齐

1. 建 `packages/live_server/` 或等价的纯 Dart server，直接 import **同一个** `live_parser`，提供版本化的 browse/search/resolve、弹幕 SSE/WS 和必要的图片/流代理；处理 CORS、Cookie/headers、鉴权与部署，不在浏览器运行解析源码。旧 Node server 仅作迁移参考。
2. 创建 `lib/src/apps/web/` 的 Flutter Web 入口及 `platforms/web` adapter，把共享的 `BrowseSource`/`RoomSource`/搜索/弹幕接到 server API；当前 `StreamingServerClient` 只是局部旧式 `/api/rooms`、`/api/room` 客户端，未被新 app 引用，不能视为 Web 主链路已接通。
3. 选用并验证 Web 可用播放器及平台 libs/策略；`main.dart` 当前包含 Windows 初始化与 `dart:io` 相关依赖，不能直接视作 Web 入口。最后建立 Web CI build、服务端契约测试和浏览器真实浏览→播放→弹幕 smoke（至少斗鱼/虎牙/B站）。

## Android：工程基础尚未建立

1. 生成/恢复 `android/` runner 与 Android 专属 `main`/app 组装；补 `media-kit` Android 对应 libs、网络权限/cleartext/前后台生命周期、横竖屏/系统音频焦点等平台适配。
2. 直接复用 `live_parser` 与共享业务/UI，不复制站点解析；Android 播放、弹幕和代理逐项实机验证。Windows 专属 WASAPI 语音采集当前不可复用，语音字幕应明确隐藏或做 Android audio tap adapter。
3. 补 `flutter build apk`、Android emulator/实机的浏览→播放→切线→弹幕→关注 smoke；仅有移动响应式 widget 测试不等于 Android 运行可用。

## 建议顺序与可验收出口

- **先 Windows**：针对真实故障做最小可复现测试和修复；在最新真实解析 Release 上完成斗鱼/虎牙 10 分钟长播、9 站按能力 smoke、错误日志/截图回填。将 `NOT_RUN`/`BLOCKED` 如实保留。
- **再 Web**：server 最小 API → Flutter Web adapter/入口 → 三站浏览、搜索、播放和弹幕端到端 → 自动化构建/部署。
- **最后 Android**：runner + libs/权限 → 直连 parser + 平台播放适配 → APK/真机端到端。共享响应式 UI 可以提前继续测试，但不宣称 Android 已交付。

主要证据：`lib/main.dart`、`lib/src/shared/application/providers.dart`、`lib/src/apps/{windows,web,android}/`、`lib/src/platforms/{web,android}/`、`pubspec.yaml`、`.github/workflows/release-windows.yml`、`docs/ui-parity/platform-display-matrix.md`、`docs/testing/windows-public-function-matrix.md`、`docs/superpowers/specs/2026-09-20-windows-closure-design.md`。历史待办仅作线索，不直接作为当前事实。
