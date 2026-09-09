import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 区块标题：左侧 4px 品牌色竖条 accent + 左对齐标题(可选副标题)，
/// 右侧可挂 trailing 操作区。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  /// 区块标题文案。
  final String title;

  /// 可选副标题。
  final String? subtitle;

  /// 右侧操作区(如「查看更多」)。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return IntrinsicHeight(
      child: Row(
        // stretch 让品牌色竖条贯穿整行高度
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 4,
            decoration: BoxDecoration(
              color: tokens.brand,
              borderRadius: BorderRadius.circular(AppRadius.sm / 2),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.title.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    subtitle!,
                    style: AppTypography.bodySecondary.copyWith(
                      color: tokens.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.md),
            // Center 避免 trailing 被 stretch 拉伸到整行高
            Center(child: trailing!),
          ],
        ],
      ),
    );
  }
}
