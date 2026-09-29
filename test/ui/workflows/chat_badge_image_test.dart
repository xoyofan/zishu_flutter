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
        DanmakuBadge,
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
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';

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
    testWidgets('douyuRow:平台等级按 web 口径(LV{level} 文字胶囊) + 官方粉丝牌整图 + 团名叠层',
        (tester) async {
      // 口径变更（2026-09-26 用户「复刻原网页样式」）：LV 胶囊从"斗鱼官网
      // canvas 实测 32×16 小徽标+数字"改为 web `.chat-user-level--douyu` ——
      // `LV{level}` 文字、高 1.15em(16.1)、圆角 2px、字号 .64em(8.96)、
      // 左右内边距 .26em(3.64)、**宽随内容自适应**（不再固定 32）。
      // 见 DESIGN.md §4.4。粉丝牌不变：官方 fans/{lv}.png(60x19) + 团名，盒高 18。
      final connector = _FakeDanmakuConnector();
      await _pumpPanel(tester, 'douyu', connector: connector);
      final session = _connected(connector);
      session.emitConnected();
      session.push(
        _chat('徽章哥', '都有', badgeLevel: 12, badgeName: '提督骑士团', userLevel: 31),
      );
      await _pumpStable(tester);

      // 平台等级：web 口径（高 1.15em、圆角 2px、LV 前缀、宽自适应、不接图）
      final levelPill = find.byKey(const Key('douyu-user-level-pill'));
      final levelRect = tester.getRect(levelPill);
      expect(
        levelRect.height,
        closeTo(AppDouyuChatBadge.levelHeight, 0.01),
        reason: 'web .chat-user-level--douyu 的高是 1.15em = 16.1',
      );
      expect(
        find.descendant(of: levelPill, matching: find.text('LV31')),
        findsOneWidget,
        reason: 'web userLevelLabel 斗鱼是 "LV{level}"',
      );
      final levelBox = tester.widget<Container>(
        find
            .descendant(of: levelPill, matching: find.byType(Container))
            .first,
      );
      expect(
        (levelBox.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(AppDouyuChatBadge.levelRadius),
        reason: 'web 斗鱼 LV 是 2px 圆角（不是全圆端）',
      );
      expect(
        levelBox.padding,
        const EdgeInsets.symmetric(horizontal: AppChatBadge.levelPadX),
        reason: 'web `padding: 0 .26em`',
      );
      expect(
        (levelBox.decoration! as BoxDecoration).gradient,
        isNotNull,
        reason: 'web buildDouyuUserLevelStyle 给 tier 渐变',
      );
      expect(
        levelRect.width,
        lessThan(AppDouyuChatBadge.fanImageWidth),
        reason: '宽随内容自适应，不再固定 32px 撑出空白',
      );

      // 粉丝牌：官方 PNG(等级绘在图内) + 团名，盒高 18
      final img = _badgeImage(
        tester,
        assetPath: 'assets/badges/douyu/fans/12.png',
      );
      expect(img, isNotNull, reason: '斗鱼粉丝牌应走官方 PNG 图片分支');
      expect(find.text('提督骑士团'), findsOneWidget, reason: '官方牌右侧应叠团名');
      final fanBadgeRect = tester.getRect(
        find.ancestor(of: find.text('提督骑士团'), matching: find.byType(Container)).first,
      );
      expect(fanBadgeRect.height, 18, reason: '官网粉丝牌实测盒高 18');
      expect(fanBadgeRect.width, greaterThanOrEqualTo(60),
          reason: '官方 PNG 宽 60，需为团名保留横向空间');
      expect(find.byType(ChatBadgeImage), findsOneWidget,
          reason: '斗鱼 UL 不接图,全行只有粉丝牌一张图');
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

    testWidgets('huyaRow:平台等级与粉丝牌结构对齐官网(等级降级胶囊 + 圆标/团名/官方身份图)',
        (tester) async {
      // 依据虎牙官网自己的前端（room_match / components.bundle）：
      //  平台等级 = https://diy-assets.msstatic.com/consumeLevelBadgeV2/{tier}/{tone}.png
      //    （tier 由 iLevel 分档、tone 由 iIsPolished 决定；图 90x40@2x = 45x20）
      //    URL 拼接是纯函数，由 live_parser 的 huya_chat_badges_test 逐档覆盖；
      //    本用例只断言可观测的结构与几何。
      //  粉丝牌 = **web 口径**（`.chat-fan-badge--huya-composed`）：高 1.15em(16.1)、
      //    2px 圆角、[圆形等级徽记][团名][身份图 fansBadge/3/v2/{id}.png]。
      //    旧值（高 20 全圆角胶囊）是虎牙官网 fans-icon 的实测口径，
      //    2026-09-26 按用户「复刻原网页样式」改到 web 口径（DESIGN.md §4.4）。
      final connector = _FakeDanmakuConnector();
      await _pumpPanel(tester, 'huya', connector: connector);
      final session = _connected(connector);
      session.emitConnected();
      session.push(
        DanmakuMessage(
          type: DanmakuMessageType.chat,
          roomId: '333003',
          userName: '虎牙哥',
          userId: 'huya-user',
          text: '来了',
          userLevel: 30,
          userLevelBadgeStyle: 0,
          userLevelIsPolished: 1,
          userLevelIconUrl: 'https://cdn.example/huya-consume-level.png',
          badges: const [
            DanmakuBadge(name: '铁粉团', level: 12),
          ],
        ),
      );
      // 无网环境下官方图必然加载失败 → 这里断言的是**降级胶囊**，
      // 它的尺寸必须与官方图一致（45x20），且不得回退到 14px 小胶囊。
      await _pumpStable(tester);

      final fallback = find.byKey(const Key('huya-user-level-fallback'));
      expect(fallback, findsOneWidget, reason: '官方图加载失败 → 降级数字胶囊');
      final levelRect = tester.getRect(fallback);
      expect(levelRect.height, 20, reason: '降级胶囊高 = 官方图等效高 20');
      expect(
        levelRect.width,
        lessThanOrEqualTo(34),
        reason: '降级胶囊宽不再撑到 45px 空胶囊(用户 2026-09-27 反馈背景太宽),'
            '与官方图裁剪后同宽(32,含亚像素/描边)',
      );
      expect(find.descendant(of: fallback, matching: find.text('30')), findsOneWidget);

      // 粉丝牌：web 口径（高 1.15em、2px 圆角），含圆形等级徽记(12)、团名、官方身份图
      final fanBadge = find.byKey(const Key('huya-fan-badge'));
      final fanRect = tester.getRect(fanBadge);
      expect(
        fanRect.height,
        closeTo(AppHuyaChatBadge.fanHeight, 0.01),
        reason: 'web `--huya-fan-badge-h: 1.15em` = 16.1（旧值 20 是官网实测口径）',
      );
      final fanBox = tester.widget<Container>(
        find.descendant(of: fanBadge, matching: find.byType(Container)).first,
      );
      expect(
        (fanBox.decoration! as BoxDecoration).borderRadius,
        BorderRadius.circular(AppHuyaChatBadge.fanRadius),
        reason: 'web `.chat-fan-badge--huya { border-radius: 2px }`，不是胶囊',
      );
      expect(find.descendant(
        of: find.byKey(const Key('huya-fan-badge')),
        matching: find.text('12'),
      ), findsOneWidget, reason: '左侧圆形等级徽记');
      expect(find.descendant(
        of: find.byKey(const Key('huya-fan-badge')),
        matching: find.text('铁粉团'),
      ), findsOneWidget);
      // 身份图标是**粉丝牌之外的独立兄弟徽章**(用户口径 2026-09-26),
      // 不在 `huya-fan-badge` 的 KeyedSubtree 内(否则会把整行量成 20 高)。
      final identity = find.byKey(const Key('huya-fan-identity-icon'));
      expect(identity, findsOneWidget, reason: '身份图标用官方 fansBadge/3/v2/{id}.png');
      expect(
        find.descendant(of: find.byKey(const Key('huya-fan-badge')), matching: identity),
        findsNothing,
        reason: '身份徽章不得被圈进粉丝牌的 KeyedSubtree',
      );
      // 回到原尺寸 20(官网 `.fans-icon-sf` 实测 22/26/28 × 20);
      // 此前 V 标记按 11、盾按粉丝牌高 16.1 渲染,都小了一半。
      expect(
        tester.getRect(identity).height,
        20,
        reason: '身份图标边长应回到原尺寸 20',
      );
      expect(
        tester
            .widgetList<Image>(find.byType(Image))
            .map((i) => i.image)
            .whereType<NetworkImage>()
            .map((n) => n.url)
            .any((u) => u.contains('/webui/fansBadge/3/v2/')),
        isTrue,
        reason: '身份图标必须是官方 CDN URL',
      );
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

      // 回归：抖音粉丝牌**优先用协议下发的图 URL**;无协议时回落官方
      // `ranklist_fansclub_pop_super_badge_N.png`(60×48 紧凑款,2026-09-27
      // 用户口径 dyx-compare.png:三模板统一最右紧凑款)。本地
      // `assets/badges/douyin/fans/*` 是粉翼大摆台错图,不得渲染。
      expect(
        _badgeImage(tester, assetPath: 'assets/badges/douyin/fans/10.png'),
        isNull,
        reason: '不得再渲染本地粉翼款错图',
      );
      expect(
        _badgeImage(tester, assetPath: 'assets/badges/douyin/honor/18.png'),
        isNotNull,
        reason: '抖音 UL honor 整图',
      );
      // 76 > honorMax(75):无资产 → onFail 回落紫粉渐变数字文字态。
      expect(find.text('76'), findsOneWidget, reason: '超档 honor 回落文字 pill');
      // 裁剪契约(2026-09-29 用户口径「图是对的,只用改背景宽度」):粉丝牌
      // 图原样保留,但显示宽收窄到内容区 —— width=26.25 + BoxFit.cover
      // (+ ChatBadgeImage 默认 alignment centerLeft)裁掉右侧渐变延伸底。
      final fansBadge = tester
          .widgetList<ChatBadgeImage>(find.byType(ChatBadgeImage))
          .firstWhere((w) => w.kind == ChatBadgeKind.fans);
      expect(fansBadge.width, AppDouyinChatBadge.fanCroppedWidth,
          reason: '宽模板图(150×48)只显示左端内容区宽 26.25');
      expect(fansBadge.fit, BoxFit.cover,
          reason: 'cover+centerLeft 左对齐裁右,不压缩变形');
      final clipRRect = tester.widget<ClipRRect>(
        find
            .ancestor(of: find.byWidget(fansBadge), matching: find.byType(ClipRRect))
            .first,
      );
      expect(
        (clipRRect.borderRadius as BorderRadius).bottomRight,
        const Radius.circular(AppDouyinChatBadge.fanCropEndRadius),
        reason: '裁切右端补小圆角(虎牙 consume 同款处理)',
      );
      // 修正期望：ChatBadgeImage 加载失败后**仍留在 widget 树里**（只是内部
      // 渲染 SizedBox.shrink 并回调 onFail），所以这里应是 2 个：
      //   1 个粉丝牌（官方远程图）+ 1 个平台等级 honor/18.png（本地图）。
      // 此前写成 1 是错的，导致该用例长期红。
      expect(find.byType(ChatBadgeImage), findsNWidgets(2));
      // 无网环境下远程图既没加载成功、也没及时抛错，所以**不应**断言粉丝牌
      // 已回落出等级文字（那是时序相关的）。只断言它用的是官方图 URL。
      final badgeSrcs = tester
          .widgetList<ChatBadgeImage>(find.byType(ChatBadgeImage))
          .map((w) => w.src)
          .toList();
      expect(
        badgeSrcs.any(
          (s) => s.contains('ranklist_fansclub_pop_super_badge_10.png'),
        ),
        isTrue,
        reason: '粉丝牌协议无 url 时回落官方 pop_super 紧凑款(60×48);'
            '不用 level_v6(150×48 长条)与 new_badge(90×48 中等款)',
      );
      expect(
        badgeSrcs.any((s) => s.contains('new_advanced_badge')),
        isFalse,
        reason: 'new_advanced 族是灰图/废弃款,不得直接渲染',
      );
    });

    testWidgets('douyinHonorFullAsset:honor 素材按原比例整图渲染,左右不裁切', (
      tester,
    ) async {
      // 官方 `new_user_grade_level_v1_*`(CDN)与本地 `douyin/honor/*.png` 同为
      // 96×48 长胶囊,左右那段半透明背景是素材本身的一部分。2026-09-26 曾按
      // 内容区裁到 76/48(高 21 → 宽 33.25px),用户反馈图标与数字被裁掉,
      // 2026-09-27 明确回退为「原比例整图 + BoxFit.contain」。本用例钉死
      // 整图口径,防止再次引入裁切。
      final connector = _FakeDanmakuConnector();
      await _pumpPanel(tester, 'douyin', connector: connector);
      final session = _connected(connector);
      session.emitConnected();
      session.push(_chat('抖哥', '来了', userLevel: 30));
      await _pumpStable(tester);

      final honor = _badgeImage(
        tester,
        assetPath: 'assets/badges/douyin/honor/30.png',
      );
      expect(honor, isNotNull, reason: '抖音平台等级走本地 honor 整图');
      final honorW = honor!;

      final rect = tester.getRect(find.byWidget(honorW));
      // 高度 2026-09-29 官方口径两轮校准:21 → 15 用户反馈「太小」→ 18
      // (粉丝牌 21 的 ~0.86,小于粉丝牌但不过分);宽随素材 96×48 比例
      // (高 18 → 36px)。
      expect(rect.height, closeTo(AppDouyinChatBadge.honorHeight, 0.01));
      expect(AppDouyinChatBadge.honorHeight, 18,
          reason: '2026-09-29 用户口径:honor 小于粉丝牌但 15 太小,取 18');
      // 素材未解码时 RawImage 拿不到宽(测试环境 0),所以钉死的是「不限宽 +
      // contain」这两个输入,而不是渲染后的像素宽。
      final image = tester.widget<Image>(
        find.descendant(of: find.byWidget(honorW), matching: find.byType(Image)),
      );
      expect(image.width, isNull, reason: '不限宽:按素材自身 96×48 比例渲染');
      expect(image.fit, BoxFit.contain, reason: '整图 contain,左右不裁切');
      expect(image.alignment, Alignment.centerLeft);
    });
  });
}
