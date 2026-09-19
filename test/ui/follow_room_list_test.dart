/// `FollowRoomList` 列表档(row)的自适应多列布局锁定测试。
///
/// 对齐 web `FollowRoomRowView` 的 multi-col 行为:
/// - 列数按「列宽 ≥300px、行本体 ≤400px」自适应(侧栏窄列 → 单列,
///   页面宽容器 → 多列平铺);
/// - 列比 400px 宽时行本体封顶 400、靠左放置(侧栏与页面同一组件,
///   只差容器宽度)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart';
import 'package:zishu_flutter/src/features/follow/application/follow_provider.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_entry_row.dart';
import 'package:zishu_flutter/src/features/follow/widgets/follow_room_list.dart';

FollowEntry _entry(String roomId) => FollowEntry(
      room: RoomSummary(
        site: 'douyu',
        roomId: roomId,
        title: '标题 $roomId',
        anchorName: '主播 $roomId',
        cid: '1',
        category: '户外',
        online: '1.2万',
        cover: '',
      ),
      isSpecial: false,
      remindOn: false,
      followedAt: DateTime(2026, 1, 1),
    );

Future<void> _pump(WidgetTester tester, {required double width}) async {
  tester.view.physicalSize = Size(width, 600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
      body: FollowRoomList(
        entries: [for (var i = 1; i <= 4; i++) _entry('$i')],
        density: FollowDensity.row,
        padding: EdgeInsets.zero,
        onTap: (_) {},
      ),
    ),
  ));
  await tester.pump();
}

SliverGridDelegateWithFixedCrossAxisCount _delegate(WidgetTester tester) =>
    tester.widget<GridView>(find.byType(GridView)).gridDelegate
        as SliverGridDelegateWithFixedCrossAxisCount;

double _firstRowWidth(WidgetTester tester) => tester
    .renderObject<RenderBox>(find.byType(FollowEntryRow).first)
    .size
    .width;

void main() {
  testWidgets('窄容器(侧栏口径)单列:每主播一行', (tester) async {
    await _pump(tester, width: 300);
    expect(_delegate(tester).crossAxisCount, 1);
    expect(_firstRowWidth(tester), moreOrLessEquals(300, epsilon: 0.5));
  });

  testWidgets('宽容器自适应分列,行本体限宽 400', (tester) async {
    // 900 → 2 列(列宽 447.75):列数按 300px 下限取 2,行本体封顶 400。
    await _pump(tester, width: 900);
    expect(_delegate(tester).crossAxisCount, 2);
    expect(_firstRowWidth(tester), moreOrLessEquals(400, epsilon: 0.5));

    // 1209 → 3 列,每列恰好 400。
    await _pump(tester, width: 1209);
    expect(_delegate(tester).crossAxisCount, 3);
    expect(_firstRowWidth(tester), moreOrLessEquals(400, epsilon: 0.5));
  });
}
