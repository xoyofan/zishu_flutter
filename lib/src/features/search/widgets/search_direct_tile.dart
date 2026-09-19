import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/search_provider.dart';

/// 快捷直达高亮项:纯数字显示「进入房间 N」,douyu 链接显示「打开链接」。
class SearchDirectTile extends StatelessWidget {
  const SearchDirectTile({super.key, required this.target, required this.onTap});

  final DirectTarget target;
  final VoidCallback onTap;

  bool get _isLink => target.kind == DirectKind.link;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.brand.withValues(alpha: 0.12),
      borderRadius: AppRadius.allMd,
      child: InkWell(
        borderRadius: AppRadius.allMd,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.md,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadius.allMd,
            border: Border.all(color: tokens.brand.withValues(alpha: 0.6)),
          ),
          child: Row(
            children: [
              Icon(
                _isLink ? Icons.link_rounded : Icons.meeting_room_rounded,
                size: 18,
                color: tokens.brand,
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _isLink ? '打开链接' : '进入房间 ${target.roomId}',
                      style: context.textBody.copyWith(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (_isLink && (target.url?.isNotEmpty ?? false))
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          target.url!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: context.textCaption.copyWith(color: tokens.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, size: 12, color: tokens.brand),
            ],
          ),
        ),
      ),
    );
  }
}
