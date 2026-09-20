# 代码简化与模块化复用分析

> 生成:2026-09-20。范围:`lib/src`(30,764 行 / 约 300 文件)。
> 方法:全库扫描(巨文件 TOP、重复符号 grep、私有 helper 清点)+ 近四轮改动亲历记录。
> 状态标记:[ ] 待办 / [x] 已完成。

## 1. 巨文件拆分(可读性/可维护性)

| 文件 | 行数 | 构成 | 拆分建议 |
|---|---:|---|---|
| `app/app_shell.dart` | 2686 | 32 个类:顶栏/底栏/平台条/分类浮层/登录框/我的分类/主题切换 | 拆 `app/shell/`:`top_nav.dart`、`bottom_nav.dart`、`platform_strip.dart`、`category_flyout.dart`、`login_dialog.dart`、`my_category_menu.dart`、`user_avatar.dart` |
| `play/widgets/play_side_panel.dart` | 2684 | 27 个类:侧栏头/聊天 tab/关注 tab/推荐 tab/设置 tab/弹幕徽章 4 类 | 拆 `play/widgets/side_panel/`:`side_header.dart`、`chat_tab.dart`、`chat_row.dart`、`chat_badges.dart`、`follow_panel.dart`、`recommend_panel.dart`、`settings_panel.dart`;`PlaybackStatus` 移 domain |
| `shared/domain/cross_categories_data.dart` | 2508 | 编译期内嵌映射表(设计如此) | 不拆 |
| `play/views/play_view.dart` | 1204 | 头部徽标/舞台/呈现态/快捷键/多布局分支 | 拆 `play_header.dart`(返回+分类徽标+标题);布局分支抽 `play_layout.dart` |
| `play/widgets/player_controls.dart` | 1004 | 控制条+画质/线路下拉+睡眠+弹字方块+popover | 拆 `controls/`:`danmaku_settings_button.dart`(含面板)、`quality_line_selects.dart`、`sleep_timer_button.dart` |

## 2. 重复模式 → 共享提取

| # | 重复 | 位置 | 提取目标 | 优先级 |
|---|---|---|---|---|
| 2.1 | 房间统计取数(关注条目→roomStats 兜底)两份相同逻辑 | `play_meta_bar.dart:70-81`、`play_side_panel.dart:383-387` | provider 家族扩展:`roomStatsTextProvider((site,roomId))` 返回格式化后的 (followers/online/vip) 三元组,两处 UI 只读文本 | P1(有行为一致性风险:格式化只改了一边) |
| 2.2 | 万格式化 `_formatFollowersText`/`_statText` 两份 | `play_side_panel.dart:525/532`、`play_meta_bar.dart:202` | `shared/domain/number_format.dart`:`formatCountWan()` + `statOrDash()` | P1 |
| 2.3 | 「重试」按钮五处几乎相同 | `home_view`/`category_view`/`play_view`/`follow_view`/`follow_empty_state` | `shared/presentation/widgets/retry_button.dart` | P2 |
| 2.4 | 滑杆设置行三份 | popover `_settingsRow`+`_settingsSlider`、`danmaku_settings_panel._SliderRow`、侧栏 `_SettingSliderRow` | `shared/presentation/widgets/settings_slider_row.dart`(已走 AppControls 规格) | P2 |
| 2.5 | SliderTheme 局部覆盖三处 | `player_controls.dart:237/959`、`play_side_panel.dart:2566` | 全局 `sliderTheme`(AppControls)已落地——删除与全局相同的局部覆盖,仅保留真差异(如控制条主滑杆的宽度布局) | P3 |
| 2.6 | 下拉选择(PopupMenuButton+勾选行)五处 | 画质/线路/区域/搜索/其他 | `shared/presentation/widgets/select_box.dart`(泛型:条目/当前值/渲染标签) | P3 |
| 2.7 | 描边 pill 文字按钮 | `_SideTextAction`、app_shell 分类 chip 等 | `shared/presentation/widgets/pill_text_button.dart`(可选) | P3 |

## 3. 遗留清理

- [x] `_MiniSwitch`(play_side_panel 私有)→ 并入全局 `CompactSwitch`,删除私有类(2026-09-20,含补漏 2 处调用)
- [x] `AppColors.brand` 死常量删除(2026-09-20)
- [x] `AppControls.switchScale` 死常量删除(CompactSwitch 自绘不消费)(2026-09-20)
- [ ] `_settingsSlider`/`_settingsAreaRow`/`valueBadge`(player_controls)在 2.4 落地后删除
- [ ] `follow_entry_row.dart` 与 `follow_entry_card.dart` 的行/卡双实现核对(列表/卡片两态是否可参数化合一)

## 4. 模块边界核对(无违规)

- `player_controls` import danmaku 域 provider:app→feature 方向 ✓
- `room_stats_provider` 经 `shared/application/providers` 取 refresher:不反向依赖 follow 域 ✓
- 解析包无 Flutter/UI 依赖 ✓

## 5. 建议执行顺序

1. P1:2.1+2.2(统计取数与格式化统一——已有行为不一致风险:万格式化只在侧栏头生效、主播卡仍原始数字)
2. P2:2.4 滑杆行统一 → 2.3 重试按钮
3. P2:`play_side_panel.dart` 拆分(最大收益:当前 2684 行/27 类)
4. P3:`app_shell.dart` 拆分、2.5/2.6/2.7、第 3 节剩余清理
