import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// Aurora 氛围背景(批1,DESIGN.md §2.4,真源 `preview/glass-preview.html` Demo F)。
///
/// wash、三个径向光团和 grain 由**一个 CustomPainter 一次画完**。平台切换时
/// painter 只重画一张背景缓存;没有 AnimatedContainer、持续动画或
/// BackdropFilter,不会带着房间网格逐帧合成。卡片只消费这张背景上方的普通
/// 半透明色。
class AmbientAuroraBackground extends StatelessWidget {
  const AmbientAuroraBackground({super.key, required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).brightness != Brightness.dark) {
      return const SizedBox.shrink();
    }
    final palette = AmbientAuroraPalette.forSite(
      site,
      accent: context.tokens.accent,
    );
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          size: Size.infinite,
          painter: _AuroraPainter(palette),
        ),
      ),
    );
  }
}

class _AuroraPainter extends CustomPainter {
  const _AuroraPainter(this.palette);

  final AmbientAuroraPalette palette;

  static final ui.Picture _grainTile = _makeGrainTile();
  static const double _grainTileSize = 128;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.primary.withValues(alpha: AmbientAurora.washAlpha),
    );
    _drawBlob(
      canvas,
      center: Offset(0.26 * size.width, 0.21 * size.height),
      diameter: 0.62 * size.width,
      color: palette.primary,
      alpha: AmbientAurora.primaryBlobAlpha,
    );
    _drawBlob(
      canvas,
      center: Offset(0.89 * size.width, 0.07 * size.height),
      diameter: 0.29 * size.width,
      color: palette.accent,
      alpha: AmbientAurora.accentBlobAlpha,
    );
    _drawBlob(
      canvas,
      center: Offset(0.69 * size.width, size.height),
      diameter: 0.31 * size.width,
      color: palette.balance,
      alpha: AmbientAurora.balanceBlobAlpha,
    );
    _drawGrain(canvas, size);
  }

  void _drawBlob(
    Canvas canvas, {
    required Offset center,
    required double diameter,
    required Color color,
    required double alpha,
  }) {
    final rect = Rect.fromCircle(center: center, radius: diameter / 2);
    final shader = RadialGradient(
      colors: [color.withValues(alpha: alpha), color.withValues(alpha: 0)],
    ).createShader(rect);
    canvas.drawCircle(center, diameter / 2, Paint()..shader = shader);
  }

  void _drawGrain(Canvas canvas, Size size) {
    for (var y = 0.0; y < size.height; y += _grainTileSize) {
      for (var x = 0.0; x < size.width; x += _grainTileSize) {
        canvas.save();
        canvas.translate(x, y);
        canvas.drawPicture(_grainTile);
        canvas.restore();
      }
    }
  }

  static ui.Picture _makeGrainTile() {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final rng = math.Random(20260922);
    for (var i = 0; i < 620; i++) {
      final paint = Paint()
        ..color = Color.fromRGBO(
          255,
          255,
          255,
          AmbientAurora.grainAlpha * (0.25 + rng.nextDouble() * 0.55),
        );
      canvas.drawRect(
        Rect.fromLTWH(
          rng.nextDouble() * _grainTileSize,
          rng.nextDouble() * _grainTileSize,
          1,
          1,
        ),
        paint,
      );
    }
    for (var i = 0; i < 620; i++) {
      final paint = Paint()
        ..color = Color.fromRGBO(
          0,
          0,
          0,
          AmbientAurora.grainAlpha * (0.25 + rng.nextDouble() * 0.55),
        );
      canvas.drawRect(
        Rect.fromLTWH(
          rng.nextDouble() * _grainTileSize,
          rng.nextDouble() * _grainTileSize,
          1,
          1,
        ),
        paint,
      );
    }
    return recorder.endRecording();
  }

  @override
  bool shouldRepaint(covariant _AuroraPainter oldDelegate) =>
      oldDelegate.palette.primary != palette.primary ||
      oldDelegate.palette.accent != palette.accent ||
      oldDelegate.palette.balance != palette.balance;
}
