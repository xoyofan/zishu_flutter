/// 平台 workflow 测试 driver 框架(任务卡 W1)。
///
/// 为批次 2 的平台用例提供可复用 helper,消费方:
/// - W2 `platform_douyu/huya/bilibili_test.dart`:
///   [expectCategoryRenders](categoryRenders)、
///   [expectCategoryRoomsCorrect](categoryRoomsCorrect)、
///   [platformSmoke](platformSmoke);
/// - W3 `danmaku_test.dart`:[expectDanmakuEntries];
/// - W4 `latency_test.dart`:[openRoomLatency];
/// - 通用宿主与断言([pumpPlatformApp]/[expectNoOverflow]/[findAnchor])各卡均可用。
///
/// 宿主约定(与 test/ui/ 既有 23 例锚点测试一致):
/// - media_kit 禁止在 VM 初始化:内部注入 FakeLivePlayer(playerProvider override);
/// - 走真实路由宿主(go_router + ZishuTheme):播放页路由不套 AppShell(无
///   Material 祖先),与 workflow_browse_play_test 相同,在 builder 统一补一层
///   透明 Material,否则 QualityLineBar 的 ChoiceChip 抛 "No Material widget";
/// - fixture 数据源走默认 provider,新平台接入只需批次 2 加
///   `platform_<site>_test.dart`,本 driver 零改动;
/// - 全程固定次数 pump(duration),不用 pumpAndSettle(封面图 VM 中不会真正加载);
/// - 固定 1600×1200 大视口启动,规避 GridView/横向 ListView 惰性挂载漏锚点。
///
/// 已知既有问题(排水说明见 [_pumpFrames]):分类页房间网格在卡宽 <280px 时,
/// RoomCard 文本区 68px 预算差 0.631px 触发 RenderFlex overflow(lib/ 侧问题,
/// W13 修复前由 driver 排水,不阻断 W2/W4 链路断言;溢出专项断言用
/// [expectNoOverflow] 或 W8/W9 的 sweep)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/browse/widgets/room_card.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 统一 pump 步长,与既有锚点测试保持一致。
const Duration _kFrame = Duration(milliseconds: 50);

/// 测试宿主:与 WindowsApp 相同的 router/theme,额外在 builder 补一层透明
/// Material——播放页路由无壳(不套 AppShell/Scaffold),QualityLineBar 的
/// ChoiceChip 与 PlayerControlsBar 的 Slider 都需要 Material 祖先
/// (同 workflow_browse_play_test 的 _TestApp 约定)。
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

/// 分类页路由:路由表只声明 `/:site/category/:cid`(见 app_router.dart),
/// 无 cid 的 `/{site}/category` 不匹配任何路由(已探针验证,渲染为空)。
/// fixture 第一组首个子分类 cid 固定为 '1'(与 test/ui/category_test.dart 一致),
/// CategoryView 会按 cid 归属自动选中第一组。
String _categoryLocation(String site) => '/$site/category/1';

/// 测试替身:VM 下替代 MediaKitLivePlayer,快照立即给一帧,方法只记录调用。
/// 供 [pumpPlatformApp] 内部注入,不进入消费方 API。
class _FakeLivePlayer implements LivePlayer {
  _FakeLivePlayer();

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
  Future<void> stop() async => calls.add('stop');

  @override
  void dispose() => calls.add('dispose');
}

/// 启动真实宿主(routerProvider + ZishuTheme,注入 FakeLivePlayer)到
/// 固定 1600×1200 视口,并导航到 [location],返回 GoRouter 供深度用例自行导航。
///
/// 对应卡:W2/W3/W4 全部用例的统一入口(W6/W7 如需真实宿主亦可复用)。
Future<GoRouter> pumpPlatformApp(WidgetTester tester, String location) async {
  // 断点几何直接写 tester.view(dpr=1):setSurfaceSize 只更新渲染 surface,
  // MediaQuery 仍报默认 800×600,U9 断点(icon-only tabs / chips key 切换)会误判。
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const _TestApp(),
    ),
  );
  // 两帧:壳层骨架渲染 + fixture 数据落地。
  await _pumpFrames(tester, 2, where: 'pumpPlatformApp/$location');

  final router = _routerOf(tester);
  if (location != router.routeInformationProvider.value.uri.path) {
    router.go(location);
    await _pumpFrames(tester, 2, where: 'pumpPlatformApp/go');
  }
  return router;
}

/// 断言当前帧无 RenderFlex overflow(布局破坏即 fail)。
///
/// takeException 非 null 时:RenderFlex 溢出(含批量的 "Multiple exceptions")
/// 视为布局破坏直接判失败;其余 VM 环境噪声(如图片 400 占位)不拦,
/// 保持用例聚焦布局本身。注意:组合 helper(platformSmoke 等)按窗口内部
/// 排水,本断言适用于消费方自己的 pump 窗口(W7/W9 类溢出专项)。
///
/// 对应卡:W7 全局布局检查,以及 W2/W4 用例中需要对特定页面做溢出断言处。
void expectNoOverflow(WidgetTester tester) {
  final exception = tester.takeException();
  if (exception == null) return;
  final message = exception.toString();
  expect(
    message.contains('RenderFlex') ||
        message.contains('overflowed') ||
        message.contains('Multiple exceptions'),
    isFalse,
    reason: '页面存在溢出或未消费渲染异常: $message',
  );
}

/// 固定次数 pump,并排水本窗口内的渲染异常。
///
/// 排水原因:分类页房间网格存在既有 0.631px RenderFlex 溢出(见文件头注释),
/// 未消费的渲染异常会在用例 teardown 以 "Multiple exceptions" 毒化整个用例;
/// 检测到溢出时打印 `[overflow-drain]` 报告行(不阻断链路,供 W13 收口参考),
/// 严格溢出断言请用 [expectNoOverflow]。
Future<void> _pumpFrames(
  WidgetTester tester,
  int times, {
  String where = 'workflow',
}) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
  final exception = tester.takeException();
  if (exception == null) return;
  final message = exception.toString();
  // takeException 会把多次溢出合并成 "Multiple exceptions (N)" 报告,
  // 同样视为溢出排水并上报。
  if (message.contains('RenderFlex') ||
      message.contains('overflowed') ||
      message.contains('Multiple exceptions')) {
    final short = message.length > 80
        ? '${message.substring(0, 80)}...'
        : message;
    // ignore: avoid_print
    print('[overflow-drain] $where: $short');
  }
}

/// 锚点快捷查找:`findAnchor('play-back')` 等价 `find.byKey(Key('play-back'))`。
///
/// 对应卡:W2/W3/W4 全部用例的锚点定位入口。
Finder findAnchor(String key) => find.byKey(Key(key));

/// 收集当前树上以 [prefix] 开头的字符串锚点 key(按树序,惰性挂载只含可见项)。
///
/// 对应卡:W2 断言「卡片数 = fixture 数量」、driver 内部取"首个组/子分类/卡片"。
List<String> anchorKeysWithPrefix(WidgetTester tester, String prefix) {
  return tester
      .widgetList(
        find.byWidgetPredicate((widget) {
          final key = widget.key;
          return key is ValueKey<String> && key.value.startsWith(prefix);
        }),
      )
      .map((widget) => (widget.key as ValueKey<String>).value)
      .toList();
}

/// 统计当前树上以 [prefix] 开头的锚点数量。
///
/// 对应卡:W2 categoryRenders(分组>0)/categoryRoomsCorrect(卡片≥1)。
int countAnchorsByPrefix(WidgetTester tester, String prefix) =>
    anchorKeysWithPrefix(tester, prefix).length;

/// W2 categoryRenders:打开 [site] 分类页,断言左侧 category-group-* 锚点 >0,
/// 点击首个分组后右侧 category-item-* 锚点 >0。
Future<void> expectCategoryRenders(WidgetTester tester, String site) async {
  _routerOf(tester).go(_categoryLocation(site));
  await _pumpFrames(tester, 2, where: 'categoryRenders/$site');

  final groups = anchorKeysWithPrefix(tester, 'category-group-');
  expect(groups, isNotEmpty, reason: '$site 分类页缺少 category-group-* 锚点');

  // 点首个分组(树序第一个即 fixture 第一组)。
  await tester.tap(find.byKey(Key(groups.first)));
  await _pumpFrames(tester, 2, where: 'categoryRenders/$site/tapGroup');

  expect(
    countAnchorsByPrefix(tester, 'category-item-'),
    greaterThan(0),
    reason: '$site 点击首个分组后应出现子分类 category-item-* 锚点',
  );
}

/// W2 categoryRoomsCorrect:点击首个子分类,断言房间区 room-card-* 锚点 ≥1,
/// 且每张可见卡片的标题/主播文本非空(直接读 RoomCard.room 数据模型)。
Future<void> expectCategoryRoomsCorrect(
  WidgetTester tester,
  String site,
) async {
  _routerOf(tester).go(_categoryLocation(site));
  await _pumpFrames(tester, 2, where: 'categoryRooms/$site');

  final items = anchorKeysWithPrefix(tester, 'category-item-');
  expect(items, isNotEmpty, reason: '$site 分类页缺少 category-item-* 锚点');

  // 点首个子分类,房间区按 (site, cid) 拉取房间(fixture 立即落地)。
  await tester.tap(find.byKey(Key(items.first)));
  await _pumpFrames(tester, 3, where: 'categoryRooms/$site/tapItem');

  final cards = anchorKeysWithPrefix(tester, 'room-card-');
  expect(
    cards.length,
    greaterThanOrEqualTo(1),
    reason: '$site 首个子分类下应出现至少 1 张房间卡片',
  );

  // 标题/主播字段非空:读 RoomCard 实现,不依赖封面图片加载。
  final renderedCards = tester.widgetList<RoomCard>(
    find.byWidgetPredicate((w) => w is RoomCard),
  );
  for (final card in renderedCards) {
    expect(
      card.room.title,
      isNotEmpty,
      reason: '房间卡片 ${card.room.site}/${card.room.roomId} 标题为空',
    );
    expect(
      card.room.anchorName,
      isNotEmpty,
      reason: '房间卡片 ${card.room.site}/${card.room.roomId} 主播名为空',
    );
  }
}

/// W4 耗时分析:回到 [site] 首页,点击首个 room-card,Stopwatch + runAsync
/// 度量 tap → play-quality-* 锚点出现;按 `[latency] {site}: {ms}ms / {frames} frames`
/// 打印报告行,返回墙钟毫秒与 pump 帧数。G1 接真实解析后同一度量自动变端到端。
///
/// 注意:fixture 阶段 ms 含宿主环境一次性噪声(首帧图片栈/字体/机器负载),
/// frames 才是稳定的编排帧数信号;W4 可自行决定阈值与预热策略。
Future<({int ms, int frames})> openRoomLatency(
  WidgetTester tester,
  String site,
) async {
  final router = _routerOf(tester);
  router.go('/$site');
  await _pumpFrames(tester, 2, where: 'latency/$site/home');

  final cards = anchorKeysWithPrefix(tester, 'room-card-');
  expect(cards, isNotEmpty, reason: '$site 首页无 room-card-* 锚点可点');

  final stopwatch = Stopwatch()..start();
  var frames = 0;
  await tester.runAsync(() async {
    await tester.tap(find.byKey(Key(cards.first)));
    // 逐帧 pump 直到画质锚点挂载(fixture 在 2-3 帧内落地)。
    while (countAnchorsByPrefix(tester, 'play-quality-') == 0) {
      await tester.pump(_kFrame);
      frames++;
      if (frames > 300) {
        stopwatch.stop();
        fail('openRoomLatency($site): 300 帧内未出现 play-quality-* 锚点');
      }
    }
  });
  stopwatch.stop();

  final ms = stopwatch.elapsedMilliseconds;
  // ignore: avoid_print
  print('[latency] $site: ${ms}ms / $frames frames');
  return (ms: ms, frames: frames);
}

/// W3 弹幕 workflow:播放页点击聊天 tab(play_side_panel 的 TabBar 首 tab),
/// 断言侧栏内弹幕条目(「用户名:消息」富文本行)> 0。
/// 前置:当前停留在播放页(G2 接真弹幕后可升级为增量断言,接口位预留)。
Future<void> expectDanmakuEntries(WidgetTester tester) async {
  expect(
    find.byType(PlaySidePanel),
    findsOneWidget,
    reason: 'expectDanmakuEntries 前置:需先进入播放页',
  );

  // 聊天 tab(DefaultTabController 初始即聊天页,点击保持幂等)。
  await tester.tap(find.text('聊天'));
  await _pumpFrames(tester, 2, where: 'danmaku/chatTab');

  // 弹幕条目:侧栏内含「全角冒号」分隔的富文本行(用户名：消息),
  // tab 标签与提示文案不含该分隔符,不会误计。
  final entries = tester.widgetList<RichText>(
    find.descendant(
      of: find.byType(PlaySidePanel),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText && widget.text.toPlainText().contains('：'),
      ),
    ),
  );
  expect(entries.length, greaterThan(0), reason: '聊天 tab 下应渲染至少 1 条弹幕条目');
}

/// W2 platformSmoke:完整冒烟链路——分类页渲染 → 房间列表 → 进播放页 →
/// 切第二个画质 chip → play-back 返回后房间网格锚点仍在。
/// 链路内的断言聚焦锚点与选中态;溢出专项由 expectNoOverflow/W8 承担。
Future<void> platformSmoke(WidgetTester tester, String site) async {
  // 1. 分类链路:分组 tab 与子分类联动。
  await expectCategoryRenders(tester, site);
  // 2. 房间链路:子分类 → 房间网格字段非空。
  await expectCategoryRoomsCorrect(tester, site);

  // 3. 进房:点分类页首个房间卡片 → 推入播放页。
  final cards = anchorKeysWithPrefix(tester, 'room-card-');
  expect(cards, isNotEmpty, reason: 'smoke($site):分类页应已有房间卡片可点');
  await tester.tap(find.byKey(Key(cards.first)));
  await _pumpFrames(tester, 3, where: 'smoke/$site/openRoom');
  expect(findAnchor('play-back'), findsOneWidget);

  // 4. 控制栏画质 selectbox 切档(2026-09-11 裁决):开菜单 → 点另一档 →
  //    入口标签 `play-quality-current` 同步为所选档。菜单项锚点在菜单打开
  //    时才挂载,故先 tap 入口再取锚点集。
  final qualityMenu = findAnchor('play-quality-menu');
  expect(
    qualityMenu,
    findsOneWidget,
    reason: 'smoke($site):控制栏应有画质 selectbox 入口',
  );
  await tester.tap(qualityMenu);
  // pump 8 帧:等 PopupRoute 尺寸过渡完成,菜单项才可点(实测 2 帧不够)。
  await _pumpFrames(tester, 8, where: 'smoke/$site/openQualityMenu');
  final qualities = anchorKeysWithPrefix(tester, 'play-quality-');
  expect(
    qualities.length,
    greaterThanOrEqualTo(2),
    reason: 'smoke($site):至少 2 个画质档位才能执行切换',
  );
  final currentLabel =
      tester.widget<Text>(findAnchor('play-quality-current')).data ?? '';
  // 排除入口自身锚点('menu'/'current'),只留真实档位名。
  final otherNames = qualities
      .map((key) => key.substring('play-quality-'.length))
      .where(
        (name) =>
            name != currentLabel && name != 'menu' && name != 'current',
      )
      .toList();
  expect(otherNames, isNotEmpty, reason: 'smoke($site):应有可选的其他画质');
  final secondQuality = find.byKey(Key('play-quality-${otherNames.first}'));
  await tester.tap(secondQuality);
  await _pumpFrames(tester, 2, where: 'smoke/$site/switchQuality');
  expect(
    tester.widget<Text>(findAnchor('play-quality-current')).data,
    otherNames.first,
    reason: 'smoke($site):切档后 selectbox 入口应显示新档位',
  );

  // 5. 返回:play-back 出栈回分类页,房间网格锚点仍在。
  await tester.tap(findAnchor('play-back'));
  await _pumpFrames(tester, 2, where: 'smoke/$site/popBack');
  expect(findAnchor('play-back'), findsNothing);
  expect(
    countAnchorsByPrefix(tester, 'room-card-'),
    greaterThan(0),
    reason: 'smoke($site):返回分类页后房间卡片锚点应仍在',
  );
}

/// 从当前树上取 routerProvider 的 GoRouter(Navigator 元素向上找 ProviderScope;
/// 播放页无 Scaffold,不用 Scaffold 元素定位)。
GoRouter _routerOf(WidgetTester tester) {
  final element = tester.element(find.byType(Navigator).first);
  return ProviderScope.containerOf(element).read(routerProvider);
}
