# -*- coding: utf-8 -*-
"""开关/滑杆全局统一(用户口径 2026-09-20):CompactSwitch 全局组件 +
popover 金色全部对齐 accent + 全局滑杆紧凑规格 + 「弹」方块对齐紫色。"""
import io


def patch(path, pairs, must=True):
    s = io.open(path, encoding="utf-8").read()
    for old, new in pairs:
        n = s.count(old)
        if must:
            assert n == 1, (path, repr(old[:60]), "count=", n)
        elif n != 1:
            print("skip", path, repr(old[:40]), "count=", n)
            continue
        s = s.replace(old, new)
    io.open(path, "w", encoding="utf-8", newline="").write(s)
    print("ok", path)


# ── 1. 全局 CompactSwitch(自 _MiniSwitch 提升) ──
cs = '''import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 全局紧凑开关(用户口径 2026-09-20:开关滑杆等默认大小全局统一)。
///
/// 自绘迷你开关(对齐 web el-switch 密度:轨道 30×16、圆角 8、滑块 12),
/// 替代 Material 默认大尺寸 Switch。选中轨道品牌紫(tokens.accent);
/// 未选中透明底 + 描边。保留 value/onChanged/Semantics(toggled) 语义。
class CompactSwitch extends StatelessWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final track = context.tokens.accent;
    const offBorder = Color(0xff3a3a3a);
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 30,
          height: 16,
          decoration: BoxDecoration(
            color: value ? track : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: value ? track : offBorder),
          ),
          child: AnimatedAlign(
            duration: AppMotion.fast,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: 12,
              height: 12,
              margin: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: value ? Colors.white : tokens.textSecondary,
                shape: BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
'''
io.open("lib/src/shared/presentation/widgets/compact_switch.dart", "w", encoding="utf-8", newline="").write(cs)
print("ok compact_switch.dart")

# ── 2. popover:金色 → accent;Switch → CompactSwitch ──
patch("lib/src/features/play/widgets/player_controls.dart", [
    ("import '../../danmaku/domain/danmaku_settings.dart';",
     "import '../../danmaku/domain/danmaku_settings.dart';\n"
     "import '../../../shared/presentation/widgets/compact_switch.dart';"),
    ("""              trailing: Transform.scale(
              scale: AppControls.switchScale,
              child: Switch(
                value: widget.show,
                onChanged: (_) => widget.onToggleShow(),
                activeTrackColor: const Color(0xFFF3D04E),
              ),
            ),""",
     """              trailing: CompactSwitch(
                value: widget.show,
                onChanged: (_) => widget.onToggleShow(),
              ),"""),
    ("activeColor: const Color(0xFFF3D04E),", "activeColor: context.tokens.accent,", 3),
    ("                activeColor: const Color(0xFFF3D04E),", "                activeColor: context.tokens.accent,"),
    ("color: const Color(0xFFF3D04E),", "color: context.tokens.accent,"),
    ("color: Color(0xFFF3D04E),", "color: context.tokens.accent,", 2),
    # 「弹」方块激活色:amber → 品牌紫(用户口径 2026-09-20)
    ("""  /// 激活(弹幕开 / 菜单展开):描边与文字转 amber(SFVideo --amber)。
  final bool active;""",
     """  /// 激活(弹幕开 / 菜单展开):描边与文字转品牌紫 tokens.accent
  /// (用户口径 2026-09-20 控件强调一律品牌紫,覆盖 SFVideo 的 amber)。
  final bool active;"""),
    ("    final color = active ? context.tokens.brand : AppOnVideo.textMuted;",
     "    final color = active ? context.tokens.accent : AppOnVideo.textMuted;"),
    ("""              style: TextStyle(
                fontSize: 8,
                height: 1,
                fontWeight: FontWeight.w800,
                color: context.tokens.brand,
              ),""",
     """              style: TextStyle(
                fontSize: 8,
                height: 1,
                fontWeight: FontWeight.w800,
                color: context.tokens.accent,
              ),"""),
    ("""            child: Icon(
              Icons.settings_rounded,
              size: 9,
              color: active ? context.tokens.brand : AppOnVideo.textMuted,
            ),""",
     """            child: Icon(
              Icons.settings_rounded,
              size: 9,
              color: active ? context.tokens.accent : AppOnVideo.textMuted,
            ),"""),
])

# State 方法内 context 可用性:analysis 会兜底;区域下拉勾
patch("lib/src/features/play/widgets/player_controls.dart", [
    ("                          Icon(\n                            Icons.check_rounded,\n                            size: 16,\n                            color: context.tokens.brand,\n                          )",
     "                          Icon(\n                            Icons.check_rounded,\n                            size: 16,\n                            color: context.tokens.accent,\n                          )"),
])

# ── 3. _MiniSwitch 换全局 CompactSwitch ──
patch("lib/src/features/play/widgets/play_side_panel.dart", [
    ("import '../../../shared/presentation/design_tokens.dart';",
     "import '../../../shared/presentation/design_tokens.dart';\n"
     "import '../../../shared/presentation/widgets/compact_switch.dart';"),
    ("trailing: _MiniSwitch(", "trailing: CompactSwitch(", 2),
    ("                leading: _MiniSwitch(", "                leading: CompactSwitch(", 1),
])
# 删私有 _MiniSwitch 类(括号平衡)
s = io.open("lib/src/features/play/widgets/play_side_panel.dart", encoding="utf-8").read()
start = s.index("/// 自绘迷你开关(对齐 web el-switch 密度")
depth = 0
i = s.index("class _MiniSwitch", start)
while True:
    ch = s[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            break
    i += 1
end = i + 1
s = s[:start] + s[end:].lstrip("\n")
io.open("lib/src/features/play/widgets/play_side_panel.dart", "w", encoding="utf-8", newline="").write(s)
print("ok _MiniSwitch removed")

# ── 4. 设置页/弹幕面板 Switch 换 CompactSwitch ──
patch("lib/src/features/follow/views/settings_view.dart", [
    ("                    trailing: Switch(\n                      value: settings.danmakuEnabled,\n                      onChanged: (value) => ref\n                          .read(settingsProvider.notifier)\n                          .setDanmakuEnabled(value),\n                    ),",
     "                    trailing: CompactSwitch(\n                      value: settings.danmakuEnabled,\n                      onChanged: (value) => ref\n                          .read(settingsProvider.notifier)\n                          .setDanmakuEnabled(value),\n                    ),"),
])
s = io.open("lib/src/features/follow/views/settings_view.dart", encoding="utf-8").read()
if "compact_switch.dart" not in s:
    anchor = "import '../../../shared/presentation/design_tokens.dart';"
    assert s.count(anchor) == 1
    s = s.replace(anchor, anchor + "\nimport '../../../shared/presentation/widgets/compact_switch.dart';")
    io.open("lib/src/features/follow/views/settings_view.dart", "w", encoding="utf-8", newline="").write(s)
print("ok settings_view switch")

patch("lib/src/features/danmaku/widgets/danmaku_settings_panel.dart", [
    ("""                child: Switch(
                  value: danmakuEnabled,
                  onChanged: settingsController.setDanmakuEnabled,
                ),""",
     """                child: CompactSwitch(
                  value: danmakuEnabled,
                  onChanged: settingsController.setDanmakuEnabled,
                ),"""),
])
s = io.open("lib/src/features/danmaku/widgets/danmaku_settings_panel.dart", encoding="utf-8").read()
if "compact_switch.dart" not in s:
    # 找一个 shared presentation import 锚
    anchor = "import '../../../shared/presentation/design_tokens.dart';"
    if s.count(anchor) == 1:
        s = s.replace(anchor, anchor + "\nimport '../../../shared/presentation/widgets/compact_switch.dart';")
    else:
        anchor2 = "import 'package:flutter/material.dart';"
        assert s.count(anchor2) == 1
        s = s.replace(anchor2, anchor2 + "\n\nimport '../../../shared/presentation/widgets/compact_switch.dart';")
    io.open("lib/src/features/danmaku/widgets/danmaku_settings_panel.dart", "w", encoding="utf-8", newline="").write(s)
print("ok danmaku panel switch")

# ── 5. 全局滑杆紧凑规格(app_theme) ──
patch("lib/src/app/app_theme.dart", [
    ("""      progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.accent),""",
     """      progressIndicatorTheme: ProgressIndicatorThemeData(color: tokens.accent),
      // 全局滑杆紧凑规格(用户口径 2026-09-20 开关滑杆等默认大小全局统一;
      // 对齐 SFVideo el-slider 紧凑视觉)。视频控制条主滑杆有局部主题覆盖。
      sliderTheme: SliderThemeData(
        trackHeight: AppControls.sliderTrackHeight,
        thumbShape: RoundSliderThumbShape(
          enabledThumbRadius: AppControls.sliderThumbRadius,
        ),
        overlayShape: RoundSliderOverlayShape(
          overlayRadius: AppControls.sliderThumbRadius + 3,
        ),
      ),"""),
])
s = io.open("lib/src/app/app_theme.dart", encoding="utf-8").read()
if "AppControls" not in s.split("abstract final class")[0]:
    # import design_tokens 已有(AppControls 在其中)——确认
    pass
print("ALL DONE")
