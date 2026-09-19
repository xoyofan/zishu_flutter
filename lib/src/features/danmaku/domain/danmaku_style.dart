import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'package:live_parser/live_parser.dart' show DanmakuMessage;

/// 弹幕视觉归一:颜色归一、描边、富文本(用户名 + 正文)构建。
///
/// 本文件只依赖 `dart:ui` / `material` 与解析包的 [DanmakuMessage],
/// 不引入任何新的 pub 依赖,也不依赖播放器,便于在 VM 单测中直接构造。
abstract final class DanmakuStyle {
  /// 默认弹幕色:`DanmakuMessage.color == 0` 时使用。
  ///
  /// 取纯白而非 AppColors.textPrimary(0xDEFFFFFF)——弹幕叠在任意视频
  /// 画面上,半透明文字在亮背景上会糊掉;描边负责可读性,填充必须不透明。
  static const Color defaultTextColor = Color(0xFFFFFFFF);

  /// 正文描边色:黑色半透明,保证亮色视频上仍可读。
  static const Color strokeColor = Color(0xCC000000);

  /// 用户名描边色(与正文同款,保证两段样式视觉一致)。
  static const Color userNameStrokeColor = Color(0xCC000000);

  /// 用户名基础色(未被 [DanmakuStyle.resolveColor] 覆盖时的回退)。
  static const Color userNameFallbackColor = Color(0xFFFFD666);

  /// 默认字号(pt)。固定字号而非随画布缩放:弹幕可读性优先,宽度只驱动滚动速度。
  ///
  /// 也是 [buildSpan] / [_buildParagraph] 的可选 [fontSize] 入参默认值,与
  /// overlay 默认入参同源,保证未注入设置时渲染与历史一致。
  static const double fontSize = 20;

  /// 用户名相对正文字号的缩放(用户名略小,视觉上从属于正文)。
  static const double userNameScale = 0.9;

  /// 行高(默认字号下单行占位高度,单位 px)。
  ///
  /// 公式对齐 web `DanmakuOverlay.vue` 的 `trackHeightFor`:
  /// `fontSize * 1.52 + 6`(20px → 36.4)。web 侧做了 `Math.ceil`,
  /// 这里保留 double 精度做轨道间距,视觉一致且不损失小屏精度。
  static const double lineHeight = fontSize * 1.52 + 6;

  /// 给定字号下的行高(px)。A3 字号设置生效时据此换算轨道间距。
  static double lineHeightOf(double fontSize) => fontSize * 1.52 + 6;

  /// 颜色归一:
  /// - `color == 0`(含越界值)→ [defaultTextColor];
  /// - 否则按 `0xRRGGBB` 解析为不透明 [Color]。
  ///
  /// 注意 `0xRRGGBB` 不含 alpha,必须补 `0xFF000000`,否则 RGB 与 ARGB
  /// 位序错位会得到透明/错误颜色。
  static Color resolveColor(int color) {
    if (color == 0) return defaultTextColor;
    return Color(0xFF000000 | (color & 0xFFFFFF));
  }

  /// 用户名稳定着色(hash → HSL):当消息本身颜色为默认值时,用户名用
  /// hash 色相区分不同发言者;消息指定了颜色则整体统一用消息色。
  static Color resolveUserNameColor(DanmakuMessage message) {
    if (message.color != 0) return resolveColor(message.color);
    if (message.userName.isEmpty) return userNameFallbackColor;
    var hash = 0;
    for (final unit in message.userName.codeUnits) {
      hash = (hash * 31 + unit) % 360;
    }
    return HSLColor.fromAHSL(1, hash.toDouble(), 0.6, 0.72).toColor();
  }

  /// 构建飘屏正文 [TextSpan](纯正文,用户口径 2026-09-19:「飘屏弹幕不用
  /// 显示昵称」,对齐 web DanmakuOverlay 只画正文的语义)。
  ///
  /// [fontSize] 可选,A3 由 [DanmakuOverlay] 注入(默认 [DanmakuStyle.fontSize],
  /// 与历史一致)。
  static TextSpan buildSpan(
    DanmakuMessage message, {
    double fontSize = DanmakuStyle.fontSize,
  }) {
    final bodyColor = resolveColor(message.color);
    return TextSpan(
      text: message.text,
      style: TextStyle(
        color: bodyColor,
        fontSize: fontSize,
        fontWeight: FontWeight.w500,
        height: 1.0,
      ),
    );
  }

  /// 用 [ui.ParagraphBuilder] 按顺序绘制富文本 + 描边。
  ///
  /// 为什么不用 [TextPainter]:`TextPainter` 只能给整段画一种 `TextStyle`
  /// 的描边(`foreground` + `Paint..style = stroke`),无法同时保留
  /// 「用户名有色 + 正文白色」的分段填充色。`ParagraphBuilder` 逐段
  /// `pushStyle` 天然支持分段,描边做法是「每段先 stroke 后 fill,两遍布局」:
  /// 先按描边样式布局一遍生成描边段落,再按填充样式布局一遍,依次绘制。
  static void paintRichText(
    ui.Canvas canvas,
    TextSpan span, {
    required Offset offset,
  }) {
    final strokePainter = _buildParagraph(span, stroke: true);
    strokePainter.layout(ui.ParagraphConstraints(width: double.infinity));
    canvas.drawParagraph(strokePainter, offset);

    final fillPainter = _buildParagraph(span, stroke: false);
    fillPainter.layout(ui.ParagraphConstraints(width: double.infinity));
    canvas.drawParagraph(fillPainter, offset);
  }

  /// 测量富文本实际宽度(px),用于轨道分配判定弹幕长度。
  static double measureWidth(TextSpan span) {
    final painter = _buildParagraph(span, stroke: false);
    painter.layout(ui.ParagraphConstraints(width: double.infinity));
    return painter.maxIntrinsicWidth;
  }

  ///
  /// 同时兼容两种 span 形态:
  /// - 单段纯正文([buildSpan] 当前口径:根 span 自带 `text`,无 children);
  /// - 旧两段富文本(根 span 无 text,`children` 里是用户名 + 正文)。
  /// 忽略根 `text` 会导致单段弹幕整条空白(ParagraphBuilder 零字符),
  /// 因此先写入根 span 自身 text,再递归写入 children。
  static ui.Paragraph _buildParagraph(
    TextSpan span, {
    required bool stroke,
    double fontSize = DanmakuStyle.fontSize,
  }) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textDirection: TextDirection.ltr,
        fontSize: fontSize,
        maxLines: 1,
      ),
    );

    void addSpanText(TextSpan node) {
      final base = node.style ?? const TextStyle();
      if (node.text != null && node.text!.isNotEmpty) {
        if (stroke) {
          builder.pushStyle(
            ui.TextStyle(
              fontSize: base.fontSize,
              fontWeight: base.fontWeight,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2
                ..color = strokeColor,
            ),
          );
        } else {
          builder.pushStyle(
            ui.TextStyle(
              fontSize: base.fontSize,
              fontWeight: base.fontWeight,
              color: base.color,
            ),
          );
        }
        builder.addText(node.text!);
        builder.pop();
      }
      for (final child in node.children ?? const <InlineSpan>[]) {
        addSpanText(child as TextSpan);
      }
    }

    addSpanText(span);
    return builder.build();
  }
}
