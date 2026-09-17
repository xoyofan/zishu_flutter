# zishu_flutter × pure_live 功能对照与差距分析

> 生成日期：2026-09-13
> 参照仓库：`F:/project/pure_live`（liuchuancong/pure_live，v3.1.1）
> 本仓库：`F:/project/zishu_flutter`（当前 master `6ad7eaa`）
> 方法：对照两边**实际代码结构**（模块目录、平台实现、播放层、设置页），不依赖 README 宣传口径

---

## 0. 结论先行

| 判断 | 内容 |
|---|---|
| **现状** | zishu 已打通「浏览 → 播放 → 关注 → 搜索 → 弹幕基础」主链路；新代码规模约 **31.7k 行 / 164 文件**，pure_live **140k 行 / 645 文件** —— zishu 约为其 **1/4.4** |
| **差距在哪** | ① 平台覆盖（缺 **网易 CC**）② 播放增强（小窗弹幕 / 多画面 / 录制 / 定时 / 纯音频）③ 弹幕治理（**屏蔽、去重、相似过滤、描边、模板**全缺）④ 设置与系统集成（**5 组 vs 约 30 页**）⑤ 数据管理（历史 / 备份 / WebDAV 全缺）⑥ **播放韧性层（zishu 2 文件 vs pure_live 38 文件）** |
| **该不该补** | **不该按 pure_live 1:1 补齐**。功能与视觉验收基线是 `SFVideoLive/web`，pure_live 是**同技术栈（Flutter + media-kit）的成熟实现参考**。应按「主链路闭环 → 高频体验 → 增强」三级取舍，并明确排除平台特定与自造生态 |
| **最该先补** | **CC 平台**、**IPTV UI 接线**、**开播提醒系统通知**、**Windows 窗口/托盘/单实例**、**主题真正接线**、**弹幕屏蔽与去重**、**播放错误分类 + 有限重试** |

---

## 1. 参照定位：pure_live 扮演什么角色

项目文档（`AGENTS.md` / `docs/implementation-plan.md`）写明：

- **功能与视觉基线 = `SFVideoLive/web`**（Vue 实现，9 平台，UI 布局与交互以它为准）。
- **技术栈决议 = Flutter + media-kit 单一播放栈**，三端复用同一套 presentation / 模型 / 用例。
- `lib/legacy/` 与旧 Node server 是行为参考，不是新代码依赖。

pure_live 与 zishu **技术栈高度同构**（Flutter + media-kit + 11 平台 + 弹幕 + 多画面），已经解掉大量平台协议与播放侧踩坑。因此正确的用法是：

> **功能清单以 SFVideoLive/web 为准；pure_live 用来抄「怎么实现」（协议细节、播放韧性、弹幕管线、平台兼容性），而不是抄「有什么功能」。**

一个反例：pure_live 的「本地互动 / 体验币 / 礼物目录 / 等级风格」是它自造的生态，SFVideoLive 与 zishu 目标里都没有 —— 这类就不该跟。

---

## 2. 规模概览

| 项目 | 文件数 | 代码行数 | 说明 |
|---|---:|---:|---|
| zishu `lib/src/`（新 UI + 应用层） | 78 | 16,786 | Windows 优先，6 个 feature |
| zishu `packages/live_parser/`（纯 Dart 解析） | 86 | 14,902 | 10 平台 + cross 聚合 |
| zishu `lib/legacy/`（归档旧 Web 实现） | 42 | 5,279 | 参考用，不参与构建 |
| zishu `test/` | 44 | 10,358 | 含 `test/ui` 120 用例 |
| **pure_live `lib/`** | **645** | **140,016** | 23 个 module + 10 个 site |

**结构密度对比（差距最直观的两处）**：

| 领域 | zishu | pure_live |
|---|---|---|
| 播放层 | `lib/src/platforms/common/playback/` **2 个核心文件**（`live_player.dart` / `media_kit_live_player.dart`） | `lib/player/` **38 个文件**（player_pool / preload_player_manager / texture_keeper / source_event_fence / player_error_classifier / line_fallback_manager / background_playback_service / live_audio_service / multi_player_manager / super_resolution / shaders …） |
| 弹幕设置 | 1 个面板，**5 项**（开关 / 不透明度 / 字号 / 速度 / 显示区域） | 1 个设置页 + 屏蔽页，**约 30 项** + 观看模板 + 字体管理 |

---

## 3. 功能对照表（逐类）

### 3.1 平台覆盖

| 平台 | pure_live | zishu | 备注 |
|---|:---:|:---:|---|
| 哔哩哔哩 | ✅ | ✅ | 浏览/搜索/弹幕齐 |
| 斗鱼 | ✅ | ✅ | 含 RTMP 主线路 + 多画质多线路 |
| 虎牙 | ✅ | ✅ | 含 tars 反混淆 |
| 抖音 | ✅ | ✅ | 含 protobuf + 签名 |
| 快手 | ✅ | ✅ | 保留网页搜索 |
| **网易 CC** | ✅ | ❌ | **完全缺失（parser + UI 都没有）** |
| Twitch | ✅ | ✅ | zishu **无弹幕**实现 |
| SOOP | ✅ | ✅ | |
| YY | ✅ | ✅ | zishu **无弹幕**实现 |
| YouTube | ❌ | ✅ | **zishu 独有**（pure_live 无） |
| IPTV / M3U | ✅ 有管理页 | ⚠️ **parser 有、UI 未接线** | 路由与页面都没有 |

- zishu 平台注册表见 `packages/live_parser/lib/src/registry/site_registry.dart`：注册了斗鱼/虎牙/B站/IPTV/Twitch/YY/SOOP/快手/抖音/YouTube + cross 聚合。
- **弹幕覆盖**：zishu 有 7 家（B站/抖音/斗鱼/虎牙/快手/SOOP/YouTube），**Twitch、YY 缺**；pure_live 有 8 家（含 Twitch/YY）。
- **CC 是最硬的缺口**：SFVideoLive 9 平台里有 CC，且分类数据基础设施已按 9 平台维护。

### 3.2 播放能力

| 能力 | pure_live | zishu | 差距判断 |
|---|:---:|:---:|---|
| 多线路自动切换（断流跳下一条） | ✅ | ✅ | **已对齐**（2026-09-13 移植完成） |
| 协议白名单 / RTMP 放行 | ✅ | ✅ | 已对齐 |
| 有界低延迟缓存调参 | ✅ | ✅ | 已对齐 |
| 播放错误分类 | ✅ `player_error_classifier` | ⚠️ 部分 | 需补错误分类枚举 + 用户可读文案 |
| 有限重试 / 指数退避 | ✅ | ⚠️ 看门狗已有 | 需确认退化路径 |
| 清晰度 / 线路手动切换 | ✅ | ✅ | 控制条 selectbox |
| 全屏 / 网页全屏 / PiP | ✅ | ✅ | 三态呈现模型已提交 `943fd5f` |
| **小窗弹幕（独立队列/样式）** | ✅ | ❌ | Windows 小窗 + Android PiP + 应用内悬浮 |
| **多画面同看（双/四/一大多小）** | ✅ | ❌ | 独立 module，~11 文件 |
| **直播录制** | ✅ | ❌ | 含专用目录所有权标记 |
| **定时关闭** | ✅ | ❌ | 倒计时/自定义时长 |
| **ASMR / 纯音频模式** | ✅ | ❌ | Android 为主 |
| **DLNA 投屏** | ✅ | ❌ | |
| **超分 / 渲染器 / 解码器设置** | ✅ | ❌ | |
| **后台播放 + 系统媒体通知** | ✅ | ❌ | |
| **预加载 / 播放器池 / 纹理保活** | ✅ | ❌ | 切房秒开相关 |
| 多播放器内核切换（IJK/EXO/MPV） | ✅ | ❌ | **架构决议不跟进**（见 §4-D） |
| 窗口尺寸/位置持久化、单实例、托盘 | ✅ | ❌ | plan §6.5 已列，未做 |

> **这是最大的一块差距**。zishu 播放层只有 2 个核心文件，pure_live 是 38 个 —— 直播应用的痛点恰恰在「卡顿、断流、切房、黑屏、音画」，这部分投资回报最高。

### 3.3 弹幕

| 能力 | pure_live | zishu | 差距判断 |
|---|:---:|:---:|---|
| 渲染 + 开关 | ✅ | ✅ | |
| 字号 / 速度 / 不透明度 / 显示区域 | ✅ | ✅ | 5 项面板 |
| 房间会话隔离（切房不串弹幕） | ✅ | ✅ | `danmaku_session_provider` |
| 消息 ID 去重 / 过期队列淘汰 | ✅ | ⚠️ 部分 | 需核对全链路 |
| **关键词屏蔽** | ✅ 独立页 | ❌ | 直播场景刚需 |
| **用户屏蔽** | ✅ | ❌ | |
| **精确重复 + 相似文本两级过滤** | ✅ | ❌ | pure_live 明确定位的问题 |
| 描边 / 字重 / 字体族 | ✅ | ❌ | 含字体管理器 |
| 弹幕模板 / 观看预设（"最佳观看"） | ✅ | ❌ | |
| 刷新 FPS / 省电策略 | ✅ | ❌ | |
| 弹幕点击 / 长按操作 | ✅ | ❌ | |
| 平台原始颜色 / 统一颜色 | ✅ | ❌ | |

### 3.4 浏览与发现

| 能力 | pure_live | zishu | 差距判断 |
|---|:---:|:---:|---|
| 平台 tabs / 房间自适应网格 | ✅ | ✅ | |
| 分类索引 + 我的分类 | ✅ | ✅ | |
| 房间卡片（封面/角标/状态/标题/主播/热度/促销） | ✅ | ✅ | zishu 四象限方案 |
| 直播 / 未开播筛选 | ✅ | ✅ | 代码中已有（17 处命中） |
| 排序（综合/平台序/观众/粉丝） | ✅ | ✅ | 代码中已有（10 处命中） |
| 平台独立分页状态 | ✅ | ✅ | |
| 跨平台热门分类 | ✅ | ⚠️ 部分 | `home_view` 有，独立 popular/hot_areas 页无 |
| **标签管理（自定义 tag）** | ✅ | ❌ | |
| **播放历史** | ✅ | ❌ | `history` 关键词在 lib/src **0 命中** |
| **平台屏蔽 / 隐藏平台 / 平台排序** | ✅ | ❌ | `屏蔽` 在 lib/src **0 命中** |
| 房间卡片自定义（密度/字段/渲染器） | ✅ 独立设置页 | ❌ | |

### 3.5 搜索

| 能力 | pure_live | zishu | 差距判断 |
|---|:---:|:---:|---|
| 跨平台搜索 | ✅ | ✅ | |
| 平台分页状态 / 渐进显示 | ✅ | ⚠️ | 需核对超时隔离 |
| 房间号 / 完整 URL 直达 | ✅ | ✅ | `search_direct_tile` |
| 排序 / 直播状态筛选 | ✅ | ⚠️ | |
| **最近访问 / 历史搜索** | ✅ | ❌ | plan §6.4-F 标注「后续补充」 |

### 3.6 关注与账号

| 能力 | pure_live | zishu | 差距判断 |
|---|:---:|:---:|---|
| 三密度（卡片/Tile/Row） | ✅ | ✅ | |
| 平台筛选 / 开播排序 | ✅ | ✅ | |
| 特别关注 / 单条提醒开关 | ✅ | ✅ | 模型已有 |
| 批量删除 / 批量开关提醒 | ✅ | ✅ | `removeMany` / `setAllRemind` |
| **批量导入（文件/URL）** | ✅ | ❌ | `导入` 在 lib/src **0 命中** |
| **开播提醒系统通知** | ✅ Windows 通知 | ⚠️ **只存开关，无通知投递** | 有 `remindOn` 字段但无通知链路 |
| 云同步 | ✅ backup + WebDAV | ⚠️ data-server 登录同步关注 | |
| 单实例 / 关注恢复 / 换盘迁移 | ✅ 有专门文档 | ❌ | |

### 3.7 设置与系统集成

| 分组 | pure_live | zishu |
|---|---|---|
| 设置页规模 | **约 30 个设置页** | **1 页 4 组**（外观 / 播放 / 服务器 / 账号） |
| 主题 | ✅ 完整主题引擎 | ⚠️ 仅保存偏好，注释写「全局主题接线由后续任务完成」 |
| 网络代理 | ✅ 独立页 | ❌ |
| 数据备份 / 恢复 / 移动端互传 | ✅ 8 文件 | ❌ |
| WebDAV 云存储 | ✅ 6 文件 | ❌ |
| 字体管理 | ✅ | ❌ |
| 解码器 / 渲染器 / 播放器内核 | ✅ | ❌ |
| 导航设置 / 页面设置 / 加载样式 | ✅ | ❌ |
| 观众口径 / 排行口径设置 | ✅ | ❌ |
| IPTV 源管理 | ✅ | ❌（parser 有） |
| 自动更新 | ✅ | ❌ |
| 高刷适配 | ✅（Android） | ❌ |
| 日志 / 缓存清理 | ✅ | ❌ |

---

## 4. 差异分级与建议

### P0 — 主链路闭环（不做则产品不成立，建议立即排期）

| # | 项 | 理由 | 工作量级 |
|---|---|---|---|
| 1 | **补网易 CC 平台** | SFVideoLive 9 平台中的缺口；分类基础设施已按 9 平台维护，缺 1 家会导致数据与导航不一致 | parser 新增 1 站（browse/search/room/danmaku/normalize）+ UI 注册 |
| 2 | **IPTV UI 接线** | parser 已实现 `iptv_site` / `playlist` / `channel_repository`，UI 层 0 引用 —— 有引擎无驾驶舱 | 中（1 页 + 源管理） |
| 3 | **播放错误分类 + 有限重试收敛** | 直播最大痛点；pure_live 用 `player_error_classifier` + `engine_fallback_manager` 系统化处理 | 中（新增错误枚举 + 重试策略 + 文案） |
| 4 | **开播提醒系统通知（Windows）** | 关注功能的「闭环最后一公里」，现在只有开关没有投递 | 小-中（本地通知 + 轮询/调度） |
| 5 | **窗口状态持久化 + 单实例 + 托盘** | plan §6.5 明确列为 Windows 产品闭环项 | 小-中 |
| 6 | **主题真正接线** | 设置页已有「主题模式」但仅存偏好；纯视觉割裂 | 小 |

### P1 — 高频体验（决定"好不好用"，且三端共用，建议 M4 内完成）

| # | 项 | 理由 |
|---|---|---|
| 7 | **弹幕屏蔽（关键词 + 用户）** | 直播弹幕刚需；缺屏蔽 = 不可用级体验 |
| 8 | **弹幕去重 + 相似文本过滤** | pure_live 专门解决的问题（串房/重复/积压补跳） |
| 9 | **播放历史 + 最近访问 / 搜索历史** | 高频回访入口，纯增量 |
| 10 | **平台屏蔽 / 隐藏 / 排序** | 与正在做的「分类数据 single-source-of-truth」直接相关 |
| 11 | **小窗弹幕（PiP 独立队列）** | `pip_surface` 已有舞台，扩展弹幕层即可 |
| 12 | **弹幕样式扩充（描边 / 字重 / 模板）** | 视觉成熟度；pure_live 有「最佳观看」预设可抄 |
| 13 | **批量导入关注（文件 / URL）** | 迁移期用户刚需 |

### P2 — 增强（按里程碑取舍，不必现在做）

| # | 项 | 取舍意见 |
|---|---|---|
| 14 | 多画面同看（双/四/一大多小） | 复杂度高（独立 module ~11 文件 + 多播放器管理），建议 M6 之后评估；**注意**：zishu 的 `play_room_grid` 是「推荐房间网格」，不是 multiview，别混淆 |
| 15 | 直播录制 | 有价值但涉及存储/权限/清理策略，建议 M5 后 |
| 16 | 定时关闭 | 小而完整，可随手做 |
| 17 | 纯音频 / ASMR 保活 | Android 为主，等 Android 阶段 |
| 18 | 数据备份 / WebDAV | 云同步可先用既定 data-server 方案替代 |
| 19 | 网络代理设置 | 海外平台（Twitch）场景需要，可后置 |
| 20 | 字体管理 / 房间卡片自定义 / 超分 / 渲染器 | 长尾定制，ROI 低 |

### 不建议补（明确排除 + 理由）

| 项 | 排除理由 |
|---|---|
| **多播放器内核切换（IJK / EXO / MPV）** | 架构决议是「三端统一 media-kit 单一播放栈」（plan §7.0）。pure_live 做多内核是为解 Android 硬解兼容 —— 等到 Android 真出现兼容问题再定向引入，不要提前三端铺开 |
| **本地互动 / 体验币 / 礼物目录 / 等级风格** | pure_live 自造生态，SFVideoLive 与 zishu 目标都没有。不跟 |
| **Android 专属项**（系统 PiP / 高刷适配 / 投屏 DLNA / 后台音频保活） | 当前优先级 Windows > Web > Android，等 Android 阶段再对齐 |
| **YouTube 平台** | zishu 独有，pure_live 无。**建议保留但确认是否纳入验收范围**（涉及代理与合规） |
| **pure_live 的 i18n / 主题引擎全量移植** | zishu 走自己的 `design_tokens` / `zishu_tokens` 体系，只取需要的能力 |

---

## 5. 落地建议（结合当前里程碑）

当前处于 **M4（关注与完整导航）收尾 → M5（Dart streaming-server + Flutter Web）前置**。

建议顺序：

1. **先 P0-3 / P0-4 / P0-5 / P0-6**（播放韧性收敛 + 通知 + Windows 系统集成 + 主题）—— 都是「补已经开了半扇的门」，成本低、体感强，且不阻塞后续。
2. **再 P1-7 / P1-8**（弹幕屏蔽 + 去重）—— 与已有 `danmaku_session_provider` 同层扩展，不引入新架构。
3. **P0-1 CC 平台** 与 **P0-2 IPTV 接线** 属于解析轨 + UI 轨交汇，建议单独立卡、双轨并进（CC 的 parser 可参考 pure_live `lib/core/site/cc` 与 `lib/core/danmaku`）。
4. **P2 全部**留到 M5/M6 之后按需触发，避免拖慢 Web 端交付。

**关键提醒**：pure_live 可直接复用的「实现方案」优先级排序 ——
① 播放韧性（`player_error_classifier` / `line_fallback_manager` / `source_event_fence`）
② 弹幕治理管线（`repeated_danmaku_filter` / `danmaku_similarity_filter` / `danmaku_message_gate`）
③ 平台协议补充（CC）
④ 房间卡片渲染器与设置
这四块的**代码注释质量与踩坑密度**是 pure_live 最值钱的部分，比功能列表更值得读。

---

## 6. 需要用户裁决的点

| # | 问题 | 备选 |
|---|---|---|
| 1 | **YouTube 是否保留并在验收范围内？** | 保留（独有优势，但需代理+合规）／移除（对齐 SFVideoLive 9 平台口径） |
| 2 | **CC 平台是否本轮补？** | 本轮补（补齐 9 平台口径）／下轮（先做播放韧性） |
| 3 | **多画面同看是否纳入路线图？** | 纳入 P2（M6 后评估）／明确不做 |
| 4 | **录制 / 定时 / 纯音频** 三项是否纳入 Windows 目标？ | 全部纳入／仅定时／都不做 |
| 5 | **数据备份走 WebDAV 还是既有 data-server 云同步？** | data-server（已接入，架构统一）／WebDAV（对齐 pure_live） |

---

## 7. 播放层对照审计结论（2026-09-18 实测，3 路并行只读审计）

> 参照锁定：**上游 `upstream/master` 的 `lib/player/`（43 文件）**。
> 注意：`F:/project/pure_live` 的本地分支 `ui/zishu-flutter` 是「zishu 风格重写快照」（旧 UI 已删、`lib/player/` 已不在），**不能当 pure_live 的播放实现参照**。

### 7.1 上游那批"成熟播放层"大多是死代码（0 调用点）

逐符号 grep 结果——以下符号在上游全仓**只有定义、无任何调用点**，**不要移植**：

`PlayerPool`、`PreloadPlayerManager`、`TextureKeeper`、`LiveStreamGeometryHintResolver`、`calculateVideoOutputSize`、`SourceEventFence`、`PlaybackLifecycleCoordinator`、`LiveBufferPolicy`。

上游真正接线的韧性命中路径只有：`media_kit_adapter.dart:635-719`（粗糙 `_mapErrorType`）→ `player_manager.dart:1701-1775`（切线路/换内核）→ `video_controller.dart:616-648`（Toast，2s 同签名去重）。

**结论：zishu 的播放韧性整体强于上游**——错误分类器带 `terminal` 终局判定、有界重试带 10s 健康窗（防抖动清零）、恢复重解析 40s 节流、mpv 调优还多出 Windows `ao=wasapi` + `video-sync=audio`。「把 pure_live 播放层搬过来」是伪命题。

### 7.2 本轮补齐（4 轨并行 → worktree 隔离 → cherry-pick）

| 轨 | 内容 | commit |
|---|---|---|
| A 播放韧性内核加固 | 切房生命周期串行队列 + 源代际与事件围栏（修「切房黑屏/无声且日志无错」竞态）、看门狗重挂（洞 R4）、`completed` 补退避（R8）、放弃闩锁（R3）、`stop` 重置、缓存目录路径、新增 PlaybackLog 事件 | `d09a701` |
| B 解析域请求头 | 补 huya/bilibili/youtube/yy/soop 的 `StreamLine.headers` + 头值卫生化工具（斗鱼/抖音/快手已有） | `9b8ec04` |
| C 窗口/PiP 几何记忆 | PiP 尺寸分档（360/380/280）、PiP 位置记忆（横竖两套）、主窗口几何持久化（debounce 500ms + 退出 flush） | `d0a6106` |
| D 房间音量 + 睡眠定时 | 房间独立音量记忆 + 全局静音/默认音量、恢复回调注销（`setLineRecovery(null)` + `ref.mounted`）、睡眠定时（app 级） | `9fcc414` |

验证：`flutter analyze` 0 issue；`flutter test` **330 passed**；`live_parser` `dart analyze` 0 issue + `dart test` **270 passed**；`flutter build windows --debug` 成功。

### 7.3 明确排除（勿再评估）

多播放器内核（IJK/EXO/video_player）、`PlayerPool`/`TextureKeeper`/`PreloadPlayerManager`、`calculateVideoOutputSize`、线路黑名单状态机（上游 `markSuccess` 无调用点 = 一次失败永久拉黑）、Android 前台服务/系统 PiP/方向锁/audio_session、MPRIS、RTX VSR、`customPlayerOutput`、录制（独立大域）、GetX/Hive 基建（只搬语义不搬基建）。

### 7.4 待办 / 需产品决策

1. **后台播放 + 系统媒体通知（SMTC）**：会破坏「离页即停」契约（`play_provider.dart` 的 `ref.onDispose(player.stop())` 是注释级契约，`play_controls_test.dart` 有用例锚定），且 `audio_service` 不支持 Web（违反三端单一依赖图）→ 需产品决策 + 平台分层立项。
2. **睡眠定时/全局静音/默认音量的设置页入口**：本轮只落了状态层（`settings_view.dart` 未改），UI 入口待补。
3. 抖音流几何提示、竖屏三模式、缓存策略 UI、多画面同看、录制。
4. 真机验证：切房不再黑屏、huya/bilibili 补头后开流、PiP 记忆、房间音量、睡眠定时到点停止（可用 `%APPDATA%\zishu_flutter\logs\playback.log` 的 `reopen_requested`/`stall_watchdog`/`give_up_latched`/`open_superseded` 事件观测）。
