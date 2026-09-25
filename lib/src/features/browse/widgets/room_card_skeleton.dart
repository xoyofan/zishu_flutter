import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// RoomGrid 卡片单元的「元信息区」高度预算(与 room_grid.dart 的
/// `metaHeightFor(58, context)` 同源:14 padding + ~18.9 标题 + 4 + 17
/// chips 行 ≈ 53.9,取 58 留余量——两行 meta 改版 2026-09)。
///
/// 骨架与区块网格盒高都镜像 RoomGrid 的布局,两处必须与该预算同步修改
/// (真源断言见 room_card_meta_height_test)。
const double roomGridMetaBudget = 58;

/// 骨架卡片:与 [RoomCard] 同构同高(16:9 封面 + 标题行 + chips 行占位,
/// 与两行 meta 同源),数据到达前占位,避免真实卡片挂载时的布局跳动。
///
/// 高度口径必须与 RoomGrid 的单元格预算完全一致:封面 16:9(由
/// Expanded 宽度决定,同真实卡)+ 元信息区 [roomGridMetaBudget]
/// (文字缩放同 `metaHeightFor` 放大)。占位条全部取 token,不新增色值。
class RoomCardSkeleton extends StatelessWidget {
  const RoomCardSkeleton({super.key});

  /// 占位条高度(不承载文字,固定值;真实行高见 RoomCard)。
  static const double _barHeight = 14;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      color: tokens.surface,
      borderRadius: AppRadius.allMd,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 16:9 封面占位(与 RoomCard._Cover 同比例)。
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: tokens.surfaceRaised),
          ),
          // 元信息区:预算与 RoomGrid 单元格一致,骨架行与真实行等高。
          SizedBox(
            height: metaHeightFor(roomGridMetaBudget, context),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SkeletonBar(height: _barHeight, color: tokens.surfaceRaised),
                  const SizedBox(height: AppSpacing.xs),
                  // chip 占位:Row 主轴约束无界,用 Expanded 分帧定宽。
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: _SkeletonBar(
                          height: _barHeight,
                          color: tokens.surfaceRaised,
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        flex: 2,
                        child: _SkeletonBar(
                          height: _barHeight,
                          color: tokens.surfaceRaised,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 单根占位条:占满可用宽(chips 行两根由外层 Expanded 分帧)。
class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({required this.height, required this.color});

  final double height;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      decoration: BoxDecoration(color: color, borderRadius: AppRadius.allSm),
    );
  }
}

/// 区块骨架行:数量 = 当前列数(= 首屏请求条数),几何与 [RoomGrid] 一致
/// (同样的 grid padding 与列间距),数据到达后原位替换为真实网格。
class RoomGridSkeleton extends StatelessWidget {
  const RoomGridSkeleton({super.key, required this.count, required this.site});

  /// 骨架卡片数量(当前列数)。
  final int count;

  /// 所属平台 id(测试锚点区分用)。
  final String site;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Row(
        children: [
          for (var i = 0; i < count; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.gridCrossAxisSpacing),
            Expanded(
              child: RoomCardSkeleton(
                // 测试锚点:断言骨架数量 == 列数、数据到达后消失。
                key: Key('home-section-skeleton-$site-$i'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
