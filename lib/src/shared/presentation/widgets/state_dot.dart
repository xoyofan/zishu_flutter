import 'package:flutter/material.dart';

import '../zishu_tokens.dart';

/// 直播状态圆点：live 红色(liveBadge)并带呼吸动画，
/// offline 灰色(border)静止展示。
class StateDot extends StatefulWidget {
  const StateDot({super.key, this.live = false});

  /// 是否处于直播中。
  final bool live;

  @override
  State<StateDot> createState() => _StateDotState();
}

class _StateDotState extends State<StateDot>
    with SingleTickerProviderStateMixin {
  /// 呼吸动画周期：慢速透明度往复循环。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );

  late final Animation<double> _opacity =
      Tween<double>(begin: 1.0, end: 0.35).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
  );

  @override
  void initState() {
    super.initState();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant StateDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.live != widget.live) _syncAnimation();
  }

  /// live 时循环呼吸，offline 时停止并复位。
  void _syncAnimation() {
    if (widget.live) {
      _controller.repeat(reverse: true);
    } else {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Widget dot = Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        color: widget.live ? tokens.liveBadge : tokens.border,
        shape: BoxShape.circle,
      ),
    );
    if (!widget.live) return dot;
    return AnimatedBuilder(
      animation: _opacity,
      child: dot,
      builder: (context, child) =>
          Opacity(opacity: _opacity.value, child: child),
    );
  }
}
