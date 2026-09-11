import 'dart:math' as math;

/// 弹幕轨道(lane)分配算法。
///
/// ## 核心不变式(一句话)
/// **每个 lane 只维护「尾弹幕完全离开右边缘的时刻」这个标量**;新弹幕到达时
/// 只需与各 lane 的该标量比较一次即可判定能否放入(O(1) 判定),因此入队
/// 总复杂度为 O(lane 数),而非两两比对历史弹幕的 O(n²)。
///
/// ## 为什么是「离开右边缘」而不是「离开右边缘」的变形
/// 弹幕从右向左滚动,后续弹幕要从右边缘进入。若前一条弹幕的**左端**还没
/// 离开右边缘,新弹幕就会在入场处与其重叠。因此判定条件是:
///   `now >= lane.tailLeftExitTime`(前一条的左端已越出右边缘)
/// 这等价于 `tailRightExitTime = tailLeftExitTime + 自身滚动总时长` 之外,
/// 我们额外留一点安全间隙([gapSeconds])避免视觉贴脸。
class DanmakuTrackAllocator {
  /// 构造轨道分配器。
  ///
  /// - [laneCount]:轨道条数(应 > 0,否则内部按 1 处理);
  /// - [gapSeconds]:同 lane 前后两条弹幕之间的最小安全间隙(秒);
  /// - [durationSeconds]:单条弹幕从右边缘滚到完全离场的总时长(秒)。
  ///   速度 ∝ 画布宽度由调用方保证(见 [DanmakuOverlay]),本算法只关心
  ///   「时刻」,与像素无关。
  DanmakuTrackAllocator({
    required this.laneCount,
    this.gapSeconds = 0.6,
    this.durationSeconds = 8.0,
  }) : assert(laneCount > 0, '至少需要 1 条轨道'),
       _tailLeftExit = List<double>.filled(laneCount, double.negativeInfinity);

  /// 轨道条数。
  final int laneCount;

  /// 同 lane 相邻弹幕的最小时间间隙(秒)。
  final double gapSeconds;

  /// 单条弹幕滚动总时长(秒),用于把「入场时刻 + 自身宽度占比」换算成
  /// 尾部弹幕的左端离场时刻。
  final double durationSeconds;

  /// 每条 lane 的尾弹幕「左端越过右边缘」的绝对时刻(秒)。
  ///
  /// 初始为 `-infinity`(空 lane,任何弹幕可入)。
  final List<double> _tailLeftExit;

  /// 尝试为一条宽度占比为 [widthRatio](0~1,弹幕宽度 / 画布宽度)的弹幕
  /// 在 [nowSeconds] 时刻分配轨道。
  ///
  /// 返回 lane 下标;若无可用 lane 返回 `null`(由调用方按既定策略处理)。
  ///
  /// 判定为 O(1)/lane:仅比较 `nowSeconds` 与该 lane 的尾端离场时刻。
  int? tryAllocate(double nowSeconds, double widthRatio) {
    for (var lane = 0; lane < laneCount; lane++) {
      if (_canFit(lane, nowSeconds, widthRatio)) {
        _occupy(lane, nowSeconds, widthRatio);
        return lane;
      }
    }
    return null;
  }

  /// 兜底分配:所有 lane 都满时,选择**最早释放**的 lane 复用。
  ///
  /// ## 策略选择(二选一,此处选「复用最早释放的 lane」)
  /// 备选是「直接丢弃该弹幕」。这里选复用,原因:
  /// 1. 直播弹幕是实时流,丢弃会让观众觉得「弹幕漏了」,复用只是短暂重叠;
  /// 2. 复用造成的重叠仅发生在最拥挤时,视觉代价低于丢消息的语义代价;
  /// 3. 选择「最早释放」而非「轮转」,可最大化复用后被再次释放的时间余量,
  ///    减少连续复用同一 lane 导致的叠字。
  ///
  /// 返回被复用/新占用的 lane 下标。
  int allocateReusingEarliest(double nowSeconds, double widthRatio) {
    var bestLane = 0;
    var bestRelease = double.infinity;
    for (var lane = 0; lane < laneCount; lane++) {
      // 空闲 lane 优先(离场时刻越小越早空闲;空 lane 为 -infinity)。
      if (_tailLeftExit[lane] < bestRelease) {
        bestRelease = _tailLeftExit[lane];
        bestLane = lane;
      }
    }
    _occupy(bestLane, nowSeconds, widthRatio);
    return bestLane;
  }

  /// lane 是否可容纳宽度占比 [widthRatio] 的新弹幕。
  bool _canFit(int lane, double nowSeconds, double widthRatio) {
    final tailExit = _tailLeftExit[lane];
    if (tailExit == double.negativeInfinity) return true;
    // 安全间隙按「弹幕宽度占比 × 时长」折算,宽弹幕需要更大间距,
    // 避免窄弹幕紧跟宽弹幕后视觉上过于拥挤。
    final gap = gapSeconds + widthRatio * durationSeconds * 0.25;
    return nowSeconds >= tailExit + gap;
  }

  /// 占用 lane:记录新弹幕左端离场时刻。
  ///
  /// 新弹幕自身从右边缘入场,其**左端**要 `durationSeconds × (1 + widthRatio)`
  /// 时刻后才越过右边缘(先滚过自身宽度占比,再滚过画布宽度)。
  void _occupy(int lane, double nowSeconds, double widthRatio) {
    _tailLeftExit[lane] = nowSeconds + durationSeconds * (1 + widthRatio);
  }

  /// 指定 lane 当前是否空闲([nowSeconds] 时刻可立即放入)。
  bool isLaneFree(int lane, double nowSeconds) {
    final tailExit = _tailLeftExit[lane];
    return tailExit == double.negativeInfinity || nowSeconds >= tailExit;
  }

  /// 当前空闲 lane 数(诊断/测试用)。
  int freeLaneCount(double nowSeconds) {
    var count = 0;
    for (var lane = 0; lane < laneCount; lane++) {
      if (isLaneFree(lane, nowSeconds)) count++;
    }
    return count;
  }

  /// 按画布高度估算轨道条数:每条轨道占 [lineHeight] px,至少 1 条。
  static int lanesForHeight(double height, double lineHeight, {int max = 12}) {
    if (lineHeight <= 0) return 1;
    return math.max(1, math.min(max, (height / lineHeight).floor()));
  }
}
