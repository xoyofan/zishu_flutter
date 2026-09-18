/// 播放页侧栏「关注」tab workflow 测试:可见性口径、空态、分页、切房。
///
/// 口径沿革:面板曾用 `visibleFollowEntries(liveOnly: true)` 把离线一律丢掉,
/// 「关注没显示」后一度改为 web `isPlayFollowVisible` 口径(在播 + 离线超关);
/// **2026-09-19 用户口径再次更新:不显示没开播的(离线超关也不再保留)**,
/// 且默认视图为紧凑列表(每条一行)。web 真源 `isPlayFollowVisible` 的
/// 「离线超关可见」分支为有意偏离(用户口径优先),排序保持 超关 → 在播。
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

/// 用户口径(2026-09-19:不显示没开播的)下的空态文案。
const String _kEmptyHint = '暂无在播关注';

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

/// 关注面板内的房间卡锚点(网格视图,PlayRoomCard)。
Finder _card(String site, String roomId) =>
    find.byKey(Key('play-follow-room-$site-$roomId'));

/// 关注面板内的紧凑列表行锚点(列表视图,PlayRoomRow)。
Finder _row(String site, String roomId) =>
    find.byKey(Key('play-room-row-$site-$roomId'));

/// 面板内是否有 GridView(不带 first,供 findsNothing 断言)。
Finder _anyGridInPanel() => find.descendant(
  of: find.byKey(const Key('play-side-follow-panel')),
  matching: find.byType(GridView),
);

/// 面板内的**垂直** ListView(关注列表)。面板里还有平台筛选 chips 的水平
/// ListView(_SidePlatformChips),必须按滚动方向过滤,否则 finder 误中。
Finder _verticalListsInPanel() => find.descendant(
  of: find.byKey(const Key('play-side-follow-panel')),
  matching: find.byWidgetPredicate(
    (w) => w is ListView && w.scrollDirection == Axis.vertical,
  ),
);

/// 面板内的紧凑列表(PlayRoomList 用 ListView.separated)。
Finder _followList() => _verticalListsInPanel().first;

/// 列表当前**窗口**条目数:读 builder delegate 声明的 childCount
/// (ListView.separated 把条目与 separator 交错,实际条目数 = (n+1)~/2;
/// 不能用 estimatedChildCount —— 那是按可视区估算的,GridView 才是精确值)。
int _listChildCount(WidgetTester tester) {
  final delegate =
      tester.widget<ListView>(_followList()).childrenDelegate
          as SliverChildBuilderDelegate;
  final count = delegate.childCount ?? -1;
  return count <= 0 ? 0 : (count + 1) ~/ 2;
}

void main() {
  group('侧栏关注面板可见性(用户口径 2026-09-19:只显在播)', () {
    testWidgets('在播可见(超关/普通)+ 离线一律隐藏(含超关)', (tester) async {
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
      expect(_row('douyu', '1001'), findsOneWidget, reason: '在播必须显示');
      expect(_row('douyu', '1002'), findsOneWidget, reason: '在播超关必须显示');
      expect(
        _row('douyu', '1003'),
        findsNothing,
        reason: '用户口径(2026-09-19):离线超关也不再保留,不显示没开播的',
      );
      expect(_row('douyu', '1004'), findsNothing, reason: '离线且非超关隐藏');
      expect(find.text(_kEmptyHint), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('只剩离线(含超关)时,展示空态文案', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '3001', online: '', title: '离线普通'),
              _seedEntry(
                roomId: '3002',
                online: '',
                isSpecial: true,
                title: '离线超关',
              ),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 2);
      await _pumpFrames(tester, 3);

      expect(find.text(_kEmptyHint), findsOneWidget);
      expect(_row('douyu', '3001'), findsNothing);
      expect(_row('douyu', '3002'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('排序:超关在播在前,普通在播在后(列表每条一行)', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              // 普通关注先关注(倒序下本应在前),超关后关注 —— 超关必须置顶。
              _seedEntry(roomId: '8001', title: '普通在播'),
              _seedEntry(roomId: '8002', isSpecial: true, title: '超关在播'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 2);
      await _pumpFrames(tester, 3);

      final normalRect = tester.getRect(_row('douyu', '8001'));
      final superRect = tester.getRect(_row('douyu', '8002'));
      expect(
        superRect.top,
        lessThan(normalRect.top),
        reason: '超关在播必须排在普通在播之前(用户口径:按超关、关注排序)',
      );
      expect(superRect.left, normalRect.left, reason: '列表视图每条独占一行');
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

      expect(_listChildCount(tester), _kPageSize, reason: '首屏只放一页');
      expect(find.text('向下滚动加载更多…'), findsOneWidget);

      // 滚到底 → 触发下一页加载(60 < 96,一次到位,提示随之消失)。
      await tester.drag(_followList(), const Offset(0, -6000));
      await _pumpFrames(tester, 5);

      expect(_listChildCount(tester), 60, reason: '滚动到底后应放出全部 60 条');
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

      expect(_row('douyu', '4001'), findsOneWidget);
      expect(_row('huya', '4002'), findsOneWidget);

      // 按钮锚点(卡面上的平台角标同样是「虎牙」文本,故按 key 定位 chip)。
      await tester.tap(find.byKey(const Key('play-side-follow-site-huya')));
      await _pumpFrames(tester, 3);

      expect(_row('huya', '4002'), findsOneWidget);
      expect(_row('douyu', '4001'), findsNothing, reason: '筛虎牙后不应再出现斗鱼条目');

      await tester.tap(find.byKey(const Key('play-side-follow-site-all')));
      await _pumpFrames(tester, 3);
      expect(_row('douyu', '4001'), findsOneWidget);
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

      final target = _row('douyu', '5001');
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

    testWidgets('默认列表视图;可切换到封面网格再切回', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '6001', title: '视图切换房间'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 1);
      await _pumpFrames(tester, 3);
      expect(
        _row('douyu', '6001'),
        findsOneWidget,
        reason: '用户口径(2026-09-19):默认用列表显示,每条一行',
      );
      expect(_anyGridInPanel(), findsNothing, reason: '默认不应是封面网格');

      await tester.tap(find.byKey(const Key('play-side-follow-view-toggle')));
      await _pumpFrames(tester, 3);
      expect(_card('douyu', '6001'), findsOneWidget, reason: '切换后是封面网格');
      expect(
        _verticalListsInPanel(),
        findsNothing,
        reason: '网格视图下不应残留列表',
      );

      await tester.tap(find.byKey(const Key('play-side-follow-view-toggle')));
      await _pumpFrames(tester, 3);
      expect(_row('douyu', '6001'), findsOneWidget, reason: '可切回列表');
      expect(tester.takeException(), isNull);
    });
  });
}
