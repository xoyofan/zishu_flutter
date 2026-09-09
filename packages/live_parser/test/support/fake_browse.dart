/// 聚合测试用浏览仓库:固定返回/失败,并记录最后一次请求。
library;

import 'package:live_parser/live_parser.dart';

class FakeBrowseRepository implements BrowseRepository {
  FakeBrowseRepository({
    required this.site,
    this.rooms = const [],
    this.hasMore = false,
    this.fail = false,
    this.categories = const [],
  });

  final String site;
  List<RoomSummary> rooms;
  bool hasMore;
  bool fail;
  List<CategoryGroup> categories;

  RoomListRequest? lastRequest;
  int callCount = 0;

  @override
  Future<CategoryResult> fetchCategories(String site) async =>
      CategoryResult(site: site, groups: categories);

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    lastRequest = request;
    callCount++;
    if (fail) throw const ParserHttpException('fake upstream failure');
    return RoomListResult(rooms: rooms, page: request.page, hasMore: hasMore);
  }
}

/// 构造测试用房间摘要。
RoomSummary fakeRoom(
  String site,
  String roomId, {
  String category = '',
  String cid = '',
  String online = '0',
}) => RoomSummary(
  site: site,
  roomId: roomId,
  title: 'title-$roomId',
  anchorName: 'anchor-$roomId',
  cid: cid,
  category: category,
  online: online,
  cover: '',
);

/// 注册一个仅供测试的站点(无房间解析能力)。
SiteRegistration fakeSiteRegistration({
  required String site,
  required BrowseRepository browse,
}) => SiteRegistration(
  id: site,
  name: site,
  capabilities: const SiteCapabilities(browse: true),
  resolver: UnsupportedRoomResolver(site),
  browse: browse,
);
