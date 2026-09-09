import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 网络封面:加载中/失败均回退到 surfaceRaised 占位,不出现破图与裸色值。
class NetworkCover extends StatelessWidget {
  const NetworkCover({
    super.key,
    required this.url,
    this.fallbackLabel = '',
    this.fit = BoxFit.cover,
  });

  final String url;
  final String fallbackLabel;
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    if (url.isEmpty) {
      return _CoverFallback(label: fallbackLabel);
    }
    return ColoredBox(
      color: tokens.surfaceRaised,
      child: CachedNetworkImage(
        imageUrl: url,
        fit: fit,
        fadeInDuration: AppMotion.normal,
        placeholder: (_, _) => const SizedBox.expand(),
        errorWidget: (_, _, _) => _CoverFallback(label: fallbackLabel),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: context.tokens.surfaceRaised,
      child: Center(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTypography.bodySecondary,
        ),
      ),
    );
  }
}
