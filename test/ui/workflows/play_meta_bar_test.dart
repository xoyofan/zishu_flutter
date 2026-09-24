/// 移动端播放页「直播信息条」(PlayMetaBar)widget test。
///
/// 覆盖两条口径:
/// - 窄屏(<768)堆叠布局:视频正下方渲染信息条(头像 + 昵称 + 4 项统计 +
///   关注/超关),点关注可落库(复用的是侧栏同一份 followProvider 语义);
/// - 桌面(>=768)**:渲染结果不得变化** —— 仍是侧栏完整信息头
///   (`play-side-header`),信息条不出现,锚点不重复。
///
/// 宿主与 test/ui/workflows/mobile_phones_test.dart 同约定:直接 pump 播放页
/// (media_kit 禁止在 VM 初始化,注入 FakeLivePlayer),固定次数 pump;
/// 存储后端注入 InMemorySharedPreferencesAsync 避免碰平台通道。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show RoomPayload, RoomState, RoomSummary, StreamLine, StreamQuality;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

/// 测试替身:替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class _FakeLivePlayer implements LivePlayer {
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

/// 房间解析替身:可指定开播时间,验证开播时间格的格式化(而不是永远「开播中」)。
class _RoomSourceWithStartedAt implements RoomSource {
  const _RoomSourceWithStartedAt(this.startedAt);

  final DateTime? startedAt;

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    return RoomPayload(
      site: 'douyu',
      roomId: roomIdOrUrl,
      sourceUrl: 'https://www.douyu.com/$roomIdOrUrl',
      anchorName: '神超',
      title: '英雄联盟 高分排位',
      cover: '',
      avatar: '',
      category: '英雄联盟',
      cid: '1',
      roomState: RoomState.live,
      streams: const [
        StreamQuality(
          name: '超清',
          rate: 2,
          lines: [
            StreamLine(
              name: 'HLS',
              url: 'https://fixture.zishu.dev/1/index.m3u8',
              format: 'hls',
            ),
          ],
        ),
      ],
      availableQualities: const [],
      source: 'fixture',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
      startedAt: startedAt,
    );
  }
}

const Duration _kFrame = Duration(milliseconds: 50);

Future<void> _pumpFrames(WidgetTester tester, [int times = 4]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 按脚本返回房间统计的假解析刷新源:命中 roomId 返回快照,其余抛错
/// (零网络;与 play_follow_panel_test 的同名替身同构)。
class _ScriptedRefresher implements RoomRefresher {
  _ScriptedRefresher(this.results);

  final Map<String, RoomSummary> results;

  @override
  Future<RoomSummary> refreshRoom({
    required String site,
    required String roomId,
  }) async {
    final room = results[roomId];
    if (room == null) throw StateError('no scripted result: $roomId');
    return room;
  }

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    throw UnimplementedError('本轨不校验解析路径');
  }
}

/// 解析统计快照(只承载展示统计字段,其余按契约形状置空)。
RoomSummary _statsRoom({
  required String roomId,
  String online = '',
  String followers = '',
  String vip = '',
  String diamondFans = '',
}) => RoomSummary(
  site: 'douyu',
  roomId: roomId,
  title: '',
  anchorName: '',
  cid: '',
  category: '',
  online: online,
  cover: '',
  followers: followers,
  vip: vip,
  diamondFans: diamondFans,
  roomState: RoomState.live,
);

/// pump 播放页:注入 FakeLivePlayer(可选覆盖 roomSourceProvider),设定视口。
Future<ProviderContainer> _pumpPlay(
  WidgetTester tester, {
  required Size size,
  RoomSource? roomSource,
  RoomRefresher? refresher,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        if (roomSource != null)
          roomSourceProvider.overrideWithValue(roomSource),
        if (refresher != null)
          roomRefresherProvider.overrideWithValue(refresher),
      ],
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: const Material(
          type: MaterialType.transparency,
          child: PlayView(site: 'douyu', roomId: '63136'),
        ),
      ),
    ),
  );
  await _pumpFrames(tester, 5);
  return ProviderScope.containerOf(tester.element(find.byType(PlayView)));
}

/// 信息条子树内的文本查找(避免与画质 chip 等处的同名字样混淆)。
Finder _inMetaBar(String text) => find.descendant(
  of: find.byKey(const Key('play-meta-bar')),
  matching: find.text(text),
);

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  group('窄屏移动信息条', () {
    testWidgets('375x812:视频下方渲染头像/昵称/4 项统计/关注与超关按钮', (tester) async {
      await _pumpPlay(tester, size: const Size(375, 812));

      // 信息条出现;桌面完整信息头让位(同一时刻只渲染一处)。
      expect(find.byKey(const Key('play-meta-bar')), findsOneWidget);
      expect(find.byKey(const Key('play-side-header')), findsNothing);

      // 昵称与四项统计格(关注 / 开播 / 人气 / 弹幕)。
      expect(_inMetaBar('神超'), findsOneWidget);
      for (final key in const [
        'play-meta-stat-followers',
        'play-meta-stat-started',
        'play-meta-stat-audience',
        'play-meta-stat-danmaku',
      ]) {
        expect(find.byKey(Key(key)), findsOneWidget, reason: '缺少统计格 $key');
      }

      // 两个动作按钮各一处(锚点沿用侧栏契约,不重复)。
      expect(find.byKey(const Key('play-side-follow-btn')), findsOneWidget);
      expect(find.byKey(const Key('play-side-super-follow')), findsOneWidget);

      // 布局不溢出(信息条是新增的结构,溢出会先在这里暴露)。
      expect(tester.takeException(), isNull);
    });

    testWidgets('点关注/超关:状态落库并回显(复用侧栏同一份 followProvider 语义)', (tester) async {
      final container = await _pumpPlay(tester, size: const Size(375, 812));
      const roomKey = 'douyu:63136';
      // fixture 关注种子可能已含该房;先清空再验证从「关注」开始。
      container.read(followProvider.notifier).remove(roomKey);
      await _pumpFrames(tester, 2);
      expect(_inMetaBar('关注'), findsOneWidget);

      await tester.tap(find.byKey(const Key('play-side-follow-btn')));
      await _pumpFrames(tester, 2);
      expect(
        container.read(followProvider).any((e) => e.key == roomKey),
        isTrue,
        reason: '信息条上的关注按钮应写入 followProvider',
      );
      expect(_inMetaBar('已关注'), findsOneWidget);

      await tester.tap(find.byKey(const Key('play-side-super-follow')));
      await _pumpFrames(tester, 2);
      final entry = container
          .read(followProvider)
          .firstWhere((e) => e.key == roomKey);
      expect(entry.isSpecial, isTrue, reason: '超关应把该房标记为特别关注');
      expect(_inMetaBar('已超关'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('开播格:有 startedAt 时显示 MM-DD HH:mm(参考实现同格式)', (tester) async {
      await _pumpPlay(
        tester,
        size: const Size(375, 812),
        roomSource: _RoomSourceWithStartedAt(DateTime(2026, 9, 10, 8, 8)),
      );

      expect(_inMetaBar('开播 09-10 08:08'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('统计格回填:关注条目 summary 有值时显示数值(PARSER-GAP-001)', (tester) async {
      final container = await _pumpPlay(tester, size: const Size(375, 812));
      // fixture 种子可能已含该房;替换为带真源回填统计的关注条目
      // (followers/online 同桌面侧栏信息头共用 followProvider 快照)。
      container.read(followProvider.notifier).remove('douyu:63136');
      container
          .read(followProvider.notifier)
          .addFromRoom(
            const RoomSummary(
              site: 'douyu',
              roomId: '63136',
              title: '',
              anchorName: '神超',
              cid: '',
              category: '',
              online: '341.2万',
              cover: '',
              followers: '5403780',
              vip: '1128',
            ),
          );
      await _pumpFrames(tester, 2);

      expect(_inMetaBar('关注 540万'), findsOneWidget);
      expect(_inMetaBar('人气 341.2万'), findsOneWidget);
      // 弹幕总数上游无字段,保持「—」不冒充。
      expect(_inMetaBar('弹幕 —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('统计格:已关注但上游未提供 followers/online 时仍显示「—」', (tester) async {
      final container = await _pumpPlay(tester, size: const Size(375, 812));
      container.read(followProvider.notifier).remove('douyu:63136');
      // yy/kuaishou 等上游无免登录统计接口,回填值为空 → 占位不伪造。
      container
          .read(followProvider.notifier)
          .addFromRoom(
            const RoomSummary(
              site: 'douyu',
              roomId: '63136',
              title: '',
              anchorName: '神超',
              cid: '',
              category: '',
              online: '',
              cover: '',
            ),
          );
      await _pumpFrames(tester, 2);

      expect(_inMetaBar('关注 —'), findsOneWidget);
      expect(_inMetaBar('人气 —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360x640:缺开播时间显示「开播中」,解析层缺字段一律占位不伪造', (tester) async {
      await _pumpPlay(tester, size: const Size(360, 640));

      // fixture 种子首条即本房(douyu:63136):online='42.1万' 已回填 → 人气
      // 显示真值;followers 上游未提供 → 「—」;弹幕总数无字段 → 「—」。
      expect(_inMetaBar('开播 开播中'), findsOneWidget);
      expect(_inMetaBar('关注 —'), findsOneWidget);
      expect(_inMetaBar('人气 42.1万'), findsOneWidget);
      expect(_inMetaBar('弹幕 —'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('未关注有解析统计:点关注后信息条数值不消失(375x812)', (tester) async {
      final container = await _pumpPlay(
        tester,
        size: const Size(375, 812),
        refresher: _ScriptedRefresher({
          '63136': _statsRoom(
            roomId: '63136',
            online: '1.2万',
            followers: '123456',
            vip: '321',
            diamondFans: '1300',
          ),
        }),
      );
      // fixture 种子首条即本房:先移除,构造「未关注但有解析统计」的场景。
      container.read(followProvider.notifier).remove('douyu:63136');
      await _pumpFrames(tester, 3);

      // 未关注:统计来自解析快照(任意房间可查)。
      expect(_inMetaBar('关注 12.3万'), findsOneWidget);
      expect(_inMetaBar('人气 1.2万'), findsOneWidget);

      await tester.tap(find.byKey(const Key('play-side-follow-btn')));
      await _pumpFrames(tester, 3);

      expect(
        container.read(followProvider).any((e) => e.key == 'douyu:63136'),
        isTrue,
        reason: '前置:点关注已落库',
      );
      // 回归点:关注状态与统计取数分离,刚关注的空统计不得盖掉解析值。
      expect(_inMetaBar('关注 12.3万'), findsOneWidget, reason: '点关注后关注数不得变回「—」');
      expect(
        _inMetaBar('人气 1.2万'),
        findsOneWidget,
        reason: '点关注后人气不得被占位文案/空值替代',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('play-meta-stat-vip')),
          matching: find.textContaining('321'),
        ),
        findsOneWidget,
        reason: '点关注后 VIP 数值不得消失',
      );
      expect(
        find.descendant(
          of: find.byKey(const Key('play-meta-stat-svip')),
          matching: find.textContaining('1300'),
        ),
        findsOneWidget,
        reason: '点关注后 SVIP 数值不得消失',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('桌面不回归', () {
    testWidgets('1024x768:仍是侧栏完整信息头,信息条不出现且锚点不重复', (tester) async {
      await _pumpPlay(tester, size: const Size(1024, 768));

      expect(find.byKey(const Key('play-meta-bar')), findsNothing);
      expect(find.byKey(const Key('play-side-header')), findsOneWidget);
      expect(find.byKey(const Key('play-side-follow-btn')), findsOneWidget);
      expect(find.byKey(const Key('play-side-super-follow')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
