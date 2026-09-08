// E3 单测：RemoteSiteSource（fixture 驱动 fake client）。
//
// 覆盖：getRoomDetail 缓存、切房 generation 丢弃旧响应、getPlayQualites 映射、
// getPlayUrls（缓存命中 / partial 补拉）、BrowseRoomItem→LiveRoom 映射、
// categories 双形态映射、SiteRegistry 单例。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/engine/engine.dart';

/// fixture 驱动的 fake：继承 StreamApiClient 复用构造（不发真实请求），
/// 覆盖用到的端点方法。
class FakeStreamApiClient extends StreamApiClient {
  FakeStreamApiClient() : super(config: const StreamApiConfig(baseUrl: 'http://fake'));

  final List<String> roomCalls = [];

  /// room → 闭包：根据 (mode, quality) 返回对应 payload fixture。
  late RoomPayload Function(String room, String mode, String? quality) onFetchRoom;

  /// room → 门闩：未完成时 fetchRoom 挂起，用于切房竞态测试。
  final Map<String, Completer<void>> gates = {};

  Map<String, dynamic>? categoriesJson;
  Map<String, dynamic>? recommendJson;
  Map<String, dynamic>? searchJson;

  @override
  Future<RoomPayload> fetchRoom({
    required String site,
    required String room,
    String mode = 'lazy',
    String? quality,
    bool force = false,
  }) {
    roomCalls.add('$site|$room|$mode|${quality ?? '-'}');
    final gate = gates[room];
    if (gate != null && !gate.isCompleted) {
      return gate.future.then((_) => onFetchRoom(room, mode, quality));
    }
    return Future.value(onFetchRoom(room, mode, quality));
  }

  @override
  Future<CategoriesResponse> fetchCategories(String site) {
    return Future.value(CategoriesResponse.fromJson(categoriesJson!));
  }

  @override
  Future<RoomsResponse> fetchRecommendRooms(String site, {int page = 1}) {
    return Future.value(RoomsResponse.fromJson(recommendJson!));
  }

  @override
  Future<RoomsResponse> fetchCategoryRooms(
    String site, {
    required String cid,
    int page = 1,
    String? pid,
    String? kw,
    String? quality,
    String? country,
  }) {
    categoryRoomCalls.add('cid=$cid|pid=${pid ?? '-'}|page=$page');
    return Future.value(RoomsResponse.fromJson(recommendJson!));
  }

  final List<String> categoryRoomCalls = [];

  @override
  Future<SearchResponse> search({
    required String site,
    required String q,
    int limit = 10,
    String? type,
  }) {
    return Future.value(SearchResponse.fromJson(searchJson!));
  }
}

const roomFullJson = {
  'ok': true,
  'site': 'douyu',
  'room_id': '9999',
  'title': '斗鱼房间A',
  'anchor_name': '主播A',
  'cover': 'http://img/a.jpg',
  'avatar': 'http://img/a.png',
  'category': '王者荣耀',
  'room_state': 'live',
  'is_live': true,
  'available_qualities': [
    {'name': '原画', 'rate': 10000},
    {'name': '高清', 'rate': 2000},
  ],
  'streams': [
    {
      'name': '原画',
      'rate': 10000,
      'lines': [
        {
          'name': '线路1',
          'url': 'http://flv/a1.flv',
          'format': 'flv',
          'headers': {'Referer': 'https://www.douyu.com/'},
        },
        {'name': '线路2', 'url': 'http://flv/a2.flv', 'format': 'flv'},
      ],
    },
    {
      'name': '高清',
      'lines': [
        {'name': '线路1', 'url': 'http://hls/a1.m3u8', 'format': 'hls'},
      ],
    },
  ],
};

const roomPartialJson = {
  'ok': true,
  'site': 'douyu',
  'room_id': '7777',
  'title': '斗鱼房间B',
  'anchor_name': '主播B',
  'room_state': 'live',
  'is_live': true,
  'partial': true,
  'quality': '高清',
  'available_qualities': [
    {'name': '原画'},
    {'name': '高清'},
  ],
  'streams': [
    {
      'name': '高清',
      'lines': [
        {'name': '线路1', 'url': 'http://hls/b_hd.m3u8', 'format': 'hls'},
      ],
    },
  ],
};

const roomFullForQualityJson = {
  'ok': true,
  'site': 'douyu',
  'room_id': '7777',
  'title': '斗鱼房间B',
  'anchor_name': '主播B',
  'room_state': 'live',
  'is_live': true,
  'quality': '原画',
  'streams': [
    {
      'name': '原画',
      'lines': [
        {'name': '线路1', 'url': 'http://hls/b_raw.m3u8', 'format': 'hls'},
      ],
    },
    {
      'name': '高清',
      'lines': [
        {'name': '线路1', 'url': 'http://hls/b_hd.m3u8', 'format': 'hls'},
      ],
    },
  ],
};

void main() {
  late FakeStreamApiClient client;

  setUp(() {
    client = FakeStreamApiClient();
    client.onFetchRoom = (room, mode, quality) {
      if (room == '9999') return RoomPayload.fromJson(roomFullJson);
      if (room == '7777') {
        return RoomPayload.fromJson(quality == '原画' ? roomFullForQualityJson : roomPartialJson);
      }
      fail('unexpected fetchRoom: $room');
    };
  });

  group('RemoteSiteSource.getRoomDetail', () {
    test('映射 RoomPayload → LiveRoom 并写入缓存（getPlayQualites 不再触发请求）', () async {
      final source = RemoteSiteSource('douyu', client);
      final room = await source.getRoomDetail(roomId: '9999', platform: 'douyu');

      expect(room.roomId, '9999');
      expect(room.platform, 'douyu');
      expect(room.title, '斗鱼房间A');
      expect(room.nick, '主播A');
      expect(room.cover, 'http://img/a.jpg');
      expect(room.avatar, 'http://img/a.png');
      expect(room.area, '王者荣耀');
      expect(room.effectiveLiveStatus, LiveStatus.live);

      expect(client.roomCalls, ['douyu|9999|lazy|-']);

      final qualities = await source.getPlayQualites(
        detail: LiveRoom(roomId: '9999', platform: 'douyu'),
      );
      expect(qualities.map((q) => q.quality).toList(), ['原画', '高清']);
      // 缓存命中：没有新的 fetchRoom 调用
      expect(client.roomCalls.length, 1);
    });

    test('切房 generation 防串房：旧房间响应被丢弃，不覆盖缓存', () async {
      client.gates['9999'] = Completer<void>();
      final source = RemoteSiteSource('douyu', client);

      final futureA = source.getRoomDetail(roomId: '9999', platform: 'douyu');
      final roomB = await source.getRoomDetail(roomId: '7777', platform: 'douyu');
      expect(roomB.title, '斗鱼房间B');

      client.gates['9999']!.complete();
      final roomA = await futureA;

      // 旧响应被丢弃：返回 unknown 占位，而不是房间 A 的真实数据
      expect(roomA.effectiveLiveStatus, LiveStatus.unknown);
      expect(roomA.title, '');

      // 缓存仍是房间 B：B 画质直接命中，A 画质则需重新请求
      await source.getPlayQualites(detail: LiveRoom(roomId: '7777', platform: 'douyu'));
      expect(client.roomCalls.length, 2); // 无新调用

      await source.getPlayQualites(detail: LiveRoom(roomId: '9999', platform: 'douyu'));
      expect(client.roomCalls.length, 3); // 补拉 A
      expect(client.roomCalls.last, 'douyu|9999|lazy|-');
    });
  });

  group('RemoteSiteSource 播放', () {
    test('getPlayQualites 从 available_qualities 映射（名称/档位数据/顺序）', () async {
      final source = RemoteSiteSource('douyu', client);
      await source.getRoomDetail(roomId: '9999', platform: 'douyu');

      final qualities = await source.getPlayQualites(
        detail: LiveRoom(roomId: '9999', platform: 'douyu'),
      );
      expect(qualities.length, 2);
      expect(qualities[0].quality, '原画');
      expect(qualities[0].selectionId, '原画');
      expect(qualities[0].data, 10000);
      expect(qualities[0].sort, 0);
      expect(qualities[1].quality, '高清');
      expect(qualities[1].data, 2000);
      expect(qualities[1].sort, 1);
    });

    test('getPlayUrls 缓存命中：返回该档 streams[].lines[] 的原始 url', () async {
      final source = RemoteSiteSource('douyu', client);
      final detail = await source.getRoomDetail(roomId: '9999', platform: 'douyu');

      final urls = await source.getPlayUrls(
        detail: detail,
        quality: LivePlayQuality(quality: '原画', id: '原画'),
      );
      // 原始 url 透传，不做代理改写
      expect(urls, ['http://flv/a1.flv', 'http://flv/a2.flv']);
      expect(client.roomCalls.length, 1); // 全量 payload 已缓存，无需补拉
    });

    test('getPlayUrls partial 未含该档：带 quality 补拉', () async {
      final source = RemoteSiteSource('douyu', client);
      final detail = await source.getRoomDetail(roomId: '7777', platform: 'douyu');

      // 初始为 partial（仅高清档）
      expect(client.roomCalls, ['douyu|7777|lazy|-']);

      final hdUrls = await source.getPlayUrls(
        detail: detail,
        quality: LivePlayQuality(quality: '高清', id: '高清'),
      );
      expect(hdUrls, ['http://hls/b_hd.m3u8']);
      expect(client.roomCalls.length, 1); // partial 已含高清，直接命中

      final rawUrls = await source.getPlayUrls(
        detail: detail,
        quality: LivePlayQuality(quality: '原画', id: '原画'),
      );
      expect(rawUrls, ['http://hls/b_raw.m3u8']);
      expect(client.roomCalls.length, 2);
      expect(client.roomCalls.last, 'douyu|7777|lazy|原画'); // 按档补拉
    });
  });

  group('RemoteSiteSource 浏览/搜索', () {
    test('getRecommendRooms：BrowseRoomItem → LiveRoom 字段映射', () async {
      client.recommendJson = {
        'ok': true,
        'site': 'huya',
        'list': [
          {
            'site': 'huya',
            'room_id': '123',
            'title': '虎牙房间',
            'anchor_name': '主播H',
            'cover': 'http://img/h.jpg',
            'avatar': 'http://img/h.png',
            'category': '英雄联盟',
            'online': 12345,
            'is_live': true,
          },
          {
            'site': 'huya',
            'room_id': '456',
            'title': '未开播',
            'online': 0,
            'is_live': false,
          },
        ],
      };

      final source = RemoteSiteSource('huya', client);
      final rooms = await source.getRecommendRooms();

      expect(rooms.length, 2);
      final live = rooms[0];
      expect(live.roomId, '123');
      expect(live.platform, 'huya');
      expect(live.title, '虎牙房间');
      expect(live.nick, '主播H');
      expect(live.cover, 'http://img/h.jpg');
      expect(live.avatar, 'http://img/h.png');
      expect(live.area, '英雄联盟');
      expect(live.watching, '12345');
      expect(live.effectiveLiveStatus, LiveStatus.live);

      final offline = rooms[1];
      expect(offline.effectiveLiveStatus, LiveStatus.offline);
      expect(offline.watching, '0');
    });

    test('searchRooms / searchAnchors 映射', () async {
      client.searchJson = {
        'ok': true,
        'rooms': [
          {
            'site': 'douyu',
            'room_id': '88',
            'title': '搜索结果',
            'anchor_name': '主播S',
            'is_live': true,
          },
        ],
        'anchors': [
          {'site': 'douyu', 'anchor_id': 'a1', 'name': '主播S', 'avatar': 'http://av.png', 'room_id': '88', 'is_live': true},
        ],
      };

      final source = RemoteSiteSource('douyu', client);
      final rooms = await source.searchRooms('主播S', pageSize: 5);
      expect(rooms.length, 1);
      expect(rooms[0].roomId, '88');
      expect(rooms[0].title, '搜索结果');
      expect(rooms[0].effectiveLiveStatus, LiveStatus.live);

      final anchors = await source.searchAnchors('主播S');
      expect(anchors.length, 1);
      expect(anchors[0].roomId, '88');
      expect(anchors[0].userName, '主播S');
      expect(anchors[0].avatar, 'http://av.png');
      expect(anchors[0].liveStatus, isTrue);
    });

    test('getCategores：新式分组 + 旧式扁平 双形态映射为 LiveCategory/LiveArea', () async {
      client.categoriesJson = {
        'ok': true,
        'site': 'douyu',
        'categories': [
          {
            'id': '1',
            'name': '网游',
            'list': [
              {'cid': '1001', 'name': '英雄联盟', 'pic': 'http://img/lol.png'},
            ],
          },
          // 旧扁平结构（无 list 字段）
          {'cid': '2001', 'name': '主机', 'pic': 'http://img/host.png'},
        ],
      };

      final source = RemoteSiteSource('douyu', client);
      final categories = await source.getCategores(1, 30);

      expect(categories.length, 2);

      final grouped = categories[0];
      expect(grouped.id, '1');
      expect(grouped.name, '网游');
      expect(grouped.children.length, 1);
      expect(grouped.children[0].areaId, '1001');
      expect(grouped.children[0].areaName, '英雄联盟');
      expect(grouped.children[0].areaPic, 'http://img/lol.png');
      expect(grouped.children[0].platform, 'douyu');
      expect(grouped.children[0].typeName, '网游');

      final flat = categories[1];
      expect(flat.name, '');
      expect(flat.children.length, 1);
      expect(flat.children[0].areaId, '2001');
      expect(flat.children[0].areaName, '主机');
    });

    test('getCategoryRooms：LiveArea → cid/pid 参数与房间映射', () async {
      client.recommendJson = {
        'ok': true,
        'site': 'douyu',
        'list': [
          {'site': 'douyu', 'room_id': '1', 'title': '分类房1', 'is_live': true},
        ],
      };

      final source = RemoteSiteSource('douyu', client);
      final area = LiveArea(platform: 'douyu', areaType: '1', typeName: '网游', areaId: '1001');
      final rooms = await source.getCategoryRooms(area, page: 2);

      expect(client.categoryRoomCalls, ['cid=1001|pid=1|page=2']);
      expect(rooms.length, 1);
      expect(rooms[0].roomId, '1');
      expect(rooms[0].title, '分类房1');
      expect(rooms[0].effectiveLiveStatus, LiveStatus.live);
    });

    test('SiteRegistry：init 前抛错，init 后按 siteId 单例', () {
      SiteRegistry.reset();

      expect(() => SiteRegistry.sourceOf('douyu'), throwsStateError);

      SiteRegistry.init(client);
      final a = SiteRegistry.sourceOf('douyu');
      final b = SiteRegistry.sourceOf('douyu');
      final c = SiteRegistry.sourceOf('huya');
      expect(identical(a, b), isTrue);
      expect(identical(a, c), isFalse);
      expect(a.id, 'douyu');
      expect(c.id, 'huya');

      expect(SiteRegistry.knownSiteIds, containsAll(['douyu', 'huya', 'bilibili', 'xhs', 'iptv']));

      SiteRegistry.reset();
    });
  });
}
