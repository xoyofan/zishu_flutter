/// 解析耗时基准页测试:冷解析 / 缓存命中两条采样、绕缓存重解析、错误行。
///
/// 宿主:直接 pump 目标页面(约定允许的宿主方式,见 test/ui/play_page_test.dart),
/// 但补一层 MaterialApp + ZishuTheme(本页依赖 tokens/Theme)与内存存储;
/// 数据源用替身 override `roomSourceProvider`,不触网、不碰 media_kit。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show RoomPayload, RoomState, StreamLine, StreamQuality;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/dev/views/parse_benchmark_view.dart';
import 'package:zishu_flutter/src/shared/application/browse_source.dart';
import 'package:zishu_flutter/src/shared/application/providers.dart';

/// 测试替身:实现 [RoomSource] + [RoomRecoverer],记录调用序列。
///
/// 记录调用序列是本套用例的关键 —— 它证明「冷解析」确实走了绕缓存的
/// `recoverRoom`,而「缓存命中」那条走的是普通 `resolveRoom`。
class _FakeRoomSource implements RoomSource, RoomRecoverer {
  final List<String> calls = [];

  /// 置真后所有解析抛错,用于验证错误行(不白屏、不抛到框架)。
  bool fail = false;

  RoomPayload _payload({required String site, required String roomIdOrUrl}) {
    return RoomPayload(
      site: site,
      roomId: roomIdOrUrl,
      sourceUrl: 'https://example.test/$site/$roomIdOrUrl',
      anchorName: '测试主播',
      title: '测试房间',
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
              url: 'https://example.test/index.m3u8',
              format: 'hls',
            ),
            StreamLine(
              name: 'FLV',
              url: 'https://example.test/index.flv',
              format: 'flv',
            ),
          ],
        ),
      ],
      availableQualities: const [],
      source: 'test',
      fetchedAt: DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  @override
  Future<RoomPayload> resolveRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    calls.add('resolve:$site:$roomIdOrUrl');
    if (fail) throw StateError('上游解析失败');
    return _payload(site: site, roomIdOrUrl: roomIdOrUrl);
  }

  @override
  Future<RoomPayload> recoverRoom({
    required String site,
    required String roomIdOrUrl,
    String? preferredQuality,
  }) async {
    calls.add('recover:$site:$roomIdOrUrl');
    if (fail) throw StateError('上游解析失败');
    return _payload(site: site, roomIdOrUrl: roomIdOrUrl);
  }
}

const Duration _kFrame = Duration(milliseconds: 50);

Future<void> _pumpFrames(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

Future<void> _pumpView(WidgetTester tester, _FakeRoomSource source) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [roomSourceProvider.overrideWithValue(source)],
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: const Scaffold(body: ParseBenchmarkView()),
      ),
    ),
  );
  await _pumpFrames(tester, 2);
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('运行基准:冷解析走 recoverRoom、缓存命中走 resolveRoom,两条采样都渲染', (tester) async {
    final source = _FakeRoomSource();
    await _pumpView(tester, source);

    // 初始:结果区只有空态提示。
    expect(find.byKey(const Key('bench-result')), findsOneWidget);
    expect(find.textContaining('尚未运行'), findsOneWidget);

    await tester.tap(find.byKey(const Key('bench-run')));
    await _pumpFrames(tester, 6);

    expect(
      source.calls,
      ['recover:douyu:63136', 'resolve:douyu:63136'],
      reason: '冷解析必须绕缓存(recoverRoom),缓存命中那条走 resolveRoom',
    );
    expect(find.text('冷解析'), findsOneWidget);
    expect(find.text('缓存命中'), findsOneWidget);
    // 墙钟以毫秒渲染且非负。
    final ms = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .where((s) => RegExp(r'^\d+ms$').hasMatch(s))
        .toList();
    expect(ms, hasLength(2), reason: '两条采样各有一格墙钟,实际:$ms');
    for (final value in ms) {
      expect(int.parse(value.replaceAll('ms', '')), greaterThanOrEqualTo(0));
    }
    // 关键字段来自 RoomPayload:1 档画质 / 2 条线路 / 在播 / 主播名。
    expect(find.text('在播'), findsWidgets);
    expect(find.text('测试主播'), findsWidgets);
    expect(find.byKey(const Key('bench-error')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('重新解析(绕缓存):只跑一行且仍走 recoverRoom', (tester) async {
    final source = _FakeRoomSource();
    await _pumpView(tester, source);

    await tester.tap(find.byKey(const Key('bench-recover')));
    await _pumpFrames(tester, 6);

    expect(source.calls, ['recover:douyu:63136']);
    // 按钮文案与采样行同名,故限定在结果区里断言。
    final result = find.byKey(const Key('bench-result'));
    expect(
      find.descendant(of: result, matching: find.text('重新解析(绕缓存)')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: result, matching: find.text('缓存命中')),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('解析失败:显示可见错误行(douyu 平台),不白屏不抛异常', (tester) async {
    final source = _FakeRoomSource()..fail = true;
    await _pumpView(tester, source);

    await tester.tap(find.byKey(const Key('bench-run')));
    await _pumpFrames(tester, 6);

    expect(find.byKey(const Key('bench-error')), findsOneWidget);
    expect(find.textContaining('解析失败'), findsOneWidget);
    // 失败时不留下半截采样行。
    expect(find.text('冷解析'), findsNothing);
    // 失败后按钮可用,可再次运行。
    final runButton = tester.widget<FilledButton>(
      find.byKey(const Key('bench-run')),
    );
    expect(runButton.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('房间号为空:给出可见提示且不发请求', (tester) async {
    final source = _FakeRoomSource();
    await _pumpView(tester, source);

    await tester.enterText(find.byKey(const Key('bench-room')), '');
    await tester.tap(find.byKey(const Key('bench-run')));
    await _pumpFrames(tester, 4);

    expect(find.byKey(const Key('bench-error')), findsOneWidget);
    expect(find.textContaining('请填写房间号'), findsOneWidget);
    expect(source.calls, isEmpty, reason: '输入非法时不得发解析请求');
    expect(tester.takeException(), isNull);
  });
}
