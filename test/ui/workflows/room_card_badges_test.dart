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
/// 角位真源(widget 与 web 两侧均已对齐,2026-09 房间卡改版后口径):
/// - 首页网格卡 RoomCard 四角:左上**分类实底**、右上**平台身份线框 tag**
///   (room.identityLabel,空不渲染)、左下**主播昵称**(平台品牌色底,
///   平台名角标已移除)、右下**热度**;
/// - 侧栏预览卡(PlayRoomCard/FollowEntryCard)沿用各自既有角位不变;
/// - 内部看板 `tasks-ui-refine.md` T3 曾声称「平台 badge 在右下与热度并列」,
///   与真源不符,故**不改象限**;
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart'
    show
        CategoryResult,
        RoomListResult,
        RoomRecord,
        RoomState,
        SiteChip,
        SiteChipKind,
        StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/widgets/room_card.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_card.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_room_grid.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/platform_brands.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/cover_badges.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/outline_chip.dart';
import 'package:zishu_flutter/src/shared/presentation/zishu_tokens.dart';

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

/// 只带 Twitch 卡片 chips 的浏览源:fixture 房间无 [SiteChip],Stage 2 的
/// 卡片 chip 用例需要可控的 chips 数据(语言/标签、可点/不可点、乱序输入)。
class _ChipBrowseSource implements BrowseSource {
  const _ChipBrowseSource({required this.withTag});

  /// true → 房间带可点 tag chip(filterCid 'tag:x');false → 只带不可点语言 chip。
  final bool withTag;

  @override
  Future<CategoryResult> fetchCategories(String site) async =>
      CategoryResult(site: site, groups: const []);

  @override
  Future<RoomListResult> fetchRooms({
    required String site,
    String? cid,
    int page = 1,
    int? limit,
  }) async => RoomListResult(
    page: page,
    hasMore: false,
    rooms: [
      RoomRecord(
        site: 'twitch',
        roomId: '9001',
        roomState: RoomState.live,
        title: '标签房',
        anchorName: '标签主播',
        cid: 'g1',
        category: '分类',
        audience: '1.2万',
        cover: '',
        // 故意乱序输入:language 在前,验证渲染按 SiteChipKind 排序(tag 前 language 后)。
        chips: [
          const SiteChip(
            id: 'EN',
            name: '英语',
            kind: SiteChipKind.language,
          ),
          if (withTag)
            const SiteChip(
              id: 'x',
              name: '策略',
              kind: SiteChipKind.tag,
              // 与 Stage 1 口径一致:filterCid 含 tag: 前缀,直接喂 fetchRooms。
              filterCid: 'tag:x',
            ),
        ],
      ),
    ],
  );
}

Future<({GoRouter router, ProviderContainer container})> _pumpApp(
  WidgetTester tester, {
  Map<String, Object> storage = const <String, Object>{},
  BrowseSource? browseSource,
}) async {
  SharedPreferencesAsyncPlatform.instance =
      InMemorySharedPreferencesAsync.withData(storage);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        if (browseSource != null)
          browseSourceProvider.overrideWithValue(browseSource),
      ],
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

  testWidgets('首页卡四角:左上分类实底 / 右上身份(空不渲染) / 左下昵称 / 右下热度', (tester) async {
    final app = await _pumpApp(tester);
    app.router.go('/all');
    await _pumpFrames(tester, 3);

    // douyu/63136 的 fixture 带分类「英雄联盟」、热度「42.1万」与促销「官方」。
    final card = find.byKey(const Key('room-card-douyu-63136'));
    expect(card, findsOneWidget);

    // 左上:分类实底角标(保持现状,不改线框、不挪位)。
    _expectCorner(
      tester,
      card,
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-category')),
      ),
      CoverCorner.topLeft,
    );
    // 右上:平台身份线框 tag —— fixture 无 identityLabel,不渲染(可空)。
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-identity')),
      ),
      findsNothing,
      reason: 'fixture 房间无 identityLabel,右上身份 tag 不渲染',
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
    // 平台角标已移除(用户口径 2026-09:全平台封面左下不再显示平台 tag)。
    expect(
      find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-platform')),
      ),
      findsNothing,
      reason: '平台角标移除,左下让给主播昵称',
    );

    // 左下:主播昵称,平台品牌色底 + chipForeground 文字(fixture 主播「神超」)。
    final anchorBadge = find.descendant(
      of: card,
      matching: find.byKey(const Key('cover-badge-anchor')),
    );
    expect(anchorBadge, findsOneWidget, reason: '封面左下渲染主播昵称');
    _expectCorner(tester, card, anchorBadge, CoverCorner.bottomLeft);
    final brand = PlatformBrandCatalog.byId('douyu')!;
    final badgeBox = tester.widget<DecoratedBox>(
      find
          .descendant(of: anchorBadge, matching: find.byType(DecoratedBox))
          .first,
    );
    expect(
      (badgeBox.decoration as BoxDecoration).color,
      brand.color,
      reason: '昵称底色 = 平台品牌色',
    );
    final anchorText = find.descendant(of: card, matching: find.text('神超'));
    expect(anchorText, findsOneWidget);
    final anchorStyle = tester
        .widget<DefaultTextStyle>(
          find
              .ancestor(of: anchorText, matching: find.byType(DefaultTextStyle))
              .first,
        )
        .style;
    expect(anchorStyle.color, brand.chipForeground, reason: '昵称文字色 = chipForeground');
    final anchorWidget = tester.widget<Text>(anchorText);
    expect(anchorWidget.maxLines, 1, reason: '单行');
    expect(anchorWidget.overflow, TextOverflow.ellipsis, reason: '单行省略号');

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

  group('封面四角 tag(2026-09 改版)', () {
    /// 只泵一张 RoomCard 的组件宿主(无 router)。
    Future<void> pumpCard(WidgetTester tester, RoomRecord room) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ZishuTheme.dark(),
            home: Scaffold(
              body: SizedBox(width: 320, child: RoomCard(room: room)),
            ),
          ),
        ),
      );
      await _pumpFrames(tester, 2);
    }

    testWidgets('右上身份线框 tag:有值渲染于右上,文案 = identityLabel,不可点', (tester) async {
      await pumpCard(
        tester,
        RoomRecord(
          site: 'huya',
          roomId: '9101',
          roomState: RoomState.live,
          title: '身份房',
          anchorName: '主播',
          cid: '1',
          category: '英雄联盟',
          audience: '1.2万',
          cover: '',
          identityLabel: '超级明星',
        ),
      );

      final card = find.byKey(const Key('room-card-huya-9101'));
      final identity = find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-identity')),
      );
      expect(identity, findsOneWidget, reason: 'identityLabel 非空应渲染右上 tag');
      _expectCorner(tester, card, identity, CoverCorner.topRight);
      // 线框 chip 视觉 = OutlineChip;文案 = identityLabel;不做跳转。
      final chip = tester.widget<OutlineChip>(identity);
      expect(chip.label, '超级明星', reason: '文案 = identityLabel');
      expect(chip.onTap, isNull, reason: '身份 tag 先不做跳转');
      expect(
        find.descendant(of: identity, matching: find.byType(InkWell)),
        findsNothing,
        reason: '不可点 → 无 InkWell',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('identityLabel 空串:右上 tag 不渲染', (tester) async {
      await pumpCard(
        tester,
        RoomRecord(
          site: 'huya',
          roomId: '9102',
          roomState: RoomState.live,
          title: '无身份房',
          anchorName: '主播',
          cid: '1',
          category: '英雄联盟',
          audience: '1.2万',
          cover: '',
          identityLabel: '',
        ),
      );

      expect(
        find.byKey(const Key('cover-badge-identity')),
        findsNothing,
        reason: '空 identityLabel 不渲染',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('左下昵称条:无独立手势,点击落到卡片整体 onTap(进房)', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ZishuTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 320,
                child: RoomCard(
                  room: RoomRecord(
                    site: 'douyu',
                    roomId: '9103',
                    roomState: RoomState.live,
                    title: '点击房',
                    anchorName: '点点',
                    cid: '1',
                    category: '英雄联盟',
                    audience: '1万',
                    cover: '',
                  ),
                  onTap: () => taps++,
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpFrames(tester, 2);

      final anchorBadge = find.byKey(const Key('cover-badge-anchor'));
      expect(anchorBadge, findsOneWidget);
      expect(
        find.descendant(of: anchorBadge, matching: find.byType(InkWell)),
        findsNothing,
        reason: '昵称条不单独包手势',
      );
      await tester.tap(anchorBadge);
      await _pumpFrames(tester, 2);
      expect(taps, 1, reason: '封面点击仍进房(card onTap)');
      expect(tester.takeException(), isNull);
    });
  });

  group('斗鱼卡:左上角标 → 右上身份位 + 特色 chips(2026-09-26)', () {
    /// 只泵一张 RoomCard 的组件宿主(无 router)。
    Future<void> pumpCard(WidgetTester tester, RoomRecord room, {double width = 320}) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ZishuTheme.dark(),
            home: Scaffold(
              body: SizedBox(width: width, child: RoomCard(room: room)),
            ),
          ),
        ),
      );
      await _pumpFrames(tester, 2);
    }

    RoomRecord douyuRoom({List<SiteChip> chips = const []}) => RoomRecord(
      site: 'douyu',
      roomId: '9200',
      roomState: RoomState.live,
      title: '斗鱼房',
      anchorName: '斗鱼主播',
      cid: '2',
      category: '炉石传说',
      audience: '225.7万',
      cover: '',
      identityLabel: '全站榜TOP10',
      chips: chips,
    );

    testWidgets('icv3 文案整文渲染在封面右上(不被 6 字规则砍掉)', (tester) async {
      await pumpCard(tester, douyuRoom());

      final card = find.byKey(const Key('room-card-douyu-9200'));
      final identity = find.descendant(
        of: card,
        matching: find.byKey(const Key('cover-badge-identity')),
      );
      expect(
        tester.widget<OutlineChip>(identity).label,
        '全站榜TOP10',
        reason: '官网角标整文渲染(实测最宽 8 字),解析层不截断',
      );
      _expectCorner(tester, card, identity, CoverCorner.topRight);
      expect(tester.takeException(), isNull);
    });

    testWidgets('roomLabel 三个 chips 渲成封面下方 chip 行,不可点', (tester) async {
      await pumpCard(
        tester,
        douyuRoom(
          chips: const [
            SiteChip(id: 'dy:炉石金牌讲师', name: '炉石金牌讲师', kind: SiteChipKind.tag),
            SiteChip(id: 'dy:竞技场钉子户', name: '竞技场钉子户', kind: SiteChipKind.tag),
            SiteChip(id: 'dy:天梯高玩', name: '天梯高玩', kind: SiteChipKind.tag),
          ],
        ),
      );

      final card = find.byKey(const Key('room-card-douyu-9200'));
      for (final name in ['炉石金牌讲师', '竞技场钉子户', '天梯高玩']) {
        final chip = find.descendant(
          of: card,
          matching: find.byKey(Key('room-meta-chip-$name')),
        );
        expect(chip, findsOneWidget, reason: 'chip $name 应渲染');
        expect(
          find.descendant(of: chip, matching: find.byType(InkWell)),
          findsNothing,
          reason: '斗鱼特色标签无分类 id,不可点',
        );
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('最窄网格列 + 大字体下 chips 行仍不溢出、不换行', (tester) async {
      // 4 列 @768px 是实测最窄列(卡片 ~175px,内边距后 ~159px);
      // 文字缩放 1.3 是 DESIGN.md 元信息区预算里的上限档。
      tester.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      await pumpCard(
        tester,
        douyuRoom(
          chips: const [
            SiteChip(id: 'dy:炉石金牌讲师', name: '炉石金牌讲师', kind: SiteChipKind.tag),
            SiteChip(id: 'dy:竞技场钉子户', name: '竞技场钉子户', kind: SiteChipKind.tag),
            SiteChip(id: 'dy:竞技场高玩', name: '竞技场高玩', kind: SiteChipKind.tag),
          ],
        ),
        width: 175,
      );

      // 无 overflow 异常 + chips 仍在同一行(不因压缩换行)。
      expect(tester.takeException(), isNull, reason: 'chips 行不得溢出');
      final card = find.byKey(const Key('room-card-douyu-9200'));
      final tops = ['炉石金牌讲师', '竞技场钉子户', '竞技场高玩']
          .map(
            (name) => tester
                .getTopLeft(
                  find.descendant(
                    of: card,
                    matching: find.byKey(Key('room-meta-chip-$name')),
                  ),
                )
                .dy,
          )
          .toSet();
      expect(tops, hasLength(1), reason: '三个 chip 必在同一行(第 2 行定高 17px)');
      expect(
        tester.getSize(card).width,
        175,
        reason: '守卫:本用例跑在最窄网格列宽度上',
      );
    });
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
                rooms: [
                  RoomRecord(
                    site: 'douyu',
                    roomId: '9002',
                    roomState: RoomState.offline,
                    title: '离线超关',
                    anchorName: '测试主播',
                    cid: '1',
                    category: '英雄联盟',
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
    Widget host(RoomRecord room) => ProviderScope(
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
          RoomRecord(
            site: 'douyu',
            roomId: '9001',
            roomState: RoomState.offline,
            title: '离线房',
            anchorName: '测试主播',
            cid: '1',
            category: '英雄联盟',
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
          RoomRecord(
            site: 'douyu',
            roomId: '9002',
            roomState: RoomState.live,
            title: '在播房',
            anchorName: '测试主播',
            cid: '1',
            category: '英雄联盟',
            audience: '1.2万',
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
          RoomRecord(
            site: 'douyu',
            roomId: '9003',
            roomState: RoomState.replay,
            title: '轮播房',
            anchorName: '测试主播',
            cid: '1',
            category: '英雄联盟',
            cover: '',
          ),
        ),
      );
      await _pumpFrames(tester, 2);

      expect(find.byKey(const Key('room-card-offline')), findsNothing);
      expect(find.text('轮播'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('卡片线框 chip(Stage 2:Twitch tags)', () {
    /// 只泵一张 RoomCard 的组件宿主(无 router,验证渲染与回归护栏)。
    Future<void> pumpCard(WidgetTester tester, RoomRecord room) async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ZishuTheme.dark(),
            home: Scaffold(
              body: SizedBox(width: 360, child: RoomCard(room: room)),
            ),
          ),
        ),
      );
      await _pumpFrames(tester, 2);
    }

    testWidgets('chips 行:标题下一行(meta 第 2 行),主播名在封面左下', (tester) async {
      final app = await _pumpApp(
        tester,
        browseSource: const _ChipBrowseSource(withTag: true),
      );
      app.router.go('/twitch');
      await _pumpFrames(tester, 5);

      final card = find.byKey(const Key('room-card-twitch-9001'));
      expect(card, findsOneWidget);
      final title = find.descendant(of: card, matching: find.text('标签房'));
      final anchor = find.descendant(
        of: card,
        matching: find.text('标签主播'),
      );
      final tagChip = find.byKey(const Key('room-meta-chip-策略'));
      expect(title, findsOneWidget, reason: 'meta 第 1 行标题');
      expect(anchor, findsOneWidget, reason: '主播名移到封面左下,仍在卡内');
      expect(tagChip, findsOneWidget, reason: 'chips 在 meta 第 2 行');

      // 昵称渲染在封面(16:9)高度范围内,不占 meta 文本区。
      final cover = _coverRect(tester, card);
      final anchorRect = tester.getRect(anchor);
      expect(
        anchorRect.bottom,
        lessThanOrEqualTo(cover.bottom + 0.5),
        reason: '昵称应在封面高度范围内',
      );
      // 两行契约:chip 的 y 坐标严格大于标题底部(不同行)。
      final titleBottom = tester.getBottomLeft(title).dy;
      final chipTop = tester.getTopLeft(tagChip).dy;
      expect(chipTop, greaterThan(titleBottom), reason: 'chip 应在标题下一行');
      expect(tester.takeException(), isNull);
    });

    testWidgets('可点 tag chip:线框样式,点击导航到过滤列表且不冒泡进房', (tester) async {
      final app = await _pumpApp(
        tester,
        browseSource: const _ChipBrowseSource(withTag: true),
      );
      app.router.go('/twitch');
      await _pumpFrames(tester, 5);

      final card = find.byKey(const Key('room-card-twitch-9001'));
      expect(card, findsOneWidget);

      // 排序:乱序输入(language 先)也渲染为 tag 前、language 后。
      final chips = tester.widgetList<OutlineChip>(
        find.descendant(of: card, matching: find.byType(OutlineChip)),
      );
      expect(
        chips.map((c) => c.label).toList(),
        ['策略', '英语'],
        reason: '按 SiteChipKind 排序:tag 在前、language 在后',
      );

      final tagChip = find.byKey(const Key('room-meta-chip-策略'));
      expect(tagChip, findsOneWidget, reason: '可点 tag chip 应渲染');

      // 线框样式:透明底 + tokens.border 1px 描边 + AppRadius.allSm + caption 字号。
      final container = tester.widget<Container>(
        find.descendant(of: tagChip, matching: find.byType(Container)).first,
      );
      final deco = container.decoration! as BoxDecoration;
      expect(deco.color, isNull, reason: '线框 chip 无填充底');
      expect(deco.border?.top.color, ZishuTokens.dark.border);
      expect(deco.border?.top.width, 1.0);
      expect(deco.borderRadius, AppRadius.allSm);
      final text = tester.widget<Text>(
        find.descendant(of: tagChip, matching: find.byType(Text)).first,
      );
      expect(text.style?.fontSize, AppFontSize.caption);

      // 可点:包 InkWell 且 onTap 非空。
      final inkWell = find.descendant(of: tagChip, matching: find.byType(InkWell));
      expect(inkWell, findsOneWidget);
      expect(tester.widget<InkWell>(inkWell).onTap, isNotNull);

      await tester.tap(tagChip);
      await _pumpFrames(tester, 5);

      expect(
        app.router.routeInformationProvider.value.uri.path,
        '/twitch/category/tag%3Ax',
        reason: '点击 tag chip 应导航到 /twitch/category/tag%3Ax',
      );
      expect(
        find.byType(PlayView),
        findsNothing,
        reason: '点击 chip 必须阻止冒泡到卡片整体 onTap(不得同时进房)',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('不可点 language chip:渲染但无 InkWell/点击不导航', (tester) async {
      await pumpCard(
        tester,
        RoomRecord(
          site: 'twitch',
          roomId: '9002',
          roomState: RoomState.live,
          title: '语言房',
          anchorName: '语言主播',
          cid: 'g1',
          category: '分类',
          audience: '1.2万',
          cover: '',
          chips: const [
            SiteChip(id: 'EN', name: '英语', kind: SiteChipKind.language),
          ],
        ),
      );

      final chip = find.byKey(const Key('room-meta-chip-英语'));
      expect(chip, findsOneWidget, reason: '语言 chip 渲染(仅展示)');
      expect(
        find.descendant(of: chip, matching: find.byType(InkWell)),
        findsNothing,
        reason: '不可点 chip 不包 InkWell(无 hover/点击反馈、无 onTap)',
      );

      // 组件宿主无 router:若错误接了导航,context.go 会抛异常被下面断言抳住。
      await tester.tap(chip);
      await _pumpFrames(tester, 2);
      expect(tester.takeException(), isNull, reason: '点击语言 chip 不得导航/不抛异常');
    });

    testWidgets('chips 为空:promoTag 与主播名渲染不变(零回归护栏)', (tester) async {
      await pumpCard(
        tester,
        RoomRecord(
          site: 'douyu',
          roomId: '9010',
          roomState: RoomState.live,
          title: '无 chip 房',
          anchorName: '老王',
          cid: '1',
          category: '英雄联盟',
          audience: '1.2万',
          cover: '',
          promoTag: '超清',
        ),
      );

      expect(
        find.byKey(const Key('room-meta-chip-超清')),
        findsOneWidget,
        reason: 'promoTag 行为不变:仍是元信息行的特色 chip',
      );
      // 昵称移到封面左下,仍渲染一次(不进 meta 行)。
      expect(find.text('老王'), findsOneWidget, reason: '主播名渲染不变(封面左下)');
      expect(
        tester.widget<OutlineChip>(
          find.byKey(const Key('room-meta-chip-超清')),
        ).onTap,
        isNull,
        reason: 'promoTag 仍用同一线框组件且不可点',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('chips 为空:第 2 行仍占位整行,卡片与有 chips 时完全等高', (
      tester,
    ) async {
      RoomRecord room(String id, {List<SiteChip> chips = const []}) => RoomRecord(
        site: 'twitch',
        roomId: id,
        roomState: RoomState.live,
        title: '占位房',
        anchorName: '占位主播',
        cid: 'g1',
        category: '分类',
        audience: '1.2万',
        cover: '',
        chips: chips,
      );
      final withChips = room(
        '9020',
        chips: const [
          SiteChip(id: 'x', name: '策略', kind: SiteChipKind.tag, filterCid: 'tag:x'),
        ],
      );
      final withoutChips = room('9021');
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: ZishuTheme.dark(),
            home: Scaffold(
              body: Row(
                children: [
                  SizedBox(width: 360, child: RoomCard(room: withChips)),
                  SizedBox(width: 360, child: RoomCard(room: withoutChips)),
                ],
              ),
            ),
          ),
        ),
      );
      await _pumpFrames(tester, 2);

      final hWith = tester
          .getSize(find.byKey(const Key('room-card-twitch-9020')))
          .height;
      final hWithout = tester
          .getSize(find.byKey(const Key('room-card-twitch-9021')))
          .height;
      expect(
        hWithout,
        hWith,
        reason: 'chips 为空时第 2 行用占位行撑满,所有平台卡片等高',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('promoTag 与 chips 同名时不重复渲染', (tester) async {
      await pumpCard(
        tester,
        RoomRecord(
          site: 'twitch',
          roomId: '9011',
          roomState: RoomState.live,
          title: '重复房',
          anchorName: '小张',
          cid: 'g1',
          category: '分类',
          audience: '1.2万',
          cover: '',
          promoTag: '英语',
          chips: const [
            SiteChip(id: 'EN', name: '英语', kind: SiteChipKind.language),
          ],
        ),
      );

      expect(
        find.byKey(const Key('room-meta-chip-英语')),
        findsOneWidget,
        reason: 'promoTag 已单独成 chip 时不重复',
      );
      expect(find.text('英语'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
