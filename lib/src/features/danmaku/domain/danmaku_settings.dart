/// 弹幕细粒度设置:纯逻辑模型(无 Riverpod / 无 IO 依赖)。
///
/// 仅承载「数值 + 范围 clamp + speed ↔ duration 映射 + 显示区域档位」,
/// 便于在 VM 单测中直接构造与断言,不被持久化/UI 污染。
///
/// 注意:本模型刻意不依赖 [DanmakuStyle] 的常量,避免 widgets→domain 之外的
/// 反向耦合;默认值与 `danmaku_overlay` 现行为保持一致(见各 `k*Default` 注释)。
library;

/// 弹幕细粒度设置快照。
///
/// - [opacity]:叠加层整体不透明度,百分比 10~100(100 = 完全不透明);
/// - [fontSize]:弹幕字号(px,固定值不随画布缩放),12~36;
/// - [speed]:滚动速度档 1~10(1 最慢、10 最快),经 [danmakuDurationForSpeed]
///   映射为单条弹幕滚动总时长(速度越快时长越短);
/// - [displayAreaRatio]:弹幕可占画布高度比例,取 [kDanmakuDisplayAreaRatios]
///   之一(1.0 = 全屏,0.125 = 仅顶部 1/8 屏)。
class DanmakuSettings {
  const DanmakuSettings({
    this.opacity = kOpacityDefault,
    this.fontSize = kFontSizeDefault,
    this.speed = kSpeedDefault,
    this.displayAreaRatio = kDisplayAreaDefault,
  });

  /// 不透明度百分比下限(10% 仍可读,避免完全隐形)。
  static const int kOpacityMin = 10;

  /// 不透明度百分比上限。
  static const int kOpacityMax = 100;

  /// 出厂默认不透明度 100%(与现行为一致:painter 当前无透明度叠加)。
  static const int kOpacityDefault = 100;

  /// 字号下限(px)。
  static const int kFontSizeMin = 12;

  /// 字号上限(px)。
  static const int kFontSizeMax = 36;

  /// 出厂默认字号 = [DanmakuStyle.fontSize](20px)。
  ///
  /// 说明:任务卡文字写「默认字号 16」,但 `danmaku_overlay` 当前渲染使用的
  /// 是 [DanmakuStyle.fontSize] = 20px(见 `danmaku_style.dart`),且验收要求
  /// 「默认值必须与现行为一致」。为保住既有基线(默认行为不变、既有用例不红),
  /// 此处取 20 而非 16,与 overlay 默认入参同源。若产品确实想以 16 为默认,
  /// 需同步下调 [DanmakuStyle.fontSize] 并回归视觉。
  static const int kFontSizeDefault = 20;

  /// 速度档下限(最慢)。
  static const int kSpeedMin = 1;

  /// 速度档上限(最快)。
  static const int kSpeedMax = 10;

  /// 出厂默认速度档。
  ///
  /// 取 7:经 [danmakuDurationForSpeed] 映射约 7.3s,是 1~10 整数档里最接近
  /// 现行为 8s 的一档(overlay 本身仍保留 durationSeconds=8 的入参默认值,
  /// 仅当接线传入 speedFactor 时才走此映射)。
  static const int kSpeedDefault = 7;

  /// 出厂默认显示区域:全屏(弹幕可占满画布高度)。
  static const double kDisplayAreaDefault = 1.0;

  /// 可选显示区域比例档位(降序:全屏 → 1/8 屏)。
  ///
  /// 语义 = 弹幕可占画布高度比例,overlay 据此裁剪可用轨道高度。
  static const List<double> kDisplayAreaRatios = <double>[
    1.0, // 全屏
    0.75, // 3/4 屏
    0.5, // 1/2 屏
    0.25, // 1/4 屏
    0.125, // 1/8 屏
  ];

  final int opacity;
  final int fontSize;
  final int speed;
  final double displayAreaRatio;

  /// 带字段覆盖的拷贝。
  DanmakuSettings copyWith({
    int? opacity,
    int? fontSize,
    int? speed,
    double? displayAreaRatio,
  }) => DanmakuSettings(
    opacity: opacity ?? this.opacity,
    fontSize: fontSize ?? this.fontSize,
    speed: speed ?? this.speed,
    displayAreaRatio: displayAreaRatio ?? this.displayAreaRatio,
  );

  /// 将任意(可能越界/脏)输入 clamp 到合法范围,缺失字段回退默认值。
  ///
  /// 用于本地存储读盘后的归一:脏值(如速度 99)被夹到 [kSpeedMax],缺失值
  /// 用默认值,保证 state 永远处于合法区间,UI 不会收到非法滑杆位置。
  static DanmakuSettings clamp({
    int? opacity,
    int? fontSize,
    int? speed,
    double? displayAreaRatio,
  }) {
    return DanmakuSettings(
      opacity: (opacity ?? kOpacityDefault).clamp(kOpacityMin, kOpacityMax),
      fontSize: (fontSize ?? kFontSizeDefault).clamp(
        kFontSizeMin,
        kFontSizeMax,
      ),
      speed: (speed ?? kSpeedDefault).clamp(kSpeedMin, kSpeedMax),
      displayAreaRatio: (displayAreaRatio ?? kDisplayAreaDefault).clamp(
        kDisplayAreaRatios.last,
        kDisplayAreaRatios.first,
      ),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DanmakuSettings &&
          opacity == other.opacity &&
          fontSize == other.fontSize &&
          speed == other.speed &&
          displayAreaRatio == other.displayAreaRatio;

  @override
  int get hashCode => Object.hash(opacity, fontSize, speed, displayAreaRatio);
}

/// 速度档(1~10)→ 单条弹幕滚动总时长(秒)的映射。
///
/// 设计:速度 1 = 最慢 ≈ 16s,速度 10 = 最快 ≈ 3s,线性反比(满足任务卡端点
/// 16s/3s)。像素速度 = (canvasWidth + textWidth)/duration,由 overlay 保证
/// 速度随画布宽度,本函数只关心「档位 → 时长」这一标量。
///
/// 返回值夹到 [3, 16],越界输入安全回退。
double danmakuDurationForSpeed(int speed) {
  final s = speed.clamp(DanmakuSettings.kSpeedMin, DanmakuSettings.kSpeedMax);
  // s=1 → 16; s=10 → 16 - 9*(13/9) = 3。
  final duration = 16.0 - (s - 1) * (13.0 / 9.0);
  return duration.clamp(3.0, 16.0);
}
