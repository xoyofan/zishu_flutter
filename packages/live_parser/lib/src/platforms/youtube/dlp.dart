/// YouTube yt-dlp 子进程解析路线(dart:io Process,纯 Dart)。
///
/// 背景与 SFVideoLive 一致:数据中心出口 IP 下 Google 对媒体分片强制 PO
/// Token 校验(页面/主清单/变体 200、分片 403,带登录 cookie 亦然)。yt-dlp
/// 2026.03+ 通过 EJS + Deno 完成 BotGuard 后签出的 HLS 地址分片可正常下载,
/// 因此优先走 dlp;不可用时回退页内抓取链路。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';

/// yt-dlp 提取的一档直播。
class YoutubeDlpTier {
  const YoutubeDlpTier({
    required this.label,
    required this.url,
    required this.height,
    required this.fps,
  });

  final String label;
  final String url;
  final int height;
  final int fps;
}

/// yt-dlp 提取结果。
class YoutubeDlpExtract {
  const YoutubeDlpExtract({
    required this.tiers,
    this.followers = 0,
    this.liveStartAtSec = 0,
  });

  final List<YoutubeDlpTier> tiers;
  final int followers;
  final int liveStartAtSec;
}

/// dlp 提取函数(测试可注入)。
typedef YoutubeDlpExtractor = Future<YoutubeDlpExtract?> Function(
  String videoId,
);

/// dlp 可用性检查(测试可注入)。
typedef YoutubeDlpAvailability = Future<bool> Function();

({bool ok, String bin})? _availabilityCache;
DateTime? _availabilityAt;
const Duration _availabilityTtl = Duration(minutes: 10);
const Duration _dlpTimeout = Duration(seconds: 60);

/// 定位 yt-dlp 可执行文件(Windows 下用 where 拿完整路径)。
Future<String> resolveYoutubeDlpBin() async {
  final fromEnv = Platform.environment['YOUTUBE_DLP_PATH']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
  try {
    final result = await Process.run(
      'where',
      ['yt-dlp'],
    ).timeout(const Duration(seconds: 10));
    if (result.exitCode == 0) {
      for (final line in '${result.stdout}'.split(RegExp(r'\r?\n'))) {
        final candidate = line.trim();
        if (candidate.isNotEmpty) return candidate;
      }
    }
  } on Object {
    // where 不可用时回落默认名。
  }
  return 'yt-dlp';
}

/// Deno 可执行文件探测(yt-dlp 的 EJS 需要它完成 BotGuard 挑战)。
String? denoCandidate() {
  final fromEnv = Platform.environment['DENO_PATH']?.trim();
  if (fromEnv != null && fromEnv.isNotEmpty && File(fromEnv).existsSync()) {
    return fromEnv;
  }
  final localAppData = Platform.environment['LOCALAPPDATA'];
  if (localAppData != null && localAppData.isNotEmpty) {
    final winget = File('$localAppData\\Microsoft\\WinGet\\Links\\deno.exe');
    if (winget.existsSync()) return winget.path;
  }
  return null;
}

/// yt-dlp 是否可用(结果缓存 10 分钟)。
Future<bool> isYoutubeDlpAvailable() async {
  final cached = _availabilityCache;
  final at = _availabilityAt;
  if (cached != null &&
      at != null &&
      DateTime.now().difference(at) < _availabilityTtl) {
    return cached.ok;
  }
  final bin = await resolveYoutubeDlpBin();
  var ok = false;
  try {
    final result = await Process.run(
      bin,
      const ['--version'],
    ).timeout(const Duration(seconds: 10));
    ok = result.exitCode == 0;
  } on Object {
    ok = false;
  }
  _availabilityCache = (ok: ok, bin: bin);
  _availabilityAt = DateTime.now();
  return ok;
}

/// 测试注入口:清空可用性缓存。
void resetYoutubeDlpAvailability() {
  _availabilityCache = null;
  _availabilityAt = null;
}

/// 调用 `yt-dlp -J` 提取全部 HLS 档位;失败/超时返回 null。
///
/// 结果缓存由调用方(YoutubeRoomResolver)按实例管理,避免跨解析器实例
/// 共享导致「冷解析」失真。[argsOverride] 供测试注入。
Future<YoutubeDlpExtract?> extractYoutubeViaDlp(
  String videoId, {
  List<String>? argsOverride,
}) async {
  final bin = _availabilityCache?.ok == true
      ? _availabilityCache!.bin
      : await resolveYoutubeDlpBin();
  final args = <String>[
    'https://www.youtube.com/watch?v=$videoId',
    '--no-warnings',
    '--no-playlist',
    '-J',
  ];
  final deno = denoCandidate();
  if (deno != null) {
    // RUNTIME:PATH 以第一个冒号切分,Windows 盘符路径需转正斜杠。
    args.addAll(['--js-runtimes', 'deno:${deno.replaceAll(r'\', '/')}']);
  }
  if (argsOverride != null) args.addAll(argsOverride);

  Process process;
  try {
    process = await Process.start(bin, args);
  } on Object {
    return null;
  }

  final stdoutFuture = process.stdout.transform(utf8.decoder).join();
  final stderrFuture = process.stderr.transform(utf8.decoder).join();
  final timer = Timer(_dlpTimeout, () {
    try {
      process.kill();
    } on Object {
      // 已退出。
    }
  });
  try {
    final stdout = await stdoutFuture;
    await stderrFuture;
    final exitCode = await process.exitCode;
    if (exitCode != 0) return null;
    final decoded = jsonDecode(stdout);
    if (decoded is! Map) return null;
    final meta = Map<String, dynamic>.from(decoded);
    final tiers = parseYoutubeDlpTiers(meta['formats']);
    if (tiers.isEmpty) return null;
    return YoutubeDlpExtract(
      tiers: tiers,
      followers: jsonInt(meta['channel_follower_count']),
      liveStartAtSec: jsonInt(meta['release_timestamp']),
    );
  } on Object {
    return null;
  } finally {
    timer.cancel();
  }
}

/// 把 yt-dlp formats 归一为 HLS 档位(纯函数,便于单测)。
List<YoutubeDlpTier> parseYoutubeDlpTiers(Object? formats) {
  final tiers = <YoutubeDlpTier>[];
  final seenLabels = <String>{};
  for (final raw in jsonListOf(formats)) {
    final format = jsonMapOf(raw);
    final url = jsonText(format['url']);
    if (!url.contains('m3u8')) continue;
    final resolution = jsonText(format['resolution']);
    final resMatch = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
    // 档位名按短边(height):竖屏直播 resolution 为 1080x1920,用长边会得到
    // 1920p 这类非常规档名,与设置里的 720p/1080p 对不上。
    final height = resMatch != null
        ? _shortSide(
            int.tryParse(resMatch.group(1)!) ?? 0,
            int.tryParse(resMatch.group(2)!) ?? 0,
          )
        : jsonInt(format['height']);
    final fpsValue = format['fps'];
    final fps = fpsValue is num
        ? fpsValue.round()
        : (double.tryParse(jsonText(fpsValue)) ?? 0).round();
    final label = height == 0
        ? '自动'
        : (fps > 30 ? '${height}p$fps' : '${height}p');
    if (!seenLabels.add(label)) continue;
    tiers.add(
      YoutubeDlpTier(label: label, url: url, height: height, fps: fps),
    );
  }
  tiers.sort((a, b) {
    final byHeight = b.height.compareTo(a.height);
    if (byHeight != 0) return byHeight;
    return b.fps.compareTo(a.fps);
  });
  return tiers;
}

/// dlp 档位 -> 统一 StreamQuality(每档一条线路)。
///
/// dlp 下发的是同一批 googlevideo 媒体地址,沿用 [youtubePlaybackHeaders]:
/// 首档预校验(validateYoutubeChain)即以此组头探测。
List<StreamQuality> youtubeDlpQualities(List<YoutubeDlpTier> tiers) => [
  for (final tier in tiers)
    StreamQuality(
      name: tier.label,
      rate: tier.height * 1000 + tier.fps,
      lines: [
        StreamLine(
          name: '线路',
          url: tier.url,
          format: 'hls',
          headers: youtubePlaybackHeaders,
        ),
      ],
    ),
];

int _shortSide(int width, int height) {
  if (width <= 0) return height;
  if (height <= 0) return width;
  return width < height ? width : height;
}
