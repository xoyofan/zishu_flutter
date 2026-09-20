/// 关注列表空态:图标 + 文案 + 可选「去逛逛」入口。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

class FollowEmptyState extends StatelessWidget {
  const FollowEmptyState({super.key, this.onBrowse});

  /// 点击「去逛逛」(跳首页)。
  final VoidCallback? onBrowse;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.favorite_border_rounded, size: 44, color: tokens.textSecondary),
          const SizedBox(height: AppSpacing.md),
          Text('暂无关注', style: context.textTitle),
          const SizedBox(height: AppSpacing.xs),
          Text('筛选条件下没有可显示的关注,去首页看看吧', style: context.textSecondary),
          if (onBrowse != null) ...[
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onBrowse,
              style: OutlinedButton.styleFrom(
                foregroundColor: tokens.accent,
                side: BorderSide(color: tokens.border),
                shape: RoundedRectangleBorder(borderRadius: AppRadius.allSm),
              ),
              child: const Text('去逛逛'),
            ),
          ],
        ],
      ),
    );
  }
}
