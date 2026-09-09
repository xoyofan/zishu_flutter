import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import 'room_card.dart';

/// 自适应房间网格:对齐 SFVideoLive `repeat(auto-fill, minmax(240px, 1fr))`。
/// 支持滚动接近底部时触发 [onLoadMore](由调用方的 controller 防重入),
/// [hasMore] 为 true 时在末尾渲染加载指示 footer。
class RoomGrid extends StatefulWidget {
  const RoomGrid({
    super.key,
    required this.rooms,
    this.onRoomTap,
    this.maxCardWidth = 280,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.hasMore = false,
    this.onLoadMore,
    this.showPlatformBadge = true,
  });

  final List<RoomSummary> rooms;
  final void Function(RoomSummary room)? onRoomTap;
  final double maxCardWidth;
  final EdgeInsetsGeometry padding;

  /// 是否还有下一页;true 时网格末尾显示加载 footer。
  final bool hasMore;

  /// 滚动接近底部时触发(接近底部阈值内部固定)。
  final VoidCallback? onLoadMore;

  /// 是否显示平台角标(跨站聚合网格为 true)。
  final bool showPlatformBadge;

  @override
  State<RoomGrid> createState() => _RoomGridState();
}

class _RoomGridState extends State<RoomGrid> {
  final ScrollController _controller = ScrollController();

  /// 接近底部该距离内即触发加载更多。
  static const double _loadMoreThreshold = 400;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  @override
  void dispose() {
    _controller.removeListener(_onScroll);
    _controller.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!widget.hasMore || widget.onLoadMore == null) return;
    if (_controller.position.extentAfter < _loadMoreThreshold) {
      widget.onLoadMore!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rooms = widget.rooms;
    final footerCount = widget.hasMore ? 1 : 0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = math.max(1, (width / widget.maxCardWidth).floor());
        // 卡片实际宽 = 内容宽均分(扣间距),卡高比例必须按实际宽算;
        // 用 maxCardWidth 会在列数>1 或内容区窄于 maxCardWidth 时令文本区溢出。
        final cardWidth =
            (width - AppSpacing.md * (columns - 1)) / columns;
        return GridView.builder(
          controller: _controller,
          padding: widget.padding,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: AppSpacing.md,
            crossAxisSpacing: AppSpacing.md,
            // 80 = 文本区预算(标题 18.9 + 间距 8 + 主播行 16.8 + padding 24 = 67.7)
            // + 12px 余量,覆盖测试字体(Ahem)与真实字体的行高差,防止 2~6px 级溢出;
            // 大字体下再按 metaHeightFor 同步放大,避免纵向溢出(W11)。
            childAspectRatio:
                cardWidth / (cardWidth * 9 / 16 + metaHeightFor(80, context)),
          ),
          itemCount: rooms.length + footerCount,
          itemBuilder: (context, index) {
            if (index >= rooms.length) return const _LoadingMoreFooter();
            final room = rooms[index];
            return RoomCard(
              room: room,
              showPlatformBadge: widget.showPlatformBadge,
              onTap: widget.onRoomTap == null
                  ? null
                  : () => widget.onRoomTap!(room),
            );
          },
        );
      },
    );
  }
}

/// 网格末尾的加载中 footer,视觉上与卡片底色区分。
class _LoadingMoreFooter extends StatelessWidget {
  const _LoadingMoreFooter();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      alignment: Alignment.center,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: AppSpacing.lg,
            height: AppSpacing.lg,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: tokens.brand,
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text('加载中…', style: AppTypography.caption),
        ],
      ),
    );
  }
}
