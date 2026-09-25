/// 房间卡元信息区规格测试:恒定**两行**高(标题 + chips)、无多余 padding、
/// 特色 chip 就位。
///
/// 用户口径(2026-09 房间卡改版):封面下第 1 行标题、第 2 行 chips
/// (room.chips + promoTag 去重);主播昵称已移到封面左下角,不再占
/// meta 行。有的平台没有 chip,第 2 行仍占位,卡片必须等高。
/// 参考实现 `.room-card__body { padding: 6px 8px 8px }` + 占位态用
/// `min-height: 1.35em` 保持行高。本套用「同宽卡片高度必须全等」钉住。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart' show RoomRecord, RoomState;
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/browse/widgets/room_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

RoomRecord _room({
  required String id,
  String title = '房间标题',
  String anchor = '主播名',
  String? promoTag,
  String online = '1.2万',
  String category = '英雄联盟',
}) => RoomRecord(
  site: 'douyu',
  roomId: id,
  roomState: online.isEmpty ? RoomState.offline : RoomState.live,
  title: title,
  anchorName: anchor,
  cid: '1',
  category: category,
  audience: online.isEmpty ? null : online,
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
  testWidgets('两行元信息:有/无 chip 与缺标题的卡片高度完全一致', (tester) async {
    // 三种极端:全有 / 只有标题 / 全空(标题与主播名都没有)。
    await _pumpCards(tester, [
      RoomCard(room: _room(id: 'a', promoTag: '超清')),
      RoomCard(room: _room(id: 'b', anchor: '')),
      RoomCard(room: _room(id: 'c', title: '', anchor: '')),
    ]);

    final h = _heightOf(tester, 'douyu', 'a');
    expect(h, _heightOf(tester, 'douyu', 'b'), reason: '缺 chip/昵称不得塌陷一行');
    expect(h, _heightOf(tester, 'douyu', 'c'), reason: '标题缺失也不得塌陷');
    expect(tester.takeException(), isNull);
  });

  testWidgets('第 1 行标题、第 2 行特色 chip;主播名在封面左下(不占 meta)', (tester) async {
    await _pumpCards(tester, [
      RoomCard(room: _room(id: 'a', promoTag: '超清')),
      RoomCard(room: _room(id: 'b')),
    ]);

    // 主播名已移到封面左下角:仍在卡片内,但不在 meta 文本区。
    expect(find.text('主播名'), findsNWidgets(2), reason: '昵称仍渲染(封面左下)');
    final titleFinder = find.text('房间标题').first;
    final chipFinder = find.byKey(const Key('room-meta-chip-超清'));
    expect(
      tester.getTopLeft(chipFinder).dy,
      greaterThan(tester.getBottomLeft(titleFinder).dy),
      reason: '特色 chip 在标题下一行(meta 第 2 行)',
    );
    expect(
      find.byKey(const Key('room-meta-chip-超清')),
      findsOneWidget,
      reason: '促销/画质标签作为「特色 chip」显示在封面下方,不在封面上重复',
    );
    expect(find.text('超清'), findsOneWidget, reason: '同一信息只出现一次');
    // 没有 chip 的卡片与有 chip 的卡片同高(第 2 行占位恒定行高)。
    expect(
      _heightOf(tester, 'douyu', 'b'),
      _heightOf(tester, 'douyu', 'a'),
    );
  });

  testWidgets('平台名不上卡:不渲染平台角标也不进 chip(用户口径 2026-09 改版)', (tester) async {
    await _pumpCards(tester, [RoomCard(room: _room(id: 'a'))]);
    expect(
      find.byKey(const Key('room-meta-chip-斗鱼')),
      findsNothing,
      reason: '平台名不进 chip',
    );
    expect(
      find.byKey(const Key('cover-badge-platform')),
      findsNothing,
      reason: '平台角标已移除:封面左下改为主播昵称,跨平台首页也不再渲染平台名',
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
