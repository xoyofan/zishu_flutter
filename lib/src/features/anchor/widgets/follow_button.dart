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
        color: followed ? tokens.surfaceRaised : tokens.brand,
        borderRadius: AppRadius.allSm,
        border: followed ? Border.all(color: tokens.border) : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.allSm,
          onTap: () => setState(() => _followed = !_followed),
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
                  fontSize: 26,
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
