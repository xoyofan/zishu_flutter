import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../design_tokens.dart';

/// 毛玻璃面(氛围轨清单 3.1 / 3.2):给 [child] 加一层 `BackdropFilter`,
/// 把**它背后已画好的内容**(视频画面 / 页面画布)虚化。
///
/// 与底色的分工:[AmbientGlass] **只加滤镜**,底色由调用点自己画 ——
/// 两条约定:
/// 1. 底色 = 基色 + [AmbientBlur.glassSurfaceAlpha](85%),经 [tintOf] 取;
/// 2. 调用点原样保留自己的 `Container`(高度 / 内边距 / 边框),
///    只把 `BoxDecoration.color` 换成 [tintOf] 的结果。
///
/// 为什么不提供「自带底色的玻璃容器」:既有调用点的 `Container` 还承担布局
/// (`BoxDecoration` 的边框会内缩 1px 子级 —— 顶栏 44px 高正是靠这条内缩),
/// 换掉容器就会顺带挪动 1px 布局与 golden。所以这里只做滤镜、不做盒子。
///
/// **嵌套语义**(同一玻璃平面内的层):若祖先已经是 [AmbientGlass],内层
/// 1) 不再建第二个 `BackdropFilter`;2) [tintOf] / [onGlass] 让内层保持透明。
/// 理由:两层 85% 会把可见度压到 97.75%(玻璃"发糊"、面板出现色阶接缝),
/// 而且 Windows 桌面上每层滤镜都是一次逐帧卷积(见 [AmbientBlur.maxSigma])。
/// 反过来说,内层若照旧铺**不透明**底色,会把外层玻璃整块挡死 —— 这是
/// 3.2 里侧栏根 / 侧栏头部必须跟着改的原因。
///
/// sigma 一律取自 [AmbientBlur](≤ [AmbientBlur.maxSigma]),不在调用点手写
/// 裸数字。
class AmbientGlass extends StatelessWidget {
  const AmbientGlass({super.key, required this.sigma, required this.child});

  /// 模糊 sigma,取自 [AmbientBlur](`navSigma` 16 / `panelSigma` 12)。
  final double sigma;

  final Widget child;

  /// 是否已处在玻璃面上(最近的外层 [AmbientGlass] 之内)。
  ///
  /// 同一平面内的兄弟层(侧栏根 / 侧栏头部)据此保持透明,**不要**再铺不透明
  /// 底色 —— 那会把玻璃透出的画面整块盖住。
  static bool onGlass(BuildContext context) => _glassScopeOf(context) != null;

  /// 玻璃底色:基色 [tint] 的 85%(清单 3.1)。
  ///
  /// 已在玻璃面上时返回全透明(基色 alpha=0):同一平面上不重复压暗。
  static Color tintOf(BuildContext context, Color tint) => onGlass(context)
      ? tint.withValues(alpha: 0)
      : tint.withValues(alpha: AmbientBlur.glassSurfaceAlpha);

  static _AmbientGlassScope? _glassScopeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<_AmbientGlassScope>();

  @override
  Widget build(BuildContext context) {
    if (onGlass(context)) return child;
    assert(
      sigma <= AmbientBlur.maxSigma,
      '毛玻璃 sigma($sigma)超过 AmbientBlur.maxSigma'
      '(${AmbientBlur.maxSigma})—— 清单 1.3 的硬上限,超限即违规',
    );
    return _AmbientGlassScope(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
        child: child,
      ),
    );
  }
}

/// 标记「本子树已在玻璃面上」,供嵌套的 [AmbientGlass] 与 [AmbientGlass.tintOf]
/// 判定(见其嵌套语义)。
class _AmbientGlassScope extends InheritedWidget {
  const _AmbientGlassScope({required super.child});

  @override
  bool updateShouldNotify(_AmbientGlassScope oldWidget) => false;
}
