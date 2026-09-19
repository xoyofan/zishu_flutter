# Windows 闭环交付设计

**日期：** 2026-09-20
**状态：** 已确认设计，待据此编写实施计划
**目标平台：** Windows
**项目：** zishu_flutter

## 1. 背景与问题

当前项目已经具备较完整的 Flutter UI、`media-kit` 播放器、纯 Dart `live_parser`、关注同步、弹幕、主题和响应式壳层，但工程记录仍混有早期 TODO，且 Windows 真实解析模式的长时间播放、冷启动、播放控制和跨平台数据链路尚未以一套统一的验收标准收口。

本阶段不再以新增页面或继续大规模视觉复刻为主要目标，而是将已有能力收敛为一个可交付的 Windows 产品闭环：客户端在不依赖远程 Node `streaming-server` 的情况下，能够完成真实浏览、分类、搜索、进入直播间、播放、弹幕、切换线路/画质、断流恢复、关注和设置流程。

## 2. 目标

### 2.1 主要目标

1. Windows 使用 `--dart-define=ZISHU_REAL_PARSER=true` 时，首页、分类、搜索和播放均消费 `packages/live_parser` 的真实数据。
2. 斗鱼、虎牙至少完成一次可重复的长时间真实播放验收。
3. 播放器的线路选择、画质选择、播放失败恢复、重新解析和播放日志在真实 Windows 进程中可观察、可诊断。
4. 全屏、网页全屏、画中画、快捷键、沉浸态侧栏和返回行为形成稳定闭环。
5. 冷启动、窗口几何恢复和首帧呈现不依赖用户额外 resize 或点击来“救活”。
6. 自动化门禁、真机验收记录和项目 TODO 状态一致，后续 Web/Android 工作可以在可信基线之上展开。

### 2.2 成功标准

Windows 阶段只有同时满足以下条件才视为完成：

- `flutter analyze` 通过；
- `flutter test` 通过；
- `packages/live_parser` 的 `dart analyze` 通过；
- `packages/live_parser` 的 `dart test` 通过；
- Windows debug 构建通过；
- Windows release 真实解析构建通过；
- 首页、分类、搜索、播放、弹幕、关注和设置真实链路可用；
- 斗鱼和虎牙各完成至少 10 分钟长播验证；
- 启动后首帧可见，窗口恢复不产生白屏；
- 播放控制与返回行为通过真机验收；
- 验收结果已回写 `todo.md`/`tasks.md`，UI、解析和文档提交边界清晰。

## 3. 架构原则

### 3.1 Windows 调用路径

```text
Flutter UI
  -> shared application/use case
  -> DirectLiveParserGateway
  -> package:live_parser
  -> platform upstream API
```

Windows 不通过旧 Node server 取得解析结果。`lib/legacy/` 只作为参考和回归代码，不得成为新功能依赖。

### 3.2 分层边界

```text
features
  -> shared/domain + shared/application
platforms/windows
  -> shared ports + live_parser + Windows APIs
platforms/common/playback
  -> LivePlayer + media-kit/window presentation
live_parser
  -X-> Flutter / Widget / media-kit / dart:ui / Web JS interop
```

播放器、窗口、文件日志和平台 API 保持在 `lib/src/platforms/`；站点解析、协议模型和解析契约保持在 `packages/live_parser/`。UI 不直接依赖站点实现类。

### 3.3 单一真源

- 站点解析：`packages/live_parser`；
- 播放选择与恢复编排：`features/play/application`；
- 窗口全屏/PiP：`WindowPresentation`；
- 播放状态：`playScreenProvider`、`playProvider`；
- 关注排序和可见性：`follow_sort.dart`；
- 分类展示映射：`category_display.dart` 与 parser catalog；
- 播放诊断：`playback.log`。

不为 Windows、Web、Android 分别复制解析源码或播放策略。

## 4. 范围

### 4.1 本阶段包含

#### A. 工程基线和状态收口

- 保护并核对已有未提交改动；
- 建立当前 HEAD 的 app/parser/Windows 构建基线；
- 清理 TODO 中已经完成或已被裁决取消的事项；
- 标记本地截图、探针脚本和 parser 构建目录等非产品产物；
- 处理 `docs/ui-compare/baseline/` 中已经确认的 404 错误页，避免把无效图片作为视觉基线。

#### B. 真实 Windows 数据闭环

- 真实解析开关生效；
- 首页真实房间列表；
- 平台和分类浏览；
- 全平台分类 key 与路由过滤；
- 搜索和房间直达；
- 进入真实播放页；
- 播放页返回、切房和路由栈语义正确。

#### C. 播放器和恢复

- 斗鱼 FLV/HLS 线路选择符合线路格式偏好；
- 播放请求头正确；
- 多线路 playlist 自动回退；
- 全组线路耗尽或冻结时触发恢复；
- 签名平台重新解析获取新地址；
- 错误分类和终局提示可理解；
- `playback.log` 记录 open、reopen、recover、playing 和 give_up 事件。

#### D. 弹幕和侧栏

- 斗鱼、虎牙、Bilibili 已支持能力的真实连接；
- 聊天侧栏和飘屏 overlay 共用正确会话；
- 切房不串房；
- 设置项真正影响 overlay 和聊天；
- 粉丝牌、等级和平台徽章在已有契约范围内稳定显示。

#### E. Windows 交互

- 播放/暂停、刷新、静音、音量、画质和线路；
- `F`、`W`、`M`、`Space`、`Esc`；
- 网页全屏、系统全屏、PiP；
- 沉浸态右缘侧栏热区；
- Alt+左和鼠标侧键返回；
- 控制条淡出、唤醒和焦点恢复。

#### F. 冷启动和窗口呈现

- `runApp` 前恢复 Windows 几何；
- 首帧前窗口保持隐藏；
- 全屏切换使用防闪窗保护；
- 首次显示不依赖 resize；
- 使用 `PrintWindow(PW_RENDERFULLCONTENT)` 验证窗口表面。

### 4.2 本阶段不包含

以下内容不阻塞 Windows 闭环：

- Android 产品适配；
- 完整 Dart `streaming-server`；
- 搜索协议最终的 `type=anchors|rooms` parser 分流；
- 关注批量导入；
- 后台开播提醒和系统通知；
- 移动端目录抽屉；
- 全套徽章图片、超粉 V、guard/wealth 等缺少契约字段的高级能力；
- 遗留 Pi worktree 的删除和分支清理；
- 不属于 Web 对齐差距的弹幕屏蔽词/屏蔽用户功能；
- 以旧文档为依据将房卡平台 badge 移到右下的改动。

这些项目如需实施，另立设计和计划，不与 Windows 闭环混合。

## 5. 组件和责任边界

| 组件 | 责任 | 本阶段关注点 |
|---|---|---|
| `lib/src/shared/application/parser_sources.dart` | 解析 gateway 和来源装配 | 真实解析开关、能力过滤、错误边界 |
| `lib/src/features/browse/` | 首页、分类、房间列表 | 真实数据、分类路由、空态和返回 |
| `lib/src/features/search/` | 搜索与直达 | 当前 UI 语义稳定，协议分流另立项 |
| `lib/src/features/play/application/play_provider.dart` | 解析、选择、恢复和播放状态编排 | 新地址、线路格式、恢复节流、代际隔离 |
| `lib/src/platforms/common/playback/` | `LivePlayer`、media-kit、日志、窗口呈现 | mpv 事件、playlist、全屏/PiP、诊断 |
| `lib/src/features/play/widgets/` | 舞台、控制条、侧栏、弹幕入口 | 真机交互和焦点行为 |
| `lib/src/features/follow/` | 关注、云同步、状态刷新和视图 | 真实在播状态、离线展示、持久化 |
| `lib/src/apps/windows/windows_app.dart` | Windows composition root 和生命周期 | 主题、窗口几何、预热、全局返回 |
| `lib/src/platforms/windows/` | Windows 原生适配 | 防闪窗、几何恢复、冷启动 |
| `packages/live_parser/` | 站点模型、解析、弹幕、摘要刷新 | 真实链路、契约完整性、平台隔离 |
| `docs/`、`todo.md`、`tasks.md` | 规范、计划、验收记录 | 状态与实际代码一致 |

## 6. 验收矩阵

### 6.1 自动化门禁

每次修改至少按所属轨道运行局部测试；阶段收尾运行完整门禁：

```powershell
flutter analyze
flutter test
flutter build windows --debug -t lib/main.dart

cd packages/live_parser
dart analyze
dart test
```

真实解析 release 构建：

```powershell
flutter build windows --release `
  --dart-define=ZISHU_REAL_PARSER=true
```

测试结果必须记录通过数、失败数、跳过数和已知网络基准告警，不能只记录“通过”。

### 6.2 首页/分类/搜索

| 场景 | 预期 |
|---|---|
| 真实解析启动 | 不显示固定 fixture 首页作为主数据 |
| 平台切换 | 只展示平台声明支持的入口 |
| 全平台分类 | 25 个 web HOT key 顺序和名称稳定 |
| 分类深链 | 无效 key 不静默退化为全平台混排 |
| 分类收藏 | 分类页和播放页星标状态一致 |
| 搜索 | 结果可进入房间，单站失败不阻断聚合 |
| 房间直达 | 房间号和完整 URL 可进入播放页 |
| 返回 | 返回到合理的浏览页，不抛 `GoError` |

### 6.3 真实播放

| 场景 | 预期 |
|---|---|
| 斗鱼首次播放 | 优先使用稳定 FLV/符合偏好的线路，带播放请求头 |
| 多线路失败 | mpv playlist 自动尝试同画质备用线路 |
| 线路组耗尽 | 触发重新解析或明确终局错误 |
| 虎牙地址过期 | 走恢复解析获取新签名地址，不反复使用旧 URL |
| 切画质/切线路 | 播放状态和选中项同步，旧会话被释放 |
| 播放日志 | 能区分 open/reopen/recover/playing/give_up |
| 长播 | 斗鱼、虎牙至少各 10 分钟无周期性黑屏或无休止重试 |

### 6.4 弹幕和关注

| 场景 | 预期 |
|---|---|
| 弹幕连接 | 支持的平台能显示聊天和飘屏 |
| 切房 | 旧会话关闭，新房间消息不串入 |
| 重连 | 不因协议重推造成明显重复刷屏 |
| 关注操作 | 侧栏操作持久化并可在关注页看到 |
| 状态刷新 | 在播/离线状态更新，失败保留旧值 |
| 离线卡 | 显示上次开播时间或“未开播” |
| 主题 | 深浅主题切换后背景、文字、播放侧栏均同步 |

### 6.5 Windows 交互和呈现

| 场景 | 预期 |
|---|---|
| 冷启动 | 窗口出现即有有效首帧，不需要 resize |
| 几何恢复 | 窗口尺寸和位置可恢复，失败时安全回退 |
| 系统全屏 | 不出现明显露底/标题栏闪烁 |
| 网页全屏 | 隐藏壳层但不错误改变系统窗口状态 |
| PiP | 进入/退出后窗口尺寸和置顶状态正确恢复 |
| 控制条 | 淡出后不可误触，移动鼠标可唤醒 |
| 快捷键 | `F/W/M/Space/Esc` 按焦点和优先级只处理一次 |
| 返回 | Alt+左、鼠标侧键和左上返回按钮语义一致 |
| 沉浸侧栏 | 右缘热区打开，背景遮罩可关闭，退出沉浸自动卸载 |

## 7. 失败处理策略

### 7.1 分级

1. **P0 阻塞问题**：无法启动、白屏、无法进入房间、无法播放、崩溃、持续错误重试。必须优先修复。
2. **P1 核心链路问题**：选错线路/画质、弹幕串房、关注状态错误、分类错误、真实数据回退成 fixture。Windows 发布前必须修复。
3. **P2 视觉问题**：间距、字体、badge 细节、golden 差异。只在不影响交互和可读性的前提下处理。
4. **P3 增强需求**：前进栈、后台提醒、批量导入、平台扩展。留到下一阶段。

### 7.2 真实网络测试原则

- 在线 smoke 只证明当前上游可用，不替代离线单测；
- 网络失败必须按平台/条目隔离，不能让一个站点阻断聚合首页；
- 性能基准在整机并发下允许告警，但不能吞掉功能测试异常；
- 长播验收同时看画面和 `%APPDATA%\\zishu_flutter\\logs\\playback.log`；
- 真机截图使用窗口表面抓取，避免宿主桌面遮挡造成误判。

## 8. 提交和分支策略

按照项目约定保持轨道隔离：

- UI 变更：单独 UI commit；
- `packages/live_parser/**`：单独解析 commit；
- Windows 原生适配：单独平台 commit；
- `docs/`、`todo.md`、`tasks.md`：单独文档 commit；
- 不提交 `build/`、临时 PNG、临时探针脚本和包含凭据的日志；
- 当前已有未提交业务改动不得被本阶段基线或清理操作覆盖；
- 遗留 worktree 不以 `ahead=0` 作为删除依据，清理另立任务。

本设计文档本身作为独立文档提交。实施阶段需要先依据本设计编写任务级实施计划，再按任务逐项执行。

## 9. 后续阶段顺序

Windows 闭环完成后，按以下顺序推进：

1. `DanmakuMessage.id` 与 Huya/Bilibili 精确去重；
2. Fixture 分类数据保真；
3. SOOP/YY/Kuaishou 轻量状态刷新；
4. 搜索 `type=anchors|rooms` 契约分流；
5. `packages/live_server` 最小 HTTP API；
6. Flutter Web gateway 与 Web 构建；
7. Android 生命周期、网络和 media-kit 适配。

这些后续项目不能反向破坏 Windows 的直接 parser 路径。
