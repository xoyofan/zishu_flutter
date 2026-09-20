part of '../app_shell.dart';

/// hover 浮层定位:水平以触发点为中心,并夹到视口内;
/// 顶部留 [_kBridgeHeight] 透明桥接区(SFVideoLive `.nav-*-flyout::before`),
/// 鼠标从触发区移入浮层时不经过"非 hover 空白"。
class _HoverOverlay extends StatelessWidget {
  const _HoverOverlay({
    required this.centerX,
    required this.width,
    required this.child,
  });

  static const double _kBridgeHeight = 10;

  final double centerX;
  final double width;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final w = width.clamp(120.0, screenWidth - 16).toDouble();
    final left = (centerX - w / 2).clamp(8.0, screenWidth - w - 8).toDouble();
    return Positioned(
      top: AppSpacing.topNavHeight - _kBridgeHeight,
      left: left,
      width: w,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: _kBridgeHeight),
          child,
        ],
      ),
    );
  }
}
