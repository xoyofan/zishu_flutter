/// 线框 chip:透明底 + `tokens.border` 1px 描边 + `AppRadius.allSm` 圆角 +
/// caption 字号的统一样式组件。
///
/// Stage 2(卡片 chips UI)把三处 chip 形态收敛到这一个组件:
/// - 房间卡元信息行(RoomCard 的游戏 tag / 语言 / promoTag);
/// - 平台分类底部面板与 hover 分类浮层的子分类 chip。
///
/// 约束:
/// - **不新增任何 token/裸值**:只复用 `AppRadius`/`AppSpacing`/`tokens`/
///   `AppFontSize`(DESIGN.md 视觉真源,样式改动先改 DESIGN.md 的顺序不变);
/// - 垂直 padding 恒为 0 —— `Container` 的 border 计入 effectivePadding
///   (`padding + decoration.padding`),11×1.3(caption 行高 14.3)+ 2×1px
///   边框 = 16.3,与改版前「14.3 + 2×1 padding」等高,守住元信息行
///   17px 恒定行高(两行卡片等高契约,见 `room_card_meta_height_test`);
/// - [onTap] 为 null 时不包 `InkWell`:不可点 chip 无 hover/点击反馈,
///   也不会拦截指针(点击自然落到卡片整体 onTap)。
library;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

class OutlineChip extends StatelessWidget {
  const OutlineChip({super.key, required this.label, this.onTap});

  /// 展示文案(已本地化,UI 不再翻译)。
  final String label;

  /// 点击回调;null = 仅展示不可点(如 Twitch 语言 chip、promoTag)。
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final outlined = Container(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      decoration: BoxDecoration(
        border: Border.all(color: tokens.border),
        borderRadius: AppRadius.allSm,
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textCaption.copyWith(fontSize: AppFontSize.caption),
      ),
    );
    final tap = onTap;
    if (tap == null) return outlined;
    // 可点:InkWell 反馈全走 token(与分类浮层 chip、房间卡整体同口径)。
    return InkWell(
      onTap: tap,
      borderRadius: AppRadius.allSm,
      hoverColor: tokens.accent.withValues(
        alpha: AppDirectoryDrawer.activeChipAlpha,
      ),
      splashColor: AppStateLayer.splashOf(tokens.accent),
      highlightColor: AppStateLayer.pressedOf(tokens.accent),
      focusColor: AppStateLayer.focusOf(tokens.accent),
      child: outlined,
    );
  }
}
