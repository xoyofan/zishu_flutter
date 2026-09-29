part of '../play_side_panel.dart';

/// 侧栏「推荐」tab:跨平台「相关推荐」。
///
/// 逻辑与呈现都在 [PlayRecommendPanel](参考实现 `usePlayRecommend.ts` 逐条复刻:
/// 站点顺序 douyu/huya/bilibili/douyin、每站 3 条交错合并、分类映射与热门兜底、
/// 滚动分页);本类只做「把播放页上下文与切房回调接上」的薄壳,避免侧栏文件里
/// 再养一份编排。
class _RecommendPanel extends StatelessWidget {
  const _RecommendPanel({
    required this.site,
    required this.roomId,
    required this.cid,
    required this.category,
  });

  final String site;

  /// 当前房间号:推荐里要剔除它自己。
  final String roomId;
  final String cid;

  /// 当前房间分类名:其它平台的分类映射按它匹配。
  final String category;

  @override
  Widget build(BuildContext context) {
    return PlayRecommendPanel(
      site: site,
      roomId: roomId,
      cid: cid,
      category: category,
      // 切房语义与「关注」tab 完全一致:pushReplacement 只换栈顶播放页 ——
      // 旧播放页被卸载(media-kit 会话随 autoDispose 收干净),下层浏览页
      // 保留为返回目标(go 会重置整条栈,左上角「返回」将无栈可回)。
      onTap: (room) {
        PlaybackLog.logRoomNav(
          source: 'play_recommend_panel',
          site: room.site,
          roomId: room.roomId,
        );
        context.pushReplacement('/${room.site}/play/${room.roomId}');
      },
    );
  }
}
