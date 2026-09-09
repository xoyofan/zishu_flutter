/// 移动端布局测试 harness(tasks-workflows.md 卡片 W9/W10/W11 配套)。
///
/// 纯库函数,仅依赖 flutter_test 公共 API,不 import 任何应用侧代码:
/// - W9(移动端视口注入卡):[MobileDevice] / [kMobileDevices] 设备表、
///   [pumpOnDevice] 视口与安全区注入、[resetViewport] 复位;
/// - W10(溢出与字号扫测卡):[overflowSweep] 逐设备 RenderFlex 溢出扫测、
///   [textScaleSweep] 逐档字号缩放扫测;
/// - W11(安全区锚点卡):[safeAreaSweep] iPhone 15 刘海 insets 下的
///   关键锚点遮挡断言。
///
/// 设备档位与 W1 卡的 devices.dart 遵循同名同值约定(iPhone SE 375x667@2x、
/// iPhone 15 393x852@3x insets(47,34)、ProMax 430x932@3x insets(55,34)、
/// Android 小屏 360x640@2x、Pixel7 412x915@2.625、iPad mini 744x1133@2x、
/// iPad Air 820x1180@2x、iPad Pro12.9 1024x1366@2x、Android 平板 800x1280@2x、
/// 横屏 852x393 / 915x412);为避免并行改动冲突,此处独立定义,不 import
/// devices.dart。
///
/// 宿主约定(与 test/ui/app_shell_test.dart 一致):
/// - 固定次数 pump(初始帧 + 50ms 数据帧),不使用 pumpAndSettle;
/// - 所有 sweep 返回 `List<String>` 失败记录,空列表即通过,便于在单个
///   testWidgets 内聚合断言:`expect(failures, isEmpty)`。
///
/// sweep 用 `print` 输出逐设备进度(tasks-workflows.md W10/W11 卡要求
/// `[overflow]/[textScale]/[safeArea]` 日志可 grep),故对整个文件放行
/// avoid_print。
// ignore_for_file: avoid_print
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 移动设备档位:逻辑分辨率([size])+ 像素密度([devicePixelRatio])+
/// 系统安全区 insets([safeArea],逻辑像素)。
///
/// [size] 与 Flutter 逻辑像素一致;[physicalSize] = 逻辑尺寸 x DPR,用于
/// 注入 `tester.view.physicalSize`;[safeArea] 经 `tester.view.padding` 注入
/// 后随 `MediaQueryData.fromView` 变成 `MediaQuery.padding`。
class MobileDevice {
  /// const 构造;[safeArea] 缺省为无遮挡(平板/占位档)。
  const MobileDevice({
    required this.name,
    required this.size,
    required this.devicePixelRatio,
    this.safeArea = EdgeInsets.zero,
  });

  /// 设备短名,用于日志与失败记录,如 `iPhone15`。
  final String name;

  /// 逻辑分辨率(width x height)。
  final Size size;

  /// 设备像素比 DPR。
  final double devicePixelRatio;

  /// 系统安全区 insets(逻辑像素):刘海/状态栏 top、Home 指示条 bottom 等。
  final EdgeInsets safeArea;

  /// 物理分辨率 = 逻辑分辨率 x DPR,注入 [WidgetTester.view.physicalSize] 用。
  Size get physicalSize => size * devicePixelRatio;

  /// 日志用全名,如 `iPhone15(393x852@3.0)`。
  String get label => '$name(${size.width}x${size.height}@$devicePixelRatio)';
}

/// iPhone SE:375x667@2x,无刘海(安全区 0)。
const MobileDevice kIphoneSe = MobileDevice(
  name: 'iPhoneSE',
  size: Size(375, 667),
  devicePixelRatio: 2.0,
);

/// iPhone 15:393x852@3x,刘海 insets(top 47 / bottom 34)。W11 默认设备。
const MobileDevice kIphone15 = MobileDevice(
  name: 'iPhone15',
  size: Size(393, 852),
  devicePixelRatio: 3.0,
  safeArea: EdgeInsets.only(top: 47, bottom: 34),
);

/// iPhone 15 Pro Max:430x932@3x,刘海 insets(top 55 / bottom 34)。
const MobileDevice kIphone15ProMax = MobileDevice(
  name: 'iPhone15ProMax',
  size: Size(430, 932),
  devicePixelRatio: 3.0,
  safeArea: EdgeInsets.only(top: 55, bottom: 34),
);

/// Android 小屏:360x640@2x,安全区 0。
const MobileDevice kAndroidSmall = MobileDevice(
  name: 'AndroidSmall',
  size: Size(360, 640),
  devicePixelRatio: 2.0,
);

/// Pixel 7:412x915@2.625,安全区 0。
const MobileDevice kPixel7 = MobileDevice(
  name: 'Pixel7',
  size: Size(412, 915),
  devicePixelRatio: 2.625,
);

/// iPad mini:744x1133@2x,安全区 0。
const MobileDevice kIpadMini = MobileDevice(
  name: 'iPadMini',
  size: Size(744, 1133),
  devicePixelRatio: 2.0,
);

/// iPad Air:820x1180@2x,安全区 0。
const MobileDevice kIpadAir = MobileDevice(
  name: 'iPadAir',
  size: Size(820, 1180),
  devicePixelRatio: 2.0,
);

/// iPad Pro 12.9:1024x1366@2x,安全区 0。
const MobileDevice kIpadPro129 = MobileDevice(
  name: 'iPadPro129',
  size: Size(1024, 1366),
  devicePixelRatio: 2.0,
);

/// Android 平板:800x1280@2x,安全区 0。
const MobileDevice kAndroidTablet = MobileDevice(
  name: 'AndroidTablet',
  size: Size(800, 1280),
  devicePixelRatio: 2.0,
);

/// iPhone 15 横屏:852x393@3x,安全区 0(刘海横置,占位不注入)。
const MobileDevice kIphone15Landscape = MobileDevice(
  name: 'iPhone15Landscape',
  size: Size(852, 393),
  devicePixelRatio: 3.0,
);

/// Pixel 7 横屏:915x412@2.625,安全区 0。
const MobileDevice kPixel7Landscape = MobileDevice(
  name: 'Pixel7Landscape',
  size: Size(915, 412),
  devicePixelRatio: 2.625,
);

/// 移动设备总表(竖屏优先,横屏两档收尾)。[overflowSweep] 默认全表扫测。
const List<MobileDevice> kMobileDevices = <MobileDevice>[
  kIphoneSe,
  kIphone15,
  kIphone15ProMax,
  kAndroidSmall,
  kPixel7,
  kIpadMini,
  kIpadAir,
  kIpadPro129,
  kAndroidTablet,
  kIphone15Landscape,
  kPixel7Landscape,
];

/// W9:把测试视口设成 [device] 的 DPR / 物理分辨率 / 安全区,并 pump [app]。
///
/// - `tester.view.devicePixelRatio = device.devicePixelRatio`;
/// - `tester.view.physicalSize = device.physicalSize`(逻辑尺寸 x DPR);
/// - `tester.view.padding = FakeViewPadding(...)` 注入安全区(逻辑 insets x
///   DPR,因 `MediaQueryData.fromView` 按物理像素解读再除 DPR),经
///   `MediaQueryData.fromView` 还原成 `MediaQuery.padding` 逻辑值;
/// - 自动 `addTearDown(resetViewport)`,测试结束恢复默认视口。
///
/// 返回前只 pump 初始一帧;需要数据落地的页面由调用方按宿主约定追加固定
/// 次数 pump(参考 test/ui/app_shell_test.dart,勿用 pumpAndSettle)。
Future<void> pumpOnDevice(
  WidgetTester tester,
  Widget app,
  MobileDevice device,
) async {
  _applyViewport(tester, device);
  addTearDown(() => resetViewport(tester));
  await tester.pumpWidget(app);
}

/// W9:tear-down helper,把测试视口恢复为 flutter_test 默认值
/// (800x600@3.0、无安全区)。
///
/// [pumpOnDevice] 已自动注册复位;单独设置过视口的测试请手动:
/// `addTearDown(() => resetViewport(tester))`。
void resetViewport(WidgetTester tester) {
  tester.view
    ..resetPhysicalSize()
    ..resetDevicePixelRatio()
    ..resetPadding();
}

/// W10:把 [pages] 在 [devices] 每一档上逐个 pump,收集 RenderFlex overflow。
///
/// 每个 (设备, 页面) 组合流程:resetViewport -> pumpOnDevice(初始帧)->
/// 50ms 数据帧 -> `tester.takeException()`。任何异常都记入失败记录
/// ('RenderFlex overflowed ...' 为布局溢出;其余异常同样算失败,避免静默
/// 放过),记录取异常首行,格式 `page@device: 异常首行`。
/// 返回失败记录(空 = 通过),并逐条打印
/// `print('[overflow] page@device: OK/FAIL')`。
///
/// 典型用法(W10 卡):
/// ```dart
/// final failures = await overflowSweep(tester, [
///   ('home', () => const HomeView()),
///   ('follow', () => const FollowView()),
/// ], devices: const [kIphoneSe, kIphone15]);
/// expect(failures, isEmpty);
/// ```
Future<List<String>> overflowSweep(
  WidgetTester tester,
  List<(String name, Widget Function() page)> pages, {
  List<MobileDevice> devices = kMobileDevices,
}) async {
  final failures = <String>[];
  for (final device in devices) {
    for (final (name, build) in pages) {
      resetViewport(tester);
      await pumpOnDevice(tester, build(), device);
      await tester.pump(const Duration(milliseconds: 50));
      final exception = tester.takeException();
      if (exception == null) {
        print('[overflow] $name@${device.label}: OK');
        continue;
      }
      final message = exception.toString();
      final isOverflow = message.contains('RenderFlex overflow');
      print(
        '[overflow] $name@${device.label}: '
        '${isOverflow ? 'FAIL(overflow)' : 'FAIL(非溢出异常)'}',
      );
      failures.add('$name@${device.label}: ${message.split('\n').first}');
    }
  }
  resetViewport(tester);
  return failures;
}

/// W10:在 [scales] 每一档字号下重建 [builder] 页面,逐档 pump + 收集异常。
///
/// 每档设置 `tester.platformDispatcher.textScaleFactorTestValue = scale`,
/// 经 `MediaQueryData.fromView` 转成 `MediaQueryData.textScaler`
/// (SystemTextScaler)后 pump 初始帧 + 50ms 数据帧 + `takeException`。
/// 结束时调用 `clearTextScaleFactorTestValue` 复位(含 addTearDown 兜底)。
///
/// [device] 为空则沿用当前视口;建议 W10 传入最窄机型(如 [kIphoneSe]),
/// 字号缩放溢出通常最先出现在窄视口。
/// 失败记录格式 `name@textScale <scale>: 异常首行`,空列表 = 通过,
/// 逐条打印 `print('[textScale] name@<scale>x: OK/FAIL')`。
Future<List<String>> textScaleSweep(
  WidgetTester tester,
  Widget Function() builder, {
  String name = 'page',
  List<double> scales = const <double>[1.0, 1.15, 1.3],
  MobileDevice? device,
}) async {
  final failures = <String>[];
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
  if (device != null) {
    _applyViewport(tester, device);
    addTearDown(() => resetViewport(tester));
  }
  for (final scale in scales) {
    tester.platformDispatcher.textScaleFactorTestValue = scale;
    await tester.pumpWidget(builder());
    await tester.pump(const Duration(milliseconds: 50));
    final exception = tester.takeException();
    if (exception == null) {
      print('[textScale] $name@${scale}x: OK');
      continue;
    }
    print('[textScale] $name@${scale}x: FAIL');
    failures.add('$name@textScale $scale: ${_firstLine(exception)}');
  }
  tester.platformDispatcher.clearTextScaleFactorTestValue();
  return failures;
}

/// W11:在 [device](默认 [kIphone15],刘海 insets top=47/bottom=34)下逐页
/// pump,断言 [anchors] 关键锚点不进入顶部安全区遮挡区:`getRect.top >= padding.top`。
///
/// [anchors] 为 锚点名 -> Finder,在每一页上都检查;finder 命中 0 个元素
/// 记失败(锚点缺失),命中多个取第一个。
/// 失败记录格式 `page/anchor: top=<y> < padding.top=<inset>`,空列表 = 通过,
/// 逐条打印 `print('[safeArea] page/anchor: OK/FAIL')`。
///
/// 典型用法(W11 卡):
/// ```dart
/// final failures = await safeAreaSweep(tester, [
///   ('home', () => const HomeView()),
/// ], {
///   'nav-topbar': find.byKey(const Key('nav-home')),
/// });
/// expect(failures, isEmpty);
/// ```
Future<List<String>> safeAreaSweep(
  WidgetTester tester,
  List<(String name, Widget Function() page)> pages,
  Map<String, Finder> anchors, {
  MobileDevice device = kIphone15,
}) async {
  final failures = <String>[];
  final topInset = device.safeArea.top;
  for (final (name, build) in pages) {
    resetViewport(tester);
    await pumpOnDevice(tester, build(), device);
    await tester.pump(const Duration(milliseconds: 50));
    for (final MapEntry(key: anchor, value: finder) in anchors.entries) {
      if (finder.evaluate().isEmpty) {
        print('[safeArea] $name/$anchor: FAIL(锚点未命中)');
        failures.add('$name/$anchor: 锚点未命中');
        continue;
      }
      final rect = tester.getRect(finder.first);
      if (rect.top >= topInset) {
        print('[safeArea] $name/$anchor: OK');
      } else {
        print('[safeArea] $name/$anchor: FAIL');
        failures.add('$name/$anchor: top=${rect.top} < padding.top=$topInset');
      }
    }
  }
  resetViewport(tester);
  return failures;
}

/// 注入视口档位:DPR 先行,再设物理尺寸,最后注入安全区 padding。
///
/// 注意:`MediaQueryData.fromView` 经 `EdgeInsets.fromViewPadding` 把
/// `tester.view.padding` 的值按物理像素解读(再除以 DPR),而 [MobileDevice]
/// 的 [MobileDevice.safeArea] 是逻辑像素,因此这里注入时乘回 DPR。
void _applyViewport(WidgetTester tester, MobileDevice device) {
  final dpr = device.devicePixelRatio;
  tester.view
    ..devicePixelRatio = dpr
    ..physicalSize = device.physicalSize
    ..padding = FakeViewPadding(
      left: device.safeArea.left * dpr,
      top: device.safeArea.top * dpr,
      right: device.safeArea.right * dpr,
      bottom: device.safeArea.bottom * dpr,
    );
}

/// 取异常首行,保持失败记录单行可 grep。
String _firstLine(Object exception) => exception.toString().split('\n').first;
