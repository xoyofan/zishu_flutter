# zishu_flutter 播放域对齐 SFVideoLive 计划(2026-09-19)

> 调研来源:三路只读扫查(聊天徽章 36 项 / 侧栏密度 19 项 / 播放页 38 项),
> 差异数值以调研结论为准(本文只列执行项;web 真源文件:行号在各轨任务里)。
> 基线:app 507 passed / 0 failed;parser 301 passed / 10 skipped;analyze 双 0。

## 执行环境与约束

- 沙箱搬运器:`C:/Users/Administrator/.workbuddy/binaries/python/versions/3.13.12/python.exe` +
  `C:/Users/Administrator/WorkBuddy/2026-09-18-10-56-54/_frun.py <root> <flutter args>` / `_dartrun.py`。
- **子代理禁止 git commit/add**;主代理单写者收尾。
- 文件归属矩阵(冲突红线):
  | 轨 | 独占文件 |
  |---|---|
  | 轨1 侧栏 | `lib/src/features/play/widgets/play_side_panel.dart` |
  | 轨2 控制条 | `lib/src/features/play/widgets/player_controls.dart`、`play_immersive_side_sheet.dart` |
  | 轨3 弹幕 | `lib/src/features/danmaku/**`(settings/settings_panel/dialog/overlay/style) |
  | 轨4 主代理 | `lib/src/features/play/views/play_view.dart`、`play_meta_bar.dart`、`packages/live_parser/**`(badge 色契约) |
  | 共享只读 | `app_shell.dart`、`app_router.dart`、`design_tokens.dart`(除既有)、`zishu_tokens.dart` |
- 每轨完成后跑自己的相关测试 + analyze;主代理收尾跑 `_gate.py --goldens`。

## 轨1 侧栏(play_side_panel.dart)

徽章(文字态全对齐,图片态/超粉V/guard 本轮不做——契约缺口大,另立项):
1. `_BadgeBox` 渐变方向:默认 `begin=centerLeft`(CSS 90deg=A 在左);B站改为 `to left` 语义=colorStart 在右(现实现整体镜像)。
2. 尺寸对齐 em(≈14px 基):虎牙条 14→16、圆盘 12→10/字 8.5→9.4、团名 9→11;B站胶囊 15→21/字 9→12.6、UL 改圆胶囊(999);抖音盘 14→19.6/字 9→11;斗鱼 LV 16 保持。
3. 斗鱼粉丝牌:隐藏等级数字(只显示团名;web `CHAT_FAN_BADGE_HIDE_LEVEL_SITES`),去梯度兜底(改中性深底白字;web 文字态无梯度)。
4. B站粉丝牌:去梯度兜底(无协议色→中性深底);start/end 互补缺省(`start=colorStart||colorEnd`);消费协议文字色 `badgeTextColor`/等级色 `badgeColorLevel`(轨4 契约配套)。
5. 默认平台等级 label:`Lv $level`→`$level`(web userLevel 默认纯数字,#6b7280 不变)。
6. 徽章间距 3→2。

侧栏密度:
7. 设置 tab 开关:裸 Switch → 自绘 30×16 小开关(轨道 30×16 圆角 8、滑块 12,选中 #f3d04e、关闭描边 #3a3a3a);key/语义不变(side_panel_features_test A9 依赖)。
8. TabBar 高度 →32px(web `--el-tabs-header-height: 2rem`),label 12.5。
9. 设置组圆角 4→8、组标题 11→12.5。
10. _SideHeader 头像 54→64(贴边出血,顶满头高)。
11. 聊天 tab:刷新按钮补「刷新」文字(高 24);消息 12→14、行高 1.48、去 maxLines 2;「N 条新消息」移底部水平居中、字号 10→12。

## 轨2 控制条(player_controls.dart + play_immersive_side_sheet.dart)

1. 按钮顺序对齐 web:左组[播放/暂停, 刷新](按钮组)→弹幕开关→飘屏设置;右组:音量→画质→线路→PiP;全屏独立最右。「直播中·低延迟追帧中」文案与睡眠定时保留(flutter 超集,放左组尾部)。
2. 弹幕开关 →「弹」字方框徽标(边框 2px 圆角 5 + 选中 √ 角标 amber);飘屏设置 →「弹」方框+齿轮角标,打开态 amber。
3. 图标 20→22、按钮高 48→41、条 padding .28rem .65rem。
4. 控制条背景:渐变→纯色 rgba(0,0,0,0.72)(play_view.dart 的渐变容器在轨4?——容器在 play_view.dart,轨2 只改控件条自身背景声明;容器渐变由轨4 移除)。
5. 音量滑杆:白系(track 4、thumb 14 纯白、runway 白 22%、填充白);compact 仍 52px 宽不隐藏。
6. 画质入口加 settings 前置图标;线路入口加 list 图标 + 仅 `lines.length>1` 渲染。
7. 画质/线路菜单暗色皮肤(rgba(20,20,20,.95)、边框白 12%、选中 amber+amber14%)。
8. 全屏按钮组改单态切换(webFullscreenMode 语义:常规→网页全屏?否——web 单钮在 webscreen 模式下发 webscreen;保持现行为:单击=系统全屏,网页全屏并入?)→ **裁决:保留双钮(flutter 超集),只统一图标语言**;本项缩水为图标对齐。
9. play_immersive_side_sheet:把手宽 13.1→18.4、圆角 8→4。

## 轨3 弹幕域(lib/src/features/danmaku/**)

1. `danmaku_settings.dart`:默认速度 7→5;显示区域 5 档→4 档(去 0.125);持久化 clamp 兼容旧值。
2. `danmaku_settings_panel.dart`:加标题行「飘屏弹幕」+「显示」开关行(接 danmakuEnabled);滑杆行改单行三列(label 2.4rem / 滑杆 / amber 值右对齐);文案「不透明度→透明度」「20px→20」;区域档位控件 SegmentedButton→Dropdown(4 档全屏/3/4/半屏/1/4)。
3. `danmaku_overlay.dart`/`danmaku_style.dart`:行高公式 `fontSize*1.4`→`fontSize*1.52+6`;顶部 topPadding 8→0。描边/用户名段保留(flutter 超集,可读性优先,记录)。

## 轨4 主代理(play_view.dart + play_meta_bar.dart + parser 契约)

1. `_RoomHeader`(play_view.dart):高度 44→自适应内容(padding .28/.5/.32rem);返回钮点击区 48→32;分类徽标 = 平台图标 + 分类文字 + 内嵌星标(CategoryColors 底,字 clamp≈12);标题去 `category · ` 前缀(仅 title);舞台容器加 12px 圆角(≤640 为 0)。
2. `play_meta_bar.dart`:高 64→44、头像 34→52 左贴边(圆角 0 0 2 0)、关注/超关列宽 72→59、字号 11→10.5。统计 3 行结构推迟(数据层无 followers/audience)。
3. parser:`DanmakuMessage` 增 `badgeTextColor`/`badgeColorLevel`(0xRRGGBB,0=未提供);bilibili danmaku 新协议 `v2_medal_color_text`/`v2_medal_color_level` + 老结构无对应(0);测试 +2。供轨1 消费。

## 收尾(主代理)

`_gate.py --goldens` → 差异定性 → 分轨提交(轨1/轨2/轨3/轨4-parser 各一笔,docs 一笔)→ 推送 → release 重建 → schtasks 拉起复验。

## 本轮明确不做(记录)

- 徽章图片态全套(契约 bgUrl/iconUrl/fallback 状态机)、虎牙超粉 V、B站 guard/wealth、twitch/soop/yy 徽章 —— 契约缺口大,单独立项。
- 控制条 ≤420 音量浮层、三档容器密度;弹幕设置浮层锚定形态(保留对话框);飘屏速度连续模型重构;侧栏 pad-x 10.4 全局替换;侧栏头通知/外链死按钮接通(需行为定义)。
- 桌面侧栏头统计真实数据(followers/audience 数据层缺口)。
