/// 浏览数据源端口:UI 只依赖此接口;实现分为 fixture(样式开发)与 direct(真实解析)。
library;

import 'package:live_parser/live_parser.dart';

/// 栏目浏览数据源。
abstract interface class BrowseSource {
  Future<CategoryResult> fetchCategories(String site);
  Future<RoomListResult> fetchRooms({required String site, String? cid, int page});
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
