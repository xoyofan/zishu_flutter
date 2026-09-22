import 'package:flutter/material.dart';

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

  static const Map<String, Color> _colors = {
    'bilibili': Color(0xFFFB7299),
    'douyin': Color(0xFFFE2C55),
    'douyu': Color(0xFFFF6A00),
    'huya': Color(0xFFFFB800),
    'iptv': Color(0xFF2B7FFF),
    'kuaishou': Color(0xFFFF4906),
    'soop': Color(0xFF00A8FF),
    'twitch': Color(0xFF9146FF),
    'xhs': Color(0xFFFF2442),
    'youtube': Color(0xFFFF0000),
    'yy': Color(0xFFFFD000),
  };

  @override
  Widget build(BuildContext context) {
    if (id == 'all') return _AllPlatformIcon(size: size);

    final asset = _rasterIcons.contains(id)
        ? 'assets/ui/platform-icons/$id.png'
        : null;
    final color = _colors[id] ?? Theme.of(context).colorScheme.primary;
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
                      color: id == 'yy' ? const Color(0xFF1A1A1A) : Colors.white,
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
                        color: Colors.white,
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
