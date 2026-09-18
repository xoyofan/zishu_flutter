/// 封面「四象限」角标 workflow 测试:角位、圆角与离线覆盖。
///
/// 背景:首页网格卡与播放页侧栏预览卡此前各写一套角标 —— 侧栏卡是
/// 左上★/右上平台/右下热度,与参考实现(`FollowRoomPreviewView.vue`:
/// 左上平台、右上分类、右下热度)不一致。现两处共用
/// `shared/presentation/widgets/cover_badges.dart`,本套用例把角位契约钉死。
///
/// 宿主写法与 browse_home_test / play_follow_panel_test 一致:真实 router +
/// 固定次数 pump(封面图在 VM 中不会真正加载)。
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
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
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
    _expectCorner(
      tester,
      card,
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-promo')),
      ),
      CoverCorner.topRight,
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

  testWidgets('侧栏关注卡四象限:左上平台 / 右上分类 / 右下热度 / 左下★', (tester) async {
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

    final liveCard = find.byKey(
      const ValueKey('play-follow-room-douyu-1001'),
    );
    expect(liveCard, findsOneWidget);
    for (final (key, corner) in <(String, CoverCorner)>[
      ('cover-badge-platform', CoverCorner.topLeft),
      ('cover-badge-category', CoverCorner.topRight),
      ('cover-badge-online', CoverCorner.bottomRight),
    ]) {
      _expectCorner(
        tester,
        liveCard,
        find.descendant(of: liveCard, matching: find.byKey(Key(key))),
        corner,
      );
    }

    // 离线超关:★ 占左下,热度角标不渲染,整封面覆盖「未开播」。
    final offlineCard = find.byKey(
      const ValueKey('play-follow-room-douyu-1002'),
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
}
