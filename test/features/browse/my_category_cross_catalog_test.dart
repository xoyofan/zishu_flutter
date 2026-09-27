/// 「我的分类」全平台映射回归:
///
/// 1. 管理弹窗目录默认「全平台」(跨平台映射目录,对齐 web
///    `MyCategoryManageSheet.vue` 打开时 `activeSite = "all"`),从全平台目录
///    收藏的条目按跨平台 key 命中 —— 任一平台同分类都算已收藏;
/// 2. 导航浮层收藏 chip 恒跳全平台分类页 `/all/category/<key>`
///    (对齐 web `NavMyCategoryMenu.vue` 的 `all-category-rooms`)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/browse/application/my_category_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/domain/category_display.dart'
    show resolveCrossCategoryKey;

/// 测试替身:VM 下替代 MediaKitLivePlayer(无真实播放)。
class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line,
          [List<StreamLine> fallbacks = const [], bool resetRetries = true]) =>
      Future.value();

  @override
  Future<void> play() => Future.value();

  @override
  Future<void> pause() => Future.value();

  @override
  Future<void> setVolume(double volume) => Future.value();

  @override
  Future<void> setMuted(bool muted) => Future.value();

  @override
  Future<void> toggleFullscreen() => Future.value();

  @override
  Future<void> setFullscreen(bool fullscreen) => Future.value();

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) => Future.value();

  @override
  Future<void> exitPictureInPicture() => Future.value();

  @override
  Future<void> stop() => Future.value();

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

void main() {
  /// 全平台目录条目(site=all + 跨平台 key)与各平台原生 (site,cid) 的
  /// 双向命中,是「全平台映射」语义的核心不变量。
  group('全平台目录收藏跨平台命中(控制器语义)', () {
    setUp(() {
      SharedPreferencesAsyncPlatform.instance =
          InMemorySharedPreferencesAsync.withData(const {});
    });

    test('site=all 条目:huya/douyu/bilibili 同分类全部命中已收藏', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      // 全平台 cross catalog 的条目:cid 即跨平台 key(`lol`),name 为
      // canonical 中文名。真实表:英雄联盟 → douyu '1' / huya '1' /
      // bilibili '86'。
      final ok = await container.read(myCategoriesProvider.notifier)
          .toggleForCategory(
            const MyCategoryEntry(site: 'all', cid: 'lol', name: '英雄联盟'),
          );
      expect(ok, isTrue);

      final entries = container.read(myCategoriesProvider);
      expect(entries, hasLength(1));
      expect(entries.single.site, 'all');
      expect(resolveCrossCategoryKey('lol'), 'lol');

      for (final (site, cid) in const [('huya', '1'), ('douyu', '1'), ('bilibili', '86')]) {
        expect(
          isCategoryFavorited(entries, site: site, cid: cid, name: '英雄联盟'),
          isTrue,
          reason: '$site cid=$cid 的英雄联盟应命中全平台收藏',
        );
      }
    });

    test('先收藏平台条目再点全平台目录:toggle 命中同 key 全部移除', () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(myCategoriesProvider.notifier);
      await notifier.toggleForCategory(
        const MyCategoryEntry(site: 'huya', cid: '1', name: '英雄联盟'),
      );
      expect(container.read(myCategoriesProvider), hasLength(1));

      // 从全平台目录再点同一分类:跨平台口径视为「已收藏」→ 取消,
      // 两个视角都不再命中。
      await notifier.toggleForCategory(
        const MyCategoryEntry(site: 'all', cid: 'lol', name: '英雄联盟'),
      );
      final entries = container.read(myCategoriesProvider);
      expect(entries, isEmpty);
      expect(
        isCategoryFavorited(entries, site: 'huya', cid: '1', name: '英雄联盟'),
        isFalse,
      );
    });
  });

  testWidgets('管理弹窗默认全平台目录:从目录收藏即得跨平台条目', (tester) async {
    tester.view.physicalSize = const Size(480, 800); // <768 走底栏
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(const {});

    await tester.pumpWidget(
      ProviderScope(
        overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
        child: const WindowsApp(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    // 底栏「我的分类」直接开管理弹窗(触屏路径)。
    await tester.tap(find.byKey(const Key('nav-my-category')));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));

    expect(find.byType(AlertDialog), findsOneWidget);
    // 默认目录站点是「全平台」:站点 chip 里全平台为选中态(此处只断言
    // 存在该 tab,选中样式由 golden 网覆盖)。
    expect(find.text('全平台'), findsWidgets);
    // fixture 全平台目录渲染出跨平台分类条目。
    expect(find.text('英雄联盟'), findsWidgets);

    // 点目录里的「英雄联盟」→ 以跨平台口径写入收藏。
    final dialogContext = tester.element(find.byType(AlertDialog));
    await tester.tap(find.text('英雄联盟').last);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    final container = ProviderScope.containerOf(dialogContext);
    final entries = container.read(myCategoriesProvider);
    expect(entries, hasLength(1));
    expect(entries.single.site, 'all');
    expect(entries.single.cid, '1'); // fixture 目录条目 cid
    expect(entries.single.name, '英雄联盟');
    // 跨平台命中:虎牙同分类视为已收藏。
    expect(
      isCategoryFavorited(
        entries,
        site: 'huya',
        cid: '1',
        name: '英雄联盟',
      ),
      isTrue,
    );
  });
}
