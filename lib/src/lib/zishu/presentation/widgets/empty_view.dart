import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 通用空态占位:居中图标 + 提示文案 + 可选操作按钮。
class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  /// 空态提示文案。
  final String message;

  /// 空态图标。
  final IconData icon;

  /// 可选操作区(如「去关注」按钮)。
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      // mainAxisSize.min 让占位宽度自适应内容
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.md),
            decoration: BoxDecoration(
              color: tokens.surfaceRaised,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 28, color: tokens.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          if (action != null) ...[
            const SizedBox(height: AppSpacing.lg),
            action!,
          ],
        ],
      ),
    );
  }
}
