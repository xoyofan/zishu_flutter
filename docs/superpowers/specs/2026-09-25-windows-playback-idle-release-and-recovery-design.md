# Windows 播放器空闲释放与有限恢复设计

**日期：** 2026-09-25
**状态：** 待用户审阅
**范围：** Windows Flutter 新播放链路；Web/Android 共享接口不得破坏。用户要求 `chatgoai/gpt-6-luna` 实现，`chatgoai/gpt-6-sol` 独立验收。

## 1. 意图与验收目标

解决回首页后 `media-kit` Player/视频输出长期保留 native/GPU 内存的问题，同时避免缓冲状态误判造成重复重开及画面卡顿。切房仍应快速，原画质不降档，聊天连接不随播放器保活。窗口点击/切页迟钝不在本轮范围。

- 切房复用单个播放器；离开播放页立即停止旧媒体源，20 秒内再进房复用播放器，超过 20 秒销毁播放器及视频输出；首页在首次进房前不创建 native Player。
- 普通 `buffering` 只改变展示状态，不触发自动重开；明确的终局开流失败、异常结束才启动有限恢复。同一连续故障**最多三次实际自动重开**，包括换新 URL 后的开流；用尽即闩锁，用户可手动重试。达到现有健康观察窗（10 秒）后才重置故障预算。
- 真实房间/画质保持，聊天与叠加弹幕共用房间会话并在切房/离房时关闭旧连接；不复制旧房消息、不自动降画质。
- 以真实播放器日志及 Windows 内存/GPU/线程采样核对空闲释放；不把任务管理器单点截图或 mpv `playing` 事件误写成真实像素首帧。

## 2. 现状与反例

`playerProvider` 目前是应用级单例；`playControllerProvider` 离场只调用 `stop()`，根容器退出时才 `dispose()`。`media_kit` 的 `NativePlayer.stop()` 明确卸载播放列表但不释放 Player 资源；`NativeVideoController` 的 `VideoOutputManager.Dispose` 在 `Player.dispose()` 的 release 回调上。因此切房后的旧源会停止，但首页仍可能保留 mpv/视频输出的 native/GPU 基线。曾观察到同一进程退出播放页后 Private Bytes 约 928 MB、GPU Dedicated 约 366 MB 且 120 秒稳定；重启后的进程更低，但该数值差异尚未通过同进程 `stop` 对 `dispose` 的 A/B 证明全由 Player 引起。

当前 `_onBuffering(true)` 启动 watchdog，`_resyncAfterOpen()` 也会在非 playing 态挂定时器；计时器可重开旧地址。`_recoverOrGiveUp()` 拿新地址后把 `_stallRetries` 清零并 `open(..., resetRetries: true)`，可额外开一轮；这与本次三次总预算冲突。`playerSnapshotProvider`、播放控件、PiP、呈现态、睡眠定时器都读取 `playerProvider`，不能简单改为 `autoDispose` 或销毁后沿用已捕获的旧 Player。

## 3. 选择与替代方案

**选择：稳定的应用级播放器入口 + 内部可重建的 native 会话。**入口不等于保活的原生 Player：首次播放才创建；切房保持一个 native 实例；离播放路由后 `stop` 并排一次 20 秒释放；释放后下次播放重新创建 Player/VideoController，快照转发和 UI 获取仍通过稳定入口，避免旧 Widget/睡眠定时器持有已销毁实例。具体实现可用最小的会话所有者，不为播放器、聊天再引入两套全局资源池。

不选“整个播放页单例”：它会额外保留 Widget、聊天消息和定时器，破坏离房释放；不选“每房新 Player”：失去切房快速复用；不选“直接将现有 `playerProvider` 设 `autoDispose`”：多个 `ref.read` 及异步生命周期队列不能保证监听数等同于活跃房间。

与 pure_live 的关系：沿用首次进房懒创建、切房串行、聊天独立销毁；不照搬其默认无限期 `softStop()` 保留 Player，而在 20 秒后调用硬释放；`buffering` 只更新状态，但保留本项目明确错误和完成事件的有限重试。

## 4. 生命周期和竞态

- **首次进房**：获得活跃播放租约，先撤销空闲销毁计时器；若 native Player 不存在，初始化并订阅一次底层流，随后走既有解析/开流、线路偏好和音量流程。没有播放租约时，首页/睡眠定时器读取状态不得隐式创建 Player。
- **A→B 切房**：路由间可能短时并存；旧房 `stop()`、新房 `open()` 依现有生命周期队列和全局代际按顺序执行。旧房离场不得把新房播放器判为闲置、不能晚到清除 B 的恢复回调/快照或销毁 B。聊天的 `autoDispose.family` 按各自房间关闭旧连接。
- **回首页**：最后一个播放页离场时先注销旧恢复回调并 `stop()`，确认旧源停止后记录资源样本，排程 20 秒计时。计时器到期必须再次确认无活跃租约、未被新一代操作取代，串行执行 native `dispose()`；清理快照订阅/视频输出。退出后 native 销毁可能延迟约 5 秒，采样窗口须覆盖它。
- **20 秒内/超时边界再进房**：进房先取消定时器并推进代际；若 `dispose()` 尚未开始，直接复用；若已开始，等待它完成后创建新 Player，绝不对已销毁实例 `open()`。App 根容器退出时取消 Timer 并最终释放，异步完成不能反向创建新 Player。
- **睡眠定时器**：到点仅停止当前活跃播放；若已空闲或 native 实例已销毁，停播是幂等空操作，不得重新分配 Player。

需要记录 `player_created`、`player_idle_scheduled`、`player_idle_cancelled`、`player_dispose_start/end`（含耗时/RSS）等低频事件，用现有 `PlaybackLog` 与 `tool/sample_runtime.ps1` 的 Private/GPU/Threads 关联。日志不包含完整播放 URL/token。

## 5. 三次实际重开预算与画面卡顿

- `buffering=true/false` 更新快照和提示，不启动重开计时器、不增加预算。依赖 mpv 的网络超时、真实终局错误或 `completed=true` 表示失败；旧广告过滤的合法无段等待不能被判作终局。
- 终局错误/异常结束在同一源代际内只排一次恢复任务；记录故障类别和本次尝试序号。尽量利用 mpv 播放列表已有线路自动切换，避免与 mpv 并行重新打开同组旧地址。
- 一次实际调用底层 `open` 尝试自动恢复计数 +1，上限 3。签名源确认过期、源级失败阈值达到时，可通过 `RoomRecoverer` 重新解析后**使用剩余预算**打开新 URL；重解析本身不计为重开，但其后每次实际 `open` 都计数。耗尽后只提示手动重试，不可“最后再恢复一次”或新 URL 到手后把预算清零。
- 只有本次会话连续健康播放满现有 10 秒窗口，才清零连续故障计数。手动重试/主动切房开始新会话且重置预算；上一代迟到的重解析结果不能重开当前房间或越过三次上限。
- 因移除 buffering watchdog，若上游流永远缓冲且不报终局错误，也不会自动重开：显示明确缓冲状态与手动重试入口，不声称自动检测了所有冻结。可先用 mpv 实际错误/完成事件验证，再决定是否需要独立的真实帧进度检测；不能恢复按 buffering 误判重开。

**性能诊断先于额外调参**：区分源断流、软件解码跟不上和错误重开。`open_to_first_frame` 目前只是 mpv `playing` 事件，不能当真实渲染帧；如果必须判定掉帧，使用可核对的 mpv 解码/丢帧指标或真实视频输出观测。未经同场景数据验证，不扩大缓存、不盲改 `hwdec`、不自动降低用户画质，也不承诺本轮会消除所有外部网络抖动。

## 6. 测试、真机验收与回滚

- TDD：假 Player + fake clock 验证懒创建、20 秒内取消、20 秒后释放、销毁中再进房、A→B→C 与旧 stop 并发、睡眠定时空闲幂等、根容器销毁；释放时旧的快照订阅与视频输出不得留存。
- 恢复矩阵：纯 buffering 无 `open`；首次/第二/第三次终局故障依次尝试；第三次后 `give_up` 且不发生第四次；恢复拿新 URL 仍计入三次；正常播放满 10 秒后重置；旧回调、重复 error/completed、广告等待、手动重试均覆盖。同步更新依赖旧 `maxAttempts=6` 和 watchdog 的测试。
- 根工程先执行两个独立 package 的 `pub get`，再 `flutter analyze`、相关 `flutter test`、全量 `flutter test`、`flutter build windows --debug -t lib/main.dart`；真机用 Release 真实解析构建验证，不覆盖当前正在运行的 EXE。
- Windows 实测固定同一房间/画质/视口，记录“进房到真正视频首帧”及资源曲线：连续切房、退房 10 秒内重进、退房超 20 秒重进，以及至少 30 分钟同房播放；对照 `resource_sample`、Player create/dispose 事件和 `tool/sample_runtime.ps1` 的 Private/GPU/Threads。超过 20 秒后 GPU/线程应较保留态下降且稳定；Private Bytes 未立即归零不能直接判为泄漏。对比直播卡顿前后 `reopen_requested`/`give_up` 数量和肉眼画面中断，不把日志通过等同于网络真机体验通过。
- 若硬释放后反复进房出现黑屏、已销毁 Player 被使用或首帧明显恶化，优先回滚到“`stop()` 后保留 Player”，不回退房间弹幕清理与三次重试预算；记录真实日志再定更合适的延迟。

## 7. 非目标

不将播放页 Widget 或聊天连接做全局单例；不引入新的播放器内核、远端遥测服务、平台站点解析副本；不解决窗口交互迟钝、所有上游网络抖动或承诺把任务管理器占用降回刚启动的固定数值。
