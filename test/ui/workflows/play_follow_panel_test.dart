/// 播放页侧栏「关注」tab workflow 测试:可见性口径、空态、分页、切房。
///
/// 背景(用户报告 + 根因):面板曾用 `visibleFollowEntries(liveOnly: true)`,
/// 离线房间一律被丢 —— 关注的主播恰好都没开播时侧栏整片空白(「关注没显示」)。
/// 现口径对齐 SFVideoLive `isPlayFollowVisible`:在播可见,**离线超关也可见**。
///
/// 宿主写法与 side_panel_features_test.dart 一致:真实 router + 注入
/// FakeLivePlayer(VM 下禁止初始化 media_kit)+ InMemorySharedPreferencesAsync,
/// 固定次数 pump,不用 pumpAndSettle(封面图在 VM 中不会真正加载)。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 深链播放页:关注种子里的样例房间(douyu/63136)。
const String _playLocation = '/douyu/play/63136';

/// 固定 pump 步长,与既有 workflow 测试一致。
const Duration _kFrame = Duration(milliseconds: 50);

/// 侧栏关注面板的分页窗口(与实现/web `PLAY_FOLLOW_PAGE_SIZE` 对齐)。
const int _kPageSize = 48;

/// 离线超关也被保留时的空态文案(对齐 web `follow-recommend__empty-hint`)。
const String _kEmptyHint = '暂无在播关注；离线超关主播会保留在此列表';

/// 测试替身:替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class FakeLivePlayer implements LivePlayer {
  FakeLivePlayer();

  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(
    StreamLine line, [
    List<StreamLine> fallbacks = const [],
    bool resetRetries = true,
  ]) async => calls.add('open:${line.url}');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted:$muted');

  @override
  Future<void> toggleFullscreen() async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}

  @override
  Future<void> exitPictureInPicture() async {}

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

/// 测试宿主:与 WindowsApp 相同的 router/theme,补一层透明 Material。
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: ZishuTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// 关注条目种子 JSON(与 follow_provider 的持久化字段同名)。
Map<String, Object> _seedEntry({
  required String roomId,
  String site = 'douyu',
  String title = '测试房间',
  String anchor = '测试主播',
  String online = '1.2万',
  bool isSpecial = false,
}) => {
  'site': site,
  'roomId': roomId,
  'title': title,
  'uname': anchor,
  'cid': '1',
  'category': '英雄联盟',
  'online': online,
  'cover': '',
  'isSpecial': isSpecial,
  'remindOn': false,
  'followedAt': DateTime.now().toIso8601String(),
};

/// 轮询等待关注 provider 完成异步恢复(种子条数落地)。
Future<void> _awaitFollowRestored(
  WidgetTester tester,
  ProviderContainer container,
  int count,
) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    if (container.read(followProvider).length == count) return;
    await tester.pump(_kFrame);
  }
  fail('followProvider 未在限定帧数内恢复出 $count 条种子');
}

/// 固定次数 pump。
Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 启动真实宿主 → 深链播放页 → 切到侧栏「关注」tab。
Future<({GoRouter router, ProviderContainer container})> _pumpFollowTab(
  WidgetTester tester,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(FakeLivePlayer())],
      child: const _TestApp(),
    ),
  );
  await _pumpFrames(tester, 2);

  final element = tester.element(find.byType(Navigator).first);
  final container = ProviderScope.containerOf(element);
  final router = container.read(routerProvider);
  router.go(_playLocation);
  await _pumpFrames(tester, 3);

  // TabBar 切换动画约 300ms,pump 不足时点击会落在滑动中的旧坐标上。
  await tester.tap(find.byKey(const Key('play-side-tab-follow')));
  await _pumpFrames(tester, 8);
  return (router: router, container: container);
}

/// 关注面板内的房间卡锚点。
Finder _card(String site, String roomId) =>
    find.byKey(Key('play-follow-room-$site-$roomId'));

/// 关注面板内的封面网格(PlayRoomGrid 用 GridView.builder)。
/// 页面上还有别的 GridView(壳层浮层等),必须限定在面板子树内。
Finder _followGrid() => find
    .descendant(
      of: find.byKey(const Key('play-side-follow-panel')),
      matching: find.byType(GridView),
    )
    .first;

/// 网格当前**窗口**条目数(GridView.builder 的 delegate 计数,不等于已构建的可见项)。
int _gridChildCount(WidgetTester tester) =>
    tester
        .widget<GridView>(_followGrid())
        .childrenDelegate
        .estimatedChildCount ??
    -1;

void main() {
  group('侧栏关注面板可见性(web isPlayFollowVisible 口径)', () {
    testWidgets('在播可见 + 离线超关可见 + 离线非超关隐藏', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '1001', title: '在播普通关注'),
              _seedEntry(roomId: '1002', isSpecial: true, title: '在播超关'),
              _seedEntry(
                roomId: '1003',
                online: '',
                isSpecial: true,
                title: '离线超关',
              ),
              _seedEntry(roomId: '1004', online: '', title: '离线非超关'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 4);
      await _pumpFrames(tester, 3);

      expect(find.byKey(const Key('play-side-follow-panel')), findsOneWidget);
      expect(_card('douyu', '1001'), findsOneWidget, reason: '在播必须显示');
      expect(_card('douyu', '1002'), findsOneWidget, reason: '在播超关必须显示');
      expect(
        _card('douyu', '1003'),
        findsOneWidget,
        reason: '离线超关必须保留 —— 这正是「关注没显示」的根因(liveOnly 把它丢了)',
      );
      expect(_card('douyu', '1004'), findsNothing, reason: '离线且非超关隐藏(与参考实现一致)');
      expect(find.text(_kEmptyHint), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('只剩离线非超关时,展示 web 空态文案', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '3001', online: '', title: '离线一'),
              _seedEntry(roomId: '3002', online: '', title: '离线二'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 2);
      await _pumpFrames(tester, 3);

      expect(find.text(_kEmptyHint), findsOneWidget);
      expect(_card('douyu', '3001'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('侧栏关注面板分页与交互', () {
    testWidgets('分页 48/页:滚到底自动放下一批并隐藏「加载更多」提示', (tester) async {
      final seed = [
        for (var i = 0; i < 60; i++)
          _seedEntry(roomId: '${2000 + i}', title: '批量房间 $i'),
      ];
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode(seed),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 60);
      await _pumpFrames(tester, 3);

      expect(_gridChildCount(tester), _kPageSize, reason: '首屏只放一页');
      expect(find.text('向下滚动加载更多…'), findsOneWidget);

      // 滚到底 → 触发下一页加载(60 < 96,一次到位,提示随之消失)。
      await tester.drag(_followGrid(), const Offset(0, -6000));
      await _pumpFrames(tester, 5);

      expect(_gridChildCount(tester), 60, reason: '滚动到底后应放出全部 60 条');
      expect(find.text('向下滚动加载更多…'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('平台筛选 chips:只显示所选平台的关注', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '4001', title: '斗鱼房间'),
              _seedEntry(roomId: '4002', site: 'huya', title: '虎牙房间'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 2);
      await _pumpFrames(tester, 3);

      expect(_card('douyu', '4001'), findsOneWidget);
      expect(_card('huya', '4002'), findsOneWidget);

      // 按钮锚点(卡面上的平台角标同样是「虎牙」文本,故按 key 定位 chip)。
      await tester.tap(find.byKey(const Key('play-side-follow-site-huya')));
      await _pumpFrames(tester, 3);

      expect(_card('huya', '4002'), findsOneWidget);
      expect(_card('douyu', '4001'), findsNothing, reason: '筛虎牙后不应再出现斗鱼条目');

      await tester.tap(find.byKey(const Key('play-side-follow-site-all')));
      await _pumpFrames(tester, 3);
      expect(_card('douyu', '4001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('点关注条目切房:pushReplacement 到目标播放页', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '5001', title: '待进入的房间'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 1);
      await _pumpFrames(tester, 3);

      final target = _card('douyu', '5001');
      await tester.ensureVisible(target);
      await tester.tap(target);
      await _pumpFrames(tester, 4);

      final view = tester.widget<PlayView>(find.byType(PlayView));
      expect(view.roomId, '5001', reason: '点条目应切到该直播间');
      expect(
        play.router.routeInformationProvider.value.uri.path,
        '/douyu/play/5001',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('视图切换:网格 ⇄ 紧凑列表,条目仍在', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '6001', title: '视图切换房间'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 1);
      await _pumpFrames(tester, 3);
      expect(_card('douyu', '6001'), findsOneWidget);

      await tester.tap(find.byKey(const Key('play-side-follow-view-toggle')));
      await _pumpFrames(tester, 3);
      expect(
        find.byKey(const Key('play-room-row-douyu-6001')),
        findsOneWidget,
        reason: '紧凑列表视图的锚点',
      );

      await tester.tap(find.byKey(const Key('play-side-follow-view-toggle')));
      await _pumpFrames(tester, 3);
      expect(_card('douyu', '6001'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
