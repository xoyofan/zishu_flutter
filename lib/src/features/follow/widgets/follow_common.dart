/// 关注条目通用小部件:封面、平台圆点、分类标签、状态点、条目操作按钮。
/// 颜色一律取自 context.tokens,禁止裸色值。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 离线置灰滤镜(灰度矩阵,数值非颜色)。
final ColorFilter kGrayscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// 封面图:cached_network_image 加载,离线时置灰压暗;加载失败回退占位块。
class FollowCoverImage extends StatelessWidget {
  const FollowCoverImage({
    super.key,
    required this.cover,
    required this.fallbackLabel,
    this.width,
    this.height,
    this.offline = false,
  });

  final String cover;
  final String fallbackLabel;
  final double? width;
  final double? height;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    Widget image = cover.isEmpty
        ? _placeholder(context)
        : CachedNetworkImage(
            imageUrl: cover,
            fit: BoxFit.cover,
            width: width,
            height: height,
            placeholder: (_, _) => _placeholder(context),
            errorWidget: (_, _, _) => _placeholder(context),
          );
    if (offline) {
      image = Opacity(
        opacity: 0.6,
        child: ColorFiltered(colorFilter: kGrayscaleFilter, child: image),
      );
    }
    return image;
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: context.tokens.surfaceRaised,
      child: Center(
        child: Text(
          fallbackLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySecondary,
        ),
      ),
    );
  }
}

/// 平台品牌色圆点(未收录平台回退次级文字色)。
class FollowPlatformDot extends StatelessWidget {
  const FollowPlatformDot({super.key, required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: PlatformBrandCatalog.byId(site)?.color ?? context.tokens.textSecondary,
      ),
    );
  }
}

/// 直播状态点:开播红点 / 离线灰点。
class FollowStatusDot extends StatelessWidget {
  const FollowStatusDot({super.key, required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? context.tokens.liveBadge : context.tokens.textSecondary,
      ),
    );
  }
}

/// 分类小标签(raised 底 + caption 字号)。
class FollowCategoryTag extends StatelessWidget {
  const FollowCategoryTag({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      decoration: BoxDecoration(
        color: context.tokens.surfaceRaised,
        borderRadius: AppRadius.allSm,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.caption,
      ),
    );
  }
}

/// 覆盖在封面上的浮层小标签(离线/在线人数/平台名等)。
class FollowCoverTag extends StatelessWidget {
  const FollowCoverTag({
    super.key,
    required this.child,
    this.accent,
  });

  final Widget child;

  /// 可选强调底色(如平台品牌色)。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (accent ?? context.tokens.surfaceSoft).withValues(alpha: 0.88),
        borderRadius: AppRadius.allSm,
      ),
      child: child,
    );
  }
}

/// 条目级小操作按钮(特别关注/提醒/删除),三密度共用。
class FollowIconAction extends StatelessWidget {
  const FollowIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 激活态(金色),如已特别关注/提醒开启。
  final bool active;

  /// 危险操作(删除)用 error 色。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Color color = danger
        ? tokens.error
        : active
            ? tokens.brand
            : tokens.textSecondary;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      icon: Icon(icon, size: 16, color: color),
    );
  }
}
