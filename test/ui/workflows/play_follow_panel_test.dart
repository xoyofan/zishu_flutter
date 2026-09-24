/// 播放页侧栏「关注」tab workflow 测试:可见性口径、空态、分页、切房。
///
/// 口径沿革:面板曾用 `visibleFollowEntries(liveOnly: true)` 把离线一律丢掉,
/// 「关注没显示」后一度改为 web `isPlayFollowVisible` 口径(在播 + 离线超关);
/// **2026-09-19 用户口径再次更新:不显示没开播的(离线超关也不再保留)**,
/// 且默认视图为紧凑列表(每条一行)。web 真源 `isPlayFollowVisible` 的
/// 「离线超关可见」分支为有意偏离(用户口径优先),排序保持 超关在播 → 在播;
/// 轮播(replay)与离线一样只在「我的关注」页可见。
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
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_card.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_row.dart';
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
  String roomState = '',
}) => {
  'site': site,
  'roomId': roomId,
  'title': title,
  'uname': anchor,
  'cid': '1',
  'category': '英雄联盟',
  'online': online,
  'cover': '',
  if (roomState.isNotEmpty) 'roomState': roomState,
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
///
/// [location] 缺省为种子样例房间(douyu/63136);「未关注」场景需传一个
/// **不在 fixture 种子前 6 条**里的房间(种子会自动成为关注,见
/// FollowController._seed)。
Future<({GoRouter router, ProviderContainer container})> _pumpFollowTab(
  WidgetTester tester, {
  String location = _playLocation,
  double width = 1600,
  double height = 1200,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = Size(width, height);
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
  router.go(location);
  await _pumpFrames(tester, 3);

  // TabBar 切换动画约 300ms,pump 不足时点击会落在滑动中的旧坐标上。
  await tester.tap(find.byKey(const Key('play-side-tab-follow')));
  await _pumpFrames(tester, 8);
  return (router: router, container: container);
}

/// 关注面板内的房间卡锚点(网格视图,共享组件 `FollowEntryCard`)。
/// 卡片/单行同用 `follow-entry-{site}-{roomId}` key,故按外层组件类型定位。
Finder _card(String site, String roomId) => find.ancestor(
  of: find.byKey(Key('follow-entry-$site-$roomId')),
  matching: find.byType(FollowEntryCard),
);

/// 关注面板内的四列单行锚点(列表视图,共享组件 `FollowEntryRow`)。
Finder _row(String site, String roomId) => find.ancestor(
  of: find.byKey(Key('follow-entry-$site-$roomId')),
  matching: find.byType(FollowEntryRow),
);

/// 面板内的**垂直**关注列表。列表档是垂直 GridView(300–400px 自适应
/// 多列,窄侧栏单列),卡片档是垂直 ListView —— 都按 ScrollView 读。
Finder _followList() => find.descendant(
  of: find.byKey(const Key('play-side-follow-panel')),
  matching: find.byWidgetPredicate(
    (w) => w is ScrollView && w.scrollDirection == Axis.vertical,
  ),
).first;

/// 列表当前**窗口**条目数:读 builder delegate 声明的 childCount
/// (行自带底边框;GridView/ListView 的 builder delegate 都是精确 childCount,
/// 不能用 estimatedChildCount —— 那是按可视区估算的)。
int _listChildCount(WidgetTester tester) {
  final widget = tester.widget<Widget>(_followList());
  final SliverChildBuilderDelegate delegate;
  if (widget is GridView) {
    delegate = widget.childrenDelegate as SliverChildBuilderDelegate;
  } else if (widget is ListView) {
    delegate = widget.childrenDelegate as SliverChildBuilderDelegate;
  } else {
    throw StateError('意外的关注列表组件:${widget.runtimeType}');
  }
  return delegate.childCount ?? -1;
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

    testWidgets('轮播(replay)不进侧栏,归「我的关注」页(用户口径 2026-09-19)', (
      tester,
    ) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '9001', title: '在播照常'),
              _seedEntry(
                roomId: '9002',
                online: '',
                roomState: 'replay',
                title: '轮播房间',
              ),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 2);
      await _pumpFrames(tester, 3);

      expect(_row('douyu', '9001'), findsOneWidget, reason: '在播照常显示');
      expect(
        _row('douyu', '9002'),
        findsNothing,
        reason: '侧栏只显示直播的,轮播与离线一样只在「我的关注」页出现',
      );
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
      // 视图形态按锚点断言(面板里 'all' 平台图标的四象限色块内部也有
      // 一个 2x2 GridView,按 GridView 类型断言会误中)。
      expect(_card('douyu', '6001'), findsNothing, reason: '默认不是封面网格');

      await tester.tap(find.byKey(const Key('play-side-follow-view-toggle')));
      await _pumpFrames(tester, 3);
      expect(_card('douyu', '6001'), findsOneWidget, reason: '切换后是封面网格');
      expect(
        _row('douyu', '6001'),
        findsNothing,
        reason: '网格视图下不应残留列表行',
      );

      await tester.tap(find.byKey(const Key('play-side-follow-view-toggle')));
      await _pumpFrames(tester, 3);
      expect(_row('douyu', '6001'), findsOneWidget, reason: '可切回列表');
      expect(tester.takeException(), isNull);
    });

    testWidgets('列表行四列:分类 / 主播名 / 标题 / 观看人数(对齐 web RowView)', (
      tester,
    ) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(
                roomId: '7001',
                title: '四列样式的标题',
                anchor: '四列主播',
                online: '2.3万',
              ),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 1);
      await _pumpFrames(tester, 3);

      final rowRect = tester.getRect(_row('douyu', '7001'));
      // 四列内容齐备:分类(种子固定英雄联盟)/ 主播名 / 标题 / 人数。
      expect(find.text('英雄联盟'), findsWidgets);
      expect(find.text('四列主播'), findsOneWidget);
      expect(find.text('四列样式的标题'), findsOneWidget);
      expect(find.text('2.3万'), findsOneWidget);

      // 单行:主播名与标题在同一行内(y 重叠),行高紧凑(<30)。
      final anchorRect = tester.getRect(find.text('四列主播'));
      final titleRect = tester.getRect(find.text('四列样式的标题'));
      expect(titleRect.top, closeTo(anchorRect.top, 8),
          reason: '四列应水平排布在同一行');
      expect(rowRect.height, lessThan(30),
          reason: '对齐 web 行高 1.4rem 的紧凑观感');
      expect(tester.takeException(), isNull);
    });

    testWidgets('切房后右侧仍停在关注 tab(会话级偏好,顶部/左侧/右侧解耦)', (
      tester,
    ) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '5001', title: '待进入的房间'),
            ]),
          });

      final play = await _pumpFollowTab(tester);
      await _awaitFollowRestored(tester, play.container, 1);
      await _pumpFrames(tester, 3);

      // 从关注 tab 点条目切房:路由换成新房间,右侧应仍停在「关注」。
      await tester.tap(_row('douyu', '5001'));
      await _pumpFrames(tester, 6);

      expect(
        play.router.routeInformationProvider.value.uri.path,
        '/douyu/play/5001',
        reason: '前置:切房成功',
      );
      expect(
        find.byKey(const Key('play-side-follow-panel')),
        findsOneWidget,
        reason: '切房后侧栏应仍显示关注面板(不再退回聊天 tab)',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('侧栏头统计区(接通关注条目刷新结果)', () {
    /// 侧栏头内的文本 finder(统计文案只应在信息头内断言,避免与关注行
    /// 的热度徽章等同名文本互相命中)。
    Finder headerTextOf(String text) => find.descendant(
      of: find.byKey(const Key('play-side-header')),
      matching: find.text(text),
    );

    testWidgets('已关注:关注数/人气/VIP/第 3 列显示关注条目刷新回填的值', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(
                roomId: '63136',
                online: '8.9万',
              )
                ..['followers'] = '123456'
                ..['vip'] = '321'
                ..['diamondFans'] = '1300',
            ]),
          });

      final play = await _pumpFollowTab(tester);
      // 深链房间就是种子房间(douyu/63136);统计值来自关注条目,必须等
      // 异步恢复落地后再断言。
      await _awaitFollowRestored(tester, play.container, 1);
      await _pumpFrames(tester, 2);

      expect(find.byKey(const Key('play-side-header')), findsOneWidget);
      // 用户口径(2026-09-20):关注数 ≥1万 显示「X.X万」。
      expect(headerTextOf('关注 12.3万'), findsOneWidget);
      expect(headerTextOf('8.9万'), findsOneWidget, reason: '人气取关注条目 online');
      expect(headerTextOf('321'), findsOneWidget, reason: 'VIP 取关注条目 vip');
      // 第 3 列(tone=svip)取关注条目 diamondFans;用户报的「好多 SVIP
      // 没显示」就是这一列此前根本没渲染。
      expect(
        find.descendant(
          of: find.byKey(const Key('play-side-stat-svip')),
          matching: find.text('1300'),
        ),
        findsOneWidget,
        reason: '第 3 列取 RoomSummary.diamondFans',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('未关注/无数据:三列统计均回退「—」占位(不伪造)', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode(<Object>[]),
          });

      // 88888 不在 fixture 种子(kFixtureRooms.take(6))里:空存储时种子会
      // 落为初始关注,必须避开,才能构造「当前房间未关注」的场景。
      await _pumpFollowTab(tester, location: '/douyu/play/88888');
      await _pumpFrames(tester, 2);

      expect(find.byKey(const Key('play-side-header')), findsOneWidget);
      expect(headerTextOf('关注 —'), findsOneWidget);
      // 人气/VIP/第 3 列三个 _StatValue 在无数据时各显示「—」(不是 0)。
      for (final key in const [
        'play-side-stat-audience',
        'play-side-stat-vip',
        'play-side-stat-svip',
      ]) {
        expect(
          find.descendant(
            of: find.byKey(Key(key)),
            matching: find.text('—'),
          ),
          findsOneWidget,
          reason: '$key 无数据必须显示「—」,不伪造 0',
        );
      }
      // 三列统计 = 信息头内 3 个独立的「—」文本(「关注 —」是单个
      // 拼接文本,不单独匹配 find.text('—'))。
      expect(
        find.descendant(
          of: find.byKey(const Key('play-side-header')),
          matching: find.text('—'),
        ),
        findsNWidgets(3),
        reason: '人气/VIP/第 3 列三列均无数据,显示三个「—」',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('平台未声明的统计列不渲染(SOOP 无 svip 列)', (tester) async {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '63136', site: 'soop'),
            ]),
          });

      await _pumpFollowTab(tester, location: '/soop/play/63136');
      await _pumpFrames(tester, 2);

      expect(find.byKey(const Key('play-side-header')), findsOneWidget);
      // 设计 §3.2:SOOP 声明 roomStats = [audience(观看), vip(订阅)],
      // 无 svip(钻粉)语义 —— 未声明的列不渲染,避免把不存在的能力
      // 显示成空白或 0;取不到值的「已声明」列才显示「—」。
      expect(find.byKey(const Key('play-side-stat-audience')), findsOneWidget);
      expect(find.byKey(const Key('play-side-stat-vip')), findsOneWidget);
      expect(
        find.byKey(const Key('play-side-stat-svip')),
        findsNothing,
        reason: 'SOOP 未声明 svip 列(无 diamondFans),按设计 §3.2 不渲染',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('最窄侧栏(768 视口 → 328px 面板)+ 超长统计值不溢出', (tester) async {
      // _SideHeader 只在非 stack 布局(视口 ≥ 768)出现,328px 是其最窄档;
      // 加第 3 列后四段内容会顶到行宽上限,这里守住 RenderFlex 溢出。
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(<String, Object>{
            'zishu.follow.list': jsonEncode([
              _seedEntry(roomId: '63136', online: '123.4万')
                ..['followers'] = '9876543'
                ..['vip'] = '12.3万'
                ..['diamondFans'] = '12.3万',
            ]),
          });

      final play = await _pumpFollowTab(tester, width: 768);
      await _awaitFollowRestored(tester, play.container, 1);
      await _pumpFrames(tester, 2);

      expect(find.byKey(const Key('play-side-header')), findsOneWidget);
      expect(tester.takeException(), isNull, reason: '四段统计不得溢出');
    });
  });
}
