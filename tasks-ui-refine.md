# tasks-ui-refine.md — UI 截图对齐：并行分工看板

> 基线：`feat/a11-nav-capability` 分支，`flutter analyze` 0 issue / 已有 UI 测试通过。
> 对照源：`tool/screenshots/sfvideo/` + `SFVideoLive/apps/web/src/styles/theme.css` + `docs/ui-parity/spec-layout.md`。
> 规则：每个轨只改自己独占文件；收口轨最后改 `play_view.dart` / `play_side_panel.dart` / `app_shell.dart`。

## 已确认对齐（不需要再动）

| 项 | SFVideo | zishu 现状 | 结论 |
|---|---|---|---|
| `liveBadge` 色 | `#32c874` | `#32C874` | ✅ 一致 |
| 播放页关注色 | `#582626` | `AppColors.playFollowBg` | ✅ 一致 |
| 播放页超关色 | `#442D5B` | `AppColors.playSuperBg` | ✅ 一致 |
| 播放页统计色 | audience/vip/svip 三套 | `AppColors.playStat*Text` | ✅ 一致 |
| 侧栏关注/超关按钮 | 使用 `--play-follow-*` | 已用 `AppColors.playFollow*` | ✅ 一致 |
| 断点数值 | 640/768/1024/1366/1920 | `AppBreakpoints` 同值 | ✅ 一致 |
| 顶部导航高 44px | `nav-height: 44px` | `topNavHeight = 44` | ✅ 一致 |
| 底部导航高 56px | `nav-height: 56px` | `bottomNavHeight = 56` | ✅ 一致 |
| 抽屉展开 220px | `--directory-drawer-width: 220px` | `width = 220` | ✅ 一致 |
| 房卡 16:9 封面 | `aspect-ratio: 16/9` | `cardWidth*9/16` | ✅ 一致 |

## 待处理差距（按文件隔离拆轨）

### T1：error 色统一 + 动效时长对齐

**独占文件**：`lib/src/shared/presentation/design_tokens.dart`

| 差距 | SFVideo | zishu 现状 | 改动 |
|---|---|---|---|
| error 色 | `#E55050` | `#F56C6C` | 改为 `#E55050` |
| fast 动效 | 150ms | 120ms | 改为 150ms |
| normal 动效 | 250ms | 200ms | 改为 250ms |
| easing 曲线 | `cubic-bezier(0.16, 1, 0.3, 1)` | `easeOutCubic` | 新增自定义曲线 |

**验证**：`flutter analyze` 0 issue + `flutter test test/ui/workflows/settings_test.dart`

**结论（2026-09-21 核对）**：✅ 代码已落地（`error` 色 `#E55050`、`AppMotion` 150/250ms +
`Cubic(0.16,1,0.3,1)` 均在 `design_tokens.dart`，`test/shared/design_tokens_test.dart` 已钉死）。
本次只需回填看板，无需再动代码。

### T2：抽屉收起态 rail 视觉宽度

**独占文件**：`lib/src/shared/presentation/design_tokens.dart`、`lib/src/features/browse/widgets/browse_sidebar.dart`

| 差距 | SFVideo | zishu 现状 | 改动 |
|---|---|---|---|
| rail 视觉宽度 | ~28px | 52px | 新增 `visualRailWidth = 28`，布局宽度改为 28px，点击热区通过 padding 保持 52px |

**验证**：`flutter analyze` + `test/ui/workflows/browse_sidebar_test.dart` + `test/ui/workflows/responsive_skip_test.dart`

**结论（2026-09-21 复核）**：❌ **看板漂移，无需改动**（本轮尝试后已回退）。

- 真源是 **52px**：`main.css:39 --directory-rail-width: 52px`、
  `DirectoryDrawer.vue:660 .directory-drawer { width: var(--directory-rail-width) }`、
  `AppLayout.vue:216 margin-left: var(--directory-rail-width)`；
  rail 内平台按钮 `DirectoryDrawer.vue:976-988 .directory-drawer__rail-platform { width: 100% }`
  —— 32px 图标在 52px 列里不会溢出。
- 「≈28px」来自 `docs/ui-reference/README.md:49`，而同文件第 39 行的 28px 是**顶栏平台 tab**
  在 768–1080 的收缩值，被错移植到了抽屉 rail 上。
- 处理：回退 `browse_sidebar.dart`；删除 `AppDirectoryDrawer.visualRailWidth` 及其断言；
  已订正 `docs/ui-reference/README.md:49/69`；`browse_sidebar_test.dart` 补了「持平 52px」来源断言。
- 附带发现（不属本卡）：28px 布局宽在 Flutter 里做不到「横向热区仍 52px」——命中测试不超过
  父盒边界，面板 28px 宽时横向热区最多 28px。现状 52px 无此问题。

### T3：房卡徽章象限对齐

**独占文件**：`lib/src/features/browse/widgets/room_card.dart`、`docs/ui-parity/spec-layout.md`

| 差距 | SFVideo | zishu 现状 | 改动 |
|---|---|---|---|
| 平台 badge 位置 | 右下（与热度并列） | 左下 | 平台 badge 移到右下角热度左侧 |
| 热度位置 | 右下 | 右下 | 保持 |
| 分类位置 | 左上 | 左上 | 保持 |

**验证**：`flutter analyze` + 截图对比 `tool/screenshots/sfvideo/1920x1080_desktop_home.png` 卡片区

**结论（2026-09-21 复核）**：❌ **看板漂移，无需改动**（象限保持：左上分类 / 左下平台 / 右下热度）。

- 真源 `RoomCard.vue:262-273`：`.room-card__foot-left { position:absolute; left:0; bottom:0;
  max-width:72% }` + `:deep(.platform-cover-badge) { border-radius: 0 8px 0 0 }` → 平台 badge
  **左下**；热度是另一个 `.cover-online-badge` 在**右下**（两角分居，不是并列）。
- `docs/ui-parity/spec-layout.md:67` 也记的是「封面 bottom-left 角标」，与真源一致。
- 真源截图 `360x640_mobile_home.png` / `1920x1080_desktop_home.png` 均为「左下平台 + 右下热度」。
- 处理：不改 `room_card.dart` 象限（也不因此更新 golden）；在
  `test/ui/workflows/room_card_badges_test.dart` 里补了真源出处注释作为防回摆。

### T4：移动底栏项数裁决

**独占文件**：`lib/src/app/app_shell.dart`（仅 `_BottomNav` 类）

| 差距 | SFVideo | zishu 现状 | 改动 |
|---|---|---|---|
| 底栏项数 | 6 项 | 8 项 | 裁决后裁剪到 6 项 |

SFVideo 底栏实际为：紫薯 logo / 首页 / 分类 / 关注 / 搜索 / 我的。
zishu 当前额外有"动态"和"主题"。建议将"主题"移入设置页，"动态"在桌面顶栏入口已够用。

**验证**：`flutter analyze` + `test/ui/workflows/navigation_test.dart` + `test/ui/workflows/mobile_phones_test.dart`

**结论（2026-09-21 复核）**：✅ 已执行 **只裁「动态」**，底栏 = **8 项**；看板两行说明本身有误。

- 真源底栏（截图 `tool/screenshots/sfvideo/360x640_mobile_home.png` 与 `640x800_compact_home.png`，
  外加 `docs/ui-reference/README.md:44`）= 紫薯 logo / 首页 / 分类 / 我的分类 / 关注 / 搜索 /
  **主题(月亮)** / 我的 —— **没有「动态」**，**有「主题」**。看板写的「6 项…没有主题」与真源不符。
- 改动：`lib/src/app/shell/bottom_nav.dart` 移除 `nav-time` 项（真源本来就无此项），保留「主题」
  与「我的分类」；`/timeline` 路由可达性由新增用例
  `test/ui/workflows/shell_mobile_align_test.dart`「移动底栏裁掉「动态」后,/timeline 路由仍可达且顶栏入口保留」
  钉死（桌面顶栏 `nav-time` 入口 + `router.go('/timeline')` 两条断言）。
- 执行后底栏项序与 640px 真源截图逐项一致：品牌/首页/分类/我的分类/关注/搜索/主题/我的。
- **已知差异（本卡不做，产品裁决后再定）**：
  1) 360px 真源会隐藏「我的分类」（7 项），zishu 用 `FittedBox scaleDown` 全保留 8 项；
  2) zishu 比 `docs/ui-reference/README.md:44` 多一个「我的」（挂 `/settings`、承担 `nav-settings`
  锚点契约），保留不删。
- 验证命令：`flutter test test/ui/workflows/shell_mobile_align_test.dart`（含项序 + 路由可达性）
  与 `test/ui/workflows/navigation_test.dart`、`test/ui/workflows/mobile_phones_test.dart` 全绿。

### T5：golden 基线更新

**独占文件**：`test/ui/follow_style_shot_test.dart`、`test/ui/hover_shot_test.dart`、`test/ui/*.png`

| 差距 | 状态 | 改动 |
|---|---|---|
| follow_style_card.png | 失败 0.30% | 确认变化正确后 `--update-golden` |
| follow_style_tile.png | 失败 1.26% | 同上 |
| follow_style_row.png | 失败 1.26% | 同上 |
| hover_platform_categories.png | 失败 1.03% | 同上 |
| hover_follow_grid.png | 失败 1.21% | 同上 |
| hover_my_category.png | 失败 0.97% | 同上 |

**前提**：T1-T4 全部完成后才做，避免重复更新。
**验证**：`flutter test test/ui/follow_style_shot_test.dart test/ui/hover_shot_test.dart` 全绿

**结论（2026-09-21 核对）**：✅ 6 张（实际 **7 张**）golden 在代码里已完成，本波 **无需更新任何 png**。

- 实际 golden 集合（`matchesGoldenFile`）：`follow_style_card.png`、`follow_style_row.png`、
  `play_style_recommend.png`、`play_style_follow.png`、`hover_platform_categories.png`、
  `hover_follow_grid.png`、`hover_my_category.png`（看板写的 `follow_style_tile.png` 不存在，
  且漏记 play_style 两张）。
- 本轮 `flutter test test/ui/follow_style_shot_test.dart test/ui/hover_shot_test.dart` = **7 通过 0 失败**，
  `test/ui/failures/` 未产生新差异图，故未执行 `--update-goldens`。
- 原因是本波最终**没有改动桌面视觉**：T2 已回退、T3 判定为看板漂移不动象限、T4 只动手机底栏
  （6 张 golden 全是桌面场景，不含底栏）。

## 执行顺序

```text
T1 + T2 + T3 + T4 并行（文件级隔离）
  ↓ 全部完成
T5 串行更新 golden
  ↓
全量 flutter test + flutter analyze
```

## 收口验证

```bash
cd F:\project\zishu_flutter
F:\flutter\bin\flutter.bat analyze
F:\flutter\bin\flutter.bat test
```
