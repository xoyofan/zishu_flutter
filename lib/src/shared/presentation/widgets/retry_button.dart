import 'package:flutter/material.dart';

import '../zishu_tokens.dart';

/// 重试按钮形态:[text] = 文字按钮(列表/网格错误占位区),
/// [outlined] = 描边按钮(播放错误浮层卡片)。
enum RetryButtonVariant { text, outlined }

/// 统一「重试」按钮:收敛 home/category/play_view 等错误占位处
/// 几乎相同的刷新图标 + 「重试」文案组合。前景一律 tokens.accent;
/// outlined 态描边为 accent 60%(对齐 play_view 原样式)。
///
/// 仅收敛「错误重试」语义;「刷新列表」「导航入口」等非重试按钮
/// 不复用本组件(语义不同,图标会误导)。
class RetryButton extends StatelessWidget {
  const RetryButton({
    super.key,
    required this.onRetry,
    this.label = '重试',
    this.variant = RetryButtonVariant.text,
  });

  /// 点击重试。
  final VoidCallback onRetry;

  /// 按钮文案,默认「重试」。
  final String label;

  /// 形态,默认文字按钮。
  final RetryButtonVariant variant;

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.accent;
    return switch (variant) {
      RetryButtonVariant.text => TextButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded),
        label: Text(label),
        style: TextButton.styleFrom(foregroundColor: accent),
      ),
      RetryButtonVariant.outlined => OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.6)),
        ),
      ),
    };
  }
}
