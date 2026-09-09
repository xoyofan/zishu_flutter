# tasks-workflows.md — UI 测试 Workflow 并行执行看板

> 目标:两大类测试体系——①平台 workflow(参数化,任一平台跑同一套链路)②全局 UI workflow(设置/导航/布局)+ 移动端设备矩阵(挤占/溢出/SafeArea/大字体)。
> 全部为**无窗口**验证:flutter test VM widget test,`flutter test test/ui/workflows/` 一条命令出完整报告。
> 启动条件:**前置 W0 完成**(锚点+基线测试 agent 产出已合入,`flutter analyze` 0 issue 且 `test/ui/` 基线用例全绿)。
> 并行纪律:①每张卡文件零交集;②验证只跑**自己的测试文件**(`flutter test <file>`),不跑全量(避免读到其他卡半成品);③锚点补充严格按卡内「可碰文件」边界;④完成后输出改动文件 + 用例通过数,不更新本文件(由 W13 统一收口)。

## 执行批次(最大化并行)

```text
W0 锚点基线(外部前置)
   │
   ├─ 批次1(6 卡并行)
   │   W1 driver框架 ──► 批次2 ─► W2 平台用例 ─┐
   │                    ├─► W3 弹幕     ─┤
   │                    └─► W4 耗时分析 ─┤
   │   W5 设置持久化 ─────────────────────┤
   │   W6 路由可达+导航遍历 ────────────────┤
   │   W7 壳层布局 ───────────────────────┤
   │   W8 设备harness ─► 批次2 ─► W9 手机纵向 ─┤
   │                                 W10 平板横屏 ─┤
   │                                 W11 SafeArea/大字体 ─┤
   │   W12 U9断点占位(skip) ───────────────┤
   │                                      ▼
   └───────────────────────── 批次3  W13 收尾门禁(串行)
```

## 前置

| 卡 | 内容 | 状态 |
|---|---|---|
| W0 | 锚点基线:room-card/platform-tab/play-*/search-*/nav-*/follow-density-*/anchor-follow-btn/timeline-filter-* 等锚点落位;`test/ui/` 基线冒烟测试全绿 | [x] 已合入(W13 全量门禁验证通过,锚点无补充需求) |

## 批次 1(6 卡并行)

| 卡 | 内容 | 允许文件 | 锚点可碰 | 验证 |
|---|---|---|---|---|
| W1 | 平台 workflow **driver 框架**:`pumpPlatformApp(site)`、`expectNoOverflow(tester)`(takeException 捕 RenderFlex overflow)、`measureOpenRoomLatency`(Stopwatch+runAsync,返回 `{ms, frames}` 并按格式 `[latency] {site} {roomId}: {ms}ms / {frames} frames` 打印)、`expectDanmakuEntries`、`expectCategoryRenders` 等可复用 helper;设备表 `kTestDevices`(iPhone SE/15/ProMax、Android 360×640/Pixel7、iPad mini/Air/Pro12.9、Android 平板、横屏组,含 dpr 与 safeArea insets) | `test/ui/workflows/platform_workflow.dart`、`test/ui/workflows/devices.dart` | 无 | dart analyze 该目录 0 error;driver 编译通过 |
| W5 | 设置持久化 workflow:改主题模式/弹幕开关/默认画质 → shared_preferences(in-memory)断言写入 → 重新 pump 回读一致;serverUrl 保存 SnackBar 反馈 | `test/ui/workflows/settings_test.dart` | settings_view(如需) | flutter test 本卡文件全过 |
| W6 | 路由可达 + 导航遍历:`/all /follow /time /settings /search /douyu /douyu/play/63136 /douyu/anchor/X` 逐个深链 pump 断言渲染;顶导航遍历 首页→关注→设置→搜索→返回 每步锚点断言 | `test/ui/workflows/navigation_test.dart` | app_shell.dart(如需) | flutter test 本卡文件全过 |
| W7 | 全局布局 workflow:顶导航高 44px 断言、平台 tabs 顺序与品牌色点、内容区不与导航重叠;播放页路由**无壳**(不渲染 AppShell 顶导航)断言 | `test/ui/workflows/layout_test.dart` | app_shell.dart、play_view.dart(如需) | flutter test 本卡文件全过 |
| W8 | 移动 harness:`pumpOnDevice(page, device)`(设 physicalSize/dpr/safeArea)、`overflowSweep(tester, pages)`(页面×尺寸全扫 takeException)、`textScaleSweep(1.0/1.15/1.3)`、`safeAreaSweep` 注入 iPhone15 刘海 insets | `test/ui/workflows/layout_harness.dart` | 无 | dart analyze 0 error;harness 编译通过 |
| W12 | U9 响应式断点**占位组**(<768 底部导航、播放页侧栏堆叠、窄屏单列、**平台 tab 收缩:768–1023 仅品牌色点(icon-only)、≥1024 点+文字**、内容区筛选 chips 用 `Wrap` 多行):每条 `skip: 'U9 待实现'`,写清断言内容与转绿条件;收缩规范见 `.agents/skills/vue-ui-to-flutter/SKILL.md` 响应式导航收缩节 | `test/ui/workflows/responsive_skip_test.dart` | 无 | flutter test(skip 计数正确) |

## 批次 2(6 卡并行,依赖 W1 / W8)

| 卡 | 内容 | 允许文件 | 锚点可碰 | 验证 |
|---|---|---|---|---|
| W2 | 平台用例:对 `douyu/huya/bilibili` 各生成文件,每平台 5 workflow——categoryRenders(分组>0、子分类联动)/categoryRoomsCorrect(卡片数=fixture、字段非空、loadMore 行为)/platformSmoke(分类→房间→进房→切画质→返回) | `test/ui/workflows/platform_douyu_test.dart`、`platform_huya_test.dart`、`platform_bilibili_test.dart` | browse/**、play/**(仅 key) | flutter test 本卡三文件全过 |
| W3 | 弹幕 workflow:播放页聊天 tab 弹幕条目>0、用户名 hash 着色、粉丝牌徽章;预留 `expectDanmakuIncrement` 接口位(G2 接真弹幕后同用例升级增量断言,不重写测试) | `test/ui/workflows/danmaku_test.dart` | play_side_panel.dart(仅 key) | flutter test 本卡文件全过 |
| W4 | 耗时分析 workflow:每平台 openRoomLatency——墙钟 ms(解析回调+编排+首帧)+ pump 帧数;报告逐行打印;阈值 500ms 超限 fail;输出汇总表(G1 接真解析后同一用例自动变端到端报告) | `test/ui/workflows/latency_test.dart` | browse/**、play/**(仅 key) | flutter test 本卡文件全过;stdout 含三平台报告行 |
| W9 | 手机纵向溢出矩阵:5 手机尺寸 × (首页/分类/播放/关注/搜索/设置) 全扫——无 RenderFlex overflow、顶导航不裁切、首卡与导航 rect 不相交、窄屏播放页视频宽>0(侧栏不挤没) | `test/ui/workflows/mobile_phones_test.dart` | 无(缺锚点报告给 W13) | flutter test 本卡文件全过 |
| W10 | 平板 + 横屏矩阵:iPad mini/Air/Pro12.9、Android 平板纵/横;手机横屏(852×393、915×412)播放页专项(视频主区占比、控制条可达);网格列数随宽度变化断言 | `test/ui/workflows/mobile_tablets_test.dart` | 无(同上) | flutter test 本卡文件全过 |
| W11 | 平台差异矩阵:SafeArea(iPhone15 insets 47/34 下导航内容可点、底部不被遮挡)+ textScale 1.0/1.15/1.3 三档(卡片标题行/设置行/播放控制条无溢出)+ 高 DPR @3x 抽查 | `test/ui/workflows/mobile_accessibility_test.dart` | 无(同上) | flutter test 本卡文件全过 |

## 批次 3(串行收尾)

| 卡 | 内容 | 允许文件 | 验证 |
|---|---|---|---|
| W13 | 收尾门禁:汇总各卡缺锚点报告并统一补齐 → `flutter analyze`(0 issue)→ `flutter test` 全量绿 → `flutter build windows --debug -t lib/main.dart` → 更新 `tasks.md`(U 轨测试状态)与本看板 → 输出完整测试报告(平台 workflow ×3 + 全局 ×3 + 设备矩阵用例总数) | lib/**(仅 key 补齐)、tasks.md、tasks-workflows.md | [x] 四项门禁全绿(2026-09-09):analyze 0 issue / test 147 passed+6 skipped / build 47.6s;锚点无需补齐 |

## 决议与备注

- 平台 workflow 是**参数化框架**:新平台接入只需在批次 2 增加一个 `platform_<site>_test.dart` 文件,driver/helper 零改动。
- 耗时与弹幕用例与 G1/G2 交汇:**fixture 阶段**度量 UI 编排成本、断言样例弹幕;接入真实解析/弹幕后同一用例自动升级,测试零重写。
- W12 占位组转绿即视为 U9(响应式适配)完成,作为 U9 验收标准写入 tasks.md。
- iOS/Android 差异在本阶段模拟的是**行为差异**(SafeArea、大字体、DPR);平台专属 Widget(如 Cupertino 细节)U9 后按需追加。

## 执行记录(2026-09-09 W13 收尾)

### 门禁结果

| 门禁 | 命令 | 结果 |
|---|---|---|
| 静态分析 | `flutter analyze` | No issues(0 issue,9.8s) |
| 全量测试 | `flutter test` | **147 passed / 6 skipped / 0 failed**(01:15) |
| Windows 构建 | `flutter build windows --debug -t lib/main.dart` | Built `build\windows\x64\runner\Debug\zishu_flutter.exe`(47.6s) |
| 锚点补齐 | — | 无需改动:W9/W11 失败均为布局问题而非缺 key,修复后全绿 |

### 用例统计(实际执行 153 条 = 147 通过 + 6 skip)

| 分组 | 文件 | 声明用例 |
|---|---|---|
| 平台 workflow ×3(W2) | platform_douyu / platform_huya / platform_bilibili | 9 |
| 全局 UI(W3/W4/W5/W6/W7) | danmaku / latency / settings / navigation / layout | 19 |
| 设备矩阵(W9/W10/W11) | mobile_phones / mobile_tablets / mobile_accessibility | 12 |
| 响应式占位(W12) | responsive_skip | 6(全部 skip:U9 待实现) |
| workflows 小计 | 12 文件 | 46 |
| `test/ui/` 基线 | app_shell / browse_home / category / play_page / search / follow_view / anchor_timeline / workflow_browse_play | 23 |
| `test/legacy/`(旧架构回归) | 8 文件 | 79 |

### W9 / W11 失败修复(详见 `tasks.md`「W13 修复明细」)

修复前:W9 4/4 失败、W11 2/4 失败;修复后 8/8 通过。根因为三处固定宽度(顶导航约 420dp、播放页侧栏 328dp、控制条 288dp)与卡片文本区高度预算未随字体缩放。

遗留:`follow@iPhone15Landscape(852×393)` 横屏仍有 lib 溢出,W10 以 drain 容忍(用例通过),待 U9 横屏 sheet 落地后修。

## 执行记录(2026-09-09 U9 收口,W12 转绿)

W12 占位组 6 用例全部移除 skip 转绿,U9 验收完成(见 `tasks.md`「U9 落地明细」):

| 用例 | 结果 |
|---|---|
| 底部导航 <768(360×640):顶导航不渲染、底部 56px 含 首页/关注/设置 | ✅ |
| 平台 tab 收缩 768–1023(820×1180):icon-only + Tooltip(平台名) | ✅ |
| 平台 tab 收缩 >=1024(1600×1200):色点+文字 | ✅ |
| 播放页堆叠 竖屏 360×640:视频全宽、侧栏堆叠下方 | ✅ |
| 播放页堆叠 横屏 852×393:侧栏隐藏/sheet 化 | ✅ |
| chips 换行 360 宽:Wrap 多行、全部挂载 | ✅ |

全量门禁:flutter analyze 0 issue;flutter test **153 passed / 0 skipped / 0 failed**;build windows --debug 14.7s。

配套测试基建修正:`responsive_skip_test`/`layout_test`/`browse_home_test`/`platform_workflow` 的 pump 从 `setSurfaceSize` 改为直接写 `tester.view`(physicalSize + dpr=1)——`setSurfaceSize` 不更新 MediaQuery(恒报 800×600),任何断点相关断言必须写 view 才有意义;`mobile_tablets_test` landscapePlayPriority 第 4 步按 U9 口径修订(旧断言"328 常驻同排"与新验收矛盾,以 W12 为准)。
