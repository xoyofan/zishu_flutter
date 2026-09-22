/// 氛围轨共享微交互 widget 契约测试。
///
/// 覆盖清单 §2 的三个共享效果与降级开关：
/// - 2.1 卡片 hover 抬升 + [AmbientGlow.cardHover] 发光（[AmbientCardHover]）
/// - 2.2 / 2.5 主 CTA 流光描边 + pressed 缩放 0.97（[AmbientCtaHover]）
/// - 2.3 live 圆点扩散涟漪 + "静态点保留"（[StateDot]）
/// - 清单 1.4 的 `reduce_motion`（[AmbientMotion.of]）降级
///
/// 只断言接口契约（位移值、发光来源、时长来源、静态档），不锁像素；
/// 像素回归由 `test/ui/*_shot_test.dart` 的 7 张 golden 负责。
library;

import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/ambient_card_hover.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/ambient_cta_hover.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/state_dot.dart';
import 'package:zishu_flutter/src/shared/presentation/zishu_tokens.dart';

void main() {
  /// 宿主：MaterialApp + 可控 `disableAnimations` 的 MediaQuery。
  ///
  /// `disableAnimations` 就是 [AmbientMotion.of] 的降级开关（清单 1.4），
  /// 这里显式覆写 mock 掉宿主环境，避免依赖测试 binding 的默认值。
  Future<void> pumpHost(
    WidgetTester tester,
    Widget child, {
    bool reduced = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
            child: Scaffold(body: Center(child: child)),
          ),
        ),
      ),
    );
  }

  /// 鼠标移入 [target] 并等完 150ms 进/出过渡。
  Future<TestGesture> hoverIn(WidgetTester tester, Finder target) async {
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await gesture.moveTo(tester.getCenter(target));
    await tester.pump();
    await tester.pump(AppMotion.fast);
    return gesture;
  }

  /// 移出 hover（落点远离被测控件）并等完过渡。
  Future<void> hoverOut(WidgetTester tester, TestGesture gesture) async {
    await gesture.moveTo(const Offset(4, 4));
    await tester.pump();
    await tester.pump(AppMotion.fast);
  }

  /// 拆掉整棵树，释放被测组件里可能正在循环的 Ticker。
  Future<void> unmount(WidgetTester tester) =>
      tester.pumpWidget(const SizedBox.shrink());

  group('AmbientCardHover（清单 2.1）', () {
    AnimatedContainer hostBox(WidgetTester tester) =>
        tester.widget<AnimatedContainer>(
          find.descendant(
            of: find.byType(AmbientCardHover),
            matching: find.byType(AnimatedContainer),
          ),
        );

    Transform hostTransform(WidgetTester tester) => tester.widget<Transform>(
      find.descendant(
        of: find.byType(AmbientCardHover),
        matching: find.byType(Transform),
      ),
    );

    Future<void> pumpCard(WidgetTester tester, {bool reduced = false}) =>
        pumpHost(
          tester,
          AmbientCardHover(
            borderRadius: AppRadius.allMd,
            child: const SizedBox(width: 100, height: 80),
          ),
          reduced: reduced,
        );

    testWidgets('常态不位移、投影恒在；hover 抬升 −2px 且发光取 AmbientGlow.cardHover', (
      tester,
    ) async {
      await pumpCard(tester);

      expect(hostTransform(tester).transform.getTranslation().y, 0);
      // 性能约束：常态网格不保留大面积阴影，避免多卡栅格化。
      expect((hostBox(tester).decoration! as BoxDecoration).boxShadow, isNull);

      final gesture = await hoverIn(tester, find.byType(AmbientCardHover));

      expect(hostTransform(tester).transform.getTranslation().y, -2);
      final hovered = hostBox(tester).decoration! as BoxDecoration;
      expect(hovered.boxShadow, AmbientGlow.cardHover(ZishuTokens.dark.accent));
      // 外发光贴合卡片自身圆角。
      expect(hovered.borderRadius, AppRadius.allMd);
      // 150ms 进/出 + 复用 AppMotion.curve,不新造曲线。
      expect(hostBox(tester).duration, AppMotion.fast);
      expect(hostBox(tester).curve, AppMotion.curve);

      await hoverOut(tester, gesture);
      expect(hostTransform(tester).transform.getTranslation().y, 0);
      expect((hostBox(tester).decoration! as BoxDecoration).boxShadow, isNull);
    });

    testWidgets('reduce_motion：时长降到零、hover 仍直出终态', (tester) async {
      await pumpCard(tester, reduced: true);

      expect(hostBox(tester).duration, Duration.zero);

      await hoverIn(tester, find.byType(AmbientCardHover));
      expect(hostTransform(tester).transform.getTranslation().y, -2);
      expect(
        (hostBox(tester).decoration! as BoxDecoration).boxShadow,
        AmbientGlow.cardHover(ZishuTokens.dark.accent),
      );
    });
  });

  group('AmbientCtaHover（清单 2.2 / 2.5）', () {
    Finder ringPaint() => find.descendant(
      of: find.byType(AmbientCtaHover),
      matching: find.byType(CustomPaint),
    );

    AnimatedScale scaleHost(WidgetTester tester) =>
        tester.widget<AnimatedScale>(
          find.descendant(
            of: find.byType(AmbientCtaHover),
            matching: find.byType(AnimatedScale),
          ),
        );

    Future<void> pumpCta(WidgetTester tester, {bool reduced = false}) =>
        pumpHost(
          tester,
          AmbientCtaHover(
            borderRadius: AppRadius.allSm,
            // `opaque`：让测试里的占位子控件可被命中（真实调用点是可点击的
            // IconButton / InkWell，press 事件同样会冒泡到外层 Listener）。
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {},
              child: const SizedBox(width: 120, height: 36),
            ),
          ),
          reduced: reduced,
        );

    testWidgets('hover 出渐变描边（呼吸只在 hover 时跑），移出后停表且不常驻 Ticker', (tester) async {
      await pumpCta(tester);

      // 常态:没有描边图层,缩放 1.0,且不留常驻动画帧。
      expect(ringPaint(), findsNothing);
      expect(scaleHost(tester).scale, 1.0);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);

      final gesture = await hoverIn(tester, find.byType(AmbientCtaHover));

      expect(ringPaint(), findsOneWidget);
      expect(scaleHost(tester).scale, 1.0);
      expect(scaleHost(tester).duration, AppMotion.fast);
      expect(scaleHost(tester).curve, AppMotion.curve);
      // hover 中呼吸循环持续请求帧（pulse 周期由 token 给）。
      expect(tester.binding.hasScheduledFrame, isTrue);

      // 呼吸驱动 opacity 在 0.5–1.0 之间,不熄到全透明(描边始终可见)。
      await tester.pump(const Duration(milliseconds: 400));
      final breathe = find.descendant(
        of: find.byType(AmbientCtaHover),
        matching: find.byType(Opacity),
      );
      expect(breathe, findsOneWidget);
      expect(
        tester.widget<Opacity>(breathe).opacity,
        inInclusiveRange(0.5, 1.0),
      );

      await hoverOut(tester, gesture);
      expect(ringPaint(), findsNothing);
      expect(tester.binding.hasScheduledFrame, isFalse);

      await unmount(tester);
    });

    testWidgets('描边画笔:圆角矩形描线,可重复绘制不抛异常', (tester) async {
      await pumpCta(tester);
      await hoverIn(tester, find.byType(AmbientCtaHover));

      final painter = tester.widget<CustomPaint>(ringPaint()).painter!;
      expect(painter.shouldRepaint(painter), isFalse);
      final recorder = ui.PictureRecorder();
      painter.paint(Canvas(recorder), const Size(120, 36));
      recorder.endRecording().dispose();
      expect(painter.semanticsBuilder, isNull);

      await unmount(tester);
    });

    testWidgets('pressed 缩放 0.97 且抬起复位（与 AppStateLayer 叠加,不改按下色）', (
      tester,
    ) async {
      await pumpCta(tester);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(AmbientCtaHover)),
      );
      await tester.pump();
      await tester.pump(AppMotion.fast);
      expect(scaleHost(tester).scale, 0.97);

      await gesture.up();
      await tester.pump(AppMotion.fast);
      expect(scaleHost(tester).scale, 1.0);
    });

    testWidgets('reduce_motion：描边静态（无呼吸图层）、缩放零时长', (tester) async {
      await pumpCta(tester, reduced: true);

      expect(scaleHost(tester).duration, Duration.zero);

      await hoverIn(tester, find.byType(AmbientCtaHover));

      expect(ringPaint(), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AmbientCtaHover),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
      expect(tester.binding.hasScheduledFrame, isFalse);

      await unmount(tester);
    });
  });

  group('StateDot（清单 2.3）', () {
    Finder rings() => find.descendant(
      of: find.byType(StateDot),
      matching: find.byType(Transform),
    );

    testWidgets('live：两圈错相扩散涟漪；offline：只有静态点', (tester) async {
      await pumpHost(tester, const StateDot(live: true));
      expect(rings(), findsNWidgets(2));
      expect(
        find.descendant(
          of: find.byType(StateDot),
          matching: find.byType(Opacity),
        ),
        findsNWidgets(2),
      );
      await unmount(tester);

      await pumpHost(tester, const StateDot());
      expect(rings(), findsNothing);
      expect(
        find.descendant(
          of: find.byType(StateDot),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('reduce_motion：live 也只出静态点,不运行动画', (tester) async {
      await pumpHost(tester, const StateDot(live: true), reduced: true);

      expect(rings(), findsNothing);
      await tester.pump();
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  });
}
