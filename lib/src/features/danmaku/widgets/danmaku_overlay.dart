import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:live_parser/live_parser.dart' show DanmakuMessage;

import '../domain/danmaku_settings.dart';
import '../domain/danmaku_style.dart';
import '../domain/danmaku_track.dart';

/// 弹幕叠加层(A2):画在播放器视频之上、自右向左滚动的弹幕 canvas。
///
/// 设计要点:
/// - **速度 ∝ 画布宽度**:每条弹幕的滚动总时长恒定([durationSeconds]),
///   像素速度 = `(canvasWidth + textWidth) / durationSeconds`,因此换分辨率
///   不会改变观感节奏,也不会出现「大屏弹幕飞得慢」的问题。
/// - **零新依赖**:全部基于 `CustomPainter` + `dart:ui` Paragraph 实现。
/// - **数据源解耦**:只吃 `Stream<DanmakuMessage>`,不依赖播放器/provider,
///   便于 VM 单测与后续由 lead 接线。
/// - **资源安全**:`dispose` 取消订阅;未填满/空流/流关闭均安全。
/// - **A3 细粒度设置消费**:[opacity]/[fontSize]/[speedFactor]/[displayAreaRatio]
///   均为可选,默认值与历史行为一致(不透明 / 20px / 8s / 全屏),保证既有用例
///   不红;接线后由 lead 从 [danmakuSettingsProvider] 注入。
class DanmakuOverlay extends StatefulWidget {
  const DanmakuOverlay({
    super.key,
    required this.messages,
    this.enabled = true,
    this.durationSeconds = 8.0,
    this.maxVisible = 200,
    this.topPadding = 8,
    this.opacity = 1.0,
    this.fontSize = DanmakuStyle.fontSize,
    this.speedFactor,
    this.displayAreaRatio = 1.0,
  });

  /// 弹幕消息流。可为 `null`(无数据源时渲染空画布)。
  final Stream<DanmakuMessage>? messages;

  /// 开关:`false` 时停止绘制并暂停滚动(已入队弹幕保留)。
  final bool enabled;

  /// 单条弹幕从右边缘滚至完全离场的总时长(秒)。速度随画布宽度。
  ///
  /// 仅当 [speedFactor] 为 `null` 时生效;[speedFactor] 非空时由
  /// [danmakuDurationForSpeed] 计算出更贴切的时长(覆盖本值)。
  final double durationSeconds;

  /// 同屏最大弹幕数(超出丢弃最旧的,防止长时间挂机内存无界增长)。
  final int maxVisible;

  /// 弹幕区距顶部留白(px),避免遮挡视频顶部信息。
  final double topPadding;

  /// 叠加层整体不透明度 0~1(1 = 不透明)。作用于 painter(全局 alpha)。
  final double opacity;

  /// 弹幕字号(px)。传入 [DanmakuStyle.buildSpan] 控制布局与描边。
  final double fontSize;

  /// 速度档(1~10)。非空时覆盖 [durationSeconds],经 [danmakuDurationForSpeed]
  /// 映射为滚动总时长(速度越大时长越短)。
  final int? speedFactor;

  /// 弹幕可占画布高度比例(取 [DanmakuSettings.kDisplayAreaRatios] 之一),
  /// 用于裁剪可用轨道高度。1.0 = 全屏(与历史行为一致)。
  final double displayAreaRatio;

  /// 速度档 → 滚动总时长(秒)。供 [speedFactor] 与单测共用。
  static double durationForSpeed(int speed) => danmakuDurationForSpeed(speed);

  @override
  State<DanmakuOverlay> createState() => _DanmakuOverlayState();
}

class _DanmakuOverlayState extends State<DanmakuOverlay>
    with SingleTickerProviderStateMixin {
  /// 滚动时钟:单 [Ticker] 驱动整层重绘,而非每条弹幕一个 AnimationController。
  late final Ticker _ticker;

  StreamSubscription<DanmakuMessage>? _subscription;

  /// 已入队(未离场)的弹幕。
  final List<_LiveDanmaku> _items = [];

  /// 单调递增的时钟秒数(仅 `enabled` 时推进),作为轨道分配的绝对时刻。
  double _clock = 0;
  Duration _lastElapsed = Duration.zero;

  DanmakuTrackAllocator? _allocator;

  /// 当前生效的滚动总时长:优先 [speedFactor] 映射,否则 [durationSeconds]。
  double get _duration => widget.speedFactor != null
      ? DanmakuOverlay.durationForSpeed(widget.speedFactor!)
      : widget.durationSeconds;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant DanmakuOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messages != widget.messages) {
      _subscription?.cancel();
      _subscription = null;
      _subscribe();
    }
    if (oldWidget.enabled != widget.enabled) {
      if (widget.enabled) {
        // 恢复时重置计时基准,避免暂停期间累计的 elapsed 造成跳帧。
        _lastElapsed = Duration.zero;
        if (!_ticker.isActive && mounted) _ticker.start();
      } else {
        _ticker.stop();
      }
    }
  }

  void _subscribe() {
    _subscription = widget.messages?.listen(_onMessage, onError: (_) {});
  }

  void _onMessage(DanmakuMessage message) {
    // 空正文跳过(礼物/进场等消息可能无文本)。
    if (message.text.isEmpty) return;
    // 未挂载或 track 未就绪(首帧前)先丢弃,避免用错宽度做分配。
    if (!mounted || _allocator == null) return;
    final size = context.size;
    if (size == null || size.width <= 0) return;

    final span = DanmakuStyle.buildSpan(message, fontSize: widget.fontSize);
    final textWidth = DanmakuStyle.measureWidth(span);
    final widthRatio = (textWidth / size.width).clamp(0.0, 1.0);

    final lane =
        _allocator!.tryAllocate(_clock, widthRatio) ??
        _allocator!.allocateReusingEarliest(_clock, widthRatio);

    setState(() {
      _items.add(
        _LiveDanmaku(
          span: span,
          textWidth: textWidth,
          lane: lane,
          totalSeconds: _duration,
        ),
      );
      if (_items.length > widget.maxVisible) {
        _items.removeRange(0, _items.length - widget.maxVisible);
      }
    });
  }

  void _onTick(Duration elapsed) {
    if (!mounted || !widget.enabled) return;
    final delta = _lastElapsed == Duration.zero
        ? Duration.zero
        : elapsed - _lastElapsed;
    _lastElapsed = elapsed;
    final dt = delta.inMicroseconds / 1e6;
    if (dt <= 0) return;
    _clock += dt;
    for (final item in _items) {
      item.elapsedSeconds += dt;
    }
    // 清理完全离场的弹幕(左端越过画布左边界)。
    _items.removeWhere((item) => item.progress >= 1.0);
    setState(() {});
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        if (width <= 0 || height <= 0) {
          return const SizedBox.expand(key: Key('danmaku-overlay'));
        }
        // 固定 px 留白随系统文字缩放,避免大字号模式下弹幕贴顶。
        final top = MediaQuery.textScalerOf(context).scale(widget.topPadding);
        // 显示区域比例裁剪可用轨道高度:仅顶部 (画布高 - 留白) × 比例 区域可放弹幕。
        final availableHeight = (height - top) * widget.displayAreaRatio;
        final lanes = DanmakuTrackAllocator.lanesForHeight(
          availableHeight,
          DanmakuStyle.lineHeightOf(widget.fontSize),
        );
        final allocator = _allocator;
        if (allocator == null || allocator.laneCount != lanes) {
          _allocator = DanmakuTrackAllocator(
            laneCount: lanes,
            durationSeconds: _duration,
          );
        }
        return IgnorePointer(
          child: RepaintBoundary(
            child: CustomPaint(
              key: const Key('danmaku-overlay'),
              size: Size(width, height),
              painter: _DanmakuPainter(
                items: _items,
                topPadding: top,
                canvasWidth: width,
                enabled: widget.enabled,
                fontSize: widget.fontSize,
                opacity: widget.opacity,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 一条正在飞行的弹幕的运行态。
class _LiveDanmaku {
  _LiveDanmaku({
    required this.span,
    required this.textWidth,
    required this.lane,
    required this.totalSeconds,
  });

  final TextSpan span;
  final double textWidth;
  final int lane;

  /// 滚动总时长(秒),决定像素速度 = (canvasWidth + textWidth)/totalSeconds。
  final double totalSeconds;

  /// 已飞行时间(秒)。
  double elapsedSeconds = 0;

  /// 飞行进度 0~1,1 表示完全离场。
  double get progress => (elapsedSeconds / totalSeconds).clamp(0.0, 1.0);

  /// 当前左边界 x:从 `canvasWidth` 进入,滚到 `-textWidth` 完全离场。
  double left(double canvasWidth) =>
      canvasWidth - progress * (canvasWidth + textWidth);
}

class _DanmakuPainter extends CustomPainter {
  const _DanmakuPainter({
    required this.items,
    required this.topPadding,
    required this.canvasWidth,
    required this.enabled,
    required this.fontSize,
    required this.opacity,
  });

  final List<_LiveDanmaku> items;
  final double topPadding;
  final double canvasWidth;
  final bool enabled;
  final double fontSize;
  final double opacity;

  void _paintAll(Canvas canvas, Size size) {
    canvas.save();
    for (final item in items) {
      final dx = item.left(size.width);
      // 视口裁剪:完全在左/右边界外的弹幕不绘制。
      if (dx > size.width || dx + item.textWidth < 0) continue;
      final dy = topPadding + item.lane * DanmakuStyle.lineHeightOf(fontSize);
      DanmakuStyle.paintRichText(canvas, item.span, offset: Offset(dx, dy));
    }
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (items.isEmpty) return;
    // 不透明度 < 1:用 dstIn 黑色层做全局 alpha(与 Flutter Opacity 同款做法),
    // 避免逐段改色导致描边/填充 alpha 不一致。
    if (opacity >= 1.0) {
      _paintAll(canvas, size);
      return;
    }
    canvas.saveLayer(
      Offset.zero & size,
      Paint()
        ..color = Color.fromARGB((opacity * 255).round(), 0, 0, 0)
        ..blendMode = BlendMode.dstIn,
    );
    _paintAll(canvas, size);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DanmakuPainter oldDelegate) {
    // 每帧 tick 都会 setState,painter 必须重绘;items 为同一可变列表,
    // 用长度 + enabled + 宽度变化判断不可靠,直接返回 true。
    return oldDelegate.items.length != items.length ||
        oldDelegate.enabled != enabled ||
        oldDelegate.canvasWidth != canvasWidth ||
        oldDelegate.opacity != opacity ||
        oldDelegate.fontSize != fontSize ||
        enabled;
  }
}
