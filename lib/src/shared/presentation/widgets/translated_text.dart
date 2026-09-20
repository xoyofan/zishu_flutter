/// 自动中文化文本组件:标题类单行文本的统一翻译挂接点。
///
/// 原文先渲染,译文到达后原位替换;关闭翻译(设置)/文本已是中文/
/// 翻译失败时恒显示原文,组件与调用方都无需关心状态。
/// 弹幕正文不走本组件(富文本段),直接消费 `translatedTextProvider`。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/translation/translation_provider.dart';

class TranslatedText extends ConsumerWidget {
  const TranslatedText(
    this.text, {
    super.key,
    this.style,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.semanticsLabel,
    this.textAlign,
    this.translateName = false,
  });

  final String text;

  final TextStyle? style;
  final int? maxLines;
  final TextOverflow overflow;
  final String? semanticsLabel;
  final TextAlign? textAlign;

  /// 主播名模式:仅韩文/日文名翻译,英文与中文名原样(用户口径
  /// 2026-09-20);标题/弹幕正文模式见 [translatedTextProvider]。
  final bool translateName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Riverpod 3:AsyncValue.value 语义即「有值给值,否则 null」。
    final display = ref
        .watch(
          translateName
              ? translatedAnchorNameProvider(text)
              : translatedTextProvider(text),
        )
        .value ??
        text;
    return Text(
      display,
      style: style,
      maxLines: maxLines,
      overflow: overflow,
      semanticsLabel: semanticsLabel,
      textAlign: textAlign,
    );
  }
}
