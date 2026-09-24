/// 播放页侧栏「相关推荐」面板:跨平台交错网格 + 滚动加载。
///
/// 数据与规则全在 [playRecommendProvider](见
/// `features/play/application/play_recommend_provider.dart`);本文件只负责呈现:
/// - 无标题(用户口径 2026-09-19)+ 兜底提示行 + 2 列封面网格;
/// - 首屏加载渲染灰底骨架卡(每站 [kRecommendPerSite] 个);
/// - 滚到底部自动追加下一页(「加载更多…」/「没有更多了」)。
///
/// 网格几何与 `play_room_grid.dart::PlayRoomGrid` 保持一致(2 列、间距
/// `AppSpacing.sm`、卡片高 = 16:9 封面 + 36dp 元信息区),卡片本体直接复用
/// 公开的 [PlayRoomCard];这里自建 Sliver 网格的原因只有一个——骨架占位卡
/// 不是 [RoomRecord],`PlayRoomGrid` 表达不了。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/play_recommend_provider.dart';
import 'play_room_grid.dart';

/// 侧栏推荐面板。
class PlayRecommendPanel extends ConsumerStatefulWidget {
  const PlayRecommendPanel({
    super.key,
    required this.site,
    required this.roomId,
    required this.cid,
    required this.category,
    required this.onTap,
  });

  /// 当前房间平台。
  final String site;

  /// 当前房间号(推荐里要剔除它自己)。
  final String roomId;

  /// 当前房间分类 id(可空串)。
  final String cid;

  /// 当前房间分类名(可空串;跨平台映射按它匹配)。
  final String category;

  /// 点推荐房:切房回调由播放页提供(保持它既有的 pushReplacement 语义)。
  final void Function(RoomRecord room) onTap;

  @override
  ConsumerState<PlayRecommendPanel> createState() => _PlayRecommendPanelState();
}

class _PlayRecommendPanelState extends ConsumerState<PlayRecommendPanel> {
  /// 列数:侧栏宽度下 2 列(与参考实现 sidebar 预览网格一致)。
  static const int _columns = 2;

  /// 卡片元信息区(封面下两行文本)高度预算,与 PlayRoomGrid 同值。
  static const double _cardMetaHeight = 36;

  /// 触底阈值:距底部不足这个距离就预取下一页。
  static const double _loadMoreThreshold = 160;

  PlayRecommendArgs get _args => PlayRecommendArgs(
    site: widget.site,
    roomId: widget.roomId,
    cid: widget.cid,
    category: widget.category,
  );

  @override
  void initState() {
    super.initState();
    // 用 microtask 而不是直接调用:loadFirst 会同步落一次 loading 状态,
    // 在 initState 里改 provider 会撞上「widget 树构建中修改 provider」。
    Future<void>.microtask(() {
      if (!mounted) return;
      ref.read(playRecommendProvider(_args).notifier).loadFirst();
    });
  }

  @override
  void didUpdateWidget(PlayRecommendPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.roomId != widget.roomId ||
        oldWidget.cid != widget.cid ||
        oldWidget.category != widget.category) {
      // 与 initState 同理:didUpdateWidget 发生在父层构建期,同步改 provider
      // 会撞「Tried to modify a provider while the widget tree was building」。
      // 真实播放页正是这条路径 —— 首帧 payload 为空,payload 到达后 cid/category
      // 变化触发重载(实测 A10 用例在此抛错)。
      Future<void>.microtask(() {
        if (!mounted) return;
        ref.read(playRecommendProvider(_args).notifier).loadFirst();
      });
    }
  }

  /// 滚到底部附近 → 追加下一页(编排层自带防重入与「没有更多」判定)。
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter > _loadMoreThreshold) return false;
    ref.read(playRecommendProvider(_args).notifier).loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playRecommendProvider(_args));
    // 无「相关推荐」标题(用户口径 2026-09-19:顶部不要标题),直接铺内容。
    return Column(
      key: const Key('play-side-recommend-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: _body(context, state)),
      ],
    );
  }

  Widget _body(BuildContext context, PlayRecommendState state) {
    final loadingFirstPage = state.loading && state.rooms.isEmpty;
    if (state.rooms.isEmpty && !loadingFirstPage) {
      return _Hint(
        text: state.error.isEmpty ? '相同分类的直播间会显示在这里' : state.error,
      );
    }
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: LayoutBuilder(
        builder: (context, constraints) => CustomScrollView(
        key: const Key('play-recommend-scroll'),
        slivers: [
          if (state.fallbackHint.isNotEmpty)
            SliverToBoxAdapter(
              child: _Hint(
                key: const Key('play-recommend-fallback-hint'),
                text: state.fallbackHint,
                compact: true,
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            sliver: SliverGrid.builder(
              gridDelegate: _gridDelegate(context, constraints.maxWidth),
              itemCount: state.rooms.length + state.placeholderCount,
              itemBuilder: (context, index) {
                final room = index < state.rooms.length
                    ? state.rooms[index]
                    : null;
                if (room == null) {
                  return _SkeletonCard(
                    key: ValueKey('play-recommend-skeleton-$index'),
                  );
                }
                return PlayRoomCard(
                  // 锚点沿用既有测试契约 play-recommend-room-{site}-{roomId}。
                  key: ValueKey(
                    'play-recommend-room-${room.site}-${room.roomId}',
                  ),
                  room: room,
                  onTap: () => widget.onTap(room),
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: _Footer(
              loadingMore: state.loadingMore,
              hasMore: state.hasMore,
              roomCount: state.rooms.length,
            ),
          ),
        ],
        ),
      ),
    );
  }

  /// 与 `PlayRoomGrid` 同源的纵横比推导:卡片高 = 封面(16:9) + 元信息两行,
  /// 由实际列宽反推 childAspectRatio(固定 0.78 在窄侧栏下会把元信息区拉空)。
  SliverGridDelegate _gridDelegate(BuildContext context, double maxWidth) {
    const padding = EdgeInsets.fromLTRB(
      AppSpacing.sm,
      0,
      AppSpacing.sm,
      AppSpacing.sm,
    );
    final width = math.max(0.0, maxWidth - padding.horizontal);
    final gaps = AppSpacing.sm * (_columns - 1);
    final columnWidth = math.max(1.0, (width - gaps) / _columns);
    final metaHeight = metaHeightFor(_cardMetaHeight, context);
    return SliverGridDelegateWithFixedCrossAxisCount(
      crossAxisCount: _columns,
      mainAxisSpacing: AppSpacing.sm,
      crossAxisSpacing: AppSpacing.sm,
      childAspectRatio: columnWidth / (columnWidth * 9 / 16 + metaHeight),
    );
  }
}

/// 空态/提示行(单行居中,与 web `.recommend-hint` 同位置)。
class _Hint extends StatelessWidget {
  const _Hint({super.key, required this.text, this.compact = false});

  final String text;

  /// 紧凑模式:作为列表首行提示(不居中占满),用于兜底文案。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final style = context.textCaption.copyWith(color: tokens.textSecondary);
    if (compact) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.sm,
          0,
          AppSpacing.sm,
          4,
        ),
        child: Text(text, style: style),
      );
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Text(text, textAlign: TextAlign.center, style: style),
      ),
    );
  }
}

/// 底部状态行:追加中 / 没有更多。
class _Footer extends StatelessWidget {
  const _Footer({
    required this.loadingMore,
    required this.hasMore,
    required this.roomCount,
  });

  final bool loadingMore;
  final bool hasMore;
  final int roomCount;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // 首屏骨架期没有房间也没有「更多」语义,不显示底行。
    if (roomCount == 0) return const SizedBox(height: AppSpacing.sm);
    final text = loadingMore
        ? '加载更多…'
        : (hasMore ? '向下滚动加载更多…' : '没有更多了');
    return Padding(
      key: const Key('play-recommend-footer'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: context.textCaption.copyWith(color: tokens.textSecondary),
      ),
    );
  }
}

/// 骨架占位卡:封面块 + 两条文字块,灰度色全部取 tokens。
class _SkeletonCard extends StatelessWidget {
  const _SkeletonCard({super.key});

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    Widget bar({required double widthFactor, required double height}) {
      return FractionallySizedBox(
        alignment: Alignment.centerLeft,
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            color: tokens.surfaceRaised,
            borderRadius: AppRadius.allSm,
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.allSm,
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: ColoredBox(color: tokens.surfaceRaised),
          ),
          Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                bar(widthFactor: 0.7, height: 9),
                const SizedBox(height: 5),
                bar(widthFactor: 0.45, height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
