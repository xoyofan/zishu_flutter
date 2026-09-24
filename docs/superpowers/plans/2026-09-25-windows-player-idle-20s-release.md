# Windows 播放器退房 20 秒释放实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 切房继续复用一个 Player，最后一个播放页离开后立即停播、20 秒内可复用，超过 20 秒释放 mpv/视频纹理；再次进房安全重建。

**Architecture:** `playerProvider` 继续提供稳定的 `LivePlayer` 入口，但内部 native `MediaKitLivePlayer` 按活跃房间租约懒创建和空闲释放。`playControllerProvider` 负责取得/释放带代际的房间租约；稳定入口转发快照和 Video Widget。native 销毁与新一代创建串行，旧页面不可停止、取消新页面的回调或销毁新实例。此次不改变 `buffering`、watchdog、自动重试次数、聊天协议或 UI 视觉。

**Tech Stack:** Flutter、Riverpod、`media-kit`、`media-kit_video`、Dart Timer、`flutter_test`、Windows PowerShell。

**Spec:** `docs/superpowers/specs/2026-09-25-windows-playback-idle-release-and-recovery-design.md` 的第 1、3、4、6 节；**本计划只实施 20 秒生命周期切片**，第 5 节三次恢复属于另一个后续计划。

## Global Constraints

- 20 秒从最后一个活跃播放页离开且旧源 `stop()` 完成开始计时；新播放页进入时撤销尚未开始的释放。
- 首页首次浏览不初始化 mpv；20 秒超时后真正释放 Player 和 `VideoOutputManager`，不是再次调用 `stop()`。
- 切房保持原画质与 `LivePlayer` 功能契约；不延长聊天 `autoDispose.family` 的生命周期。
- Windows 主链路更改至少执行独立 package 的 `pub get`、`flutter analyze`、相关 `flutter test`、`flutter build windows --debug -t lib/main.dart`；全量 `flutter test` 作为回归门禁。
- 交付前必须**打包真实解析的 Windows Release EXE 并自行切换房间验证内存**；不能只做 Debug 构建或只让用户手动验证。
- 项目已有未提交的 `AGENTS.md` 改动不纳入实现提交；不能杀用户当前 Release 进程，不能直接覆盖其正在运行的构建目录。

## Review Focus

- A→B 切房中 A 的迟到 `onDispose`：不能停掉或释放 B；Task 1 的租约代际测试。
- 20 秒恰好到点时进房：若销毁未开始应取消；已开始应等待销毁结束后重建；Task 1 的边界测试。
- native `Player.dispose()` 异步并延迟彻底销毁：不复用 disposed 实例，不遗留旧快照/纹理监听；Task 2 的 fake-dispose 与真机采样。
- 未播首页触发睡眠定时 `stop()`：不得隐式创建 mpv；Task 1 的空闲停播测试。
- 同一播放页配置变化导致 provider rebuild：旧回调不得误判断“最后一个房间离开”；Task 1 的 rebuild 测试。

---

### Task 1: 稳定播放器入口和带代际的 20 秒租约

**Files:**
- Create: `lib/src/platforms/common/playback/idle_releasing_live_player.dart`，稳定入口、代际、快照和 Timer；此文件不依赖站点解析。
- Modify: `lib/src/features/play/application/play_provider.dart` 中 `playerProvider` 与 `PlayController.build/onDispose` 的租约接线，不改变现有解析/选线逻辑。
- Test: `test/features/playback/idle_releasing_live_player_test.dart`、`test/features/playback/play_controller_volume_lifecycle_test.dart`。

**Interfaces:**
- 消费现有 `LivePlayer`/`LineRecoveryAware`。稳定入口实现 `LivePlayer`，并提供 `int enterRoom()`、`Future<void> leaveRoom(int token)`；`enterRoom()` 同步更新代际与取消空闲 Timer，`leaveRoom` 只对仍拥有活跃租约的 token 生效。Player factory、释放 Future 和 idle delay 可构造注入，生产 delay 固定 `Duration(seconds: 20)`；对外仍通过 `playerProvider` 返回 `LivePlayer`，feature 层使用可选租约能力，不强迫现有测试替身新增接口。
- 为原有 UI 保留单一 `snapshots` broadcast stream；内部实例切换时取消旧订阅，切到新实例后转发新快照，空闲时显示默认快照；`buildVideoView()` 在无 native Player 时返回占位，内部实例换代时能重建 Video Widget。

- [ ] **Step 1: 先写失败测试。** 使用已有 `RecordingLivePlayer` 或最小 fake factory，分别断言：初始只读取稳定入口无 factory 调用；`enterRoom → leaveRoom` 调用 stop；假时钟推进 `19s` 后未 dispose，`20s` 后恰一次 dispose；`19s` 时再 enter 撤销释放；A→B 后 A 的 leave 不停止 B；空闲 `stop()` 不创建 Player；空闲释放期间 enter 等待旧 Future 再创建新实例；重建后快照来自新实例。provider 测试断言 `playControllerProvider` 离场保留现有 `room_release_start/end` 样本，settings 触发同页面重建不会释放新房。
- [ ] **Step 2: 跑 RED。** `F:\flutter\bin\flutter.bat test test/features/playback/idle_releasing_live_player_test.dart test/features/playback/play_controller_volume_lifecycle_test.dart`；确认因缺租约/释放行为失败，而非语法或 VM 原生库错误。
- [ ] **Step 3: 实现最小稳定入口。** 包装 `LivePlayer` 方法，唯一 native factory 仅由 `enterRoom`/`open` 的活跃播放路径调用；`leaveRoom` 先确认 token，再调用 stop，结束后排 20 秒 Timer。Timer 到期再验证 token/活跃数，设置 `disposing` Future；新的 `enterRoom` 若销毁在途则暂存新意图，后续 `open` 等待它结束才创建新 native Player。不要通过 `playerProvider.autoDispose` 持有这个 Timer，也不要清掉新房注册的 `LineRecoveryHandler`。`playerProvider` 根容器释放时取消 Timer 并释放当前实例。
- [ ] **Step 4: 跑 GREEN 与邻近测试。** 上述测试 + `F:\flutter\bin\flutter.bat test test/features/playback/playback_public_state_matrix_test.dart test/ui/workflows/play_controls_test.dart`；检查离页即停播、快照/音量/PiP 语义未改变。
- [ ] **Step 5: 独立核查 diff、提交。** `git diff --check`；只提交上述实现与测试，中文提交说明，不暂存 `AGENTS.md`。

### Task 2: native Player/纹理异步释放与 Windows 资源验收

**Files:**
- Modify: `lib/src/platforms/common/playback/media_kit_live_player.dart`：提供可等待的 native 释放入口，保留现有 `LivePlayer.dispose()` 兼容接口；不得在 `stop()` 里销毁 Player。
- Modify: `lib/src/platforms/common/playback/idle_releasing_live_player.dart`：生产 factory/async disposer、`player_created`、`player_idle_scheduled/cancelled`、`player_dispose_start/end` 低频日志与 RSS。
- Test: `test/features/playback/media_kit_player_fence_test.dart`、`test/features/playback/idle_releasing_live_player_test.dart`。

**Interfaces:**
- 在 `MediaKitLivePlayer` 提供 `Future<void> releaseNative()`：幂等、取消订阅/计时器并等待 `_player.dispose()`，由该包触发 `VideoOutputManager.Dispose`；原有 `void dispose()` 可调用 `unawaited(releaseNative())` 维持 20+ `LivePlayer` 测试替身契约。稳定入口的释放 Future 必须等待 `releaseNative()`；销毁期间到来的新开流不得落在旧实例。

- [ ] **Step 1: 先写失败测试。** 假 `PlatformPlayer.dispose()` 挂起时 `releaseNative` Future 不完成；重复释放只调用一次；旧订阅不再把事件送到稳定快照；旧实例释放时新房请求排队，放行后新实例收到 open，旧实例不收到；用日志测试确认销毁只写低频事件、不写 URL/token。
- [ ] **Step 2: 跑 RED。** `F:\flutter\bin\flutter.bat test test/features/playback/media_kit_player_fence_test.dart test/features/playback/idle_releasing_live_player_test.dart`。
- [ ] **Step 3: 实现异步 native 释放。** `releaseNative` 捕获且复用一个 Future，关闭旧订阅/Timer/广告代理并等待 `Player.dispose()`；稳定入口在 20 秒后等待它结束才将 native 引用归位。保持 `VideoController` 与原 Player 同代，在下一代新建；源代际 fence 不跨实例复用。记录耗时和 RSS，不吞掉错误而不留日志。
- [ ] **Step 4: 完成自动门禁。** 在 `packages/live_parser` 和 `packages/speech2zh` 各自 `pub get` 后运行 `F:\flutter\bin\flutter.bat analyze`、`F:\flutter\bin\flutter.bat test`、`F:\flutter\bin\flutter.bat build windows --debug -t lib/main.dart`。日志留存失败项，不用绿色的局部测试代替全量测试。
- [ ] **Step 5: 打包 Release 并自行真机验收。** Task 1/2 的受测提交完成后，在与用户运行目录隔离的 checkout/worktree 中执行 `powershell -ExecutionPolicy Bypass -File tool/build-windows.ps1`（默认 `--release -t lib/main.dart --dart-define=ZISHU_REAL_PARSER=true`）。记录该目录 `build/windows/x64/runner/Release/zishu_flutter.exe`、`data/app.so` 的时间与大小；仅 EXE 文件不构成可运行包，应保留同目录 `data` 和 DLL。自行启动这份**隔离产物**，以 PID 定位其窗口（`tool/win_tool.py` 按最大窗口选择，多实例时禁止直接使用它盲点），独立采样 PID。固定同一画质完成：进房→切房至少 10 次→回首页 10 秒内重进（无 `player_dispose_start`，核对复用）→回首页超过 20 秒（看到 `player_dispose_end`）→再进房（新建 Player、画面/声音正常）。使用 `%APPDATA%\zishu_flutter\logs\playback.log` 的 `app_start/player_*` 与 `tool/sample_runtime.ps1 -DurationSeconds 90 -IntervalSeconds 3 -OutputPath <temp.csv>` 的 Private/GPU/Threads 对时；脚本若按进程名混采用户实例，必须按 PID 筛选或单独采样，绝不可把另一实例数据当作本次结果。等待 native 最长约 5 秒延迟后看趋势，不承诺固定 MB 数字。记录每次操作时刻、首帧/黑屏、资源基线/峰值/释放后数值；真实网络或图形环境失败要报告未完成项，不得宣称已真机通过。
- [ ] **Step 6: 独立验收、提交。** 由 `reviewer` + `chatgoai/gpt-6-sol` 只读核对 diff、生命周期竞态、测试、隔离 Release 打包和切房资源 CSV；阻塞项由原 writer 修复并复验。`git diff --check` 后只提交本轨文件，中文说明，不提交 `AGENTS.md`。

## Self-review

- 本计划只覆盖 20 秒释放；不实施设计稿第 5 节的 buffering 与三次重试修改。
- 两项交付分别是可测的稳定租约和真实 native 释放；所有首次创建、快速返回、超时边界、切房竞态、旧回调、空闲睡眠定时均有测试步骤。
- 不把 `open_to_first_frame` 的 mpv `playing` 事件称为像素首帧；真正画面在真机检查。
