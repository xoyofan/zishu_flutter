/// 房间卡元信息区规格测试:恒定**两行**高、无多余 padding、特色 chip 就位。
///
/// 用户报:封面下「第一行主播名、第二行特色 chip」,有的主播/平台没有 chip,
/// 卡片高度就会参差。参考实现 `.room-card__body { padding: 6px 8px 8px }` +
/// `.room-card__meta { margin-top: 4px; gap: 6px }`,且占位态用 `min-height: 1.35em`
/// 保持行高。本套用「同宽卡片高度必须全等」把这条钉住。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show RoomSummary;
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/browse/widgets/room_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

RoomSummary _room({
  required String id,
  String title = '房间标题',
  String anchor = '主播名',
  String? promoTag,
  String online = '1.2万',
  String category = '英雄联盟',
}) => RoomSummary(
  site: 'douyu',
  roomId: id,
  title: title,
  anchorName: anchor,
  cid: '1',
  category: category,
  online: online,
  cover: '',
  promoTag: promoTag,
);

Future<void> _pumpCards(WidgetTester tester, List<Widget> cards) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: ZishuTheme.dark(),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 900,
              child: Wrap(
                children: [
                  for (final card in cards) SizedBox(width: 180, child: card),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 50));
}

double _heightOf(WidgetTester tester, String site, String roomId) =>
    tester.getSize(find.byKey(Key('room-card-$site-$roomId'))).height;

void main() {
  testWidgets('两行元信息:有/无主播名与 chip 的卡片高度完全一致', (tester) async {
    // 三种极端:全有 / 只有标题 / 全空(标题与主播名都没有)。
    await _pumpCards(tester, [
      RoomCard(room: _room(id: 'a', promoTag: '超清')),
      RoomCard(room: _room(id: 'b', anchor: '')),
      RoomCard(room: _room(id: 'c', title: '', anchor: '')),
    ]);

    final h = _heightOf(tester, 'douyu', 'a');
    expect(h, _heightOf(tester, 'douyu', 'b'), reason: '缺主播名不得塌陷一行');
    expect(h, _heightOf(tester, 'douyu', 'c'), reason: '标题与主播名都缺也不得塌陷');
    expect(tester.takeException(), isNull);
  });

  testWidgets('第二行:主播名 + 特色 chip(促销标签)', (tester) async {
    await _pumpCards(tester, [
      RoomCard(room: _room(id: 'a', promoTag: '超清')),
      RoomCard(room: _room(id: 'b')),
    ]);

    expect(find.text('主播名'), findsNWidgets(2), reason: '两行里的主播名一行一个');
    expect(
      find.byKey(const Key('room-meta-chip-超清')),
      findsOneWidget,
      reason: '促销/画质标签作为「特色 chip」显示在封面下方,不在封面上重复',
    );
    expect(find.text('超清'), findsOneWidget, reason: '同一信息只出现一次');
    // 没有 chip 的卡片与有 chip 的卡片同高(行高恒定)。
    expect(
      _heightOf(tester, 'douyu', 'b'),
      _heightOf(tester, 'douyu', 'a'),
    );
  });

  testWidgets('chip 不显示平台名:单平台/跨平台网格均不把平台名当 chip(用户口径 2026-09-18)', (tester) async {
    await _pumpCards(
      tester,
      [RoomCard(room: _room(id: 'a'), showPlatformBadge: false)],
    );
    expect(
      find.byKey(const Key('room-meta-chip-斗鱼')),
      findsNothing,
      reason: '平台名不进 chip(平台信息由封面平台角标承载)',
    );

    await _pumpCards(tester, [RoomCard(room: _room(id: 'a'))]);
    expect(
      find.byKey(const Key('room-meta-chip-斗鱼')),
      findsNothing,
      reason: '跨平台网格下封面角标已有平台名,行内同样不重复',
    );
  });

  testWidgets('body padding 对齐参考实现 6/8/8', (tester) async {
    await _pumpCards(tester, [RoomCard(room: _room(id: 'a'))]);
    // 元信息区是封面之后的第一层 Padding。
    final paddings = tester
        .widgetList<Padding>(find.byType(Padding))
        .map((p) => p.padding)
        .whereType<EdgeInsets>()
        .toList();
    expect(
      paddings,
      contains(const EdgeInsets.fromLTRB(8, 6, 8, 8)),
      reason: '参考实现 .room-card__body padding: 6px 8px 8px',
    );
  });
}
