import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show RoomSummary;

import '../../../shared/application/providers.dart' show roomRefresherProvider;

/// 播放页当前房间的统计兜底(用户口径 2026-09-20:huya 等平台的关注/VIP
/// 统计不能只服务已关注房间)。
///
/// 对任意房间直接调解析侧 `RoomSummaryRefresher.refreshRoom` —— 与关注行
/// 刷新同一条真源链(huya profileRoom / douyu getAnchorNewCard 等),不需要
/// 关注状态。已关注房间优先消费关注条目的 summary(关注链路维护、带离线
/// 跃迁记账),本 provider 只在条目缺失/未回填时兜底。
///
/// 单房间 10s 超时;失败返回 null(展示「—」,数据诚实性:不伪造)。
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
