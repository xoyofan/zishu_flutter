import 'package:flutter/material.dart';

import '../design_tokens.dart';
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
///
/// **状态补齐(2026-09-21 交互反馈轨 A)**:hover / pressed / focus 三态改为
/// 显式 token 取值,不再依赖 M3 默认 state layer(见 [_overlay]
/// ——前者不可控且与显式 `hoverColor` 的其它调用点互相打架)。
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
        // `styleFrom` 的 `overlayColor` 只收 `Color?`(内部再展开成 state layer),
        // 要逐态取值得用 `copyWith`(收 `WidgetStateProperty`)。
        style: TextButton.styleFrom(foregroundColor: accent)
            .copyWith(overlayColor: _overlay(context)),
      ),
      RetryButtonVariant.outlined => OutlinedButton.icon(
        onPressed: onRetry,
        icon: const Icon(Icons.refresh_rounded, size: 16),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: accent,
          side: BorderSide(color: accent.withValues(alpha: 0.6)),
        ).copyWith(overlayColor: _overlay(context)),
      ),
    };
  }
}

/// hover / pressed / focus 的叠色。全部取自既有 token,不新增色值:
/// - hover = accent 12%(`AppDirectoryDrawer.activeChipAlpha` 同档);
/// - pressed = accent 24%(`AppFocus.ring` 外层光晕已登记的不透明度,
///   在 hover 基础上再压一档,DESIGN.md §4.2);
/// - focus = `surfaceRaised`(DESIGN.md §4.2 抬升档)。
WidgetStateProperty<Color?> _overlay(BuildContext context) {
  final accent = context.tokens.accent;
  final raised = context.tokens.surfaceRaised;
  // 环光晕档:直接取 token 算出的色,避免复制 0.24 这个数值。
  final pressed = AppFocus.ring(accent).first.color;
  return WidgetStateProperty.resolveWith((states) {
    if (states.contains(WidgetState.pressed)) return pressed;
    if (states.contains(WidgetState.focused)) return raised;
    if (states.contains(WidgetState.hovered)) {
      return accent.withValues(alpha: AppDirectoryDrawer.activeChipAlpha);
    }
    return null;
  });
}
