/// 房间卡分类角标 widget 测试:验证平台原生分类名在角标上显示为跨平台中文名,
/// 而非平台原文(如虎牙 `lol` → `英雄联盟`)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zishu_flutter/src/shared/presentation/widgets/cover_badges.dart';

void main() {
  testWidgets('房间卡分类角标显示中文而非平台原文', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverCategoryBadge(
            corner: CoverCorner.topLeft,
            category: 'lol',
            site: 'huya',
            cid: '1',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 虎牙原生分类名 lol 应被映射为「英雄联盟」,且角标上不再出现平台原文。
    expect(find.text('英雄联盟'), findsOneWidget);
    expect(find.text('lol'), findsNothing);
  });

  testWidgets('房间卡分类角标:无映射时回落平台原名', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CoverCategoryBadge(
            corner: CoverCorner.topLeft,
            category: '某未知分类XYZ',
            site: 'bilibili',
            cid: '999',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('某未知分类XYZ'), findsOneWidget);
  });
}
