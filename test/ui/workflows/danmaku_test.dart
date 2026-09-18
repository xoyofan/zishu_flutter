/// 弹幕 workflow test(A4:侧栏聊天接真实弹幕会话,消除「假绿」)。
///
/// 历史背景:`test/ui/workflows/danmaku_test.dart` 曾断言「PlaySidePanel 内含
/// 全角冒号的 RichText > 0」,但数据源是 `play_side_panel.dart` 里硬编码的
/// `_chatSamples`(12 条样例)——**用例通过,但不是真弹幕**。A4 把侧栏聊天改为
/// 消费 `danmakuSessionProvider` 的真实 [DanmakuMessage] 流后,本用例同步改为
/// **注入 fake connector 推送受控弹幕**并断言列表随之变化,以此证明数据来自会话
/// 而非硬编码。
///
/// 覆盖用例:
/// 1. danmakuRendersFromInjectedSession:注入会话推送既定弹幕后,侧栏出现对应
///    条目(不推就是空态,推什么就出现什么);
/// 2. danmakuVisualIntegrity:条目为「徽章? + 用户名 + '：' + 正文」富文本,
///    用户名 hash 着色(w600 + HSL 稳定色相)且与正文颜色区分,粉丝徽章存在;
/// 3. danmakuIsNotHardcoded:推送内容改变后断言随之变化——旧的硬编码样例
///    (星河不入梦/来了来了…)不再出现,新推送内容出现;并验证增量(先 2 条后加 1 条);
/// 4. danmakuPanelIsolatedFromRoomNav:聊天 → 关注 → 推荐 → 聊天 往返,条目数一致;
/// 5. playbackStatusIndicator:状态条左侧播放状态可配置(不依赖弹幕数据)。
///
/// 定位约定(与 driver [expectDanmakuEntries] 一致):
/// - 弹幕条目 = PlaySidePanel 内含「全角冒号」的 RichText。条目由
///   `Text.rich(TextSpan(children: [用户名, '：', 正文]))` 构建;Flutter 的
///   Text.build 会再包一层默认样式 wrapper span(剥壳见 [_danmakuRowSpan]);
/// - tab 标签(聊天/关注/推荐)、粉丝徽章(「粉丝 N」)、面板标题与提示文案、
///   侧栏信息头(「关注 —」「开播 —」)均不含全角冒号,不会误计。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart'
    show
        DanmakuConnector,
        DanmakuMessage,
        DanmakuMessageType,
        DanmakuSession,
        DanmakuSessionRequest,
        DanmakuSessionState,
        SiteCapabilities,
        SiteRegistration,
        SiteRegistry,
        StreamLine,
        buildSiteRegistry;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_session_provider.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';

/// 播放页深链位置(fixture 样例房间,与 navigation/layout 基线同房间)。
const String _playLocation = '/douyu/play/63136';

/// 固定时长 pump(TabBarView 切换动画 kTabScrollDuration≈300ms,4×100ms 足够),
/// 遵循 driver 约定不用 pumpAndSettle(封面图在 VM 中不会真正加载)。
Future<void> _pumpStable(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 弹幕条目 finder:侧栏内含全角冒号的 RichText(见文件头定位约定)。
Finder _danmakuEntries() {
  return find.descendant(
    of: find.byType(PlaySidePanel),
    matching: find.byWidgetPredicate(
      (widget) => widget is RichText && widget.text.toPlainText().contains('：'),
    ),
  );
}

/// 从条目 RichText 取业务 TextSpan:剥掉 Text.build 的默认样式 wrapper
/// (wrapper text == null 且仅 1 个 child),得到「[用户名, '：', 正文]」
/// 三 child 组合 span。
TextSpan _danmakuRowSpan(RichText entry) {
  var span = entry.text as TextSpan;
  while (span.text == null &&
      span.children != null &&
      span.children!.length == 1) {
    final inner = span.children!.single;
    if (inner is! TextSpan) break;
    span = inner;
  }
  return span;
}

/// 复刻 _ChatRow._userColor 的 hash 着色:用户名 codeUnits 按 31 进制累加
/// 取模 360 得稳定色相(SFVideoLive 同款思路,饱和度/亮度 0.6/0.68)。
Color _hashUserColor(String user) {
  var hash = 0;
  for (final unit in user.codeUnits) {
    hash = (hash * 31 + unit) % 360;
  }
  return HSLColor.fromAHSL(1, hash.toDouble(), 0.6, 0.68).toColor();
}

/// 统计当前聊天 tab 挂载的弹幕条目数。
int captureDanmakuCount(WidgetTester tester) =>
    tester.widgetList<RichText>(_danmakuEntries()).length;

/// 构造一条 chat 弹幕。
DanmakuMessage _chat(
  String userName,
  String text, {
  int badgeLevel = 0,
  String badgeName = '',
  int userLevel = 0,
  int color = 0,
}) {
  return DanmakuMessage(
    type: DanmakuMessageType.chat,
    roomId: '63136',
    userName: userName,
    userId: 'uid-$userName',
    text: text,
    badgeLevel: badgeLevel,
    badgeName: badgeName,
    userLevel: userLevel,
    color: color,
    rawType: 'chatmsg',
  );
}

/// 测试替身弹幕会话:由测试用 [StreamController] 完全驱动,不碰网络。
class _FakeDanmakuSession implements DanmakuSession {
  _FakeDanmakuSession();

  final messagesController = StreamController<DanmakuMessage>.broadcast();
  final statesController = StreamController<DanmakuSessionState>.broadcast();

  /// close 调用次数:用于验证 autoDispose 时真正释放会话(不泄漏)。
  int closeCount = 0;

  @override
  Stream<DanmakuMessage> get messages => messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => statesController.stream;

  /// 模拟连接建立。
  void emitConnected() => statesController.add(DanmakuSessionState.connected);

  /// 推送一条真实弹幕。
  void push(DanmakuMessage message) => messagesController.add(message);

  @override
  Future<void> close() async {
    closeCount += 1;
    await messagesController.close();
    await statesController.close();
  }
}

/// 测试替身 connector:记录 connect 请求,返回受控 [_FakeDanmakuSession]。
class _FakeDanmakuConnector implements DanmakuConnector {
  _FakeDanmakuConnector({this.supported = true});

  final bool supported;

  final List<DanmakuSessionRequest> requests = [];
  _FakeDanmakuSession? session;

  @override
  SiteCapabilities get capabilities => SiteCapabilities(danmaku: supported);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    requests.add(request);
    return session ??= _FakeDanmakuSession();
  }
}

/// 构造只替换斗鱼弹幕 connector 的注册表:其余(解析/浏览/搜索)沿用真实实现,
/// 保证房间解析仍走 fixture 默认链路(本用例只关心弹幕来源)。
SiteRegistry buildTestRegistry(DanmakuConnector connector) {
  final registry = buildSiteRegistry();
  final douyu = registry['douyu']!;
  registry.register(
    SiteRegistration(
      id: douyu.id,
      name: douyu.name,
      capabilities: douyu.capabilities,
      resolver: douyu.resolver,
      browse: douyu.browse,
      search: douyu.search,
      danmaku: connector,
    ),
  );
  return registry;
}

/// 测试替身:VM 下替代 MediaKitLivePlayer,不触碰任何原生播放内核。
class _FakeLivePlayer implements LivePlayer {
  _FakeLivePlayer();

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

/// 宿主:真实路由 + 主题,注入 FakeLivePlayer 与覆盖站点注册表的 fake connector。
///
/// 与 `platform_workflow.pumpPlatformApp` 同构,额外覆盖 [danmakuRegistryProvider]
/// —— 这正是本用例「证明消费真实会话而非硬编码」的关键:弹幕数据只能来自我们
/// 注入的 fake connector 所返回的会话。
Future<void> _pumpHost(WidgetTester tester, _FakeDanmakuConnector connector) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1600, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        playerProvider.overrideWithValue(_FakeLivePlayer()),
        danmakuRegistryProvider.overrideWithValue(buildTestRegistry(connector)),
      ],
      child: const _TestApp(),
    ),
  );
  await _pumpStable(tester);
}

/// 测试宿主:同 platform_workflow._TestApp(播放页无壳,补一层透明 Material)。
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

/// 从当前树取 GoRouter(Navigator 元素向上找 ProviderScope)。
GoRouter _router(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(Navigator).first))
        .read(routerProvider);

/// 导航到播放页。
void _goPlay(WidgetTester tester) {
  _router(tester).go(_playLocation);
}

void main() {
  testWidgets('danmakuRendersFromInjectedSession:推送真实弹幕后侧栏出现对应条目', (
    tester,
  ) async {
    final connector = _FakeDanmakuConnector();
    await _pumpHost(tester, connector);

    // 进入播放页(聊天 tab 为默认页)。
    _goPlay(tester);
    await _pumpStable(tester);
    expect(find.byType(PlaySidePanel), findsOneWidget);

    // 未推送前:列表为空态(证明不是硬编码常驻样例)。
    expect(captureDanmakuCount(tester), 0, reason: '未推送时不应有弹幕条目');
    expect(find.text('暂无弹幕，等待水友发言…'), findsOneWidget);

    // connector 确实按 (site, roomId) 发起了连接。
    expect(connector.requests, isNotEmpty);
    expect(connector.requests.last.site, 'douyu');
    expect(connector.requests.last.roomId, '63136');

    final session = connector.session!;
    session.emitConnected();
    session.push(_chat('星河不入梦', '来了来了，主播这波操作可以', badgeLevel: 12));
    session.push(_chat('奶茶三分甜', '晚上好呀，刚下班就来蹲直播'));
    await _pumpStable(tester);

    expect(captureDanmakuCount(tester), 2, reason: '推送 2 条应渲染 2 条');
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('星河不入梦：'),
        ),
      ),
      findsOneWidget,
      reason: '应出现注入会话推送的用户名条目',
    );
    expect(find.text('弹幕已连接'), findsOneWidget);
  });

  testWidgets('danmakuIsNotHardcoded:推送内容变化,列表随之变化(证明非硬编码)', (
    tester,
  ) async {
    final connector = _FakeDanmakuConnector();
    await _pumpHost(tester, connector);
    _goPlay(tester);
    await _pumpStable(tester);

    final session = connector.session!;
    session.push(_chat('真实水友甲', '这条来自会话 A'));
    session.push(_chat('真实水友乙', '这条来自会话 B'));
    await _pumpStable(tester);
    expect(captureDanmakuCount(tester), 2);

    // 硬编码样例的用户名/文案不得出现(旧 `_chatSamples` 的钉死值)。
    // 旧实现(任务 A4 之前)硬编码 12 条样例,其中首条正是下面这组;若仍是
    // 硬编码,即使一条弹幕都不推也会渲染这些文本 —— 这里显式证明它们不存在。
    const legacyMessage = '来了来了，主播这波操作可以';
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().contains(legacyMessage),
        ),
      ),
      findsNothing,
      reason: '硬编码样例文案「$legacyMessage」不得出现',
    );
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('星河不入梦：'),
        ),
      ),
      findsNothing,
      reason: '硬编码样例用户名「星河不入梦」不得出现',
    );

    // 再推一条:条目增量 +1,且新内容出现 —— 列表完全跟随注入流。
    session.push(_chat('真实水友丙', '这条来自会话 C'));
    await _pumpStable(tester);
    expect(
      captureDanmakuCount(tester),
      3,
      reason: '追加推送后条目应随之增加(证明列表由会话流驱动)',
    );
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is RichText &&
              widget.text.toPlainText().startsWith('真实水友丙：'),
        ),
      ),
      findsOneWidget,
    );
  });

  testWidgets('danmakuBadges:粉丝牌(名+级)/等级圆盘/用户等级 pill 对齐 web 语义', (
    tester,
  ) async {
    final connector = _FakeDanmakuConnector();
    await _pumpHost(tester, connector);
    _goPlay(tester);
    await _pumpStable(tester);

    final session = connector.session!;
    session.emitConnected();
    // 斗鱼/B 站/虎牙式:有团名 → 名牌「团名 级」。
    session.push(_chat('徽章哥', '都有', badgeLevel: 12, badgeName: '提督骑士团', userLevel: 31));
    // 抖音式:无团名 → 仅等级圆盘(对齐 web douyinTextFallback)。
    session.push(_chat('抖音哥', '仅圆盘', badgeLevel: 10, userLevel: 18));
    // 素人:无徽章 → 不渲染任何徽章,也不渲染 Lv 0。
    session.push(_chat('素人', '无徽章'));
    await _pumpStable(tester);

    expect(find.text('提督骑士团 12'), findsOneWidget,
        reason: '有团名时粉丝牌显示「团名 级」');
    expect(find.text('10'), findsOneWidget, reason: '无团名时仅显示等级(斗鱼胶囊兜底)');
    // 斗鱼 UL 文字兜底对齐 web buildDouyuUserLevelStyle:「LV N」。
    expect(find.text('LV31'), findsOneWidget);
    expect(find.text('LV18'), findsOneWidget);
    expect(find.text('Lv 0'), findsNothing, reason: '无等级不渲染占位');

    // 徽章顺序对齐 web SideChatTab.vue:38-44:平台等级 pill 在粉丝牌之前
    // (同一行内按 x 坐标比较;「徽章哥」一条同时带 LV31 与粉丝牌)。
    final levelRect = tester.getRect(find.text('LV31'));
    final fanRect = tester.getRect(find.text('提督骑士团 12'));
    expect(levelRect.left, lessThan(fanRect.left),
        reason: '平台等级(用户口径:平台等级在粉丝等级前)应排在粉丝牌左边');
    // 两枚徽章由同一 Row 水平排布;高度不同(胶囊 vs 渐变条)顶部可差零点几
    // 像素,用容差断言"同一行"而非严格相等。
    expect((levelRect.top - fanRect.top).abs(), lessThan(8.0),
        reason: '两枚徽章应渲染在同一行');
  });

  testWidgets('danmakuVisualIntegrity:富文本结构完整,hash 着色+粉丝徽章', (
    tester,
  ) async {
    final connector = _FakeDanmakuConnector();
    await _pumpHost(tester, connector);
    _goPlay(tester);
    await _pumpStable(tester);

    final session = connector.session!;
    session.push(_chat('星河不入梦', '来了来了，主播这波操作可以', badgeLevel: 12));
    session.push(_chat('皮蛋solo', '这波是教科书级别，学会了吗', badgeLevel: 7));
    await _pumpStable(tester);

    final entries = tester.widgetList<RichText>(_danmakuEntries()).toList();
    expect(entries, isNotEmpty);
    // 通用结构:每条目均为 [用户名 span, '：' span, 正文 span] 三段组合,
    // 用户名 w600 加粗 + 独立颜色(与正文 textPrimary 区分)。
    for (final entry in entries) {
      final label = entry.text.toPlainText();
      final row = _danmakuRowSpan(entry);
      expect(row.children, isNotNull, reason: '弹幕条目应为 TextSpan 组合:$label');
      expect(
        row.children!.length,
        3,
        reason: '弹幕条目结构应为 用户名+冒号+正文 三段:$label',
      );
      final userSpan = row.children![0] as TextSpan;
      final colonSpan = row.children![1] as TextSpan;
      final messageSpan = row.children![2] as TextSpan;
      expect(colonSpan.text, '：', reason: '$label 应以全角冒号分隔用户名与正文');
      expect(userSpan.text, isNotEmpty, reason: '用户名 span 文本非空:$label');
      expect(messageSpan.text, isNotEmpty, reason: '正文 span 文本非空:$label');
      expect(
        userSpan.style?.fontWeight,
        FontWeight.w600,
        reason: '用户名「${userSpan.text}」应为 w600 加粗',
      );
      expect(
        userSpan.style?.color,
        isNotNull,
        reason: '用户名「${userSpan.text}」应有独立颜色',
      );
      expect(
        userSpan.style?.color,
        isNot(messageSpan.style?.color),
        reason: '用户名「${userSpan.text}」颜色应与正文区分',
      );
    }

    // hash 着色钉死校验:注入的用户名颜色 == 复刻算法计算值(31 进制 hash → HSL 0.6/0.68)。
    const pinnedUser = '星河不入梦';
    final pinnedFinder = find.descendant(
      of: find.byType(PlaySidePanel),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith('$pinnedUser：'),
      ),
    );
    expect(pinnedFinder, findsOneWidget, reason: '应存在注入会话的弹幕「$pinnedUser」');
    final pinnedRow = _danmakuRowSpan(tester.widget<RichText>(pinnedFinder));
    final pinnedSpans = pinnedRow.children!;
    expect((pinnedSpans[0] as TextSpan).text, pinnedUser);
    expect((pinnedSpans[2] as TextSpan).text, '来了来了，主播这波操作可以');
    expect(
      (pinnedSpans[0] as TextSpan).style?.color,
      _hashUserColor(pinnedUser),
      reason: '用户名颜色应按 hash(用户名) 稳定色相计算',
    );

    // 粉丝团徽章:「badgeLevel > 0」且无团名(构造未传 badgeName)→
    // 渲染纯等级圆盘「N」(对齐 web douyinTextFallback 分支)。
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.text('12'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.text('7'),
      ),
      findsOneWidget,
      reason: '两条注入消息均带徽章(等级 12/7),应各渲染一个等级圆盘',
    );
  });

  testWidgets('danmakuPanelIsolatedFromRoomNav:切关注/推荐再切回聊天条目仍在', (
    tester,
  ) async {
    final connector = _FakeDanmakuConnector();
    await _pumpHost(tester, connector);
    _goPlay(tester);
    await _pumpStable(tester);

    final session = connector.session!;
    session.push(_chat('星河不入梦', '来了来了，主播这波操作可以'));
    session.push(_chat('奶茶三分甜', '晚上好呀，刚下班就来蹲直播'));
    session.push(_chat('皮蛋solo', '这波是教科书级别，学会了吗'));
    await _pumpStable(tester);
    final countBefore = captureDanmakuCount(tester);
    expect(countBefore, 3);

    // 切「关注」:关注面板出现。
    await tester.tap(find.byKey(const Key('play-side-tab-follow')));
    await _pumpStable(tester);
    expect(find.byKey(const Key('play-side-follow-panel')), findsOneWidget);
    // 侧栏面板内的标题(壳层顶栏也有「我的关注」入口,故限定在面板子树内)。
    expect(
      find.descendant(
        of: find.byKey(const Key('play-side-follow-panel')),
        matching: find.text('我的关注'),
      ),
      findsOneWidget,
    );

    // 切「推荐」:推荐面板出现。
    await tester.tap(find.byKey(const Key('play-side-tab-recommend')));
    await _pumpStable(tester);
    expect(find.byKey(const Key('play-side-recommend-panel')), findsOneWidget);
    expect(find.text('相关推荐'), findsOneWidget);

    // 切回「聊天」:条目数与切换前一致——会话不因 tab 切换而重建/丢消息。
    await tester.tap(find.byKey(const Key('play-side-tab-chat')));
    await _pumpStable(tester);
    expect(
      captureDanmakuCount(tester),
      countBefore,
      reason: '往返切换 tab 后弹幕条目应原样恢复',
    );
  });

  testWidgets('danmakuSessionReleased:离开播放页后会话被 close(autoDispose 不泄漏)', (
    tester,
  ) async {
    final connector = _FakeDanmakuConnector();
    await _pumpHost(tester, connector);
    _goPlay(tester);
    await _pumpStable(tester);

    final session = connector.session!;
    session.push(_chat('星河不入梦', '来了来了'));
    await _pumpStable(tester);
    expect(session.closeCount, 0);

    // 回首页:播放页销毁 → autoDispose → 会话 close。
    _router(tester).go('/all');
    await _pumpStable(tester);
    await _pumpStable(tester);
    expect(find.byType(PlaySidePanel), findsNothing, reason: '应已离开播放页');

    // close() 是异步的(onDispose 内 fire-and-forget),用 runAsync 让真实异步完成。
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await _pumpStable(tester);
    expect(
      session.closeCount,
      greaterThanOrEqualTo(1),
      reason: '离开播放页后弹幕会话应被 close(autoDispose),避免连接泄漏',
    );
  });

  testWidgets('danmakuUnsupportedSite:站点不支持弹幕时显示空态而非崩溃', (
    tester,
  ) async {
    final connector = _FakeDanmakuConnector(supported: false);
    await _pumpHost(tester, connector);
    _goPlay(tester);
    await _pumpStable(tester);

    expect(find.text('弹幕不支持'), findsOneWidget);
    expect(captureDanmakuCount(tester), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('playbackStatusIndicator:聊天状态条左侧播放状态可配置', (
    tester,
  ) async {
    // 直泵 PlaySidePanel(上下文 tokens 回退 ZishuTokens.dark),验证状态条左侧
    // 播放指示随 PlaybackStatus 变化;文案避免全角冒号。
    Future<void> pumpWith(PlaybackStatus status) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            danmakuRegistryProvider.overrideWithValue(
              buildTestRegistry(_FakeDanmakuConnector()),
            ),
          ],
          child: MaterialApp(
            theme: ZishuTheme.dark(),
            home: Scaffold(
              body: SizedBox(
                width: 392,
                child: PlaySidePanel(
                  site: 'douyu',
                  roomId: '63136',
                  playbackStatus: status,
                ),
              ),
            ),
          ),
        ),
      );
      await _pumpStable(tester);
    }

    // 默认(无参)= 播放中
    await pumpWith(const PlaybackStatus());
    expect(find.text('播放中'), findsOneWidget);
    expect(find.text('已暂停'), findsNothing);

    // 静音态:播放中(静音)
    await pumpWith(const PlaybackStatus(muted: true));
    expect(find.text('播放中(静音)'), findsOneWidget);
    expect(find.text('播放中'), findsNothing);

    // 暂停态:已暂停
    await pumpWith(const PlaybackStatus(playing: false));
    expect(find.text('已暂停'), findsOneWidget);

    // 状态指示与「重新连接」按钮并排。
    expect(find.byKey(const Key('play-side-chat-refresh')), findsOneWidget);
  });
}
