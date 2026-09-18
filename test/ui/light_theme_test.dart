/// 日夜主题接线验证:切换后背景/前景色必须真的变(不只是 MaterialApp 的
/// themeMode 变了),并且源码里不允许再有写死的 `AppColors.*`。
///
/// 背景:旧实现有两个坑 ——
/// 1. `AppTypography.*` 的 TextStyle 写死深色基线色,浅色主题下白底白字;
/// 2. 页面/Surface/侧栏 chip 直接用 `AppColors.*` 常量(深色一套),
///    `themeMode` 切了但背景纹丝不动。
/// 本套用例把「切了确实生效」与「不准再写死」都钉住。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/zishu_tokens.dart';

class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line,
          [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

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

Future<({ProviderContainer container, BuildContext context})> _pumpApp(
  WidgetTester tester,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  for (var i = 0; i < 3; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
  final element = tester.element(find.byType(Scaffold).first);
  return (
    container: ProviderScope.containerOf(element),
    context: element,
  );
}

/// 走完 AnimatedTheme(200ms)后方能读到新主题的 ThemeData。
Future<void> _settleTheme(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  setUp(() {
    // 桌面壳里有登录恢复/关注云同步链路,注入内存后端避免碰平台通道。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('默认深色:背景取 ZishuTokens.dark(产品基线不变)', (tester) async {
    final app = await _pumpApp(tester);
    expect(app.context.tokens.background, ZishuTokens.dark.background);
    expect(
      Theme.of(app.context).brightness,
      Brightness.dark,
      reason: '桌面端基线为深色(浅色/跟随系统是显式选择项)',
    );
  });

  testWidgets('切浅色:壳层背景色随主题切换(不只是 themeMode 变)', (tester) async {
    final app = await _pumpApp(tester);
    final darkBackground = app.context.tokens.background;

    await app.container
        .read(settingsProvider.notifier)
        .setThemeMode(ThemeModeChoice.light);
    await _settleTheme(tester);

    final tokens = app.context.tokens;
    expect(tokens.background, ZishuTokens.light.background);
    expect(
      tokens.background,
      isNot(darkBackground),
      reason: '浅色背景必须与深色不同,否则等于没切',
    );
    expect(Theme.of(app.context).brightness, Brightness.light);

    // 壳层 Scaffold 真的用了主题背景色(旧实现写死 AppColors.background)。
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      ZishuTokens.light.background,
    );

    // 切回深色同样生效。
    await app.container
        .read(settingsProvider.notifier)
        .setThemeMode(ThemeModeChoice.dark);
    await _settleTheme(tester);
    expect(app.context.tokens.background, ZishuTokens.dark.background);
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold).first).backgroundColor,
      ZishuTokens.dark.background,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('播放页关注/超关 chip 取主题 token(浅色下不再用深红/深紫)', (tester) async {
    final app = await _pumpApp(tester);
    // 播放页深色与浅色下的 chip 底色必须分别等于对应主题 token。
    expect(ZishuTokens.light.playFollowBg, isNot(ZishuTokens.dark.playFollowBg));
    expect(ZishuTokens.light.playSuperBg, isNot(ZishuTokens.dark.playSuperBg));

    app.container.read(routerProvider).go('/douyu/play/63136');
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await _settleTheme(tester);

    /// 取锚点子树里所有底色集合(Material.color + Container 的 BoxDecoration.color)。
    ///
    /// 控件层级会变(按钮是 `Material(color:)` 而不是 Container),故断言
    /// 「其中出现过期望色」,不绑定某个具体节点。
    Set<Color?> colorsUnder(Key key) => {
      for (final material in tester.widgetList<Material>(
        find.descendant(of: find.byKey(key), matching: find.byType(Material)),
      ))
        material.color,
      for (final container in tester.widgetList<Container>(
        find.descendant(of: find.byKey(key), matching: find.byType(Container)),
      ))
        if (container.decoration is BoxDecoration)
          (container.decoration! as BoxDecoration).color,
      if (tester.widget(find.byKey(key)) case final Container container)
        if (container.decoration is BoxDecoration)
          (container.decoration! as BoxDecoration).color,
    };

    final followKey = const Key('play-side-follow-btn');
    expect(
      find.byKey(followKey),
      findsOneWidget,
      reason: '播放页侧栏应有「关注」按钮锚点',
    );
    // 房间可能已是「已关注」态,故接受 常态/已关注 两种 token。
    final darkColors = colorsUnder(followKey);
    expect(
      darkColors.any(
        (c) =>
            c == ZishuTokens.dark.playFollowBg ||
            c == ZishuTokens.dark.playFollowBgActive,
      ),
      isTrue,
      reason: '深色下关注按钮底应为深色 token,实际:$darkColors',
    );

    await app.container
        .read(settingsProvider.notifier)
        .setThemeMode(ThemeModeChoice.light);
    await _settleTheme(tester);
    final lightColors = colorsUnder(followKey);
    expect(
      lightColors.any(
        (c) =>
            c == ZishuTokens.light.playFollowBg ||
            c == ZishuTokens.light.playFollowBgActive,
      ),
      isTrue,
      reason: '浅色下关注按钮底应换成浅色 token(旧实现写死 AppColors.playFollowBg,切了也不变),实际:$lightColors',
    );
    expect(
      lightColors.intersection(darkColors),
      isEmpty,
      reason: '浅色下不得残留深色 chip 底色',
    );
    expect(tester.takeException(), isNull);
  });

  test('静态守则:lib/src 下不得再写死 AppColors.*(主题常量文件除外)', () {
    // 仅允许两个 tokens 定义文件:常量本体就住在那里。
    // 其余任何位置写死 AppColors.* 都会让浅色主题失效(背景/chip 纹丝不动)。
    const allowed = {
      'lib/src/shared/presentation/design_tokens.dart',
      'lib/src/shared/presentation/zishu_tokens.dart',
    };
    final offenders = <String>[];
    for (final entity in Directory('lib/src').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final path = entity.path.replaceAll('\\', '/');
      if (allowed.contains(path)) continue;
      final lines = entity.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i];
        // 注释里的举例(如弹幕色文档)不算写死用法。
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('AppColors.')) {
          offenders.add('$path:${i + 1}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '这些位置仍写死深色常量,浅色主题下不会跟着切:${offenders.join(', ')}'
          ' —— 改用 context.tokens.* / context.textX(见 zishu_tokens.dart)',
    );
  });
}
