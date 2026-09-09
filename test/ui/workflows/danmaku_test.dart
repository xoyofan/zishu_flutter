/// 弹幕 workflow test(任务卡 W3)。
///
/// 覆盖四条用例:
/// 1. danmakuRendersOnOpen:深链播放页 → 切「聊天」tab → 弹幕条目 >0;
/// 2. danmakuVisualIntegrity:条目为「粉丝徽章? + 用户名 + '：' + 消息」富文本,
///    用户名 hash 着色(w600 + HSL 稳定色相)且与正文颜色区分,粉丝团徽章存在;
/// 3. danmakuPanelIsolatedFromRoomNav:聊天 → 关注 → 推荐 → 聊天 往返切换,
///    弹幕条目数保持一致(侧栏 tab 状态独立,不丢样例数据);
/// 4. danmakuIncrementStub:G2 增量断言接口位(fixture 阶段保持静态断言)。
///
/// 定位约定(读 play_side_panel.dart 得出,与 driver [expectDanmakuEntries]
/// 一致):
/// - 弹幕条目 = PlaySidePanel 内含「全角冒号」的 RichText。条目由
///   `Text.rich(TextSpan(children: [用户名, '：', 消息]))` 构建;Flutter 的
///   Text.build 会再包一层默认样式 wrapper span(剥壳见 [_danmakuRowSpan]);
/// - tab 标签(聊天/关注/推荐)、粉丝徽章(「粉丝 N」)、底部说明与占位提示
///   文案均不含全角冒号,不会误计;
/// - 粉丝团徽章 = 纯 `Text('粉丝 {level}')` 色块;12 条样例中 6 条带徽章,
///   等级(12/7/23/5/9/31)互不相同。
///
/// G2 升级路径(接口位预留,用例零重写):
/// 1. `_ChatSampleList` 替换为真实弹幕流驱动的列表(provider/state),条目保持
///    「徽章? + 用户名 + '：' + 消息」富文本结构不变;
/// 2. 本文件 finder 零改动:[captureDanmakuCount]/[expectDanmakuEntries] 均按
///    「PlaySidePanel 内含全角冒号的 RichText」结构定位,与数据来源解耦;
/// 3. `danmakuIncrementStub` 中的静态断言按用例内注释块升级为
///    `expect(captureDanmakuCount(tester), greaterThan(count1))`,pump 窗口
///    对齐真实弹幕节奏(默认 5s),用例名称与结构保持不变。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';

import 'platform_workflow.dart' show expectDanmakuEntries, pumpPlatformApp;

/// 播放页深链位置(fixture 样例房间,与 navigation/layout 基线同房间)。
const String _playLocation = '/douyu/play/63136';

/// 钉死校验用首条样例(与 play_side_panel.dart 的 _chatSamples[0] 对齐;
/// 其余断言按结构定位不耦合样例数据,仅 hash 着色需钉死一条用户名)。
const String _pinnedUser = '星河不入梦';
const String _pinnedMessage = '来了来了，主播这波操作可以';
const String _pinnedBadge = '粉丝 12';

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
/// (wrapper text == null 且仅 1 个 child),得到「[用户名, '：', 消息]」
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

/// 增量断言接口位(W3 预留):统计当前聊天 tab 挂载的弹幕条目数。
///
/// G2 接入真弹幕后,在 danmakuIncrementStub 中直接使用:
/// ```dart
/// final count1 = captureDanmakuCount(tester);
/// await tester.pump(const Duration(seconds: 5)); // 真弹幕流持续推送
/// expect(captureDanmakuCount(tester), greaterThan(count1));
/// ```
int captureDanmakuCount(WidgetTester tester) =>
    tester.widgetList<RichText>(_danmakuEntries()).length;

/// 固定时长 pump(TabBarView 切换动画 kTabScrollDuration≈300ms,4×100ms 足够),
/// 遵循 driver 约定不用 pumpAndSettle(封面图在 VM 中不会真正加载)。
Future<void> _pumpStable(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('danmakuRendersOnOpen:深链播放页切聊天 tab,弹幕条目 >0', (
    tester,
  ) async {
    final router = await pumpPlatformApp(tester, _playLocation);
    expect(router.routeInformationProvider.value.uri.path, _playLocation);
    expect(find.byType(PlaySidePanel), findsOneWidget);

    // driver 断言:点击聊天 tab(DefaultTabController 初始页,点击幂等)后,
    // 侧栏内「用户名：消息」富文本条目 >0。
    await expectDanmakuEntries(tester);
  });

  testWidgets('danmakuVisualIntegrity:富文本结构完整,hash 着色+粉丝徽章', (
    tester,
  ) async {
    await pumpPlatformApp(tester, _playLocation);
    await expectDanmakuEntries(tester);

    final entries = tester.widgetList<RichText>(_danmakuEntries()).toList();
    expect(entries, isNotEmpty);
    // 通用结构:每条目均为 [用户名 span, '：' span, 消息 span] 三段组合,
    // 用户名 w600 加粗 + 独立颜色(与正文 textPrimary 区分)。
    for (final entry in entries) {
      final label = entry.text.toPlainText();
      final row = _danmakuRowSpan(entry);
      expect(row.children, isNotNull, reason: '弹幕条目应为 TextSpan 组合:$label');
      expect(
        row.children!.length,
        3,
        reason: '弹幕条目结构应为 用户名+冒号+消息 三段:$label',
      );
      final userSpan = row.children![0] as TextSpan;
      final colonSpan = row.children![1] as TextSpan;
      final messageSpan = row.children![2] as TextSpan;
      expect(colonSpan.text, '：', reason: '$label 应以全角冒号分隔用户名与消息');
      expect(userSpan.text, isNotEmpty, reason: '用户名 span 文本非空:$label');
      expect(messageSpan.text, isNotEmpty, reason: '消息 span 文本非空:$label');
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

    // hash 着色钉死校验:首条样例用户名颜色 == 复刻算法计算值
    // (31 进制 hash → HSL 0.6/0.68)。
    final pinnedFinder = find.descendant(
      of: find.byType(PlaySidePanel),
      matching: find.byWidgetPredicate(
        (widget) =>
            widget is RichText &&
            widget.text.toPlainText().startsWith('$_pinnedUser：'),
      ),
    );
    expect(pinnedFinder, findsOneWidget, reason: '应存在样例弹幕「$_pinnedUser」');
    final pinnedRow = _danmakuRowSpan(tester.widget<RichText>(pinnedFinder));
    final pinnedSpans = pinnedRow.children!;
    expect((pinnedSpans[0] as TextSpan).text, _pinnedUser);
    expect((pinnedSpans[2] as TextSpan).text, _pinnedMessage);
    expect(
      (pinnedSpans[0] as TextSpan).style?.color,
      _hashUserColor(_pinnedUser),
      reason: '用户名颜色应按 hash(用户名) 稳定色相计算',
    );

    // 粉丝团徽章:钉死样例行带「粉丝 12」徽章,且侧栏内徽章整体存在。
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.text(_pinnedBadge),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(PlaySidePanel),
        matching: find.textContaining('粉丝 '),
      ),
      findsWidgets,
      reason: '侧栏内应存在粉丝团徽章(样例 12 条中 6 条带徽章)',
    );
  });

  testWidgets('danmakuPanelIsolatedFromRoomNav:切关注/推荐再切回聊天条目仍在', (
    tester,
  ) async {
    await pumpPlatformApp(tester, _playLocation);
    await expectDanmakuEntries(tester);
    final countBefore = captureDanmakuCount(tester);
    expect(countBefore, greaterThan(0));

    // 切「关注」:占位提示出现(tab 内容切换生效)。
    await tester.tap(find.text('关注'));
    await _pumpStable(tester);
    expect(find.text('关注/特别关注/开播提醒(M4)'), findsOneWidget);

    // 切「推荐」:占位提示出现。
    await tester.tap(find.text('推荐'));
    await _pumpStable(tester);
    expect(find.text('关注房间推荐(M4)'), findsOneWidget);

    // 切回「聊天」:弹幕条目数与切换前一致——侧栏 tab 状态独立,样例流不丢。
    await tester.tap(find.text('聊天'));
    await _pumpStable(tester);
    expect(
      captureDanmakuCount(tester),
      countBefore,
      reason: '往返切换 tab 后弹幕条目应原样恢复',
    );
    await expectDanmakuEntries(tester);
  });

  testWidgets('danmakuIncrementStub:G2 增量断言接口位(fixture 阶段静态)', (
    tester,
  ) async {
    await pumpPlatformApp(tester, _playLocation);
    await expectDanmakuEntries(tester);

    // ── G2 接入真弹幕后的增量断言(届时替换下方静态断言块,其余零改动)────
    // final count1 = captureDanmakuCount(tester);
    // await tester.pump(const Duration(seconds: 5)); // 真弹幕流持续推送
    // expect(
    //   captureDanmakuCount(tester),
    //   greaterThan(count1),
    //   reason: '真弹幕流下 5s 窗口内应有新条目到达',
    // );
    // ── fixture 阶段静态断言:样例弹幕流静止,5s 窗口内条目数不变 ──────────
    final count1 = captureDanmakuCount(tester);
    expect(count1, greaterThan(0));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(
      captureDanmakuCount(tester),
      count1,
      reason: 'fixture 阶段弹幕为静态样例,5s 窗口内条目数应保持不变;'
          'G2 接真弹幕后升级为 greaterThan(count1)(见上方注释块)',
    );
  });
}
