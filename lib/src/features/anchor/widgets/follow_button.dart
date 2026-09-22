import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 关注按钮:本页局部状态切换(已关注/未关注),不落全局存储。
class FollowButton extends StatefulWidget {
  const FollowButton({super.key});

  @override
  State<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends State<FollowButton> {
  bool _followed = false;

  /// 键盘焦点可见环开关。
  ///
  /// Flutter 没有 CSS 的 `:focus-visible`,等效物是
  /// [FocusHighlightMode.traditional]:Tab 键导航时为真,鼠标/触摸点击时为假,
  /// 因此只有键盘访问才出环。
  bool _focusRing = false;

  void _handleFocusChange(bool focused) {
    final keyboard =
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    final showRing = focused && keyboard;
    if (showRing != _focusRing) {
      setState(() => _focusRing = showRing);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final followed = _followed;
    return AnimatedContainer(
      // 测试锚点:主播页关注按钮。
      key: const Key('anchor-follow-btn'),
      duration: AppMotion.normal,
      curve: AppMotion.curve,
      decoration: BoxDecoration(
        color: followed ? tokens.surfaceRaised : tokens.accent,
        borderRadius: AppRadius.allSm,
        border: followed ? Border.all(color: tokens.border) : null,
        // focus: AppFocus.ring——2px 实环 + 2px 间隙,外扩不占布局,
        // 不撑开盒子、不位移(DESIGN.md §4.2 / §7)。
        boxShadow: _focusRing ? AppFocus.ring(tokens.accent) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.allSm,
          onTap: () => setState(() => _followed = !_followed),
          onFocusChange: _handleFocusChange,
          // accent 实底按钮:状态层取反白 on-accent(accent 低 alpha 压在同色
          // 底上不可见,等于没有反馈)。焦点只用外环,不叠 M3 内层 tint。
          hoverColor: AppOnBright.white.withValues(alpha: 0.12),
          splashColor: AppStateLayer.splashOf(AppOnBright.white),
          highlightColor: AppStateLayer.pressedOf(AppOnBright.white),
          focusColor: AppStateLayer.focusOf(tokens.accent),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  followed ? Icons.check_rounded : Icons.add_rounded,
                  size: 16,
                  color: followed ? tokens.textSecondary : tokens.surfaceSoft,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  followed ? '已关注' : '关注',
                  style: context.textBody.copyWith(
                    color: followed ? tokens.textSecondary : tokens.surfaceSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 圆形网络头像:加载失败回退到首字占位。
class AnchorAvatar extends StatelessWidget {
  const AnchorAvatar({
    super.key,
    required this.url,
    required this.label,
    this.size = 80,
  });

  final String url;
  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: ColoredBox(
          color: tokens.surfaceRaised,
          child: CachedNetworkImage(
            imageUrl: url,
            width: size,
            height: size,
            fit: BoxFit.cover,
            fadeInDuration: AppMotion.normal,
            placeholder: (_, _) => const SizedBox.expand(),
            errorWidget: (_, _, _) => Center(
              child: Text(
                label.isEmpty ? '?' : label.substring(0, 1),
                style: context.textTitle.copyWith(
                  fontSize: AppFontSize.display,
                  color: tokens.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
