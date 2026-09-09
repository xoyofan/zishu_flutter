/// W4 耗时分析 workflow 测试:进房耗时门槛(中位数策略)+ 切画质二次进房回归。
///
/// 度量口径(driver [openRoomLatency]):回到 `/{site}` 首页 → 点击首个
/// room-card,Stopwatch + runAsync 度量 tap → 首个 `play-quality-*` 锚点出现
/// 的墙钟 ms 与 pump 帧数,并逐次打印 `[latency] {site}: ...` 报告行。
///
/// 阈值策略(稳健,避免 CI 抖动误报):
/// - 每平台先跑 1 次**预热不计分**(暖化首帧图片栈/字体/JIT 等一次性环境噪声),
///   再跑 3 次计分取**中位数**;
/// - 断言中位墙钟 < 1500ms(宽松上限:fixture 阶段的目的是捕获编排劣化而非
///   精确性能;墙钟含环境噪声,单次曾测得 649ms,不适用紧阈值);
/// - 断言中位帧数 ≤ 8(fixture 阶段 frames 稳定为 2-3,是比墙钟更稳定的编排
///   信号,>8 即路由/provider/锚点挂载编排退化)。
///
/// TODO(G1): 接真实解析后同一度量自动变端到端,建议把墙钟阈值收紧到 500ms,
/// 并把 `[latency-summary]` 汇总行纳入门禁输出(W13 收录)。
///
/// 交互回归:切第二个画质 chip 后,3 轮「play-back 返回 → 再进房」计分,断言
/// 二次进房中位数 ≤ 首次进房中位数 + 500ms——语义是防止切房/切画质后
/// player/provider/监听未随路由释放导致的资源泄漏型单调劣化。
///
/// 用例间依赖:同文件用例按声明顺序串行执行(flutter test 默认不乱序),
/// 前置用例把各平台中位数写入 [_firstEntryMedians],交互回归与汇总用例消费;
/// 单独只跑后两者会因缺数据失败,属预期防护。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'platform_workflow.dart';

/// W4 范围内的平台(与批次 2 平台用例保持一致)。
const List<String> _kSites = ['douyu', 'huya', 'bilibili'];

/// 进房中位墙钟宽松上限(G1 接真实解析后建议收紧到 500ms,见文件头)。
const int _kMedianWallClockBudgetMs = 1500;

/// 进房中位帧数上限(known-good 为 2-3)。
const int _kMedianFramesBudget = 8;

/// 二次进房相对首次中位数的劣化预算(环境噪声余量)。
const int _kReentryDegradationBudgetMs = 500;

/// 与 driver 一致的固定 pump 步长。
const Duration _kFrame = Duration(milliseconds: 50);

/// 各平台首次进房中位数(site → median ms)。
final Map<String, int> _firstEntryMedians = {};

/// 3 样本中位数(固定奇数样本,取排序后中位)。
int _medianOf3(List<int> samples) {
  expect(samples.length, 3, reason: '计分策略固定为 3 个样本');
  final sorted = [...samples]..sort();
  return sorted[1];
}

/// 固定次数 pump(本文件自己的计时/恢复窗口使用;driver 内部窗口的溢出排水
/// 由其自行处理,链路断言不含溢出专项)。
Future<void> _pumpFrames(WidgetTester tester, int times) async {
  for (var i = 0; i < times; i++) {
    await tester.pump(_kFrame);
  }
}

void main() {
  // ---- 任务 1+2:三平台首帧进房耗时,预热 1 次不计分 + 计分 3 次取中位数 ----
  for (final site in _kSites) {
    testWidgets(
      '$site 首帧进房耗时:预热 1 次不计分,计分 3 次取中位数',
      (tester) async {
        await pumpPlatformApp(tester, '/$site');
        // ignore: avoid_print
        print('[latency-plan] $site: 1 warmup (not scored) + 3 scored samples');

        // 预热(不计分):driver 照常打印 [latency] 报告行,但不进入样本。
        await openRoomLatency(tester, site);

        final msSamples = <int>[];
        final frameSamples = <int>[];
        for (var i = 0; i < 3; i++) {
          final result = await openRoomLatency(tester, site);
          msSamples.add(result.ms);
          frameSamples.add(result.frames);
        }

        final medianMs = _medianOf3(msSamples);
        final medianFrames = _medianOf3(frameSamples);
        // 先记录后断言:即使阈值失败,汇总行仍能给出数值供人工比对。
        _firstEntryMedians[site] = medianMs;

        // 每平台中位数报告行(供人工比对与 W13 收录)。
        // ignore: avoid_print
        print(
          '[latency-median] $site: median=${medianMs}ms '
          'samples=$msSamples frames=$medianFrames',
        );

        expect(
          medianMs,
          lessThan(_kMedianWallClockBudgetMs),
          reason: '$site 进房中位墙钟 ${medianMs}ms 应 < '
              '$_kMedianWallClockBudgetMs ms,samples=$msSamples——疑似编排劣化或'
              '环境异常(G1 接真实解析后阈值收紧到 500ms)',
        );
        expect(
          medianFrames,
          lessThanOrEqualTo(_kMedianFramesBudget),
          reason: '$site 进房中位帧数 $medianFrames 应 ≤ $_kMedianFramesBudget,'
              'samples=$frameSamples——进房编排(路由/provider/锚点挂载)退化',
        );
      },
      timeout: const Timeout(Duration(minutes: 5)),
    );
  }

  // ---- 任务 4:交互回归,切画质后二次进房不劣化(防切房资源泄漏) ----
  // 只在 douyu 上执行:fixture payload 与 site 无关(fixtureRoomPayload 忽略
  // site,四档画质/线路形状全平台一致),douyu 作为代表平台即可覆盖该语义,
  // 同时控制用例时长;G1 接真实解析后可按平台展开。
  testWidgets(
    'douyu 切画质后二次进房不劣化(防切房资源泄漏)',
    (tester) async {
      final firstMedian = _firstEntryMedians['douyu'];
      expect(
        firstMedian,
        isNotNull,
        reason: '依赖首个用例记录的 douyu 首次进房中位数',
      );

      await pumpPlatformApp(tester, '/douyu');

      // 进入播放页(入口跑一次完整 openRoomLatency,不计分),切第二个画质 chip。
      await openRoomLatency(tester, 'douyu');
      await _pumpFrames(tester, 2); // payload 完整落地,画质 chips 全部挂载。
      final qualities = anchorKeysWithPrefix(tester, 'play-quality-');
      expect(
        qualities.length,
        greaterThanOrEqualTo(2),
        reason: 'fixture 房间应至少有 2 个画质档位',
      );
      final secondQuality = find.byKey(Key(qualities[1]));
      await tester.tap(secondQuality);
      await _pumpFrames(tester, 2);
      expect(
        tester.widget<ChoiceChip>(secondQuality).selected,
        isTrue,
        reason: '切画质后第二个 chip 应进入选中态',
      );

      // 3 轮「play-back 返回 → 再进房」计分:计时窗口与首次口径一致
      // (tap 房卡 → play-quality 锚点出现),play-back 与首页恢复不计入。
      final msSamples = <int>[];
      final frameSamples = <int>[];
      for (var i = 1; i <= 3; i++) {
        final result = await _reentryLatency(tester, 'douyu', run: i);
        msSamples.add(result.ms);
        frameSamples.add(result.frames);
      }
      final medianMs = _medianOf3(msSamples);
      final medianFrames = _medianOf3(frameSamples);
      final budget = firstMedian! + _kReentryDegradationBudgetMs;

      // ignore: avoid_print
      print(
        '[latency-reentry] douyu: first=${firstMedian}ms '
        'reentry-median=${medianMs}ms samples=$msSamples '
        'frames=$medianFrames budget=$budget',
      );

      // 语义:切房/切画质后反复进出房间,若 player/provider/监听未随路由释放,
      // 二次进房会呈资源泄漏型单调劣化。fixture 阶段门槛取「不劣化」:
      // 中位墙钟 ≤ 首次中位数 + 500ms,中位帧数同样 ≤ 8。
      expect(
        medianMs,
        lessThanOrEqualTo(budget),
        reason: '二次进房中位墙钟 ${medianMs}ms 应 ≤ 首次中位数 ${firstMedian}ms + '
              '${_kReentryDegradationBudgetMs}ms,samples=$msSamples——'
              '疑似切房资源泄漏(切画质后未释放)',
      );
      expect(
        medianFrames,
        lessThanOrEqualTo(_kMedianFramesBudget),
        reason: '二次进房中位帧数 $medianFrames 应 ≤ $_kMedianFramesBudget,'
            'samples=$frameSamples——切房后编排退化',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  // ---- 任务 3:汇总报告,一行输出三平台中位数(W13 门禁录入格式) ----
  test('汇总报告:三平台中位数一行输出(供人工比对与 W13 收录)', () {
    expect(
      _firstEntryMedians.keys,
      containsAll(_kSites),
      reason: '汇总前三平台进房用例应已全部完成(同文件按声明顺序串行执行)',
    );
    final line = _kSites
        .map((site) => '$site=${_firstEntryMedians[site]}ms')
        .join(' ');
    // ignore: avoid_print
    print('[latency-summary] $line (median of 3)');
  });
}

/// 简化版进房计时:点 play-back 出栈回首页(不计入计时),再点首个 room-card,
/// Stopwatch + runAsync 度量 tap → play-quality-* 锚点出现。口径与
/// [openRoomLatency] 一致,保证与首次进房样本可比。
Future<({int ms, int frames})> _reentryLatency(
  WidgetTester tester,
  String site, {
  required int run,
}) async {
  await tester.tap(findAnchor('play-back'));
  await _pumpFrames(tester, 2);
  expect(
    findAnchor('play-back'),
    findsNothing,
    reason: 'play-back 应出栈返回首页',
  );
  final cards = anchorKeysWithPrefix(tester, 'room-card-');
  expect(cards, isNotEmpty, reason: 'play-back 返回后应仍有 room-card-* 锚点可点');

  final stopwatch = Stopwatch()..start();
  var frames = 0;
  await tester.runAsync(() async {
    await tester.tap(find.byKey(Key(cards.first)));
    // 逐帧 pump 直到画质锚点挂载(与 driver 同口径)。
    while (countAnchorsByPrefix(tester, 'play-quality-') == 0) {
      await tester.pump(_kFrame);
      frames++;
      if (frames > 300) {
        stopwatch.stop();
        fail('_reentryLatency($site): 300 帧内未出现 play-quality-* 锚点');
      }
    }
  });
  stopwatch.stop();

  final ms = stopwatch.elapsedMilliseconds;
  // ignore: avoid_print
  print('[latency-reentry] $site run$run: ${ms}ms / $frames frames');
  return (ms: ms, frames: frames);
}
