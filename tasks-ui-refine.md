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

### T2：抽屉收起态 rail 视觉宽度

**独占文件**：`lib/src/shared/presentation/design_tokens.dart`、`lib/src/features/browse/widgets/browse_sidebar.dart`

| 差距 | SFVideo | zishu 现状 | 改动 |
|---|---|---|---|
| rail 视觉宽度 | ~28px | 52px | 新增 `visualRailWidth = 28`，布局宽度改为 28px，点击热区通过 padding 保持 52px |

**验证**：`flutter analyze` + `test/ui/workflows/browse_sidebar_test.dart` + `test/ui/workflows/responsive_skip_test.dart`

### T3：房卡徽章象限对齐

**独占文件**：`lib/src/features/browse/widgets/room_card.dart`、`docs/ui-parity/spec-layout.md`

| 差距 | SFVideo | zishu 现状 | 改动 |
|---|---|---|---|
| 平台 badge 位置 | 右下（与热度并列） | 左下 | 平台 badge 移到右下角热度左侧 |
| 热度位置 | 右下 | 右下 | 保持 |
| 分类位置 | 左上 | 左上 | 保持 |

**验证**：`flutter analyze` + 截图对比 `tool/screenshots/sfvideo/1920x1080_desktop_home.png` 卡片区

### T4：移动底栏项数裁决

**独占文件**：`lib/src/app/app_shell.dart`（仅 `_BottomNav` 类）

| 差距 | SFVideo | zishu 现状 | 改动 |
|---|---|---|---|
| 底栏项数 | 6 项 | 8 项 | 裁决后裁剪到 6 项 |

SFVideo 底栏实际为：紫薯 logo / 首页 / 分类 / 关注 / 搜索 / 我的。
zishu 当前额外有"动态"和"主题"。建议将"主题"移入设置页，"动态"在桌面顶栏入口已够用。

**验证**：`flutter analyze` + `test/ui/workflows/navigation_test.dart` + `test/ui/workflows/mobile_phones_test.dart`

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
