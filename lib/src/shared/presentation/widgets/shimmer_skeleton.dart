/// 骨架屏(skeleton / shimmer)共享组件 —— 氛围级 UI 清单 §3.6。
///
/// 三处加载态(房间网格 footer、搜索结果、关注刷新)共用本文件,不得各自
/// 手写一份扫光:
/// - [ShimmerSkeleton] 是**扫光容器**:给一段"骨架形状子树"整体加一条横向
///   扫过的线性高光,循环周期取 `AmbientMotion.shimmer`(1.4s,清单 1.1);
/// - [SkeletonBox] 是**形状原语**:单块占位矩形(底色取既有 `surfaceSoft`);
/// - [SkeletonTile] / [SkeletonRow] 是**成型骨架**:分别对齐房间卡
///   (`RoomCard`:16:9 封面 + 两行文字条)与搜索结果行(`SearchResultTile`:
///   方头像块 + 两行文字条)。
///
/// 纪律:
/// - 颜色只用既有 surface 档位([ZishuTokens.surfaceSoft] 为底、
///   [ZishuTokens.surface] 为扫光高光),**不发明新色**;
/// - 时长/降级一律经 `AmbientMotion.of(context)`,widget 里不散写裸时长,
///   也不自行判 `MediaQuery.disableAnimationsOf`;
/// - `reduce_motion`([AmbientMotionSpec.reduced])时**不扫光**:子树直出静态
///   占位矩形(清单 3.6 明文要求)。
library;

import 'package:flutter/material.dart';

import '../design_tokens.dart';
import '../zishu_tokens.dart';

/// 单块骨架占位:圆角矩形,底色取 [ZishuTokens.surfaceSoft]。
///
/// 单纯形状,不含扫光 —— 扫光由外层 [ShimmerSkeleton] 统一施加;单独使用
/// (不套 [ShimmerSkeleton])时就是一块静态占位色块。
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({
    super.key,
    this.width,
    this.height,
    this.widthFactor,
    this.radius,
  });

  /// 固定宽;与 [widthFactor] 二选一(同时给时以 [width] 为准)。
  final double? width;

  /// 固定高;为空时按父约束撑开(如 `AspectRatio` 封面块)。
  final double? height;

  /// 占比宽(0–1],左对齐。用于文字条这类"占一整行的若干成"的占位。
  final double? widthFactor;

  /// 圆角,缺省 [AppRadius.allSm]。
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final box = Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: radius ?? AppRadius.allSm,
      ),
    );
    if (widthFactor == null) return box;
    return FractionallySizedBox(
      alignment: Alignment.centerLeft,
      widthFactor: widthFactor,
      child: box,
    );
  }
}

/// 扫光容器:把 [child](骨架形状子树)整体套上一条横向扫过的线性高光。
///
/// - 完整档:高光按 [AmbientMotion.shimmer](1.4s)循环,每周期从左穿到右,
///   曲线复用 `AppMotion.curve`;
/// - `reduce_motion` 档([AmbientMotionSpec.reduced]):**不建动画、不加扫光**,
///   直接渲染子树(即静态占位矩形)。
///
/// 实现用 `ShaderMask(srcIn)`:子树的不透明区域被渐变着色,透明间隙(卡片
/// 底、行间距)保持透出 —— 因此子树里的 [SkeletonBox] 自带底色只是为了
/// "静态档"直出,扫光档下底色由渐变的本色端提供。
class ShimmerSkeleton extends StatefulWidget {
  const ShimmerSkeleton({super.key, required this.child});

  /// 骨架形状子树(通常由 [SkeletonBox] 拼成)。
  final Widget child;

  @override
  State<ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final motion = AmbientMotion.of(context);
    if (motion.reduced) {
      // 静态档:循环周期为零,建动画无意义 —— 停下并直出静态占位。
      if (_controller.isAnimating) _controller.stop();
      return;
    }
    _controller.duration = motion.shimmer;
    if (!_controller.isAnimating) _controller.repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 静态档(reduce_motion):不加扫光,子树即静态占位矩形。
    if (AmbientMotion.of(context).reduced) return widget.child;
    final base = context.tokens.surfaceSoft;
    final highlight = context.tokens.surface;
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          // 本色两端 = 骨架底(surfaceSoft),中段高光 = surface:两个既有
          // surface 档位之差就是扫光亮度差,不引入新色。
          colors: [base, highlight, base],
          // 光带宽度占形状宽的 20%(0.4→0.6):太宽会读成"整体渐晕"而不是
          // 一条扫过的光带,且行宽随窗口变化(行宽大时光带也成比例变宽)。
          stops: const [0.4, 0.5, 0.6],
          transform: _SlidingGradientTransform(
            slidePercent: _controller.value * 2 - 1,
          ),
        ).createShader(bounds),
        child: child,
      ),
    );
  }
}

/// 把扫光渐变整体横向平移 [slidePercent] 段宽(-1 = 完全在左外,1 = 完全在右外)。
class _SlidingGradientTransform extends GradientTransform {
  const _SlidingGradientTransform({required this.slidePercent});

  final double slidePercent;

  @override
  Matrix4? transform(Rect bounds, {TextDirection? textDirection}) =>
      Matrix4.translationValues(bounds.width * slidePercent, 0, 0);
}

/// 房间卡形状的骨架:16:9 封面块 + 两行文字条。
///
/// 形状与房间卡(`features/browse/widgets/room_card.dart`)同口径 ——
/// 卡面底色/圆角取 `surface` + [AppRadius.allMd],封面 16:9,元信息区
/// padding 8/6/8/8、标题条 ≈ 19(14px×1.35)、副行条 17,故骨架与真实卡片
/// 在网格里等高、等比例。
class SkeletonTile extends StatelessWidget {
  const SkeletonTile({super.key});

  /// 文字条高度:标题行 14px × 1.35 ≈ 19,RoomCard._RoomCardMeta 同口径。
  static const double _titleBarHeight = 19;

  /// 副行条高度:RoomCard._metaLineHeight(17)。
  static const double _metaBarHeight = 17;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
      ),
      child: ClipRRect(
        borderRadius: AppRadius.allMd,
        child: ShimmerSkeleton(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const AspectRatio(
                aspectRatio: 16 / 9,
                child: SkeletonBox(radius: BorderRadius.zero),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  6,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: const [
                    SkeletonBox(
                      widthFactor: 0.7,
                      height: _titleBarHeight,
                    ),
                    SizedBox(height: AppSpacing.xs),
                    SkeletonBox(
                      widthFactor: 0.45,
                      height: _metaBarHeight,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 结果行形状的骨架:方形头像块 + 两行文字条(对齐 `SearchResultTile`)。
///
/// 行高/padding/底部分隔线与搜索结果行一致,故骨架行与真实结果行等高,
/// 结果落地时列表不发生跳动。
class SkeletonRow extends StatelessWidget {
  const SkeletonRow({super.key});

  /// 头像块边长:对齐 `SearchResultTile._Avatar`(40)。
  static const double _leading = 40;

  /// 标题条/副行条高度(14px×1.35 ≈ 19、12px×1.35 ≈ 16)。
  static const double _titleBarHeight = 19;
  static const double _metaBarHeight = 16;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: ShimmerSkeleton(
        child: Row(
          children: [
            const SkeletonBox(width: _leading, height: _leading),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: const [
                  SkeletonBox(widthFactor: 0.5, height: _titleBarHeight),
                  SizedBox(height: AppSpacing.sm),
                  SkeletonBox(widthFactor: 0.75, height: _metaBarHeight),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
