---
name: vue-ui-to-flutter
description: 把 SFVideoLive/web 的 Vue 组件与视图移植为 zishu_flutter 的 Flutter Widget。当用户要求移植/复刻/对齐某个 SFVideoLive 页面或组件(如 HomeView、PlayView、RoomGrid、RoomCard、AppLayout、CategoryIndexView、FollowView 等)到 Flutter,或提到 "web 转 Flutter"、"复刻旧 UI"、"按 Vue 参考画页面" 时使用。不适用于解析/弹幕/播放器内核逻辑。
---

# Vue UI → Flutter Widget 移植

把 `D:\gitProject\SFVideoLive\web\src` 下的 Vue 3 组件移植为 `D:\gitProject\zishu_flutter\lib\src` 下的 Flutter Widget。目标是**布局、样式、交互对齐**,不是逐行翻译;禁止把 Vue 运行时/WebF 嵌入 Flutter,禁止复制 Vue 文件到新工程。

## 开始前必读(按需加载,不要跳过)

1. `D:\gitProject\zishu_flutter\AGENTS.md` — 目录与依赖边界(新代码在 `lib/src/`,禁止 import `lib/legacy/`)。
2. `D:\gitProject\zishu_flutter\docs\implementation-plan.md` 第 6 节 — 视觉基线、路由清单、页面功能目标。
3. 待移植的 Vue 源文件(views + 它 import 的 components/composables/styles)。
4. `D:\gitProject\zishu_flutter\lib\src\shared\presentation\` — 已有 design tokens,禁止在 Widget 里写裸色值/裸数字。

## 工作流

1. **定位源**:在 `SFVideoLive/web/src/views/` 与 `components/` 找到目标组件;`.vue` 文件的 `<style>`(含 scoped 和引入的 `src/styles/*.css`)是样式的唯一真源。
2. **提取视觉规格**:颜色、间距、圆角、字号、断点先归一到 design tokens(见下表);tokens 里没有的新值先补进 tokens 文件再使用。
3. **映射结构**:按下方对照表把 template → Widget 树,数据绑定 → 构造参数/controller 状态;composables 逻辑不放 UI,放 `features/<f>/application/` 的 controller。
4. **数据解耦**:Widget 只消费稳定 Dart model(来自 `shared/domain` 或 fixtures),禁止 `Map<String, dynamic>` 直接进 UI;解析数据未就绪时用 `FixtureLiveRepository` 样例数据驱动样式。
5. **验证**:`flutter analyze` 0 issue;改动涉及主链路时再跑 `flutter build windows --debug -t lib/main.dart`;纯样式改动至少写一个 widget test 或 golden test 锁布局。

## Vue → Flutter 对照

| Vue/Web | Flutter |
|---|---|
| `<template>` 根节点 | `build()` 返回的根 Widget(不必一一对应) |
| `v-if / v-else` | 条件表达式 + collection-if,或提前 return 不同 Widget |
| `v-for` | `for` collection-for 或 `.map()` 进 `children:` |
| `:class="{ active: x }"` | 条件 `BoxDecoration`/`TextStyle`,封装成私有 getter |
| scoped `<style>` | `BoxDecoration`、`Padding`、`Container` 等,值取自 tokens |
| flex 布局 | `Row`/`Column` + `MainAxisAlignment`/`CrossAxisAlignment` |
| `display: grid; grid-template-columns: repeat(auto-fill, minmax(220px,1fr))` | `LayoutBuilder`/`Wrap`/`GridView.builder` + `SliverGridDelegateWithMaxCrossAxisExtent` |
| `position: fixed` 顶栏 | `Scaffold` + 顶部固定 `PreferredSize`/Column 结构 |
| `<transition>` | `AnimatedContainer`/`AnimatedOpacity`/`SlideTransition` |
| `@click` | `onTap`/`GestureDetector`/`InkWell` |
| props + emit | 构造参数 + `VoidCallback`/`ValueChanged` 回调 |
| composable(useXxx) | `ChangeNotifier`/`ValueNotifier` controller,Widget 只读状态 |
| `ref/reactive` 状态 | controller 字段 + `notifyListeners` 或 `ValueListenableBuilder` |

## 视觉 token 基线(SFVideoLive 深色主题)

```text
页面背景 #181818   elevated surface #1f1f1f   soft surface #141414 / #2a2a2a
品牌金 #f3d04e     主文字 white 87%          次文字 white 55%
边框 #3a3a3a      圆角 4/8/12px 三级         顶部导航高约 44px,底部导航约 56px
断点 640/768/1024/1366/1920   平台品牌色:斗鱼橙、虎牙黄、B站粉蓝、抖音红、Twitch 紫
```

落点:`lib/src/shared/presentation/` 下 `AppColors`、`AppSpacing`、`AppRadius`、`AppTypography`、`AppMotion`、`PlatformBrandCatalog` + `ZishuTheme`(浅色同步,深色为 Windows 验收基线)。

## 响应式导航收缩规范(源自 SFVideoLive 实测行为)

顶部固定导航(44px)高度有限,平台项过多时按宽度分级收缩,优先级:横向滚动 > icon 收缩 > 换行:

1. **≥1024px**:平台 tab = 品牌色点 + 文字;放不下时横向滚动条(单行 `ListView` horizontal)+ 右缘渐隐遮罩提示可滚,对齐原版 `PlatformTabs.vue` 的 scrollable nav。
2. **768–1023px**:tab 收缩为仅品牌色点(`Tooltip` 保留名称),工具区 icon 按钮(`IconButton`)不变——"icon+文字 → 仅 icon"原则。
3. **<768px**:主导航切换到底部 56px(implementation-plan 6.2);平台列表变顶部横向 strip,仍单行滚动。
4. **多行 `Wrap`(spacing/runSpacing)只用于内容区**:左侧目录 drawer、分类面板、首页筛选 chips——对齐原版 `NavPlatformStrip.vue` 的 `flex-wrap: wrap` 用法;禁止在 44px 顶导航里换行(会撑高或裁切)。

Flutter 落点:`LayoutBuilder` + `AppBreakpoints` 分支;icon-only 判断用 `constraints.maxWidth`;不需要引入 adaptive_scaffold 等依赖,自绘组件用 LayoutBuilder 足够。

**展开细节**(Overflow 归因三步法、响应式工具箱选型表、SafeArea/键盘 insets 所有权、大字体兜底)按需读取 `references/responsive.md`,不要跳过它直接发明断点规则。

## 硬约束

- 不 import `package:zishu_flutter/legacy/...`;Web 专属 API(`dart:js_interop`、`package:web`、`HtmlElementView`)只允许出现在 legacy 或 `src/platforms/web/`。
- 不把 CSS 数值散落在 Widget 里;一律走 tokens。像素级还原优先于"看起来像"。
- 路由语义对齐 SFVideoLive(`/all`、`/:site/play/:id` 等,见 implementation-plan.md 6.3),route 参数只存 site/id/cid。
- 播放器 Widget 不承担重试/选线/状态机;播放统一走 `LivePlayer` 抽象 + media-kit adapter。

## 输出要求

每次移植结束输出:改动文件清单、`flutter analyze`/test 结果、与 Vue 原版的已知差异(截屏或描述),并更新 `tasks.md` 对应卡片状态。
