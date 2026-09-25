/// 浏览数据源端口:UI 只依赖此接口;实现分为 fixture(样式开发)与 direct(真实解析)。
library;

import 'package:live_parser/live_parser.dart';

/// 栏目浏览数据源。
abstract interface class BrowseSource {
  Future<CategoryResult> fetchCategories(String site);

  /// 拉取房间列表首页/下一页。
  ///
  /// [limit] = 本次请求条数;`null` 表示调用方不指定,由实现取默认口径
  /// (真实解析 30)。首页「按平台区块」路径下发首屏列数(见
  /// `PlatformRoomsQuery.limit`),单平台页旧路径不指定,保持既有行为。
  Future<RoomListResult> fetchRooms({
    required String site,
    String? cid,
    int page,
    int? limit,
  });
}

/// 房间解析数据源(播放页)。
abstract interface class RoomSource {
  /// [preferredQuality] 为生效的默认画质(平台级设置);解析侧可据此只取该档
  /// 流地址(懒取流),其余档位以占位线路返回,由播放页切换时按需重解析。
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  });
}

/// 可恢复的房间解析数据源(可选能力)。
///
/// 与 [RoomSource.resolveRoom] 的关键差别:**必须绕开缓存重新获取**地址。
/// 签名平台(虎牙等)的播放地址带时效参数,生命周期短于观看会话;播放器自动
/// 重连耗尽后必须拿一份全新地址,复用旧地址等于无限重开一个已过期的源。
///
/// 播放器侧对应 `LineRecoveryAware`,解析层对应 live_parser 的
/// `RoomRecoveryResolver` —— 三者构成同一条恢复链路。
///
/// 继承 [RoomSource]:能恢复者必能解析,同时让调用点 `is` 探测后可
/// 直接调用(类型提升要求子类型关系)。
abstract interface class RoomRecoverer implements RoomSource {
  Future<RoomPayload> recoverRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  });
}

/// 轻量房间状态刷新能力(可选)。
///
/// 与 [RoomSource.resolveRoom] 的差别:不解析播放地址、不做签名 —— 只拿
/// 「这个房间此刻在不在播」以及标题/封面/在线数这类元信息。因此它可以被关注
/// 列表**周期性**调用(顶栏「我的关注」浮层、侧栏最近在播都读它的结果),
/// 而 [RoomSource.resolveRoom] 的成本无法承受这种频率。
///
/// 失败由调用方**按条目隔离**:单条抛错只能保留该条旧值,不得把已有列表刷成
/// 空、也不得把在播房间翻成离线(网络抖动不是「下播」)。
///
/// fixture 源不实现本能力,关注列表据此保持「样例数据、零网络」的既有行为。
///
/// 返回统一 [RoomRecord]:状态真源是 `roomState`,本次未取到的统计字段为
/// `null`(不伪造 0);存储仍是 `RoomSummary` 的消费者在边界自行转换
/// (`RoomRecord.toSummary` / `RoomRecord.fromSummary`)。
///
/// 继承 [RoomSource]:让调用点 `is` 探测获得类型提升(同 [RoomRecoverer])。
abstract interface class RoomRefresher implements RoomSource {
  Future<RoomRecord> refreshRoom({
    required String site,
    required String roomId,
  });
}

/// 关注平台一次返回的直播快照。
class FollowLiveSnapshot {
  const FollowLiveSnapshot({required this.rooms, required this.complete});

  /// 接口返回的正在直播房间。
  final List<RoomRecord> rooms;

  /// 是否已读到服务端 `has_more=false`；false 时不能把缺失项标记为离线。
  final bool complete;
}

/// 关注直播批量刷新能力(可选)。
///
/// 与逐房间 [RoomRefresher] 分离：抖音等平台可用一次 feed 请求返回
/// 当前关注直播流，避免关注数量增大后逐条请求。
abstract interface class FollowLiveRefresher {
  Future<FollowLiveSnapshot> refreshFollowLive();
}

/// 关注导入进度。
class FollowImportProgress {
  const FollowImportProgress({
    required this.page,
    required this.imported,
    this.total = 0,
    this.refreshing = false,
  });

  final int page;
  final int imported;
  final int total;
  final bool refreshing;
}

/// 平台关注列表导入能力(可选)。
abstract interface class FollowImportSource {
  Future<List<RoomSummary>> importDouyinFollows({
    void Function(FollowImportProgress progress)? onProgress,
  });
}
