/// 播放页控制接线 workflow test(任务卡 A7-t8)。
///
/// 覆盖三类接线,全部走真实路由宿主 + 注入 FakeLivePlayer
/// (VM 下禁止初始化 media_kit):
/// 1. 默认画质生效:`zishu.settings.defaultQuality` 命中 streams 时该档进选中态;
///    未命中(脏值/列表外)时静默回退 `streams.first`,不报错;
/// 2. 桌面快捷键:Space 播放/暂停、M 静音切换、F 全屏切换,均落到 LivePlayer;
/// 3. 弹幕开关:控制条按钮切换 `PlayState.showDanmaku`(舞台弹幕叠加层显隐),
///    且写入 settings 的 `danmakuEnabled` 生效(关闭时按钮整体隐藏)。
///
/// 宿主约定与 platform_workflow.dart / settings_test.dart 一致:固定次数 pump,
/// 不用 pumpAndSettle;存储后端注入 InMemorySharedPreferencesAsync。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/follow/application/settings_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/player_controls.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 深链播放页(fixture 样例房间,与 layout/danmaku 基线同房间)。
const String _playLocation = '/douyu/play/63136';

/// 固定 pump 步长,与既有 workflow 测试一致。
const Duration _kFrame = Duration(milliseconds: 50);

/// 测试替身:替代 MediaKitLivePlayer,记录方法调用并按需广播快照。
///
/// 不覆写 snapshots 也能跑通——`playerSnapshotProvider` 在 VM 里拿不到帧时
/// 控制条会回退 `const PlayerSnapshot()`(playing=false / muted=false),
/// 这正好给快捷键与点击帧一个确定的初始态。
class FakeLivePlayer implements LivePlayer {
  FakeLivePlayer();

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

/// 测试宿主:与 WindowsApp 相同的 router/theme,补一层透明 Material
/// (播放页无壳,ChoiceChip / Slider 需要 Material 祖先)。
class _TestApp extends ConsumerWidget {
  const _TestApp();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      theme: ZishuTheme.dark(),
      routerConfig: ref.watch(routerProvider),
      builder: (context, child) =>
          Material(type: MaterialType.transparency, child: child),
    );
  }
}

/// 记录播放器替身,便于用例断言调用序列。
late FakeLivePlayer _player;

/// 启动宿主并深链到播放页,返回 router 与 container。
Future<({GoRouter router, ProviderContainer container})> _pumpPlay(
  WidgetTester tester,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  _player = FakeLivePlayer();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_player)],
      child: const _TestApp(),
    ),
  );
  await _pumpFrames(tester, 2);

  final element = tester.element(find.byType(Navigator).first);
  final container = ProviderScope.containerOf(element);
  final router = container.read(routerProvider);
  router.go(_playLocation);
  await _pumpFrames(tester, 3);
  return (router: router, container: container);
}

/// 固定次数 pump(不用 pumpAndSettle:封面图在 VM 中不会真正加载)。
Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

/// 轮询等待 settingsProvider 完成异步 _restore(hydrated)。
Future<void> _awaitSettingsHydrated(
  WidgetTester tester,
  ProviderContainer container,
) async {
  for (var attempt = 0; attempt < 10; attempt++) {
    if (container.read(settingsProvider).hydrated) return;
    await tester.pump(_kFrame);
  }
  fail('settingsProvider 未在限定帧数内完成 hydrated');
}

/// 当前选中画质锚点名(null 表示无选中档)。
///
/// 画质选择已是控制栏内的 selectbox(2026-09-11 裁决,原独立 chip 行已移除):
/// 锚点取入口标签 `play-quality-current` 的文本,回填成 `play-quality-{name}`
/// 口径以保持各用例断言不变。
String? _selectedQualityName(WidgetTester tester) {
  final current = find.byKey(const Key('play-quality-current'));
  if (!tester.any(current)) return null;
  final label = tester.widget<Text>(current).data;
  if (label == null || label == '画质') return null;
  return 'play-quality-$label';
}

/// 从当前 settings 状态读值。
SettingsState _settingsOf(ProviderContainer container) =>
    container.read(settingsProvider);

void main() {
  setUp(() {
    // 每个用例独立内存后端:被测代码与测试共享同一存储,写盘即可回读。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{});
  });

  testWidgets('defaultQualityApplies:默认画质命中列表时该档进选中态', (tester) async {
    final play = await _pumpPlay(tester);
    expect(play.router.routeInformationProvider.value.uri.path, _playLocation);
    await _awaitSettingsHydrated(tester, play.container);

    // 出厂默认画质为「超清」,fixture 四档里存在同名 stream。
    expect(_settingsOf(play.container).defaultQuality, '超清');
    expect(
      _selectedQualityName(tester),
      'play-quality-超清',
      reason: '进房应按 settings.defaultQuality 选中对应画质档,而不是永远第一档',
    );

    // 切回首页再进房,默认画质仍生效(payload 每次重新解析)。
    play.router.go('/all');
    await _pumpFrames(tester, 2);
    play.router.go(_playLocation);
    await _pumpFrames(tester, 3);
    expect(_selectedQualityName(tester), 'play-quality-超清');
  });

  testWidgets('defaultQualityApplies:改设置后重新进房按新默认档选中', (tester) async {
    final play = await _pumpPlay(tester);
    await _awaitSettingsHydrated(tester, play.container);

    // 用户改默认画质为「流畅」。
    await play.container
        .read(settingsProvider.notifier)
        .setDefaultQuality('流畅');
    await tester.pump(_kFrame);
    expect(_settingsOf(play.container).defaultQuality, '流畅');

    // 离开再进房:新默认生效。
    play.router.go('/all');
    await _pumpFrames(tester, 2);
    play.router.go(_playLocation);
    await _pumpFrames(tester, 3);
    expect(
      _selectedQualityName(tester),
      'play-quality-流畅',
      reason: '重新进房应采用更新后的默认画质',
    );
  });

  testWidgets('defaultQualityFallback:默认档不在本次列表时回退首档且不报错', (tester) async {
    // 预置一个「列表外」的脏值:测试直接写内存后端,绕过 setDefaultQuality 的
    // 白名单校验,模拟旧版本残留 / 平台档位改名后的脏数据。
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'zishu.settings.defaultQuality': '4K 原画',
        });

    final play = await _pumpPlay(tester);
    await _awaitSettingsHydrated(tester, play.container);
    // hydrated 后 settingsProvider 因 notify 触发一次普通 rebuild,播放控制器
    // watch 的是 select 出的值,值未变不会重建;这里再等两帧让重建真正落地。
    await _pumpFrames(tester, 3);

    // 脏值不写入状态(restore 阶段已被 qualityOptions 过滤,回退出厂默认
    // 「超清」)。注意:出厂默认本身就是 fixture 档位之一,因此断言重点在
    // 「脏值未生效」——若脏值穿透白名单,选中档会既不是超清也不是蓝光8M。
    final settings = _settingsOf(play.container);
    expect(settings.defaultQuality, isNot('4K 原画'));
    expect(settings.defaultQuality, '超清');
    expect(
      _selectedQualityName(tester),
      'play-quality-超清',
      reason: '脏值被白名单过滤后应回退出厂默认档「超清」,而不是无选中档',
    );
    // 回退路径不得抛异常。
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboardShortcuts:播放页获得焦点后 Space/M/F 生效', (tester) async {
    await _pumpPlay(tester);

    // 快捷键走 CallbackShortcuts:按键沿焦点树从叶子向根冒泡,焦点落在播放页
    // 子树内即命中。点一下视频舞台(play-stage-focus)把焦点交给页面,
    // 这正是桌面用户「先点播放区、再按快捷键」的路径。sendKeyDownEvent /
    // sendKeyUpEvent 走框架原生派发(keyDataThenRawKeyData),无需额外 shim。
    await tester.tap(find.byKey(const Key('play-stage-focus')));
    await _pumpFrames(tester, 2);
    expect(
      tester.binding.focusManager.primaryFocus,
      isNotNull,
      reason: '点击舞台后应有焦点落在播放页内,快捷键才可达',
    );
    _player.calls.clear();

    // ── Space:回退快照 playing=false → 期望 play ──────────────────────
    await tester.sendKeyDownEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.space);
    await _pumpFrames(tester, 2);
    expect(_player.calls, contains('play'), reason: 'Space 应触发播放/暂停切换');
    _player.calls.clear();

    // ── M:回退快照 muted=false → 期望 setMuted(true) ──────────────────
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyM);
    await _pumpFrames(tester, 2);
    expect(_player.calls, contains('muted:true'), reason: 'M 应切换静音');
    _player.calls.clear();

    // ── F:全屏接口当前是平台层空实现(见 live_player.dart),这里只断言
    //        按键确实把调用送到了接口,而不是被吞掉 ────────────────────
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    await _pumpFrames(tester, 2);
    expect(
      _player.calls,
      contains('fullscreen'),
      reason: 'F 应调用 toggleFullscreen 接口(平台层当前为空实现)',
    );
  });

  testWidgets('keyboardShortcuts:按键不能吞掉,输入框仍可正常输入', (tester) async {
    final container = (await _pumpPlay(tester)).container;

    // 把控制条与一个输入框放进同一页,验证 Shortcuts 只在控制条内生效、
    // 不拦截输入框的按键(未被 Focus 抢占)。
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                PlayerControlsBar(
                  site: 'douyu',
                  roomId: '63136',
                  showDanmaku: true,
                  danmakuEnabled: true,
                  onDanmakuToggle: () {},
                ),
                const TextField(key: Key('probe-field')),
              ],
            ),
          ),
        ),
      ),
    );
    await _pumpFrames(tester, 2);

    await tester.enterText(find.byKey(const Key('probe-field')), 'hello');
    await tester.pump(_kFrame);
    expect(find.text('hello'), findsOneWidget);

    // 输入框索焦后按 Space 应输入空格,而不是触发播放/暂停。
    final before = _player.calls.length;
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await _pumpFrames(tester, 2);
    expect(_player.calls.length, before, reason: '输入框聚焦时 Space 不应被控制条快捷键吞掉');
    expect(tester.takeException(), isNull);
  });

  testWidgets('danmakuToggle:按钮切舞台叠加层显隐,不误改设置总开关', (tester) async {
    final play = await _pumpPlay(tester);
    final container = play.container;
    await _awaitSettingsHydrated(tester, play.container);

    final toggle = find.byKey(const Key('play-toggle-danmaku'));
    expect(toggle, findsOneWidget, reason: '弹幕总开关开启时控制条应有弹幕按钮');

    final params = (site: 'douyu', roomId: '63136');
    expect(
      container.read(playControllerProvider(params)).value?.showDanmaku,
      isTrue,
    );

    await tester.tap(toggle);
    await _pumpFrames(tester, 2);
    expect(
      container.read(playControllerProvider(params)).value?.showDanmaku,
      isFalse,
      reason: '点击弹幕按钮应切换舞台叠加层显隐',
    );
    // 舞台显隐是会话态,不应污染设置项总开关。
    expect(_settingsOf(container).danmakuEnabled, isTrue);

    // 再点回显。
    await tester.tap(find.byKey(const Key('play-toggle-danmaku')));
    await _pumpFrames(tester, 2);
    expect(
      container.read(playControllerProvider(params)).value?.showDanmaku,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('danmakuToggle:设置总开关关闭时控制条不出现弹幕按钮', (tester) async {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.withData(<String, Object>{
          'zishu.settings.danmakuEnabled': false,
        });

    final play = await _pumpPlay(tester);
    final container = play.container;
    await _awaitSettingsHydrated(tester, play.container);
    await _pumpFrames(tester, 2);

    expect(_settingsOf(container).danmakuEnabled, isFalse);
    expect(
      find.byKey(const Key('play-toggle-danmaku')),
      findsNothing,
      reason: '设置里弹幕总开关关闭时不显示舞台弹幕按钮',
    );
    // 按钮隐藏不应影响其它控制项。
    expect(find.byKey(const Key('play-toggle-play')), findsOneWidget);
    expect(find.byKey(const Key('play-toggle-mute')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('clickStage:点视频帧切换播放/暂停,不误触控制条', (tester) async {
    await _pumpPlay(tester);

    // 点舞台中央(playerControls 区域之外的空白处)。
    await tester.tapAt(const Offset(200, 300));
    await _pumpFrames(tester, 2);
    expect(_player.calls, contains('play'), reason: '点击视频帧应切到播放');

    // 点控制条上的播放按钮:走按钮自身回调,同样落到 play 通路。
    final beforeButton = _player.calls.length;
    await tester.tap(find.byKey(const Key('play-toggle-play')));
    await _pumpFrames(tester, 2);
    expect(_player.calls.length, greaterThan(beforeButton));
    expect(tester.takeException(), isNull);
  });

  testWidgets('refreshStream:点刷新按钮重开当前线路,画质/线路不变', (tester) async {
    final play = await _pumpPlay(tester);
    final container = play.container;
    await _awaitSettingsHydrated(tester, container);

    final params = (site: 'douyu', roomId: '63136');
    final genBefore =
        container.read(playControllerProvider(params)).value?.generation ?? 0;
    expect(
      find.byKey(const Key('play-refresh-stream')),
      findsOneWidget,
      reason: '控制条应存在刷新视频按钮',
    );

    await tester.tap(find.byKey(const Key('play-refresh-stream')));
    await _pumpFrames(tester, 3);

    // 刷新走 retry 通路:build 已 bump 一代际,retry 再 +1;fixture 房间不真正
    // open 播放器(_openSelected 对 fixture 早返回),故用代际递增作 retry 路径证据。
    final genAfter =
        container.read(playControllerProvider(params)).value?.generation ?? 0;
    expect(
      genAfter,
      greaterThan(genBefore),
      reason: '刷新应经 retry 通路(代际递增),不重解析 payload',
    );

    // 刷新后弹 SnackBar「已刷新」。
    expect(find.text('已刷新'), findsOneWidget, reason: '刷新后应提示「已刷新」');

    // 刷新只重开流,不改变选中画质/线路。
    expect(
      container.read(playControllerProvider(params)).value?.quality?.name,
      '超清',
      reason: '刷新不应改变默认画质档',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('qualityMenuNarrow:窄屏画质收进下拉,菜单项可点切档', (tester) async {
    final play = await _pumpPlay(tester);
    final container = play.container;
    await _awaitSettingsHydrated(tester, play.container);

    // 切到窄屏视口(<1024):横向 chips 应收进菜单。
    tester.view.physicalSize = const Size(480, 900);
    tester.view.devicePixelRatio = 1.0;
    await _pumpFrames(tester, 3);

    // 菜单未打开时,横向画质 chip 不应在树上。
    expect(
      find.byKey(const Key('play-quality-超清')),
      findsNothing,
      reason: '窄屏下画质 chip 应收进下拉,菜单未打开时不在树上',
    );
    // 下拉入口与当前画质标签存在。
    expect(
      find.byKey(const Key('play-quality-menu')),
      findsOneWidget,
      reason: '窄屏应有画质下拉入口',
    );
    expect(
      find.byKey(const Key('play-quality-current')),
      findsOneWidget,
      reason: '窄屏下拉入口应暴露当前画质名标签',
    );

    // 打开画质下拉。pump 8 帧:等 PopupRoute 尺寸过渡完成,菜单项才可点
    // (实测 2 帧不够,尤其靠近菜单底部的项——过渡自顶向下展开)。
    await tester.tap(find.byKey(const Key('play-quality-menu')));
    await _pumpFrames(tester, 8);

    // 菜单项可见且可点。
    final item = find.byKey(const Key('play-quality-蓝光8M'));
    expect(item, findsOneWidget, reason: '下拉应展开画质菜单项');
    expect(item.hitTestable(), findsOneWidget, reason: '画质菜单项应可点');

    // 点选第二个画质:选中态更新(验证下拉切档通路)。
    await tester.tap(item);
    await _pumpFrames(tester, 2);
    expect(
      container
          .read(playControllerProvider((site: 'douyu', roomId: '63136')))
          .value
          ?.quality
          ?.name,
      '蓝光8M',
      reason: '窄屏下拉选画质应更新选中档',
    );
    expect(tester.takeException(), isNull);
  });
}
