import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/fixture_sources.dart';

/// 主播主页 family 参数:路由只透传 site/id,大对象不进路由。
typedef AnchorScope = ({String site, String anchorId});

/// 主播资料:由 fixture 房间构造,统计字段为 UI 演示样例。
class AnchorProfile {
  const AnchorProfile({
    required this.site,
    required this.nickname,
    required this.avatarUrl,
    required this.state,
    required this.fansLabel,
    required this.videosLabel,
    this.liveRoom,
  });

  /// 所属平台 id,与 shared/presentation/platform_brands.dart 的目录对应。
  final String site;

  /// 主播昵称。
  final String nickname;

  /// 头像地址(样例固定走 pravatar)。
  final String avatarUrl;

  /// 直播状态,复用契约枚举 SearchHitState 表达。
  final SearchHitState state;

  /// 当前直播中的房间;离线时为 null。
  final RoomSummary? liveRoom;

  /// 样例粉丝数。
  final String fansLabel;

  /// 样例视频数。
  final String videosLabel;

  bool get isLive => state == SearchHitState.live;
}

/// 主播主页状态;[profile] 为 null 表示未找到该主播。
class AnchorProfileState {
  const AnchorProfileState({this.profile, this.relatedRooms = const []});

  final AnchorProfile? profile;

  /// 相关直播:同分类的其他房间优先,不足时按 fixture 顺序补足,最多 6 个。
  final List<RoomSummary> relatedRooms;

  bool get notFound => profile == null;
}

/// 主播主页 controller:按 (site, anchorId) 从 kFixtureRooms 构造资料。
class AnchorController extends AsyncNotifier<AnchorProfileState> {
  AnchorController(this.scope);

  final AnchorScope scope;

  @override
  FutureOr<AnchorProfileState> build() {
    final own = _findOwnRoom(kFixtureRooms);
    if (own == null) {
      // 未命中主播:返回「未找到」状态,由视图渲染空态。
      return const AnchorProfileState();
    }
    return AnchorProfileState(
      profile: _buildProfile(own),
      relatedRooms: _relatedRooms(kFixtureRooms, own),
    );
  }

  /// 按 anchorId 匹配主播昵称,同时校验 site 一致(跨平台同名不冲突)。
  RoomSummary? _findOwnRoom(List<RoomSummary> rooms) {
    for (final room in rooms) {
      if (room.anchorName == scope.anchorId && room.site == scope.site) {
        return room;
      }
    }
    // site 不匹配时回退为纯昵称匹配,兼容「全平台」入口传 site=all 的场景。
    for (final room in rooms) {
      if (room.anchorName == scope.anchorId) {
        return room;
      }
    }
    return null;
  }

  AnchorProfile _buildProfile(RoomSummary own) {
    final seed = int.tryParse(own.roomId) ?? 0;
    return AnchorProfile(
      site: own.site,
      nickname: own.anchorName,
      avatarUrl: 'https://i.pravatar.cc/150?img=${(seed % 70) + 1}',
      state: SearchHitState.live,
      liveRoom: own,
      // 以下为样例统计,仅驱动 UI,真实数据接入后由资料接口提供。
      fansLabel: '${12 + (seed % 880) / 10}万',
      videosLabel: '${120 + seed % 2600}',
    );
  }

  /// 相关房间:同分类(排除自己)优先,再补其他房间,最多 6 个。
  List<RoomSummary> _relatedRooms(List<RoomSummary> rooms, RoomSummary own) {
    final sameCategory = rooms
        .where((room) => room.category == own.category && room.roomId != own.roomId)
        .toList();
    final others = rooms
        .where((room) => room.category != own.category && room.roomId != own.roomId)
        .toList();
    return [...sameCategory, ...others].take(6).toList(growable: false);
  }
}

/// 主播主页 provider(autoDispose:离开页面即释放)。
final anchorControllerProvider = AsyncNotifierProvider.autoDispose
    .family<AnchorController, AnchorProfileState, AnchorScope>(AnchorController.new);
