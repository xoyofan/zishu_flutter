import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 通用错误占位:居中错误图标 + 错误信息 + 可选重试按钮。
class ErrorView extends StatelessWidget {
  const ErrorView({
    super.key,
    this.message = '加载失败，请稍后重试',
    this.onRetry,
  });

  /// 错误提示文案。
  final String message;

  /// 非空时展示「重试」按钮。
  final VoidCallback? onRetry;

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
            child: Icon(Icons.error_outline, size: 28, color: tokens.error),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppTypography.bodySecondary.copyWith(
              color: tokens.textSecondary,
            ),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: AppSpacing.lg),
            FilledButton.tonal(
              onPressed: onRetry,
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}
