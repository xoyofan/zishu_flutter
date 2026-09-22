import 'package:flutter/material.dart';

import '../platform_brands.dart';

/// SFVideoLive 风格平台图标。
///
/// 优先使用 `assets/ui/platform-icons/` 下的品牌素材；`all` 使用四象限
/// 平台色块绘制，缺少素材的平台使用品牌色文字兜底(例如 YY 的 SVG 素材)。
class PlatformIcon extends StatelessWidget {
  const PlatformIcon({
    super.key,
    required this.id,
    this.size = 28,
  });

  final String id;
  final double size;

  static const Set<String> _rasterIcons = {
    'bilibili',
    'douyin',
    'douyu',
    'huya',
    'iptv',
    'kuaishou',
    'soop',
    'twitch',
    'xhs',
    'youtube',
  };

  static const Map<String, String> _labels = {
    'all': '全',
    'bilibili': '哔',
    'douyin': '抖',
    'douyu': '斗',
    'huya': '虎',
    'iptv': 'TV',
    'kuaishou': '快',
    'soop': 'S',
    'twitch': 'T',
    'xhs': '红',
    'youtube': '▶',
    'yy': 'YY',
  };

  /// 兜底字形的品牌色:取自 [PlatformBrandCatalog](平台色表的**唯一真源**),
  /// 本文件不再复制一份色值(此前与真源重复定义,含 YY 的 `#FFD000`)。
  static final Map<String, Color> _colors = {
    for (final brand in PlatformBrandCatalog.navPlatforms)
      brand.id: brand.color,
  };

  @override
  Widget build(BuildContext context) {
    if (id == 'all') return _AllPlatformIcon(size: size);

    final asset = _rasterIcons.contains(id)
        ? 'assets/ui/platform-icons/$id.png'
        : null;
    final color = _colors[id] ?? Theme.of(context).colorScheme.primary;
    // 字形前景:平台色表的约定档 —— YY 的黄底用深色字,其余品牌色底用白。
    final glyphColor = id == 'yy'
        ? PlatformBrandCatalog.chipForegroundDark
        : PlatformBrandCatalog.chipForegroundLight;
    final fallback = _labels[id] ?? (id.isEmpty ? '?' : id.substring(0, 1));
    final radius = BorderRadius.circular(size * 0.22);

    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: radius,
        child: asset == null
            ? ColoredBox(
                color: color,
                child: Center(
                  child: Text(
                    fallback,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: TextStyle(
                      color: glyphColor,
                      fontSize: id == 'yy' ? size * 0.36 : size * 0.42, // ignore: design_token 几何比例(字母字形随图标盒缩放),非排版字号档
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                ),
              )
            : Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => ColoredBox(
                  color: color,
                  child: Center(
                    child: Text(
                      fallback,
                      style: TextStyle(
                        color: PlatformBrandCatalog.chipForegroundLight,
                        fontSize: size * 0.42, // ignore: design_token 几何比例(字母字形随图标盒缩放),非排版字号档
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

class _AllPlatformIcon extends StatelessWidget {
  const _AllPlatformIcon({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    const colors = [
      Color(0xFFFF6A00),
      Color(0xFFFFB800),
      Color(0xFF00A1D6),
      Color(0xFFFE2C55),
    ];
    return SizedBox(
      width: size,
      height: size,
      child: Padding(
        padding: EdgeInsets.all(size * 0.08),
        child: GridView.count(
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: size * 0.08,
          mainAxisSpacing: size * 0.08,
          children: [
            for (final color in colors)
              DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(size * 0.12),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
