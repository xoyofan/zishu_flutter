import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/anchor_provider.dart';
import 'badge_chips.dart';
import 'follow_button.dart';

/// 主播头部卡:圆形头像 + 昵称 + 平台/状态徽标 + 样例统计 + 关注按钮。
class AnchorHero extends StatelessWidget {
  const AnchorHero({super.key, required this.profile});

  final AnchorProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: context.tokens.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AnchorAvatar(url: profile.avatarUrl, label: profile.nickname),
          const SizedBox(width: AppSpacing.lg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.xs,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      profile.nickname,
                      style: context.textTitle.copyWith(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    PlatformBadgeChip(site: profile.site),
                    LiveStateChip(isLive: profile.isLive),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    _Stat(label: '粉丝', value: profile.fansLabel),
                    const SizedBox(width: AppSpacing.xl),
                    _Stat(label: '视频', value: profile.videosLabel),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                const FollowButton(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 样例统计项:数值加粗 + 灰色标签。
class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: context.textTitle.copyWith(fontSize: 15),
        ),
        const SizedBox(height: 2),
        Text(label, style: context.textCaption),
      ],
    );
  }
}
