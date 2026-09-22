# 氛围级 UI 效果清单（分支 ui/ambient-polish）

> 状态：**已交付，待真机录屏验收**（16 项实现全部完成、任务级审查 + 终审 + 修复波复审闭环）。本文档是 `ui/ambient-polish` 分支的实现范围契约——逐屏列出
> 「加什么、加在哪、预期是什么」。实现顺序 = 清单顺序；每完成一项打钩，
> golden 更新必须对应清单项，禁止批量一键 accept。
>
> 风格参照：直播平台原生感（深色底 + 高饱和强调 + 发光/脉冲）。
> 约束：不改信息结构（不增删栏目、不挪主要控件位置）；凡改**既有**颜色/字号/
> 阴影仍走 `DESIGN.md` → token → 调用点流程；新增装饰图层允许在本清单内发明。

## 0. 基线事实（2026-09-22 勘察）

| 事实 | 结论 |
|---|---|
| `_shellPage` 用 `NoTransitionPage`（app_router.dart:247） | 页面切换零过渡，是「切换动画」的落点 |
| 全仓无 `BackdropFilter` | 毛玻璃全部为新增 |
| 全仓 0 处 `reduceMotion`/`disableAnimations` | 本次所有动效必须**新建**降级路径 |
| 动效 token 仅有 `AppMotion`（fast 150 / normal 250 / curve） | 新增 ambient 档位并入或新设 token，禁止裸 duration |
| 阴影四档 `AppElevation`（含 `accentGlow`），守卫脚本拦裸 `BoxShadow` | 发光效果**必须**走 `accentGlow` 或新增档位并登记 DESIGN.md §6 |
| golden 断言仅 7 处 / 3 文件（follow_style、hover_shot + workflows） | golden 爆破半径小，逐项更新可行 |
| 加载态用 `CircularProgressIndicator`（8 处 view） | shimmer 是替换项，逐屏换 |

## 1. Token 层（先行，其它项依赖）

| # | 效果 | 落点 | 预期 |
|---|---|---|---|
| 1.1 | `AmbientMotion` token：`pageTransition` 180ms、`pulse` 1.6s 循环、`shimmer` 1.4s 循环、easing 复用 `AppMotion.curve` | `design_tokens.dart` 或并列新文件 | 全部动效时长单一来源 |
| 1.2 | `AmbientGlow` token：卡片 hover 发光（accent 18%、blur 12）、CTA 流光（accent 24%、blur 16）、氛围光晕（accent 8%、blur 64） | 同上 | 三档发光常量，DESIGN.md §6 登记 |
| 1.3 | blur 上限：毛玻璃 `BackdropFilter` sigma ≤ 20（Windows 性能约束） | token + 注释 | 超限即违规 |
| 1.4 | `reduce_motion` 降级 API：`AmbientMotion.of(context)` —— `MediaQuery.disableAnimations` 为 true 时返回零时长/静态 | token 文件 | 所有新 widget 走它 |

## 2. 微交互层（B 级，先做）

| # | 效果 | 落点文件 | 预期 |
|---|---|---|---|
| 2.1 | 卡片 hover 抬升 + 发光：translateY(−2px) + 阴影升一档 + `AmbientGlow.cardHover` | `room_card.dart`、`anchor_live_card.dart`、`follow_entry_card.dart`、`play_room_grid` 内卡片 | 150ms 进/出，`AppMotion.curve`；**仅 hover 轨，鼠标光标已有** |
| 2.2 | 主 CTA 流光边框：follow 按钮、播放页主操作按钮 hover 时 accent 渐变描边呼吸 | `follow_button.dart`、`player_controls.dart`（主操作） | 渐变沿边框缓慢流动或 2s 呼吸；pressed 仍走现有 `pressedOf` |
| 2.3 | 直播中红点脉冲：`state_dot` / `cover_badges` 的 live 圆点外圈 2s 扩散涟漪 | `state_dot.dart`、`cover_badges.dart` | 静态红点保留，外加扩散圈；reduce_motion 时只留静态点 |
| 2.4 | 热度/在线数字发光：热度角标数值 hover/进入视口时 accent 微发光 | `cover_badges.dart`（热度角标） | 装饰性 textShadow，不动角标底色（对齐 web 真源的约束不破） |
| 2.5 | 按钮 pressed 缩放 0.97 | 主 CTA（同 2.2 范围） | 与 `AppStateLayer` 叠加使用，不重复发明按下色 |

## 3. 氛围层（C 级新增）

| # | 效果 | 落点文件 | 预期 |
|---|---|---|---|
| 3.1 | **毛玻璃 top_nav**：滚动/内容透出时 nav 底 `surface` 85% + blur 16 | `top_nav.dart` | 静止时观感≈现状（golden 波动最小化方案：只在内容滚过时可见） |
| 3.2 | **毛玻璃侧栏**：播放页沉浸侧滑面板、side_panel 头部 blur 12 + 现有 `surface` 色 | `play_immersive_side_sheet.dart`、`side_panel/side_panel_header.dart` | 面板下透出播放器画面虚化 |
| 3.3 | **氛围光晕（播放页）**：播放器容器外圈低透明 accent 径向光晕（8%、blur 64） | `play_view.dart` | 紫薯 accent 家族色驱动；窗口失焦/非全屏时不渲染 |
| 3.4 | **氛围光晕（壳层顶部）**：top_nav 下沿一条 accent 极淡渐变过渡带（≤6%） | `top_nav.dart` 或 `app_shell.dart` | 弱到不干扰内容，只提供「发光的顶」的感知 |
| 3.5 | **页面切换过渡**：`NoTransitionPage` → fade-through（op0→1 180ms，y+8→0；反向对称） | `app_router.dart` `_shellPage` | 所有 `_shellPage` 统一；`_RouteFallback` 不动 |
| 3.6 | **骨架屏 shimmer**：房间网格、搜索结果、关注列表加载态——线性扫光矩形替换 `CircularProgressIndicator` | `room_grid.dart`、`search_view.dart`、`follow_view.dart`（首屏加载分支） | 卡片形状的 skeleton；reduce_motion 时静态骨架不扫光 |
| 3.7 | 浮层（flyout/弹出菜单）入场：现有 `normal` 档基础上加 opacity 0→1 + scale 0.98→1 | `category_flyout.dart`、`my_category_flyout.dart`、`user_area.dart` | 只加 opacity/scale，位移已有则不动 |

## 4. 明确不做（防蔓延）

- ❌ 改任何布局结构、断点、信息层级（那是 `refactoring-ui` 轨的事，另开任务）
- ❌ 换平台色/强调色（`f41ca59` 刚裁决过，不重开）
- ❌ 毛玻璃铺满所有 surface（只做 3.1/3.2 两处，blur ≤ 20）
- ❌ page transition 用滑动大位移（fade-through + 8px，避免桌面端晕动）
- ❌ Lottie/外部动画资源（全部用 Flutter 原生 AnimationController / implicit animation）

## 5. 验收流程（每项通用）

1. 实现清单项 → `flutter analyze` + `tool/check.ps1`（裸值守卫零新增）
2. 受影响 golden：对着清单项逐个 `--update-goldens`，diff 目检后随该功能提交入库
3. 动效类（2.x 脉冲流光、3.5 过渡、3.6 扫光）静态 golden 看不出 → 记入本表「真机验收」列，分支完成后你本机 `flutter build windows --debug -t lib/main.dart` 录屏统一验收
4. 每提交一条：中文 commit message，UI 轨独立

## 6. 进度打钩

- [x] 1.x Token 层（`0af4d24`）
- [x] 2.1 卡片 hover 抬升发光（`fdda680`）
- [x] 2.2 CTA 流光（`fdda680`）
- [x] 2.3 红点脉冲（`fdda680`，按裁决仅落 state_dot，暂无可见消费点）
- [x] 2.4 热度发光（`fdda680`）
- [x] 2.5 pressed 缩放（`fdda680`，仅两主 CTA，§4.2/§7 已补豁免注记）
- [x] 3.1 毛玻璃 top_nav（`3e8338d`）
- [x] 3.2 毛玻璃侧栏（`3e8338d`，常规布局像素零变化）
- [x] 3.3 播放页光晕（`3e8338d`，按裁决为常规布局渲染/失焦与沉浸态不渲染）
- [x] 3.4 壳层顶部光带（`3e8338d`）
- [x] 3.5 页面过渡（`a5708a8`，fade-through 180ms）
- [x] 3.6 骨架屏 shimmer（`0338f35`，follow_view 落点偏差已裁决 q1-A）
- [x] 3.7 浮层入场（`3e8338d`，user_area 无 scale 属裁决 3 批准偏差）
- [ ] 真机录屏验收

## 附：本次配套 skill（已装 `.agents/skills/`，均 MIT）

- `motion-design`（LottieFiles）—— 2.x/3.x 动效参数依据
- `refactoring-ui` —— 防氛围化改花哨的纪律约束
- `qiaomu-design`（裁剪安装）—— 视觉 QA 与风格顾问
