# Windows 公共功能跨平台测试矩阵

> 目标：验证 Windows 客户端在所有已注册平台上的公共功能。本文档同时记录自动化测试、Windows 真实 smoke、问题根因、修复提交和证据路径。
>
> 状态枚举：`PASS` / `FAIL` / `BLOCKED` / `N/A` / `NOT_RUN`。
>
> 当前阶段：阶段 4（平台参数化与 Windows 真实验收）。Windows 真实 smoke 尚未开始，真实列保持 `NOT_RUN`。

## 1. 平台能力基线

| 平台 | Browse | Search | Multi-quality | Multi-line | Danmaku | Status refresh | Playback | 自动化契约 | Windows 真实 |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| `douyu` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | NOT_RUN |
| `huya` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | NOT_RUN |
| `bilibili` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | NOT_RUN |
| `douyin` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | NOT_RUN |
| `kuaishou` | PASS | N/A | PASS | PASS | PASS | NOT_RUN | NOT_RUN | PASS | NOT_RUN |
| `yy` | PASS | PASS | PASS | PASS | N/A | NOT_RUN | NOT_RUN | PASS | NOT_RUN |
| `twitch` | PASS | PASS | PASS | PASS | PASS | PASS | NOT_RUN | PASS | NOT_RUN |
| `soop` | PASS | PASS | PASS | PASS | PASS | NOT_RUN | NOT_RUN | PASS | NOT_RUN |
| `youtube` | PASS | N/A | PASS | PASS | PASS | N/A | NOT_RUN | PASS | NOT_RUN |
| `iptv` | N/A | N/A | N/A | N/A | N/A | N/A | PASS | NOT_RUN | NOT_RUN |

> 上表中的 `PASS` 表示能力已在当前代码/解析测试记录中存在，不表示本轮 Windows 真实 smoke 已通过。真实验证必须在阶段 4 逐平台填入证据。

## 2. 公共功能 ID

| ID | 功能 | 当前自动化 | Windows 真实 | 说明 |
|---|---|---|---|---|
| `VOL` | 房间音量隔离与恢复 | PASS | NOT_RUN | 纯逻辑、生命周期和控制条 UI 均已覆盖 |
| `MUTE` | 静音/取消静音 | PASS | NOT_RUN | 全局静音、房间 0 值、控制条 mute/unmute 已覆盖 |
| `QUALITY` | 默认画质与切换 | PASS | NOT_RUN | 画质/线路矩阵验证切档后音量、线路格式和 generation |
| `LINE` | 线路格式、线路切换和备用线路 | PASS | NOT_RUN | 线路切换复用统一 open 生命周期并保留音量/恢复能力 |
| `DANMAKU` | 弹幕连接、切房、设置和去重 | PASS | NOT_RUN | provider 生命周期 5/5、弹幕目录 51/51、UI workflow 10/10；覆盖切房释放、重连代际、chat/overlay 共享和不支持能力 |
| `FULLSCREEN` | 系统全屏/网页全屏 | PASS | NOT_RUN | `fullscreen_test.dart` 9/9；覆盖 F/Esc、网页全屏、淡出阻断和控制条同源 |
| `PIP` | 画中画进入、退出和恢复 | PASS | NOT_RUN | `fullscreen_test.dart` + `public_playback_state_test.dart`；覆盖 PiP 退出优先级、恢复进入前模式和销毁清理 |
| `FOLLOW` | 关注、超关、状态刷新和同步 | NOT_RUN | NOT_RUN | 房间身份和平台隔离 |
| `THEME` | 深浅主题与设置恢复 | PASS | NOT_RUN | `nav_theme_test.dart`、`light_theme_test.dart`、`public_playback_state_test.dart`；覆盖 dark/light/system 映射与壳层背景 |
| `RETURN` | 返回按钮、Alt+左、鼠标侧键 | PASS | NOT_RUN | `back_shortcuts_test.dart` 5/5；覆盖栈顶返回、栈底静默和切房后返回 |

## 3. 音量回归用例

| 用例 ID | 场景 | 预期 | 自动化 | Windows 真实 | 证据 |
|---|---|---|---|---|---|
| `VOL-001` | 房间 A 设置音量 35 后进入房间 B | B 使用 B 的记忆值或默认值，不能继承 A | PASS | NOT_RUN | 生命周期测试验证 A→B 的最终调用序列与 snapshot |
| `VOL-002` | 从 B 返回 A | A 恢复 35 | PASS | NOT_RUN | 生命周期测试验证 A→B→A 的最终值 |
| `VOL-003` | `douyu:123` 与 `huya:123` | 两个平台音量独立 | PASS | NOT_RUN | `test/features/playback/room_volume_provider_test.dart` |
| `VOL-004` | `open` 完成后底层音量重置为 100 | 最终播放器实际音量仍为设置值 | PASS | NOT_RUN | `play_controller_volume_lifecycle_test.dart`；开流后最终 snapshot=35 |
| `VOL-005` | 切换画质 | 音量和静音状态保持 | PASS | NOT_RUN | `playback_public_state_matrix_test.dart`；切档后音量仍为 37 |
| `VOL-006` | 切换线路 | 音量和静音状态保持 | PASS | NOT_RUN | `playback_public_state_matrix_test.dart`；线路切换后音量仍为 37 |
| `VOL-007` | 断流恢复/重新解析 | 音量和静音状态保持 | NOT_RUN | NOT_RUN | recovery test + playback log |
| `VOL-008` | 全局静音后切房 | 所有房间实际音量为 0 | NOT_RUN | NOT_RUN | lifecycle test |
| `VOL-009` | 房间音量设为 0 但未开启全局静音 | 该房间为 0，取消/切房不误恢复成 100 | PASS | NOT_RUN | `test/features/playback/room_volume_provider_test.dart` |
| `VOL-010` | A→B→C 快速切房 | 只有 C 的最终状态生效 | NOT_RUN | NOT_RUN | lifecycle test |
| `DAN-001` | 切房销毁旧 session | 旧 session close，迟到消息不进入新房间 | PASS | NOT_RUN | `danmaku_session_lifecycle_test.dart`；过期连接完成后立即 close 且无消息订阅 |
| `DAN-002` | 重连去重与最新 generation | 只保留最新 session，旧连接不再广播 | PASS | NOT_RUN | `danmaku_session_lifecycle_test.dart`；连续重连只保留最新 session |
| `DAN-003` | chat/overlay 共享会话 | 只建立一条连接，两个消费者收到同一状态 | PASS | NOT_RUN | `danmaku_session_lifecycle_test.dart`；两个 listener 只触发一次 `connect` |
| `DAN-004` | 不支持平台不建连 | 返回明确 `supported=false` 空态 | PASS | NOT_RUN | `danmaku_session_lifecycle_test.dart` |
| `DAN-005` | 弹幕设置 clamp 与生效 | 设置立即生效且始终落在合法范围 | PASS | NOT_RUN | `danmaku_session_lifecycle_test.dart` |
| `UI-001` | 全屏/PiP 退出优先级 | PiP > 系统全屏 > 网页全屏 > 路由返回 | PASS | NOT_RUN | `fullscreen_test.dart`；`public_playback_state_test.dart` |
| `UI-002` | PiP 退出恢复模式并清理记忆 | 恢复进入前模式，退出后不残留 `modeBeforePip` | PASS | NOT_RUN | `public_playback_state_test.dart`；5/5 |
| `UI-003` | PiP/全屏销毁清理 | 离开播放页不残留窗口级副作用 | PASS | NOT_RUN | `public_playback_state_test.dart`；包含 await 期间销毁回归 |
| `UI-004` | 返回快捷键和主题切换 | Alt+左/侧键安全返回，主题 provider/MaterialApp/token 同步 | PASS | NOT_RUN | `back_shortcuts_test.dart`、`nav_theme_test.dart`、`light_theme_test.dart` |

## 4. 阶段进度

### 阶段 1：矩阵与测试基础设施

- 状态：已完成
- 已完成：矩阵文档、功能 ID、音量回归用例目录、状态枚举和证据约定
- 新增：`test/support/recording_live_player.dart`、`test/support/scripted_live_player.dart`
- 自动化：`flutter analyze test/support --no-pub` 通过；统一替身契约测试 **4/4 通过**
- Windows 真实：NOT_RUN
- 当前风险：统一替身已能模拟异步 `open` 和底层音量重置，但生产编排竞态尚未进入阶段 2 验证

- UI workflow 子阶段：`play_volume_workflow_test.dart` **3/3 通过**；覆盖 snapshot slider、拖动持久化、mute/unmute
- Windows 真实：NOT_RUN
- 已修复：`BUG-WIN-VOLUME-001` 的 open 完成后音量回退问题
- 剩余风险：仍需 Windows release 真实播放验证 UI slider、`PlayerSnapshot` 和 media-kit 实际音量的一致性

### 阶段 3：其他公共播放状态

- 状态：已完成
- 已完成：
  - 阶段 3.1 画质/线路矩阵 **2/2 通过**；发现并修复 `switchLine()` 绕过统一 `_open()` 的状态污染缺口
  - 阶段 3.2 弹幕会话矩阵 **5/5 通过**；弹幕目录 **51/51 通过**；UI workflow **10/10 通过**
  - 阶段 3.3 全屏/PiP/返回/主题矩阵：新增 **5/5**，全屏/PiP **10/10**，返回/主题/浅色 **11/11**；修复 PiP 退出后残留 `modeBeforePip` 及销毁期间异步续段重开系统全屏
- 剩余风险：恢复重解析专项仍为 `NOT_RUN`；Windows 真实验证仍为 `NOT_RUN`

### 阶段 4：平台参数化与 Windows 真实验收

- 状态：进行中
- 阶段 4.1：平台能力契约 **7/7 通过**；`live_parser` 分析通过，解析测试 **378 通过 / 10 跳过（真实网络）**
- 已验证：10 个目标平台均注册；能力位与 repository/connector 存在性一致；不支持能力不伪造接口；房间音量 key 跨平台隔离
- 待完成：Windows release 真实 smoke 与证据记录

### 阶段 5：收口门禁

- 状态：未开始
- 范围：全量门禁、进度归档和已知风险清单

## 5. 问题登记

### BUG-WIN-VOLUME-001

- 状态：自动化已修复，Windows 真实验证待执行
- 影响范围：所有使用同一 `LivePlayer` 实例的播放平台
- 场景：房间 A 调整音量后进入房间 B
- 已知现象：用户观察到音量条未变化或显示值与实际音量不一致，实际音量可能回到 100%
- 根因：`PlayController._open()` 原先并行启动 `player.open()` 与 `_applyRoomVolume()`；`open` 重建底层音频管线后可能把音量恢复为 100%，没有完成后的最终补偿
- 修复：`_openAndApplyVolume` 在当前 generation 下先应用一次，等待 `player.open()` 完成后再应用一次；旧 generation 不执行收尾补偿
- 自动化回归：`test/features/playback/play_controller_volume_lifecycle_test.dart` **6/6 通过**
- 相关纯逻辑：`test/features/playback/room_volume_provider_test.dart` **10/10 通过**
- 修复提交：待本阶段提交
- Windows 证据：NOT_RUN

## 6. 状态更新规则

1. 测试先写失败用例，再实现修复；
2. 自动化测试通过后才可将自动化列标记为 `PASS`；
3. Windows 真实验证必须有构建版本、平台、测试 ID、日志路径或截图证据；
4. 能力不支持标记 `N/A`，网络不可用或凭据缺失标记 `BLOCKED`；
5. 没有执行过的测试保持 `NOT_RUN`；
6. 每个阶段完成后记录测试总数、失败数、提交和剩余风险。
