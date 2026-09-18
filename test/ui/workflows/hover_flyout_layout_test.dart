/// hover 浮层布局测试:列数按实际条目收敛、宽度随列数收缩并夹在
/// `[12rem, 56rem]`,且不越出视口。
///
/// 背景(用户反馈):「有的没有多余列最后空列大片空白,应该按实际列数来」——
/// 旧实现三个浮层都用**固定宽度**(平台 560 / 关注 336 / 我的分类 320)配
/// **固定列数**(关注 7 列),条目少时右侧留整片空列。
///
/// 规格来源:web `.nav-platform-menu { min-width: 12rem;
/// max-width: min(92vw, 56rem) }` —— 宽度由内容决定,不写死中间值。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' as lp;
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 浮层规格常量(与 app_shell.dart 内实现同源,写在测试里做交叉校验)。
const double _kFlyoutMinWidth = 192; // 12rem
const double _kFlyoutMaxWidth = 896; // 56rem
const double _kPlatformColumnWidth = 67.2;
const double _kPlatformChrome = 9.6 * 2 + 2;
const double _kFollowSlotWidth = 45.9;
const double _kFollowColumnGap = 0.96;
const double _kFollowChrome = 3.52 * 2 + 2;

class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(lp.StreamLine line,
          [List<lp.StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

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

lp.RoomSummary _room(int index, {bool live = true}) => lp.RoomSummary(
  site: 'douyu',
  roomId: 'nav$index',
  title: '房间$index',
  anchorName: '主播$index',
  cid: '1',
  category: '英雄联盟',
  online: live ? '$index万' : '',
  cover: '',
);

/// 指定条数的在播关注:用于验证「列数 = 实际条目数」。
class _LiveFollowController extends FollowController {
  _LiveFollowController(this.count);

  final int count;

  @override
  List<FollowEntry> build() => [
    for (var i = 0; i < count; i++)
      FollowEntry(
        room: _room(i),
        isSpecial: false,
        remindOn: false,
        followedAt: DateTime(2026, 1, 1),
      ),
  ];
}

Future<void> _pump(WidgetTester tester, Size size, {int? liveCount}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        if (liveCount != null)
          followProvider.overrideWith(() => _LiveFollowController(liveCount)),
      ],
      child: const WindowsApp(),
    ),
  );
  await _frames(tester, 3);
}

Future<void> _frames(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// 悬停到某个导航项并等浮层内容落地(分类是异步 provider)。
///
/// **每个用例只悬停一次**:Flutter 的 MouseTracker 只跟踪一个鼠标指针,
/// 同用例内第二次 addPointer 会触发其内部断言。
Future<void> _hover(WidgetTester tester, Key key) async {
  final finder = find.byKey(key);
  await tester.ensureVisible(finder);
  final center = tester.getCenter(finder);
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: center);
  await gesture.moveTo(center);
  addTearDown(() => gesture.removePointer());
  await _frames(tester, 14);
}

/// 取锚点子树里所有叶子的左边界集合(不同 x 即不同列)。
Set<double> _columnLefts(WidgetTester tester, Finder finder) => {
  for (final e in finder.evaluate())
    tester.getTopLeft(find.byWidget(e.widget)).dx.roundToDouble(),
};

void main() {
  testWidgets('关注浮层:2 条在播 → 列数 = 2,宽度收缩到 min 且不再固定 336', (tester) async {
    await _pump(tester, const Size(1440, 900), liveCount: 2);
    await _hover(tester, const Key('nav-follow'));

    final panel = find.byKey(const Key('follow-flyout-panel'));
    expect(panel, findsOneWidget, reason: '应渲染关注浮层');
    final width = tester.getRect(panel).width;

    // 2 列理论宽 = chrome + 2×45.9 + 1×0.96 ≈ 101.8 → 夹到 min 192。
    expect(width, greaterThanOrEqualTo(_kFlyoutMinWidth - 0.01),
        reason: '不得低于 min-width 12rem');
    expect(width, lessThan(336),
        reason: '宽度应随列数收缩,不再固定 336(旧实现)');

    // 列数 = 条目数:两个头像格同一行、两个不同 x。
    final avatars = find.byWidgetPredicate(
      (w) => w.key is Key && w.key.toString().contains('nav-follow-avatar-'),
    );
    expect(avatars.evaluate().length, 2, reason: '只有 2 条在播就渲染 2 个');
    expect(_columnLefts(tester, avatars).length, 2, reason: '两格应在两列');
    expect(tester.takeException(), isNull);
  });

  testWidgets('关注浮层:5 条在播(fixture)→ 5 列,右侧不留第 6/7 列空位', (tester) async {
    // fixture 种子里 6 条关注、1 条离线 → 5 条在播。
    await _pump(tester, const Size(1440, 900));
    await _hover(tester, const Key('nav-follow'));

    final panel = find.byKey(const Key('follow-flyout-panel'));
    final rect = tester.getRect(panel);
    final expectedWidth =
        _kFollowChrome + 5 * _kFollowSlotWidth + 4 * _kFollowColumnGap;
    expect(rect.width, closeTo(expectedWidth, 1.5),
        reason: '宽度 = 列宽×实际列数 + 内边距(5 列 ≈ $expectedWidth)');
    expect(rect.width, lessThan(336), reason: '比旧固定 336 更窄');

    final grid = tester.widget<GridView>(
      find.descendant(of: panel, matching: find.byType(GridView)),
    );
    final delegate =
        grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
    expect(delegate.crossAxisCount, 5,
        reason: '5 条在播应排成 5 列(不是固定 7 列)');

    // 网格实际占满面板宽度:最后一列的右边界贴近面板右内边。
    final gridRect = tester.getRect(
      find.descendant(of: panel, matching: find.byType(GridView)),
    );
    expect(gridRect.right, lessThanOrEqualTo(rect.right + 0.01));
    expect(gridRect.width, closeTo(rect.width - _kFollowChrome, 2.0),
        reason: '列数 × 列宽应正好撑满面板,不留空列');
    expect(tester.takeException(), isNull);
  });

  testWidgets('平台分类浮层:宽度随分组列数收缩(≈3 列),夹在 min/max 之间', (tester) async {
    await _pump(tester, const Size(1440, 900));
    await _hover(tester, const Key('platform-tab-douyu'));

    final panel = find.byKey(const Key('platform-flyout-panel'));
    expect(panel, findsOneWidget, reason: '应渲染平台分类浮层');
    final rect = tester.getRect(panel);

    // fixture 3 组 → 3 列:chrome + 3×67.2 ≈ 222.8。
    final expectedWidth = _kPlatformChrome + 3 * _kPlatformColumnWidth;
    expect(rect.width, closeTo(expectedWidth, 2.0),
        reason: '宽度应由列数推出(3 列 ≈ $expectedWidth),而不是固定 560');
    expect(rect.width, greaterThanOrEqualTo(_kFlyoutMinWidth - 0.01));
    expect(rect.width, lessThanOrEqualTo(_kFlyoutMaxWidth + 0.01));
    expect(rect.width, lessThan(560), reason: '比旧固定 560 更窄');

    // 分类 chip 落在 3 个不同列上(一组一列)。
    final chips = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('flyout-category-'),
    );
    expect(chips.evaluate(), isNotEmpty, reason: '浮层应列出分类条目');
    expect(_columnLefts(tester, chips).length, 3,
        reason: '3 个分组应为 3 列(列数 = 实际列数)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('关注浮层不越出视口:窄视口下被夹在视口内', (tester) async {
    // 800px 宽(>=768 才有顶栏 hover 浮层):5 列理论宽 ≈243.3 本就在视口内,
    // 断言的是「两侧不出界」这条不变量(夹取逻辑在 _HoverOverlay)。
    await _pump(tester, const Size(800, 700), liveCount: 5);
    await _hover(tester, const Key('nav-follow'));

    final follow = tester.getRect(find.byKey(const Key('follow-flyout-panel')));
    expect(follow.left, greaterThanOrEqualTo(0));
    expect(follow.right, lessThanOrEqualTo(800 + 0.01));
    expect(follow.width, lessThanOrEqualTo(800 - 16 + 0.01),
        reason: '宽度不得超过 视口-16(HoverOverlay 夹取)');
    expect(tester.takeException(), isNull);
  });

  testWidgets('平台浮层不越出视口:窄视口下被夹在视口内', (tester) async {
    await _pump(tester, const Size(800, 700));
    await _hover(tester, const Key('platform-tab-douyu'));

    final platform =
        tester.getRect(find.byKey(const Key('platform-flyout-panel')));
    expect(platform.left, greaterThanOrEqualTo(0));
    expect(platform.right, lessThanOrEqualTo(800 + 0.01));
    expect(tester.takeException(), isNull);
  });

  testWidgets('我的分类浮层:chip 用 Wrap(天然无空列),宽度仍为 min(92vw, 18.5rem)', (tester) async {
    await _pump(tester, const Size(1440, 900));
    await _hover(tester, const Key('nav-my-category'));

    final panel = find.byKey(const Key('my-category-flyout-panel'));
    expect(panel, findsOneWidget, reason: '应渲染我的分类浮层');
    final rect = tester.getRect(panel);
    expect(rect.width, closeTo(18.5 * 16, 1.5),
        reason: 'web `.nav-my-cat-flyout { width: min(92vw, 18.5rem) }`,桌面为 296');

    // chip 区是 Wrap:所有 chip 落在面板内(不会因为固定列数留空列)。
    final chips = find.byWidgetPredicate(
      (w) => w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('my-cat-chip-'),
    );
    for (final e in chips.evaluate()) {
      final r = tester.getRect(find.byWidget(e.widget));
      expect(r.left, greaterThanOrEqualTo(rect.left - 0.01));
      expect(r.right, lessThanOrEqualTo(rect.right + 0.01));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('浮层宽度上界仍受 56rem 约束(理论值越界时夹到 max)', (tester) async {
    // 关注浮层给 12 条在播:列数被夹到 7,宽度 = chrome + 7×45.9 + 6×0.96 ≈ 337,
    // 远小于 56rem —— 断言「列数上限 7」与「宽度 ≤ max」。
    await _pump(tester, const Size(1440, 900), liveCount: 12);
    await _hover(tester, const Key('nav-follow'));

    final panel = find.byKey(const Key('follow-flyout-panel'));
    final rect = tester.getRect(panel);
    final expectedWidth =
        _kFollowChrome + 7 * _kFollowSlotWidth + 6 * _kFollowColumnGap;
    expect(rect.width, closeTo(expectedWidth, 1.5),
        reason: '超过 7 条时列数夹到上限 7,宽度不再增长(≈$expectedWidth)');
    expect(rect.width, lessThanOrEqualTo(_kFlyoutMaxWidth));

    final avatars = find.byWidgetPredicate(
      (w) => w.key is Key && w.key.toString().contains('nav-follow-avatar-'),
    );
    // 12 条在播但只展示前 3 个头像(web NAV_FOLLOW_AVATAR_LIMIT),
    // 浮层网格里仍按 7 列排满 12 项 → 列数上限 7。
    final lefts = _columnLefts(tester, avatars);
    expect(lefts.length, lessThanOrEqualTo(7));
    expect(tester.takeException(), isNull);
  });
}
