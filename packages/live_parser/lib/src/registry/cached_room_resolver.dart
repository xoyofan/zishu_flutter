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
class CachedRoomResolver implements RoomResolver {
  CachedRoomResolver(
    this._inner, {
    this.ttl = const Duration(seconds: 60),
    this.maxEntries = 64,
  });

  final RoomResolver _inner;
  final Duration ttl;
  final int maxEntries;

  final Map<String, _CacheEntry> _entries = {};

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) {
    final preferred = request.preferredQuality?.trim() ?? '';
    if (preferred.isEmpty) return _inner.resolveRoom(request);

    final key = '${request.site}\u0000${request.roomIdOrUrl}\u0000$preferred';
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
