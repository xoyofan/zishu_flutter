/// 关注页三密度 + 播放页推荐 tab 的样式截图(golden)。
///
/// 用途:与 SFVideoLive 参考实现做视觉对齐时快速比对。运行:
/// `flutter test test/ui/follow_style_shot_test.dart --update-goldens`
/// 产物会被复制到 `tool/screenshots/zishu/`。
///
/// 说明:VM 测试环境无中文字体(渲染为方块)且网络图片被拦成占位块,
/// 真机上为真实封面与中文;本套图只用于校验结构与间距。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line) async {}

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
  Future<void> stop() async {}

  @override
  void dispose() {}
}

void main() {
  void suppressRenderFlexOverflow() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
  }

  /// CachedNetworkImage 的 flutter_cache_manager 初始化要 path_provider,
  /// VM 无插件实现 → mock 临时目录(图片请求仍被拦成占位块)。
  void mockPathProvider() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => r'F:\project\zishu_flutter\build\.tmp_cache',
    );
  }

  Future<GoRouter> pumpShell(
    WidgetTester tester, {
    double width = 1024,
    double height = 768,
  }) async {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
        child: const WindowsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    final element = tester.element(find.byType(Scaffold));
    return ProviderScope.containerOf(element).read(routerProvider);
  }

  Future<void> pumpFrames(WidgetTester tester, [int count = 6]) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('关注页 卡片密度', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpShell(tester);
    router.go('/follow');
    await pumpFrames(tester, 8);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('follow_style_card.png'),
    );
  });

  testWidgets('关注页 紧凑密度', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpShell(tester);
    router.go('/follow');
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const Key('follow-density-tile')));
    await pumpFrames(tester, 8);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('follow_style_tile.png'),
    );
  });

  testWidgets('关注页 单行密度(宽屏多列)', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpShell(tester);
    router.go('/follow');
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const Key('follow-density-row')));
    await pumpFrames(tester, 8);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('follow_style_row.png'),
    );
  });

  testWidgets('播放页 侧栏推荐 tab 封面网格', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpShell(tester, width: 1440, height: 900);
    router.go('/douyu/play/63136');
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const Key('play-side-tab-recommend')));
    await pumpFrames(tester, 10);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('play_style_recommend.png'),
    );
  });

  testWidgets('播放页 侧栏关注 tab 封面网格', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    final router = await pumpShell(tester, width: 1440, height: 900);
    router.go('/douyu/play/63136');
    await pumpFrames(tester, 8);
    await tester.tap(find.byKey(const Key('play-side-tab-follow')));
    await pumpFrames(tester, 10);
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('play_style_follow.png'),
    );
  });
}
