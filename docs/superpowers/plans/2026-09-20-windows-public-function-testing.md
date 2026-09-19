# Windows 公共功能跨平台测试实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans 按任务逐条实施。步骤使用 checkbox (`- [ ]`) 跟踪；每个阶段完成后更新 `docs/testing/windows-public-function-matrix.md`，独立提交并推送。

**Goal:** 建立覆盖所有已注册平台的 Windows 公共功能测试体系，优先发现并修复播放状态在切房、重开、恢复和重启过程中的不一致问题。

**Architecture:** 测试分为纯逻辑契约、应用编排、Widget workflow、Windows 真实 smoke 四层。纯逻辑和应用层使用统一的 `RecordingLivePlayer`/`ScriptedLivePlayer`，Widget 层通过 Riverpod 覆盖播放器与数据源，真实 Windows 层记录人工/半自动证据；所有平台通过同一套能力矩阵区分 PASS、FAIL、BLOCKED、N/A、NOT_RUN。

**Tech Stack:** Flutter test、Riverpod、media-kit 抽象 `LivePlayer`、纯 Dart `live_parser`、Windows release build、`playback.log`。

**Spec:** `docs/superpowers/specs/2026-09-20-windows-closure-design.md` 以及本轮确认的“分层测试 + 平台矩阵 + Markdown 进度”设计。

## Global Constraints

- Windows 是当前优先交付端；Web 和 Android 不阻塞本计划。
- `packages/live_parser` 禁止依赖 Flutter、Widget、`media-kit` 和具体 UI。
- 新代码不得依赖 `lib/legacy/`。
- UI 轨和解析轨分开提交；文档和测试基础设施单独提交。
- 当前已有未提交业务改动不得被 reset、stash、clean 或覆盖。
- 不把 `build/`、临时截图、临时探针脚本和凭据日志加入产品提交。
- 每个生产行为修复必须先有会失败的回归测试，再写实现。
- 平台不支持的能力记录为 `N/A`，未执行记录为 `NOT_RUN`，不能伪装成通过。
- 每个阶段完成后必须运行阶段门禁、更新进度 Markdown、commit 并 push。

## Review Focus

- 播放器 `open` 完成后重置音量：必须断言最终底层音量，而不只断言 `setVolume` 被调用。
- A/B/C 快速切房的异步竞态：旧房间的 open、volume 或 snapshot 不得覆盖最终房间。
- 同房间号跨平台隔离：`douyu:123` 和 `huya:123` 的音量、静音和播放状态必须独立。
- 全局静音与房间音量为 0 的语义差异：取消全局静音只能恢复房间自身值，不能把房间 0 误改成 100。
- 切线路、切画质、断流恢复和重新解析：播放状态不应重置音量、静音、弹幕会话或当前房间身份。

---

## 阶段 1：矩阵与测试基础设施

### Task 1.1：建立进度矩阵文档

**Files:**
- Create: `docs/testing/windows-public-function-matrix.md`
- Modify: `docs/superpowers/plans/2026-09-20-windows-public-function-testing.md`

**Produces:** 稳定的功能 ID、平台能力表、当前状态表、Bug 登记格式和阶段进度记录。

- [x] 写入平台能力矩阵，至少包含 `douyu`、`huya`、`bilibili`、`douyin`、`kuaishou`、`yy`、`twitch`、`soop`、`youtube`、`iptv`。
- [x] 写入公共功能 ID：`VOL`、`MUTE`、`QUALITY`、`LINE`、`DANMAKU`、`FULLSCREEN`、`PIP`、`FOLLOW`、`THEME`、`RETURN`。
- [x] 为每条功能记录自动化状态、Windows 真实状态、证据路径和修复提交。
- [x] 写入第一条已知问题 `BUG-WIN-VOLUME-001`，状态为 `NOT_RUN`，不得提前声称已修复。
- [x] 运行 Markdown 结构检查：所有表格列数一致，状态只使用规定枚举。
- [x] 提交：`docs(testing): add Windows public function matrix`。
- [x] 推送：`git push origin master`。

### Task 1.2：建立统一播放测试替身

**Files:**
- Create: `test/support/recording_live_player.dart`
- Create: `test/support/scripted_live_player.dart`
- Test: `test/support/recording_live_player_test.dart`

**Interfaces:**
- `RecordingLivePlayer implements LivePlayer`，公开 `openCalls`、`volumeCalls`、`mutedCalls`、`stopCalls`、`currentSnapshot`。
- `ScriptedLivePlayer` 在 `open` 完成后可注入底层音量重置，暴露 `Future<void> completeOpen()` 和 `void resetUnderlyingVolume(double volume)`。
- `Future<void> waitForCall(String callType)` 用于避免测试依赖固定 sleep。

- [x] 先写替身契约测试：`open`、`setVolume`、`setMuted`、`stop` 的调用和 snapshot 都可观察。
- [x] 运行测试确认缺少替身文件时按预期失败。
- [x] 实现最小替身，默认 `open` 不阻塞；所有数值按 `0..100` 钳制。
- [x] 添加异步脚本能力，允许模拟“open 完成后底层音量回到 100”。
- [x] 运行 `flutter test test/support/recording_live_player_test.dart`。
- [x] 提交：`test(playback): add shared observable live player fakes`。
- [x] 推送：`git push origin master`。

## 阶段 2：音量状态完整回归

### Task 2.1：补齐房间音量纯逻辑矩阵

**Files:**
- Test: `test/features/playback/room_volume_provider_test.dart`
- Modify: `docs/testing/windows-public-function-matrix.md`

- [ ] 为所有平台参数化验证 `roomVolumeKey` 的小写、去空格和 `site + roomId` 隔离。
- [ ] 验证房间记忆值、默认值、全局静音、0 音量、负数和大于 100 的钳制。
- [ ] 先运行并确认缺少测试文件/用例时的失败，再补齐测试。
- [ ] 运行该测试文件并记录通过数。
- [ ] 更新矩阵：纯逻辑自动化标记为 `PASS`，Windows 真实列保持 `NOT_RUN`。
- [ ] 提交：`test(playback): cover room volume isolation matrix`。
- [ ] 推送：`git push origin master`。

### Task 2.2：修复并验证切房音量异步竞态

**Files:**
- Modify: `lib/src/features/play/application/play_provider.dart`
- Test: `test/features/playback/play_controller_volume_lifecycle_test.dart`
- Modify: `docs/testing/windows-public-function-matrix.md`

**Consumes:** Task 1.2 的 `ScriptedLivePlayer`；现有 `roomVolumeProvider`、`RoomVolumeStore` 和 `PlayController`。

**Produces:** `PlayController` 在首次进房、切房、重开、切线路、切画质和恢复解析后，播放器最终 snapshot 与当前房间设置一致；旧房间异步操作不能覆盖新房间。

- [ ] 先写并运行失败测试：房间 A 音量 35，切换房间 B，模拟 B 的 `open` 完成后底层重置为 100，断言最终实际音量等于 B 的记忆值或默认值，而不是 100。
- [ ] 添加失败测试：A→B→A 恢复各自音量；同 roomId 跨 douyu/huya 隔离；切线路和切画质不改音量；全局静音和房间 0 值语义不混淆。
- [ ] 确认失败原因是生产编排时序或代际覆盖，而不是测试替身错误。
- [ ] 以最小改动修复：确保 `open` 完成后对当前 generation 再次应用房间音量，并让旧 generation 的音量应用失效；禁止使用全局可变房间状态绕过 Riverpod。
- [ ] 运行 `test/features/playback/play_controller_volume_lifecycle_test.dart`，再运行全部 `test/features/playback/`。
- [ ] 更新矩阵中的 `VOL-001` 至 `VOL-010`，填写根因、修复 commit 和自动化证据。
- [ ] 提交：`fix(playback): preserve room volume across source lifecycle`。
- [ ] 推送：`git push origin master`。

### Task 2.3：补齐播放控制 Widget workflow

**Files:**
- Create: `test/ui/workflows/play_volume_workflow_test.dart`
- Modify: `lib/src/features/play/widgets/player_controls.dart`（仅当失败测试证明 UI 接线有问题）
- Modify: `docs/testing/windows-public-function-matrix.md`

- [ ] 测试音量 slider 初始值来自当前 snapshot。
- [ ] 测试拖动 slider 后 UI、`LivePlayer` 和房间设置写入一致。
- [ ] 测试 mute/unmute 恢复之前的有效音量。
- [ ] 测试切房后 slider 不显示旧房间值。
- [ ] 测试控制条淡出后不可误触音量控件。
- [ ] 先观察失败，再修改生产代码；若现有实现通过则只增加测试和文档。
- [ ] 运行本文件及 `test/ui/workflows/play_controls_test.dart`。
- [ ] 提交：`test(ui): cover playback volume workflow`。
- [ ] 推送：`git push origin master`。

## 阶段 3：其他公共播放状态

### Task 3.1：画质、线路和恢复状态矩阵

**Files:**
- Test: `test/features/playback/playback_public_state_matrix_test.dart`
- Modify: `docs/testing/windows-public-function-matrix.md`

- [ ] 参数化覆盖默认画质、切画质、线路格式、备用线路、重新解析和失败恢复。
- [ ] 验证切画质/线路不重置音量、静音和房间身份。
- [ ] 验证旧 generation 的 open 结果不会覆盖新选择。
- [ ] 运行 parser 相关 fixture 与 app 播放测试。
- [ ] 更新矩阵并提交：`test(playback): cover quality line and recovery state matrix`。
- [ ] 推送：`git push origin master`。

### Task 3.2：弹幕会话和侧栏状态矩阵

**Files:**
- Test: `test/features/danmaku/danmaku_session_lifecycle_test.dart`
- Modify: `docs/testing/windows-public-function-matrix.md`

- [ ] 覆盖切房销毁旧 session、重连去重、overlay/chat 分离、设置生效和不支持平台不建连。
- [ ] 运行现有 `test/features/danmaku/` 和 `test/ui/workflows/danmaku_test.dart`。
- [ ] 更新矩阵并提交：`test(danmaku): cover session lifecycle matrix`。
- [ ] 推送：`git push origin master`。

### Task 3.3：全屏、PiP、返回和主题矩阵

**Files:**
- Test: `test/ui/workflows/public_playback_state_test.dart`
- Modify: `docs/testing/windows-public-function-matrix.md`

- [ ] 覆盖全屏/PiP 退出优先级、切房状态、Esc、Alt+左、侧键返回和主题切换。
- [ ] 运行现有 fullscreen/back/theme 测试。
- [ ] 更新矩阵并提交：`test(ui): cover public playback state transitions`。
- [ ] 推送：`git push origin master`。

## 阶段 4：平台参数化与 Windows 真实验收

### Task 4.1：平台能力契约测试

**Files:**
- Create: `test/features/platform/public_capability_matrix_test.dart`
- Modify: `docs/testing/windows-public-function-matrix.md`

- [ ] 对所有已注册平台验证 capability、room key、未支持入口过滤和错误隔离。
- [ ] 对不支持的能力明确断言 `N/A`，不要求伪造真实数据。
- [ ] 运行测试并更新平台表。
- [ ] 提交：`test(platforms): add public capability contract matrix`。
- [ ] 推送：`git push origin master`。

### Task 4.2：Windows 真实 smoke 记录

**Files:**
- Create: `tool/windows_public_smoke.ps1`
- Modify: `docs/testing/windows-public-function-matrix.md`
- Modify: `todo.md`

- [ ] 编写只负责启动、记录 build 版本、测试 ID 和日志路径的 smoke 脚本，不把凭据写入仓库。
- [ ] 真实解析 release 构建，逐平台记录首帧、播放、音量、静音、切房、返回、弹幕和日志结果。
- [ ] 使用 `PrintWindow(PW_RENDERFULLCONTENT)` 或现有工具抓窗口表面；屏幕合成截图不作为唯一证据。
- [ ] 每个平台使用 `PASS/FAIL/BLOCKED/N/A/NOT_RUN`，并记录证据文件名。
- [ ] 提交：`test(windows): add public function smoke checklist`。
- [ ] 推送：`git push origin master`。

## 阶段 5：收口门禁

### Task 5.1：全量验证和进度收口

**Files:**
- Modify: `docs/testing/windows-public-function-matrix.md`
- Modify: `todo.md`
- Modify: `tasks.md`

- [ ] 运行 `flutter analyze`、`flutter test`、`dart analyze`、`dart test` 和 Windows debug/release build。
- [ ] 汇总每阶段测试数量、失败和已知网络告警。
- [ ] 将未完成项明确保留为 `NOT_RUN` 或 `BLOCKED`，不能用“基本完成”替代。
- [ ] 记录最终已知风险和下一轮工作项。
- [ ] 提交：`docs(testing): record Windows public function verification progress`。
- [ ] 推送：`git push origin master`。

## 阶段门禁命令

```powershell
flutter analyze
flutter test
flutter build windows --debug -t lib/main.dart

cd packages/live_parser
dart analyze
dart test
```

真实 Windows 构建：

```powershell
flutter build windows --release --dart-define=ZISHU_REAL_PARSER=true
```

每个阶段完成后，必须读取命令输出，确认退出码和通过/失败数量，再更新矩阵和提交；不能凭历史结果宣称通过。
