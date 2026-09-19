import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/features/play/application/room_volume_provider.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';

const _sites = <String>{
  'douyu',
  'huya',
  'bilibili',
  'douyin',
  'kuaishou',
  'yy',
  'twitch',
  'soop',
  'youtube',
  'iptv',
};

void main() {
  test('所有已注册目标平台都提供稳定 registration 和 resolver', () {
    final registry = buildSiteRegistry();

    expect(registry.supportedSites, containsAll(_sites));
    for (final site in _sites) {
      final registration = registry[site];
      expect(registration, isNotNull, reason: '$site 必须注册');
      expect(registration!.id, site);
      expect(registration.name, isNotEmpty);
      expect(registration.resolver, isA<RoomResolver>());
    }
  });

  test('能力为 true 时对应入口依赖必须存在', () {
    final registry = buildSiteRegistry();

    for (final site in _sites) {
      final registration = registry[site]!;
      final capabilities = registration.capabilities;
      if (capabilities.browse) {
        expect(
          registration.browse,
          isNotNull,
          reason: '$site 声明 browse 但没有 browse repository',
        );
      }
      if (capabilities.roomSearch || capabilities.anchorSearch) {
        expect(
          registration.search,
          isNotNull,
          reason: '$site 声明 search capability 但没有 search repository',
        );
      }
      if (capabilities.danmaku) {
        expect(
          registration.danmaku,
          isNotNull,
          reason: '$site 声明 danmaku 但没有 connector',
        );
        expect(registration.danmaku!.capabilities.danmaku, isTrue);
      }
    }
  });

  test('平台能力基线与注册表保持一致', () {
    final registry = buildSiteRegistry();
    const expected = <String, SiteCapabilities>{
      'douyu': SiteCapabilities(
        browse: true,
        roomSearch: true,
        anchorSearch: true,
        danmaku: true,
        multiQuality: true,
        multiLine: true,
      ),
      'huya': SiteCapabilities(
        browse: true,
        roomSearch: true,
        anchorSearch: true,
        danmaku: true,
        multiQuality: true,
        multiLine: true,
      ),
      'bilibili': SiteCapabilities(
        browse: true,
        roomSearch: true,
        anchorSearch: true,
        danmaku: true,
        multiQuality: true,
        multiLine: true,
      ),
      'douyin': SiteCapabilities(
        browse: true,
        roomSearch: true,
        anchorSearch: true,
        danmaku: true,
        multiQuality: true,
        multiLine: true,
      ),
      'kuaishou': SiteCapabilities(
        browse: true,
        danmaku: true,
        multiQuality: true,
        multiLine: true,
      ),
      'yy': SiteCapabilities(
        browse: true,
        roomSearch: true,
        anchorSearch: true,
        multiQuality: true,
        multiLine: true,
      ),
      'twitch': SiteCapabilities(
        browse: true,
        roomSearch: true,
        anchorSearch: true,
        danmaku: true,
        multiQuality: true,
      ),
      'soop': SiteCapabilities(
        browse: true,
        roomSearch: true,
        anchorSearch: true,
        danmaku: true,
        multiQuality: true,
        multiLine: true,
      ),
      'youtube': SiteCapabilities(
        browse: true,
        danmaku: true,
        multiQuality: true,
        multiLine: true,
      ),
      'iptv': SiteCapabilities(browse: true, roomSearch: true, multiLine: true),
    };

    for (final entry in expected.entries) {
      final actual = registry[entry.key]!.capabilities;
      final wanted = entry.value;
      expect(actual.browse, wanted.browse, reason: '${entry.key}.browse');
      expect(
        actual.roomSearch,
        wanted.roomSearch,
        reason: '${entry.key}.roomSearch',
      );
      expect(
        actual.anchorSearch,
        wanted.anchorSearch,
        reason: '${entry.key}.anchorSearch',
      );
      expect(actual.danmaku, wanted.danmaku, reason: '${entry.key}.danmaku');
      expect(
        actual.multiQuality,
        wanted.multiQuality,
        reason: '${entry.key}.multiQuality',
      );
      expect(
        actual.multiLine,
        wanted.multiLine,
        reason: '${entry.key}.multiLine',
      );
    }
  });

  test('不支持能力不会伪造接口，IPTV 与 YY 的弹幕入口保持关闭', () {
    final registry = buildSiteRegistry();

    expect(registry['iptv']!.capabilities.danmaku, isFalse);
    expect(registry['iptv']!.danmaku, isNull);
    expect(registry['yy']!.capabilities.danmaku, isFalse);
    expect(registry['yy']!.danmaku, isNull);
    expect(registry['twitch']!.capabilities.multiLine, isFalse);
  });

  test('真实解析入口筛选只能暴露声明 browse 且存在 repository 的平台', () {
    final registry = buildSiteRegistry();
    final visible = registry.supportedSites.where((site) {
      final registration = registry[site]!;
      return registration.capabilities.browse && registration.browse != null;
    }).toSet();

    expect(visible, containsAll(_sites));
    expect(visible, contains('all'));
  });

  test('所有目标平台的同房间号使用独立 room volume key', () {
    final keys = _sites.map((site) => roomVolumeKey(site, '123')).toSet();

    expect(keys, hasLength(_sites.length));
    expect(roomVolumeKey(' douyu ', ' 123 '), roomVolumeKey('douyu', '123'));
  });

  test('平台品牌目录包含所有目标注册平台', () {
    final ids = PlatformBrandCatalog.navPlatforms
        .map((brand) => brand.id)
        .toSet();

    expect(ids, containsAll(_sites));
  });
}
