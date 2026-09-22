/// 骨架屏 loading 态测试(氛围级 UI 清单 §3.6):
/// - 共享骨架 widget 的扫光/静态两档行为;
/// - 三处落点(房间网格 footer、搜索结果、关注刷新)的加载态确实换了骨架,
///   原 `CircularProgressIndicator` 不再出现,且出现时机不变。
///
/// 参照同目录既有页面测试的约定:全程固定次数 `pump`,**不使用
/// `pumpAndSettle`** —— 骨架扫光是循环动画,`pumpAndSettle` 会永远等不到静止。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zishu_flutter/src/features/browse/widgets/room_grid.dart';
import 'package:zishu_flutter/src/features/follow/views/follow_view.dart';
import 'package:zishu_flutter/src/features/search/application/search_provider.dart';
import 'package:zishu_flutter/src/features/search/views/search_view.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/shimmer_skeleton.dart';
import 'package:zishu_flutter/src/shared/presentation/zishu_tokens.dart';

void main() {
  /// 完整档骨架:套了 srcIn 扫光,且扫光持续调度帧(循环在跑)。
  testWidgets('ShimmerSkeleton 完整档:带 srcIn 线性扫光且循环调度帧', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 40,
              height: 40,
              child: ShimmerSkeleton(child: SkeletonBox()),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    final shaderMask = tester.widget<ShaderMask>(find.byType(ShaderMask));
    expect(shaderMask.blendMode, BlendMode.srcIn);
    expect(
      tester.binding.hasScheduledFrame,
      isTrue,
      reason: '1.4s 循环扫光应持续请求下一帧',
    );

    // 跑满一个周期不抛异常(时长来自 AmbientMotion.shimmer)。
    await tester.pump(AmbientMotion.shimmer);
    expect(tester.takeException(), isNull);
  });

  /// reduce_motion:骨架不扫光,直出静态占位矩形(底色 = 既有 surfaceSoft)。
  testWidgets('ShimmerSkeleton 静态档(disableAnimations):不扫光且底色为 surfaceSoft', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: 40,
                height: 40,
                child: ShimmerSkeleton(child: SkeletonBox()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(ShaderMask), findsNothing, reason: '静态档不应加扫光');
    expect(
      tester.binding.hasScheduledFrame,
      isFalse,
      reason: '静态档不应有待跑的动画',
    );
    final box = tester.widget<Container>(
      find.descendant(
        of: find.byType(SkeletonBox),
        matching: find.byType(Container),
      ),
    );
    expect(
      (box.decoration! as BoxDecoration).color,
      ZishuTokens.dark.surfaceSoft,
      reason: '骨架底色只用既有 surface 档位',
    );
  });

  /// SkeletonTile = 房间卡形状:16:9 封面块 + 两条文字条。
  testWidgets('SkeletonTile 形状对齐房间卡:16:9 封面 + 两行文字条', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(width: 160, height: 160, child: SkeletonTile()),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(SkeletonBox), findsNWidgets(3), reason: '封面 1 条 + 文字 2 条');
    expect(
      tester.widget<AspectRatio>(find.byType(AspectRatio)).aspectRatio,
      16 / 9,
    );
  });

  /// 落点 1:房间网格「加载更多」footer —— 卡片形状骨架替换原加载圈。
  testWidgets('房间网格加载 footer:出现卡片骨架、不再出现加载圈', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoomGrid(rooms: [], hasMore: true),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byKey(const Key('room-grid-loading-more')), findsOneWidget);
    expect(find.byType(SkeletonTile), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    // 加载语义经读屏标签保留(原「加载中…」文案所在的位置)。
    expect(
      find.bySemanticsLabel('加载中…'),
      findsOneWidget,
      reason: '骨架是纯图形,加载中语义应由 Semantics 承载',
    );

    // hasMore=false 时 footer 不存在(骨架出现时机 = 原 loading footer 时机)。
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: RoomGrid(rooms: [], hasMore: false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(find.byType(SkeletonTile), findsNothing);
  });

  /// 落点 2:搜索结果首屏 —— 结果行形状骨架替换「搜索中…」文本占位。
  testWidgets('搜索结果首屏:出现 5 条结果行骨架、「搜索中…」文本占位消失', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: SearchView(onNavigate: (_) {}, onClose: () {}),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.enterText(find.byKey(const Key('search-input')), '英雄');
    // onChanged → searching=true:此时进入首屏加载分支。
    await tester.pump();

    expect(find.byType(SkeletonRow), findsNWidgets(5));
    expect(find.byKey(const Key('search-skeleton-0')), findsOneWidget);
    // 语义锚点(同 room_grid 口径):searching 且 hits 为空 → 骨架出现,
    // 加载语义由 Semantics(label: '搜索中…') 承载。
    expect(
      find.bySemanticsLabel('搜索中…'),
      findsOneWidget,
      reason: 'searching 且 hits 为空时应出现带「搜索中…」语义的骨架',
    );
    expect(find.text('搜索中…'), findsNothing);
    // 顶部「进行中」进度条保留(增量搜索仍要有连续反馈)。
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // 防抖到期:结果落地,骨架退场(加载判定/时机与替换前一致)。
    await tester.pump(kSearchDebounce + const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byType(SkeletonRow), findsNothing);
    expect(
      find.bySemanticsLabel('搜索中…'),
      findsNothing,
      reason: '结果落地后语义锚点随骨架双向退场',
    );
  });

  /// 落点 3:关注页刷新中指示位 —— 同尺寸骨架块替换原 16×16 加载圈。
  ///
  /// 说明:关注列表 provider 是同步 Notifier(fixture 种子即时可见),该页
  /// **没有首屏加载分支**;唯一加载指示是头栏「刷新封面与状态」按钮位的
  /// 16×16 加载圈,故骨架落在该位置(位置/时机/布局均不变)。
  testWidgets('关注页刷新中:头栏指示位换成骨架块、不再出现加载圈', (tester) async {
    // 与 follow_view_test 同口径:卡片固定元信息区在测试字体下会溢出,
    // 属既有布局在测试环境的固有表现,只放行溢出类错误。
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      if (details.exception.toString().contains('A RenderFlex overflowed')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);

    tester.view.physicalSize = const Size(1280, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Scaffold(body: FollowView())),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));

    final refreshButton = find.byTooltip('刷新封面与状态');
    expect(refreshButton, findsOneWidget, reason: '刷新前:头栏是刷新按钮');
    expect(find.byType(ShaderMask), findsNothing);

    await tester.tap(refreshButton);
    await tester.pump();

    expect(find.byType(ShaderMask), findsOneWidget, reason: '刷新中:指示位换成骨架块');
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(refreshButton, findsNothing, reason: '刷新中:按钮位由骨架取代');

    // fixture 下 refresher 为空 → 600ms 模拟耗时;跑完避免留下 pending timer。
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 50));
    expect(refreshButton, findsOneWidget, reason: '刷新结束:恢复刷新按钮');
    expect(find.byType(ShaderMask), findsNothing);
  });
}
