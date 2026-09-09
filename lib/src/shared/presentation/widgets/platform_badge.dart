import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../platform_brands.dart';
import '../zishu_tokens.dart';

/// 平台角标：小圆角色块 + 平台名。
/// 色值取 PlatformBrandCatalog，未收录的站点回退主题品牌色。
class PlatformBadge extends StatelessWidget {
  const PlatformBadge({
    super.key,
    required this.site,
    this.fontSize = 10,
  });

  /// 平台 id(如 douyu / huya / bilibili)。
  final String site;

  /// 角标字号。
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final brand = PlatformBrandCatalog.byId(site);
    final color = brand?.color ?? context.tokens.brand;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xs / 2,
      ),
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.allSm),
      child: Text(
        // 未收录站点直接展示原始 id
        brand?.name ?? site,
        style: TextStyle(
          fontSize: fontSize,
          height: 1,
          fontWeight: FontWeight.w600,
          fontFamily: AppTypography.family,
          // 彩色底上统一黑 87% 保证可读性
          color: Colors.black87,
        ),
      ),
    );
  }
}
