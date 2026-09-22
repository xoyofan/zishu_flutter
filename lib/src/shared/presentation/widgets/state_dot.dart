import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 直播状态圆点：live 绿点 + 外圈扩散涟漪，offline 灰点静止展示。
///
/// 涟漪周期取 [AmbientMotion.pulse]（清单 2.3 的「扩散涟漪」），时长与降级
/// 一律经 [AmbientMotion.of] 获取，widget 内不写裸时长。
///
/// `reduce_motion` 时只渲染静态圆点、不建动画（清单 2.3 的降级要求）。
///
/// **落点现状（2026-09-22 裁决【2】）**：本组件当前无可见消费点（dead code，
/// 全库仅 `widgets.dart` 导出），裁决要求严格按清单落点只改本文件、不擅自把它
/// 接线到任何卡片；因此涟漪效果暂不可见，接线留给后续任务。
class StateDot extends StatefulWidget {
  const StateDot({super.key, this.live = false});

  /// 是否处于直播中。
  final bool live;

  @override
  State<StateDot> createState() => _StateDotState();
}

class _StateDotState extends State<StateDot>
    with SingleTickerProviderStateMixin {
  /// 圆点直径（live/offline 同尺寸，仅颜色与涟漪不同）。
  static const double _dotSize = 6;

  /// 涟漪相位偏移：两圈错开半个周期，形成连续外扩。
  static const double _ringPhase = 0.5;

  /// 涟漪最大缩放（1.0 → 2.5 倍）。
  static const double _ringMaxScale = 2.5;

  /// 涟漪起笔不透明度（随扩散线性衰减到 0）。
  static const double _ringOpacity = 0.6;

  /// 涟漪描边宽度。
  static const double _ringStrokeWidth = 1;

  /// 涟漪描边不透明度（圆环自身再乘 [Opacity] 的扩散淡出）。
  static const double _ringStrokeAlpha = 0.7;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AmbientMotion.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = AmbientMotion.of(context).pulse;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant StateDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.live != widget.live) _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// live 且非 `reduce_motion` 时循环扩散；否则停表复位（不留常驻 Ticker）。
  void _syncAnimation() {
    final animate = widget.live && !AmbientMotion.of(context).reduced;
    if (animate) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final color = widget.live ? tokens.liveBadge : tokens.border;
    final dot = Container(
      width: _dotSize,
      height: _dotSize,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    );

    // 静态红/绿点保留：非 live，或 reduce_motion 静态档。
    if (!widget.live || AmbientMotion.of(context).reduced) return dot;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Stack(
          alignment: Alignment.center,
          children: [
            _RippleRing(controller: _controller, color: color),
            _RippleRing(
              controller: _controller,
              color: color,
              phase: _ringPhase,
            ),
            child!,
          ],
        );
      },
      child: dot,
    );
  }
}

/// 单圈扩散涟漪：一个跟着 [controller] 相位外扩并淡出的细描边圆环。
class _RippleRing extends StatelessWidget {
  const _RippleRing({
    required this.controller,
    required this.color,
    this.phase = 0,
  });

  final AnimationController controller;
  final Color color;

  /// 相位偏移（0–1），用于多圈错开。
  final double phase;

  @override
  Widget build(BuildContext context) {
    // 扩散进度用既有 [AppMotion.curve](不新造曲线):先快后慢地外扩、淡出。
    final t = (controller.value + phase) % 1.0;
    final eased = AppMotion.curve.transform(t);
    final scale = 1.0 + eased * (_StateDotState._ringMaxScale - 1);
    final opacity = (1.0 - eased) * _StateDotState._ringOpacity;
    return Opacity(
      opacity: opacity,
      child: Transform.scale(
        scale: scale,
        child: Container(
          width: _StateDotState._dotSize,
          height: _StateDotState._dotSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: color.withValues(alpha: _StateDotState._ringStrokeAlpha),
              width: _StateDotState._ringStrokeWidth,
            ),
          ),
        ),
      ),
    );
  }
}
