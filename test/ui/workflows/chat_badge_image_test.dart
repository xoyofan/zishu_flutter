/// 聊天徽章本地图片(assets/badges/)workflow test:
/// 「本地图片优先 → 既有文字态兜底」。
///
/// 对齐 SFVideoLive web 消费侧:
/// - 路径规则:`apps/web/src/utils/badges/platformBadgeStatic.ts`(分段 + 上限);
/// - 站点分支:`ChatFanBadge.vue`(douyu 官方牌整图/douyin img-only/huya 渐变条/
///   bilibili 边框图)与 `ChatUserLevelBadge.vue`(huya emblem 叠数字/douyin honor);
/// - 资产清单:`web/public/assets/badges/manifest.json`(honorMax/fansMax/vipEmblems)。
///
/// 覆盖:
/// 1. badgeAssetPath:各站/类/档位分段与越界('');
/// 2. ChatBadgeImage:无资产 → shrink + onFail;真实资产可在测试环境解码渲染;
/// 3. 弹幕行集成:douyu 官方牌 + 团名叠层/UL 文字不变、huya 粉丝条不变 +
///    emblem 叠数字、douyin 粉丝牌与 honor 整图、超档资产缺失回落文字态。
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
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
        buildSiteRegistry;
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_session_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/chat_badge_image.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';

/// 测试替身弹幕会话(同 danmaku_test 思路,由测试完全驱动,不碰网络)。
class _FakeDanmakuSession implements DanmakuSession {
  final messagesController = StreamController<DanmakuMessage>.broadcast();
  final statesController = StreamController<DanmakuSessionState>.broadcast();

  @override
  Stream<DanmakuMessage> get messages => messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => statesController.stream;

  void emitConnected() => statesController.add(DanmakuSessionState.connected);

  void push(DanmakuMessage message) => messagesController.add(message);

  @override
  Future<void> close() async {
    await messagesController.close();
    await statesController.close();
  }
}

class _FakeDanmakuConnector implements DanmakuConnector {
  _FakeDanmakuSession? session;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    return session ??= _FakeDanmakuSession();
  }
}

/// 构造仅替换 [siteId] 弹幕 connector 的注册表(真实解析/浏览沿用 fixture 链路,
/// 其余站 connector 不动 —— 测试只关心当前面板的聊天行,避免真实网络连接)。
SiteRegistry _registryFor(String siteId, DanmakuConnector connector) {
  final registry = buildSiteRegistry();
  final target = registry[siteId]!;
  registry.register(
    SiteRegistration(
      id: target.id,
      name: target.name,
      capabilities: target.capabilities,
      resolver: target.resolver,
      browse: target.browse,
      search: target.search,
      danmaku: connector,
    ),
  );
  return registry;
}

DanmakuMessage _chat(
  String userName,
  String text, {
  int badgeLevel = 0,
  String badgeName = '',
  int userLevel = 0,
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
    rawType: 'chatmsg',
  );
}

/// 直泵 PlaySidePanel(同 danmaku_test playbackStatusIndicator 用例:
/// 上下文 tokens 回退 ZishuTokens.dark;392 宽,聊天 tab 为默认页)。
Future<void> _pumpPanel(
  WidgetTester tester,
  String site, {
  required _FakeDanmakuConnector connector,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(500, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        danmakuRegistryProvider
            .overrideWithValue(_registryFor(site, connector)),
      ],
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 392,
            child: PlaySidePanel(site: site, roomId: '63136'),
          ),
        ),
      ),
    ),
  );
  await _pumpStable(tester);
}

/// 固定时长 pump(遵循 driver 约定不用 pumpAndSettle)。
Future<void> _pumpStable(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// 取 connector 会话(面板挂载即已发起 connect)。
_FakeDanmakuSession _connected(_FakeDanmakuConnector connector) {
  final session = connector.session;
  if (session == null) {
    throw StateError('PlaySidePanel 未发起弹幕连接');
  }
  return session;
}

ChatBadgeImage? _badgeImage(WidgetTester tester, {String? assetPath}) {
  for (final widget in tester.widgetList<ChatBadgeImage>(
    find.byType(ChatBadgeImage),
  )) {
    if (assetPath == null || widget.assetPath == assetPath) return widget;
  }
  return null;
}

void main() {
  group('badgeAssetPath:web platformBadgeStatic 路径规则', () {
    test('douyin fans 1..20 有图,0/21 越界无图', () {
      expect(
        badgeAssetPath(site: 'douyin', kind: ChatBadgeKind.fans, level: 1),
        'assets/badges/douyin/fans/1.png',
      );
      expect(
        badgeAssetPath(site: 'douyin', kind: ChatBadgeKind.fans, level: 20),
        'assets/badges/douyin/fans/20.png',
      );
      expect(
        badgeAssetPath(site: 'douyin', kind: ChatBadgeKind.fans, level: 0),
        '',
      );
      expect(
        badgeAssetPath(site: 'douyin', kind: ChatBadgeKind.fans, level: 21),
        '',
      );
    });

    test('douyin honor 1..75 有图,76 超档无图(VIP/SVIP 尾档覆盖)', () {
      expect(
        badgeAssetPath(site: 'douyin', kind: ChatBadgeKind.userLevel, level: 1),
        'assets/badges/douyin/honor/1.png',
      );
      // 抖音高消费档(用户口径:特别是 VIP/SVIP)。
      expect(
        badgeAssetPath(
          site: 'douyin',
          kind: ChatBadgeKind.userLevel,
          level: 75,
        ),
        'assets/badges/douyin/honor/75.png',
      );
      expect(
        badgeAssetPath(
          site: 'douyin',
          kind: ChatBadgeKind.userLevel,
          level: 76,
        ),
        '',
      );
    });

    test('douyu fans 1..50 有图;UL 恒无图(web 强制文字)', () {
      expect(
        badgeAssetPath(site: 'douyu', kind: ChatBadgeKind.fans, level: 12),
        'assets/badges/douyu/fans/12.png',
      );
      expect(
        badgeAssetPath(site: 'douyu', kind: ChatBadgeKind.fans, level: 50),
        'assets/badges/douyu/fans/50.png',
      );
      expect(
        badgeAssetPath(site: 'douyu', kind: ChatBadgeKind.fans, level: 51),
        '',
      );
      expect(
        badgeAssetPath(site: 'douyu', kind: ChatBadgeKind.userLevel, level: 31),
        '',
      );
    });

    test('huya fans 恒无图(v2 emblem 不用于粉丝牌);UL 走 7 档 identity', () {
      expect(
        badgeAssetPath(site: 'huya', kind: ChatBadgeKind.fans, level: 12),
        '',
      );
      // 档位映射(web resolveHuyaVipEmblemIdentity):≤4→1、≤7→2、≤10→3、
      // ≤13→4、≤16→11、≤19→12、其余→13。
      int identityOf(int level) => int.parse(
          badgeAssetPath(site: 'huya', kind: ChatBadgeKind.userLevel, level: level)
              .split('/')
              .last
              .replaceAll('.png', ''));
      expect(identityOf(1), 1);
      expect(identityOf(4), 1);
      expect(identityOf(5), 2);
      expect(identityOf(7), 2);
      expect(identityOf(8), 3);
      expect(identityOf(10), 3);
      expect(identityOf(11), 4);
      expect(identityOf(13), 4);
      expect(identityOf(14), 11);
      expect(identityOf(16), 11);
      expect(identityOf(17), 12);
      expect(identityOf(19), 12);
      expect(identityOf(20), 13);
      expect(identityOf(80), 13);
      expect(
        badgeAssetPath(site: 'huya', kind: ChatBadgeKind.userLevel, level: 17),
        'assets/badges/huya/vip/v2/12.png',
      );
    });

    test('bilibili 本轮无 fans/UL 分图;medal-frame 边框路径固定', () {
      expect(
        badgeAssetPath(site: 'bilibili', kind: ChatBadgeKind.fans, level: 12),
        '',
      );
      expect(
        badgeAssetPath(
          site: 'bilibili',
          kind: ChatBadgeKind.userLevel,
          level: 6,
        ),
        '',
      );
      expect(bilibiliMedalFrameAssetPath(),
          'assets/badges/bilibili/medal-frame.png');
    });
  });

  group('ChatBadgeImage:失败/无资产 → shrink + onFail', () {
    testWidgets('noAsset:huya fans 无本地图,渲染 shrink 并回调 onFail', (
      tester,
    ) async {
      var failCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ChatBadgeImage(
              site: 'huya',
              kind: ChatBadgeKind.fans,
              level: 12,
              height: 16,
              onFail: () => failCount++,
            ),
          ),
        ),
      );
      await tester.pump(); // 首帧构建(shrink 已渲染)
      expect(find.byType(Image), findsNothing);
      await tester.pump(); // 帧尾 onFail 回调后的下一帧
      expect(failCount, 1, reason: '无资产应在帧尾回调一次 onFail');
      await tester.pump();
      expect(failCount, 1, reason: 'onFail 只回调一次,不重复触发');
    });

    testWidgets('assetLoads:douyu fans 12 声明资产在测试环境真实解码渲染', (
      tester,
    ) async {
      // 先证明资产确实已随 pubspec 声明进测试包(rootBundle 可读)。
      late ByteData bytes;
      await tester.runAsync(() async {
        bytes = await rootBundle.load('assets/badges/douyu/fans/12.png');
      });
      expect(bytes.lengthInBytes, greaterThan(0), reason: '声明资产应可加载');
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: ChatBadgeImage(
              site: 'douyu',
              kind: ChatBadgeKind.fans,
              level: 12,
              height: 18,
            ),
          ),
        ),
      );
      // 资产解码在 flutter_tester 里是真实异步,runAsync 让其完成。
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 300));
      });
      await tester.pump();
      final loaded = tester
          .widgetList<RawImage>(find.byType(RawImage))
          .where((w) => w.image != null)
          .toList();
      expect(loaded, isNotEmpty, reason: '已声明资产应真实解码为 RawImage');
    });
  });

  group('弹幕行徽章:图片优先 → 文字态兜底', () {
    testWidgets('douyuRow:官方粉丝牌整图 + 团名叠层;UL 保持 LV 文字', (tester) async {
      final connector = _FakeDanmakuConnector();
      await _pumpPanel(tester, 'douyu', connector: connector);
      final session = _connected(connector);
      session.emitConnected();
      session.push(
        _chat('徽章哥', '都有', badgeLevel: 12, badgeName: '提督骑士团', userLevel: 31),
      );
      await _pumpStable(tester);

      // 图片分支:douyu/fans/12.png(等级绘在图内,不另绘数字)。
      final img = _badgeImage(
        tester,
        assetPath: 'assets/badges/douyu/fans/12.png',
      );
      expect(img, isNotNull, reason: '斗鱼粉丝牌应走官方 PNG 图片分支');
      expect(find.text('提督骑士团'), findsOneWidget,
          reason: '官方牌整图上应叠团名文字');
      expect(find.byType(ChatBadgeImage), findsOneWidget);
      // 斗鱼 UL 文字兜底不回归(web 强制文字)。
      expect(find.text('LV31'), findsOneWidget);
      expect(find.byType(ChatBadgeImage),
          findsOneWidget, reason: '斗鱼 UL 不接图,全行只有粉丝牌一张图');
    });

    testWidgets('douyuRowFallback:档位超资产清单(99 级)→ 帧内回落中性团名胶囊', (
      tester,
    ) async {
      final connector = _FakeDanmakuConnector();
      await _pumpPanel(tester, 'douyu', connector: connector);
      final session = _connected(connector);
      session.emitConnected();
      session.push(_chat('超限哥', '99 级', badgeLevel: 99, badgeName: '超限骑士团'));
      await _pumpStable(tester);

      expect(_badgeImage(tester), isNull,
          reason: '99 级无本地图,不应挂 ChatBadgeImage');
      expect(find.text('超限骑士团'), findsOneWidget,
          reason: '无图回落文字态:中性深底团名胶囊');
    });

    testWidgets('huyaRow:粉丝条维持渐变文字态;UL emblem 图上叠白数字', (tester) async {
      final connector = _FakeDanmakuConnector();
      await _pumpPanel(tester, 'huya', connector: connector);
      final session = _connected(connector);
      session.emitConnected();
      session.push(
        _chat('虎牙哥', '来了', badgeLevel: 12, badgeName: '铁粉团', userLevel: 17),
      );
      await _pumpStable(tester);

      // 粉丝条:渐变条 = 等级圆盘 + 团名(v2 emblem 不用于粉丝牌)。
      expect(find.text('12'), findsOneWidget, reason: '粉丝条等级圆盘');
      expect(find.text('铁粉团'), findsOneWidget);
      // UL:identity 17→12 的 emblem 图 + 右下白数字叠层。
      final emblem = _badgeImage(
        tester,
        assetPath: 'assets/badges/huya/vip/v2/12.png',
      );
      expect(emblem, isNotNull, reason: '虎牙 UL 应走 vip/v2 emblem 图片分支');
      expect(find.text('17'), findsOneWidget, reason: 'emblem 图上应叠等级数字');
      expect(find.byType(ChatBadgeImage), findsOneWidget);
    });

    testWidgets('douyinRow:img-only 粉丝牌 + honor 整图;超档 honor 回落文字', (
      tester,
    ) async {
      final connector = _FakeDanmakuConnector();
      await _pumpPanel(tester, 'douyin', connector: connector);
      final session = _connected(connector);
      session.emitConnected();
      // 抖音协议常无团名:img-only 有等级即图(web fanImgOnly)。
      session.push(_chat('抖哥', '图', badgeLevel: 10, userLevel: 18));
      session.push(_chat('抖神', '超档', userLevel: 76));
      await _pumpStable(tester);

      expect(
        _badgeImage(tester, assetPath: 'assets/badges/douyin/fans/10.png'),
        isNotNull,
        reason: '抖音粉丝牌 img-only:有等级即整图',
      );
      expect(
        _badgeImage(tester, assetPath: 'assets/badges/douyin/honor/18.png'),
        isNotNull,
        reason: '抖音 UL honor 整图',
      );
      // 76 > honorMax(75):无资产 → onFail 回落紫粉渐变数字文字态。
      expect(find.text('76'), findsOneWidget, reason: '超档 honor 回落文字 pill');
      expect(find.byType(ChatBadgeImage), findsNWidgets(2));
    });
  });
}
