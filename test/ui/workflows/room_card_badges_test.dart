/// 封面「四象限」角标 workflow 测试:角位、圆角与离线覆盖。
///
/// 背景:首页网格卡与播放页侧栏预览卡此前各写一套角标 —— 侧栏卡是
/// 左上★/右上平台/右下热度,与参考实现(`FollowRoomPreviewView.vue`:
/// 左上平台、右上分类、右下热度)不一致。现两处共用
/// `shared/presentation/widgets/cover_badges.dart`,本套用例把角位契约钉死。
///
/// 宿主写法与 browse_home_test / play_follow_panel_test 一致:真实 router +
/// 固定次数 pump(封面图在 VM 中不会真正加载)。
///
/// 角位真源(widget 与 web 两侧均已对齐,2026-09-21 复核):
/// - 网格卡 RoomCard.vue:262-273 `.room-card__foot-left { position:absolute;
///   left:0; bottom:0; max-width:72% }` + `:deep(.platform-cover-badge)
///   { border-radius: 0 8px 0 0 }` → 平台 badge **左下**贴角;
///   热度则是另一个 `.cover-online-badge` 在**右下**;
/// - 内部看板 `tasks-ui-refine.md` T3 曾声称「平台 badge 在右下与热度并列」,
///   与真源不符(真源截图 360×640 / 1920×1080 也显示左下平台 + 右下热度),
///   故**不改象限**。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart'
    show RoomState, RoomSummary, StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/widgets/room_card.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_card.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_room_grid.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/cover_badges.dart';

const Duration _kFrame = Duration(milliseconds: 50);

class _FakeLivePlayer implements LivePlayer {
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
  ]) async {}

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

Map<String, Object> _seedEntry({
  required String roomId,
  String title = '测试房间',
  String anchor = '测试主播',
  String online = '1.2万',
  bool isSpecial = false,
}) => {
  'site': 'douyu',
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

Future<void> _pumpFrames(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

Future<({GoRouter router, ProviderContainer container})> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> storage = const <String, Object>{},
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(storage);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  await _pumpFrames(tester, 2);
  final element = tester.element(find.byType(Navigator).first);
  final container = ProviderScope.containerOf(element);
  return (router: container.read(routerProvider), container: container);
}

/// 卡片的封面矩形(卡片内唯一的 16:9 容器)。
Rect _coverRect(WidgetTester tester, Finder card) => tester.getRect(
  find.descendant(of: card, matching: find.byType(AspectRatio)).first,
);

/// 断言角标落在封面指定象限内,且不越出封面(贴角语义)。
void _expectCorner(
  WidgetTester tester,
  Finder card,
  Finder badge,
  CoverCorner corner,
) {
  expect(badge, findsOneWidget, reason: '角标缺失: $corner');
  final cover = _coverRect(tester, card);
  final rect = tester.getRect(badge);
  final left = rect.center.dx < cover.center.dx;
  final top = rect.center.dy < cover.center.dy;
  switch (corner) {
    case CoverCorner.topLeft:
      expect(left && top, isTrue, reason: '应为左上限象: badge=$rect cover=$cover');
    case CoverCorner.topRight:
      expect(!left && top, isTrue, reason: '应为右上限象: badge=$rect cover=$cover');
    case CoverCorner.bottomLeft:
      expect(left && !top, isTrue, reason: '应为左下限象: badge=$rect cover=$cover');
    case CoverCorner.bottomRight:
      expect(!left && !top, isTrue, reason: '应为右下限象: badge=$rect cover=$cover');
  }
  // 贴角不越界(允许 0.5px 亚像素误差)。
  expect(rect.left, greaterThanOrEqualTo(cover.left - 0.5));
  expect(rect.top, greaterThanOrEqualTo(cover.top - 0.5));
  expect(rect.right, lessThanOrEqualTo(cover.right + 0.5));
  expect(rect.bottom, lessThanOrEqualTo(cover.bottom + 0.5));
}

void main() {
  group('CoverBadge 圆角契约', () {
    test('圆角只出现在朝向封面内部的角(对齐 web 8px)', () {
      expect(
        CoverBadge.radiusFor(CoverCorner.topLeft),
        const BorderRadius.only(bottomRight: Radius.circular(8)),
      );
      expect(
        CoverBadge.radiusFor(CoverCorner.topRight),
        const BorderRadius.only(bottomLeft: Radius.circular(8)),
      );
      expect(
        CoverBadge.radiusFor(CoverCorner.bottomLeft),
        const BorderRadius.only(topRight: Radius.circular(8)),
      );
      expect(
        CoverBadge.radiusFor(CoverCorner.bottomRight),
        const BorderRadius.only(topLeft: Radius.circular(8)),
      );
    });
  });

  testWidgets('首页卡四象限:左上分类 / 右上促销 / 右下热度 / 左下平台', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);

    // douyu/63136 的 fixture 带分类「英雄联盟」、热度「42.1万」与促销「官方」。
    final card = find.byKey(const Key('room-card-douyu-63136'));
    expect(card, findsOneWidget);

    _expectCorner(
      tester,
      card,
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-category')),
      ),
      CoverCorner.topLeft,
    );
    // 促销/画质标签不再压在封面右上角,而是封面下方元信息行的「特色 chip」
    // (用户口径:预览图下面第二行是各种特色 chip;同一信息不在两处重复)。
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('room-meta-chip-官方')),
      ),
      findsOneWidget,
      reason: '促销标签应作为元信息行 chip 出现',
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-promo')),
      ),
      findsNothing,
      reason: '封面右上不再重复渲染促销角标',
    );
    _expectCorner(
      tester,
      card,
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-online')),
      ),
      CoverCorner.bottomRight,
    );
    // 平台 badge 贴左下角:真源 `.room-card__foot-left`(RoomCard.vue:262-273,
    // `left:0; bottom:0` + 圆角 `0 8px 0 0`)。看板曾误记为「右下与热度并列」。
    _expectCorner(
      tester,
      card,
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-platform')),
      ),
      CoverCorner.bottomLeft,
    );

    // 角标文案与数据同源。
    expect(
      tester
          .widget<Text>(
            find.descendant(
              of: card,
              matching: find.descendant(
                of: find.byKey(const Key('cover-badge-category')),
                matching: find.text('英雄联盟'),
              ),
            ),
          )
          .data,
      '英雄联盟',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏关注(用户口径 2026-09-19):默认列表只显在播;网格在播卡四象限', (
    tester,
  ) async {
    final app = await _pumpApp(
      tester,
      storage: {
        'zishu.follow.list': jsonEncode([
          _seedEntry(roomId: '1001', title: '在播房', online: '2.3万'),
          _seedEntry(roomId: '1002', title: '离线超关', online: '', isSpecial: true),
        ]),
      },
    );
    app.router.go('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    await tester.tap(find.byKey(const Key('play-side-tab-follow')));
    await _pumpFrames(tester, 8);

    // 口径:离线(含超关)在侧栏任何视图都不出现。
    expect(
      find.byKey(const Key('follow-entry-douyu-1002')),
      findsNothing,
      reason: '离线超关不再保留(用户口径:不显示没开播的)',
    );
    // 默认视图为列表(每条一行):与「我的关注」页共用的四列单行。
    expect(
      find.byKey(const Key('follow-entry-douyu-1001')),
      findsOneWidget,
    );

    // 切到封面网格:与「我的关注」页共用的紧凑卡片(FollowEntryCard)。
    // 注:PlayRoomCard 的四象限角标契约由其下方「直 pump PlayRoomGrid」用例锁定。
    await tester.tap(find.byKey(const Key('play-side-follow-view-toggle')));
    await _pumpFrames(tester, 8);

    final liveCard = find.descendant(
      of: find.byType(FollowEntryCard),
      matching: find.byKey(const Key('follow-entry-douyu-1001')),
    );
    expect(liveCard, findsOneWidget, reason: '网格视图应渲染共享紧凑卡片');
    expect(tester.takeException(), isNull);
  });

  testWidgets('离线关注卡渲染:★ 左下 + 未开播遮罩(直 pump,不经侧栏数据链)', (
    tester,
  ) async {
    // 侧栏口径只显在播后,离线卡的角标/遮罩逻辑不再经面板触达;
    // 直 pump PlayRoomGrid 钉住渲染契约,防口径回摆时丢行为。
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: ZishuTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: PlayRoomGrid(
                rooms: const [
                  RoomSummary(
                    site: 'douyu',
                    roomId: '9002',
                    title: '离线超关',
                    anchorName: '测试主播',
                    cid: '1',
                    category: '英雄联盟',
                    online: '',
                    cover: '',
                  ),
                ],
                superKeys: const {'douyu:9002'},
                // 与侧栏关注面板同前缀:卡面键 = play-follow-room-douyu-9002。
                keyPrefix: 'play-follow-room-',
              ),
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester, 2);

    final offlineCard = find.byKey(
      const ValueKey('play-follow-room-douyu-9002'),
    );
    expect(offlineCard, findsOneWidget);
    _expectCorner(
      tester,
      offlineCard,
      find.descendant(
        of: offlineCard,
        matching: find.byKey(const Key('cover-badge-special')),
      ),
      CoverCorner.bottomLeft,
    );
    expect(
      find.descendant(
        of: offlineCard,
        matching: find.byKey(const Key('cover-badge-online')),
      ),
      findsNothing,
    );
    final overlay = find.descendant(
      of: offlineCard,
      matching: find.byKey(const Key('cover-offline-overlay')),
    );
    expect(overlay, findsOneWidget);
    final overlayRect = tester.getRect(overlay);
    final coverRect = _coverRect(tester, offlineCard);
    expect(overlayRect.center.dx, closeTo(coverRect.center.dx, 0.5));
    expect(overlayRect.center.dy, closeTo(coverRect.center.dy, 0.5));
    expect(
      find.descendant(of: overlay, matching: find.text('未开播')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('侧栏推荐卡:左上平台 / 右上分类(无 ★ 角标)', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/douyu/play/63136');
    await _pumpFrames(tester, 4);
    await tester.tap(find.byKey(const Key('play-side-tab-recommend')));
    await _pumpFrames(tester, 8);

    final card = find
        .byWidgetPredicate(
          (widget) =>
              widget.key is ValueKey<String> &&
              (widget.key as ValueKey<String>).value.startsWith(
                'play-recommend-room-',
              ),
        )
        .first;
    expect(card, findsOneWidget);
    _expectCorner(
      tester,
      card,
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-platform')),
      ),
      CoverCorner.topLeft,
    );
    _expectCorner(
      tester,
      card,
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-category')),
      ),
      CoverCorner.topRight,
    );
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-special')),
      ),
      findsNothing,
      reason: '推荐卡不传 superKeys,不应出现 ★',
    );
    expect(tester.takeException(), isNull);
  });

  group('首页网格卡离线遮罩(对齐 web .room-card__offline)', () {
    /// 组件级宿主:不走全 app(首页 fixture 全是在播房,塞离线房会改变
    /// 网格内容波及大量布局/hover 用例)。深浅主题各验一遍遮罩可读性。
    Widget host(RoomSummary room) => ProviderScope(
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: Scaffold(
          body: SizedBox(width: 320, child: RoomCard(room: room)),
        ),
      ),
    );

    testWidgets('离线房:整封面遮罩 + 「未开播」,不渲染热度角标', (tester) async {
      await tester.pumpWidget(
        host(
          const RoomSummary(
            site: 'douyu',
            roomId: '9001',
            title: '离线房',
            anchorName: '测试主播',
            cid: '1',
            category: '英雄联盟',
            online: '',
            cover: '',
          ),
        ),
      );
      await _pumpFrames(tester, 2);

      final overlay = find.byKey(const Key('room-card-offline'));
      expect(overlay, findsOneWidget, reason: '离线房应渲染整封面遮罩');
      expect(
        find.descendant(of: overlay, matching: find.text('未开播')),
        findsOneWidget,
      );

      // 遮罩盖满封面(16:9 容器),而非只有文字大小。
      final coverRect = tester.getRect(
        find.descendant(
          of: find.byKey(const Key('room-card-douyu-9001')),
          matching: find.byType(AspectRatio),
        ),
      );
      final overlayRect = tester.getRect(overlay);
      expect(overlayRect.left, closeTo(coverRect.left, 0.5));
      expect(overlayRect.top, closeTo(coverRect.top, 0.5));
      expect(overlayRect.right, closeTo(coverRect.right, 0.5));
      expect(overlayRect.bottom, closeTo(coverRect.bottom, 0.5));

      // 离线不渲染热度角标(与既有判据一致)。
      expect(
        find.byKey(const Key('cover-badge-online')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('在播房:不渲染离线遮罩,分类角标照常', (tester) async {
      await tester.pumpWidget(
        host(
          const RoomSummary(
            site: 'douyu',
            roomId: '9002',
            title: '在播房',
            anchorName: '测试主播',
            cid: '1',
            category: '英雄联盟',
            online: '1.2万',
            cover: '',
          ),
        ),
      );
      await _pumpFrames(tester, 2);

      expect(find.byKey(const Key('room-card-offline')), findsNothing);
      expect(find.byKey(const Key('cover-badge-category')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('轮播房:不渲染离线遮罩,显示轮播状态', (tester) async {
      await tester.pumpWidget(
        host(
          const RoomSummary(
            site: 'douyu',
            roomId: '9003',
            title: '轮播房',
            anchorName: '测试主播',
            cid: '1',
            category: '英雄联盟',
            online: '',
            cover: '',
            roomState: RoomState.replay,
          ),
        ),
      );
      await _pumpFrames(tester, 2);

      expect(find.byKey(const Key('room-card-offline')), findsNothing);
      expect(find.text('轮播'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
