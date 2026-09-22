/// 氛围层 A(清单 3.1 / 3.2 / 3.3 / 3.4 / 3.7)的机械验证。
///
/// 这几项大多在静态 golden 里**看不出**:浮层入场跑完即终态、光晕只在舞台
/// 外圈、毛玻璃的 sigma / 透明度得读 widget 属性。故用 widget 断言把三件事
/// 钉住:
/// ① 值取自 token,且毛玻璃 sigma ≤ `AmbientBlur.maxSigma` 硬上限(清单 1.3);
/// ② 渲染守卫 —— 沉浸态 / 窗口失焦不渲染光晕;常规布局侧栏保持不透明
///    (3.2 的"常规布局像素零变化"是硬要求);
/// ③ 降级路径 —— `reduce_motion` 直出终态,不建动画层(清单 1.4)。
library;

import 'dart:ui' show ImageFilter;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show StreamLine;
import 'package:zishu_flutter/src/app/app_router.dart';
import 'package:zishu_flutter/src/apps/windows/windows_app.dart';
import 'package:zishu_flutter/src/features/play/application/play_provider.dart';
import 'package:zishu_flutter/src/platforms/common/playback/live_player.dart';
import 'package:zishu_flutter/src/shared/presentation/design_tokens.dart';
import 'package:zishu_flutter/src/shared/presentation/widgets/ambient_glass.dart';

/// 播放页深链位置(fixture 样例房间,与 layout / golden 基线同房间)。
const String _kPlayLocation = '/douyu/play/63136';

/// 固定 pump 步长,与既有 workflow 测试一致(不用 pumpAndSettle:封面图在 VM
/// 里不会真正加载)。
const Duration _kFrame = Duration(milliseconds: 50);

/// 测试替身:VM 下替代 MediaKitLivePlayer。
class _FakeLivePlayer implements LivePlayer {
  @override
  Stream<PlayerSnapshot> get snapshots =>
      Stream<PlayerSnapshot>.value(const PlayerSnapshot());

  @override
  Widget buildVideoView({BoxFit fit = BoxFit.contain}) =>
      const SizedBox.expand();

  @override
  Future<void> open(StreamLine line,
          [List<StreamLine> fallbacks = const [], bool resetRetries = true]) async {}

  @override
  Future<void> play() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setMuted(bool muted) async {}

  @override
  Future<void> toggleFullscreen() async {}

  @override
  Future<void> setFullscreen(bool fullscreen) async {}

  @override
  Future<void> enterPictureInPicture({double? aspectRatio}) async {}

  @override
  Future<void> exitPictureInPicture() async {}

  @override
  Future<void> stop() async {}

  @override
  Widget wrapPipSurface(Widget child) => child;

  @override
  void dispose() {}
}

Future<void> _frames(WidgetTester tester, [int times = 3]) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

Future<GoRouter> _pumpApp(
  WidgetTester tester, {
  Size size = const Size(1440, 900),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [playerProvider.overrideWithValue(_FakeLivePlayer())],
      child: const WindowsApp(),
    ),
  );
  await _frames(tester, 2);
  final element = tester.element(find.byType(Scaffold).first);
  return ProviderScope.containerOf(element).read(routerProvider);
}

/// 把键盘焦点交给播放页舞台(页面级 Space/M/F 快捷键沿焦点树冒泡才可达)。
Future<void> _focusStage(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('play-stage-focus')));
  await _frames(tester, 2);
}

/// 按 F 进入 / 退出全屏(呈现态唯一入口,见 play_screen_provider)。
Future<void> _pressF(WidgetTester tester) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
  await _frames(tester, 4);
}

/// 走平台生命周期通道(测试里不能直调 `@protected` 的 binding 方法)。
Future<void> _setLifecycle(WidgetTester tester, AppLifecycleState state) async {
  await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .handlePlatformMessage(
        'flutter/lifecycle',
        const StringCodec().encodeMessage(state.toString()),
        (_) {},
      );
  await _frames(tester, 2);
}

/// 鼠标悬停到指定锚点(单指针:同一用例内不要重复 addPointer)。
Future<TestGesture> _hover(WidgetTester tester, Key key) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: Offset.zero);
  addTearDown(() => gesture.removePointer());
  await gesture.moveTo(tester.getCenter(find.byKey(key)));
  return gesture;
}

/// 是否存在带指定 sigma 的毛玻璃(`ImageFilter.blur` 有值语义 ==)。
bool _hasBlur(WidgetTester tester, double sigma) => tester
    .widgetList<BackdropFilter>(find.byType(BackdropFilter))
    .any((f) => f.filter == ImageFilter.blur(sigmaX: sigma, sigmaY: sigma));

/// 是否存在 `AmbientGlow.halo`(accent 8% / blur 64)外圈光晕。
bool _hasHalo(WidgetTester tester) => tester
    .widgetList<DecoratedBox>(find.byType(DecoratedBox))
    .any((box) {
      final decoration = box.decoration;
      if (decoration is! BoxDecoration) return false;
      return (decoration.boxShadow ?? const <BoxShadow>[]).any(
        (shadow) =>
            shadow.blurRadius == AmbientGlow.haloBlur &&
            (shadow.color.a - AmbientGlow.haloAlpha).abs() < 1e-9,
      );
    });

/// 取某个 `Container` 的底色(3.2 的"不透明 / 玻璃化"断言用)。
Color _containerColor(WidgetTester tester, Key key) {
  final container = tester.widget<Container>(find.byKey(key));
  return (container.decoration! as BoxDecoration).color!;
}

void main() {
  testWidgets('3.1 顶栏毛玻璃:薄档 glassThinAlpha 0.55 + blur 16(取自 token,≤ 上限)', (tester) async {
    await _pumpApp(tester);
    // 顶栏容器:nav-brand 最近的 Container 祖先(高度 = AppSpacing.topNavHeight)。
    final nav = tester.widget<Container>(
      find
          .ancestor(
            of: find.byKey(const Key('nav-brand')),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(nav.constraints?.maxHeight, AppSpacing.topNavHeight);
    final color = (nav.decoration! as BoxDecoration).color!;
    // 批1(DESIGN.md §2.4):顶栏改薄档 0.55 透出 Aurora 平台色氛围;
    // 0.85 厚档保留给清单 3.2 侧栏/沉浸面板(底下是视频)。
    expect(color.a, closeTo(AmbientBlur.glassThinAlpha, 1e-9));
    expect(
      AmbientBlur.glassThinAlpha,
      lessThan(AmbientBlur.glassSurfaceAlpha),
    );
    expect(AmbientBlur.navSigma, lessThanOrEqualTo(AmbientBlur.maxSigma));
    expect(_hasBlur(tester, AmbientBlur.navSigma), isTrue);
    // 清单 §4「明确不做」:毛玻璃只做 3.1/3.2 两处 —— 壳层静止态只有顶栏一层。
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('3.4 顶部光带:accent ≤6% 渐变,只占顶栏下沿 6px', (tester) async {
    await _pumpApp(tester);
    final band = tester.widgetList<DecoratedBox>(find.byType(DecoratedBox)).firstWhere(
      (box) {
        final decoration = box.decoration;
        return decoration is BoxDecoration &&
            decoration.gradient is LinearGradient;
      },
    );
    final gradient =
        (band.decoration as BoxDecoration).gradient! as LinearGradient;
    expect(gradient.colors.first.a, 0);
    expect(gradient.colors.last.a, closeTo(AmbientGlow.topBandAlpha, 1e-9));
    expect(AmbientGlow.topBandAlpha, lessThanOrEqualTo(0.06));
    final rect = tester.getRect(find.byWidget(band));
    expect(rect.height, 6, reason: '光带只占顶栏下沿一条,不挤压导航项');
    expect(
      rect.bottom,
      AppSpacing.topNavHeight - 1,
      reason: '贴着顶栏下沿(Container 的 1px 底边框会内缩子级)',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('3.7 浮层入场:opacity 0→1 + scale 0.98→1(AppMotion.normal 档)', (tester) async {
    // 显式声明动画可用(不依赖测试环境默认的 reduce_motion 取值)。
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: false);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpApp(tester);
    await _hover(tester, const Key('platform-tab-douyu'));
    // 入场首帧:opacity 0(不可见)、scale 0.98、锚点为顶边中点。
    await tester.pump();
    final panel = find.byKey(const Key('platform-flyout-panel'));
    expect(panel, findsOneWidget);
    final opacity = tester.widget<Opacity>(
      find.descendant(of: panel, matching: find.byType(Opacity)).first,
    );
    expect(opacity.opacity, 0);
    final scale = tester.widget<Transform>(
      find.descendant(of: panel, matching: find.byType(Transform)).first,
    );
    expect(scale.alignment, Alignment.topCenter);
    expect(scale.transform.storage[0], closeTo(0.98, 1e-6));

    // 跑完 250ms 档:入场动画层不残留(Opacity/Transform 同时创建,断言其一
    // 即可)→ 静止态像素与加动效前一致。浮层宽度本身由异步分类数据决定,
    // 故这里不比几何。
    await _frames(tester, 12);
    expect(
      find.descendant(of: panel, matching: find.byType(Opacity)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('3.7 reduce_motion:直出终态,不建动画层', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pumpApp(tester);
    await _hover(tester, const Key('platform-tab-douyu'));
    await tester.pump();
    final panel = find.byKey(const Key('platform-flyout-panel'));
    expect(panel, findsOneWidget);
    expect(
      find.descendant(of: panel, matching: find.byType(Opacity)),
      findsNothing,
      reason: 'reduce_motion 下首帧即终态,不该有入场动画层',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('3.2/3.3 常规布局:侧栏不透明 + 舞台外圈光晕;沉浸态:光晕停渲染 + 侧栏玻璃化',
      (tester) async {
    final router = await _pumpApp(tester);
    router.go(_kPlayLocation);
    await _frames(tester, 8);

    // 常规布局:侧栏根 / 头部保持不透明 surface(3.2 常规布局像素零变化的
    // 硬要求),整页毛玻璃只有顶栏一层;光晕在舞台外圈渲染。
    expect(_containerColor(tester, const Key('play-side-panel')).a, 1.0);
    expect(_containerColor(tester, const Key('play-side-header')).a, 1.0);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(_hasHalo(tester), isTrue);

    // 窗口失焦:不渲染光晕(性能 / 注意力守卫)。
    await _setLifecycle(tester, AppLifecycleState.inactive);
    expect(_hasHalo(tester), isFalse);
    await _setLifecycle(tester, AppLifecycleState.resumed);
    expect(_hasHalo(tester), isTrue);

    // 进入沉浸(全屏):舞台铺满窗口 → 外发光看不见,不渲染;
    // 侧栏玻璃化(blur 12 + surface 85%),根 / 头部让出底色把画面透出来。
    await _focusStage(tester);
    await _pressF(tester);
    expect(find.byKey(const Key('play-immersive-stage')), findsOneWidget);
    expect(_hasHalo(tester), isFalse);
    expect(_hasBlur(tester, AmbientBlur.panelSigma), isTrue);
    expect(_containerColor(tester, const Key('play-side-panel')).a, 0.0);
    expect(_containerColor(tester, const Key('play-side-header')).a, 0.0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AmbientGlass:同一平面不重复卷积 / 不重复压暗', (tester) async {
    late BuildContext root;
    late BuildContext outer;
    late BuildContext inner;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            root = context;
            return AmbientGlass(
              sigma: AmbientBlur.panelSigma,
              child: Builder(
                builder: (context) {
                  outer = context;
                  return AmbientGlass(
                    sigma: AmbientBlur.panelSigma,
                    child: Builder(
                      builder: (context) {
                        inner = context;
                        return const SizedBox.shrink();
                      },
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
    );
    const surface = Color(0xFF1F1F1F);
    expect(AmbientGlass.onGlass(root), isFalse);
    expect(AmbientGlass.onGlass(outer), isTrue);
    expect(AmbientGlass.onGlass(inner), isTrue);
    expect(
      AmbientGlass.tintOf(root, surface).a,
      closeTo(AmbientBlur.glassSurfaceAlpha, 1e-9),
    );
    expect(AmbientGlass.tintOf(outer, surface).a, 0.0);
    expect(AmbientGlass.tintOf(inner, surface).a, 0.0);
    // 嵌套只保留最外层一层滤镜(Windows 上每层都是一次逐帧卷积)。
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(_hasBlur(tester, AmbientBlur.panelSigma), isTrue);
  });
}
