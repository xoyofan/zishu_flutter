# Wave 5:遗留收口并行计划(2026-09-19)

> 基线:app 569/0;parser 336/10skip;analyze 双 0。

## 轨 A 表情渲染接线 —— 独占:play_side_panel 聊天行 + danmaku_style
segments 契约已就绪(N2),渲染未接线:
- 聊天行正文按 segments 展开:文本段 TextSpan、表情段 WidgetSpan(Image.network url,边长=字号×1.6;url 空/失败回退「[名]」文本)。
- 飘屏 buildSpan:表情段以「[名]」文本参与(纯文本绘制)。
- 测试 +2。

## 轨 B B站画质重复排查修复 —— 独占:bilibili 解析 + player_controls 菜单构建
用户报告「bili 清晰度多级重复」。解析档位表(qn/name 唯一)与 accept_qn 并集无重复来源;用真实探针打印 resolve 的 streams/availableQualities 确认;若解析无重,排查 UI 菜单构建(availableQualities 与 qualities 双源/concat)。修复到菜单无重复。

## 轨 C 壳层主题切换 —— 独占:app_shell.dart(顶栏/底栏 nav-theme)
顶栏与移动底栏的 nav-theme 死按钮接深浅切换(settingsProvider.themeMode,对齐 web NavSidebar label 随目标态)。移动底栏空 onTap 同修。

## 轨 D(主代理)开播提醒到点通知 —— 独占:follow_provider poller + 播放页提示
FollowStatusPoller 刷新发现「离线→在播」跃迁且 remindOn=true 时,应用内提醒(SnackBar/横幅,含主播名),同会话每主播只提醒一次。

## 不做(维持 backlog)
徽章 gif 动态(需虎牙 CDN 资源调研)、B站 wealth、关注批量导入、首页直达表单、移动目录抽屉、pad-x 10.4、1920 底部工具栏、单清晰度解析(soop)。
