import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart'
    show RoomSummary, tryParseOnlineCount;

import '../../../shared/application/providers.dart' show roomRefresherProvider;

/// 播放页当前房间的统计快照(用户口径 2026-09-20:huya 等平台的关注/VIP
/// 统计不能只服务已关注房间;2026-09-24 回归口径:统计与关注状态完全分离)。
///
/// 对任意房间直接调解析侧 `RoomSummaryRefresher.refreshRoom` —— 与关注行
/// 刷新同一条真源链(huya profileRoom / douyu getAnchorNewCard 等),不需要
/// 关注状态。展示层经 [mergeDisplayStats] 逐字段合并新鲜解析值与本地已有
/// 统计快照,任何一侧的空缺互不遮蔽。
///
/// 单房间 10s 超时;失败返回 null(回退本地快照或展示「—」,数据诚实性:
/// 不伪造)。
final roomStatsProvider = FutureProvider.autoDispose
    .family<RoomSummary?, ({String site, String roomId})>((ref, key) async {
      final refresher = ref.read(roomRefresherProvider);
      if (refresher == null) return null;
      try {
        return await refresher
            .refreshRoom(site: key.site, roomId: key.roomId)
            .timeout(const Duration(seconds: 10));
      } catch (_) {
        return null;
      }
    });

/// 展示统计的逐字段合并(桌面信息头与窄屏信息条共用)。
///
/// 统计取数与关注状态**完全分离**:每个统计字段独立选值 ——
/// 先取 [parsed](roomStatsProvider 的新鲜解析快照)中该字段的非空值;
/// 该字段解析缺失时再回退 [local](关注条目维护的本地统计快照)的非空值;
/// 两侧都未知则保持空串,展示层渲染「—」。
/// [parsed] 为 null(解析失败/无刷新能力)时整体回退本地快照:错误只表现为
/// 回退或「—」,不冒充有效零,也绝不从关注布尔值推任何人数
/// (回归根因:此前整份快照按 followed 有无切换数据源,点关注瞬间
/// 空统计盖掉解析值、数值全部消失)。
///
/// **观看人数(online)例外,只认可可信数值**:online 同时承载在播占位
/// 文案(点关注写入的「直播中」、SOOP `kSoopLiveOnlineFallback`),它们
/// 只表达在播、不是人数 —— 该字段两侧都必须通过 [tryParseOnlineCount]
/// (可解析含合法 0)才可展示,否则取另一个可信值,再否则置空 →「—」。
/// 仅清洗展示取数,不回写任何快照,roomState/是否开播判据不受影响;
/// followers/vip/diamondFans 仍按「非空字符串即有效」的既有口径不变。
///
/// 返回值仅供统计展示取数,不参与在播判据等业务语义。
RoomSummary? mergeDisplayStats({RoomSummary? parsed, RoomSummary? local}) {
  final base = parsed ?? local;
  if (base == null) return null;
  String fresh(String parsedValue, String localValue) =>
      parsedValue.trim().isNotEmpty ? parsedValue : localValue;
  // 观看人数数值边界:两侧只认可 tryParseOnlineCount 可解析的可信文案。
  String onlineCount(String parsedOnline, String localOnline) {
    if (tryParseOnlineCount(parsedOnline) != null) return parsedOnline;
    if (tryParseOnlineCount(localOnline) != null) return localOnline;
    return '';
  }

  return RoomSummary(
    site: base.site,
    roomId: base.roomId,
    title: fresh(parsed?.title ?? '', local?.title ?? ''),
    anchorName: fresh(parsed?.anchorName ?? '', local?.anchorName ?? ''),
    cid: fresh(parsed?.cid ?? '', local?.cid ?? ''),
    category: fresh(parsed?.category ?? '', local?.category ?? ''),
    online: onlineCount(parsed?.online ?? '', local?.online ?? ''),
    cover: fresh(parsed?.cover ?? '', local?.cover ?? ''),
    avatar: fresh(parsed?.avatar ?? '', local?.avatar ?? ''),
    promoTag: parsed?.promoTag ?? local?.promoTag,
    followers: fresh(parsed?.followers ?? '', local?.followers ?? ''),
    vip: fresh(parsed?.vip ?? '', local?.vip ?? ''),
    diamondFans: fresh(parsed?.diamondFans ?? '', local?.diamondFans ?? ''),
    roomState: parsed?.roomState ?? local!.roomState,
    startedAt: parsed?.startedAt ?? local?.startedAt,
  );
}
