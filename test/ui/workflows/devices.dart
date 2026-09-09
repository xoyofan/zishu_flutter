/// 移动端设备矩阵常量表(任务卡 W1):供设备 workflow 测试参数化使用。
///
/// - 尺寸为**逻辑分辨率**(logical px),dpr 为设备像素比,与
///   `tester.view.devicePixelRatio` / `physicalSize` 的注入约定对应。
/// - safeArea 为逻辑像素安全区 insets(刘海/挖孔/手势条),iPhone 15 注入
///   (top 47, bottom 34),其余设备默认零 insets(W11 SafeArea 卡用)。
/// - 消费方:W8 `layout_harness.dart`(pumpOnDevice)、W9 手机纵向、
///   W10 平板/横屏、W11 SafeArea/大字体矩阵。
library;

import 'package:flutter/widgets.dart';

/// 单台测试设备的视口参数。
class TestDevice {
  const TestDevice({
    required this.name,
    required this.width,
    required this.height,
    required this.dpr,
    this.safeArea = EdgeInsets.zero,
  });

  /// 设备显示名(报告/用例 reason 用,要求在表内唯一)。
  final String name;

  /// 逻辑宽度(logical px,竖屏)。
  final double width;

  /// 逻辑高度(logical px,竖屏)。
  final double height;

  /// 设备像素比(devicePixelRatio)。
  final double dpr;

  /// 安全区 insets(逻辑像素;刘海 top/手势条 bottom 等)。
  final EdgeInsets safeArea;

  /// 逻辑视口尺寸。
  Size get logicalSize => Size(width, height);

  /// 物理视口尺寸(width/height * dpr),可直接喂 `tester.view.physicalSize`。
  Size get physicalSize => Size(width * dpr, height * dpr);

  /// 是否横屏(宽 > 高,横屏组成员)。
  bool get isLandscape => width > height;

  @override
  String toString() => '$name ${width}x$height@$dpr';
}

/// 手机纵向组(W9 手机溢出矩阵)。
const List<TestDevice> kPhoneDevices = [
  // iPhone SE(2016 比例小屏,无刘海)。
  TestDevice(name: 'iPhone SE', width: 375, height: 667, dpr: 2),
  // iPhone 15:灵动岛 top 47、手势条 bottom 34(W11 SafeArea 注入源)。
  TestDevice(
    name: 'iPhone 15',
    width: 393,
    height: 852,
    dpr: 3,
    safeArea: EdgeInsets.fromLTRB(0, 47, 0, 34),
  ),
  // iPhone 15 Pro Max。
  TestDevice(name: 'iPhone 15 Pro Max', width: 430, height: 932, dpr: 3),
  // Android 小屏(360 基准)。
  TestDevice(name: 'Android Small', width: 360, height: 640, dpr: 2),
  // Pixel 7(2.625x)。
  TestDevice(name: 'Pixel 7', width: 412, height: 915, dpr: 2.625),
];

/// 平板组(W10 平板矩阵)。
const List<TestDevice> kTabletDevices = [
  TestDevice(name: 'iPad mini', width: 744, height: 1133, dpr: 2),
  TestDevice(name: 'iPad Air', width: 820, height: 1180, dpr: 2),
  TestDevice(name: 'iPad Pro 12.9', width: 1024, height: 1366, dpr: 2),
  // Android 平板(800 基准)。
  TestDevice(name: 'Android Tablet', width: 800, height: 1280, dpr: 2),
];

/// 手机横屏组(W10 播放页横屏专项):
/// 分别为 iPhone 15 与 Pixel 7 的横置逻辑分辨率;不注入横屏刘海 insets
/// (避免过度假设,W11 如需可按设备追加)。
const List<TestDevice> kLandscapeDevices = [
  TestDevice(name: 'iPhone 15 Landscape', width: 852, height: 393, dpr: 3),
  TestDevice(name: 'Pixel 7 Landscape', width: 915, height: 412, dpr: 2.625),
];

/// 全量设备矩阵:手机 5 + 平板 4 + 横屏 2,共 11 台。
const List<TestDevice> kTestDevices = [
  ...kPhoneDevices,
  ...kTabletDevices,
  ...kLandscapeDevices,
];
