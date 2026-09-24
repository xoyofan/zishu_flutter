/// 顶栏「我的关注」hover 浮层的**在播口径**用例。
///
/// 需求:hover 浮层永远只列**当前在播**的关注对象 ——
/// - 离线普通关注不出现;
/// - 离线**超关**也不出现(浮层是「现在能点进去看」的入口,与「我的关注」页
///   和播放页侧栏的可见性口径不同;两个入口的口径分别是
///   `visibleFollowEntries` / `isPlayFollowVisible`);
/// - 全部离线 → 「暂无开播」;
/// - 注入刷新能力后触发一轮刷新,新开播的房间会立刻出现在浮层里。
///
/// 宿主:真实 WindowsApp + 假播放器 + InMemorySharedPreferencesAsync,
/// 固定次数 pump(不用 pumpAndSettle)。
library;

import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show RoomPayload, RoomRecord, RoomState, RoomSummary, StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_status_poller.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer。
class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line,
          [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> toggleFullscreen() async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}

  @override
  Future<void> exitPictureInPicture() async {}

  @override
  Future<void> stop() async {}

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

/// 假刷新源:把脚本里的"开播"房间刷成在线,其余按离线返回。
class _ScriptedRefresher implements RoomRefresher {
  _ScriptedRefresher(this.onlineRoomIds);

  /// 刷新后视为在播的房间号集合。
  final Set<String> onlineRoomIds;

  int calls = 0;

  @override
  Future<RoomRecord> refreshRoom({
    required String site,
    required String roomId,
  }) async {
    calls++;
    final live = onlineRoomIds.contains(roomId);
    // 端口返回统一 RoomRecord:脚本仍按 RoomSummary 描述平台返回值,
    // 在端口边界转换(关注存储本切片仍为 RoomSummary);状态真源
    // roomState 随脚本在播/离线如实赋值 —— 关注链只认 roomState。
    return RoomRecord.fromSummary(
      RoomSummary(
        site: site,
        roomId: roomId,
        title: '直播中$roomId',
        anchorName: '主播$roomId',
        cid: 'cid-$roomId',
        category: '网游',
        online: live ? '1.2万' : '',
        cover: '',
        roomState: live ? RoomState.live : RoomState.offline,
      ),
    );
  }

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async =>
      throw UnimplementedError('本轨不校验解析路径');
}

Map<String, Object> _entry({
  required String roomId,
  required String online,
  bool isSpecial = false,
}) => {
  'site': 'douyu',
  'roomId': roomId,
  'title': '标题$roomId',
  'uname': '主播$roomId',
  'cover': '',
  'cid': 'cid-$roomId',
  'category': '网游',
  'online': online,
  'isSpecial': isSpecial,
  'remindOn': false,
  'followedAt': '2026-09-01T00:00:00.000Z',
};

/// pump 宿主:可注入刷新能力(不注入即 fixture 语义:无 refresher)。
Future<ProviderContainer> _pumpApp(
  WidgetTester tester, {
  required List<Map<String, Object>> seed,
  RoomRefresher? refresher,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(
        <String, Object>{'zishu.follow.list': jsonEncode(seed)},
      );
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        if (refresher != null) roomRefresherProvider.overrideWithValue(refresher),
      ],
      child: const WindowsApp(),
    ),
  );
  await _pumpFrames(tester, 3);
  final container = ProviderScope.containerOf(
    tester.element(find.byType(Navigator).first),
  );
  // 等 followProvider 从存储恢复出种子。
  for (var i = 0; i < 20; i++) {
    if (container.read(followProvider).length == seed.length) break;
    await _pumpFrames(tester, 1);
  }
  return container;
}

const Duration _kFrame = Duration(milliseconds: 50);

Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// hover 顶栏「我的关注」入口,触发浮层。
Future<void> _hoverFollow(WidgetTester tester) async {
  final finder = find.byKey(const Key('nav-follow'));
  await tester.ensureVisible(finder);
  final center = tester.getCenter(finder);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: center);
  await gesture.moveTo(center);
  addTearDown(() => gesture.removePointer());
  await _pumpFrames(tester, 6);
}

/// 浮层里的主播格(按主播名找)。
bool _flyoutHasAnchor(WidgetTester tester, String anchorName) {
  return find
      .descendant(
        of: find.byType(GridView),
        matching: find.text(anchorName),
      )
      .evaluate()
      .isNotEmpty;
}

void main() {
  testWidgets('hover 只列在播:离线普通与离线超关都不出现', (tester) async {
    await _pumpApp(
      tester,
      seed: [
        _entry(roomId: '1001', online: '1.2万'), // 在播
        _entry(roomId: '1002', online: '', isSpecial: true), // 离线超关
        _entry(roomId: '1003', online: ''), // 离线普通
      ],
    );

    await _hoverFollow(tester);

    expect(_flyoutHasAnchor(tester, '主播1001'), isTrue, reason: '在播应出现');
    expect(
      _flyoutHasAnchor(tester, '主播1002'),
      isFalse,
      reason: '浮层只列在播,离线超关也不列(与关注页/侧栏口径不同)',
    );
    expect(_flyoutHasAnchor(tester, '主播1003'), isFalse, reason: '离线普通不出现');
    expect(find.text('暂无开播'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('全部离线:浮层显示「暂无开播」而不是兜底列出全部关注', (tester) async {
    await _pumpApp(
      tester,
      seed: [
        _entry(roomId: '2001', online: ''),
        _entry(roomId: '2002', online: '', isSpecial: true),
      ],
    );

    await _hoverFollow(tester);

    expect(find.text('暂无开播'), findsOneWidget);
    expect(_flyoutHasAnchor(tester, '主播2001'), isFalse);
    expect(_flyoutHasAnchor(tester, '主播2002'), isFalse);
    expect(find.text('暂无关注'), findsNothing, reason: '空态文案对齐参考实现');
    expect(tester.takeException(), isNull);
  });

  testWidgets('注入刷新能力后:刷新把新开播房间带进浮层', (tester) async {
    final refresher = _ScriptedRefresher({'3002'});
    final container = await _pumpApp(
      tester,
      seed: [
        _entry(roomId: '3001', online: ''),
        _entry(roomId: '3002', online: ''),
      ],
      refresher: refresher,
    );
    expect(container.read(followProvider).any((e) => e.isLive), isFalse);

    // 轮询件存在(有 refresher 才建),刷新后 3002 开播。
    expect(container.read(followStatusPollerProvider), isNotNull);
    final refreshed = await container
        .read(followProvider.notifier)
        .refreshStatuses();
    expect(refreshed, 2);
    expect(refresher.calls, 2);
    await _pumpFrames(tester, 2);

    await _hoverFollow(tester);

    expect(_flyoutHasAnchor(tester, '主播3002'), isTrue, reason: '新开播房间应出现在浮层');
    expect(_flyoutHasAnchor(tester, '主播3001'), isFalse, reason: '仍在离线的房间不出现');
    expect(find.text('暂无开播'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
