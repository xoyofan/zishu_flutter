import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_session_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/chat_badge_image.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';

class _FakeSession implements DanmakuSession {
  final _messages = StreamController<DanmakuMessage>.broadcast();
  final _states = StreamController<DanmakuSessionState>.broadcast();

  @override
  Stream<DanmakuMessage> get messages => _messages.stream;

  @override
  Stream<DanmakuSessionState> get states => _states.stream;

  void emitState(DanmakuSessionState state) => _states.add(state);

  void emitMessage(DanmakuMessage message) => _messages.add(message);

  @override
  Future<void> close() async {
    await _messages.close();
    await _states.close();
  }
}

class _FakeConnector implements DanmakuConnector {
  _FakeSession? session;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async =>
      session = _FakeSession();
}

DanmakuMessage _message({
  String site = 'bilibili',
  String user = '观众',
  String text = '你好',
  int userLevel = 0,
  String userLevelIconUrl = '',
  List<DanmakuBadge> badges = const [],
  DanmakuBadge? guard,
  List<DanmakuSegment> segments = const [],
}) => DanmakuMessage(
  type: DanmakuMessageType.chat,
  roomId: 'room-1',
  userName: user,
  userId: 'u-1',
  text: text,
  userLevel: userLevel,
  userLevelIconUrl: userLevelIconUrl,
  badges: badges,
  guard: guard,
  segments: segments,
);

Future<void> _pump(WidgetTester tester, String site, DanmakuMessage message) async {
  final connector = _FakeConnector();
  final registry = buildSiteRegistry();
  final target = registry[site]!;
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

  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(500, 1200);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [danmakuRegistryProvider.overrideWithValue(registry)],
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: Scaffold(
          body: SizedBox(
            width: 392,
            child: PlaySidePanel(site: site, roomId: 'room-1'),
          ),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  final session = connector.session!;
  session.emitState(DanmakuSessionState.connected);
  session.emitMessage(message);
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('B站大航海按真实 guard 字段显示', (tester) async {
    await _pump(
      tester,
      'bilibili',
      _message(
        guard: const DanmakuBadge(
          name: '舰长',
          level: 3,
          color: 0xfff39c12,
          kind: 'guard',
        ),
        badges: const [
          DanmakuBadge(name: '提督骑士团', level: 12),
        ],
      ),
    );

    expect(find.text('舰长'), findsOneWidget);
    expect(find.textContaining('提督骑士团'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
  });

  testWidgets('虎牙平台等级用官方 consumeLevelBadgeV2 图,不用协议 iconUrl/本地贵族图',
      (tester) async {
    // 官网 `components/ConsumeLevelBadge/index.tsx`：
    //   https://diy-assets.msstatic.com/consumeLevelBadgeV2/{tier}/{light|gray}.png
    // 关键回归：旧的 `assets/badges/huya/vip/v2/*.png` 是**身份图标**
    // （= 官网 fans-icon-sf），绝不能当平台等级底图。
    await _pump(
      tester,
      'huya',
      _message(
        site: 'huya',
        userLevel: 30,
        userLevelIconUrl: 'https://cdn.example/huya-consume-level.png',
      ),
    );

    // 无网环境下官方图加载失败 → 降级胶囊（尺寸与官方图一致）
    final fallback = find.byKey(const Key('huya-user-level-fallback'));
    expect(fallback, findsOneWidget);
    expect(find.text('30'), findsOneWidget);
    expect(
      tester.getRect(fallback).height,
      20,
      reason: '官方 consumeLevelBadgeV2 图等效高 20',
    );
    expect(
      find.byWidgetPredicate(
        (w) => w is Image && w.image is AssetImage,
      ),
      findsNothing,
      reason: '不得再拿本地 vip/v2 贵族/身份图当平台等级底图',
    );
  });

  testWidgets('虎牙粉丝牌把超粉 V 收进皇冠位并保留等级和团名', (tester) async {
    await _pump(
      tester,
      'huya',
      _message(
        site: 'huya',
        badges: const [
          DanmakuBadge(
            name: '铁粉团',
            level: 13,
            vFlag: 1,
            vLogo: 'https://cdn.example/huya-v.png',
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('huya-fan-badge')), findsOneWidget);
    expect(find.byKey(const Key('huya-fan-v-mark')), findsOneWidget);
    expect(find.byType(CachedNetworkImage), findsOneWidget);
    expect(find.text('13'), findsOneWidget);
    expect(find.text('铁粉团'), findsOneWidget);
  });

  testWidgets('SOOP 0109 表情段在聊天行显示图片', (tester) async {
    await _pump(
      tester,
      'soop',
      _message(
        site: 'soop',
        text: '你好[OGQ表情]',
        segments: const [
          DanmakuSegment.text('你好'),
          DanmakuSegment.emoji(
            text: '[OGQ表情]',
            name: 'OGQ表情',
            url: 'https://cdn.example/ogq.png',
          ),
        ],
      ),
    );

    expect(find.byKey(const Key('chat-emoji-image-OGQ表情')), findsOneWidget);
  });

  testWidgets('抖音粉丝牌:用官网聊天同款 60x48 紧凑图(非 150x48 黄底长条/本地粉翼款)', (tester) async {
    // 候选素材对比(实测 2026-09-25):
    //   - fansclub_level_v6_N.png         150×48 黄色宽底长条 → 背景颜色太宽(用户报障)
    //   - assets/badges/douyin/fans/N.png  本地图是粉翼大摆台 → 也不是官网样式
    //   - fansclub_new_advanced_badge_N_xmp.png 60×48 → 官网聊天行同款
    await _pump(
      tester,
      'douyin',
      _message(
        site: 'douyin',
        userLevel: 29,
        userLevelIconUrl:
            'https://p3-webcast.douyinpic.com/img/webcast/'
            'new_user_grade_level_v1_29.png~tplv-obj.image',
        badges: const [
          DanmakuBadge(
            name: '粉丝团等级9级勋章',
            level: 9,
            url: 'https://p11-webcast.douyinpic.com/img/webcast/'
                'fansclub_level_v6_9.png~tplv-obj.image',
          ),
        ],
      ),
    );

    final rendered = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .map((provider) {
          if (provider is NetworkImage) return provider.url;
          if (provider is AssetImage) return provider.assetName;
          return '';
        })
        .where((source) => source.contains('fans'))
        .toList();
    expect(
      rendered,
      isNot(contains(anything)),
      reason: '不得渲染本地粉翼款 fans 图(非官网样式)',
    );
    expect(
      rendered.where((source) => source.contains('new_advanced_badge')),
      isEmpty,
      reason: '不得渲染 60x48 紧凑款(无团名位,且与平台等级同款观感)',
    );
  });

  testWidgets('斗鱼至尊/贵族/超粉/钻粉:按 kind 分档渲染(URL 未确证 → 数字/文字占位)',
      (tester) async {
    // 官网 4 个 dy-* 徽章组件聊天行顺序:用户等级 → 粉丝牌 → 至尊大钻石 →
    // 贵族(另加超粉/钻粉两个身份标记)。本例的徽章序列就是解析包
    // `danmaku.dart` 对 `ne/sl/sid/sahf/diaf` 编出来的顺序。
    //
    // 【降级说明】至尊图标 = `getDiamondIconExt({diafid})`、贵族图标 =
    // `resource/noble/global/web.json` 的 host+icons，两个 URL 规则都**未确证**
    // → 不渲染任何远程图，只出等级数字/文字 chip。
    await _pump(
      tester,
      'douyu',
      _message(
        site: 'douyu',
        userLevel: 41,
        badges: const [
          DanmakuBadge(name: '金咕咕', level: 26),
          DanmakuBadge(name: '至尊大钻石', level: 3, kind: 'supreme'),
          DanmakuBadge(name: '贵族', level: 6, kind: 'noble'),
          DanmakuBadge(name: '超粉', level: 0, kind: 'superfan'),
          DanmakuBadge(name: '钻粉', level: 0, kind: 'diamondfan'),
        ],
      ),
    );

    // 至尊大钻石：官网 dy-supreme-medal :host 实测 28x28。
    final supreme = find.byKey(const Key('douyu-supreme-medal'));
    expect(supreme, findsOneWidget);
    expect(tester.getRect(supreme).height, 28);
    expect(tester.getRect(supreme).width, 28);
    expect(
      find.descendant(of: supreme, matching: find.text('3')),
      findsOneWidget,
      reason: '图标 URL 未确证 → 用协议等级数字占位',
    );

    // 贵族：文字 chip「贵族 6」；超粉：金色 V；钻粉：文字 chip「钻粉」。
    expect(find.byKey(const Key('douyu-noble-chip')), findsOneWidget);
    expect(find.text('贵族 6'), findsOneWidget);
    expect(find.byKey(const Key('douyu-superfan-mark')), findsOneWidget);
    expect(find.text('V'), findsOneWidget);
    expect(find.byKey(const Key('douyu-diamondfan-chip')), findsOneWidget);
    expect(find.text('钻粉'), findsOneWidget);

    // 顺序 = 官网聊天行从左到右(粉丝牌 → 至尊 → 贵族 → 超粉 → 钻粉)。
    final fanLeft = tester.getRect(find.text('金咕咕')).left;
    final supremeLeft = tester.getRect(supreme).left;
    final nobleLeft = tester.getRect(find.byKey(const Key('douyu-noble-chip'))).left;
    final superFanLeft = tester.getRect(find.byKey(const Key('douyu-superfan-mark'))).left;
    final diamondLeft = tester.getRect(find.byKey(const Key('douyu-diamondfan-chip'))).left;
    expect(supremeLeft, greaterThan(fanLeft), reason: '至尊挂在粉丝牌之后');
    expect(nobleLeft, greaterThan(supremeLeft), reason: '官网顺序：至尊 → 贵族');
    expect(superFanLeft, greaterThan(nobleLeft), reason: '官网顺序：贵族 → 超粉');
    expect(diamondLeft, greaterThan(superFanLeft), reason: '官网顺序：超粉 → 钻粉');

    // 严禁编造 CDN 路径：本行只允许本地粉丝牌资产，不得出现远程徽章图。
    final remoteBadges = tester
        .widgetList<Image>(find.byType(Image))
        .map((image) => image.image)
        .whereType<NetworkImage>()
        .map((provider) => provider.url)
        .toList();
    expect(
      remoteBadges,
      isEmpty,
      reason: '至尊/贵族/钻粉图标 URL 未确证，不得拼远程图',
    );
  });

  testWidgets('B站平台等级按 web 口径(LV{level} 文字胶囊,高 1.48em/圆角 999)', (
    tester,
  ) async {
    // 口径变更(2026-09-26 用户「复刻原网页样式」):B 站平台等级从
    // 「16px 方角渐变」改成 web `.chat-user-level--bilibili` —— 高 1.48em(20.72)、
    // `min-width: auto`、圆角 999px、文字 `.64em`(8.96) + 左右 `.26em`(3.64)。
    // 见 DESIGN.md §4.4。
    await _pump(
      tester,
      'bilibili',
      _message(site: 'bilibili', userLevel: 25),
    );

    final pill = find.byKey(const Key('bilibili-user-level-pill'));
    expect(pill, findsOneWidget);
    expect(
      tester.getRect(pill).height,
      closeTo(AppChatBadge.levelHeight, 0.01),
      reason: 'web .chat-user-level--bilibili 高 1.48em = 20.72',
    );
    expect(find.text('LV25'), findsOneWidget, reason: 'web userLevelLabel 是 LV 前缀');

    final box = tester.widget<Container>(
      find.descendant(of: pill, matching: find.byType(Container)).first,
    );
    final deco = box.decoration! as BoxDecoration;
    expect(
      deco.borderRadius,
      BorderRadius.circular(AppRadius.pill),
      reason: 'web `.chat-user-level--bilibili { border-radius: 999px }`',
    );
    expect(
      box.padding,
      const EdgeInsets.symmetric(horizontal: AppChatBadge.levelPadX),
      reason: 'web `padding: 0 .26em` = 3.64',
    );
    expect(deco.gradient, isNotNull, reason: 'tier 渐变（同斗鱼 buildBilibiliUserLevelStyle）');
  });

  testWidgets('B站粉丝牌:有协议色走 composed(1.48em/3.5em)', (tester) async {
    // web `.chat-fan-badge--bilibili-composed`：高 1.48em(20.72)、
    // 最小宽 3.5em(49)、`padding: 0 .5em`(7)。
    await _pump(
      tester,
      'bilibili',
      DanmakuMessage(
        type: DanmakuMessageType.chat,
        roomId: 'room-1',
        userName: '小电视',
        userId: 'u-1',
        text: '你好',
        userLevel: 25,
        badgeColorStart: 0xfffb7299,
        badgeColorEnd: 0xff5c3aa8,
        badges: const [DanmakuBadge(name: '提督骑士团', level: 12)],
      ),
    );

    final composed = find.byKey(const Key('bilibili-fan-badge'));
    expect(composed, findsOneWidget);
    expect(
      tester.getRect(composed).height,
      closeTo(AppChatBadge.biliFanHeight, 0.01),
      reason: '有协议色 = composed，高 1.48em',
    );
    expect(
      tester.getRect(composed).width,
      greaterThanOrEqualTo(AppChatBadge.biliFanMinWidth),
      reason: 'composed 最小宽 3.5em = 49',
    );
  });

  testWidgets('B站粉丝牌:无协议色走 has-bg(1.28em/3.2em,不是 composed)', (tester) async {
    // web 无协议渐变色时走 `.chat-fan-badge--has-bg`（官方边框图 medal-frame）：
    // 高 1.28em(17.92)、最小宽 3.2em(44.8)、内容 `padding: 0 .22em 0 .16em`。
    // 旧实现把它写成 21/49 + 左右 10 内边距，明显偏宽。
    await _pump(
      tester,
      'bilibili',
      _message(
        site: 'bilibili',
        userLevel: 6,
        badges: const [DanmakuBadge(name: '舰团', level: 4)],
      ),
    );

    final framed = find.byKey(const Key('bilibili-fan-badge'));
    expect(framed, findsOneWidget);
    expect(
      tester.getRect(framed).height,
      closeTo(AppChatBadge.fanHeight, 0.01),
      reason: '无协议色 = has-bg，高 1.28em = 17.92',
    );
    expect(
      tester.getRect(framed).width,
      greaterThanOrEqualTo(AppChatBadge.fanMinWidth),
      reason: 'has-bg 最小宽 3.2em = 44.8',
    );
  });

  testWidgets('其他平台等级按 web default 口径(高 1.48em / 圆角 0 / 字号 1em)', (
    tester,
  ) async {
    // web 基础类 `.chat-user-level`：高 1.48em、`min-width: 1.2em`、
    // `border-radius: 0`（只有 bilibili/douyu 覆写成圆角）、文字 `1em` +
    // 左右 `.22em`。旧实现是 16px 高 / 2px 圆角 / 9px 字号。
    await _pump(tester, 'twitch', _message(site: 'twitch', userLevel: 12));

    final pill = find.byKey(const Key('other-user-level-pill'));
    expect(pill, findsOneWidget);
    expect(
      tester.getRect(pill).height,
      closeTo(AppChatBadge.levelHeight, 0.01),
    );
    final box = tester.widget<Container>(
      find.descendant(of: pill, matching: find.byType(Container)).first,
    );
    expect(
      (box.decoration! as BoxDecoration).borderRadius,
      BorderRadius.circular(0),
      reason: 'web 基础类是方角',
    );
    final text = tester.widget<Text>(
      find.descendant(of: pill, matching: find.byType(Text)).first,
    );
    expect(
      text.style?.fontSize,
      AppChatBadge.levelFontSizeWide,
      reason: '其他平台没吃到 `.64em` 覆盖，文字是 1em = 14',
    );
  });

  test('抖音粉丝牌:协议图优先 + 灰图换彩色 + 兜底统一 pop_super 紧凑款', () {
    // 2026-09-27 用户口径(dyx-compare.png 三模板实测对比):同一等级官方 CDN
    // 有三种宽度——level_v6(150×48 → 65.6px 长条)、new_badge(90×48 →
    // 39.4px 中等)、ranklist_fansclub_pop_super_badge(60×48 → 26.2px 紧凑款),
    // 抖音聊天间实际展示**最右的紧凑款**;兜底与灰图换彩统一用 pop_super,
    // 消除同房间 39.4/26.2 两种宽度的混排。
    // 1) 协议 URL 优先,但 `pop_gray_super_badge` 要换成同尺寸彩色款
    //    (实测真实弹幕 513 条里 152 条是未点亮灰图);
    // 2) 无协议 URL 回落官方紧凑款 `ranklist_fansclub_pop_super_badge`,
    //    **不是** `fansclub_level_v6`(150×48 → 65.6px 长条,用户 2026-09-26
    //    报「粉丝牌背景太长」)。
    expect(
      douyinFansBadgeUrl(9),
      'https://p3-webcast.douyinpic.com/img/webcast/'
      'ranklist_fansclub_pop_super_badge_9.png~tplv-obj.image',
    );
    expect(
      douyinFansBadgeUrl(1),
      contains('ranklist_fansclub_pop_super_badge_1.png'),
    );
    expect(
      douyinFansBadgeUrl(20),
      contains('ranklist_fansclub_pop_super_badge_20.png'),
    );
    expect(douyinFansBadgeUrl(0), isEmpty, reason: '无等级不出图');
    expect(douyinFansBadgeUrl(21), isEmpty, reason: '超档位(实测 404)不出图');
    for (final lv in [1, 9, 20]) {
      expect(
        douyinFansBadgeUrl(lv),
        isNot(contains('level_v6')),
        reason: 'level_v6 是 150×48 长条,与协议主流 60×48 差 2.5 倍',
      );
      expect(
        douyinFansBadgeUrl(lv),
        isNot(contains('new_badge')),
        reason: 'new_badge 是 90×48 中等款,与协议主流 60×48 宽窄不一',
      );
    }

    // 灰图 → 彩色:同为 60×48,只去 gray_。
    expect(
      douyinFansColoredBadgeUrl(
        'https://p11-webcast.douyinpic.com/img/webcast/'
        'ranklist_fansclub_pop_gray_super_badge_7.png~tplv-obj.image',
        7,
      ),
      'https://p11-webcast.douyinpic.com/img/webcast/'
      'ranklist_fansclub_pop_super_badge_7.png~tplv-obj.image',
    );
    // 彩色图原样透传(主播定制款不能被改写)。
    const custom = 'https://example.com/my_fans_badge.png';
    expect(douyinFansColoredBadgeUrl(custom, 5), custom);
    // 其他灰图族(advanced_gray)→ 官方 pop_super 紧凑款兜底。
    expect(
      douyinFansColoredBadgeUrl(
        'https://p3-webcast.douyinpic.com/img/webcast/'
        'fansclub_new_advanced_gray_badge_9_xmp.png~tplv-obj.image',
        9,
      ),
      douyinFansBadgeUrl(9),
    );
    expect(douyinFansColoredBadgeUrl('', 9), isEmpty);

    // 2026-09-29 用户口径(官方实际渲染 vs 当前宽图对比):官方模板族的
    // **彩色宽图**同样统一紧凑款 —— 此前只有灰图换彩/无图兜底走 pop_super,
    // 协议彩色宽图被「原样透传(含主播定制款)」放行,渲染成 65.6px 长条
    // (用户报「粉丝团背景太宽」)。
    expect(
      douyinFansColoredBadgeUrl(
        'https://p3-webcast.douyinpic.com/img/webcast/'
        'fansclub_level_v6_7.png~tplv-obj.image',
        7,
      ),
      douyinFansBadgeUrl(7),
      reason: 'level_v6 彩色长条(150×48)也必须换紧凑款',
    );
    expect(
      douyinFansColoredBadgeUrl(
        'https://p11-webcast.douyinpic.com/img/webcast/'
        'fansclub_new_badge_7_xmp.png~tplv-obj.image',
        7,
      ),
      douyinFansBadgeUrl(7),
      reason: 'new_badge 彩色中等款(90×48)也统一紧凑款',
    );
    // 已是紧凑款(非 gray 的 pop_super):原样透传,不做无谓改写。
    const compactColored = 'https://p11-webcast.douyinpic.com/img/webcast/'
        'ranklist_fansclub_pop_super_badge_7.png~tplv-obj.image';
    expect(douyinFansColoredBadgeUrl(compactColored, 7), compactColored);
    // level 越界(紧凑款 CDN 404)保留协议原图,聊胜于无。
    const v6Over = 'https://p3-webcast.douyinpic.com/img/webcast/'
        'fansclub_level_v6_21.png~tplv-obj.image';
    expect(douyinFansColoredBadgeUrl(v6Over, 21), v6Over);
  });

  testWidgets('ChatBadgeImage 接受协议 URL 并保留本地资源回退', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ChatBadgeImage(
          site: 'douyu',
          kind: ChatBadgeKind.fans,
          level: 12,
          height: 18,
          src: 'https://cdn.example/custom-fans.png',
        ),
      ),
    );

    expect(find.byType(Image), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('斗鱼粉丝牌:3 字团名按 web 口径恰好落在 60px 徽章内', (
    tester,
  ) async {
    // 回归护栏(2026-09-26 用户报「长度还是不够」):web
    // `.chat-fan-badge--douyu-official` 按 1.58em 内缩 + .78em 字号设计,
    // 3 字团名 = 22 + 11×3 + 4 = 59px ≤ 60px 徽章。此前用 12px 字号 +
    // 24px 内缩,3 字要 64px,撑出徽章右缘。
    const fanName = '金咕咕';
    await _pump(
      tester,
      'douyu',
      _message(
        site: 'douyu',
        userLevel: 41,
        badges: const [DanmakuBadge(name: fanName, level: 24)],
      ),
    );

    final name = find.text(fanName);
    expect(name, findsOneWidget);
    final style = tester.widget<Text>(name).style;
    expect(
      style?.fontSize,
      AppFontSize.caption,
      reason: 'web 斗鱼官方牌文字为 .78em(折算 11px),不是 12px',
    );
    // 内缩 22 + 3×11 + 右侧 spacing 4 = 59,不得超 60px 徽章宽。
    final textWidth = tester.getSize(name).width;
    expect(
      AppDouyuChatBadge.fanTextInset + textWidth + AppSpacing.xs,
      lessThanOrEqualTo(AppDouyuChatBadge.fanImageWidth),
      reason: '3 字团名必须整体落在官方 60px 徽章内',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('斗鱼粉丝牌:牌区有中性底(超长团名不裸露在聊天行背景上)', (
    tester,
  ) async {
    // 两次踩坑的回归护栏(2026-09-26 用户报障):
    // ① ImageRepeat.repeatX 铺底 → 等级徽被复制到右侧(用户:「右侧显示了
    //    重复的左侧部分」);② BoxFit.fill 铺底 → 徽标横向压扁。
    // 正确做法:徽章 60×19 **原样**贴左(不拉伸/不裁切/不重复),比徽章
    // 宽出来的部分由 fanFallbackBg 中性深底接住。
    //
    // 注:测试环境加载不到 assets/badges/*(Image.asset 走空),本例断言的是
    // 该分支共用的**牌区中性底**;徽章是否原样由真机目视。
    const fanName = '一个很长的粉丝团名字测试';
    await _pump(
      tester,
      'douyu',
      _message(
        site: 'douyu',
        userLevel: 41,
        badges: const [DanmakuBadge(name: fanName, level: 24)],
      ),
    );

    final name = find.text(fanName);
    expect(name, findsOneWidget);
    final holder = find
        .ancestor(of: name, matching: find.byType(DecoratedBox))
        .first;
    final deco = tester
        .widget<DecoratedBox>(holder)
        .decoration as BoxDecoration;
    expect(
      deco.color,
      AppDouyuChatBadge.fanFallbackBg,
      reason: '团名超出 60px 徽章的部分由中性深底接住',
    );
    expect(tester.takeException(), isNull);
  });
}
