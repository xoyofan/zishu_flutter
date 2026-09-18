/// 封面「四象限」角标:SFVideoLive 卡片封面信息密度的唯一真源。
///
/// 参考实现:`components/browse/CoverBadges.vue`(平台/热度/促销三枚绝对定位角标)
/// 与各卡 CSS(`.room-card__badge--category`、`.room-card__foot-left`、
/// `.follow-preview-cat`)。
///
/// 几何口径(逐条对齐,勿凭观感调整):
/// - 角标**紧贴所在角**,只把**朝向封面内部**的那一个角做成 8px 圆角
///   (左上 `border-radius: 0 0 8px 0`、右上 `0 0 0 8px`、左下 `0 8px 0 0`、
///   右下 `8px 0 0 0`);
/// - 文字 10.5px / 粗体;内边距水平 7px、垂直 3px(web `.26~.28rem .48~.5rem`);
/// - 颜色全部走 tokens / 平台品牌色,禁止裸色值。
///
/// 首页网格卡与播放页侧栏预览卡共用本套角标,避免两处各写一份导致角位漂移。
library;

import 'package:flutter/material.dart';

import '../category_colors.dart';
import '../design_tokens.dart';
import '../platform_brands.dart';
import '../zishu_tokens.dart';
import '../../domain/category_display.dart';

/// 角标所处角位。
enum CoverCorner { topLeft, topRight, bottomLeft, bottomRight }

/// 贴角徽章容器:负责圆角、内边距与默认文字样式。
class CoverBadge extends StatelessWidget {
  const CoverBadge({
    super.key,
    required this.corner,
    required this.child,
    this.background,
    this.foreground,
  });

  /// 朝向封面内部的圆角半径(对齐 web 的 8px)。
  static const double innerRadius = 8;

  /// 角标字号(web `.74rem` @16px 基准 ≈ 11.8,这里按既有卡片基线取 10.5)。
  static const double fontSize = 10.5;

  /// 角标内边距(web `.26rem .48rem` ≈ 4.2 × 7.7)。
  static const EdgeInsets padding = EdgeInsets.symmetric(
    horizontal: 7,
    vertical: 3,
  );

  final CoverCorner corner;
  final Widget child;
  final Color? background;
  final Color? foreground;

  /// 只保留朝向封面内部的那个圆角。
  static BorderRadius radiusFor(CoverCorner corner) => switch (corner) {
    CoverCorner.topLeft => const BorderRadius.only(
      bottomRight: Radius.circular(innerRadius),
    ),
    CoverCorner.topRight => const BorderRadius.only(
      bottomLeft: Radius.circular(innerRadius),
    ),
    CoverCorner.bottomLeft => const BorderRadius.only(
      topRight: Radius.circular(innerRadius),
    ),
    CoverCorner.bottomRight => const BorderRadius.only(
      topLeft: Radius.circular(innerRadius),
    ),
  };

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background ?? tokens.coverScrim,
        borderRadius: radiusFor(corner),
      ),
      child: Padding(
        padding: padding,
        child: DefaultTextStyle.merge(
          style: AppTypography.caption.copyWith(
            fontSize: fontSize,
            height: 1.15,
            fontWeight: FontWeight.w700,
            color: foreground ?? tokens.coverScrimText,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 分类角标:底色/文字色由 [CategoryColors] 计算;未命中配色时不渲染。
class CoverCategoryBadge extends StatelessWidget {
  const CoverCategoryBadge({
    super.key,
    required this.corner,
    required this.category,
    this.site = '',
    this.cid = '',
  });

  final CoverCorner corner;
  final String category;
  final String site;
  final String cid;

  @override
  Widget build(BuildContext context) {
    if (category.trim().isEmpty) return const SizedBox.shrink();
    // 跨平台统一中文分类名:命中映射用 canonical 名,否则回落平台原名。
    final display = displayCategoryName(site, category, cid);
    final style = CategoryColors.opaqueFor(
      category: category,
      site: site,
      cid: cid,
    );
    if (style == null) return const SizedBox.shrink();
    return CoverBadge(
      corner: corner,
      background: style.background,
      foreground: style.foreground,
      child: Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 平台角标:平台品牌色底 + 该平台约定的前景色(`chipForeground`)。
class CoverPlatformBadge extends StatelessWidget {
  const CoverPlatformBadge({super.key, required this.corner, required this.site});

  final CoverCorner corner;
  final String site;

  @override
  Widget build(BuildContext context) {
    final brand = PlatformBrandCatalog.byId(site);
    if (brand == null) return const SizedBox.shrink();
    return CoverBadge(
      corner: corner,
      background: brand.color,
      foreground: brand.chipForeground,
      child: Text(brand.name, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}

/// 热度角标:仅开播且有数值时渲染(对齐 `CoverOnlineBadge` 的 `live` 判据)。
class CoverOnlineBadge extends StatelessWidget {
  const CoverOnlineBadge({
    super.key,
    required this.corner,
    required this.online,
    this.live = true,
  });

  final CoverCorner corner;
  final String online;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final text = online.trim();
    if (!live || text.isEmpty || text == '—' || text == '-') {
      return const SizedBox.shrink();
    }
    return CoverBadge(
      corner: corner,
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        // 数值等宽,避免同一列卡片上的热度角标宽度跳动。
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
    );
  }
}

/// 促销/画质角标(web `CoverPromoBadge`):琥珀底、超长截断到 [maxLen] 字。
class CoverPromoBadge extends StatelessWidget {
  const CoverPromoBadge({super.key, required this.corner, required this.text, this.maxLen = 6});

  final CoverCorner corner;
  final String text;
  final int maxLen;

  @override
  Widget build(BuildContext context) {
    final full = text.trim();
    if (full.isEmpty) return const SizedBox.shrink();
    final chars = full.characters;
    final display = chars.length <= maxLen
        ? full
        : chars.take(maxLen).toString();
    return CoverBadge(
      corner: corner,
      background: context.tokens.promoBadge,
      child: Text(display, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }
}
