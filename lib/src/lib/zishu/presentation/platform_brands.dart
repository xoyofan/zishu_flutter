import 'package:flutter/material.dart';


/// 平台品牌规格:角标、tabs、筛选 chips 共用。
class PlatformBrand {
  const PlatformBrand({
    required this.id,
    required this.name,
    required this.color,
    this.chipForeground = PlatformBrandCatalog.chipForegroundLight,
    this.browseSupported = true,
  });

  final String id;
  final String name;
  /// 平台品牌色。**单一真源**:对齐 web `config/platformCatalog.ts` 的
  /// `PLATFORM_BRAND_COLORS[id].bg`。
  ///
  /// 图标底色、顶栏 tab 描边/光晕、封面角标、侧栏标签都用这一个值 ——
  /// web 也是同一份:启动时 `initPlatformBrandVars()`（main.js:57）把
  /// `info.bg` 内联注入 `--platform-{id}` / `-chip-bg` / `--sidebar-tag-{id}-bg`,
  /// **覆盖** theme.css/main.css 里的静态同名变量。
  ///
  /// 因此 theme.css:12 的 `--platform-bilibili: #00a1d6`（蓝）是**被覆盖的旧值**，
  /// 不是第二个真源：哔哩实渲染色是色表里的 **粉 `#fb7299`**。
  /// 同理斗鱼的静态 `#ff6b00` 也被 `#ff6a00` 覆盖。详见 `DESIGN.md` §2.3。
  final Color color;

  /// 平台色块(pill/chip)上的文字色。
  ///
  /// 不能按背景亮度自动算:参考实现的 chip 前景是**按平台硬编码**的
  /// (`--platform-{id}-chip-fg`,如虎牙黄底用 `#1a1a1a`,斗鱼橙底用 `#fff`),
  /// 自动估算会在橙色上给出深色字,与参考不一致。
  ///
  /// 取值见 [PlatformBrandCatalog.chipForegroundLight] /
  /// [PlatformBrandCatalog.chipForegroundDark]。
  final Color chipForeground;

  /// 该平台是否支持栏目浏览(不支持时展示房间号/URL 直达输入)。
  final bool browseSupported;
}

/// 平台品牌目录:色值、名称与 SFVideoLive 平台目录对齐。
///
/// `navigationPlatforms` / `searchPlatforms` 在真实解析构建中从 live_parser
/// 注册表能力动态裁剪；fixture 构建保留 `navPlatforms` 全量目录。
abstract final class PlatformBrandCatalog {
  /// 亮底平台色块/图标上的**白色**前景(`--platform-{id}-chip-fg: #fff`,
  /// 深底平台的通用默认)。
  ///
  /// 平台数据,不是主题量:压在品牌色上的前景由平台自身决定,深浅主题共用。
  static const Color chipForegroundLight = Color(0xFFFFFFFF);

  /// 亮底平台色块/图标上的**深色**前景(`--platform-huya-chip-fg: #1a1a1a`,
  /// 黄/橙等亮底平台用)。
  ///
  /// YY 的 `#FFD000` 底同样取这一档(见 `PlatformIcon` 的兜底字形)。
  static const Color chipForegroundDark = Color(0xFF1A1A1A);

  static const PlatformBrand all = PlatformBrand(
    id: 'all',
    name: '全平台',
    color: Color(0xFFF3D04E),
    // 「全平台」是品牌金底(亮底),web 无对应条目;按同族亮底的约定用深色字
    // (与 yy / huya 同理),不能用默认的白字。
    chipForeground: chipForegroundDark,
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
    chipForeground: chipForegroundDark,
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
    // 对齐 web `platformCatalog.ts` 的 `yy: { bg: "#ffd000", fg: "#1a1a1a" }`
    // (黄底用深色字)。此前漏了这一档,与 platform_icon 的兜底字形取值不一致。
    chipForeground: chipForegroundDark,
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

  static const bool realParserEnabled = bool.fromEnvironment(
    'ZISHU_REAL_PARSER',
    defaultValue: false,
  );

  /// 真实解析模式下按注册表的 browse 能力裁剪导航平台；同时要求实际
  /// 注册了 browse repository，避免「声明能力但不可用」的平台
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
  ) => filterPlatforms(
    registry: buildSiteRegistry(),
    realParser: realParserEnabled,
    supported: supported,
  );

  /// 纯过滤逻辑(A11,可测):
  ///
  /// - `realParser: false`(fixture 构建)原样返回 [navPlatforms] 全量目录;
  /// - `realParser: true` 只保留「品牌支持栏目浏览 && 注册表有该站 &&
  ///   [supported] 能力为真」的站点 —— 保证入口列表里的每一站
  ///   `registration.browse != null`,点击分类不会在
  ///   `ParserBrowseSource.fetchCategories` 抛 `StateError('站点 X 不支持分类浏览')`。
  @visibleForTesting
  static List<PlatformBrand> filterPlatforms({
    required SiteRegistry registry,
    required bool realParser,
    required bool Function(SiteRegistration registration) supported,
  }) {
    if (!realParser) return navPlatforms;
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
  /// 不出现主播档。
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
  ];

  static PlatformBrand? byId(String id) {
    for (final brand in navPlatforms) {
      if (brand.id == id) return brand;
    }
    return null;
  }
}
