/// 临时截图用例:渲染顶栏 hover 浮层的两种形态(平台分类 / 我的关注主播网格),
/// 产物 PNG 用于人工比对 SFVideoLive 的 `.nav-platform-menu` 与
/// `.nav-follow-flyout`。用 `--update-goldens` 生成;生成后本文件即删除。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/application/my_category_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 测试替身:VM 下替代 MediaKitLivePlayer。
class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line, [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

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

/// 收藏替身:VM 无 SharedPreferences 实现,直接用固定收藏渲染浮层。
class _SeededMyCategoryController extends MyCategoryController {
  @override
  List<MyCategoryEntry> build() => const [
        MyCategoryEntry(site: 'all', cid: '1', name: '英雄联盟'),
        MyCategoryEntry(site: 'douyu', cid: '8', name: '无畏契约'),
        MyCategoryEntry(site: 'douyu', cid: '2', name: '唱见'),
        MyCategoryEntry(site: 'huya', cid: '3', name: '户外'),
      ];
}

void main() {
  /// VM 测试字体取整可能带来既有布局的 RenderFlex 溢出,只放行该类渲染错误。
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
  /// VM 无插件实现 → mock 临时目录(图片请求仍被测试 binding 拦成占位块)。
  void mockPathProvider() {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => r'.tmp_cache');
  }

  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    bool seedMyCategories = false,
  }) async {
    useWideSurface(tester);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playerProvider.overrideWithValue(_FakeLivePlayer()),
          if (seedMyCategories)
            myCategoriesProvider.overrideWith(_SeededMyCategoryController.new),
        ],
        child: const WindowsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Future<void> hover(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    final center = tester.getCenter(finder);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await gesture.moveTo(center);
    addTearDown(() => gesture.removePointer());
    await tester.pump();
    // 分类数据为异步:固定次数 pump 等待落地。
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  testWidgets('hover 平台 tab → 分类浮层', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    await pumpApp(tester);
    await hover(tester, find.byKey(const Key('platform-tab-douyu')));
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('hover_platform_categories.png'),
    );
  });

  testWidgets('hover 我的关注 → 主播头像网格', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    await pumpApp(tester);
    await hover(tester, find.byKey(const Key('nav-follow')));
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('hover_follow_grid.png'),
    );
  });

  testWidgets('hover 我的分类 → 收藏 chip 网格', (tester) async {
    suppressRenderFlexOverflow();
    mockPathProvider();
    await pumpApp(tester, seedMyCategories: true);
    await hover(tester, find.byKey(const Key('nav-my-category')));
    await expectLater(
      find.byType(Scaffold).first,
      matchesGoldenFile('hover_my_category.png'),
    );
  });
}
