# 按钮与微交互提案：按钮打磨 + 状态缺口

> **状态**：提案（待评审）——**本文件只写方案，不含任何代码改动**。
> **日期**：2026-09-21
> **范围**：`lib/src/**` 下全部可点元素的状态矩阵、动效强度与观感打磨。
> **约束真源**：`DESIGN.md` §1/§2/§4/§6/§7/§10；token 以 `design_tokens.dart` /
> `zishu_tokens.dart` 为唯一来源；规则引自 `.agents/skills/` 下 7 个已 vendor 的 skill（见附录 A）。
> **动笔前提**：任何 token 变更 = `DESIGN.md` + token 文件 + `test/shared/design_tokens_test.dart`
> 三处同步（`AGENTS.md`「视觉真源」硬规则）。

---

## ⚠️ 盘点快照与并发改动（先读这一节）

**盘点快照**：`git HEAD = 5db76eb`，盘点开始时工作区**干净**（`git status --short` 为空）。
盘点完成时间约 **2026-09-22 10:30**。

**盘点后发生了并发改动**：另一个轨（token 收敛 + svip 第 3 统计列）在 **10:39–10:48**
修改了 20 个文件，其中**包含本提案的目标文件**：`side_panel_header.dart`（+110 行）、
`compact_switch.dart`、`design_tokens.dart`、`tool/design_token_baseline.json` 等。
本提案**只写文档**，未触碰这些文件：本轨的全部产出就是本文档一个文件，
在 `git status --short` 里以 `?? docs/plans/2026-09-21-button-polish-proposal.md` 出现。
列表中其余的 `M` 与 `??`（含 `test/ui/failures/` 下新生成的 `_band_*.png` / `_crop_*.png`）
**全部属于并发轨**（盘点开始时 `git status --short` 为空，可作为对照）。

**对本提案的影响**：

1. **行号会漂**——`side_panel_header.dart` 的 `_SideHeader` 内新增了统计列与 `FittedBox`，
   使 `_StatValue` 从 ~477 行下移到 520 行。本文档的行号是**盘点快照值**，
   但已按 10:48 的工作区**重新核对过一遍**；后续如再变动，请**以符号名
   （`_SideActionButton` / `_SideTextAction` / `CompactSwitch` 等）为准**，行号只作定位辅助。
2. **结构性结论未变**——已在 10:48 的工作区上逐条复核：`InkWell` 43 / 显式 `hoverColor` 8 /
   `GestureDetector` 7 / `mouseCursor` **0** / `AppFocus` 组件引用 **0** / 代码内 `Semantics(` 2 /
   `playFollowBgHover`+`playSuperBgHover` 引用 **0** / `strokeWidth: 2` 11 /
   `disableAnimations` **0**——**全部与盘点时一致**。
   `_SideActionButton`（:463）仍是 `Material(color: background)` + `InkWell(onTap:)`，
   无过渡、无 hover token、`onPressed` 非空——**手段 1 的前提未变**。
3. **已并轨的项**：并发轨已把 `compact_switch.dart` 的两处裸值换成 token
   （`Color(0xff3a3a3a)` → `AppColors.border`、`Colors.white` → `AppOnBright.white`）。
   因此**§3.3 手段 6 的第 4 步（清裸色值）已完成，可直接删掉**；
   手段 6 剩余的 `curve` / 光标 / hover / disabled 四项**仍未做**。
4. **独立佐证**：并发轨新增的 `AppOnBright` token 注释自己就写着
   「**已知对比度问题**（既有取值，本轮只做同值换 token，未改数值）：浅色主题的 accent 是深紫
   `#6A1B9A`，本类的 `text` / `glyph`（黑系）压在其上对比度偏低；浅色主题真正需要的是反白前景。
   **是否按主题分套待裁决**。」——这与 §1.7 与 §六-10 的对比度结论**互相印证**，
   说明「颜色当填充 vs 当文字」的边界问题是两条轨独立撞到的同一面墙。
5. **⚠️ 已发生 golden 碰撞**：并发轨已 `--update-goldens` 重刷了
   `test/ui/play_style_follow.png` 与 `test/ui/play_style_recommend.png`（两者现在在 `git status` 里是 `M`）。
   而本提案的 §5.2 预测**手段 1/2 也会动 `play_style_follow.png`**（侧栏关注/超关 chip 就在那个画面里）。
   → **两个轨会碰同一张 golden**。建议：本提案的 Phase 2 必须等并发轨提交并稳定后再开，
   否则差异图里分不清是谁改的（`visual-polish` 的“看不懂的差异不要更新”在这里会直接失效）。

**建议**：本提案的评审应在并发轨落地并提交后再定稿，届时把行号与 §3.3 手段 6 的步骤重对一遍。

---

## 0. 结论摘要（TL;DR）

盘点结论是：**这个项目的按钮不是"不够酷"，而是"六态里只做了 2.5 态"**。

| 维度 | 现状 |
|---|---|
| focus 态 | **全项目 0 实现**。`AppFocus` 只出现在 token 文件与其契约测试里，无任何组件引用（`DESIGN.md` §4.2 自认待办） |
| hover 态 | 43 处 `InkWell` 只有 **8 处**显式写了 `hoverColor`；其余靠 Material 3 默认 state layer。同一壳层里有 4 种 hover 底色来源，**且桌面顶栏的 hover 方向是反的**（`surface` L=0.239 → `surfaceSoft` L=0.191 = 变暗；`DESIGN.md` §4.2 要的是 `surfaceRaised` L=0.285） |
| pressed 态 | 除 2 处 chip 有 `*BgActive` token 外，其余全靠 InkWell 涟漪；无一处有 token 化的按压反馈 |
| disabled 态 | 全库只有 **4 处** `onPressed: null`；且 `_SideTextAction` 的禁用文字实测 \|Lc\| **13.8**（远低于 APCA 门槛） |
| loading 态 | 全库只有 **1 个**按钮做对（`user_area.dart` 登录），其余 11 处 `strokeWidth: 2` 全是页面级 spinner，不是按钮态 |
| 指针光标 | `mouseCursor` / `SystemMouseCursors` **全库 0 处**。7 处 `GestureDetector` 既无光标也无 hover 也无涟漪 |
| 曲线纪律 | 4 处 `AnimatedContainer` 未给 `curve` → 默认 `Curves.linear`（`motion-and-storytelling` 明令禁止 linear） |
| 死 token | `playFollowBgHover` / `playSuperBgHover` 在组件层**零引用**——即"关注/超关"两个最重要的表现型按钮**根本没有 hover 态** |
| 实测对比度 | 超关常态标签 `#C9A0F0` on `#442D5B` = \|Lc\| **31.5**；顶栏/侧栏 active 用 `accent` 当文字 = \|Lc\| **17.3** |

**三个最严重的缺口**（详见 §二）：
1. focus 态零实现（Windows 键盘可达性是验收项）。
2. hover/pressed 无 token 纪律：`playFollow*Hover`/`playSuper*Hover` 死 token + 4 种 hover 底色来源 + **顶栏 hover 变暗（方向反）** + 4 处 linear 曲线。
3. `GestureDetector` 无反馈（`CompactSwitch` 是全局设置里最常用的控件，却无 hover、无光标、无按压视觉）。

**推荐的三个"酷炫化"手段**（详见 §3.3，全部零新 token）：
1. **关注/超关 chip 用 `AnimatedContainer` + 已有 hover/active token 做颜色组合过渡**，并让内层图标做一次性脉冲（不撑按钮边界）。
2. **hover 光晕复用已登记的 `AppElevation.accentGlow`**（配 `AppMotion.fast` + `AppMotion.curve` 淡入，不跳出来）。
3. **loading 用进度指示原地替换文字**（`Stack` 保宽 + 交叉淡入），先把「跳转」「重试」这两个"点了没反应"的按钮补上。

---

## 一、现状盘点

### 1.1 盘点口径

- 逐文件读源码 + `grep` 统计，不凭印象。统计命令与原始数字见附录 B。
- 六态列定义直接取 `button-states` 的 "The Six States" 表：**default / hover / active(pressed) / focus / disabled / loading**。
- 图例：✅ 有且用 token / ⚠️ 有但来自 Material 默认（非 token，不可控）或口径不一致 / ❌ 无。
- 「实现原语」列标注承载交互的 widget，这是判断"反馈从哪来"的关键。

### 1.2 全局基础设施盘点（缺口是系统性的，不是零散的）

| 项 | 实测 | 后果 |
|---|---|---|
| `app_theme.dart` 的 `_decorate()` | 配了 `colorScheme` / `sliderTheme` / `chipTheme` / `navigationBarTheme` / `progressIndicatorTheme`；**没有** `hoverColor` / `focusColor` / `splashColor` / `splashFactory`，**也没有** `textButtonTheme` / `iconButtonTheme` / `filledButtonTheme` / `outlinedButtonTheme` | Material 3 的 hover(8%) / focus(10%) / pressed(10%) state layer 全部走 `colorScheme.primary = accent` 的默认不透明度——**不是 token，改主题改不动，且与显式 `hoverColor` 的 8 处互相打架** |
| `InkWell` 总数 | **43** | — |
| 其中显式 `hoverColor` | **8**（`bottom_nav:144` surface、`follow_avatars:206` 平台色@0.3、`platform_strip:158/180` surfaceRaised、`platform_strip:250` surfaceSoft、`top_nav:207/315` surfaceSoft、`user_area:141` surfaceSoft） | hover 底色有 **4 种来源**：`surfaceSoft` / `surface` / `surfaceRaised` / M3 默认。`DESIGN.md` §4.2 只写了 `surfaceRaised` 一种 |
| `mouseCursor` / `SystemMouseCursors` | **0** | `designing-elite-ui` 原则 6 要求 "Cursor affordances… hover highlights… unmistakable active states"；`button-states` checklist 要求 "Does `cursor: pointer` appear on all interactive elements at rest?"。`InkWell` 在 `onTap != null` 时会自动给 click 光标，但 `GestureDetector` **不会** |
| `AppFocus` 组件引用 | **0**（只有 `design_tokens.dart:254` 定义 + `test/shared/design_tokens_test.dart:175` 契约断言；定义行因并发轨新增 token 已从 202 漂到 254） | 键盘焦点完全依赖 Material 默认 overlay（无外扩环） |
| `Semantics(button: true)` | **0**（全库代码里 `Semantics(` 只有 **2 处**：`side_panel_header.dart:208`、`compact_switch.dart:26`，都不是 button role） | 屏幕阅读器读不到"这是个按钮" |
| `MediaQuery.disableAnimationsOf` / reduce-motion | **0** | `micro-interactions` 与 `motion-and-storytelling` 都把 `prefers-reduced-motion` 列为 "always" 硬规则 |
| `strokeWidth: 2` | **11 处**，其中 **1 处**在按钮内（`user_area.dart:304`） | loading 态几乎全缺 |
| 显式禁用（`onPressed: null` / `onTap: null`） | **4 处**（`user_area:294`、`parse_benchmark_view:326/339`、`follow_view:220`） | 29 个 `VoidCallback?` 字段里绝大多数从没被传过 `null`——即**结构上无法禁用** |
| `AnimatedContainer` / `AnimatedAlign` | **7 处调用，分布在 5 个文件**：带 `curve` 的 3 处（`follow_button:22`、`browse_sidebar:54`、`follow_platform_filter:137`），**不带 `curve` 的 4 处**（`compact_switch:30/39/42`、`platform_strip:252`） | 不带 `curve` 时 `AnimatedContainer` 默认 `Curves.linear` → `motion-and-storytelling`「Never use `linear` for UI motion — it reads as mechanical and unfinished」直接判为缺陷 |
| 守卫脚本规则 | `tool/check_design_tokens.dart` 只有 `raw_color` / `raw_shadow` / `raw_font_size` / `raw_radius` 四类 | **没有 `raw_duration`** → 时长漂移不会被拦。实测已存在 200ms(`play_view:484`) / 220ms(`chat_tab:403`) / 720ms(`play_view:256`) / 800ms(`app_shell:62`) / 1200ms(`state_dot:22`) 五处裸时长 |

> `visual-polish` 的 "The state and content matrix" 说得很准："Flag cells that are *missing* and cells that are *present but indistinguishable* — hover and active rendering identically is the same defect as no hover at all."
> 本项目的实际情况是**第三种**：hover 到处都有，但**来源不可控**（M3 默认 vs 显式 token 混用），所以它在不同区域长得不一样。

### 1.3 表现型元素状态矩阵（关注 / 超关 / CTA / 空态）

| # | 元素 | 文件:行 | 实现原语 | default | hover | pressed | focus | disabled | loading |
|---|---|---|---|---|---|---|---|---|---|
| E1 | 侧栏「关注」chip | `features/play/widgets/side_panel/side_panel_header.dart:463` `_SideActionButton`（`:402` 的 `_SideActions` 组装） | `Material(color: background)` + `InkWell` | ✅ `playFollowBg` | ❌ token 已备但零引用；只有 M3 默认叠加 | ❌ | ❌ | ❌ `onPressed` 是 `VoidCallback`（非空） | ❌ |
| E2 | 侧栏「超关」chip | 同上（`:441` 调用） | 同上 | ✅ `playSuperBg` | ❌ 同上 | ❌ | ❌ | ❌ | ❌ |
| E3 | 侧栏「直播提醒」文字按钮 | `side_panel_header.dart:343` `_SideTextAction`（`:130` 调用，key `play-side-notify`） | `Material(shape: StadiumBorder)` + `InkWell` | ✅ `textSecondary` + `tokens.border` 描边 | ❌ 无 `hoverColor` | ❌ | ❌ | ✅ `onPressed: null` → fg `textSecondary@0.55`（**实测 \|Lc\| 13.8**） | ❌ |
| E4 | 侧栏「跳转」文字按钮 | 同上（`:140` 调用，key `play-side-external`；`onPressed` 来自 `async` 的 `_openRoomExternal`） | 同上 | ✅ | ❌ | ❌ | ❌ | ✅（`externalUrl == null` 时） | ❌ **异步动作零反馈**（失败才弹 SnackBar） |
| E5 | 移动端 meta bar 关注/超关 | `features/play/widgets/play_meta_bar.dart:369` `_MetaActionButton` | `Material` + `InkWell` | ✅ `playFollowBg`/`playSuperBg` | ❌ | ❌ | ❌ | ❌ `VoidCallback` 非空 | ❌ |
| E6 | 主播页「关注」按钮 | `features/anchor/widgets/follow_button.dart:22` `FollowButton` | `AnimatedContainer(normal + curve)` + `Material(transparent)` + `InkWell` | ✅ `accent` 实底 | ❌ 无 `hoverColor` | ⚠️ 只有涟漪（但**有** 250ms 颜色过渡） | ❌ | ❌ | ❌ |
| E7 | 「重试」按钮（text / outlined） | `shared/presentation/widgets/retry_button.dart:36/42` | `TextButton.icon` / `OutlinedButton.icon`，`foregroundColor: accent` | ⚠️ `accent` 当文字色，实测 **\|Lc\| 17.3** | ⚠️ M3 默认 | ⚠️ M3 默认 | ⚠️ M3 overlay，非 `AppFocus.ring` | ❌ `onRetry` 非空 | ❌（重试会触发异步 reload，但按钮不显示） |
| E8 | 错误空态区（`EmptyView`/`ErrorView` 里的按钮） | `shared/presentation/widgets/empty_view.dart` / `error_view.dart` | 复用 E7 | — | — | — | — | — | — |

### 1.4 标准型元素状态矩阵（导航 / 列表项）

| # | 元素 | 文件:行 | 实现原语 | default | hover | pressed | focus | disabled | loading |
|---|---|---|---|---|---|---|---|---|---|
| N1 | 顶栏 logo | `app/shell/top_nav.dart:204` `_Logo` | `InkWell(hoverColor: surfaceSoft)` | ✅ | ✅ `surfaceSoft` | ❌ | ❌ | ❌ | n/a |
| N2 | 顶栏导航项（首页/分类/关注/搜索/主题/设置/账号） | `top_nav.dart:313` `_NavAction` | `MouseRegion` + `Tooltip` + `Material(transparent)` + `InkWell(hoverColor: surfaceSoft)` | ✅ active=`accent`（**\|Lc\| 17.3**）/ rest=`textSecondary`（**\|Lc\| 41.8**） | ✅ `surfaceSoft` | ❌ | ❌ | ❌ | n/a |
| N3 | 底栏导航项（8 项） | `app/shell/bottom_nav.dart:143` `_BottomItem` | `InkWell(hoverColor: surface)` | ✅ | ✅ `surface`（在 `surfaceSoft` 底上只亮一档） | ❌ | ❌ | ❌ | n/a |
| N4 | 平台条 tab（文字+图标） | `app/shell/platform_strip.dart:154/176` | `InkWell(hoverColor: surfaceRaised)` + `DecoratedBox` | ✅ 选中 `brand@0.12` + `brand` 描边 | ✅ `surfaceRaised` | ❌ | ❌ | ❌ | n/a |
| N5 | 平台 tab（34×34 网格，**本项目最佳实践**） | `platform_strip.dart:247` | `MouseRegion` + `InkWell(hoverColor: surfaceSoft)` + `AnimatedContainer(fast, **无 curve → linear**)` + `AppElevation.accentGlow` | ✅ 选中 `surfaceRaised` + `brand` 描边 + **accentGlow** | ✅ | ❌ | ❌ | ❌ | n/a |
| N6 | 顶栏账号 / 登录 | `app/shell/user_area.dart:138` | `InkWell(hoverColor: surfaceSoft)` + `borderRadius: allPill` | ✅ | ✅ | ❌ | ❌ | ❌ | n/a |
| N7 | 抽屉收藏星行 | `features/browse/widgets/browse_sidebar.dart:124` `_FollowRow` | `InkWell`（**无 hoverColor**） | ✅ | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N8 | 抽屉分类项 | `browse_sidebar.dart:238/437` | `InkWell`（**无 hoverColor**） | ✅ | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N9 | 抽屉开合竖条 | `browse_sidebar.dart` `_ToggleRail` | `InkWell` | ✅ | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N10 | 顶栏 hover 浮层分类项 | `app/shell/category_flyout.dart:99/413` | `InkWell`（**无 hoverColor**） | ✅ | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N11 | 我的分类 chip | `app/shell/my_category_flyout.dart:342/374` | `InkWell` + `Container`（**无动画**） | ✅ 选中 `brand@0.12` + `brand@0.55` 描边 | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N12 | 关注页平台筛选 chip | `features/follow/widgets/follow_platform_filter.dart:133` | `InkWell` + `AnimatedContainer(fast + curve)` | ✅ 选中 `accent@0.18` + `accent` 描边 | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N13 | 搜索页平台筛选 chip | `features/search/widgets/search_platform_chips.dart:52` | `InkWell` + `Container`（**无动画**） | ✅ 选中 `brand.color@0.18` | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N14 | 房卡 | `features/browse/widgets/room_card.dart:43` | `Material(surface)` + `InkWell`（无 hoverColor） | ✅ | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N15 | 关注卡 / 关注行 | `follow_entry_card.dart:77` / `follow_entry_row.dart:70` | `Material` + `InkWell(onTap/onLongPress)` | ✅ | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N16 | 关注卡/行内**主播名** | `follow_entry_card.dart:96` / `follow_entry_row.dart:129` | **`GestureDetector`** | ✅（看起来可点） | ❌ | ❌ | ❌ | ❌ | n/a |
| N17 | 搜索结果 tile / 头像 | `search_result_tile.dart:33/206` `InkWell`；`:156` **`GestureDetector`** | 混合 | ✅ | ⚠️ M3 默认 / ❌ | ❌ | ❌ | ❌ | n/a |
| N18 | 播放侧栏分类收藏星 | `features/play/views/play_view.dart:770` | `InkWell`（无 hoverColor） | ✅ `brand` 星 | ⚠️ M3 默认 | ❌ | ❌ | ❌ | n/a |
| N19 | 播放页 stage（点画面切播放/暂停） | `play_view.dart:1069` `Focus` + `GestureDetector(opaque)` | `GestureDetector` | ✅ | ❌（有 `Focus` 但只用于键盘空格） | ❌ | ⚠️ 有 `FocusNode`，但**无可见环** | n/a | n/a |
| N20 | 沉浸侧滑面板遮罩（点空白关闭） | `play_immersive_side_sheet.dart:64` | `GestureDetector(opaque)` | ✅ | ❌ | ❌ | ❌ | n/a | n/a |

### 1.5 克制型元素状态矩阵（表单 / 设置 / 危险操作）

| # | 元素 | 文件:行 | 实现原语 | default | hover | pressed | focus | disabled | loading |
|---|---|---|---|---|---|---|---|---|---|
| C1 | 登录对话框「登录」 | `app/shell/user_area.dart:294` | `FilledButton` + `_busy` | ✅ `accent` 实底 / 白字 | ⚠️ M3 | ⚠️ M3 | ⚠️ M3 overlay | ✅ `_busy ? null : _submit` | ✅ **14×14 spinner 原地替换文字** ← **全项目唯一做对的 loading** |
| C2 | 登录对话框「取消」 | `user_area.dart:285` | `TextButton` | ✅ `textSecondary` | ⚠️ M3 | ⚠️ M3 | ⚠️ M3 | ❌ | n/a |
| C3 | `CompactSwitch`（全局设置开关） | `shared/presentation/widgets/compact_switch.dart:28` | **`GestureDetector`** + `AnimatedContainer(fast, **linear**)` ×3 | ✅ 选中 `accent` / 未选 `AppColors.border`（盘点时为裸 `Color(0xff3a3a3a)`，并发轨已收敛） | ❌ 无 | ❌ 无按压视觉 | ❌ | ❌ `onChanged` 非空 | n/a |
| C4 | `FollowIconAction`（特别关注/提醒/删除） | `features/follow/widgets/follow_common.dart:265` | `IconButton` | ✅ active=`accent`（**\|Lc\| 17.3**）/ danger=`error` / rest=`textSecondary` | ⚠️ M3 | ⚠️ M3 | ⚠️ M3 | ✅ `onPressed` 可空 | n/a |
| C5 | 关注页「删除所选」 | `features/follow/views/follow_view.dart:220` | `onPressed: _selectedKeys.isEmpty ? null : _deleteSelected` | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ | ❌ |
| C6 | 解析基准页运行/恢复 | `features/dev/views/parse_benchmark_view.dart:326/339` | `onPressed: _running ? null : …` | ✅ | ⚠️ | ⚠️ | ⚠️ | ✅ | ❌（`_running` 期间按钮只是变灰，不显示进度） |
| C7 | 设置页各控件 | `features/follow/views/settings_view.dart` | 混合（`CompactSwitch` / `Slider` / `Checkbox`） | ✅ | ⚠️ | ⚠️ | ⚠️ | 部分 | n/a |
| C8 | `SectionHeader` | `shared/presentation/widgets/section_header.dart` | **自身无可点元素**（`trailing` 由调用方注入，通常是 `TextButton`） | — | — | — | — | — | — |

> `SectionHeader` 被列在任务清单里，但盘点结论是它**不含可点元素**——真正需要审计的是各调用点注入的 `trailing`（多为「查看更多」`TextButton`，落在 C1/C2 的同一类问题里）。

### 1.6 非按钮但影响按钮观感的动效

| 位置 | 现状 | 判定 |
|---|---|---|
| `shared/presentation/widgets/state_dot.dart:22` | 直播红点 1200ms 循环呼吸，`Curves.easeInOut` | ⚠️ 时长与曲线都不在 `AppMotion` 里，且**未在 `DESIGN.md` §5.1 登记**；属状态指示不是按钮，**建议只登记不改值**（改值会动 golden） |
| `play_view.dart:481` | 控制条 `AnimatedOpacity(200ms)`（裸值） | ⚠️ 200ms 不在 `AppMotion.fast(150)` / `normal(250)` 档内 |
| `chat_tab.dart:403` | 回到底部滚动 `220ms` + `Curves.easeOut`（裸值） | ⚠️ 是 `ScrollController.animateTo`，不是组件状态过渡；**建议只登记** |
| `platform_strip.dart:252` | 平台 tab `AnimatedContainer(fast, 无 curve)` | ❌ `Curves.linear` |
| `compact_switch.dart:30/39/42` | 开关轨道/滑块 `AnimatedContainer/AnimatedAlign(fast, 无 curve)` | ❌ `Curves.linear`——且这是**全局设置里最常用的控件** |
| `play_immersive_side_sheet.dart:56/75` | `AnimatedOpacity` + `AnimatedSlide(normal + curve)` | ✅ 合规 |

### 1.7 度量证据：状态色的 APCA 与 OKLCH

用 OKLCH 转换 + APCA（签名约定：正值 = 深字浅底，负值 = 浅字深底；下表给 **绝对值**）实测现有状态色。
`oklch-color-space` 的 "Compose to a contrast target — don't pick L and test" 明确反对"挑一个色再测"，
下面这张表正是**现状是"挑出来的"**的证据。

| 用途 | 深色值 | \|Lc\| | 浅色值 | Lc | 判定 |
|---|---|---|---|---|---|
| 关注 chip 常态文字 | `#FFB8B8` on `#582626` | **52.8** | `#A83838` on `#FBECEC` | 78.3 | ❌ 深色低于 Lc 60（次级门槛），远低于 Lc 75（正文最低）；字号是 10px 小字 |
| 关注 chip 已关注文字 | `#FFE0E0` on `#4F2C2C` | 76.9 | `#8C2424` on `#F8E5E5` | 76.0 | ✅ |
| 超关 chip 常态文字 | `#C9A0F0` on `#442D5B` | **31.5** | `#6F3FA8` on `#F2ECFA` | 80.8 | ❌❌ **全库最低的按钮标签**，只有次级门槛的一半 |
| 超关 chip 已超关文字 | `#E9D5FF` on `#413052` | 65.2 | `#592C87` on `#EDE4F4` | 75.3 | ⚠️ 深色勉强过 60，未到 75 |
| 「直播提醒中」active 文字 | `accent #7C4DFF` on `accent@14% over #1F1F1F`(=`#38296D`) | **17.0** | — | — | ❌❌❌ 实际不可读 |
| 顶栏/底栏 active 标签 | `accent #7C4DFF` on `surfaceSoft #141414` | **17.3** | — | — | ❌❌❌ |
| `RetryButton` 前景 | `accent #7C4DFF` on `background #181818` | **17.3** | — | — | ❌❌❌ |
| 「直播提醒」**禁用**文字 | `textSecondary@0.55 over surface` → `#979797` | **13.8** | — | — | ❌❌ 正是 `visual-polish` 说的 "A disabled state built from opacity alone often drops its label under the contrast floor" |
| `textSecondary`（全局次级文字） | 白 55% on `surface #1F1F1F` | 41.8 | — | — | ⚠️ 低于 Lc 60；**属既有基线，见 §六 裁决点 10** |
| `textPrimary` | 白 87% on `surface` | 86.8 | — | — | ✅ |
| `statAudience` / `statVip` / `statSvip`（10px） | on `surface` | 61.3 / 66.3 / 53.1 | — | — | ⚠️ 10px 小字，均未到 75 |

| 档位 | L | 用途 |
|---|---|---|
| `surfaceSoft` | 0.1913 | 顶栏 / 底栏底（“更深一层”） |
| `background` | 0.2090 | 页面画布 |
| `surface` | 0.2393 | 卡片 / 浮层 |
| `surfaceRaised` | 0.2850 | **`DESIGN.md` §4.2 指定的 hover 档** |

按这张表，hover 必须从当前底**向 L 更大处**走。实测结果：

| 位置 | 底 | hover | 方向 | 判定 |
|---|---|---|---|---|
| 桌面顶栏 logo / 导航项 / 平台网格 / 账号 | `surface` 0.239 | `surfaceSoft` **0.191** | **变暗** | ❌ 反了，且与 §4.2 不符 |
| 移动底栏导航项 | `surfaceSoft` 0.191 | `surface` 0.239 | 变亮 | ⚠️ 方向对，但只走一档（§4.2 要的是 `surfaceRaised`） |
| 移动平台条 tab | `surfaceSoft` 0.191 | `surfaceRaised` 0.285 | 变亮 | ✅ |

> 这是“43 处 InkWell 只有 8 处写了 `hoverColor`、且用了 4 种底色”的**具体危害**：
> 同一个 hover 语义在桌面顶栏是“压暗”，在移动底栏是“提亮”。详见 §二 G2 证据 ④。

**OKLCH 色相/彩度实测**（`chroma-harmonization` 的审计口径）：

| token | L | C | H |
|---|---|---|---|
| `playFollowBg` | 0.3391 | **0.0742** | 21.8 |
| `playSuperBg` | 0.3466 | **0.0816** | 305.6 |
| `playFollowBorder` | 0.4422 | 0.0539 | 19.4 |
| `playSuperBorder` | 0.4476 | 0.0529 | 306.4 |
| `playFollowText` | 0.8485 | **0.0827** | 18.9 |
| `playSuperText` | 0.7716 | **0.1193** | 307.3 |
| `accent` | 0.5786 | **0.2468** | 288.2 |

两条可验证的观察：

1. **`playSuperText` 是这一对里的"霓虹离群值"**：C=0.1193 比 `playFollowText` 的 0.0827 高 **44%**。
   按 `chroma-harmonization` 的算法（每个 stop 取跨色相最大 chroma 的**最小值**作 ceiling），
   同 stop 的彩度应被收到较低者——这解释了为什么"超关"在并排时明显比"关注"更"艳"。
   注意两个 border 反而已经齐了（0.0539 / 0.0529），说明**不齐的只有文字色**。
2. **选中态反而掉彩度**：`playFollowBg` C=0.0742 → `playFollowBgActive` C=0.0520；
   `playSuperBg` C=0.0816 → `playSuperBgActive` C=0.0615。
   即"已关注/已超关"这个**更需要强调**的状态比常态**更灰**。这不是 bug（是 web 逐字复刻），
   但它是"状态切换缺少形状/层级补偿"的根因——现状只靠换色，而换的这个色还在减彩度。

---

## 二、缺口清单（按严重度排序）

### G1 — focus 态全项目零实现（阻断 Windows 键盘可达性验收）

- 证据：`grep -rn "AppFocus" lib/src test` → 只命中 `design_tokens.dart:254`（定义处，盘点时为 202）
  与 `test/shared/design_tokens_test.dart:175-191`（契约断言）；组件层 **0 引用**。
  `DESIGN.md` §4.2 自认"`AppFocus` 目前只有 token，组件默认聚焦态仍是 Material 默认样式"。
- 影响：`button-states` 说 focus "is a keyboard navigation requirement (WCAG 2.2). It must be visible and must not rely on the hover style alone — keyboard users do not trigger hover." 现状既不可见（只有 M3 的 10% 叠加），也无外扩环。
- 附带：`play_view.dart:1069` 有 `Focus(autofocus: true)` + `FocusNode`，是**唯一**有焦点语义的地方，但同样无可见环。
- 附带：`Semantics(button: true)` = 0，屏幕阅读器不知道这些是可点元素。

### G2 — hover / pressed 没有 token 纪律，"看着有其实不可控"

- 证据 ①：43 处 `InkWell` 只有 8 处显式 `hoverColor`，且用了 4 种不同底色
  （`surfaceSoft` / `surface` / `surfaceRaised` / M3 默认）。`DESIGN.md` §4.2 只定义了 `surfaceRaised` 一种。
- 证据 ②：`playFollowBgHover`（`#512626`）与 `playSuperBgHover`（`#402C54`）在 `lib/src` 组件层
  **零引用**（`grep -rn playFollowBgHover lib/src | grep -v zishu_tokens.dart | grep -v design_tokens.dart` → 0 条）。
  `DESIGN.md` §2 把它们登记为"6 态"的一部分，但**这两个最重要的表现型按钮根本没有 hover 态**。
- 证据 ③：pressed 除了两处 chip 的 `*BgActive` token 外，全靠 InkWell 涟漪，无 token 化反馈。
- 证据 ④（**最具体的一条**）：**桌面顶栏的 hover 方向是反的**。
  `top_nav.dart:44-45` 的顶栏底是 `tokens.surface`（`#1F1F1F`，L=0.239），
  而 `:207`（logo）/ `:315`（`_NavAction`）/ `:250`（`_PlatformTabs` 平台网格）/ `user_area.dart:141`（账号）
  的 `hoverColor` 全是 `surfaceSoft`（`#141414`，**L=0.191**）——即 hover 时元素**比它所在的底栏更暗**，
  读起来是个“洞”而不是高亮；而 `bottom_nav.dart:144` 是 `surfaceSoft` 底 → `surface` hover（**提亮**），
  `platform_strip.dart:158/180`（移动端平台条）是 `surfaceSoft` 底 → `surfaceRaised` hover（**提亮**）。
  同一套“hover”在桌面顶栏与移动底栏上**方向相反**，且都与 `DESIGN.md` §4.2 的
  `hover → surfaceRaised`（`#2A2A2A`，L=0.285，最亮）不符。
- 影响：`visual-polish` 的"present but indistinguishable"——hover 和 pressed 在多数元素上渲染一致。
  另外“hover 变暗”还额外输了一层：`designing-elite-ui` 原则 6 要的是 "unmistakable active states"，
  而变暗在近黑底上很难读成“高亮”。

### G3 — `GestureDetector` 造成"动了但没反馈"

- 证据：`mouseCursor` / `SystemMouseCursors` 全库 **0** 处；7 处 `GestureDetector`：
  `compact_switch.dart:28`、`follow_entry_card.dart:96`、`follow_entry_row.dart:129`、
  `search_result_tile.dart:156`、`play_view.dart:1074`、`play_immersive_side_sheet.dart:64`（+ 1 处 `Listener`）。
- 最严重的是 `CompactSwitch`：它是全局设置里出现频率最高的控件，却
  **无 hover 底色、无指针光标、无按压视觉、无 focus、无 disabled**。
- 依据：`designing-elite-ui` 原则 6「Interaction feels alive before the click」；`button-states` checklist「Does `cursor: pointer` appear on all interactive elements at rest?」。

### G4 — 曲线纪律破裂：4 处 `AnimatedContainer` 落到 `Curves.linear`

- 证据：`compact_switch.dart:30/39/42`、`platform_strip.dart:252` 未传 `curve` → Flutter 默认 `Curves.linear`。
- 依据：`motion-and-storytelling`「Never use `linear` for UI motion — it reads as mechanical and unfinished」；
  `micro-interactions`「Does the toggle/switch use a spring easing curve, not linear?」——**开关正好是重灾区**。

### G5 — loading 态几乎全缺

- 证据：11 处 `strokeWidth: 2` 里只有 1 处在按钮内（`user_area.dart:304`）。该处同时做对了三件事：
  宽度稳定（14×14 `SizedBox` 替换文字）、`onPressed: null` 防重复提交、完成后回 rest——**可作为范式**。
- 缺口点：`_SideTextAction`（「跳转」，`async` 打开外链）、`RetryButton`（重试触发异步 reload）、
  `parse_benchmark_view`（`_running` 只让按钮变灰）。
- 依据：`button-states`「When a button triggers an async action, replace the label with a spinner and prevent re-submission」+
  「Keep the button width stable during loading — avoid layout shift」+「The cursor does not change while loading」。
- 附带：`DESIGN.md` §4.2 的 disabled 口径是"`textSecondary` 文字 + 不响应指针；**不额外加灰罩**"，
  但 `_SideTextAction` 现在用 `textSecondary.withValues(alpha: 0.55)`（实测 \|Lc\| 13.8）——**第三种口径**。

### G6 — chip 选中过渡不一致（同一件事三种实现）

- 有动画：`follow_platform_filter.dart:133`（`AnimatedContainer(fast + curve)`）✅
- 无动画：`search_platform_chips.dart:52`、`my_category_flyout.dart:342/374`（裸 `Container`）❌
- 有动画但线性：`platform_strip.dart:252`（`AnimatedContainer(fast)`）❌
- 依据：`motion-and-storytelling` 的 "The Gutter"——"A smooth transition lets the user's brain construct a coherent mental model. A jarring jump forces them to re-orient."

### G7 — 两个"反馈方向反了"的地方

- ① 选中态掉彩度（§1.7 观察 2）：`已关注` 比 `未关注` 更灰。
- ② `FollowButton`（`follow_button.dart:22`）用 `AppMotion.normal`(250ms) 做状态切换，
  而 `_SideActionButton`（侧栏同语义按钮）**完全没有过渡**。同一个"关注"动作，两处手感不同。

### G8 — 无 reduce-motion 处理

- 证据：`MediaQuery.disableAnimationsOf` / `AccessibilityFeatures.disableAnimations` 全库 0 处。
- 依据：`micro-interactions`「Respect `prefers-reduced-motion` — always」；`motion-and-storytelling` 把它列为 Practical Rule 1。

### G9 — 工程卫生（不影响观感，但影响本轮可验证性）

- `tool/check_design_tokens.dart` 无 `raw_duration` 规则 → 裸时长漂移不被拦（已有 5 处）。
- `test/ui/failures/` 残留 **28 张**（7 组 golden × 4 张）2026-09-22 09:07 的差异图
  （`follow_style_card/row`、`hover_follow_grid/my_category/platform_categories`、`play_style_follow/recommend`），
  会让后续 `flutter test test/ui` 的差异判定难以解读。
- `test/ui/hover_shot_test.dart` 与 `test/ui/follow_style_shot_test.dart` 文件头自称
  "临时截图用例…用 `--update-goldens` 生成；生成后本文件即删除"，但它们是**全库仅有的 7 条 golden**。

---

## 三、提案

### 3.1 分档与动效强度上限

分档依据 `designing-elite-ui` 原则 3「Restraint beats richness」——**克制不是全项目的统一要求，
而是要按语义分层**：越是"工具型/高频/危险"的操作越克制，越是"表达型/低频/情绪化"的操作越允许动效。

| 档 | 覆盖元素 | 允许的动效强度上限 | 明确禁止 |
|---|---|---|---|
| **克制型**<br>表单 / 设置 / 危险操作 | C1–C8：登录对话框、`CompactSwitch`、`FollowIconAction(danger)`、删除所选、解析基准、设置项 | ① 颜色 / 描边 / 不透明度过渡（`AppMotion.fast` + `AppMotion.curve`）<br>② focus ring<br>③ loading 用进度指示<br>④ disabled 只改颜色 + 光标 | 位移、缩放、阴影、光晕、图标动画、任何"庆祝" |
| **标准型**<br>导航 / 列表项 | N1–N20：顶栏、底栏、平台条、抽屉、房卡、关注卡/行、搜索结果、各类 chip | 克制型 +<br>⑤ hover 底色档位过渡（`surface` → `surfaceRaised`）<br>⑥ selected 可用 `AppElevation.accentGlow`（`platform_strip` 已落地，作为范式）<br>⑦ 内层图标位移 ≤ 2px（`motion-and-storytelling` 原则 8 Secondary Action） | 整体缩放、圆角/尺寸变化、循环动画、逐项 stagger（列表可能上百项） |
| **表现型**<br>关注 / 超关 / CTA / 空态 | E1–E8：侧栏关注与超关、移动端 meta bar、主播页 `FollowButton`、错误空态 `RetryButton(outlined)` | 标准型 +<br>⑧ 形状（圆角 / 描边宽）+ 颜色**组合**过渡<br>⑨ 内层图标一次性脉冲（≤1.15，`AppMotion.normal`）<br>⑩ 按压缩放 0.97（**待裁决，见 §六-1**）<br>⑪ loading 原地替换图标 | 循环动画、confetti（除"首次关注"这类里程碑且需裁决）、玻璃拟态 / 大投影、**新增强调色** |

> 三档的边界不是"好看程度"，而是**语义风险**：危险操作必须"冷静、可撤销"（`designing-elite-ui` 原则 1
> "Reserve a color for ONE meaning only"——`error` 只属于危险），导航项已被用户按位置记忆
> （`micro-interactions` Sacred Rule + `designing-elite-ui` 原则 5 "The canvas is stable"）。

### 3.2 逐态方案

下表所有时长/曲线**只从 `AppMotion` 取**，elevation **只从 `AppElevation` 取**，不发明新值。

#### default（rest）

| 项 | 克制型 | 标准型 | 表现型 |
|---|---|---|---|
| 底色 | `tokens.surface` / `surfaceSoft` | `tokens.surface` | 关注 `playFollowBg` / 超关 `playSuperBg` |
| 描边 | `tokens.border` | `tokens.border` | `playFollowBorder` / `playSuperBorder` |
| 圆角 | `AppRadius.allSm`(4) | `allSm`(4) / `allMd`(8)（卡片）/ `allPill`（chip、头像） | `allSm`(4) |
| 前景 | `tokens.textPrimary` | rest `textSecondary` / selected `accent` | `playFollowText` / `playSuperText` |
| 光标 | `SystemMouseCursors.click` | 同左 | 同左 |
| 动效 | 无（rest 不动） | 无 | 无 |

**新增要求**：`systemMouseCursors.click` 必须显式出现在所有可点元素上——`InkWell` 会自动给，
但 `GestureDetector` 不会，需补 `MouseRegion`（这是 G3 的修法）。

#### hover

| 项 | 方案 | token |
|---|---|---|
| 触发条件 | 仅 `(hover: hover) and (pointer: fine)`（`DESIGN.md` §8 已定） | — |
| 底色 | `surface` → `surfaceRaised`（`DESIGN.md` §4.2 原文） | `tokens.surfaceRaised` |
| 表现型底色 | `playFollowBg` → `playFollowBgHover`；`playSuperBg` → `playSuperBgHover` | **token 已存在、零引用，直接用** |
| 描边 | **不动**（避免发明 `borderHover` token） | — |
| 动效 | `duration: AppMotion.fast, curve: AppMotion.curve` | `AppMotion.fast` / `AppMotion.curve` |
| 禁止 | 位移、缩放、elevation 变化（elevation 变化见 §六-3 裁决点） | — |

**壳层统一**：现有 4 种 hover 来源收敛为 `surfaceRaised`（`DESIGN.md` §4.2 唯一口径）。
`top_nav` / `bottom_nav` / `user_area` 的 `surfaceSoft`、`bottom_nav` 的 `surface` 都要改。

> ⚠️ **这不是纯粹的“统一”，而是修一个方向错误**：桌面顶栏底是 `surface`（L=0.239），
> 现在 hover 到 `surfaceSoft`（L=0.191）是**变暗**；`surfaceRaised`（L=0.285）才是变亮。
> 也就是说顶栏系（logo / 导航项 / 平台网格 / 账号）的 hover 现在是“往下压”的，
> 而移动底栏是“往上抬”的。详见 §二 G2 证据 ④。
> 这是**有意改动**，会动 golden；也意味着"壳层 hover 观感会比现在亮一档"，需真机确认（§5.4）。

#### active / pressed

| 项 | 方案 | token |
|---|---|---|
| 底色 | 在 hover 档再压一档：表现型 → `playFollowBgActive` / `playSuperBgActive`（已存在、已用）；标准型 → `surfaceRaised` + InkWell 的 M3 pressed overlay（**不新增 `surfacePressed`**） | `playFollow*Active` / `playSuper*Active` |
| 前景 | 表现型 → `playFollowTextActive` / `playSuperTextActive`（已存在、已用） | 同上 |
| 动效 | `AppMotion.fast` + `AppMotion.curve` | 同上 |
| 缩放 | **默认不做**（`micro-interactions` Sacred Rule「No Scaling」）；表现型可选 `scale(0.97)`，见 §六-1 | `AppMotion.fast` |
| 合规替代（若裁决不做缩放） | 叠一层 `AppElevation.hairline`（黑 35%、blur 0、spread 1）表达"陷下去"——这是 `micro-interactions` 自己给的 `box-shadow: inset …` 的 Flutter 近似 | `AppElevation.hairline` |

> **为什么"标准型不新增 pressed 底色"**：`DESIGN.md` §4.2 写的是"在 hover 基础上再压一档"，但项目里
> `surfaceRaised` 已是抬升顶档，再压就要新增第 5 个灰阶——而 `visual-polish` 的 "Silent failures"
> 警告过 "The fix landed as a magic number"。用 InkWell 的 M3 pressed overlay 是现成且可打断的，
> 先不扩灰阶。若产品认为压感不够，再按 §六-6 走新 token 流程。

#### focus

| 项 | 方案 |
|---|---|
| 视觉 | `AppFocus.ring(tokens.accent)` —— 2px 实环 + 2px 间隙，**外扩、不占布局** |
| token | `AppFocus.ring` / `AppFocus.ringWidth`(2) / `AppFocus.ringOffset`(2)（**零新 token**） |
| 只在键盘导航时显示 | Flutter 没有 CSS 的 `:focus-visible`；等价物是 `FocusManager.instance.highlightMode == FocusHighlightMode.traditional`。鼠标点击时**不应**出环 |
| 实现原语 | `FocusableActionDetector`（拿 `onShowFocusHighlight`）或 `Focus` + `MouseRegion`，把环挂到 `BoxDecoration.boxShadow` |
| 与 Material 默认叠加的关系 | 需同时把该组件的 `Material.focusColor` 置为 `Colors.transparent`，否则 M3 的 10% 叠加会和外扩环叠成"两层"。**不要**全局改 `ThemeData.focusColor`（会影响 `TextField` 等） |
| 不改什么 | **不改 fill**（`button-states`：「Focus… no change to fill」） |
| 依据 | `button-states` "Focus State"：`outline-offset: 2–4px`、"Never use `outline: none` without a replacement focus style"；`designing-elite-ui` 原则 8「never ship a clipped focus ring」 |

#### disabled

| 项 | 方案 |
|---|---|
| 文字 / 图标 | `tokens.textSecondary`（`DESIGN.md` §4.2 原文） |
| 底 / 描边 / 形状 | **不变**（`button-states`：「Do not change the shape or size of a disabled button — only colour and cursor change」） |
| 光标 | 不设 click（`InkWell` 在 `onTap == null` 时自动 `MouseCursor.defer` ✅） |
| 不加灰罩 | `DESIGN.md` §4.2 明确「不额外加灰罩」——**这与 `button-states` 的 `opacity: 0.4` 直接冲突，以 `DESIGN.md` 为准**（项目约束 > skill） |
| 口径统一 | `_SideTextAction` 现在的 `textSecondary.withValues(alpha: 0.55)`（实测 \|Lc\| 13.8）是第三种口径，**改回 `textSecondary`**（\|Lc\| 41.8），或把 0.55 登记为 token（不推荐，见 §六-4） |
| 可达性 | 保留 `Tooltip` 说明"为什么不能点"——`_SideTextAction` 已做（`'关注后可开启开播提醒'`）✅，值得推广 |

#### loading

| 项 | 方案 |
|---|---|
| 结构 | `Stack` + `Opacity` 交叉淡入**保住 label 的盒子**，或固定 `SizedBox` 宽度。**禁止**直接换 `child`（会让按钮跳宽） |
| 指示器 | 14×14 `CircularProgressIndicator(strokeWidth: 2)`，颜色 = 当前 `fg` |
| 交叉淡入 | `AppMotion.fast` + `AppMotion.curve` |
| 交互 | `onTap: null`（= CSS 的 `pointer-events: none`） |
| 光标 | **不变**（`button-states`：「The cursor does not change while loading. It signals affordance, not progress」） |
| 不透明度 | `button-states` 说 0.7；本项目与 disabled 口径保持一致，**只换指示器、不加灰罩** |
| 完成 | 成功 / 失败都回 rest |
| 长任务 | 配状态文案（`play_side_panel.dart` 已有 SnackBar 习惯，可复用） |
| 依据 | `button-states` "Loading State" 全节 + `motion-and-storytelling` 原则 4「Never animate layout properties (`width`, `height`, `padding`…)」 |

### 3.3 "更酷炫"的具体手段

> 全部手段都**不新增强调色**、不引入玻璃拟态 / 大投影 / 渐变滥用（`DESIGN.md` §1）；
> 6 个手段里 **5 个零新 token**。

---

#### 手段 1：关注 / 超关 chip 的"形状 + 颜色"组合过渡 + 图标一次性脉冲（表现型）

**改哪个文件**
- `lib/src/features/play/widgets/side_panel/side_panel_header.dart` → `_SideActionButton`（:463）
- 同款：`lib/src/features/play/widgets/play_meta_bar.dart` → `_MetaActionButton`（:369）

**现状问题**：`Material(color: background)` 是**直接跳变**——`button-states` 与 `motion-and-storytelling`
的 "Cut vs Dissolve" 都说"两个相关状态"（关注 ↔ 已关注）应该 crossfade，不该硬切；
"The Gutter" 更是直说硬切 "forces them to re-orient"。

**改法**
1. 把 `Material(color: background)` 换成
   `AnimatedContainer(duration: AppMotion.fast, curve: AppMotion.curve, decoration: BoxDecoration(color:…, borderRadius: AppRadius.allSm, border: Border.all(color:…)))`
   ——**与 `follow_button.dart:22` 同一写法**，顺手收敛 G7-② 的两处不一致。
   内部保留 `Material(color: Colors.transparent)` + `InkWell` 承载涟漪。
2. 给内层图标套 `AnimatedSwitcher(duration: AppMotion.fast)`，
   已关注时对**图标**做一次性 1.0 → 1.15 → 1.0（`TweenAnimationBuilder`，`AppMotion.normal`）。
   这是 `micro-interactions` 的 "A stamp pressing paper → Inner element shift (e.g. icon nudge) **without shifting button bounds**"。
3. 可选形状变化（**需裁决，见 §六-2**）：已关注时圆角 `AppRadius.allSm`(4) → `AppRadius.allPill`(999)。
   `DESIGN.md` §7 明确允许 chip 用 `AppRadius.pill`，且圆角动画不改变盒子尺寸（59px 宽不变）。

**用哪些 token**：`playFollowBg` / `playFollowBgHover` / `playFollowBgActive` / `playFollowBorder` /
`playFollowText` / `playFollowTextActive`（超关同族 `playSuper*`）+ `AppMotion.fast` / `AppMotion.normal` /
`AppMotion.curve` + `AppRadius.allSm`（`allPill` 若裁决通过）。

**预期观感**：点下去那一刻底色 / 描边 / 文字**一起"长"过去**而不是闪过去；心形或星形在按钮里弹一下；
鼠标划过时 chip 先用已登记的 hover 底色"预告"即将发生什么。

**是否需要新 token**：**不需要**（`playFollow*Hover` / `playSuper*Hover` 两个死 token 就此接线）。

**依据**：`button-states` "Deriving State Colours Algorithmically"（状态色由基色推导，不该乱挑）；
`motion-and-storytelling` 原则 8 Secondary Action、原则 6 Ease In/Out、Cut vs Dissolve、The Gutter；
`micro-interactions` 的 "Heart pulse on like" keyframe（本项目把 1.25 收敛到 1.15，
因为 `motion-and-storytelling` 原则 10 说 "The exaggeration is 10–15%, not theatrical"）。

---

#### 手段 2：hover 光晕复用 `AppElevation.accentGlow`（标准型 selected + 表现型 hover）

**改哪个文件**
- 范式已存在：`lib/src/app/shell/platform_strip.dart:268`（`_PlatformTabs` 的 34×34 平台 tab；注意 `design_tokens.dart` 的 `accentGlow` 注释把来源写成 `:269`，实际代码在 `:268`，差一行）
- 新增接线点：`lib/src/app/shell/top_nav.dart`（`_NavAction` :313）、
  `lib/src/app/shell/bottom_nav.dart`（`_BottomItem` :143）、
  `lib/src/features/play/widgets/side_panel/side_panel_header.dart`（`_SideActionButton`）

**现状问题**：`accentGlow` 全项目只用在一个地方（平台 tab 选中态），其余 hover 都只有底色变化。

**改法**
- hover 时 `boxShadow: AppElevation.accentGlow(tokens.accent)`；
  表现型用 `playFollowBorder` / `playSuperBorder` 作色源（让光晕跟 chip 同色系）。
- **必须**配 `AnimatedContainer(duration: AppMotion.fast, curve: AppMotion.curve)`，
  否则光晕是"跳"出来的（`motion-and-storytelling` 原则 6）。

**用哪些 token**：`AppElevation.accentGlow`（**零新 token**）+ `AppMotion.fast` / `AppMotion.curve`。

**边界说明**：`DESIGN.md` §1 禁的是"玻璃拟态**大**投影"；`accentGlow` 是 blur 8 / alpha 0.22 的小光晕，
且已在 §6 登记为四档之一——属**合规复用**，不是新增 elevation 语义。
但 `DESIGN.md` §4.2 的 hover 行只写了"颜色/边框过渡，不位移"，**没有** elevation 变化，
所以这仍是"扩语义"，需登记 §10（见 §六-3）。

**预期观感**：鼠标扫过导航时，选中项"亮起来"而不是"变亮"——有层次、有方向感，但不发光污染。

**是否需要新 token**：**不需要**。若真机确认 22%/blur 8 太强，可选新增
`AppElevation.hoverGlow(Color)` = 同色 14%、blur 6、offset(0, 1)——
**但新增 elevation 档必须改 `DESIGN.md` §6 + 加 `test/shared/design_tokens_test.dart` 契约断言**。

**依据**：`visual-polish` 第 5 条「Theme parity beyond colour」——"A drop shadow is a light-surface device —
over near-black there is little left to darken, so elevation has to come from surface lightness"
（**这条同时是本方案的警告**：`#181818` 上光晕的实际可见度必须真机验证，见 §5.4）；
`designing-elite-ui` 原则 6「hover highlights… unmistakable active states」。

---

#### 手段 3：按压缩放 / 回弹 0.97（表现型，**待裁决**）

**改哪个文件**：`side_panel_header.dart` `_SideActionButton`、`follow_button.dart` `FollowButton`、
`retry_button.dart`（`outlined` 变体）

**改法**：外层 `AnimatedScale(duration: AppMotion.fast, curve: AppMotion.curve)`，
按下 `0.97`、抬起回 `1.0`。

**⚠️ 这是一个 skill 之间直接冲突的点，必须裁决：**

| skill | 条文 | 立场 |
|---|---|---|
| `button-states` | "Scale on Active (Optional)… `transform: scale(0.97)`… Keep the scale value between `0.95–0.98`. Below `0.95` feels like the button is breaking." | ✅ 允许 |
| `motion-and-storytelling` | 原则 1「Squash and Stretch」`button:active { transform: scale(0.96) }`——"Use sparingly — **reserved for primary CTAs** and satisfying confirmations." | ✅ 允许（限 CTA） |
| `micro-interactions` | **"The Sacred Rule of Component Stability"**：**"No Scaling: Never use `transform: scale()` on hover or click for buttons.** It causes visual vibrating and can feel 'squishy' rather than premium." | ❌ 禁止 |

**本提案的建议**：**默认不缩放**，理由是 `micro-interactions` 的 Sacred Rule 是唯一带 "Never" 的绝对表述，
且它给出的理由是"用户光标下的 UI 移动会让人觉得不可预测"——这在本项目的**高密度工具型界面**（`DESIGN.md` §1）
里比在落地页里更致命。若产品坚持，只对**表现型且是 CTA 语义**的元素启用，并把决定登记进 `DESIGN.md` §10。

**合规替代**（若裁决不做缩放）：pressed 时叠 `AppElevation.hairline`（黑 35%、blur 0、spread 1），
表达"按下去陷了一层"——这正是 `micro-interactions` 自己给的
`box-shadow: inset 0 2px 4px rgba(0,0,0,.1)` 的 Flutter 近似。

**用哪些 token**：`AppMotion.fast` / `AppMotion.curve`（或 `AppElevation.hairline`）（**零新 token**）。

**预期观感**：按下时按钮"被按进去"——但代价是按钮在视觉上改变了外框尺寸，与 Sacred Rule 相悖。

---

#### 手段 4：loading 用进度指示原地替换文字（克制型 + 表现型）

**改哪个文件**
- `lib/src/features/play/widgets/side_panel/side_panel_header.dart` → `_SideTextAction`（:343）：
  「跳转」的 `onOpenExternal` 是 `async`，现在点下去**完全没反应**，只有失败才弹 SnackBar
- `lib/src/shared/presentation/widgets/retry_button.dart`：重试会触发异步 reload
- **参照实现（已经做对，直接照抄）**：`lib/src/app/shell/user_area.dart:294-305`

**改法**
1. `_SideTextAction` 增 `bool loading` 字段；`loading` 时 `onTap: null`。
2. 用 `Stack` 保宽交叉淡入：`Stack(children: [Opacity(opacity: loading ? 0 : 1, child: Text(label)), if (loading) Center(child: SizedBox(14, 14, child: CircularProgressIndicator(strokeWidth: 2)))])`
   —— 盒子尺寸 = label 的尺寸，**不跳宽**（`button-states`：「Keep the button width stable during loading」）。
3. 交叉淡入用 `AppMotion.fast` + `AppMotion.curve`（`micro-interactions` 的
   "Skeleton → Content Transition" 说 "do not flash it in. Fade it over… at 150–200ms"）。
4. 完成后回 rest（成功 / 失败都回）。

**用哪些 token**：`AppMotion.fast` / `AppMotion.curve`。
建议新增 `AppSpinner.size = 14` / `AppSpinner.strokeWidth = 2`（当前 `strokeWidth: 2` 散落 **11 处**，
14×14 手写 1 处）——**新增 token 需改 `DESIGN.md` §4.3 + 契约测试**，见 §六-6。

**预期观感**：点「跳转」不再"点了没反应"，小圈**在原地**转，按钮宽度一动不动；
重试按钮同理——这直接消灭 G5 里"最像 bug 的交互"。

**是否需要新 token**：可选 `AppSpinner.*`（见上）。核心方案零新 token。

**依据**：`button-states` "Loading State" 全节（含 "The cursor does not change while loading"
与 "For long-running operations, pair with a status message"）；
`motion-and-storytelling` 原则 4「Never animate layout properties」；
`micro-interactions` "Skeleton → Content Transition"。

---

#### 手段 5：chip 选中过渡统一（标准型，消除"跳变 vs 动画"不一致）

**改哪个文件**
- `lib/src/features/search/widgets/search_platform_chips.dart:52`（裸 `Container` → `AnimatedContainer`）
- `lib/src/app/shell/my_category_flyout.dart:342/374`（同上）
- 范式：`lib/src/features/follow/widgets/follow_platform_filter.dart:133`（已是 `AnimatedContainer(fast + curve)`）

**改法**：`Container` → `AnimatedContainer(duration: AppMotion.fast, curve: AppMotion.curve)`，
只动画 `color` 与 `border`（**不动 padding / width**——`motion-and-storytelling` 原则 4）。

**用哪些 token**：`AppMotion.fast` / `AppMotion.curve`（**零新 token**）。

**预期观感**：搜索页 / 我的分类的 chip 点选时底色与描边一起过渡；与关注页 chip 手感一致。

**依据**：`motion-and-storytelling` "The Gutter"；`visual-polish` 第 4 条（"present but indistinguishable"）。

---

#### 手段 6（工程向）：`CompactSwitch` 补齐 hover / 光标 / curve / disabled

**改哪个文件**：`lib/src/shared/presentation/widgets/compact_switch.dart:28`

**改法**
1. `GestureDetector` → `MouseRegion(cursor: SystemMouseCursors.click)` 包一层（或直接换 `InkWell`）。
2. 三处 `AnimatedContainer` / `AnimatedAlign` 补 `curve: AppMotion.curve`
   （当前默认 `Curves.linear`，见 G4）。
3. `onChanged` 改为可空 → 支持 disabled 态。
4. `const offBorder = Color(0xff3a3a3a)` → `tokens.border`
   （盘点时它是裸值，顺带可把守卫基线里 `compact_switch.dart|raw_color|Color(0xff3a3a3a)` 这条**清零**，
   `AGENTS.md` 要求基线只降不升）。
   > **✅ 并发轨已完成（见开头快照节）**：现已改为 `AppColors.border` /
   > `AppOnBright.white`。本步可直接删掉，只做 1–3 与 5。
5. hover 时轨道底色给一档 `tokens.surfaceRaised`（克制型允许的上限）。

**用哪些 token**：`AppMotion.curve` / `tokens.border` / `tokens.surfaceRaised`（**零新 token**）。

**预期观感**：这是全局设置里出现频率最高的控件，补上指针光标、hover 底色与正确的缓动曲线后，
整个设置页的"手感年龄"会明显下降。

**依据**：`micro-interactions` "Toggle / Switch"——"The cubic-bezier `(0.34, 1.56, 0.64, 1)` produces a spring effect…
This is the difference between a switch that feels cheap and one that feels premium"；
`motion-and-storytelling` 原则 6「Never use `linear`」；`designing-elite-ui` 原则 6。

> **关于弹簧曲线**：`micro-interactions` 推荐的是带 overshoot 的 `Cubic(0.34, 1.56, 0.64, 1)`，
> 而 `AppMotion` 只有 `Cubic(0.16, 1, 0.3, 1)`（无 overshoot）。本提案**先复用 `AppMotion.curve`**
> （零新 token、零风险）。是否新增 `AppMotion.curveSpring` 见 §六-6。

### 3.4 token 变更清单

| 类型 | 名称 | 值 | 是否必需 | 代价 |
|---|---|---|---|---|
| 复用 | `AppElevation.accentGlow(Color)` | 已有（强调色 22%、blur 8、y+2） | 是（手段 2） | 无 |
| 复用 | `playFollowBgHover` / `playSuperBgHover` | 已有（`#512626` / `#402C54`；浅色 `#F7E1E1` / `#ECE2F5`） | 是（手段 1） | 无（**从死 token 变活**） |
| 复用 | `AppFocus.ring(accent)` | 已有（2px 环 + 2px 间隙） | 是（G1） | 无 |
| 复用 | `AppElevation.hairline` | 已有（黑 35%、blur 0、spread 1） | 可选（手段 3 的替代方案） | 无 |
| **可选新增** | `AppSpinner.size` | `14` | 建议（手段 4，消除 11 处裸 `strokeWidth` + 1 处裸 `14`） | `DESIGN.md` §4.3 + 契约测试 |
| **可选新增** | `AppSpinner.strokeWidth` | `2` | 同上 | 同上 |
| **可选新增** | `AppElevation.hoverGlow(Color)` | 同色 14%、blur 6、offset(0, 1) | 仅当真机确认 `accentGlow` 太强 | `DESIGN.md` §6 + 契约测试 |
| **可选新增** | `AppMotion.curveSpring` | `Cubic(0.34, 1.56, 0.64, 1)` | 仅当裁决要求开关有 overshoot | `DESIGN.md` §5.1 + 契约测试 |

**结论：6 个手段里 5 个可以零新 token 落地。** 这一点很重要——`oklch-color-space` 的
"Primitive ranges and naming" 要求新色名进主题层而非 primitive 层，而本轮**一个新色值都不需要**，
所以完全绕开了颜色命名的复杂度。

---

## 四、明确不做

| # | 不做什么 | 涉及文件 | 理由（引条文） |
|---|---|---|---|
| D1 | **危险操作不做任何光晕 / 脉冲 / 庆祝** | `follow_common.dart:265`（`danger: true`）、`follow_view.dart:220`（删除所选） | `designing-elite-ui` 原则 1：「**Reserve a color for ONE meaning only**」——`tokens.error` 只属于危险；且危险操作需要"冷静、可撤销"的确认阈值，动效会降低它。`micro-interactions` 也说庆祝要"reserved for genuine milestones"，删除不是里程碑 |
| D2 | **密集表格行不加 hover 光晕 / 位移** | `follow_entry_row.dart`（行密度态）、`chat_tab.dart:656` | 每行都是可点项，光晕会让整屏"闪烁"（`micro-interactions`：「**Repeats too often** (becomes noise, not signal)」）；行高已按 `DESIGN.md` §3.3「密集单行例外」压到 ≤1.15，位移会破坏网格。**只补指针光标**（G3 的最小修法） |
| D3 | **已有肌肉记忆的导航项不改形状 / 尺寸 / 圆角 / 顺序** | `top_nav.dart`（8 项）、`bottom_nav.dart`（8 项）、`platform_strip.dart` 平台 tab | `micro-interactions` Sacred Rule「**No Shifting**: Never use `translate` or margins that change the element's position relative to its neighbors」；`designing-elite-ui` 原则 5「**The canvas is stable; chrome floats**」；用户已按位置记忆点击，位移是纯负收益。**只允许 hover 底色 + focus ring** |
| D4 | **房卡不加按压缩放** | `room_card.dart:43` | 房卡是网格里最小重复单元（最多 7 列 × N 行）。`micro-interactions`：「**Skip on repeat actions** — a bulk delete of 50 items should not animate 50 times」。允许 hover 时 `surface` → `surfaceRaised` |
| D5 | **`StateDot` 的 1200ms 呼吸不改数值** | `state_dot.dart:22` | 它是"直播中"状态指示而非按钮；`micro-interactions` 允许 "remote changes highlight"。但 1200ms + `Curves.easeInOut` **未在 `DESIGN.md` §5.1 登记**——**只建议登记，不改值**（改值会动 `follow_style_card.png` 等 golden，且它是循环动画，改时长收益极低） |
| D6 | **播放控制条不在本轮范围** | `player_controls.dart`、`play_view.dart:481` | on-video 层是另一套语义（`AppOnVideo`、恒定暗色、不随主题翻转），且已有独立的 `AnimatedOpacity(200ms)` 显隐逻辑（裸值，属 G9 登记项）。混进来会让本提案失控，应单开一轨 |
| D7 | **`chat_tab` 的 `Curves.easeOut`(220ms) 滚动不改** | `chat_tab.dart:403` | 那是 `ScrollController.animateTo` 的滚动落点，不是组件状态过渡；换成 `AppMotion.curve`（强 ease-out）在长距离滚动上会更"急"。**只登记为已知偏离** |
| D8 | **不新增任何强调色 / 渐变 / 大投影** | — | `DESIGN.md` §1 三禁：玻璃拟态大投影、渐变滥用、多强调色；§7「❌ 常规容器用 > 12px 圆角（chip / badge / 头像用 `AppRadius.pill`）」。本提案 6 个手段零新色值 |
| D9 | **不为了"统一"把 `follow_platform_filter` 的 chip 颜色改成 `accent`** | `follow_platform_filter.dart` | 它用的是平台品牌色（`PlatformBrandCatalog`），`DESIGN.md` §2.3 明确"平台色只用于平台 tab、卡片角标、平台图标，**不得**用于通用控件强调"。这里平台色是**语义**（筛哪个平台），不是强调——不动 |
| D10 | **不在本轮做"关注红 / 超关紫 的彩度 harmonize"** | `zishu_tokens.dart` `playFollow*` / `playSuper*` | 虽然 §1.7 证明了 `playSuperText` C=0.1193 比 `playFollowText` C=0.0827 高 44%（`chroma-harmonization` 的典型离群），但这两个色是 **web 逐字复刻**（`DESIGN.md` §2），改它们等于改视觉真源 → 需产品裁决 + §10 登记。**见 §六-5** |

---

## 五、实施顺序与验证方式

### 5.1 分阶段（按"是否改变像素"排序，让低风险项先落地）

| 阶段 | 内容 | 是否改变像素 | 依赖 |
|---|---|---|---|
| **Phase 0**<br>文档先行 | 本提案 → 评审 → 按结论改 `DESIGN.md`（§4.2 补 hover/focus/pressed 口径、§5.1 登记 `state_dot` 1200ms、§6 若新增 elevation 档、§10 登记裁决结果） | ❌ | 无 |
| **Phase 1**<br>低风险（不新增视觉语义） | 手段 6（`CompactSwitch` 的 curve + 光标 + hover + disabled，裸色值已由并发轨完成）；6 处 `GestureDetector` 补 `MouseRegion(cursor: click)`；手段 5 的两个 chip 换 `AnimatedContainer`；**顶栏 hover 方向修正**（`surfaceSoft` → `surfaceRaised`，按 §4.2，不需裁决） | ⚠️ 几乎不（曲线/光标/等价动画）；顶栏 hover 底色会变亮一档 → **会动 `hover_*` 三张 golden** | Phase 0 |
| **Phase 2**<br>会产生 golden 差异 | 手段 1（chip 过渡 + 图标脉冲）、手段 2（hover 光晕 + hover 底色统一到 `surfaceRaised`）、手段 4（loading） | ✅ 会 | Phase 1；§六 的裁决 1–3 必须先出结论 |
| **Phase 3**<br>需真机 | G1（focus ring 迁移，按组件逐个）、手段 3（缩放，若裁决通过）、reduce-motion（G8） | ✅ 会 | Phase 2；Windows 环境 |

**Phase 3 的 focus 迁移顺序建议**（按键盘 Tab 链的自然顺序，逐组件提交，不一次性铺开）：
`top_nav` → `bottom_nav` → `platform_strip` → `category_flyout` / `my_category_flyout` →
`browse_sidebar` → `user_area`（登录对话框）→ 表现型按钮。
`DESIGN.md` §4.2 已写明"迁移需逐组件进行"，这里只是把它排成序。

### 5.2 golden 影响面（先看清再动手）

**全库只有 7 条 golden 断言，且全部在两个自称"临时截图用例"的文件里**：

| 文件 | golden | 会被本轮哪些手段影响 |
|---|---|---|
| `test/ui/follow_style_shot_test.dart` | `follow_style_card.png`、`follow_style_row.png`、`play_style_recommend.png`、`play_style_follow.png` | `play_style_follow.png` ← **手段 1/2 必动**（侧栏关注/超关 chip 就在这个画面里）；`follow_style_*` ← 手段 5（chip 过渡，静止帧不变） |
| `test/ui/hover_shot_test.dart` | `hover_platform_categories.png`、`hover_follow_grid.png`、`hover_my_category.png` | `hover_*` 三个都是 hover 态截图 ← **手段 2 必动**（hover 底色统一 + 光晕）；`hover_my_category.png` ← 手段 5 |

**流程（`ui-from-design-md` skill 的原文要求）**：
> "确认差异就是本次有意改动再 `--update-goldens`；**看不懂的差异不要更新，报出来**。"

1. 先跑 `flutter test test/ui`，**不要**先加 `--update-goldens`。
2. 打开 `test/ui/failures/` 新生成的 `*_isolatedDiff.png` / `*_maskedDiff.png`，
   逐张确认差异落在预期的元素上、量级符合预期。
3. 确认后**逐个文件**更新（不要一把全刷）：
   `flutter test test/ui/hover_shot_test.dart --update-goldens`
   `flutter test test/ui/follow_style_shot_test.dart --update-goldens`
4. 顺带清理 `test/ui/failures/` 里 2026-09-22 09:07 的 **28 张残留**差异图（G9，7 组 × 4 张）——
   否则新旧差异混在一起无法解读。

> **前置裁决（见 §六-7）**：这两个文件头都写着"生成后本文件即删除"，它们是人工比对基线、
> 不是回归门禁。**要不要把它们升级成正式门禁（或新建 `test/ui/button_states_test.dart`）
> 必须先定**——否则本轮的"验证"没有真正的保护网。
>
> **⚠️ 并发轨已碰过这两张图**：`play_style_follow.png` / `play_style_recommend.png`
> 已被并发轨（svip 第 3 统计列）`--update-goldens` 重刷（见开头快照节第 5 条）。
> 本提案的 Phase 2 必须**等并发轨提交并稳定后**再开，否则差异图分不清归属。

### 5.3 命令

```bash
# 每阶段收口（AGENTS.md 要求的门禁）
flutter analyze
dart run tool/check_design_tokens.dart          # 基线只降不升
flutter test test/ui

# 仅在看懂差异后
flutter test test/ui/<shot_test>.dart --update-goldens

# Phase 1 的额外证据：确认 compact_switch 的裸色值已清零
grep -n "compact_switch" tool/design_token_baseline.json
# 期望：compact_switch 的 raw_color 条目已因并发轨的 token 收敛而消失（已核实）
# 若仍剩 Colors.transparent / Colors.white 等条目，需一并处理或明确保留理由
```

`tool/check.ps1` 是全量一键门禁（`pub get` ×3 → `analyze` → token guard → `test`），
Phase 2/3 收口时建议直接跑它。

### 5.4 必须真机看的（golden 抓不到）

`visual-polish` 的 "Silent failures" 明确列了这条：
> "**Motion judged from stills.** A transition that jumps, a hover that shifts layout,
> an entrance animation replaying on every re-render: none of it is in a screenshot."

| 项 | 为什么 golden 抓不到 | 怎么看 |
|---|---|---|
| hover 光晕在 `#181818` / `#1F1F1F` 上的实际可见度 | 静态帧能看到阴影，但看不出"是否够亮 / 是否发灰" | Windows 真机，鼠标慢速扫过顶栏 → 平台条 → 抽屉 |
| focus ring 是否被相邻元素裁切 | 需要真实 Tab 走位 | Windows 真机 `Tab` / `Shift+Tab` 走完整链；`designing-elite-ui` 原则 8「never ship a clipped focus ring」 |
| 鼠标点击时**不**应出现 focus ring | 需要真实 `FocusHighlightMode` 切换 | 点一下顶栏项，确认无环；再按 Tab，确认有环 |
| 按压回弹手感（150ms 够不够 / 太长） | 需要连续交互 | 连点 20 次关注 chip |
| chip 圆角 4 → pill 的形状过渡（若裁决通过） | 需要看中间帧 | 慢速点击，观察是否有"抽搐" |
| `(hover: hover) and (pointer: fine)` 在 Windows 触控屏 / 触控板上的判定 | 平台相关 | 若有触屏设备，确认触屏下走的是 `DESIGN.md` §8 的"控制条改底部 sheet"路径 |
| 深浅双主题 | `visual-polish` Verification 3 要求"Both themes were compared" | 切浅色，重跑上述全部 |

---

## 六、风险与需要产品裁决的点

| # | 裁决点 | 冲突/风险 | 本提案建议 |
|---|---|---|---|
| **1** | **按钮按压缩放（`scale(0.97)`）做不做？** | `button-states`「Scale on Active (Optional)」✅ vs `motion-and-storytelling` 原则 1（限 primary CTA）✅ vs `micro-interactions` **Sacred Rule「No Scaling… Never」**❌。三个 vendor 的 skill 直接冲突 | **默认不做**。Sacred Rule 是唯一带 "Never" 的绝对表述，且其理由（"光标下的 UI 移动 = 不可预测"）在高密度工具型界面里代价更高。若要做，只限表现型 CTA，并登记 `DESIGN.md` §10 |
| **2** | **关注/超关 chip 的形状变化（圆角 4 → pill）做不做？** | `DESIGN.md` §7 明确允许 chip 用 `AppRadius.pill`，但侧栏是两个 59px 宽、上下堆叠的按钮，变 pill 后视觉重心会变 | 建议**先只做颜色+描边+图标脉冲**（手段 1 的 1–2 步），把 pill 作为独立的可选第 3 步。会动 `play_style_follow.png` |
| **3** | **hover 加光晕算不算"新 elevation 语义"？** | `DESIGN.md` §4.2 的 hover 行只写"颜色/边框过渡，不位移"，没有 elevation 变化；复用 `accentGlow` 等于扩语义 | 建议做，但**必须同步改 `DESIGN.md` §4.2 + 登记 §10**。理由：`accentGlow` 已在 §6 四档内，不是新增档，且 `platform_strip` 已有先例 |
| **4** | **disabled 口径以谁为准？** | `button-states` 说 `opacity: 0.4` + `cursor: not-allowed`；`DESIGN.md` §4.2 说"`textSecondary` 文字 + 不响应指针；**不额外加灰罩**"；而 `_SideTextAction` 现在用 `textSecondary@0.55`（实测 \|Lc\| **13.8**） | **以 `DESIGN.md` 为准**（项目约束 > skill），把 `@0.55` 改回 `textSecondary`（\|Lc\| 41.8）。若产品坚持 `@0.55`，需登记为 token 并接受 \|Lc\| 13.8 的对比度 |
| **5** | **`playFollowBgHover` / `playSuperBgHover` 接线还是删除？** | 两个 token 在组件层零引用，`DESIGN.md` §2 却把它们登记为"6 态"的一部分 | 建议**接线**（手段 1）。若删，必须同时改 `DESIGN.md` §2 与 `test/shared/design_tokens_test.dart` |
| **6** | **本轮是否接受新增 token？** | 任何新 token = `DESIGN.md` + token 文件 + 契约测试三处同步（`AGENTS.md` 硬规则） | 建议只加 `AppSpinner.size/strokeWidth`（消除 11 处裸 `strokeWidth: 2`，是"基线只降不升"的正收益）。`AppElevation.hoverGlow` / `AppMotion.curveSpring` **暂不加** |
| **7** | **`test/ui/*_shot_test.dart` 的存废？** | 它们自称"临时截图用例…生成后本文件即删除"，却是全库仅有的 7 条 golden。本轮要动其中的 `play_style_follow.png` 与 3 张 `hover_*.png` | 建议**升级为正式门禁**（或新建 `test/ui/button_states_test.dart` 专测六态）。否则本轮的"验证"没有真正的保护网 |
| **8** | **要不要加 `raw_duration` 守卫规则？** | 当前守卫只拦裸色值/阴影/字号/圆角，时长漂移不被拦（已存在 200/220/720/800/1200ms 五处裸值） | 建议加第 5 条规则 + 把 5 处存量进基线（同现有四类的做法：只降不升）。这是"曲线纪律"能长期守住的前提 |
| **9** | **reduce-motion（G8）本轮做不做？** | `micro-interactions` 与 `motion-and-storytelling` 都把它列为 "always" 硬规则；全库 0 处处理 | 建议做，成本低：一个 `AppMotion.durationFor(context, base)` 帮助函数（`MediaQuery.disableAnimationsOf(context)` 为真时返回 `Duration.zero`），所有 `AnimatedContainer` 改走它 |
| **10** | **全局次级文字对比度（`textSecondary` 白 55% → \|Lc\| 41.8）要不要动？** | 低于 APCA 的 Lc 60 次级门槛。这是**既有基线**且是 web 逐字复刻；动它会影响全应用观感 | **本轮不动**，但**必须登记为已知项**并路由到 a11y 轨（`visual-polish` 明确要求："Findings that are really drift or really a11y were routed, not re-filed here"）。同时：`accent` 当文字前景（\|Lc\| **17.3**，见 `retry_button.dart` / `top_nav` active / `FollowIconAction` active）**应视为缺陷**，因为它把"填充色"当"文字色"用了——这是本轮范围内可修的点（改用 `textPrimary` + `accent` 作描边/底色） |
| **11** | **超关常态标签 \|Lc\| 31.5 要不要修？** | 是按钮**常态**态，属本轮范围；但改色 = 偏离 web 真源，需 §10 登记 | 建议用 `oklch-color-space` 的 **APCACH 反解**（声明 `target_lc` + hue 305.6 + chroma cap + bg `#442D5B` → 二分求 L）重新推导 `playSuperText`，而不是"挑一个更亮的紫再测"。同时用 `chroma-harmonization` 把 `playFollowText` / `playSuperText` 的 C 收到同一 ceiling（现值 0.0827 / 0.1193，差 44%） |
| **12** | **两处"关注"按钮手感统一到哪个时长？** | `FollowButton` 用 `AppMotion.normal`(250ms)，`_SideActionButton` 无过渡（G7-②） | 建议**统一到 `AppMotion.fast`(150ms)**——`button-states` 说状态过渡是 "80–150ms"，250ms 属"组件级过渡"档（展开/收起），用在按一下的 chip 上偏慢 |

---

## 附录 A：引用的 skill 规则（逐条）

> 格式：`skill` → 「原文条文」→ 本提案用在哪儿。

### A.1 `.agents/skills/button-states/SKILL.md`

| # | 条文 | 用在哪 |
|---|---|---|
| 1 | "The Six States" 表（Rest / Hover / Active·Pressed / Focus / Disabled / Loading 的 trigger 与 visual signal） | §1.1 盘点口径；§1.3–1.5 状态矩阵的列定义 |
| 2 | "Deriving State Colours Algorithmically"：`hover: hsl(H,S%,L%−8%)`、`active: hsl(H,S%,L%−14%)`，"This guarantees coherence across the entire palette" | §1.7 用 OKLCH 实测校验 `#582626 → #512626 → #4F2C2C` 的明度递减是否自洽；§六-11 |
| 3 | "For light buttons on dark backgrounds, invert the logic — **lighten** on hover instead of darkening" | §3.2 hover 表；浅色主题 `#FBECEC → #F7E1E1`（实测 L 0.9549 → 0.9275，方向正确） |
| 4 | "Focus State"：`outline-offset: 2–4px` 给环"呼吸空间"；"Never use `outline: none` without a replacement focus style"；"It must be visible and must not rely on the hover style alone — keyboard users do not trigger hover" | §3.2 focus 节（Flutter 无 `outline`，用 `AppFocus.ring` 的 `boxShadow` 等价，offset = `AppFocus.ringOffset`=2）；§5.4 |
| 5 | "Disabled State"：`opacity: 0.4` / `cursor: not-allowed` / `pointer-events: none`；"**Do not change the shape or size** of a disabled button — only colour and cursor change" | §3.2 disabled 节；§六-4（与 `DESIGN.md` §4.2 冲突，按项目约束取"不加灰罩"） |
| 6 | "Loading State"：替换 label 为 spinner + 防重复提交；"**Keep the button width stable during loading — avoid layout shift**"；"**The cursor does not change while loading.** It signals affordance, not progress"；"Return to rest state on completion"；"For long-running operations, pair with a status message" | 手段 4 全节；§3.2 loading 节；G5 |
| 7 | "Scale on Active (Optional)"：`transform: scale(0.97)`；"Keep the scale value between `0.95–0.98`. **Below `0.95` feels like the button is breaking.**" | 手段 3 的数值依据；§六-1 |
| 8 | "Complete Button CSS Reference"：`transition: background 120ms ease-out, transform 80ms ease-out` | §3.2 全表（说明为什么 `AppMotion.fast`=150ms 是对的档） |
| 9 | "Review Checklist"：六态齐备 / hover-active 由基色明度推导 / focus 可见且用 outline / disabled 低不透明度 / loading 防重复提交 / "Are transition durations **80–150ms** — not instant, not slow?" / "Does `cursor: pointer` appear on all interactive elements at rest?" / "Does the cursor stay unchanged while an action runs, with progress shown by the element itself?" | §二 缺口清单的验收项；G1/G2/G3/G5；§3.2 各态 |

### A.2 `.agents/skills/micro-interactions/SKILL.md`

| # | 条文 | 用在哪 |
|---|---|---|
| 1 | "What Makes a Good Micro-Interaction"：必须 confirm / reward / reveal / add texture；"It fails when it: Delays the user / **Repeats too often** (becomes noise, not signal) / **Exists only for decoration**" | §四 D2/D4 的判据 |
| 2 | "Natural World as Reference" 表："A bell ringing → Icon that briefly oscillates (shakes) on trigger"；"**A stamp pressing paper → Inner element shift (e.g. icon nudge) without shifting button bounds**" | 手段 1 第 2 步（图标脉冲不撑按钮边界） |
| 3 | "Heart pulse on like"：`0%{scale(1)} 40%{scale(1.25)} 100%{scale(1)}` | 手段 1 的曲线原型；本项目把 1.25 收敛到 1.15（见 A.3-5） |
| 4 | "Toggle / Switch"：`cubic-bezier(0.34, 1.56, 0.64, 1)` "produces a spring effect — the thumb overshoots and settles. **This is the difference between a switch that feels cheap and one that feels premium.**"；checklist "Does the toggle/switch use a spring easing curve, **not linear**?" | 手段 6；G4 |
| 5 | "Button Interaction Feedback (Stability Rule)"：按钮"must never change their outer dimensions or shift their position"；反馈走颜色 / **内部阴影**（`box-shadow: inset 0 2px 4px rgba(0,0,0,.1)`）/ 内部元素微动 | 手段 3 的合规替代方案（`AppElevation.hairline`）；§3.2 pressed 节 |
| 6 | "Skeleton → Content Transition"：150–200ms 交叉淡入，"do not flash it in" | 手段 4 的交叉淡入；§3.2 loading 节 |
| 7 | "Attracting Attention to Remote Changes"："**The animation should be non-looping.** Once the eye is caught, the motion must stop" | §四 D5（`StateDot` 是唯一允许的循环动画，且只作登记） |
| 8 | "**The Sacred Rule of Component Stability**"：**"No Scaling: Never use `transform: scale()` on hover or click for buttons.** It causes visual vibrating and can feel 'squishy' rather than premium."；"**No Shifting**"；"If the UI moves under the user's cursor, it feels unpredictable" | **§六-1 的核心裁决点**；§四 D3 |
| 9 | "How to Declare the Motion"：**"Transitions for state, keyframes for sequences."** A transition can be interrupted, a keyframe cannot；"**Name the properties**"（禁 `transition: all`）；"`will-change` is a last resort" | §3.2 全表（所有状态过渡用可打断的 `AnimatedContainer`/`AnimatedScale`，而非一次性 `AnimationController`） |
| 10 | "Restraint"："**Once per trigger**" / "**Skip on repeat actions**" / "**No blocking animations**" / "**Respect `prefers-reduced-motion` — always**" | §四 D2/D4；§六-9；G8 |
| 11 | "Review Checklist"：Sacred Rule / 200–600ms / 自然物理（spring、ease-out、overshoot）而非 linear / 非阻塞 / prefers-reduced-motion / 高成本庆祝只给里程碑 / 开关用 spring / 远端变化用短暂非循环动画 | §二/§三 的逐条对照 |

### A.3 `.agents/skills/motion-and-storytelling/SKILL.md`

| # | 条文 | 用在哪 |
|---|---|---|
| 1 | 原则 1「Squash and Stretch」：`button:active { transform: scale(0.96) }`；"**Use sparingly — reserved for primary CTAs** and satisfying confirmations" | 手段 3 的授权与范围限定；§六-1 |
| 2 | 原则 6「Ease In and Ease Out」：`ease-out`=进入 / `ease-in`=离开 / `ease-in-out`=位移 / spring=交互元素；"**Never use `linear` for UI motion** — it reads as mechanical and unfinished" | **G4 的直接判据**（`compact_switch` / `platform_strip` 落到 `Curves.linear`） |
| 3 | 原则 8「Secondary Action」："a supporting motion that reinforces the main action. In UI: **an icon inside a button that shifts slightly when the button is pressed**" | 手段 1 第 2 步；§3.1 标准型上限 ⑦ |
| 4 | 原则 9「Timing」：80–120ms 微交互 / 150–250ms 组件过渡 / 250–400ms 页面级 / "**> 600ms Almost always too long**" | §3.2 全表（校验 `AppMotion.fast`=150 / `normal`=250 落在正确档）；§六-12 |
| 5 | 原则 10「Exaggeration」："a success checkmark that overshoots slightly before settling… **The exaggeration is 10–15%, not theatrical**" | 手段 1（把 heart-pulse 的 1.25 收敛到 1.15） |
| 6 | 原则 11「Solid Drawing」：元素应"move in ways consistent with their perceived layer" | 手段 2（光晕只用已登记的 elevation 档，不越层造新深度） |
| 7 | "Cut vs Dissolve"：hard cut 用于导航/关闭；"**Dissolve / crossfade**: gradual, considered, connected. **Use when two states are related** — a tab switching, an image gallery transitioning" | 判定"关注 ↔ 已关注"属"相关状态"→ 应 crossfade 而非硬切（手段 1 的立论） |
| 8 | "The Gutter"：transition 是状态之间的"槽"；"A smooth transition lets the user's brain construct a coherent mental model. **A jarring jump forces them to re-orient.**" | 手段 1 / 手段 5 的立论；G6 |
| 9 | "Practical Rules" 1–5：respect `prefers-reduced-motion` / motion 要服务用户 / 组件级 **under 400ms** / "**Never animate layout properties (`width`, `height`, `padding`, `top`, `left`) — they cause reflow. Animate `transform` and `opacity` only**" / "**One motion at a time per region.**" | §3.2 loading 节（禁换 child 造成跳宽）；手段 5（不动 padding）；G8 |

### A.4 `.agents/skills/visual-polish/SKILL.md`

| # | 条文 | 用在哪 |
|---|---|---|
| 1 | 第 4 条「**The state and content matrix**」：状态轴 rest/hover/focus-visible/active/disabled/loading/error + 内容轴 empty/one item/long string/overflow/slow network；"Flag cells that are *missing* and cells that are *present but indistinguishable* — **hover and active rendering identically is the same defect as no hover at all**" | **§一 / §二 的方法论来源**；G2（本项目是第三种：hover 来源不可控） |
| 2 | 同上："A **disabled state built from opacity alone** often drops its label under the contrast floor" | §1.7 的"禁用文字 \|Lc\| 13.8"；G5；§六-4 |
| 3 | 第 5 条「Theme parity beyond colour」："A drop shadow is a light-surface device — **over near-black there is little left to darken**, so elevation has to come from surface lightness" | 手段 2 的风险提示；§5.4（光晕必须真机验证） |
| 4 | "Silent failures"：「**Motion judged from stills**」——"A transition that jumps, a hover that shifts layout, an entrance animation replaying on every re-render: **none of it is in a screenshot**" | §5.4 的立论（golden 抓不到动效，必须真机） |
| 5 | "Silent failures"：「**The fix landed as a magic number**」——"A 2 px optical nudge hardcoded is drift the moment density or type changes… **The fix is a trim, a token, or a geometry change.**" | §3.2 pressed 节（不新增 `surfacePressed` 灰阶）；§3.4（所有改动走 token） |
| 6 | "Silent failures"：「**Nits manufactured to look thorough**」——"**A polished surface reported as polished is a valid output**; padding the list costs the reviewer's credibility" | §一 N5（如实标注 `platform_strip` 是本项目最佳实践）；§四（只列 10 条真不做，不凑数） |
| 7 | "Verification" 1–5：每条 finding 必须给"具体升级"（"A verdict without an upgrade is not a finding"）/ 不得用裸值当修法 / "Both themes were compared, and the DPR and content state of the evidence are stated" / "Findings that are really drift or really a11y were **routed, not re-filed here** — severity never ranks a polish nit above a measured failure" / 真·打磨过的表面要一句话明说 | §二（每条缺口都带修法）；§六-10（对比度路由到 a11y 轨，不混进 polish 项）；§5.4（双主题） |

### A.5 `.agents/skills/designing-elite-ui/SKILL.md`

| # | 条文 | 用在哪 |
|---|---|---|
| 1 | 原则 1「One semantic role → one meaning → one variation axis」/「**Reserve a color for ONE meaning only.**」 | §四 D1（`tokens.error` 只属危险操作，不参与光晕/庆祝） |
| 2 | 原则 2「**Contrast is gated, not eyeballed.** APCA-check every text-on-fill. A theme flip needs its *own* ramp… never reuse the light values on a dark surface" | §1.7 全表（APCA 实测）；§六-11 |
| 3 | 原则 3「**Restraint beats richness.** Distinguish by hue-in-band + shape + label, not a rainbow… **Retire decoration that doesn't carry meaning.**" | §3.1 分档的立论；§四 D8；§3.4（零新色值） |
| 4 | 原则 5「**The canvas is stable; chrome floats.** The work surface NEVER reflows or rescales on selection… the toolbar morphs smoothly" | §四 D3（导航项不改形状/尺寸/位置） |
| 5 | 原则 6「**Interaction feels alive before the click.** Cursor affordances (resize cursors on handles, grab/grabbing on pan), **hover highlights**, valid/invalid ghost tints, smooth transitions, **unmistakable active states**." | **G3 的直接判据**（全库 0 处 `SystemMouseCursors`）；手段 2；手段 6 |
| 6 | 原则 7「**Light and dark are BOTH primary.** Design and verify in both" | §3.2 各表（逐态都写深浅两套）；§5.4 双主题验收 |
| 7 | 原则 8「**Optical, not metric, alignment**… **never ship a clipped focus ring**" | §5.4（focus ring 真机验收项） |
| 8 | "Gotchas" 表：「Two controls read 'active' at once — Mode vs tool both filled with the accent → **give the resting one a tinted/outline state**」 | 用于审视"已关注 + 已超关"同时成立时的两 chip 同实底（现状靠红/紫色相区分，语义可辨；**未列为缺口，仅记录**） |
| 9 | "Encode the Bar (so it's enforceable)"：tokens 一处、design-system doc 一处、"Feed it to the design-critic: **challenge the render against THIS bar in light + dark** — not 'is it nice?'" | §5.4 的验收方式（对照 `DESIGN.md` 而不是"看着还行"） |

### A.6 `.agents/skills/oklch-color-space/SKILL.md`

| # | 条文 | 用在哪 |
|---|---|---|
| 1 | "**Compose to a contrast target — don't pick L and test.**" APCACH 反解：`INPUT target_lc=75, hue=220, chroma_cap=auto, bg=…` → 二分搜索 L → "The output is **guaranteed** to satisfy the contrast obligation — without a test-and-adjust loop" | §1.7 的判据（现状色是"挑出来的"）；§六-11（修法必须走反解，不许"挑个更亮的再测"） |
| 2 | "Primitive ranges and naming"：`<name>-<angle>` 约定；"**Reserve generic accent labels (`accent-teal`, `primary`) for the theme layer above primitives, not the primitives themselves**" | §3.4（本轮零新色值，完全绕开命名复杂度） |
| 3 | "Gamut mapping"：sRGB 只在 ①emission edge ②apcach 背景锚 ③WCAG 交叉验证三处进入；"the shipped APCA *meter* still gamut-clamps both colors into sRGB before scoring… **never state that the live meter measures in P3**" | §1.7 的方法说明（本项目 hex 值都是 sRGB 输出边界产物，推导 hover/active 时保持同一边界）；附录 B 的口径 |
| 4 | "Verification" 1–4：range check（`0≤L≤1`, `0≤C≤0.4`, `0≤H<360`）/ gamut check / round-trip check / contrast check（"APCA Lc against the declared pairing background hits the target **± 1 Lc**"） | §3.4 的验收清单；§六-11 新增色值的验收 |

### A.7 `.agents/skills/chroma-harmonization/SKILL.md`

| # | 条文 | 用在哪 |
|---|---|---|
| 1 | "The algorithm"：每个 stop 取跨色相最大 chroma 的**最小值**作 ceiling（"Average would push half the hues out of gamut… **Minimum is the only value where every hue can hit the target chroma in-gamut**"） | §1.7 观察 1（`playFollowText` C=0.0827 vs `playSuperText` C=0.1193，差 44%——典型离群）；§六-11 |
| 2 | "**Recompose, don't just clamp**"：在共享 ceiling 上重解 L（constant-chroma 分支），"Clamping chroma while leaving L untouched lets achieved Lc drift off target by up to ~5" | §六-11（修 `playSuperText` 必须"重解 L"而非"只降 C"，否则对比度会漂） |
| 3 | "Known counterexample, not a template"：UDTS 自己的 `harmonizeChroma` 是 clamp-without-recompose，"**its chroma-clamp-without-recompose is the bug to fix, not the pattern to copy**" | §六-11（明确不照抄 clamp-only 的做法） |
| 4 | "When NOT to use"："Brand-spot or accent palettes where one hue *should* dominate. Use the `max` palette variant instead" | §四 D10 / §六-11（"关注红 / 超关紫"是**功能语义色**而非品牌强调色，是否强行 harmony 需裁决） |
| 5 | "Headroom rule"：**"Stay ≥ 10% below the computed ceiling"** —— 为 sRGB fallback 的 8-bit 量化与显示驱动留余量 | §3.4（若新增状态色，取值纪律）；§六-11 |
| 6 | "Verification" 1–3：gamut check / "**at the same stop, all hues should report identical (or near-identical) saturation in a side-by-side swatch**" / headroom check | 把"关注红 vs 超关紫 饱和度不齐"变成可验证项（§六-11） |

---

## 附录 B：复现证据的方法

盘点与 §1.7 的全部数字都可复现，命令如下。

**结构性统计**（在仓库根执行）：

```bash
# 交互原语计数
for p in InkWell GestureDetector MouseRegion AnimatedContainer TextButton OutlinedButton IconButton FilledButton; do
  printf "%-18s %s\n" "$p" "$(grep -rn "\b$p\b" lib/src --include=*.dart | wc -l)"
done

# 显式 hoverColor（8 处）
grep -rn "hoverColor" lib/src --include=*.dart

# 指针光标（期望 0）
grep -rn "mouseCursor\|SystemMouseCursors" lib/src --include=*.dart | wc -l

# AppFocus 组件引用（期望只命中 token 定义与契约测试）
grep -rn "AppFocus" lib/src test --include=*.dart

# 死 token（期望 0）
grep -rn "playFollowBgHover\|playSuperBgHover" lib/src --include=*.dart \
  | grep -v zishu_tokens.dart | grep -v design_tokens.dart | wc -l

# 未给 curve 的 AnimatedContainer / AnimatedAlign
grep -rn -A3 "AnimatedContainer(\|AnimatedAlign(" lib/src --include=*.dart | grep -c "curve:"

# loading 态（按钮内 vs 页面级）
grep -rn "strokeWidth: 2" lib/src --include=*.dart | wc -l

# 裸时长（守卫不拦）
grep -rn "Duration(milliseconds\|Duration(seconds" lib/src --include=*.dart | wc -l

# reduce-motion（期望 0）
grep -rn "disableAnimations" lib/src --include=*.dart | wc -l

# golden 断言（全库 7 条）
grep -rn "matchesGoldenFile" test --include=*.dart
```

**§1.7 的颜色度量**：用 OKLCH（Björn Ottosson 的 sRGB→linear→LMS→Lab 变换）与 APCA
（0.0.98G 系数版：`Y = 0.2126729R^2.4 + 0.7151522G^2.4 + 0.0721750B^2.4`，
暗端软钳制 `Y<0.022 ? Y+(0.022−Y)^1.414 : Y`，正常极性 `(Ybg^0.56 − Ytxt^0.57)×1.14`、
反极性 `(Ybg^0.65 − Ytxt^0.62)×1.14`）。**签名约定：正值 = 深字浅底，负值 = 浅字深底**，
本文表格给绝对值。半透明色（如 `0x8CFFFFFF` = 白 55%）先按
`composite = fg×α + bg×(1−α)`（在 linear RGB 空间）合成再计分。

**口径提醒**（`oklch-color-space` 的 "Gamut mapping"）：本项目的 hex 值都是 sRGB 输出边界产物，
且 APCA 计分本身在 sRGB 空间完成——不要把这些数字当作 P3 度量结果。
`oklch-color-space` 明确警告过 "never state that the live meter measures in P3"。

---

## 附录 C：一页速查（评审时只看这个）

**已做对的（不要改坏）**
- `platform_strip.dart:247` 的 34×34 平台 tab：唯一同时有 hover 底色 + `AnimatedContainer` + `accentGlow` 的元素，是标准型/表现型的范式（**只差 `curve`**）。
- `user_area.dart:294` 的登录按钮：全项目唯一做对的 loading（保宽 + 禁用 + 转圈）。
- `follow_button.dart:22`：唯一用 `AnimatedContainer` 做状态过渡的按钮（**但时长用了 `normal`，见 §六-12**）。
- `_SideTextAction` 的禁用 Tooltip 文案（`'关注后可开启开播提醒'`）：值得推广到所有 disabled 元素。

**最该先动的四件事**
1. 4 处 `AnimatedContainer` 补 `curve: AppMotion.curve`（一行改动，消除 `Curves.linear`）。
2. 6 处 `GestureDetector` 补 `MouseRegion(cursor: SystemMouseCursors.click)`。
3. **修顶栏 hover 方向**：`top_nav.dart:207/315`、`platform_strip.dart:250`、`user_area.dart:141`
   的 `hoverColor` 从 `surfaceSoft` 改 `surfaceRaised`——这是**按 `DESIGN.md` §4.2 修正既有缺陷，不需裁决**。
4. `playFollowBgHover` / `playSuperBgHover` 接线（两个死 token → 两个表现型按钮有 hover 态）。

**动手前必须先出的裁决**：§六-1（缩放）、§六-2（chip 形状）、§六-3（hover 光晕语义）、§六-7（golden 门禁存废）。

**盘点快照提醒**：行号以 2026-09-22 10:48 工作区为准；并发轨（token 收敛 + svip 第 3 列）
仍在改 `side_panel_header.dart` / `compact_switch.dart` / `design_tokens.dart`——
请**以符号名定位**，见开头“盘点快照与并发改动”一节。

---

## 裁决结果（2026-09-21，产品确认）

| # | 议题 | 裁决 | 落地 |
|---|---|---|---|
| 1 | 按压缩放 0.97 | **禁止** | 已写入 `DESIGN.md` §7 Don'ts：按钮反馈只走颜色/描边/阴影/图标，不做位移与缩放 |
| 2 | 关注/超关 chip 圆角 4 → pill | **采纳** | `side_panel_header.dart` 与 `play_meta_bar.dart` 各 2 处 `AppRadius.allSm` → `allPill`；已更新 play 相关 golden |
| 3 | hover 光晕是否算新 elevation 语义 | 主控裁定：**不算新语义** | `AppElevation.accentGlow` 本就在 §6 登记（强调色外发光）；已把适用面从「选中态」扩到「选中态 + hover 态」，不新增档位 |
| 4 | `test/ui/*_shot_test.dart` 存废 | 主控裁定：**保留并升格为正式 golden 套件** | 本轮它连抓 13 处真实像素变化（6 + 7），证明价值；其余取舍见下 |
| 5 | 浅色 accent 上黑系前景对比度 | **处理**（按实测） | 4 处 accent 底前景黑→白（`AppOnBright.glyph` 已删除）；白前景在两种主题都更优：深 accent 4.81:1 vs 黑 4.36:1，浅 accent 9.39:1 vs 黑 **2.24:1** |
| 6 | `platform_icon` 四象限余 4 处裸值 | 主控裁定：**限定到平台色表** | 四象限改为按 `accentColor` 派生（见下「新发现」），`raw_color` 基线 33 → 24 |
| 7 | `platform_badge` 改用平台 `chipForeground`？ | **采纳**（对齐 web `platformCatalog.ts` 的 `fg`） | 角标文字改为按平台：虎牙/YY/全平台用深色 `#1a1a1a`，其余用白；不再是"统一黑 87%" |

### 本轮顺带发现的两个真 bug（不在原提案里）

1. **平台色有两个真源家族，项目混用了**：web `--platform-{id}`（theme.css，供平台图标/顶栏 tab 描边与光晕）与 `PLATFORM_BRAND_COLORS` 的 `bg`/`fg`（platformCatalog.ts，供封面角标/chip）是两套。哔哩两套不同色——**变体蓝 `#00a1d6` vs 角标粉 `#fb7299`**。项目只存了后者并用于两处，导致顶栏 tab 与平台图标串成粉色。已给色表加 `accentColor` 字段（默认回退 `color`），按 web 变量家族填哔哩蓝与斗鱼 `#ff6b00`，并让四象限与顶栏 tab 光晕改用它。
2. **色表漏了两个前景定义**：`yy`（黄底 `#ffd000`）与「全平台」（品牌金底）在 web 里都该用深色字 `#1a1a1a`，项目用的是默认白字——白字压在黄/金底上对比度极低。已补 `chipForeground: chipForegroundDark`。
