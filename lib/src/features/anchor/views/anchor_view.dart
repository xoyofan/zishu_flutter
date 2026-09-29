import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/playback_log.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/anchor_provider.dart';
import '../widgets/anchor_hero.dart';
import '../widgets/anchor_live_card.dart';
import '../widgets/related_rooms.dart';

/// 主播主页(U8):头部资料卡 + 当前直播状态卡 + 相关直播,fixture 驱动。
/// 布局与信息结构对齐 SFVideoLive AnchorProfileView,以 Flutter 重写。
class AnchorView extends ConsumerWidget {
  const AnchorView({super.key, required this.site, required this.anchorId});

  /// 平台 id。
  final String site;

  /// 主播 id(fixture 阶段即主播昵称)。
  final String anchorId;

  /// SFVideoLive .anchor-profile 的 max-width 52rem。
  static const double _contentMaxWidth = 832;

  void _openRoom(BuildContext context, RoomSummary room) {
    PlaybackLog.logRoomNav(
      source: 'anchor_view',
      site: room.site,
      roomId: room.roomId,
    );
    context.push('/${room.site}/play/${room.roomId}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(
      anchorControllerProvider((site: site, anchorId: anchorId)),
    );
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: _buildBody(context, async),
      ),
    );
  }

  Widget _buildBody(BuildContext context, AsyncValue<AnchorProfileState> async) {
    if (async.isLoading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (async.hasError) {
      return const _MessageView(
        icon: Icons.error_outline_rounded,
        title: '加载失败',
        hint: '请稍后重试',
      );
    }
    final state = async.value;
    if (state == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    final profile = state.profile;
    if (profile == null) {
      return const _MessageView(
        icon: Icons.person_search_rounded,
        title: '未找到该主播',
        hint: '主播可能已改名或离开平台',
      );
    }
    final liveRoom = profile.liveRoom;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AnchorHero(profile: profile),
          const SizedBox(height: AppSpacing.lg),
          AnchorLiveCard(
            profile: profile,
            onEnterRoom:
                liveRoom == null ? () {} : () => _openRoom(context, liveRoom),
          ),
          if (state.relatedRooms.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.lg),
            RelatedRoomList(
              rooms: state.relatedRooms,
              onRoomTap: (room) => _openRoom(context, room),
            ),
          ],
        ],
      ),
    );
  }
}

/// 居中信息占位:错误 / 未找到共用。
class _MessageView extends StatelessWidget {
  const _MessageView({
    required this.icon,
    required this.title,
    required this.hint,
  });

  final IconData icon;
  final String title;
  final String hint;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: tokens.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text(title, style: context.textTitle),
          const SizedBox(height: AppSpacing.xs),
          Text(hint, style: context.textSecondary),
        ],
      ),
    );
  }
}
