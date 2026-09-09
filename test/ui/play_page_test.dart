/// 播放页(PlayView)widget test:锚点、画质 chip 选中态与侧栏折叠验证。
///
/// - media_kit 禁止在 VM 初始化:必须用 playerProvider.overrideWithValue 注入
///   FakeLivePlayer(实现 LivePlayer 接口,快照用 Stream.value,方法记录调用)。
/// - 直接 pump 目标页面(约定允许的宿主方式):真实路由宿主中播放页不套
///   AppShell(无 Scaffold/Material),PlayerControlsBar 的 Slider 依赖 Material
///   祖先,这里用 Scaffold 提供等价宿主环境,聚焦锚点交互验证。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/views/play_view.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class FakeLivePlayer implements LivePlayer {
  FakeLivePlayer();

  /// 记录方法调用,便于必要时验证交互链路。
  final List<String> calls = [];

  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line) async => calls.add('open:${line.url}');

  @override
  Future<void> play() async => calls.add('play');

  @override
  Future<void> pause() async => calls.add('pause');

  @override
  Future<void> setVolume(double volume) async => calls.add('volume:$volume');

  @override
  Future<void> setMuted(bool muted) async => calls.add('muted:$muted');

  @override
  Future<void> toggleFullscreen() async => calls.add('fullscreen');

  @override
  void dispose() => calls.add('dispose');
}

void main() {
  /// 直接 pump PlayView:fixture 数据源走默认 provider,FakeLivePlayer 注入。
  ///
  /// 画质/线路条是水平 ListView 惰性挂载:默认 800x600 下侧栏占掉 328 后,
  /// 左列仅约 424 宽,末尾「备线 FLV」chip 不会挂载;放大 surface 保证全部锚点挂载。
  Future<void> pumpPlayView(WidgetTester tester) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.binding.setSurfaceSize(const Size(1600, 1200));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWithValue(FakeLivePlayer())],
        child: MaterialApp(
          theme: ZishuTheme.dark(),
          home: const Scaffold(
            body: PlayView(site: 'douyu', roomId: '63136'),
          ),
        ),
      ),
    );
    // 数帧:挂载 + 播放控制器异步解析落地(fixture payload)。
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('/douyu/play/63136:返回与侧栏开关锚点存在,画质锚点 4 个',
      (tester) async {
    await pumpPlayView(tester);

    expect(find.byKey(const Key('play-back')), findsOneWidget);
    expect(find.byKey(const Key('play-side-panel-toggle')), findsOneWidget);

    // fixture payload 固定 4 个画质:蓝光8M/超清/高清/流畅。
    for (final name in const ['蓝光8M', '超清', '高清', '流畅']) {
      expect(
        find.byKey(Key('play-quality-$name')),
        findsOneWidget,
        reason: '缺少画质锚点 $name',
      );
    }
    // 默认选中第一档画质(蓝光8M),其下 3 条线路锚点可见。
    for (final name in const ['HLS', '主线 FLV', '备线 FLV']) {
      expect(find.byKey(Key('play-line-$name')), findsOneWidget);
    }
  });

  testWidgets('点击 play-quality-流畅:对应 chip 进入选中态', (tester) async {
    await pumpPlayView(tester);

    final qualityChip = find.byKey(const Key('play-quality-流畅'));
    expect(
      tester.widget<ChoiceChip>(qualityChip).selected,
      isFalse,
      reason: '初始选中蓝光8M,流畅应未选中',
    );

    await tester.tap(qualityChip);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    // ChoiceChip 的 selected 即选中态样式来源(实现里同时切换边框/文字色)。
    expect(tester.widget<ChoiceChip>(qualityChip).selected, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击 play-side-panel-toggle:328px 侧栏消失/再点恢复出现',
      (tester) async {
    await pumpPlayView(tester);

    // 侧栏初始可见(容器宽 328,由 PlaySidePanel 填充)。
    expect(find.byType(PlaySidePanel), findsOneWidget);

    await tester.tap(find.byKey(const Key('play-side-panel-toggle')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(PlaySidePanel), findsNothing);

    await tester.tap(find.byKey(const Key('play-side-panel-toggle')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(PlaySidePanel), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
