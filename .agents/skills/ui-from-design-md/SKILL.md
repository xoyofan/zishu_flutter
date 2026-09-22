---
name: ui-from-design-md
description: 按 zishu_flutter 的视觉真源 DESIGN.md 新建或改造页面。当用户要求在 zishu_flutter 里"做/改某个页面或组件"、"调样式/配色/字号/间距/圆角/阴影"、"加 hover/选中/禁用/focus 态"、"做响应式断点收缩"、"新建设置页/面板/弹窗",或需要"视觉评审/对齐 DESIGN.md/检查是否用了 token"时使用。不适用于解析核心(live_parser)、播放器内核、弹幕协议、网络层等非视觉改动。
---

# 按 DESIGN.md 做 zishu_flutter 的 UI

本 skill 的执行目标是：**让改动后的界面和 `DESIGN.md` 一致，且不引入任何裸值。**

## 开工前必读(按序,不要跳)

1. `DESIGN.md`(项目根) — 视觉唯一真源。至少读完 §2 色板、§3 字号、§4 状态矩阵、§6 elevation、§7 Don'ts。
2. `AGENTS.md` — 目录与依赖边界(新代码只在 `lib/src/`，禁止 import `lib/legacy/`)。
3. 本页对应的布局证据：`docs/ui-parity/spec-layout.md` 的对应页面章节(房间卡/首页/关注/播放/断点矩阵)。
4. 现有 token 取证：`lib/src/shared/presentation/design_tokens.dart`、`zishu_tokens.dart`、`platform_brands.dart`、`app_theme.dart`。
5. 相邻的同类实现(同 feature 下已有 Widget) — 优先复用而不是新写。

## 工作流

1. **定 token**：先列出这次需要哪些语义值(底色、文字、边框、圆角、间距、阴影、状态)。
   每个值都要落到一个已有 token 上。
2. **补 token(仅当确实缺)**：在 `design_tokens.dart` 或 `zishu_tokens.dart` 加定义，
   并在 `test/shared/design_tokens_test.dart` 加契约断言。**先补 token，再引用**。
   不允许"先在 Widget 里写死，回头再抽"。
3. **实现 Widget**：
   - 颜色一律 `context.tokens.*`；文字样式 `context.textTitle/textBody/textSecondary/textCaption`。
   - 压在深色视频/封面上的控件用 `AppOnVideo` / `coverScrim` 语义，不跟随主题翻转。
   - 悬停/过渡用 `AppMotion.fast` + `AppMotion.curve`；展开收起用 `AppMotion.normal`。
   - 阴影只用 `AppElevation` 四档；不要新写 `BoxShadow`。
   - 响应式用 `LayoutBuilder` + `AppBreakpoints`；复合条件(横竖屏/触屏/hover)照 §8 做。
   - 缩小视觉尺寸时必须靠 padding 保住 36–48px 热区。
4. **收口验证**(必须真跑，贴原始输出)：
   ```bash
   flutter analyze                                  # 必须 0 error
   dart run tool/check_design_tokens.dart           # 裸值守卫必须 OK
   flutter test                                     # 相关测试 + golden
   flutter build windows --debug -t lib/main.dart   # 主链路改动时
   ```
   golden 若有差异，先用 `read` 打开 `test/ui/failures/*.png` **实际看一眼**，
   确认差异就是本次有意改动再 `--update-goldens`；看不懂的差异不要更新，报出来。

## 禁止

- Widget 内裸色值 / 裸数字 / 裸 `BoxShadow`。
- 把深色基线色写死当文字色(浅色主题下会白底白字)。
- 引入新依赖来解决响应式布局(自绘 + `LayoutBuilder` 足够)。
- 用 `Map<String, dynamic>` 直接驱动 UI(必须经过 `shared/domain` 的稳定 model)。
- 改动 `DESIGN.md` 的色板 / 字号 / elevation 数值而不更新契约测试。

## 需要外部品牌参考时

`.agents/skills/awesome-design-md/` 下有 74 套知名产品的 DESIGN.md(含 SKILL.md 索引)。
只在"本页 SFVideoLive 没有对应基线"时使用，且：

- **一次只选一套**，按气质挑(深色产品工具类优先 `linear.app` / `raycast` / `supabase`)。
- **只取结构**：层级关系、状态矩阵、密度节奏、响应式收缩策略。
- **不取**品牌色、品牌字体、logo、商标字形、专有插图。
- 取用的结论要写回项目根 `DESIGN.md` 的对应章节，并在提交说明里标注来源。

## 输出要求

每次 UI 改动结束输出：

1. 改动文件清单；
2. `flutter analyze` / `dart run tool/check_design_tokens.dart` / `flutter test` 的**原始结果行**；
3. 新增或复用的 token 对照表(新增了哪些、复用了哪些)；
4. 与 `DESIGN.md` 的有意偏离及原因(没有就写"无")；
5. golden 变化清单及每张图的差异原因(没有就写"无")。
