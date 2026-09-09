/// fixture 数据源:G0 阶段 UI 完全用样例数据驱动样式,不依赖真实解析。
/// 数据形状与 live_parser 契约模型一致,后续换实现不改 Widget。
library;

import 'package:live_parser/live_parser.dart';

import 'browse_source.dart';

/// 首页/分类网格样例房间。
final List<RoomSummary> kFixtureRooms = [
  RoomSummary(
    site: 'douyu',
    roomId: '63136',
    title: '英雄联盟 高分排位 冲击王者',
    anchorName: '神超',
    cid: '1',
    category: '英雄联盟',
    online: '42.1万',
    cover: 'https://placeholder.zishu.dev/douyu/63136.jpg',
    promoTag: '官方',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '288016',
    title: '云顶之弈 上分教学 赛季末冲分',
    anchorName: '红莲',
    cid: '1',
    category: '云顶之弈',
    online: '18.7万',
    cover: 'https://placeholder.zishu.dev/douyu/288016.jpg',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '71415',
    title: '无畏契约 冠军联赛二路解说',
    anchorName: 'CFCL解说台',
    cid: '8',
    category: '无畏契约',
    online: '9.3万',
    cover: 'https://placeholder.zishu.dev/douyu/71415.jpg',
    promoTag: '赛事',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '74960',
    title: '深夜唱见 温柔声线点歌台',
    anchorName: '小缘',
    cid: '2',
    category: '唱见',
    online: '5.8万',
    cover: 'https://placeholder.zishu.dev/douyu/74960.jpg',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '9999',
    title: '王者荣耀 巅峰赛 2500 分冲榜',
    anchorName: '耀神',
    cid: '1',
    category: '王者荣耀',
    online: '23.4万',
    cover: 'https://placeholder.zishu.dev/douyu/9999.jpg',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '24422',
    title: '永劫无间 天人榜第一 千杀修行',
    anchorName: 'ZX',
    cid: '1',
    category: '永劫无间',
    online: '7.2万',
    cover: 'https://placeholder.zishu.dev/douyu/24422.jpg',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '606118',
    title: '炉石传说 标准传说卡组试玩',
    anchorName: '啦啦啦是茶',
    cid: '1',
    category: '炉石传说',
    online: '3.1万',
    cover: 'https://placeholder.zishu.dev/douyu/606118.jpg',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '445245',
    title: '户外 逛街探店 城市漫游',
    anchorName: '二细',
    cid: '3',
    category: '户外',
    online: '1.9万',
    cover: 'https://placeholder.zishu.dev/douyu/445245.jpg',
    promoTag: '新秀',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '518801',
    title: '主机游戏 艾尔登法环 DLC 全收集',
    anchorName: '老戴',
    cid: '1',
    category: '主机游戏',
    online: '6.6万',
    cover: 'https://placeholder.zishu.dev/douyu/518801.jpg',
  ),
  RoomSummary(
    site: 'douyu',
    roomId: '723100',
    title: '一起看电影 经典港片连播',
    anchorName: '影迷小站',
    cid: '3',
    category: '影视',
    online: '8921',
    cover: 'https://placeholder.zishu.dev/douyu/723100.jpg',
  ),
];

/// 播放页样例 payload:多画质 + 多线路。
RoomPayload fixtureRoomPayload(String roomId) {
  const qualities = [
    ('蓝光8M', 0),
    ('超清', 2),
    ('高清', 3),
    ('流畅', 4),
  ];
  return RoomPayload(
    site: 'douyu',
    roomId: roomId,
    sourceUrl: 'https://www.douyu.com/$roomId',
    anchorName: '神超',
    title: '英雄联盟 高分排位 冲击王者',
    cover: 'https://placeholder.zishu.dev/douyu/$roomId.jpg',
    avatar: 'https://placeholder.zishu.dev/douyu/$roomId-avatar.jpg',
    category: '英雄联盟',
    cid: '1',
    roomState: RoomState.live,
    availableQualities: [
      for (final (name, rate) in qualities) QualityOption(name: name, rate: rate),
    ],
    streams: [
      for (final (name, rate) in qualities)
        StreamQuality(
          name: name,
          rate: rate,
          lines: [
            StreamLine(name: 'HLS', url: 'https://fixture.zishu.dev/$roomId/$rate/index.m3u8', format: 'hls'),
            StreamLine(name: '主线 FLV', url: 'https://fixture.zishu.dev/$roomId/$rate/main.flv', format: 'flv'),
            StreamLine(name: '备线 FLV', url: 'https://fixture.zishu.dev/$roomId/$rate/backup.flv', format: 'flv'),
          ],
        ),
    ],
    source: 'fixture',
    fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
  );
}

class FixtureBrowseSource implements BrowseSource {
  const FixtureBrowseSource();

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    const groups = [
      ('1', '网游竞技', [('1', '英雄联盟', 'LOL'), ('8', '无畏契约', 'VAL'), ('3203', '云顶之弈', 'TFT')]),
      ('2', '娱乐天地', [('2', '唱见', 'SING'), ('16', '颜值', 'FACE')]),
      ('3', '户外休闲', [('3', '户外', 'OUT'), ('245', '影视', 'MOVIE')]),
    ];
    return CategoryResult(
      site: site,
      groups: [
        for (final (id, name, items) in groups)
          CategoryGroup(
            id: id,
            name: name,
            items: [for (final (cid, cname, _) in items) CategoryItem(cid: cid, name: cname, pic: '')],
          ),
      ],
    );
  }

  @override
  Future<RoomListResult> fetchRooms({required String site, String? cid, int page = 1}) async {
    final rooms = cid == null || cid.isEmpty
        ? kFixtureRooms
        : kFixtureRooms.where((room) => room.cid == cid).toList();
    return RoomListResult(rooms: rooms, page: page, hasMore: false);
  }
}

class FixtureRoomSource implements RoomSource {
  const FixtureRoomSource();

  @override
  Future<RoomPayload> resolveRoom({required String site, required String roomIdOrUrl}) async {
    final roomId = RegExp(r'(\d+)\s*$').firstMatch(roomIdOrUrl)?.group(1) ?? roomIdOrUrl;
    return fixtureRoomPayload(roomId);
  }
}
