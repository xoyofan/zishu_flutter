import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 主 CTA「流光呼吸描边 + pressed 缩放 0.97」包装。
///
/// - hover 时沿子控件边界**内侧**描一圈 accent 渐变细描边,以
///   [AmbientMotion.pulse] 做呼吸(清单 2.2);
/// - pressed 时整体缩放 0.97(清单 2.5),与现有 [AppStateLayer.pressedOf]
///   叠加,不重复发明按下色;
/// - `reduce_motion`([AmbientMotion.of] 的静态档)时呼吸停止,只留静态描边,
///   按压缩放以零时长切换。
///
/// 描边是**描线**而不是底色叠加:用 [CustomPaint] 画圆角矩形描边,不遮子控件
/// 内容、不占布局、不撑开外部尺寸。外发光只经 [AmbientGlow.ctaSheen] helper 派生。
class AmbientCtaHover extends StatefulWidget {
  const AmbientCtaHover({
    super.key,
    required this.child,
    required this.borderRadius,
  });

  final Widget child;

  /// 描边跟随子控件自身圆角:**必须与子控件一致**,否则圆角处会露出直角或
  /// 弧线不贴合。M3 `IconButton` 默认 `StadiumBorder` → 传 [AppRadius.allPill]。
  final BorderRadius borderRadius;

  @override
  State<AmbientCtaHover> createState() => _AmbientCtaHoverState();
}

class _AmbientCtaHoverState extends State<AmbientCtaHover>
    with SingleTickerProviderStateMixin {
  /// 描边宽度(清单 2.2「描边」的 2px 细线;不随主题变化)。
  static const double _strokeWidth = 2;

  /// pressed 缩放比(清单 2.5 的精确值)。
  static const double _pressedScale = 0.97;

  bool _hover = false;
  bool _pressed = false;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: AmbientMotion.pulse,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _pulse.duration = AmbientMotion.of(context).pulse;
    _syncPulse();
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  /// 呼吸只在 hover 且非 `reduce_motion` 时运行:空闲时不留常驻 Ticker,
  /// 避免桌面端持续请求帧。
  void _syncPulse() {
    final animate = _hover && !AmbientMotion.of(context).reduced;
    if (animate) {
      if (!_pulse.isAnimating) _pulse.repeat(reverse: true);
    } else if (_pulse.isAnimating) {
      _pulse.stop();
      _pulse.value = 0;
    }
  }

  void _setHover(bool value) {
    if (_hover == value) return;
    setState(() => _hover = value);
    _syncPulse();
  }

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final reduced = AmbientMotion.of(context).reduced;
    final duration = reduced ? Duration.zero : AppMotion.fast;

    Widget? overlay;
    if (_hover) {
      final ring = _SheenRing(
        accent: tokens.accent,
        borderRadius: widget.borderRadius,
        strokeWidth: _strokeWidth,
      );
      overlay = reduced
          ? ring
          : AnimatedBuilder(
              animation: _pulse,
              builder: (context, child) => Opacity(
                opacity: _breatheOpacity(
                  AppMotion.curve.transform(_pulse.value),
                ),
                child: child,
              ),
              child: ring,
            );
    }

    return MouseRegion(
      onEnter: (_) => _setHover(true),
      onExit: (_) => _setHover(false),
      child: Listener(
        onPointerDown: (_) => _setPressed(true),
        onPointerUp: (_) => _setPressed(false),
        onPointerCancel: (_) => _setPressed(false),
        child: AnimatedScale(
          duration: duration,
          curve: AppMotion.curve,
          scale: _pressed ? _pressedScale : 1.0,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              widget.child,
              if (overlay != null)
                Positioned.fill(child: IgnorePointer(child: overlay)),
            ],
          ),
        ),
      ),
    );
  }

  /// 呼吸曲线:0.5 → 1.0 → 0.5(不熄到全透明,描边始终可见)。
  static double _breatheOpacity(double t) => 0.5 + (t * 0.5);
}

/// 流光描边本体:一圈渐变描线 + [AmbientGlow.ctaSheen] 外发光。
///
/// 两者画在同一个 [CustomPaint] 里:外发光必须**只落在子控件边界之外**
/// (`BoxShadow` 的模糊会向内溢,若不过滤就成了一块 accent 底色,既脏也不是
/// 「描边」),所以先用路径差集剪掉轮廓内部再画模糊投影。
class _SheenRing extends StatelessWidget {
  const _SheenRing({
    required this.accent,
    required this.borderRadius,
    required this.strokeWidth,
  });

  final Color accent;
  final BorderRadius borderRadius;
  final double strokeWidth;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _SheenRingPainter(
        accent: accent,
        borderRadius: borderRadius,
        strokeWidth: strokeWidth,
      ),
    );
  }
}

/// 渐变描线:对角线上「透明 → accent 24% → 透明」,模拟缓慢流动的流光;
/// 外发光同样经 [AmbientGlow.ctaSheen] 派生,且只向边界外扩散。
class _SheenRingPainter extends CustomPainter {
  const _SheenRingPainter({
    required this.accent,
    required this.borderRadius,
    required this.strokeWidth,
  });

  final Color accent;
  final BorderRadius borderRadius;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final outline = borderRadius.toRRect(rect);

    // 外发光:排除轮廓内部(模糊会向内溢色),只留向外扩散的投影。
    // 画布 API 的 `clipRRect` 没有 `ClipOp.difference`,用路径差集代替。
    final outside = Path.combine(
      PathOperation.difference,
      Path()..addRect(rect.inflate(AmbientGlow.ctaSheenBlur * 3)),
      Path()..addRRect(outline),
    );
    canvas.save();
    canvas.clipPath(outside);
    for (final shadow in AmbientGlow.ctaSheen(accent)) {
      canvas.drawRRect(outline, shadow.toPaint());
    }
    canvas.restore();

    // 描线居中于内缩 strokeWidth/2 的圆角矩形上 → 完全落在子控件边界内侧。
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          accent.withValues(alpha: 0),
          accent.withValues(alpha: AmbientGlow.ctaSheenAlpha),
          accent.withValues(alpha: 0),
        ],
      ).createShader(rect);
    canvas.drawRRect(outline.deflate(strokeWidth / 2), paint);
  }

  @override
  bool shouldRepaint(_SheenRingPainter oldDelegate) =>
      oldDelegate.accent != accent ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.strokeWidth != strokeWidth;
}
