import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

/// 平台品牌规格:角标、tabs、筛选 chips 共用。
class PlatformBrand {
  const PlatformBrand({
    required this.id,
    required this.name,
    required this.color,
    this.chipForeground = const Color(0xFFFFFFFF),
    this.browseSupported = true,
  });

  final String id;
  final String name;
  final Color color;

  /// 平台色块(pill/chip)上的文字色。
  ///
  /// 不能按背景亮度自动算:参考实现的 chip 前景是**按平台硬编码**的
  /// (`--platform-{id}-chip-fg`,如虎牙黄底用 `#1a1a1a`,斗鱼橙底用 `#fff`),
  /// 自动估算会在橙色上给出深色字,与参考不一致。
  final Color chipForeground;

  /// 该平台是否支持栏目浏览(不支持时展示房间号/URL 直达输入)。
  final bool browseSupported;
}

/// 平台品牌目录:色值、名称与 SFVideoLive 平台目录对齐。
///
/// `navigationPlatforms` / `searchPlatforms` 在真实解析构建中从 live_parser
/// 注册表能力动态裁剪；fixture 构建保留 `navPlatforms` 全量目录。
abstract final class PlatformBrandCatalog {
  static const PlatformBrand all = PlatformBrand(
    id: 'all',
    name: '全平台',
    color: Color(0xFFF3D04E),
  );

  static const PlatformBrand douyu = PlatformBrand(
    id: 'douyu',
    name: '斗鱼',
    color: Color(0xFFFF6A00),
  );

  static const PlatformBrand huya = PlatformBrand(
    id: 'huya',
    name: '虎牙',
    color: Color(0xFFFFB800),
    // 对齐 `--platform-huya-chip-fg: #1a1a1a`(黄底用深色字)。
    chipForeground: Color(0xFF1A1A1A),
  );

  static const PlatformBrand bilibili = PlatformBrand(
    id: 'bilibili',
    name: '哔哩',
    color: Color(0xFFFB7299),
  );

  static const PlatformBrand douyin = PlatformBrand(
    id: 'douyin',
    name: '抖音',
    color: Color(0xFFFE2C55),
    browseSupported: true,
  );

  static const PlatformBrand yy = PlatformBrand(
    id: 'yy',
    name: 'YY',
    color: Color(0xFFFFD000),
  );

  static const PlatformBrand twitch = PlatformBrand(
    id: 'twitch',
    name: 'Twitch',
    color: Color(0xFF9146FF),
  );

  static const PlatformBrand kuaishou = PlatformBrand(
    id: 'kuaishou',
    name: '快手',
    color: Color(0xFFFF4906),
  );

  static const PlatformBrand soop = PlatformBrand(
    id: 'soop',
    name: 'SOOP',
    color: Color(0xFF00A8FF),
  );

  static const PlatformBrand xhs = PlatformBrand(
    id: 'xhs',
    name: '小红书',
    color: Color(0xFFFF2442),
  );

  static const PlatformBrand youtube = PlatformBrand(
    id: 'youtube',
    name: 'YouTube',
    color: Color(0xFFFF0000),
  );

  static const PlatformBrand iptv = PlatformBrand(
    id: 'iptv',
    name: 'IPTV',
    color: Color(0xFF2B7FFF),
  );

  static const bool realParserEnabled = bool.fromEnvironment(
    'ZISHU_REAL_PARSER',
    defaultValue: false,
  );

  /// 真实解析模式下按注册表的 browse 能力裁剪导航平台；同时要求实际
  /// 注册了 browse repository，避免 IPTV 空数据源等「声明能力但不可用」的平台
  /// 出现在入口里。fixture 模式保留完整视觉目录，避免离线 UI 测试漂移。
  static List<PlatformBrand> get browsePlatforms => _platformsWith(
    (registration) =>
        registration.capabilities.browse && registration.browse != null,
  );

  /// 搜索页按注册表的 search 能力裁剪平台筛选项；空实现(例如快手当前的
  /// 占位 search repository)不作为真实搜索入口暴露。
  static List<PlatformBrand> get searchPlatforms => _platformsWith(
    (registration) =>
        (registration.capabilities.roomSearch ||
            registration.capabilities.anchorSearch) &&
        registration.search != null,
  );

  static List<PlatformBrand> _platformsWith(
    bool Function(SiteRegistration registration) supported,
  ) {
    if (!realParserEnabled) return navPlatforms;
    final registry = buildSiteRegistry();
    final result = <PlatformBrand>[all];
    for (final brand in navPlatforms.skip(1)) {
      final registration = registry[brand.id];
      if (brand.browseSupported &&
          registration != null &&
          supported(registration)) {
        result.add(brand);
      }
    }
    return result;
  }

  /// 真实解析构建使用注册表的实际能力;fixture 构建保留完整导航目录。
  static List<PlatformBrand> get navigationPlatforms => _platformsWith(
    (registration) =>
        registration.capabilities.browse && registration.browse != null,
  );

  static bool supportsBrowse(String site) =>
      browsePlatforms.any((brand) => brand.id == site);

  static bool supportsSearch(String site) =>
      searchPlatforms.any((brand) => brand.id == site);

  /// 平台是否支持**主播**搜索(昵称 / 抖音号),对齐 web
  /// `SearchDialog.vue:207` 的 `supportsAnchorSearch(site)`。
  ///
  /// 用于搜索弹框的「主播 / 房间」双档显隐:只支持房间搜索的平台
  /// (如 IPTV)不出现主播档。
  static bool supportsAnchorSearch(String site) =>
      _capabilitySearch(site, (c) => c.anchorSearch);

  /// 平台是否支持**房间**搜索(房间名 / 标题 / 房间号),对齐 web
  /// `SearchDialog.vue:208` 的 `supportsRoomSearch(site)`。
  static bool supportsRoomSearch(String site) =>
      _capabilitySearch(site, (c) => c.roomSearch);

  /// 按能力位 + 是否注册了真实 search repository 判定。
  ///
  /// fixture 构建(离线 UI 测试)下与 [supportsSearch] 同口径放行:fixture
  /// 目录没有真实注册表,若此处收紧会让双档在测试里整块消失,失去覆盖。
  static bool _capabilitySearch(
    String site,
    bool Function(SiteCapabilities capabilities) test,
  ) {
    if (!realParserEnabled) return supportsSearch(site);
    final registration = buildSiteRegistry()[site];
    if (registration == null || registration.search == null) return false;
    return test(registration.capabilities);
  }

  /// CC 已停运,不加入导航;保留在 parser 层但不作为 UI 入口。
  static const List<PlatformBrand> navPlatforms = [
    all,
    douyu,
    huya,
    bilibili,
    douyin,
    yy,
    twitch,
    kuaishou,
    soop,
    xhs,
    youtube,
    iptv,
  ];

  static PlatformBrand? byId(String id) {
    for (final brand in navPlatforms) {
      if (brand.id == id) return brand;
    }
    return null;
  }
}
