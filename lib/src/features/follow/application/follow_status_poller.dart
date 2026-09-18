/// 关注「在播状态」定时轮询:让关注列表里的在线状态始终是**当前**的。
///
/// 为什么需要它:顶栏「我的关注」hover 浮层、侧栏「最近在播」都读
/// `FollowEntry.room.online`,而该字段只在「加入关注 / 上次刷新」时写入 ——
/// 不轮询就永远是入列那一刻的快照(用户会看到早已下播的主播还在浮层里)。
/// 参考实现的 Web 端由 `utils/follow/followStatusHub.ts` 周期性驱动同一件事,
/// 本件对齐它的**最小刷新间隔**语义(60s)。
///
/// 设计约束:
/// - 无 [RoomRefresher](全 fixture / 单元测试)时**不建 timer、零网络**;
/// - 每 tick 只刷一批(默认 16 条,游标在 controller 内环状推进)→ 关注 N 条
///   时 ceil(N/16) 个周期全覆盖,不会每个周期把全部房间打一遍;
/// - 单轮失败静默(条目级隔离在 `FollowController.refreshStatuses` 内),
///   不弹提示、不打扰 UI;
/// - 上一轮未结束时跳过本轮,避免慢网下周期重叠把请求量翻倍。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/application/providers.dart';
import 'follow_provider.dart';

/// 轮询周期:对齐 Web 端 `followStatusHub` 的 60s 最小刷新间隔。
const Duration kFollowStatusRefreshInterval = Duration(seconds: 60);

/// 单轮刷新批量上限(游标轮转的窗口大小)。
const int kFollowStatusRefreshBatch = 16;

/// 关注状态轮询器:纯 Dart 定时件,便于单测直接注入短周期与假刷新函数。
class FollowStatusPoller {
  FollowStatusPoller({
    required this.refresh,
    this.interval = kFollowStatusRefreshInterval,
  });

  /// 单轮刷新函数(通常是 `FollowController.refreshStatuses(limit: …)`)。
  final Future<int> Function() refresh;

  /// 轮询周期。
  final Duration interval;

  Timer? _timer;
  bool _running = false;

  /// 是否已在周期轮询中。
  bool get running => _timer != null;

  /// 启动周期轮询(幂等)。
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(tick()));
  }

  /// 停止并释放 timer(容器销毁或手动停用)。
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }

  /// 立即补跑一轮:浮层打开时调用,让 hover 看到的是刚刷新的结果,
  /// 而不必等下一个周期。
  Future<int> wake() => tick();

  /// 单轮刷新;上一轮未结束时返回 0(跳过),异常静默。
  Future<int> tick() async {
    if (_running) return 0;
    _running = true;
    try {
      return await refresh();
    } catch (_) {
      // 单轮失败静默:下一周期继续;单条失败已在 controller 内按条目隔离。
      return 0;
    } finally {
      _running = false;
    }
  }
}

/// 轮询器 provider:无 refresher(fixture/单测)时返回 null ——
/// 调用点用 `?.wake()` 自然退化为无操作,不会建 timer、不会发网络。
final followStatusPollerProvider = Provider<FollowStatusPoller?>((ref) {
  final refresher = ref.watch(roomRefresherProvider);
  if (refresher == null) return null;
  final poller = FollowStatusPoller(
    refresh: () => ref
        .read(followProvider.notifier)
        .refreshStatuses(limit: kFollowStatusRefreshBatch),
  )..start();
  ref.onDispose(poller.dispose);
  return poller;
});
