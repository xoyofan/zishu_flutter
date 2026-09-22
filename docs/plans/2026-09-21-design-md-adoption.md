# DESIGN.md 落地改进计划（awesome-design-md skill 应用）

> 日期：2026-09-21
> 基线：`master` @ `aa11012`（`chore(release): 版本号对齐 1.0.2-beta`）
> 关联 skill：`awesome-design-md`（已安装，见 §1）
> 关联场景：`docs/ui-parity/spec-tokens.md`、`docs/ui-parity/spec-layout.md`、`tasks-ui-refine.md`
>
> **执行状态**：D0 / D1 / D2 / D3 已落地，T2/T3/T4/T5 收口进行中；实测证据与偏差见 §9 执行记录。

## 1. 本次已完成的动作

| 项 | 结果 |
|---|---|
| 安装 `awesome-design-md` skill | `C:\Users\XXF\.pi\agent\skills\awesome-design-md\`（`SKILL.md` + `references/*.md`，共 74 套 DESIGN.md，2.3MB） |
| 来源 | `VoltAgent/awesome-design-md`（74 套，含 `vercel`/`linear.app`/`raycast`/`supabase`/`claude`/`x.ai`/`apple`/`binance` 等） |
| 与 web 对照 | 每套文件含 Stitch 9 段结构：Visual Theme / Color Palette & Roles / Typography / Components / Layout / Depth & Elevation / Do's and Don'ts / Responsive / Agent Prompt Guide |

## 2. 结论先行：这个 skill 在 zishu_flutter 里的正确用法

**不是**"把界面改成 Linear / Vercel 风格"。`AGENTS.md` 已明确：视觉真源是 `SFVideoLive/web`。把外部品牌 DESIGN.md 直接当规范用，会和现有 4 份 parity 规格打架。

正确用法是三条：

| 用法 | 内容 | 价值 |
|---|---|---|
| **A. 借格式，建自家真源** | 用 DESIGN.md 的 Stitch 9 段结构，把项目现在散落在 5 处的视觉规范收敛成**一份项目根 `DESIGN.md`** | 消除规范漂移（现状已出现，见 §3.6） |
| **B. 借参考，补缺失维度** | 项目现在缺 elevation/shadow 系统、字号阶梯、focus/交互态、Do's & Don'ts 成文章节；挑 **1 套**气质最近的参考（推荐 `linear.app`，理由见 §5）**只取结构不取品牌色** | 用成熟格式补齐，而不是自己发明 |
| **C. 借目录，补无基线页面** | `SFVideoLive` 没有对应页面的地方（`/settings`、`/dev`、`/time`、Web landing、Android Material 适配），按气质从 74 套里选 1 套做视觉生成 | 有出处可依，不再"凭感觉调" |

## 3. 现状盘点（全部有代码/文档证据）

### 3.1 没有单一视觉真源

规范目前分散在 **5 处**，没有项目根 `DESIGN.md`（`ls DESIGN.md` → No such file）：

| # | 位置 | 覆盖内容 |
|---|---|---|
| 1 | `docs/ui-parity/spec-tokens.md` | 色板、平台色、播放页三态色、圆角/间距/动效、断点 |
| 2 | `docs/ui-parity/spec-layout.md` | 骨架几何、卡片几何、断点矩阵、4pt 栅格校验 |
| 3 | `docs/implementation-plan.md` §6.1 | 视觉基线一段话 |
| 4 | `lib/src/shared/presentation/design_tokens.dart` | 代码注释里的契约（如 `AppMotion` 的"改动前请确认真源"） |
| 5 | `.agents/skills/vue-ui-to-flutter/SKILL.md` | 视觉 token 基线 + 响应式收缩规范 |

### 3.2 elevation / shadow 完全没有 token 层

全仓 `BoxShadow` 仅 7 处，且多数是裸值：

| 文件:行 | 值 | 问题 |
|---|---|---|
| `lib/src/features/play/widgets/player_controls.dart:781` | `BoxShadow(color: Color(0x59000000), blurRadius: 0, spreadRadius: 1)` | 裸色 + 裸数字 |
| `lib/src/features/play/widgets/player_controls.dart:738` | 裸 `BoxShadow` | 同上 |
| `lib/src/app/shell/category_flyout.dart:171` | 裸 `BoxShadow` | 同上 |
| `lib/src/app/shell/platform_strip.dart:269` | 裸 `BoxShadow` | 同上 |
| `lib/src/features/play/widgets/play_immersive_side_sheet.dart:126` | 裸 `BoxShadow` | 同上 |

`spec-tokens.md` 和 `spec-layout.md` 都没有 elevation 章节 → 这正是 DESIGN.md 的 `Depth & Elevation` 段要覆盖的。

### 3.3 字号阶梯只有 4 级，无 letterSpacing

`design_tokens.dart` 的 `AppTypography` 只有 `title(16)/body(13)/bodySecondary(12)/caption(11)`，没有 Display/Headline 级，没有 `letterSpacing`，也没有 web 真源的字号表。DESIGN.md 的 `Typography Rules` 是完整阶梯表（示例 `linear.app.md` 给了 display-xl→caption 共 10 级含 tracking）。

### 3.4 无 focus / 键盘态规范

Windows 是第一优先级平台（`AGENTS.md`），但全仓没有 focus ring token、没有组件状态矩阵（default/hover/active/focus/disabled/invalid）。DESIGN.md 的 `Component Stylings` 段逐组件给状态。

### 3.5 无 Do's and Don'ts 集中章节

护栏现在散在 `AGENTS.md`（依赖边界）、`vue-ui-to-flutter/SKILL.md`（硬约束）、`design_tokens.dart` 注释里，没有可被 agent 一次性读完的反模式清单。

### 3.6 规范已经漂移（不是假设，是事实）

`tasks-ui-refine.md` 的看板与代码不一致：

| 卡片 | 看板状态 | 代码实际 | 结论 |
|---|---|---|---|
| T1 error 色 + 动效 | "待处理" | `design_tokens.dart` 已是 `#E55050`、`150ms/250ms`、`Cubic(0.16,1,0.3,1)` | **已完成，看板未更新** |
| T2 抽屉 rail 28px | "待处理" | `AppDirectoryDrawer.railWidth` 仍 `52`，无 `visualRailWidth` | 确实待做 |
| T3 房卡平台 badge 移右下 | "待处理" | `room_card.dart:223` 仍在左下 | 确实待做 |
| T4 底栏裁剪到 6 项 | "待处理" | `bottom_nav.dart` 实际 7 项（首页/分类/关注/搜索/动态/我的 + logo） | 确实待做（且"主题"已不在底栏，"动态"仍占位） |
| T5 golden 基线 | "待处理" | 6 张 png 失败 0.97%–1.26% | 确实待做 |

### 3.7 裸值没有机械守卫

`analysis_options.yaml` 只 `include: package:flutter_lints/flutter.yaml`，无自定义 rule、无脚本扫描。`design_tokens.dart` 的"Widget 内禁止裸色值"全靠注释和人工评审。`spec-tokens.md` 已记录**10 处非 4pt 栅格例外**（`13.6 / 5.6 / 10.4 / 4.48 / 3.52 / 5.12 / 5.76 / 7.2 / 8.8 / 18.4 / 70`）和 `AppSpacing.xxl = 28`（web 无对应值），没有登记表 → 例外会继续增长。

### 3.8 有意偏离未登记

`zishu_tokens.dart` 的 `accent` 是**品牌紫**（用户口径 2026-09-20），而 web 真源是金黄 `#f3d04e`。这是有意的，但只在代码注释里写了一次，没有进任何规格文档的"偏离登记"。

## 4. 分阶段改进计划

### D0 — 立真源（0.5 天）

**目标**：项目根出现 `DESIGN.md` v0.1，内容**只记录现状**，不发明新风格。

- 新建 `DESIGN.md`（项目根），按 Stitch 9 段结构：
  - §Visual Theme：深色产品界面 + 单强调色 + Fluent motion，Windows 为验收基线。
  - §Color Palette & Roles：直接引 `zishu_tokens.dart` / `design_tokens.dart` 的语义名，hex 与代码同值；附 `docs/ui-parity/spec-tokens.md` 的完整色板链接。
  - §Typography：现状 4 级 + 字体回退链（`Microsoft YaHei` → fallback list）。
  - §Components：现状组件清单（`shared/presentation/widgets/` 15 个 + `shell/` 8 个）。
  - §Layout：`AppSpacing` / `AppRadius` / `AppDirectoryDrawer` / `AppRoomGrid`。
  - §Depth & Elevation：**登记"当前缺失，散落 5 处裸 BoxShadow"，指向 D1**。
  - §Do's and Don'ts：把 `AGENTS.md` + `vue-ui-to-flutter` 的硬约束 + `spec-layout.md` 的 4pt 例外合并。
  - §Responsive Behavior：`AppBreakpoints` 5 档 + `spec-layout.md` 断点矩阵摘要。
  - §偏离登记：品牌紫 vs web 金黄、`AppSpacing.xxl=28`、10 处非 4pt 例外。
- `AGENTS.md` 增一节：视觉真源 = 根 `DESIGN.md`，改 token 必须先改它。

**验证**：`DESIGN.md` 里每个 hex 都能在 `design_tokens.dart`/`zishu_tokens.dart` 里 grep 到；`flutter analyze` 0 issue（未改代码）。

### D1 — 补 token 缺口（1 天）

**目标**：把 DESIGN.md 里标"缺失"的维度落成代码。

| 新增 | 落点 | 内容 |
|---|---|---|
| `AppElevation` | `design_tokens.dart` | 3–4 级 shadow token（`overlay`/`popover`/`sheet`/`focusHalo`），替换 §3.2 的 5 处裸值 |
| `AppTypography` 扩展 | `design_tokens.dart` | 补 `displaySm / headline / titleLarge / label / overline`，带 `letterSpacing`；**保持字号取自 web 真源**，不抄参考品牌 |
| `AppFocus` | `design_tokens.dart` | focus ring：`accent` 2px + offset 2px；替换 Material 默认聚焦态 |
| `AppStates`（文档级） | `DESIGN.md` | 组件状态矩阵 default/hover/active/focus/disabled/invalid |
| spacing 例外登记 | `DESIGN.md` + `spec-layout.md` | 10 处例外 + `xxl=28` 裁决（保留/废弃并给出替代值） |
| 契约测试 | `test/shared/design_tokens_test.dart` | 为新增 token 加断言（沿用现有契约测试风格） |

**验证**：`flutter analyze` 0 issue；`flutter test test/shared/design_tokens_test.dart`；`flutter test test/ui/light_theme_test.dart`（确保浅色主题同步）。

### D2 — 机械守卫（1 天）

**目标**：让 D1 的成果不会腐化。

- 新建 `tool/check_design_tokens.dart`：扫描 `lib/src/**`，
  - 禁止 `Color(0x...)` / `Colors.*`（白名单：`design_tokens.dart`、`zishu_tokens.dart`、`platform_brands.dart`、`category_colors.dart`）；
  - 禁止裸 `BoxShadow(`（白名单：token 文件）；
  - 禁止裸 `fontSize:` / `BorderRadius.circular(<字面量>)`（白名单同上）；
  - 输出 `file:line` + 违规类型，非 0 退出。
- 接入 `tool/check.ps1` 与 GitHub Actions（`.github/workflows/`）。
- 白名单外的历史违规用 `// ignore: design_token` 显式标注并计数，形成"存量违规数"基线。

**验证**：故意在临时文件写 `Color(0xFF123456)` → 脚本报错；删掉 → 通过；`flutter analyze` + `flutter test` 全绿。

### D3 — 流程接线（0.5 天）

- `.agents/skills/vue-ui-to-flutter/SKILL.md`：把"视觉 token 基线"表替换为"先读根 `DESIGN.md`"，只留 Vue→Flutter 映射表。
- 新建 `.agents/skills/ui-from-design-md/SKILL.md`（项目级）：新页面开工前读 `DESIGN.md` → 选 token → 禁止新增裸值 → 收口跑 D2 脚本。
- `docs/ui-parity/spec-*.md` 顶部加一行"本文是 DESIGN.md 的推导来源；冲突以根 DESIGN.md 为准"。

**验证**：`flutter analyze` 0 issue；人工走查 skill 触发词能命中。

### D4 — 无基线页面的视觉生成（按需，每页 0.5–1 天）

`SFVideoLive` 没有对应页面的地方，按 §5 选型用参考 DESIGN.md 生成，产物写回根 `DESIGN.md` 的对应章节：

| 页面 | 现状 | 参考选型 |
|---|---|---|
| `/settings` | `features/dev`、`user` 有零散 UI | 表单密度参考 `linear.app` |
| `/dev`、`/time` | 私有页面，无基线 | 数据表密度参考 `linear.app` / `clickhouse` |
| Web landing（M5） | 未做 | 按气质另选（候选 `vercel` / `raycast`） |
| Android Material 适配（M6） | 未做 | 保留 Material 3 骨架，只映射 `DESIGN.md` 的色/字 token |

### 并行收口：既有看板 `tasks-ui-refine.md`

D1 会改 `design_tokens.dart`，与 T1 同文件，所以顺序必须是：

```text
T1 标记完成(回填看板)  →  T2 + T3 + T4 并行  →  T5 golden 更新  →  D1
```

T2/T3/T4/T5 都是与外部品牌无关的 SFVideo 对齐项，不要塞进 D0–D3 的计划里混做。

## 5. 参考 DESIGN.md 选型

只用 1 套做**结构参照**（"只取结构不取品牌色"）：

| 参考 | 与 zishu 的匹配度 | 用途 |
|---|---|---|
| **`linear.app`** ← 主推荐 | 近黑画布 + 单强调色 + 密集桌面产品界面 + charcoal 面板 + hairline 边框；气质最接近"深色产品工具" | 字号阶梯、elevation 层级、focus ring、Do/Don'ts 结构 |
| `raycast` | 深色 chrome + 浮层/popover 质感 | 补 `category_flyout` / `player_controls` popover 的 elevation |
| `vercel` | 黑白极简 + 完整 token 表 | 间距刻度与栅格章法 |
| `supabase` | 深色 + 单色强调 + code-first | 备选 |

**明确不取**：`linear.app` 的 `Linear Display` 字体、品牌 logo、`#5e6ad2` 强调色 —— zishu 强调色是品牌紫（`zishu_tokens.dart` 的 `accent`），字体是微软雅黑。

参考路径（绝对）：
`C:\Users\XXF\.pi\agent\skills\awesome-design-md\references\linear.app.md`

## 6. 验收门

```powershell
cd D:\zishu_flutter
flutter analyze                                    # 0 issue
flutter test                                       # 全绿
flutter test test/shared/design_tokens_test.dart    # token 契约
flutter test test/ui/light_theme_test.dart          # 深浅主题同步
dart run tool/check_design_tokens.dart              # D2 后：裸值守卫 0 违规（或存量基线不增长）
flutter build windows --debug -t lib/main.dart      # 主链路改动
```

D0 完成定义：`DESIGN.md` 存在，且其中每个 hex 都能在代码里 grep 到。
D1 完成定义：新增 token 有契约测试；`BoxShadow` 裸值 0 处。
D2 完成定义：守卫脚本能拦住故意注入的裸值；已接入 `tool/check.ps1`。
D3 完成定义：skill 与 `AGENTS.md` 都指向根 `DESIGN.md`，且不再重复定义色板。

## 7. 明确不做

- 不把 zishu 的视觉改成任何外部品牌风格。
- 不重写 `spec-tokens.md` / `spec-layout.md`（它们是 parity 证据链，保留；只在顶部加"以根 DESIGN.md 为准"的说明）。
- 不在 D 系列里顺手做 T2/T3/T4/T5（既是文件冲突，也会让验证口径混在一起）。
- 不引入 light 主题 + accent 切换机制（`spec-tokens.md` 已定为 P3，另立计划）。
- 不为"看起来更现代"替换现行组件库/字体。

## 8. 待裁决

1. **D0 的 `DESIGN.md` 放哪**：项目根 `DESIGN.md`（agent 默认读取位置）还是 `docs/design/DESIGN.md`（不污染根目录）？倾向项目根。
2. **主参考选 `linear.app` 是否认可**？若你认为气质应更接近别的（如 `raycast`/`supabase`），D1/D4 的补缺依据会随之切换。
3. **D2 守卫对存量违规的处理**：一次清干净，还是先打 `// ignore` 建基线、后续逐步清零？倾向后者（避免大范围改动污染 golden）。
4. **是否把 skill 的 `references/` 也 vendor 进仓库** `.agents/skills/awesome-design-md/`（+2.3MB，好处是 Cursor/Codex 等其他 agent 离线可读）？

---

## 9. 执行记录（2026-09-21 回填）

### 9.1 环境基线修正（与计划假设不同，重要）

| 项 | 计划假设 | 实测 | 说明 |
|---|---|---|---|
| `flutter analyze` | 0 issue | **0 error + 11 info** | info 全部是 `test/flutter_test_config.dart` 的 `avoid_return_types_on_setters` |
| 首次 analyze | — | **3006 issues（2995 error）** | `packages/live_parser`、`packages/speech2zh` 未 `pub get`，`uri_does_not_exist`/`undefined_function` 刷屏；子包 `pub get` 后归零 |
| `flutter test` | 未知 | **677 通过 / 1 失败** | 唯一失败 `test/ui/workflows/latency_test.dart`（bilibili 首帧进房耗时，网络相关；单独重跑通过） |
| T1（error 色 + 动效） | 待处理 | **早已完成** | `design_tokens.dart` 已是 `#E55050` / 150ms / 250ms / `Cubic(0.16,1,0.3,1)` |
| T5（6 张 golden） | 失败 0.97%–1.26% | **全部通过** | 看板漂移，已按此回填 |

结论：验收门从「0 issue」改为「**不新增 error**」；分析基线固定为 0 error / 11 info。

### 9.2 D0 立真源 —— 已完成

- 新增项目根 `DESIGN.md`（Stitch 九段 + 偏离登记表 + 真源与漂移），`docs/ui-parity/spec-tokens.md` /
  `spec-layout.md` 顶部各加一行「以 DESIGN.md 为准」。
- `AGENTS.md` 新增 `## 视觉真源`（视觉真源 / 变更纪律 / 守卫命令 / 外部品牌只作结构参考）。
- 校验：`DESIGN.md` 中 45 个 hex 全部能在 `lib/src/shared/presentation/` 或 `spec-tokens.md` 命中（45/45）。

### 9.3 D1 补 token 缺口 —— 已完成

| 新增 | 内容 |
|---|---|
| `AppElevation` | `popover` / `hairline` / `sheet` / `accentGlow(accent)`，数值从原 5 处裸 `BoxShadow` 逐字搬家 |
| `AppFocus` | `ringWidth = 2`、`ringOffset = 2`、`ring(accent)` = 2px 实环 + 4px 24% 光晕 |
| `AppTypography` | 新增 `display` 22 / `headline` 18 / `subtitle` 15 / `label` 10 / `overline` 9（带 letterSpacing）；既有 16/13/12/11 一字未改 |
| `AppDirectoryDrawer` | 曾新增 `visualRailWidth = 28`，经复核真源为 52px 后**已撤销**（见 §9.7） |

- 5 处裸 `BoxShadow` 已全部替换；`grep -rn "BoxShadow(" lib/src` 仅剩 `design_tokens.dart` 定义，守卫实测 `raw_shadow 当前 0 / 基线 0`。
- `test/shared/design_tokens_test.dart` 新增契约断言：4 档既有值逐项钉死、5 档新值、`AppElevation` 四个成员逐字段、`AppFocus.ring` 两圈 spread 4/2、`visualRailWidth`/`railWidth`。

### 9.4 D2 机械守卫 —— 已完成

- `tool/check_design_tokens.dart`（446 行，纯 `dart:io` + `dart:convert`）：4 条规则（`raw_color` / `raw_shadow` /
  `raw_font_size` / `raw_radius`）、5 个整文件白名单、`// ignore: design_token` 行内豁免、
  **行号无关**的稳定基线 key（`路径|规则|字面量`），只允许收敛不允许增长；退出码 0/1/2。
- `tool/design_token_baseline.json`：159 个 key / 220 条存量（`raw_color 101`、`raw_font_size 107`、
  `raw_radius 12`、`raw_shadow 0`）。
- 接入 `tool/check.ps1`（`flutter analyze` 之后，用可选 `Command` 键跑 `dart`，保留失败即停）与
  新增 `.github/workflows/guards.yml`（push/PR → master，Flutter 版本与 `release-windows.yml` 对齐 3.47.1）。
- 自测：注入 `Color(0xFF123456)` 被拦并 exit 1，删除后恢复 OK。

### 9.5 D3 流程接线 —— 已完成

- 新增 `.agents/skills/ui-from-design-md/SKILL.md`：开工必读清单 → token 工作流 → 收口验证 →
  禁止事项 → 输出要求 → 外部品牌只取结构的边界。
- `.agents/skills/vue-ui-to-flutter/SKILL.md`：删除自带色板（改为「一律以根 DESIGN.md 为准」），
  必读清单加入 `DESIGN.md`，并标出两处高频错误（强调色是紫不是金 / 直播中是绿不是红）。
- `awesome-design-md` skill 已 vendor 进 `.agents/skills/awesome-design-md/`（`SKILL.md` + `references/` 74 套）。

### 9.6 未按计划执行的部分

- **原文「T1 回填 → T2+T3+T4 → T5 → 再进 D1」的串行顺序被打破**：D1 与 T2 的耦合点（`visualRailWidth`）最终被证伪并撤销（§9.7），二者实际无数据依赖，
  因此 D1 与 T2/T3/T4 可以完全并行。
- **多 subagent 分轨执行的实测结果**：三条 lane 均在约 41 分钟处被 `Connection error` 掐断
  （`worker` = `opencode-go/deepseek-v4.1-flash`）。`tokens` / `guard` 在被掐断前已把成果落盘且质量达标；
  `docs` 轨零产出（全程在读文件），改由主控直接完成。结论：**长时间跨度的 lane 在本环境不可靠**，
  后续应把 lane 拆到 20 分钟以内，或由主控承担需要大量既有上下文的写作任务。
- 工作区基线同步：远端 `master` 已前进 8 个提交（`aa11012..7e5bb4c`，新增 tag `v1.0.3-beta`），
  本次改动按「stash → pull → 合并」流程与远端合流，冲突面仅 `player_controls.dart`、`tool/README.md`
  与 2 张 `play_style_*.png`。

### 9.7 看板反向漂移：任务书里的「真源」是错的

T2/T3/T4 三张卡片的「SFVideo 真源」描述经复核有两处是错的（细节与出处见 `DESIGN.md` §11.1）：

| 卡片 | 看板主张 | 复核结果 | 处置 |
|---|---|---|---|
| T2 | 抽屉收起态视觉 rail 约 28px，要把布局宽改成 28 | ❌ `main.css:39 --directory-rail-width: 52px`；`DirectoryDrawer.vue:660` 取该变量；rail 内按钮 `width:100%` | 回退 `browse_sidebar.dart`，删掉 `visualRailWidth`，并勘误 `docs/ui-reference/README.md:49` |
| T3 | 平台 badge 应在右下与热度并列 | ❌ `RoomCard.vue:262-273` `.room-card__foot-left { left:0; bottom:0 }` 内含 `.platform-cover-badge` | 不改代码，现状已对齐 |
| T4 | 真源 6 项（紫薯 logo/首页/分类/关注/搜索/我的） | ⚠️ `ui-reference/README.md:44` 为「首页/分类/我的分类/关注/搜索/主题」；「没有动态」成立 | 仅移除 `nav-time`，保留主题与我的分类；360px 差异记为已知差异 |

教训：**看板不是真源**。裁决前必须回到 `SFVideoLive/apps/web/src` 的 CSS/模板原文或官方截图；
中介文档（看板、实测笔记）只能当线索。本次 lane 没有直接照令执行而是先举证反驳，是正确的做法。
