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
  Future<void> open(StreamLine line, [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async => calls.add('open:${line.url}');

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
  Future<void> setFullscreen(bool fullscreen) async => calls.add('fullscreen:$fullscreen');

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async => calls.add('pip:enter');

  @override
  Future<void> exitPictureInPicture() async => calls.add('pip:exit');

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() => calls.add('dispose');
}

void main() {
  /// 直接 pump PlayView:fixture 数据源走默认 provider,FakeLivePlayer 注入。
  ///
  /// 画质/线路条是水平 ListView 惰性挂载:默认 800x600 下侧栏占掉 328 后,
  /// 左列仅约 424 宽,末尾「备线 FLV」chip 不会挂载;放大 surface 保证全部锚点挂载。
  Future<void> pumpPlayView(WidgetTester tester) async {
    // 必须写 tester.view(物理尺寸 + dpr),不能用 setSurfaceSize:
    // setSurfaceSize 只改渲染 surface,MediaQuery 仍报 800×600,断点判定全失灵
    // (tasks.md W13 记录)→ 800<1024 被判成窄屏,画质/线路收进下拉,
    // play-quality-*/play-line-* 锚点不挂载,桌面口径用例全部失真。
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1600, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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

  testWidgets('/douyu/play/63136:返回与侧栏开关锚点存在,画质/线路 selectbox 可用', (
    tester,
  ) async {
    await pumpPlayView(tester);

    expect(find.byKey(const Key('play-back')), findsOneWidget);
    expect(find.byKey(const Key('play-side-panel-toggle')), findsOneWidget);

    // 2026-09-11 裁决:画质/线路收进控制栏 selectbox(菜单项锚点只在菜单
    // 打开时挂载)。入口与当前档标签必须常驻。
    expect(
      find.byKey(const Key('play-quality-menu')),
      findsOneWidget,
      reason: '控制栏应有画质 selectbox 入口',
    );
    expect(find.byKey(const Key('play-quality-current')), findsOneWidget);
    expect(find.byKey(const Key('play-line-menu')), findsOneWidget);

    // 打开画质菜单:fixture 固定 4 档(蓝光8M/超清/高清/流畅)。
    // pump 8 帧:等 PopupRoute 尺寸过渡完成(见下方选档用例说明)。
    await tester.tap(find.byKey(const Key('play-quality-menu')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (final name in const ['蓝光8M', '超清', '高清', '流畅']) {
      expect(
        find.byKey(Key('play-quality-$name')),
        findsOneWidget,
        reason: '画质菜单缺少档位 $name',
      );
    }

    // 切到线路菜单:蓝光8M 下 3 条线路。
    await tester.tap(find.text('蓝光8M').last);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const Key('play-line-menu')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    for (final name in const ['HLS', '主线 FLV', '备线 FLV']) {
      expect(
        find.byKey(Key('play-line-item-$name')),
        findsOneWidget,
        reason: '线路菜单缺少 $name',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('selectbox 选画质:入口标签切换为所选档', (tester) async {
    await pumpPlayView(tester);

    String currentLabel() =>
        tester
            .widget<Text>(find.byKey(const Key('play-quality-current')))
            .data ??
        '';

    // 进房默认档 = settings 生效默认(出厂「超清」,fixture 有同名档)。
    expect(currentLabel(), '超清');

    // 打开画质菜单选「流畅」。PopupMenuRoute 有约 300ms 的尺寸过渡,过渡期间
    // 靠近菜单底部的项不在裁剪区内(hitTestable=0,实测):pump 到过渡完成后
    // 再点,不能只 pump 2 帧。
    await tester.tap(find.byKey(const Key('play-quality-menu')));
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.tap(find.byKey(const Key('play-quality-流畅')));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // ignore: avoid_print
    print('DBG labelAfter=${currentLabel()}');

    expect(currentLabel(), '流畅', reason: 'selectbox 选档后入口标签应切换为所选画质');
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击 play-side-panel-toggle:328px 侧栏消失/再点恢复出现', (tester) async {
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
