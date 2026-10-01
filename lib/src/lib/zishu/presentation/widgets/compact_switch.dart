import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 全局紧凑开关(用户口径 2026-09-20:开关滑杆等默认大小全局统一)。
///
/// 自绘迷你开关(对齐 web el-switch 密度:轨道 30×16、圆角 8、滑块 12),
/// 替代 Material 默认大尺寸 Switch。选中轨道品牌紫(tokens.accent);
/// 未选中透明底 + 描边。保留 value/onChanged/Semantics(toggled) 语义。
///
/// **状态补齐(2026-09-21 交互反馈轨 A)**——此前它只有 default/选中两态:
/// - focus:键盘聚焦时挂 `AppFocus.ring(accent)`(2px 实环 + 2px 间隙,**外扩、
///   不占布局**;仅 traditional 高亮模式显示,鼠标点击不出环);同时支持
///   回车 / 空格切换(`FocusableActionDetector` + `ActivateIntent`);
/// - hover:关态轨道给一档 `surfaceRaised`(DESIGN.md §4.2 抬升档);
/// - pressed:由 `GestureDetector` 的即时切换表达,不做缩放 / 位移
///   (2026-09-21 裁决,DESIGN.md §7);
/// - 指针:恒为 `SystemMouseCursors.click`(`GestureDetector` 不会自动给);
/// - 过渡:三处动画补 `AppMotion.curve`(此前是 `AnimatedContainer` 默认的
///   `Curves.linear`,DESIGN.md §5.1 / 动效纪律明令禁止 linear)。
///
/// 零新增 token:焦点环 / 抬升底色 / 曲线全部来自既有 token。
class CompactSwitch extends StatefulWidget {
  const CompactSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<CompactSwitch> createState() => _CompactSwitchState();
}

class _CompactSwitchState extends State<CompactSwitch> {
  /// 键盘焦点高亮(仅在 traditional 焦点模式下为 true,对齐 CSS `:focus-visible`)。
  bool _showFocusRing = false;

  /// 鼠标 hover(关态轨道抬一档用)。
  bool _hovered = false;

  void _toggle() => widget.onChanged(!widget.value);

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final track = tokens.accent;
    final offBorder = tokens.border;
    return Semantics(
      toggled: widget.value,
      child: FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        onShowFocusHighlight: (value) => setState(() => _showFocusRing = value),
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (intent) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          onTap: _toggle,
          child: AnimatedContainer(
            duration: AppMotion.fast,
            curve: AppMotion.curve,
            width: 30,
            height: 16,
            decoration: BoxDecoration(
              color: widget.value
                  ? track
                  : (_hovered ? tokens.surfaceRaised : Colors.transparent),
              borderRadius: AppRadius.allMd,
              border: Border.all(color: widget.value ? track : offBorder),
              // 焦点环靠 boxShadow 外扩:不改尺寸、不加 padding。
              boxShadow: _showFocusRing ? AppFocus.ring(track) : null,
            ),
            child: AnimatedAlign(
              duration: AppMotion.fast,
              curve: AppMotion.curve,
              alignment: widget.value
                  ? Alignment.centerRight
                  : Alignment.centerLeft,
              child: AnimatedContainer(
                duration: AppMotion.fast,
                curve: AppMotion.curve,
                width: 12,
                height: 12,
                margin: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: widget.value
                      ? AppOnBright.white
                      : tokens.textSecondary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
