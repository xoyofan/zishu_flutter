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
  Future<RoomPayload> resolveRoom({required String site, required String roomIdOrUrl});
}
