import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/registry/cached_room_resolver.dart';
import 'package:test/test.dart';

import 'support/fake_browse.dart';

/// 最小 fake 解析器:按调用序轮换播放 URL,可注入失败。
class _SequenceResolver implements RoomResolver {
  int calls = 0;
  Object? failure;

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    calls++;
    final failure = this.failure;
    if (failure != null) throw failure;
    return RoomPayload(
      site: request.site,
      roomId: request.roomIdOrUrl,
      sourceUrl: 'https://demo/room/${request.roomIdOrUrl}',
      anchorName: '主播',
      title: '房间',
      cover: '',
      avatar: '',
      category: '',
      cid: '1',
      roomState: RoomState.live,
      streams: [
        StreamQuality(
          name: '高清',
          rate: 1,
          lines: [
            StreamLine(
              name: '线路',
              url: 'https://stream/$calls.m3u8',
              format: 'hls',
            ),
          ],
        ),
      ],
      availableQualities: const [QualityOption(name: '高清', rate: 1)],
      source: 'test',
      fetchedAt: DateTime.now(),
    );
  }
}

/// 直接实现刷新的 fake(用于 refresher 部件失败传播)。
class _FailingRefresher implements RoomResolver, RoomSummaryRefresher {
  int refreshCalls = 0;

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async =>
      throw UnimplementedError();

  @override
  Future<RoomRecord> refreshRoomSummary(RoomRequest request) async {
    refreshCalls++;
    throw StateError('refresh boom');
  }
}

/// 搜索部件:存在但 Future 失败。
class _FailingSearch implements SearchRepository {
  @override
  Future<SearchResult> search(SearchRequest request) async =>
      throw StateError('search boom');
}

/// 弹幕部件:存在但 Future 失败。
class _FailingDanmaku implements DanmakuConnector {
  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async =>
      throw StateError('danmaku boom');
}

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

  test('buildSiteRegistry 注册 YY 并声明能力', () {
    final registry = buildSiteRegistry();

    expect(registry.supportedSites, contains('yy'));
    final yy = registry['yy']!;
    expect(yy.id, 'yy');
    expect(yy.name, 'YY');
    expect(yy.resolver, isA<RoomResolver>());
    expect(yy.browse, isA<BrowseRepository>());
    expect(yy.search, isA<SearchRepository>());
    expect(yy.capabilities.browse, isTrue);
    expect(yy.capabilities.roomSearch, isTrue);
    expect(yy.capabilities.anchorSearch, isTrue);
    expect(yy.capabilities.multiQuality, isTrue);
    expect(yy.capabilities.multiLine, isTrue);
    expect(yy.capabilities.danmaku, isTrue, reason: 'YY trident 弹幕协议已接入');
    expect(yy.danmaku, isNotNull);
  });

  test('buildSiteRegistry 注册全平台聚合(现有可浏览直播站)', () async {
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
    // xhs 接入后具备 browse 能力,自动进入聚合尾部(canonical 九站之后)。
    expect(cross.siteIds, [
      'douyu',
      'huya',
      'bilibili',
      'douyin',
      'kuaishou',
      'yy',
      'twitch',
      'soop',
      'youtube',
      'xhs',
    ]);
    expect(
      cross.registry['douyu']?.browse,
      isNotNull,
      reason: '聚合持有宿主同一 registry,参与站点可解析',
    );
  });

  group('LiveSite 统一站点外观', () {
    const nineSites = [
      'douyu',
      'huya',
      'bilibili',
      'twitch',
      'yy',
      'soop',
      'kuaishou',
      'douyin',
      'youtube',
    ];

    test('不支持弹幕的站点返回 null,而不是空连接', () {
      // 九站现已全部接入弹幕,用合成站点锁定「不声明能力即不暴露部件」的
      // 契约,避免把真实站点的能力变化误当成外观缺陷。
      final registry = SiteRegistry()
        ..register(
          SiteRegistration(
            id: 'no-danmaku',
            name: '无弹幕测试站',
            capabilities: const SiteCapabilities(browse: true),
            resolver: UnsupportedRoomResolver('no-danmaku'),
          ),
        );
      final site = registry.site('no-danmaku')!;
      expect(site.danmaku, isNull);
      expect(site.capabilities.danmaku, isFalse);
    });

    test('九站:LiveSite 与注册项同源,声明的 browse/search/danmaku 与部件双向一致', () {
      final registry = buildSiteRegistry();
      for (final id in nineSites) {
        final registration = registry[id]!;
        final site = registry.site(id)!;
        expect(site.id, registration.id, reason: id);
        expect(site.name, registration.name, reason: id);
        expect(site.capabilities, same(registration.capabilities), reason: id);
        expect(site.display, same(registration.display), reason: id);

        expect(
          site.capabilities.browse,
          site.browse != null,
          reason: '$id browse 能力与部件一致',
        );
        expect(
          site.capabilities.danmaku,
          site.danmaku != null,
          reason: '$id danmaku 能力与部件一致',
        );
        // 搜索能力与部件双向一致:声明即有部件;未声明(快手/YouTube)
        // 即使旧注册项带返回空结果的占位部件,新外观也必须暴露为 null ——
        // 否则调用方看到「支持但无结果」而非 N/A(能力假阳性)。
        expect(
          site.capabilities.roomSearch || site.capabilities.anchorSearch,
          site.search != null,
          reason: '$id 搜索能力与部件双向一致',
        );
      }
    });

    test('未声明的能力部件为 null(YouTube/快手无搜索、聚合站只有浏览)', () {
      final registry = buildSiteRegistry();
      final youtube = registry.site('youtube')!;
      expect(youtube.capabilities.roomSearch, isFalse);
      expect(youtube.search, isNull);
      // 快手旧注册项带占位搜索部件,新外观按能力过滤为 null(N/A)。
      final kuaishou = registry.site('kuaishou')!;
      expect(kuaishou.capabilities.roomSearch, isFalse);
      expect(kuaishou.capabilities.anchorSearch, isFalse);
      expect(kuaishou.search, isNull);

      final all = registry.site('all')!;
      expect(all.capabilities.browse, isTrue);
      expect(all.browse, isNotNull);
      expect(all.search, isNull);
      expect(all.danmaku, isNull);
    });

    test('refresher 按内层真实能力逐站判定:装饰器不可把未实现刷新误称为支持', () {
      final registry = buildSiteRegistry();
      const refreshImplemented = {
        'douyu': true,
        'huya': true,
        'bilibili': true,
        'twitch': true,
        'yy': true,
        'soop': true,
        'kuaishou': true,
        'douyin': true,
        // YouTube 内层未实现刷新:短缓存包装恒 `is RoomSummaryRefresher`,
        // 但注册时必须按内层真实能力判 null。
        'youtube': false,
      };
      refreshImplemented.forEach((id, implemented) {
        expect(
          registry.site(id)!.refresher != null,
          implemented,
          reason: '$id refresher 应按内层真实实现判定',
        );
      });
      // 聚合站占位 resolver 无刷新能力。
      expect(registry.site('all')!.refresher, isNull);
    });

    test('recovery:九站经短缓存包装均可恢复;聚合站为 null', () {
      final registry = buildSiteRegistry();
      for (final id in nineSites) {
        expect(registry.site(id)!.recovery, isNotNull, reason: id);
      }
      expect(registry.site('all')!.recovery, isNull);
    });

    test('resolveRoom 返回 RoomRecord;偏好档第二次命中缓存,recovery 绕开且 URL 更新', () async {
      final inner = _SequenceResolver();
      final registry = SiteRegistry()
        ..register(
          SiteRegistration(
            id: 'demo',
            name: '演示',
            capabilities: const SiteCapabilities(multiQuality: true),
            resolver: CachedRoomResolver(inner),
          ),
        );
      final site = registry.site('demo')!;
      const request = RoomRequest(
        site: 'demo',
        roomIdOrUrl: '42',
        preferredQuality: '高清',
      );

      final first = await site.resolveRoom(request);
      final second = await site.resolveRoom(request);
      expect(first, isA<RoomRecord>());
      expect(first.roomState, RoomState.live);
      expect(first.playUrl, 'https://stream/1.m3u8');
      expect(second.playUrl, 'https://stream/1.m3u8');
      expect(inner.calls, 1, reason: '带偏好画质的第二次解析走短缓存');

      final recovered = await site.recovery!.recoverRoom(request);
      expect(inner.calls, 2, reason: '恢复绕开缓存新增一次真实请求');
      expect(
        recovered.playUrl,
        'https://stream/2.m3u8',
        reason: '恢复必须返回更新后的播放 URL',
      );
    });

    test('部件存在但 Future 失败:异常原样传播,不伪装成空值', () async {
      final inner = _SequenceResolver();
      final registry = SiteRegistry()
        ..register(
          SiteRegistration(
            id: 'demo',
            name: '演示',
            capabilities: const SiteCapabilities(
              browse: true,
              roomSearch: true,
              danmaku: true,
              multiQuality: true,
            ),
            resolver: CachedRoomResolver(inner),
            browse: FakeBrowseRepository(site: 'demo', fail: true),
            search: _FailingSearch(),
            danmaku: _FailingDanmaku(),
          ),
        );
      final site = registry.site('demo')!;
      const request = RoomRequest(site: 'demo', roomIdOrUrl: '42');

      inner.failure = StateError('resolve boom');
      await expectLater(
        site.resolveRoom(request),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        site.recovery!.recoverRoom(request),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        site.browse!.fetchRooms(const RoomListRequest(site: 'demo')),
        throwsA(isA<ParserHttpException>()),
      );
      await expectLater(
        site.search!.search(const SearchRequest(site: 'demo', query: 'q')),
        throwsA(isA<StateError>()),
      );
      await expectLater(
        site.danmaku!.connect(
          const DanmakuSessionRequest(site: 'demo', roomId: '42'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('refresher 部件存在但刷新失败:throwsA 原样传播', () async {
      final registry = SiteRegistry()
        ..register(
          SiteRegistration(
            id: 'demo',
            name: '演示',
            capabilities: const SiteCapabilities(),
            resolver: CachedRoomResolver(_FailingRefresher()),
          ),
        );
      final site = registry.site('demo')!;
      expect(site.refresher, isNotNull);

      await expectLater(
        site.refresher!.refreshRoomSummary(
          const RoomRequest(site: 'demo', roomIdOrUrl: '42'),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
