/// 房间解析结果短缓存装饰器(对齐 SFVideoLive 服务层 payload 60s 缓存)。
library;

import '../contracts/contracts.dart';
import '../models/models.dart';

/// 只缓存「带偏好画质 + 在播且有线路」的成功结果:
/// - 键 = `site + roomIdOrUrl + preferredQuality`,同一入口短时间重复进房
///   (含切档回退)直接复用,0 请求;
/// - 不带 `preferredQuality` 的裸解析保持实时(浏览/测试语义不变);
/// - 离线/不存在/异常不缓存,开播或修好后立即重试;
/// - 并发的同键请求合并到同一个 Future,避免 UI 重建触发重复请求。
///
/// 同时实现 [RoomRecoveryResolver]:恢复路径**必须绕开本缓存**——缓存里的
/// 地址可能已过期,复用即等于反复重开失效源。故 `recoverRoom` 先失效键,
/// 再委托内层重新解析。
class CachedRoomResolver
    implements RoomResolver, RoomRecoveryResolver, RoomSummaryRefresher {
  CachedRoomResolver(
    this._inner, {
    this.ttl = const Duration(seconds: 60),
    this.maxEntries = 64,
  });

  final RoomResolver _inner;
  final Duration ttl;
  final int maxEntries;

  final Map<String, _CacheEntry> _entries = {};

  /// 缓存键:与 [resolveRoom] 的命中判据严格一致。
  String _keyOf(RoomRequest request) =>
      '${request.site}\u0000${request.roomIdOrUrl}\u0000'
      '${request.preferredQuality?.trim() ?? ''}';

  /// 恢复重解析:先失效本键短缓存,再委托内层。
  ///
  /// 内层若自身就是 [RoomRecoveryResolver](签名平台实现),优先调用其
  /// `recoverRoom`,由它保证重新走一遍签名 / 取流;否则回退到 `resolveRoom`
  /// —— 内层每次调用都是真实网络请求(不在内部缓存地址),故同样满足
  /// 「重新获取」的语义。
  @override
  Future<RoomPayload> recoverRoom(RoomRequest request) {
    _entries.remove(_keyOf(request));
    final inner = _inner;
    if (inner is RoomRecoveryResolver) return inner.recoverRoom(request);
    return inner.resolveRoom(request);
  }

  /// 轻量刷新:直接委托内层,**不经过短缓存也不写缓存**。
  ///
  /// 刷新本身就是为了拿最新在播状态,缓存会把刷新变成“回读旧快照”;
  /// 内层未实现该能力(如部分站点)时抛错,由调用方按条目隔离。
  /// 异步抛出(而非同步 throw):保证调用方统一用 Future 的错误处理捕获
  /// ——与 `UnsupportedRoomResolver` 同一约定。
  @override
  Future<RoomSummary> refreshRoomSummary(RoomRequest request) async {
    final inner = _inner;
    if (inner is RoomSummaryRefresher) {
      return inner.refreshRoomSummary(request);
    }
    throw UnsupportedError('站点 ${request.site} 未实现房间状态刷新');
  }

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) {
    final preferred = request.preferredQuality?.trim() ?? '';
    if (preferred.isEmpty) return _inner.resolveRoom(request);

    final key = _keyOf(request);
    final now = DateTime.now();
    final hit = _entries[key];
    if (hit != null && now.difference(hit.at) < ttl) return hit.future;

    final inner = _inner.resolveRoom(request);
    final entry = _CacheEntry(at: now, future: inner);
    _entries[key] = entry;
    _evictOverflow();
    return inner.then(
      (payload) {
        if (payload.roomState != RoomState.live || payload.streams.isEmpty) {
          if (identical(_entries[key], entry)) _entries.remove(key);
        }
        return payload;
      },
      onError: (Object error, StackTrace stackTrace) {
        if (identical(_entries[key], entry)) _entries.remove(key);
        Error.throwWithStackTrace(error, stackTrace);
      },
    );
  }

  void _evictOverflow() {
    while (_entries.length > maxEntries) {
      _entries.remove(_entries.keys.first);
    }
  }
}

class _CacheEntry {
  const _CacheEntry({required this.at, required this.future});

  final DateTime at;
  final Future<RoomPayload> future;
}
