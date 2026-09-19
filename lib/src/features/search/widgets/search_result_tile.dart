import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 单条搜索命中:方形头像 + 昵称/状态点 + 标题 + 分类 chip + 在线人数,
/// 直播中行尾部带「进入直播间」按钮;头像点击进入主播主页。
class SearchResultTile extends StatelessWidget {
  const SearchResultTile({
    super.key,
    required this.hit,
    required this.onRowTap,
    required this.onAnchorTap,
  });

  final SearchHit hit;

  /// 行主体点击(进入直播间 / 未开播提示)。
  final VoidCallback onRowTap;

  /// 头像点击(进入主播主页)。
  final VoidCallback onAnchorTap;

  bool get _isLive => hit.state == SearchHitState.live;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final stateColor = _isLive ? tokens.liveBadge : tokens.textSecondary;
    return InkWell(
      onTap: onRowTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: tokens.border)),
        ),
        child: Row(
          children: [
            _Avatar(hit: hit, onTap: onAnchorTap),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hit.anchor,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textTitle.copyWith(
                            fontSize: 14,
                            color: tokens.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(color: stateColor, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        _isLive ? '直播中' : '未开播',
                        style: context.textCaption.copyWith(color: stateColor),
                      ),
                    ],
                  ),
                  if (hit.title.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        hit.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: context.textSecondary.copyWith(color: tokens.textSecondary),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.xs),
                    child: Row(
                      children: [
                        if (hit.category.isNotEmpty) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: tokens.surfaceRaised,
                              borderRadius: AppRadius.allSm,
                            ),
                            child: Text(
                              hit.category,
                              style: context.textCaption.copyWith(color: tokens.textSecondary),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                        ],
                        if (hit.online.isNotEmpty) ...[
                          Icon(
                            Icons.visibility_rounded,
                            size: 12,
                            color: tokens.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            hit.online,
                            style: context.textCaption.copyWith(color: tokens.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isLive) ...[
              const SizedBox(width: AppSpacing.sm),
              _EnterButton(onTap: onRowTap),
            ],
          ],
        ),
      ),
    );
  }
}

/// 方形头像:CachedNetworkImage,失败/为空时以昵称首字占位。
class _Avatar extends StatelessWidget {
  const _Avatar({required this.hit, required this.onTap});

  final SearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: '查看主播主页',
        child: ClipRRect(
          borderRadius: AppRadius.allSm,
          child: Container(
            width: 40,
            height: 40,
            color: tokens.surfaceRaised,
            child: hit.avatar.isEmpty
                ? _fallback(context)
                : CachedNetworkImage(
                    imageUrl: hit.avatar,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    placeholder: (_, _) => ColoredBox(color: tokens.surfaceRaised),
                    errorWidget: (_, _, _) => _fallback(context),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _fallback(BuildContext context) {
    final tokens = context.tokens;
    return ColoredBox(
      color: tokens.surfaceRaised,
      child: Center(
        child: Text(
          hit.anchor.isEmpty ? '?' : hit.anchor.characters.first,
          style: context.textBody.copyWith(color: tokens.textSecondary),
        ),
      ),
    );
  }
}

/// 「进入直播间」描边按钮:品牌色文字 + 品牌色边框。
class _EnterButton extends StatelessWidget {
  const _EnterButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.allSm,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          borderRadius: AppRadius.allSm,
          border: Border.all(color: tokens.brand),
        ),
        child: Text(
          '进入直播间',
          style: context.textCaption.copyWith(
            color: tokens.brand,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}
