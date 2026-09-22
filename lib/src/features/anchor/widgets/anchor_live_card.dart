import 'dart:math';

import 'package:flutter/material.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import '../application/anchor_provider.dart';
import 'badge_chips.dart';
import 'network_cover.dart';

/// 当前直播状态卡:在播为封面预览 + 标题/分类/在线 + 进入直播间大按钮;
/// 离线为灰态提示。
class AnchorLiveCard extends StatelessWidget {
  const AnchorLiveCard({
    super.key,
    required this.profile,
    required this.onEnterRoom,
  });

  final AnchorProfile profile;
  final VoidCallback onEnterRoom;

  /// SFVideoLive cover-wrap 的 max-height 260px。
  static const double _maxCoverHeight = 260;

  /// 大按钮高度,与顶部导航一致。
  static const double _buttonHeight = 44;

  @override
  Widget build(BuildContext context) {
    final room = profile.liveRoom;
    if (!profile.isLive || room == null) {
      return const _OfflineCard();
    }
    final tokens = context.tokens;
    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final height = min(
                constraints.maxWidth * 9 / 16,
                _maxCoverHeight,
              );
              return SizedBox(
                height: height,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetworkCover(
                      url: room.cover,
                      fallbackLabel: displayCategoryName(
                        room.site,
                        room.category,
                        room.cid,
                      ),
                    ),
                    Positioned(
                      left: AppSpacing.md,
                      top: AppSpacing.md,
                      child: LiveStateChip(isLive: true),
                    ),
                    Positioned(
                      right: AppSpacing.md,
                      bottom: AppSpacing.md,
                      child: OnlineTag(online: room.online),
                    ),
                  ],
                ),
              );
            },
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TranslatedText(
                        room.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textTitle.copyWith(fontSize: AppFontSize.subtitle),
                      ),
                    ),
                    if (room.category.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      CategoryChip(label: room.category, site: room.site),
                    ],
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Text('${room.anchorName} 正在直播', style: context.textSecondary),
                const SizedBox(height: AppSpacing.lg),
                SizedBox(
                  width: double.infinity,
                  height: _buttonHeight,
                  child: Material(
                    color: tokens.accent,
                    borderRadius: AppRadius.allMd,
                    child: InkWell(
                      borderRadius: AppRadius.allMd,
                      onTap: onEnterRoom,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.play_arrow_rounded,
                            size: 20,
                            color: tokens.surfaceSoft,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            '进入直播间',
                            style: context.textTitle.copyWith(
                              fontSize: AppFontSize.subtitle,
                              fontWeight: FontWeight.w700,
                              color: tokens.surfaceSoft,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 离线灰态:图标 + 提示文案,不提供进入入口。
class _OfflineCard extends StatelessWidget {
  const _OfflineCard();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl * 2),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        children: [
          Icon(
            Icons.videocam_off_rounded,
            size: 36,
            color: tokens.textSecondary,
          ),
          const SizedBox(height: AppSpacing.md),
          Text('主播当前未直播', style: context.textSecondary),
          const SizedBox(height: AppSpacing.xs),
          Text('可以先看看下方相关直播', style: context.textCaption),
        ],
      ),
    );
  }
}
