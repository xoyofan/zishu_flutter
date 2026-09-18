# zishu_flutter 对齐 SFVideoLive Web 实施计划（2 小时长任务）

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans 按任务逐条实施本计划。
> 两阶段审查用 superpowers:requesting-code-review；收尾用 superpowers:finishing-a-development-branch。

**Goal:** 在 2 小时窗口内，把 zishu_flutter 与参考实现 `F:\project\SFVideoLive\apps\web` 在**界面形态**与**业务逻辑**两个维度上再推进一批已核实、文件隔离、可验收的差距项，做到 analyze 0 issue / 测试全绿 / golden 同步 / 真机截图复验。

**Architecture:** 全部改动落在既有的分层里 —— UI 改 `lib/src/features/*/widgets|views`，逻辑改 `lib/src/features/*/application` 与 `lib/src/shared/application`，解析改 `packages/live_parser`（纯 Dart，禁 Flutter 依赖）。每个任务**独占文件**，在**同一棵工作树**内并行推进、各自立即提交；共享资源（golden PNG、`todo.md`）只在收尾波次由单一执行者触碰。

**Tech Stack:** Flutter 3.x + Riverpod + go_router + media-kit；解析核心为纯 Dart package `live_parser`；参考实现为 Vue 3 + Element Plus。

---

## 0. 前提纠错（本轮调研推翻的三条过期认知）

> 这三条如果不先纠正，会照着一份过期看板做出**主动回归**。务必先读。

| # | 过期认知 | 真相（已用真源核实） | 影响 |
|---|---|---|---|
| 1 | `tasks-ui-refine.md` T3：「房卡平台 badge 应放**右下**」 | **错**。web 真源 `components/browse/CoverBadges.vue:100-157` + `room/RoomCard.vue:24-61`：平台在 `left:0;bottom:0`（**左下**），热点在 `right:0;bottom:0`（右下），促销在右上，分类在左上。flutter `room_card.dart:185-221` **已对齐**。 | **T3 作废，不得执行** |
| 2 | 上一轮 todo.md：「`/time` 是时间线」 | web `views/TimeView.vue` 是**解析耗时基准页**；web **不存在**「时间线」页。flutter `/time` 已对齐，`/timeline` 是 flutter **超集**（web 无）。 | 不列为差距 |
| 3 | 上一轮 todo.md backlog：「补弹幕屏蔽词/屏蔽用户」 | **不是差距**。`apps/web/src` 全仓检索「屏蔽」为空 —— web 侧同样没有该功能。 | 从 backlog 移除 |

另：`tasks-ui-refine.md` 的 T1（error 色 / 动效时长）与 T2（抽屉 rail 宽度）**我实测仍未落地**（`design_tokens.dart` 仍是 `F56C6C` / 120ms / 200ms / `railWidth = 52`），这两条有效，纳入本轮。

## 0.1 已确认**无需动**的项（避免重复劳动）

- 房卡四象限：flutter 已对齐（差异仅在促销徽章位置 —— flutter 依**用户明确口径**把促销 chip 移到封面下方第二行，见 `room_card.dart:198-200` 注释，**不要改回**）。
- 主播主页：flutter **存在** `features/anchor/views/anchor_view.dart` 且比 web 多「相关直播」。
- 播放页侧栏四 Tab（聊天/关注/推荐/设置）：已对齐。
- 顶栏 44px / 底栏 56px / 抽屉 220px / 断点数值 / 直播中绿 `#32C874` / 播放页 follow·super 色：全部已对齐。
- 线路格式偏好、多线路回退、断流恢复、推荐跨平台聚合：已对齐。

---

## 1. 执行环境与约束（**必读，否则命令全失败**）

### 1.1 沙箱搬运器（bash 直调 flutter 会挂）

```bash
PY=C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe
WS=C:/Users/Administrator/WorkBuddy/2026-09-18-10-56-54
ROOT=F:/project/zishu_flutter

# App 侧（analyze / test / build）
$PY $WS/_frun.py $ROOT analyze --no-pub
$PY $WS/_frun.py $ROOT test test/ui/workflows/room_card_badges_test.dart --no-pub --reporter compact

# parser 侧（analyze / test / dart run）
$PY $WS/_dartrun.py $ROOT/packages/live_parser analyze
$PY $WS/_dartrun.py $ROOT/packages/live_parser test --reporter compact

# 收尾一键门禁（golden 重生成 → 全量 test → analyze → parser）
$PY $WS/_gate.py $ROOT --goldens
```

详细日志落 `$ROOT/tool/_gate_*.log`。`git` 一律用 python `subprocess` 驱动（bash 内 git 在本环境会卡死）。

### 1.2 并发与隔离策略（**本计划的明确裁决**）

- **不建 git worktree。** 理由：pi agent 遗留的 13 个 worktree 已全部被吸收却仍挂在 `git worktree list` 里，且历史上两次因 worktree 中断留下散落文件。本轮任务**文件完全互斥**，同树并行即可，恢复成本更低。
- **并发上限 2~3 个写轨。** 上一个子代理因 **429 频率限制**中途死亡（配额 16:01 UTC+8 重置）。若开跑时间早于 16:01，必须降到 **2 个并发**；每个任务**做完立即 commit**，保证中途死亡不丢工作。
- **文件归属矩阵（冲突红线）**：见 §5。命中同一文件的两个任务**不得**同时进行。

### 1.3 推送配方（已验证）

```python
# GCM 取 token -> 嵌入一次性 URL -> 推完补写 origin ref
r = subprocess.run(['git','credential-manager','get'],
                   input=b'protocol=https\nhost=github.com\n\n', capture_output=True)
# 取 password= 行；然后：
# git -c credential.helper= push https://trianglestrip:<TOKEN>@github.com/trianglestrip/zishu_flutter.git master:master
# 禁止把 token 写入任何仓库文件或输出
```

---

## Wave 0：预检（执行者本人，约 5 分钟）

**Task 0.1 清理 13 个已吸收的遗留 worktree**

已核实：全部 `ahead=0`（内容已在 master）；`pi-subagents/shell-mobile-align-*` 的 3 个文件与 master `7c31ffc` **逐字节相同**（`git diff 7c31ffc 3f82198 -- lib/src/app/app_shell.dart test/ui/workflows/shell_mobile_align_test.dart test/ui/workflows/hover_flyout_layout_test.dart` 输出为空）。

- 操作：对 `F:/project/worktrees/zishu_flutter/*` 逐个 `git worktree remove --force`，再 `git worktree prune` + `git branch -D <已吸收分支>`。
- **安全门**：执行前对每个分支再跑一次 `git rev-list --count master..<branch>`，非 0 即跳过并在报告里点名。
- 验收：`git worktree list` 只剩主工作树；`git status --porcelain` 为空。

**Task 0.2 记录基线**

```bash
$PY $WS/_gate.py $ROOT
```
- 期望基线：app test **472 passed / 0 failed**、app analyze **0 issue**、parser test **290 passed / 10 skipped**、parser analyze 0 issue。
- 数字不符则**先报告再继续**，不要带着未知偏移开工。

---

## Wave 1：4 条并行轨（文件互斥，约 40 分钟）

### T1 — 房卡补 LIVE/录播角标 + 离线遮罩

**Files:**
- Modify: `lib/src/features/browse/widgets/room_card.dart`（`_Cover`，当前 159-226 行，只渲染「左上分类 / 右下热度 / 左下平台」）
- Modify: `lib/src/shared/presentation/widgets/cover_badges.dart`（新增角标组件；现有 `CoverCategoryBadge` / `CoverPlatformBadge` / `CoverOnlineBadge` / `CoverPromoBadge`，**无 LIVE/录播**）
- Test: `test/ui/workflows/room_card_badges_test.dart`

**参考真源：** `apps/web/src/components/browse/room/RoomCard.vue:49-61`
```html
<el-tag v-if="liveBadge" class="room-card__badge room-card__badge--live" size="small" type="danger" effect="dark">LIVE</el-tag>
<el-tag v-else-if="replayBadge" class="room-card__badge room-card__badge--replay" ... type="warning">录播</el-tag>
<div v-if="room.status === false" class="room-card__offline">
  <span>{{ offlineOverlayText }}</span>   <!-- offlineLastLiveLabel(room) || "未开播" -->
</div>
```
CSS：live/replay 角标 `top:0; left:0; border-radius: 0 0 8px 0`（**与分类同角，二者互斥：有 LIVE 就不显分类**）；离线遮罩 `position:absolute; inset:0; background: rgba(0,0,0,.72); color:#fff; font-size:13px; z-index:2`。

**Step 1** 先在 `room_card_badges_test.dart` 写失败用例：
- `离线房间('未开播'状态) 渲染 room-card-offline 遮罩且文案为「未开播」`
- `直播中房间(status==true 且 hideLiveFrame==false) 左上渲染 cover-badge-live`
- `LIVE 角标存在时 不渲染 cover-badge-category`（互斥）

**Step 2** 跑测确认失败（组件/Key 不存在 → 失败）。

**Step 3** 实现：`cover_badges.dart` 新增 `CoverLiveBadge`（红底 `context.tokens` 里取直播危险色，直角贴角，Key 由调用方传）；`room_card.dart` 的 `_Cover` 增加：
- 左上：`_liveBadge ? CoverLiveBadge : CoverCategoryBadge`（`room.online.trim().isNotEmpty` 视为在播，与现有 `live` 判据保持同一来源，**不要新造第二套判据**）
- 全封面：`room.online.isEmpty` 时叠半透明遮罩 + 「未开播」文案（Key `room-card-offline`）。**暂不接「上次开播 X」**——那是 T4 的职责，T4 落地后由 T4 补文案。

**Step 4** 跑测确认通过。**Step 5** commit：`feat(browse): 房卡补 LIVE/录播角标与离线遮罩(对齐 web RoomCard)`

**验收**：`$PY $WS/_frun.py $ROOT test test/ui/workflows/room_card_badges_test.dart test/ui/workflows/room_card_meta_height_test.dart --no-pub` 全绿；`analyze` 0 issue。

---

### T2 — 搜索对话框补「主播 / 房间」双 Tab

**Files:**
- Modify: `lib/src/features/search/views/search_view.dart`（321 行；当前**无任何** `TabBar`/`TabController`）
- Test: `test/ui/workflows/search_dialog_test.dart`

**参考真源：** `apps/web/src/components/browse/SearchDialog.vue:14-54` —— `el-tabs` 两个 pane（主播 / 房间）；**只有**房间 Tab 的结果行才显示「进入直播间」按钮。

**Step 1** 写失败用例：
- `搜索页存在 主播/房间 两个 tab（Key: search-tab-anchor / search-tab-room）`
- `切到 主播 tab 时 房间结果行不渲染 进入直播间 按钮`
- `切到 房间 tab 时 在播房间行 渲染 进入直播间 按钮`

**Step 2** 确认失败。

**Step 3** 实现：在输入框下方加 `TabBar`（沿用 `context.tokens` 配色，勿引裸色）。数据层**已具备**分流能力：`search.hits` 每条含主播与房间信息、`search.direct` 是直达、`_openDirect` 已存在（56-57、205-222 行）。按 tab 过滤既有 `hits` 即可，**不要新增 network 调用**。直达卡片保持**两个 tab 都显示**（web 亦如此）。

**Step 4** 跑测通过。**Step 5** commit：`feat(search): 搜索对话框补 主播/房间 双 Tab(对齐 web SearchDialog)`

**验收**：`search_dialog_test.dart` + `search_test.dart` + `navigation_test.dart` 全绿。

---

### T3 — 离线关注卡接上「上次开播」链路（逻辑，本轮最高性价比）

**Files:**
- Modify: `lib/src/features/follow/application/follow_provider.dart`（`FollowEntry` 在 28 行，仅 room/isSpecial/remindOn/followedAt；`_fromRemote` 在 387 行）
- Modify: `lib/src/features/follow/widgets/follow_entry_card.dart`、`follow_common.dart`（离线卡文案）
- Test: `test/features/follow/follow_status_refresh_test.dart` 或新增 `follow_last_live_test.dart`

**已核实的事实：** 云端契约**已经带着这个字段** —— `lib/src/shared/application/data_server_api.dart:66-67,97-98` 定义了 `RemoteFollow.lastLiveAt` / `liveStartAt`，且 53 行注释写明「多余字段透传保留」。断点在 `follow_provider.dart:387` 的 `_fromRemote` **把字段丢掉了**，导致 UI 只能显示「未开播」。web 侧对应 `utils/follow/followDisplay.ts` 的 `offlineLastLiveLabel(room)`。

**Step 1** 写失败用例：
- `_fromRemote 保留 lastLiveAt/liveStartAt（构造 RemoteFollow(lastLiveAt: X) → FollowEntry.lastLiveAt == X）`
- `离线卡在 lastLiveAt>0 时文案为「上次开播 MM-DD HH:mm」，为 0 时回落「未开播」`

**Step 2** 确认失败。

**Step 3** 实现：
1. `FollowEntry` 增 `final int lastLiveAt; final int liveStartAt;`（默认 0），`_fromRemote` 透传、`copyWith` 同步。
2. **刷新链路合并口径**：`refreshStatuses` 拿到新数据时，`lastLiveAt` 取 `max(旧, 新)`（web `followStatusDecay` 的累积语义），避免刷新把已有时间抹成 0。
3. 文案格式化抽成一个纯函数（放 `follow_common.dart`），`offlineLastLiveLabel` 同款：`>0` 显示「上次开播 MM-DD HH:mm」，否则「未开播」。**格式函数要有单测**。
4. T1 若已落地遮罩，把遮罩文案接到这个函数上。

**Step 4** 跑测通过。**Step 5** commit：`feat(follow): 离线关注卡接上「上次开播」链路(透传 lastLiveAt)`

**验收**：`test/features/follow/` 全绿 + 新用例覆盖 max 累积与格式化。

---

### T4 — 设计 tokens 收口（error 色 / 动效时长 / 抽屉 rail 宽度）

**Files:**
- Modify: `lib/src/shared/presentation/design_tokens.dart`
- Modify: `lib/src/features/browse/widgets/browse_sidebar.dart`
- Test: `test/ui/workflows/browse_sidebar_test.dart`、`test/ui/workflows/responsive_skip_test.dart`

**实测现状（与 web 真源对齐要求）：**

| 项 | web 真源 | 当前 flutter | 改为 |
|---|---|---|---|
| error 色 | `#E55050` | `Color(0xFFF56C6C)` | `Color(0xFFE55050)` |
| fast 动效 | 150ms | `Duration(milliseconds: 120)` | 150 |
| normal 动效 | 250ms | `Duration(milliseconds: 200)` | 250 |
| easing | `cubic-bezier(0.16, 1, 0.3, 1)` | `easeOutCubic` | 新增常量化曲线 |
| 抽屉收起态 rail 视觉宽度 | ~28px | `railWidth = 52` | 新增 `visualRailWidth = 28`，布局用 28、点击热区靠 padding 保住 52 |

**Step 1** 写失败用例：`抽屉收起态实际渲染宽度 == 28`（几何断言，用 `tester.getSize` 读带 Key 的容器，不要断言常量自身的值 —— 那测不出行为）。

**Step 2** 确认失败。

**Step 3** 实现上述 5 项。**注意**：改 `error` 色会连带影响所有用 `error` 的组件（`error_view.dart` 等），属预期；`durationFast`/`durationNormal` 的语义保持「用于 hover/过渡」，不要顺手改 `AppSpacing` 数值。

**Step 4** 跑测通过。**Step 5** commit：`style(tokens): error 色 #E55050 + 动效 150/250ms + 抽屉 rail 28px`

**验收**：两个 workflow 测试全绿；`analyze` 0 issue。

---

## Wave 2：2 条并行轨（约 30 分钟）

### T5 — 播放控制条补「飘屏弹幕设置」入口

**Files:**
- Modify: `lib/src/features/play/widgets/player_controls.dart`（539 行；`play-toggle-danmaku` 在 220 行，`IconButton` 组在 125-300 行）
- Test: `test/ui/workflows/play_controls_test.dart`

**参考真源：** `apps/web/src/components/play/PlayerControls.vue:46` —— 控制条有独立的「飘屏弹幕设置」入口（不只是弹幕开关）。

**Step 1** 写失败用例：`控制条存在 key=play-danmaku-settings 的按钮`；`点击后 danmaku-settings-dialog 打开`。

**Step 2** 确认失败。

**Step 3** 实现：在弹幕开关（220 行）旁加一个 `IconButton`（Key `play-danmaku-settings`），`onPressed` 复用**已存在**的 `danmaku_settings_dialog.dart`（`showDanmakuSettingsDialog`）。不要新写对话框，不要改 `danmaku_settings_provider`。

**Step 4** 跑测通过。**Step 5** commit：`feat(play): 控制条补「飘屏弹幕设置」入口(对齐 web PlayerControls)`

---

### T6 — huya/bilibili 弹幕去重

**Files:**
- Modify: `packages/live_parser/lib/src/platforms/huya/danmaku.dart`、`packages/live_parser/lib/src/platforms/bilibili/danmaku.dart`
- Test: `packages/live_parser/test/src/platforms/.../danmaku_test.dart`

**参考真源：** web 有专项去重 —— `apps/web/src/utils/danmaku/huyaDanmakuDedup.ts`（752B）与 `bilibiliDanmakuDedup.ts`（737B）。flutter 侧**只有** kuaishou/youtube 各自实现了 `seen` 集合，huya/bilibili 无 → 协议重推会导致**真机重复刷屏**。

**Step 1** 写失败用例：同一 `(user, content)` 在协议重推时**只产出一条**。

**Step 2** 确认失败。

**Step 3** 实现：对齐两个 ts 的去重键与容量策略（读真源确认键是该平台的稳定 ID 还是 `user+content` 哈希，容量上限用真源数值）。**解析包保持纯 Dart**，禁止引 Flutter。

**Step 4** 跑测通过。**Step 5** commit：`fix(parser): huya/bilibili 弹幕补专项去重(对齐 web danmakuDedup)`

**验收**：`$PY $WS/_dartrun.py $ROOT/packages/live_parser test` 全绿，数量只增不减。

---

## Wave 3：收尾（单执行者，串行，约 25 分钟）

**Task 3.1 golden 重生成 + 同步**

T1（房卡角标）、T4（rail 宽度）、T5（控制条）都会改渲染。**必须等这三条全部落地后一次性重生成**，否则重复返工。

```bash
$PY $WS/_gate.py $ROOT --goldens
```
- 验收：8 张 golden 全绿；`tool/screenshots/zishu/` 同步（脚本自动拷）。
- **若 golden 差异是"多出/少了一块"而非样式微调 → 视为回归，先查再更新**，不要无脑接受。

**Task 3.2 全量门禁**

```bash
$PY $WS/_gate.py $ROOT
```
- 期望：app test **≥472 passed / 0 failed**、app analyze **0 issue**、parser test **≥290 passed / 10 skipped**、parser analyze 0 issue。
- 已知噪声：`latency_test` 在整机套件下可能因并行抢资源告警（已分档，宽松档只 `[latency-warn]`）。若真 failed，单跑该文件复核后再判定。

**Task 3.3 更新 todo.md + 提交推送**

- todo.md 追加本轮章节：结论 / 每项改动与 commit / 门禁实测数字 / **§0 的三条纠错**（尤其「T3 作废」「屏蔽词非差距」）/ 剩余 backlog。
- 提交 `docs(todo): ...`，推送 master（配方见 §1.3），推完补写 `.git/refs/remotes/origin/master`（本环境 `update-ref` 不落盘）。
- 同时提交本计划文档 `docs/plans/2026-09-18-web-alignment-2h.md`。

---

## Wave 4：真机验收（单执行者，约 20 分钟，需要用户授权跳出沙箱）

**Task 4.1 release 重建**

```bash
# 先关掉旧进程
$PY -c "import subprocess; subprocess.run(['taskkill','/F','/IM','zishu_flutter.exe'], capture_output=True)"
$PY $WS/_frun.py $ROOT build windows --release --dart-define=ZISHU_REAL_PARSER=true
```
- 验证开关生效：`data/app.so` 的 mtime 必须更新（`zishu_flutter.exe` 本体不变属正常，见 sandbox 技能坑 4）。

**Task 4.2 拉起 + 截图复验**

- 用 `schtasks /Create + /Run`（父进程=系统服务，绕过宿主边界回收），用完 `/Delete`。
- 探针：`~/.workbuddy/skills/flutter-windows-ui-probe/scripts/shots.py` 拷到 `tool/_shots.py`，**用完删除**。
- **坑**：宿主窗口屏幕矩形会偷走落在其内的点击 → 把应用窗口 `place` 到宿主 rect 之外再点。
- 逐项截图：房卡 LIVE/录播 + 离线遮罩、搜索页两个 tab、离线关注卡「上次开播」、播放条弹幕设置入口、抽屉 rail 宽度。
- **列表类 UI 必须逐条念名字**核对重复/缺失（golden 重生成后依然全绿的那类 bug 只能靠这个抓）。

---

## 5. 文件归属矩阵（冲突红线）

| 任务 | 独占文件 |
|---|---|
| T1 | `room_card.dart`、`cover_badges.dart`、`room_card_badges_test.dart` |
| T2 | `search_view.dart`、`search_dialog_test.dart` |
| T3 | `follow_provider.dart`、`follow_entry_card.dart`、`follow_common.dart`、`test/features/follow/**` |
| T4 | `design_tokens.dart`、`browse_sidebar.dart`、`browse_sidebar_test.dart`、`responsive_skip_test.dart` |
| T5 | `player_controls.dart`、`play_controls_test.dart` |
| T6 | `packages/live_parser/**/huya/danmaku.dart`、`bilibili/danmaku.dart` + 对应测试 |
| 收尾 | golden PNG、`tool/screenshots/zishu/**`、`todo.md`、本计划文档 |

**共享只读**（谁都别改）：`app_shell.dart`、`app_router.dart`、`play_view.dart`、`play_side_panel.dart`、`zishu_tokens.dart`、`cross_catalog.dart`。

## 6. 本轮明确不做（YAGNI / 待裁决）

- ❌ `tasks-ui-refine.md` **T3**（平台 badge 移到右下）—— 依据错误，做了就是回归。
- ⏸ **移动端底栏项集**：web 底栏 = 首页/分类/我的分类/**平台**/关注/搜索/主题/用户；flutter 用**动态**顶替了「平台」位。这是**产品裁决**（「动态」是 flutter 超集功能），不自动执行。
- ⏸ **沉浸态右缘侧抽屉**（web `PlayImmersiveSideSheet.vue`）—— 真实缺口，工作量中，建议单独立项（要动 `play_view.dart`，与多条轨争用）。
- ⏸ **分类索引/分类房间拆成两个路由** —— 结构性重构，超出 2 小时窗口。
- ⏸ **关注页批量导入**、**首页非浏览平台直达表单**、**移动端目录抽屉** —— 真实缺口，留给下一轮。
- ⏸ **弹幕徽章/等级/粉丝牌图片体系** —— web `ChatFanBadge.vue` 23KB，高价值但工作量大，单独立项。
- ⏸ **画质 rank 归一**（移植 `qualityMap.ts`）、**房间统计真实刷新**、**全平台首页纳入抖音 + 加权页配额**、**开播提醒真正生效** —— 均为真实逻辑差距，工作量中，留给下一轮。
- ⏸ **fixture 保真度缺口**：`FixtureBrowseSource.fetchCategories` 忽略 `site`、恒返回写死 3 组分类，导致 golden 覆盖不到全平台索引。修它会连带改 golden 与多处断言，本轮不动，但已记入 backlog。
- ❌ **弹幕屏蔽词/屏蔽用户** —— 非差距（web 也没有），从 backlog 移除。

## 7. 完成定义（DoD）

- [ ] Wave 0~2 六个任务全部 commit，且每条 commit 独立（UI 轨与解析轨不混提）。
- [ ] `$PY $WS/_gate.py $ROOT --goldens` 输出：golden 全绿、app test ≥472 passed / 0 failed、analyze 0 issue、parser ≥290 passed / 10 skipped。
- [ ] golden 变更**逐张**解释过原因（不是"看着没问题"）。
- [ ] 真机截图为证：至少覆盖 T1/T2/T3/T5 四项的可见行为。
- [ ] todo.md 章节含**实测数字**与 §0 三条纠错。
- [ ] master 已推送，`git status -sb` 无 ahead/behind，工作区干净（无临时脚本残留）。
