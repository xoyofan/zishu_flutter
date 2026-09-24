# Windows 公共功能跨平台测试矩阵

> 目标：验证 Windows 客户端在所有已注册平台上的公共功能。本文档同时记录自动化测试、Windows 真实 smoke、问题根因、修复提交和证据路径。
>
> 状态枚举：`PASS` / `FAIL` / `BLOCKED` / `N/A` / `NOT_RUN`。
>
> 当前阶段：阶段 5（收口门禁）。阶段 4 的 Windows release 真实 smoke 已于 2026-09-20 执行完毕（release 构建 `--dart-define=ZISHU_REAL_PARSER=true`，commit 725a1a2，证据目录 `tool/windows-public-smoke/rel-smoke-20260920/`，已 gitignore）。IPTV 平台已于 2026-09-24 整平台移除（解析轨 `85b0471` / UI 轨 `deb5096`），CC 已停运无实现，均不再列入矩阵。

## 1. 平台能力基线

| 平台 | Browse | Search | Multi-quality | Multi-line | Danmaku | Status refresh | Playback | 自动化契约 | Windows 真实 |
|---|---:|---:|---:|---:|---:|---:|---:|---|---|
| `douyu` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `huya` | PASS | PASS | PASS | PASS | PASS | NOT_RUN | NOT_RUN | PASS | FAIL |
| `bilibili` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `douyin` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `kuaishou` | PASS | N/A | PASS | PASS | PASS | NOT_RUN | NOT_RUN | PASS | PASS |
| `yy` | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS | PASS |
| `twitch` | PASS | PASS | PASS | PASS | PASS | PASS | NOT_RUN | PASS | BLOCKED |
| `soop` | PASS | PASS | PASS | PASS | PASS | NOT_RUN | NOT_RUN | PASS | PASS |
| `youtube` | PASS | N/A | PASS | PASS | PASS | N/A | NOT_RUN | PASS | PASS |

> 上表中的 `PASS` 表示能力已在当前代码/解析测试记录中存在，不表示本轮 Windows 真实 smoke 已通过。真实验证必须在阶段 4 逐平台填入证据。
>
> **Windows 真实列说明（2026-09-20 release smoke）**：
> - `douyu` PASS：browse/播放/弹幕(已连接+滚动+飘屏)/画质(原画1080P60→蓝光4M)/线路(7→13 FLV)/音量(35 隔离恢复)/关注 toggle+超关联动/返回 全通过；切房返回弹幕不自动重连见 BUG-WIN-DANMAKU-002。
> - `huya` FAIL：browse/播放/音量记忆落盘通过；弹幕「已连接」但 37s+ 零消息（BUG-WIN-DANMAKU-003）；房间详情关注/人气/超关数未解析（PARSER-GAP-001，用户口径）。
> - `bilibili` PASS：竖屏自适应播放、弹幕已连接并收到消息；房间详情字段缺失归入 PARSER-GAP-001。
> - `douyin` PASS：推荐流 browse、第二房间(爱瑜伽)弹幕已连接收流；首个带货房零消息属房间冷清非缺陷。
> - `kuaishou` PASS：播放+弹幕收流（昵称:正文）；表情显示 `[贊]`/`[笑哭]` 文本占位归入 PARSER-GAP-002。
> - `yy` PASS：播放通过；弹幕正确呈现「当前站点暂不支持弹幕」N/A 态（诚实呈现，不伪造）。
> - `twitch` BLOCKED：播放/画质(720p60→480p)/单线路 HLS/静音/全屏/PiP 全通过；弹幕连接失败且刷新无效（BUG-WIN-DANMAKU-004，出口抖动+connector 层真机复验遗留）。
> - `soop` PASS：韩文房播放、24+ 条韩文聊天弹幕与多条韩文飘屏（裸 socket+CONNECT 隧道真机确认）。
> - `youtube` PASS：browse(27,490/120,219 watching)、换房后播放+多语言弹幕刷屏；个别频道(HOY)流拉不动见 OBS-WIN-PLAY-001。

## 2. 公共功能 ID

| ID | 功能 | 当前自动化 | Windows 真实 | 说明 |
|---|---|---|---|---|
| `VOL` | 房间音量隔离与恢复 | PASS | FAIL | A→B→A 恢复、跨平台有记忆房隔离、切画质/线路保持均真实验证通过；但无记忆新房间 slider 继承上一房间值（VOL-001 场景 FAIL，BUG-WIN-VOLUME-002） |
| `MUTE` | 静音/取消静音 | PASS | PASS | twitch 房静音图标/slider 灰化与恢复（`twitch-muted.png`） |
| `QUALITY` | 默认画质与切换 | PASS | PASS | twitch 720p60→480p、douyu 原画1080P60→蓝光4M，切档后播放不中断且音量保持 |
| `LINE` | 线路格式、线路切换和备用线路 | PASS | PASS | douyu 线路7 FLV→线路13 FLV 播放连续；twitch 真实仅单线路 HLS（无可切第二条，符合源实况） |
| `DANMAKU` | 弹幕连接、切房、设置和去重 | PASS | FAIL | douyu/bilibili/douyin/kuaishou/soop/youtube 真实收流通过（含飘屏正文）；twitch 连接失败 BLOCKED、huya 已连接零消息 FAIL、douyu 切房返回不自动重连 |
| `FULLSCREEN` | 系统全屏/网页全屏 | PASS | PASS | twitch 系统全屏铺满 1920x1080 控制条保留，Esc 退出回播放页且播放连续 |
| `PIP` | 画中画进入、退出和恢复 | PASS | PASS | twitch PiP 缩为 360x202 小窗播放连续，Esc 退出恢复播放页且画质记忆保持 |
| `FOLLOW` | 关注、超关、状态刷新和同步 | PASS | PASS | douyu pigff 取消关注→「关注/+超关」（超关联动取消）→重新关注→恢复「已关注/已超关」；侧栏关注行点击跨平台切房 |
| `THEME` | 深浅主题与设置恢复 | PASS | PASS | 深色↔浅色全页即时切换（`theme-light.png`）；发现「金色」循环文案残留与强调色口径见 UI-BUG-002（用户口径：强调色应改紫色） |
| `RETURN` | 返回按钮、Alt+左、鼠标侧键 | PASS | PASS | 播放页返回按钮多次回列表验证；Alt+左/侧键真实按键未单独执行（自动化已覆盖） |

## 3. 音量回归用例

| 用例 ID | 场景 | 预期 | 自动化 | Windows 真实 | 证据 |
|---|---|---|---|---|---|
| `VOL-001` | 房间 A 设置音量 35 后进入房间 B | B 使用 B 的记忆值或默认值，不能继承 A | PASS | FAIL | 有记忆 B 房(twitch 86.8)正确用自身值；但无记忆 B 房(huya/bilibili)slider 显示 36.8=A 值，落盘无 huya 记录——BUG-WIN-VOLUME-002（`huya-play.png`） |
| `VOL-002` | 从 B 返回 A | A 恢复 35 | PASS | PASS | douyu A 调 36.8→twitch B 调 86.8→回 A slider 仍 36.8（`vol-A-back-35.png`） |
| `VOL-003` | `douyu:123` 与 `huya:123` | 两个平台音量独立 | PASS | PASS | 落盘 `room_vol_douyu_24422=36.8` 与 `room_vol_twitch_zackrawrr=86.8` 互不影响（shared_preferences.json） |
| `VOL-004` | `open` 完成后底层音量重置为 100 | 最终播放器实际音量仍为设置值 | PASS | NOT_RUN | 底层 media-kit 内部值真实环境不可观察，自动化已覆盖（`play_controller_volume_lifecycle_test.dart`） |
| `VOL-005` | 切换画质 | 音量和静音状态保持 | PASS | PASS | douyu 切蓝光4M 后 slider 仍在 36.8 位置（`douyu-quality-4m.png`） |
| `VOL-006` | 切换线路 | 音量和静音状态保持 | PASS | PASS | douyu 切线路13 后 slider 位置不变（`douyu-line13.png`） |
| `VOL-007` | 断流恢复/重新解析 | 音量和静音状态保持 | PASS | NOT_RUN | 真实断流场景未主动构造 |
| `VOL-008` | 全局静音后切房 | 所有房间实际音量为 0 | PASS | NOT_RUN | 真实未执行全局静音切房链 |
| `VOL-009` | 房间音量设为 0 但未开启全局静音 | 该房间为 0，取消/切房不误恢复成 100 | PASS | NOT_RUN | 真实未执行 0 值房间链 |
| `VOL-010` | A→B→C 快速切房 | 只有 C 的最终状态生效 | PASS | NOT_RUN | 真实快速三房链未执行（A→B→A 已验证） |
| `DAN-001` | 切房销毁旧 session | 旧 session close，迟到消息不进入新房间 | PASS | NOT_RUN | twitch 侧 session 本就未连，真实无串扰样本；切房返回不重连见 BUG-WIN-DANMAKU-002 |
| `DAN-002` | 重连去重与最新 generation | 只保留最新 session，旧连接不再广播 | PASS | NOT_RUN | 真实未构造连续重连 |
| `DAN-003` | chat/overlay 共享会话 | 只建立一条连接，两个消费者收到同一状态 | PASS | NOT_RUN | 真实无法分别观察 chat/overlay 连接数 |
| `DAN-004` | 不支持平台不建连 | 返回明确 `supported=false` 空态 | PASS | PASS | yy 房呈现「● 弹幕不支持/当前站点暂不支持弹幕」诚实空态（`yy-play.png`） |
| `DAN-005` | 弹幕设置 clamp 与生效 | 设置立即生效且始终落在合法范围 | PASS | NOT_RUN | 真实未操作弹幕设置面板 |
| `UI-001` | 全屏/PiP 退出优先级 | PiP > 系统全屏 > 网页全屏 > 路由返回 | PASS | PASS | 系统全屏态按 Esc 退出全屏而非返回路由，仍留播放页（`twitch-fullscreen-esc-exit.png`） |
| `UI-002` | PiP 退出恢复模式并清理记忆 | 恢复进入前模式，退出后不残留 `modeBeforePip` | PASS | PASS | PiP Esc 退出恢复播放页常规布局，480p 画质记忆保持（`twitch-pip-exit4.png`） |
| `UI-003` | PiP/全屏销毁清理 | 离开播放页不残留窗口级副作用 | PASS | NOT_RUN | 真实未在 PiP/全屏态直接离开播放页 |
| `UI-004` | 返回快捷键和主题切换 | Alt+左/侧键安全返回，主题 provider/MaterialApp/token 同步 | PASS | PASS | 主题按钮深→浅→深全页即时切换（`theme-light.png`/`theme-back-dark.png`）；Alt+左未单独执行 |

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
  - 音量专项补齐 VOL-007/VOL-008/VOL-010：新增恢复、全局静音切房和跨 family 快速切房回归；修复共享 `LivePlayer` 缺少全局 open token 导致旧房间收尾覆盖新房间的问题
  - FOLLOW 公共能力矩阵 **3/3 通过**；覆盖关注持久化、特别关注、跨平台房间身份和刷新失败隔离
- 已完成：
  - 阶段 3.1 画质/线路矩阵 **2/2 通过**；发现并修复 `switchLine()` 绕过统一 `_open()` 的状态污染缺口
  - 阶段 3.2 弹幕会话矩阵 **5/5 通过**；弹幕目录 **51/51 通过**；UI workflow **10/10 通过**
  - 阶段 3.3 全屏/PiP/返回/主题矩阵：新增 **5/5**，全屏/PiP **10/10**，返回/主题/浅色 **11/11**；修复 PiP 退出后残留 `modeBeforePip` 及销毁期间异步续段重开系统全屏
- 剩余风险：Windows 真实验证仍为 `NOT_RUN`

### 阶段 4：平台参数化与 Windows 真实验收

- 状态：已完成（2026-09-20）
- 阶段 4.1：平台能力契约 **7/7 通过**；`live_parser` 分析通过，解析测试 **378 通过 / 10 跳过（真实网络）**
- 已验证：10 个目标平台均注册；能力位与 repository/connector 存在性一致；不支持能力不伪造接口；房间音量 key 跨平台隔离
- 阶段 4.2 Windows release 真实 smoke：已执行
  - 构建：`flutter build windows --release -t lib/main.dart --dart-define=ZISHU_REAL_PARSER=true`（commit 725a1a2，构建耗时 36.2s）
  - 执行方式：schtasks 拉起 release exe，`tool/_smoke.py` 真实鼠标/键盘/拖动操作，`PrintWindow(PW_RENDERFULLCONTENT)` 抓窗口表面存证
  - 覆盖：9 平台真实 browse+进房+播放（iptv 按用户口径跳过）；功能级 VOL/MUTE/QUALITY/LINE/DANMAKU/FULLSCREEN/PIP/FOLLOW/THEME/RETURN
  - 结果：见第 1/2/3 表「Windows 真实」列；证据目录 `tool/windows-public-smoke/rel-smoke-20260920/screenshots/`（gitignore，不入库）
  - 用户本轮口径（2026-09-20，已登记）：IPTV 不用管；弹幕表情未解析为图片；多平台房间详情关注/VIP/徽章平台等级等字段未解析；聊天折行第二行应顶格；无金色主题、控件强调色应为紫霄紫色

### 阶段 5：收口门禁

- 状态：已完成（2026-09-20）
- 全量门禁 `tool/_gate.py --goldens`（goldens → app-test → analyze → parser-test）全绿：
  - goldens rc=0（7 png 同步至 `tool/screenshots/zishu`）
  - app-test rc=0（**644 通过**）
  - app-analyze rc=0（No issues found）
  - parser-analyze rc=0（No issues found）
  - parser-test rc=0（**378 通过 / 10 跳过真实网络**）
- 进度归档：本矩阵文档 + `todo.md` 记录
- 已知风险与待修清单（全部已登记于第 5 节问题登记，不阻塞归档）：
  1. BUG-WIN-VOLUME-002 无记忆新房间音量继承上一房间值（VOL-001 真实 FAIL）
  2. BUG-WIN-DANMAKU-002 douyu 切房返回弹幕不自动重连（刷新可恢复）
  3. BUG-WIN-DANMAKU-003 huya 弹幕已连接但零消息
  4. BUG-WIN-DANMAKU-004 twitch 弹幕连接失败（出口抖动 + connector 真机复验遗留）
  5. PARSER-GAP-001 多平台房间详情字段缺失（关注数/人气/超关数/VIP/贵族标/粉丝徽章平台等级；用户口径）
  6. PARSER-GAP-002 弹幕表情未渲染为图片，显示 `[名]`/`:name:` 文本占位（用户口径；对应 backlog 表情 segments 内联与 twitch emote）
  7. UI-BUG-001 聊天弹幕折行第二行未顶格（用户口径）
  8. UI-BUG-002 「金色」主题循环文案残留；slider/按钮等控件强调色应改为紫霄紫色（用户口径）
  9. OBS-WIN-PLAY-001 youtube 个别频道（HOY 亚运）流拉不动黑屏转圈，换房正常
  10. OBS-WIN-OVERLAY-001 飘屏多轨重叠观感问题

## 5. 问题登记

### BUG-WIN-VOLUME-001

- 状态：自动化已修复，Windows 真实验证待执行
- 影响范围：所有使用同一 `LivePlayer` 实例的播放平台
- 场景：房间 A 调整音量后进入房间 B
- 已知现象：用户观察到音量条未变化或显示值与实际音量不一致，实际音量可能回到 100%
- 根因：`PlayController._open()` 原先并行启动 `player.open()` 与 `_applyRoomVolume()`；`open` 重建底层音频管线后可能把音量恢复为 100%，没有完成后的最终补偿
- 修复：`_openAndApplyVolume` 在当前 generation 下先应用一次，等待 `player.open()` 完成后再应用一次；旧 generation 不执行收尾补偿
- 自动化回归：`test/features/playback/play_controller_volume_lifecycle_test.dart` **10/10 通过**；覆盖恢复重解析、全局静音切房和跨 family 快速切房
- 相关纯逻辑：`test/features/playback/room_volume_provider_test.dart` **10/10 通过**
- 修复提交：e4c0978 前序已含（open 完成后最终补偿）
- Windows 证据：PASS——A(36.8)→B(twitch 86.8)→回 A 仍 36.8，跨平台隔离与恢复真实成立（`vol-A-back-35.png` + shared_preferences 落盘）

### BUG-WIN-VOLUME-002

- 状态：已登记，待修复
- 影响范围：所有平台的「无音量记忆新房间」
- 场景：房间 A 调整音量后进入一个从未设置过音量的房间 B
- 现象：B 的控制条 slider 显示 A 的值（如 36.8%），而 `zishu.settings.roomVolumes` 落盘中无 B 记录——新房间默认值实现为「继承上一房间」而非默认 100，违反 VOL-001 预期；自动化单测（B 默认 100）与真机行为不一致
- 证据：`huya-play.png`（slider≈35%）+ 落盘仅 `room_vol_douyu_24422=36.8`、`room_vol_twitch_zackrawrr=86.8` 两条；bilibili 新房同样复现
- Windows 证据：FAIL

### BUG-WIN-DANMAKU-002

- 状态：已登记，待修复
- 影响范围：douyu（至少）切房返回场景
- 场景：A(douyu) → B(twitch) → 返回 A
- 现象：回到 A 后弹幕状态「未连接」「暂无弹幕」，首次进房时是自动连接；点「刷新」立即恢复「已连接」并收流
- 根因方向：切房后新 session 建连失败/未发起且无自动重试（或 douyu 对快速重连限流后缺少退避重试）
- Windows 证据：`douyu-danmaku-t1.png`/`t2.png`（未连接）vs `douyu-danmaku-retry.png`（刷新后已连接+收流）

### BUG-WIN-DANMAKU-003

- 状态：已登记，待排查
- 影响范围：huya 弹幕收流
- 场景：进入 huya 在播房间（三桂园区-泫法，26.6 万人气）
- 现象：状态行「● 弹幕已连接」（绿点），但 37s+ 聊天区零消息
- 根因方向：huya 弹幕注册/心跳/订阅包或消息解包层问题（连接建立 ≠ 消息订阅成功）
- Windows 证据：`huya-danmaku-t1/t2/t3.png`

### BUG-WIN-DANMAKU-004

- 状态：已登记（backlog 已知「twitch connector 层真机复验」的延续），待排查
- 影响范围：twitch 弹幕
- 现象：播放/画质/聊天区正常，但「● 弹幕未连接」，点刷新无效；此前 GQL 受出口抖动影响超时、irc-ws 443 直连确认可达
- Windows 证据：`twitch-danmaku-t2.png`、`twitch-danmaku-retry.png`

### PARSER-GAP-001

- 状态：已登记（用户口径 2026-09-20），待排期
- 范围：huya/bilibili/douyin/kuaishou/yy/soop/twitch/youtube 房间详情
- 现象：主播卡「关注数/人气值/超关数」显示「—」；VIP/贵族标、粉丝徽章平台等级等未解析（douyu 房间详情字段完整可对照）
- 口径：数据诚实性——解析层没有的字段显示「—」不伪造；本项是把缺失字段补解析
- Windows 证据：`huya-play.png`、`bilibili-danmaku-t2.png` vs `douyu-play.png`（douyu 有真实数值）

### PARSER-GAP-002

- 状态：已登记（用户口径 2026-09-20），待排期
- 范围：全平台弹幕表情
- 现象：弹幕正文中表情以文本占位显示——kuaishou `[贊]`/`[笑哭]`、youtube `:crossed_flags:`/`:grinning_face_with_sweat:`，未渲染为图片
- 关联 backlog：表情 segments 飘屏图片内联、twitch emote 渲染（segments 契约已就绪）
- Windows 证据：`kuaishou-danmaku-t3.png`、`youtube-danmaku-t2.png`

### UI-BUG-001

- 状态：已登记（用户口径 2026-09-20），待修复
- 现象：同一条弹幕正文折行时第二行未从最左侧顶格开始
- Windows 证据：`douyin-danmaku2.png`（第三条弹幕折行样本）

### UI-BUG-002

- 状态：已登记（用户口径 2026-09-20），待修复
- 现象 1：主题循环中出现「金色」文案，但不存在金色主题（深→浅→深循环，中间态文案残留）
- 现象 2：slider、按钮等控件强调色目前为黄/橙系，用户口径应统一改为紫霄品牌紫色
- Windows 证据：`theme-light.png`（按钮文案「金色」）、各播放截图控制条黄色 slider

### OBS-WIN-PLAY-001

- 状态：观察项（非本轮回归）
- 现象：youtube 个别频道（HOY 亚运专区，120,219 watching）流拉不动：黑屏+加载 spinner 37s+，刷新无效；换房（YoTyan Arena）播放正常
- 方向：单频道流源/代理带宽问题，非播放器回归
- Windows 证据：`youtube-play.png`、`youtube-play-t3.png` vs `youtube-play2.png`

### OBS-WIN-PLAY-002

- 状态：观察项（2026-09-20 用户报告「播放一会就卡」，单次出现，复现性未确认）
- 场景：真机长时间播放（douyu Gemini 房）期间，宿主正在后台跑全量 flutter test（多进程编译+运行，CPU 吃满）
- 现象：画面冻结数分钟；冻结期间弹幕持续收流（连接正常），控制条呈「▶」暂停态而侧栏状态行仍显示「▶ 播放中」——播放呈现与 provider 状态不同步（与 BUG-WIN-VOLUME-002 同族：底层状态变化未驱动快照）
- 初判：最可能是测试负载挤占解码/渲染（负载释放后待确认）；若正常负载下稳定复现，需排查 mpv 暂停/停顿/EOF 事件是否被围栏丢弃（参照 volume 快照修法）
- Windows 证据：`check-stuck.png`（冻结帧+弹幕滚动+状态矛盾）

### OBS-WIN-VIDEO-001

- 状态：已登记（2026-09-20 用户报告，多次复现），待排查
- 现象：进入房间后播放状态为「播放中」但画面黑屏（舞台飘屏弹幕与聊天正常渲染）；**点暂停再点播放后画面立即显示**（kick 强制 mpv 重出一帧即恢复）
- 方向：media-kit VideoController 纹理首帧未送 UI（GPU/驱动时序类）；候选修复 = 播放中但 videoInfo 长期缺失时自动 pause/play kick 一次
- Windows 证据：`verify-popover-compact2.png`（黑屏+飘屏/弹幕正常）

### OBS-WIN-OVERLAY-001

- 状态：观察项（低优先）
- 现象：飘屏多条弹幕在不同轨道出现重叠观感（youtube 房顶部）
- Windows 证据：`youtube-play2.png` 顶部

### OBS-WIN-AUTO-001

- 状态：观察项（自动化工具层，非用户可见）
- 现象：全屏/PiP 切换瞬间 `FindWindow/EnumWindows` 间歇 NO_WINDOW；合成输入序列曾偶发一次非预期切房（douyu→twitch），随后拖动复测 10+ 次未再现
- 结论：真实鼠标键盘输入功能正常；自动化脚本需对窗口枚举做重试

## 7. Task 4.2 Windows 公共 smoke 记录

Task 4.2 的记录脚本为 `tool/windows_public_smoke.ps1`。它只负责创建人工验收 checklist、记录 build/git/evidence 元数据，并可按显式 `-Launch` 请求启动 release exe；不会自动点击、访问网络、登录、写入凭据，也不会根据进程启动结果推断 `PASS`/`FAIL`。未实际执行的条目默认保持 `NOT_RUN`。

### 使用方法

在本 worktree 根目录执行（PowerShell）：

```powershell
# 只生成 checklist 和 evidence.json；不启动应用、不进行真实平台操作
powershell -ExecutionPolicy Bypass -File .\\tool\\windows_public_smoke.ps1 -DryRun -Checklist

# 指定 release exe 和证据目录；仍需人工执行 checklist
powershell -ExecutionPolicy Bypass -File .\\tool\\windows_public_smoke.ps1 `
  -ExePath build\\windows\\x64\\runner\\Release\\zishu_flutter.exe `
  -EvidenceDir C:\\temp\\zishu-windows-smoke

# 可选启动应用；启动后仍必须人工验证并记录状态
powershell -ExecutionPolicy Bypass -File .\\tool\\windows_public_smoke.ps1 -Launch
```

默认 release exe 为 `build/windows/x64/runner/Release/zishu_flutter.exe`，默认临时证据目录为 `tool/windows-public-smoke/<timestamp>`，该目录已加入 `.gitignore`。也可以通过 `-EvidenceDir` 指向 worktree 外的临时目录。脚本不生成 build、截图、凭据或 playback log。

截图证据推荐使用现有 `tool/win_tool.py` 的窗口表面抓取：

```powershell
py tool/win_tool.py shot <evidence-dir>\\screenshots\\<platform>-<test-id>.png
```

该命令使用 `PrintWindow(PW_RENDERFULLCONTENT)`；`shotdesktop` 的屏幕合成截图只能作为补充，不能作为唯一证据。真实验收还应由人工记录首帧、播放、音量、静音、切房、返回、弹幕等适用功能结果。

### 证据 schema

脚本生成 `<evidence-dir>/evidence.json` 和 `<evidence-dir>/checklist.md`。`evidence.json` 的核心字段如下：

- `schemaVersion`：证据格式版本。
- `generatedAt`：生成时间（UTC）。
- `testId` / `platform` / `status`：本轮记录的测试 ID、平台和总体状态。脚本生成阶段的总体状态固定为 `NOT_RUN`；人工验证后再编辑证据文件，状态只能是 `PASS`、`FAIL`、`BLOCKED`、`N/A`、`NOT_RUN`。
- `build.executable` / `build.version` / `build.gitCommit`：release exe 路径、文件版本（缺少 exe 时为 unavailable）和 Git commit。
- `evidence.logPath` / `evidence.screenshotPath`：人工日志和截图目录/路径。
- `evidence.screenshotMethod`：要求优先使用 `PrintWindow(PW_RENDERFULLCONTENT)` 的说明。
- `checklist[]`：按平台和公共功能 ID 展开的条目；每项包含 `platform`、`testId`、`status`、`logPath`、唯一的 `screenshotPath`（默认 `<platform>-<testId>.png`）、`notes`，默认状态全部为 `NOT_RUN`。

### 当前执行状态

2026-09-20 已完成一轮真实 Windows release smoke（commit 725a1a2，`--dart-define=ZISHU_REAL_PARSER=true`）。执行方式：schtasks 拉起 release exe → `tool/_smoke.py`（真实鼠标 click/双击/拖动、键盘 Esc）逐平台操作 → `PrintWindow(PW_RENDERFULLCONTENT)` 抓窗口表面存证。证据目录 `tool/windows-public-smoke/rel-smoke-20260920/`（已 gitignore，不入库；`evidence.json`/`checklist.md` 由 `tool/windows_public_smoke.ps1 -DryRun -Checklist` 生成后人工回填状态）。

本轮结论：9 平台真实 browse+进房+播放通过（iptv 按用户口径跳过）；VOL 隔离/恢复、MUTE、QUALITY、LINE、FULLSCREEN、PIP、FOLLOW、THEME、RETURN 真实通过；DANMAKU 6 平台收流通过但 twitch BLOCKED / huya FAIL；VOL-001 场景因 BUG-WIN-VOLUME-002 真实 FAIL。全部问题已登记于第 5 节。阶段 5 全量门禁全绿（goldens 7、app-test 644、analyze 0 issue、parser-test 378/10 跳过）。

### 后续人工步骤

1. 按 PARSER-GAP-001/002 与 UI-BUG-001/002 排期修复（用户口径优先）；
2. 修复后重跑受影响的真实 smoke 子集（音量 VOL-001 新房链、douyu 切房返回弹幕、huya/twitch 弹幕）并回填本矩阵；
3. BUG-WIN-VOLUME-002 修复时先补自动化失败用例（新房间默认 100）再改实现；
4. 网络不可用或凭据缺失的条目保持 `BLOCKED`，未执行项保持 `NOT_RUN`，不以脚本 dry-run 或 exe 启动冒充 `PASS`。

## 8. 状态更新规则

1. 测试先写失败用例，再实现修复；
2. 自动化测试通过后才可将自动化列标记为 `PASS`；
3. Windows 真实验证必须有构建版本、平台、测试 ID、日志路径或截图证据；
4. 能力不支持标记 `N/A`，网络不可用或凭据缺失标记 `BLOCKED`；
5. 没有执行过的测试保持 `NOT_RUN`；
6. 每个阶段完成后记录测试总数、失败数、提交和剩余风险。
