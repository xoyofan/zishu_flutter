/// 解析耗时基准页(对齐参考实现 `apps/web/src/views/TimeView.vue` + `api/time.ts`)。
///
/// 参考实现经服务端 `/api/time` 跑基准(冷解析 vs 缓存命中)并返回
/// `{cache, benchmark.runs[]}`;本仓客户端直接 import 解析核心,等价能力由本页在
/// **客户端墙钟**上量:同一个数据源端口 [roomSourceProvider] 上依次跑
/// 「冷解析」(实现 [RoomRecoverer] 时走 `recoverRoom` 绕开 60s 短缓存)与
/// 「缓存命中」(紧接着再解析一次),两行结果与 web 的 runs 表同构
/// (场景 / 墙钟 / 关键字段)。
///
/// 与 web 的有意差异(见本轨交接文件):
/// - 无服务端,故没有 meta/tier/payload 三段内部耗时,只有墙钟与关键字段;
/// - 无「刷新缓存」服务端动作,改为「重新解析(绕缓存)」按需再取一次。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart' show RoomPayload;

import '../../../shared/application/browse_source.dart';
import '../../../shared/application/providers.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 一次基准采样:场景 + 墙钟 + 关键字段(web runs 表的一行)。
class BenchSample {
  const BenchSample({
    required this.label,
    required this.desc,
    required this.wallMs,
    required this.qualityCount,
    required this.lineCount,
    required this.stateLabel,
    required this.detail,
  });

  /// 场景名(冷解析 / 缓存命中 / 重新解析(绕缓存))。
  final String label;

  /// 场景说明(web 的 `row.desc`)。
  final String desc;

  /// 客户端墙钟耗时(毫秒)。
  final int wallMs;

  /// 解析出的画质档数。
  final int qualityCount;

  /// 解析出的线路总数(各档求和)。
  final int lineCount;

  /// 房间状态文案(在播/未开播/不存在)。
  final String stateLabel;

  /// 备注:主播名,或错误摘要(web 的 `row.error || row.anchor`)。
  final String detail;
}

/// 解析耗时基准页。
class ParseBenchmarkView extends ConsumerStatefulWidget {
  const ParseBenchmarkView({super.key});

  @override
  ConsumerState<ParseBenchmarkView> createState() => _ParseBenchmarkViewState();
}

class _ParseBenchmarkViewState extends ConsumerState<ParseBenchmarkView> {
  /// 页宽上限,对齐参考实现 `.time-page` 的 max-width 960px。
  static const double _contentMaxWidth = 960;

  /// 采样表最多保留的行数(web 展示整轮 runs,这里只留最近几轮防止无界增长)。
  static const int _maxSamples = 6;

  /// 默认房间号:与 web 表单占位同源(斗鱼样例房)。
  static const String _defaultRoom = '63136';

  late final TextEditingController _roomController = TextEditingController(
    text: _defaultRoom,
  );
  late final TextEditingController _qualityController = TextEditingController();

  /// 选中平台;null 表示尚未初始化(首次 build 取第一个可浏览平台)。
  String? _site;

  final List<BenchSample> _samples = [];
  String _error = '';
  bool _running = false;

  @override
  void initState() {
    super.initState();
    _site = _firstBrowseSite();
  }

  @override
  void dispose() {
    _roomController.dispose();
    _qualityController.dispose();
    super.dispose();
  }

  /// 可基准的平台清单:取导航平台里支持栏目浏览的(排除 `all` 聚合站)。
  List<PlatformBrand> get _sites => [
    for (final brand in PlatformBrandCatalog.navigationPlatforms)
      if (brand.id != 'all' && brand.browseSupported) brand,
  ];

  String _firstBrowseSite() {
    final sites = _sites;
    return sites.isEmpty ? 'douyu' : sites.first.id;
  }

  String get _quality => _qualityController.text.trim();

  /// 运行基准:冷解析 + 缓存命中两行(web 的默认 runs)。
  Future<void> _runBenchmark() async {
    await _run(
      (source) async => [
        await _measure(
          source,
          label: '冷解析',
          desc: '首次解析;数据源支持恢复能力时绕开 60s 短缓存',
          preferRecover: true,
        ),
        await _measure(
          source,
          label: '缓存命中',
          desc: '紧接着再解析一次,命中数据源内短缓存',
          preferRecover: false,
        ),
      ],
    );
  }

  /// 重新解析(绕缓存):只跑一行 —— 对齐 web 的「刷新缓存」动作在客户端的等价物。
  Future<void> _runRecover() async {
    await _run(
      (source) async => [
        await _measure(
          source,
          label: '重新解析(绕缓存)',
          desc: '显式绕开短缓存重新取一份(签名平台地址过期后的恢复路径)',
          preferRecover: true,
        ),
      ],
    );
  }

  /// 共用执行壳:校验输入 → 清态 → 跑采样 → 落地结果或错误行。
  Future<void> _run(
    Future<List<BenchSample>> Function(RoomSource source) body,
  ) async {
    if (_running) return;
    final site = _site;
    final room = _roomController.text.trim();
    if (site == null || site.isEmpty) {
      setState(() => _error = '请选择平台');
      return;
    }
    if (room.isEmpty) {
      setState(() => _error = '请填写房间号');
      return;
    }

    setState(() {
      _running = true;
      _error = '';
      _samples.clear();
    });
    try {
      final samples = await body(ref.read(roomSourceProvider));
      if (!mounted) return;
      setState(() {
        _samples.addAll(samples);
        // 多跑几轮时只保留最近几行(与 web 一轮 runs 同量级,不做无界增长)。
        if (_samples.length > _maxSamples) {
          _samples.removeRange(0, _samples.length - _maxSamples);
        }
      });
    } catch (error) {
      // 未注册平台 / 上游报错 / 网络异常:给可见错误行,不白屏。
      if (!mounted) return;
      setState(() => _error = '解析失败:$error');
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  /// 单次采样:计时 + 关键字段归一。preferRecover 为真且数据源具备恢复能力时
  /// 走 [RoomRecoverer.recoverRoom](绕短缓存),否则走 [RoomSource.resolveRoom]。
  Future<BenchSample> _measure(
    RoomSource source, {
    required String label,
    required String desc,
    required bool preferRecover,
  }) async {
    final site = _site!;
    final room = _roomController.text.trim();
    final stopwatch = Stopwatch()..start();
    late final RoomPayload payload;
    if (preferRecover && source is RoomRecoverer) {
      payload = await source.recoverRoom(
        site: site,
        roomIdOrUrl: room,
        preferredQuality: _quality.isEmpty ? null : _quality,
      );
    } else {
      payload = await source.resolveRoom(
        site: site,
        roomIdOrUrl: room,
        preferredQuality: _quality.isEmpty ? null : _quality,
      );
    }
    stopwatch.stop();
    return BenchSample(
      label: label,
      desc: desc,
      wallMs: stopwatch.elapsedMilliseconds,
      qualityCount: payload.streams.length,
      lineCount: payload.streams.fold(0, (sum, q) => sum + q.lines.length),
      stateLabel: switch (payload.roomState.name) {
        'live' => '在播',
        'offline' => '未开播',
        _ => '不存在',
      },
      detail: payload.anchorName.trim().isEmpty
          ? (payload.error ?? '—')
          : payload.anchorName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _contentMaxWidth),
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              '解析耗时',
              style: context.textTitle.copyWith(
                fontSize: AppFontSize.display,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '客户端墙钟计时:冷解析 vs 缓存命中,数据源为设置里的当前解析源。',
              style: context.textSecondary,
            ),
            const SizedBox(height: AppSpacing.lg),
            _panel(
              tokens,
              key: const Key('bench-form'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      _field(
                        context,
                        label: '平台',
                        width: 160,
                        child: DropdownButton<String>(
                          key: const Key('bench-site'),
                          value: _site,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          dropdownColor: tokens.surfaceRaised,
                          style: context.textBody,
                          items: [
                            for (final brand in _sites)
                              DropdownMenuItem(
                                value: brand.id,
                                child: Text(brand.name),
                              ),
                          ],
                          onChanged: _running
                              ? null
                              : (value) => setState(() => _site = value),
                        ),
                      ),
                      _field(
                        context,
                        label: '房间号',
                        width: 160,
                        child: TextField(
                          key: const Key('bench-room'),
                          controller: _roomController,
                          enabled: !_running,
                          style: context.textBody,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: _defaultRoom,
                          ),
                        ),
                      ),
                      _field(
                        context,
                        label: '清晰度(可选)',
                        width: 160,
                        child: TextField(
                          key: const Key('bench-quality'),
                          controller: _qualityController,
                          enabled: !_running,
                          style: context.textBody,
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '原画',
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Wrap(
                    spacing: AppSpacing.sm,
                    children: [
                      FilledButton(
                        key: const Key('bench-run'),
                        onPressed: _running ? null : _runBenchmark,
                        style: FilledButton.styleFrom(
                          backgroundColor: tokens.accent,
                          foregroundColor: tokens.background,
                          minimumSize: const Size(0, 32),
                        ),
                        child: Text(
                          _running ? '测试中…' : '运行基准',
                          style: const TextStyle(fontSize: AppFontSize.bodySecondary),
                        ),
                      ),
                      OutlinedButton(
                        key: const Key('bench-recover'),
                        onPressed: _running ? null : _runRecover,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: tokens.textPrimary,
                          side: BorderSide(color: tokens.border),
                          minimumSize: const Size(0, 32),
                        ),
                        child: const Text(
                          '重新解析(绕缓存)',
                          style: TextStyle(fontSize: AppFontSize.bodySecondary),
                        ),
                      ),
                    ],
                  ),
                  if (_error.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.md),
                    Row(
                      key: const Key('bench-error'),
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 15,
                          color: tokens.error,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            _error,
                            style: context.textSecondary.copyWith(
                              color: tokens.error,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _panel(
              tokens,
              key: const Key('bench-result'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '基准结果',
                    style: context.textBody.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  if (_samples.isEmpty)
                    Text('尚未运行:填平台与房间号后点「运行基准」。', style: context.textSecondary)
                  else ...[
                    _headerRow(context, tokens),
                    for (final sample in _samples)
                      _sampleRow(context, tokens, sample),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            _panel(
              tokens,
              key: const Key('bench-source'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '数据源',
                    style: context.textBody.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '当前解析源由 `ZISHU_REAL_PARSER` 决定:关闭时是样例数据(fixture,'
                    '无网络、无缓存),开启时是真实解析(签名平台地址带时效,'
                    '解析包内有 60s 短缓存)。',
                    style: context.textSecondary,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    '与 web 的差异:web 经服务端 `/api/time` 取 meta/tier/payload 三段'
                    '内部耗时与缓存条目数,本页只给客户端墙钟与关键字段。',
                    style: context.textCaption,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 表单字段容器:小标题 + 控件。
  Widget _field(
    BuildContext context, {
    required String label,
    required double width,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.textCaption),
          const SizedBox(height: AppSpacing.xs),
          child,
        ],
      ),
    );
  }

  /// 面板容器:统一 surface 底 + 描边 + 内边距。
  Widget _panel(ZishuTokens tokens, {required Key key, required Widget child}) {
    return Container(
      key: key,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surface,
        borderRadius: AppRadius.allMd,
        border: Border.all(color: tokens.border),
      ),
      child: child,
    );
  }

  Widget _headerRow(BuildContext context, ZishuTokens tokens) {
    final style = context.textCaption.copyWith(fontWeight: FontWeight.w700);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        children: [
          Expanded(flex: 3, child: Text('场景', style: style)),
          Expanded(flex: 2, child: Text('墙钟', style: style)),
          Expanded(child: Text('画质', style: style)),
          Expanded(child: Text('线路', style: style)),
          Expanded(child: Text('状态', style: style)),
          Expanded(flex: 2, child: Text('备注', style: style)),
        ],
      ),
    );
  }

  Widget _sampleRow(
    BuildContext context,
    ZishuTokens tokens,
    BenchSample sample,
  ) {
    final cell = context.textSecondary;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sample.label,
                  style: context.textBody.copyWith(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(sample.desc, style: context.textCaption),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${sample.wallMs}ms',
              style: context.textBody.copyWith(color: tokens.accent),
            ),
          ),
          Expanded(child: Text('${sample.qualityCount}', style: cell)),
          Expanded(child: Text('${sample.lineCount}', style: cell)),
          Expanded(child: Text(sample.stateLabel, style: cell)),
          Expanded(flex: 2, child: Text(sample.detail, style: cell)),
        ],
      ),
    );
  }
}
