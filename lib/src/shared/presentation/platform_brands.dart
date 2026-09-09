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

/// 平台品牌目录:色值取自 SFVideoLive 平台角标基线。
abstract final class PlatformBrandCatalog {
  static const PlatformBrand all = PlatformBrand(
    id: 'all',
    name: '全平台',
    color: Color(0xFFF3D04E),
  );

  static const PlatformBrand douyu = PlatformBrand(
    id: 'douyu',
    name: '斗鱼',
    color: Color(0xFFFF7700),
  );

  static const PlatformBrand huya = PlatformBrand(
    id: 'huya',
    name: '虎牙',
    color: Color(0xFFFF8800),
  );

  static const PlatformBrand bilibili = PlatformBrand(
    id: 'bilibili',
    name: '哔哩哔哩',
    color: Color(0xFFFB7299),
  );

  static const PlatformBrand douyin = PlatformBrand(
    id: 'douyin',
    name: '抖音',
    color: Color(0xFF161823),
    browseSupported: false,
  );

  static const PlatformBrand twitch = PlatformBrand(
    id: 'twitch',
    name: 'Twitch',
    color: Color(0xFF9146FF),
  );

  /// Windows 首轮导航清单:全平台聚合 + P0/P1 平台。
  static const List<PlatformBrand> navPlatforms = [
    all,
    douyu,
    huya,
    bilibili,
    douyin,
    twitch,
  ];

  static PlatformBrand? byId(String id) {
    for (final brand in navPlatforms) {
      if (brand.id == id) return brand;
    }
    return null;
  }
}
