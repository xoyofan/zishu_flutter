import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 卡片「氛围级 hover」包装：translateY(−2px) + [AmbientGlow.cardHover] 外发光
/// （清单 2.1）。
///
/// 收敛纪律：卡片 hover 只在本 widget 实现一处，调用方**不得**自行写
/// `MouseRegion` + `Transform` + 裸 `BoxShadow`（同一效果禁止逐处手写）。
///
/// - 仅响应 hover 轨；focus / pressed 仍由子控件自身的
///   `AppStateLayer` / `AppFocus` 状态层维护，本 widget 不介入、不重复发明按下色。
/// - 卡片常态不添加大面积投影：网格中多卡阴影会增加栅格化与合成成本；
///   发光只在 hover 时出现，避免静止页面持续付出阴影成本。
/// - [glassHairline] 开启时叠 hairline 边框(hover 加亮到 borderHover)——
///   仅无自带边框的卡开启(RoomCard / PlayRoomCard),AnchorLiveCard /
///   FollowEntryCard 各自有边框逻辑,不叠双框。
/// - 进/出时长 [AppMotion.fast]（150ms）+ [AppMotion.curve]；[AmbientMotion.of]
///   的 `reduce_motion` 静态档下降级为零时长直出终态。
/// - 位移发生在子控件**之上**（`AnimatedContainer.transform`），不改变布局尺寸，
///   网格列宽与命中区域不变。
class AmbientCardHover extends StatefulWidget {
  const AmbientCardHover({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.glassHairline = false,
  });

  final Widget child;

  /// 卡片自身圆角：用于让外发光贴合卡片轮廓（不传则按直角矩形投光）。
  final BorderRadius borderRadius;

  /// 是否画薄玻璃 hairline 边框(常态白 9% / hover 白 22%,取自
  /// [AmbientCardGlass])。仅无自带边框的卡开启,避免双框。
  final bool glassHairline;

  @override
  State<AmbientCardHover> createState() => _AmbientCardHoverState();
}

class _AmbientCardHoverState extends State<AmbientCardHover> {
  /// hover 抬升位移（清单 2.1 的精确值 −2px；DESIGN.md §4.2 氛围分支修订条款）。
  static const double _hoverLift = -2;

  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final motion = AmbientMotion.of(context);
    final duration = motion.reduced ? Duration.zero : AppMotion.fast;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: duration,
        curve: AppMotion.curve,
        transform: Matrix4.translationValues(0, _hover ? _hoverLift : 0, 0),
        decoration: BoxDecoration(
          borderRadius: widget.borderRadius,
          border: widget.glassHairline
              ? Border.all(
                  color: _hover
                      ? AmbientCardGlass.borderHover
                      : AmbientCardGlass.border,
                )
              : null,
          boxShadow: _hover ? AmbientGlow.cardHover(tokens.accent) : null,
        ),
        child: widget.child,
      ),
    );
  }
}
