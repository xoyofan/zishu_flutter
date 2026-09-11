/// CachedRoomResolver:结果短缓存的命中/失效/并发合并语义。
library;

import 'dart:async';

import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/registry/cached_room_resolver.dart';
import 'package:test/test.dart';

RoomPayload _payload(RoomState state, {bool withLines = true}) => RoomPayload(
  site: 'demo',
  roomId: '42',
  sourceUrl: 'https://demo/42',
  anchorName: '主播',
  title: '房间',
  cover: '',
  avatar: '',
  category: '',
  cid: '42',
  roomState: state,
  streams: withLines
      ? const [
          StreamQuality(
            name: '高清',
            rate: 1,
            lines: [
              StreamLine(
                name: '线路',
                url: 'https://demo/live.m3u8',
                format: 'hls',
              ),
            ],
          ),
        ]
      : const [],
  availableQualities: const [QualityOption(name: '高清', rate: 1)],
  source: 'test',
  fetchedAt: DateTime.now(),
);

class _FakeResolver implements RoomResolver {
  _FakeResolver(this.respond);

  final Future<RoomPayload> Function(RoomRequest request) respond;
  final List<RoomRequest> calls = [];

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) {
    calls.add(request);
    return respond(request);
  }
}

void main() {
  const request = RoomRequest(
    site: 'demo',
    roomIdOrUrl: '42',
    preferredQuality: '高清',
  );

  test('同一 (site,room,偏好档) 在 TTL 内命中缓存,不重复请求', () async {
    final inner = _FakeResolver((_) async => _payload(RoomState.live));
    final cached = CachedRoomResolver(inner);

    final first = await cached.resolveRoom(request);
    final second = await cached.resolveRoom(request);

    expect(inner.calls, hasLength(1));
    expect(identical(first, second), isTrue);
  });

  test('偏好档不同 → 不同缓存键', () async {
    final inner = _FakeResolver((_) async => _payload(RoomState.live));
    final cached = CachedRoomResolver(inner);

    await cached.resolveRoom(request);
    await cached.resolveRoom(
      const RoomRequest(site: 'demo', roomIdOrUrl: '42', preferredQuality: '流畅'),
    );

    expect(inner.calls, hasLength(2));
  });

  test('不带偏好档的裸解析不缓存', () async {
    final inner = _FakeResolver((_) async => _payload(RoomState.live));
    final cached = CachedRoomResolver(inner);

    await cached.resolveRoom(const RoomRequest(site: 'demo', roomIdOrUrl: '42'));
    await cached.resolveRoom(const RoomRequest(site: 'demo', roomIdOrUrl: '42'));

    expect(inner.calls, hasLength(2));
  });

  test('离线/无线路结果不缓存,便于开播后立即重试', () async {
    final inner = _FakeResolver(
      (_) async => _payload(RoomState.offline, withLines: false),
    );
    final cached = CachedRoomResolver(inner);

    await cached.resolveRoom(request);
    await cached.resolveRoom(request);

    expect(inner.calls, hasLength(2));
  });

  test('异常不缓存且原样抛出', () async {
    var fail = true;
    final inner = _FakeResolver((_) async {
      if (fail) throw StateError('boom');
      return _payload(RoomState.live);
    });
    final cached = CachedRoomResolver(inner);

    await expectLater(cached.resolveRoom(request), throwsStateError);
    fail = false;
    final payload = await cached.resolveRoom(request);

    expect(payload.roomState, RoomState.live);
    expect(inner.calls, hasLength(2));
  });

  test('并发同键合并为一次请求', () async {
    final completer = Completer<RoomPayload>();
    final inner = _FakeResolver((_) => completer.future);
    final cached = CachedRoomResolver(inner);

    final pending = Future.wait([
      cached.resolveRoom(request),
      cached.resolveRoom(request),
    ]);
    completer.complete(_payload(RoomState.live));
    final results = await pending;

    expect(inner.calls, hasLength(1));
    expect(results, hasLength(2));
  });

  test('TTL 过期后重新解析', () async {
    final inner = _FakeResolver((_) async => _payload(RoomState.live));
    final cached = CachedRoomResolver(inner, ttl: Duration.zero);

    await cached.resolveRoom(request);
    await cached.resolveRoom(request);

    expect(inner.calls, hasLength(2));
  });
}
