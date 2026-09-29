import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';

/// A11 导航能力过滤:`navigationPlatforms` / `browsePlatforms` 在真实解析
/// 模式下必须只含「注册表可分类浏览」的站点,否则入口点击会在
/// `ParserBrowseSource.fetchCategories` 抛 `StateError('站点 X 不支持分类浏览')`。
void main() {
  final registry = buildSiteRegistry();

  bool browseable(SiteRegistration registration) =>
      registration.capabilities.browse && registration.browse != null;

  test('真实解析模式:过滤结果每站都可分类浏览,不触发 StateError', () {
    final platforms = PlatformBrandCatalog.filterPlatforms(
      registry: registry,
      realParser: true,
      supported: browseable,
    );

    expect(platforms.first.id, 'all');
    for (final brand in platforms.where((b) => b.id != 'all')) {
      final registration = registry[brand.id];
      expect(
        registration,
        isNotNull,
        reason: '${brand.id} 出现在导航但注册表缺失 → 点击将抛 StateError',
      );
      expect(
        registration!.capabilities.browse && registration.browse != null,
        isTrue,
        reason: '$brand 无分类浏览能力 → 不得进入导航',
      );
    }
  });

  test('真实解析模式:已注册十站全部保留(含 xhs),未注册平台被剔除', () {
    final platforms = PlatformBrandCatalog.filterPlatforms(
      registry: registry,
      realParser: true,
      supported: browseable,
    );
    final ids = platforms.map((b) => b.id).toList();

    expect(ids, containsAll(<String>[
      'douyu',
      'huya',
      'bilibili',
      'douyin',
      'kuaishou',
      'yy',
      'twitch',
      'soop',
      'xhs',
      'youtube',
    ]));
    // xhs 已接入(buildXhsRegistration,browse 能力),真实解析下是合法入口。
    expect(ids, contains('xhs'));
    // 移除的平台不得复活。
    expect(ids, isNot(contains('iptv')));
    expect(ids, isNot(contains('cc')));
  });

  test('fixture 模式:保留全量品牌目录(离线 UI 测试不漂移)', () {
    final platforms = PlatformBrandCatalog.filterPlatforms(
      registry: registry,
      realParser: false,
      supported: browseable,
    );
    expect(platforms, PlatformBrandCatalog.navPlatforms);
  });

  test('navigationPlatforms 与 browsePlatforms 同源(入口/分类页一致)', () {
    expect(
      PlatformBrandCatalog.navigationPlatforms.map((b) => b.id),
      PlatformBrandCatalog.browsePlatforms.map((b) => b.id),
    );
  });
}
