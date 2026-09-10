import 'package:flutter/material.dart';

/// 平台品牌规格:角标、tabs、筛选 chips 共用。
class PlatformBrand {
  const PlatformBrand({
    required this.id,
    required this.name,
    required this.color,
    this.browseSupported = true,
  });

  final String id;
  final String name;
  final Color color;

  /// 该平台是否支持栏目浏览(不支持时展示房间号/URL 直达输入)。
  final bool browseSupported;
}

/// 平台品牌目录:色值、名称与 SFVideoLive 平台目录对齐。
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

  /// SFVideo 的启用平台顺序:全平台 + 支持 browse/crossBrowse 的平台。
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
