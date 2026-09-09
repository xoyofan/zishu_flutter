import 'package:live_parser/live_parser.dart';
import 'package:test/test.dart';

void main() {
  test('buildSiteRegistry 注册斗鱼并声明能力', () {
    final registry = buildSiteRegistry();

    expect(registry.supportedSites, contains('douyu'));
    final douyu = registry['douyu']!;
    expect(douyu.id, 'douyu');
    expect(douyu.name, '斗鱼');
    expect(douyu.resolver, isA<RoomResolver>());
    expect(douyu.browse, isA<BrowseRepository>());
    expect(douyu.search, isA<SearchRepository>());

    expect(douyu.capabilities.browse, isTrue);
    expect(douyu.capabilities.roomSearch, isTrue);
    expect(douyu.capabilities.anchorSearch, isTrue);
    expect(douyu.capabilities.multiQuality, isTrue);
    expect(douyu.capabilities.multiLine, isTrue);
    expect(douyu.capabilities.danmaku, isTrue);
    expect(douyu.danmaku, isNotNull, reason: '能力开启即注册连接器');
    expect(douyu.capabilities.requiresCookie, isFalse);
  });

  test('buildSiteRegistry 注册虎牙并声明能力', () {
    final registry = buildSiteRegistry();

    expect(registry.supportedSites, contains('huya'));
    final huya = registry['huya']!;
    expect(huya.id, 'huya');
    expect(huya.name, '虎牙');
    expect(huya.resolver, isA<RoomResolver>());
    expect(huya.browse, isA<BrowseRepository>());
    expect(huya.search, isA<SearchRepository>());

    expect(huya.capabilities.browse, isTrue);
    expect(huya.capabilities.roomSearch, isTrue);
    expect(huya.capabilities.anchorSearch, isTrue);
    expect(huya.capabilities.danmaku, isTrue);
    expect(huya.capabilities.multiQuality, isTrue);
    expect(huya.capabilities.multiLine, isTrue);
    expect(huya.capabilities.requiresCookie, isFalse);
  });

  test('buildSiteRegistry 注册 B 站并声明能力', () {
    final registry = buildSiteRegistry();

    expect(registry.supportedSites, contains('bilibili'));
    final bilibili = registry['bilibili']!;
    expect(bilibili.id, 'bilibili');
    expect(bilibili.name, 'B站');
    expect(bilibili.resolver, isA<RoomResolver>());
    expect(bilibili.browse, isA<BrowseRepository>());
    expect(bilibili.search, isA<SearchRepository>());

    expect(bilibili.capabilities.browse, isTrue);
    expect(bilibili.capabilities.roomSearch, isTrue);
    expect(bilibili.capabilities.anchorSearch, isTrue);
    expect(bilibili.capabilities.danmaku, isTrue);
    expect(bilibili.capabilities.multiQuality, isTrue);
    expect(bilibili.capabilities.multiLine, isTrue);
  });

  test('buildSiteRegistry 注册全平台聚合(斗鱼+虎牙+B站)', () async {
    final registry = buildSiteRegistry();

    expect(registry.supportedSites, contains('all'));
    final all = registry['all']!;
    expect(all.id, 'all');
    expect(all.name, '全平台');
    expect(all.browse, isA<CrossBrowseRepository>());
    expect(all.capabilities.browse, isTrue);

    // 聚合站点本身没有房间解析/搜索/弹幕,必须落到具体平台。
    expect(all.search, isNull);
    expect(all.danmaku, isNull);
    expect(all.capabilities.danmaku, isFalse);

    final categories = await all.browse!.fetchCategories('all');
    expect(categories.site, 'all');
    expect(categories.groups.single.items.map((e) => e.cid), contains('lol'));

    final cross = all.browse! as CrossBrowseRepository;
    expect(cross.siteIds, ['douyu', 'huya', 'bilibili']);
    expect(
      cross.registry['douyu']?.browse,
      isNotNull,
      reason: '聚合持有宿主同一 registry,参与站点可解析',
    );
  });

  test('buildSiteRegistry 注册 IPTV 占位(空源,能力受限)', () {
    final registry = buildSiteRegistry();

    expect(registry.supportedSites, contains('iptv'));
    final iptv = registry['iptv']!;
    expect(iptv.id, 'iptv');
    expect(iptv.name, 'IPTV');
    expect(iptv.browse, isA<BrowseRepository>());
    expect(iptv.search, isA<SearchRepository>());

    expect(iptv.capabilities.browse, isTrue);
    expect(iptv.capabilities.roomSearch, isTrue);
    expect(iptv.capabilities.danmaku, isFalse, reason: 'IPTV 无弹幕');
    expect(iptv.danmaku, isNull);
    expect(iptv.capabilities.requiresCookie, isFalse);

    // 空源占位:频道不存在
    expect(
      iptv.browse!.fetchRooms(const RoomListRequest(site: 'iptv', cid: null)),
      completion(
        isA<RoomListResult>().having((r) => r.rooms, 'rooms', isEmpty),
      ),
    );
  });
}
