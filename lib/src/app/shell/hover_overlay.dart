part of '../app_shell.dart';

/// 壳层交互态的**按下**叠色统一出口(2026-09-21 交互反馈轨 A)。
///
/// accent 12%= `AppDirectoryDrawer.activeChipAlpha` 同量级(既有 chip 选中底),
/// 供 InkWell 的 `splashColor` / `highlightColor`(pressed)使用——
/// 零新增 token、零裸值。
///
/// 键盘焦点另走 `focusColor: context.tokens.surfaceRaised`(DESIGN.md §4.2 抬升档);
/// hover 底色**按组件语义取**(导航品牌块压暗到 `surfaceSoft`、卡片/浮层抬到
/// `surfaceRaised`),见 DESIGN.md §4.2/§11.2,不在此处统一。
Color _pressTint(BuildContext context) =>
    context.tokens.accent.withValues(alpha: AppDirectoryDrawer.activeChipAlpha);

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
