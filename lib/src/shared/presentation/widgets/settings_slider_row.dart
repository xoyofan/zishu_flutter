import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 面板内「标签 + 滑杆 + 数值」行(用户口径 2026-09-20 尺寸全局统一,
/// 走 AppControls:行高 20/轨道 3/圆点 6/标签 11)。
///
/// 滑杆轨道/圆点规格由全局 `sliderTheme`(app_theme.dart)提供,本组件
/// 不再局部包裹 SliderTheme;行高与三列布局(标签固定宽 38 + Expanded
/// 滑杆 + 右对齐数值)在此统一。
///
/// 颜色语义:标签/数值默认随主题(textSecondary / accent);压在视频画面
/// 等恒定暗底上的面板(如控制条飘屏弹幕 popover)传 [onVideo] = true,
/// 标签改用 AppOnVideo.textMuted 恒定亮色,避免浅色主题下暗底不可读。
class SettingsSliderRow extends StatelessWidget {
  const SettingsSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.display,
    required this.onChanged,
    this.width = 216,
    this.onVideo = false,
  });

  /// 行首标签(如「透明度」)。
  final String label;

  /// 滑杆当前值。
  final double value;
  final double min;
  final double max;

  /// 刻度数。
  final int divisions;

  /// 行尾数值文案(如「50%」「20」)。
  final String display;

  /// 拖动回调。
  final ValueChanged<double> onChanged;

  /// 行宽;null = 不限宽(侧栏面板内随宿主拉伸),默认 216(视频控制条
  /// popover 面板行宽)。
  final double? width;

  /// 宿主是否恒定暗底(on-video):true 时标签用 AppOnVideo.textMuted。
  final bool onVideo;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: AppControls.labelFontSize,
      color: onVideo ? AppOnVideo.textMuted : context.tokens.textSecondary,
    );
    final row = Row(
      children: [
        SizedBox(width: _kLabelWidth, child: Text(label, style: labelStyle)),
        Expanded(
          // 紧凑行高(默认 M3 触摸目标 ~48px 会把每行撑到两倍)。
          child: SizedBox(
            height: AppControls.sliderRowHeight,
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              activeColor: context.tokens.accent,
              onChanged: onChanged,
            ),
          ),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: _kValueWidth,
          child: Text(
            display,
            textAlign: TextAlign.end,
            style: TextStyle(
              fontSize: AppFontSize.caption,
              fontFeatures: const [FontFeature.tabularFigures()],
              color: context.tokens.accent,
            ),
          ),
        ),
      ],
    );
    if (width == null) return row;
    return SizedBox(width: width, child: row);
  }
}

/// 行首 label 固定宽(px),对齐 web `2.4rem` ≈ 38px。
const double _kLabelWidth = 38;

/// 行尾数值列宽(容纳「100%」并右对齐)。
const double _kValueWidth = 30;
