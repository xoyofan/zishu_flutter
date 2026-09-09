# Flutter 响应式布局详解(Overflow 归因、收缩策略、SafeArea/大字体)

> 整合来源:bladeofgod/flutter-ai-harness 的 flutter-layouts skill(约束归因/Overflow/SafeArea 所有权思想)、
> awesome-omni-skills/flutter-expert(LayoutBuilder+MediaQuery、多形态适配)、Flutter 官方惯用法,
> 结合本项目 SFVideoLive 移植实践。SKILL.md 的「响应式导航收缩规范」是摘要;本文件是展开。

## 1. 溢出(Overflow)归因三步法

`RenderFlex overflowed by N pixels` 只是症状,先归因再改布局:

1. **不可收缩内容塞进有限宽度**:Row 里放了长文本/固定宽 child 且无 Expanded/Flexible → 给文本 `Expanded + maxLines + ellipsis`,或让卡片走 `Wrap`。
2. **unbounded constraints**(无界约束):ListView/Row/Column 嵌套在横向 unbounded 环境里又想撑满 → 用 `ShrinkWrappingViewport`、给外层定 `AspectRatio`/固定 extent,或换 `Sliver` 结构。
3. **外部变窄超出设计最小宽**:布局本身没错,窄视口触发 → 这是响应式问题,走第 2 节收缩策略,不要用 `SingleChildScrollView` 横向滚硬扛。

## 2. 响应式工具箱(按场景选型)

| 场景 | 工具 | 备注 |
|---|---|---|
| 结构级分支(导航切换/栅格列数) | `LayoutBuilder` + `AppBreakpoints` | 判 `constraints.maxWidth`,不要用 `MediaQuery.size`(窗口尺寸 ≠ 可用宽度,桌面分栏后不同) |
| 平台项过多 | 单行横向滚动 `ListView`(scrollDirection: horizontal)+ 右缘渐隐 `ShaderMask` | 顶导航 44px 内首选,对齐原版 scrollable nav |
| 筛选 chips / 内容区标签过多 | `Wrap(spacing, runSpacing)` | 内容区专用;顶导航禁用(见 SKILL.md 收缩规范) |
| icon+文字 → icon-only | `LayoutBuilder` 阈值分支 + `Tooltip` | 768–1023px 只显示品牌色点/icon |
| 网格自适应列数 | `SliverGridDelegateWithMaxCrossAxisExtent` 或 LayoutBuilder 折算 | 本项目 RoomGrid 用后者(maxCardWidth=280) |
| 内容可能超出容器 | `FittedBox`(整块缩放)/ `Expanded`(弹性让步) | 视频/徽章类用 FittedBox;文本用省略 |
| 尺寸/插值动画过渡 | `AnimatedContainer`/`ImplicitlyAnimatedWidget` | 断点切换时平滑过渡,配 `AppMotion` |

## 3. SafeArea / 键盘 insets 所有权

- **SafeArea 由页面壳层统一消费**(AppShell/播放页壳),业务 Widget 不重复包 `SafeArea`;读取 `MediaQuery.paddingOf(context)` 做自定义布局补偿。
- **键盘**:`Scaffold.resizeToAvoidBottomInset`(默认 true)处理常规表单;弹幕输入等悬浮条自己读 `MediaQuery.viewInsetsOf(context).bottom`。二者不要叠加使用。
- 刘海/横条:注入的 `MediaQuery.padding` 属于平台差异,W11 测试卡负责验证导航内容不被遮挡。

## 4. 大字体(系统 textScale)兜底

安卓老年模式/iOS 辅助功能会把 `textScaleFactor` 推到 1.3+,是"iOS 正常 Android 崩"的第一根因:

- 所有可能涨高的行:`maxLines + TextOverflow.ellipsis` + `softWrap`;紧凑行用 `FittedBox(scaleDown)`。
- 关键表单/控制条布局按「最高一档」设计,不按 1.0 假设;行高用 tokens 的 `height` 而非固定容器高。
- 断言:W11 卡的 `textScaleSweep(1.0/1.15/1.3)` 全页面无 overflow。

## 5. 断点基线(本项目)

```text
AppBreakpoints: compact 640 / phone 768 / tablet 1024 / desktop 1366 / wide 1920
导航形态:≥1024 点+文字;768–1023 icon-only;<768 底部导航 + 顶部横向 strip
```

改动断点行为必须同步 W12 占位用例(`responsive_skip_test.dart`),转绿即验收。

## 6. 来源

- https://github.com/bladeofgod/flutter-ai-harness(.claude/skills/flutter-layouts)
- https://github.com/diegosouzapw/awesome-omni-skills(skills/flutter-expert)
- Flutter 官方:LayoutBuilder / MediaQuery / Sliver 文档
