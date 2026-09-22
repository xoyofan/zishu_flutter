/// YouTube 房间解析:watch 页 ytInitialPlayerResponse(纯 HTTP 回退链路)
/// + InnerTube `/player`(WEB → ANDROID_VR)+ HLS master 解析与链路预校验。
///
/// 不依赖 yt-dlp(宿主可自行注入外部提取结果);页面下发 `hlsManifestUrl`
/// 按实验桶随机,失败时重拉页面最多 4 轮。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../http/parser_http.dart';
import '../../models/models.dart';
import 'normalize.dart';

/// watch 页解析上下文。
class YoutubePageContext {
  const YoutubePageContext({
    this.player,
    this.innertubeContext,
    this.apiKey = '',
    this.pageCookies = '',
    this.initialData,
  });

  final Map<String, dynamic>? player;
  final Map<String, dynamic>? innertubeContext;
  final String apiKey;
  final String pageCookies;
  final Map<String, dynamic>? initialData;

  bool get hasPlayer => player != null;

  Map<String, dynamic> get videoDetails => _mapOf(player?['videoDetails']);

  Map<String, dynamic> get streamingData => _mapOf(player?['streamingData']);

  Map<String, dynamic> get playabilityStatus =>
      _mapOf(player?['playabilityStatus']);

  bool get isLiveContent => videoDetails['isLiveContent'] == true;
}

class YoutubeClient {
  YoutubeClient({http.Client? httpClient, this.cookie = ''})
    : parserHttp = ParserHttp(
        client: httpClient,
        defaultHeaders: const {'User-Agent': kYoutubeUserAgent},
      );

  final ParserHttp parserHttp;

  /// 可选登录 cookie(匿名也可用;InnerTube /player 常被 bot 校验拦截)。
  final String cookie;

  void close() => parserHttp.close();
}

/// 在 [html] 中定位 [marker] 后的第一个 `{`,用括号配平状态机提取 JSON 对象。
Map<String, dynamic>? extractJsonObjectAfter(String html, String marker) {
  final index = html.indexOf(marker);
  if (index < 0) return null;
  final start = html.indexOf('{', index + marker.length);
  if (start < 0) return null;
  var depth = 0;
  var inString = false;
  var escaped = false;
  for (var i = start; i < html.length; i++) {
    final ch = html[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (ch == r'\') {
        escaped = true;
      } else if (ch == '"') {
        inString = false;
      }
      continue;
    }
    if (ch == '"') {
      inString = true;
    } else if (ch == '{') {
      depth += 1;
    } else if (ch == '}') {
      depth -= 1;
      if (depth == 0) {
        try {
          final decoded = jsonDecode(html.substring(start, i + 1));
          return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
        } on FormatException {
          return null;
        }
      }
    }
  }
  return null;
}

/// 拉取 watch 页并解析 player / InnerTube 上下文(失败返回空上下文)。
Future<YoutubePageContext> fetchYoutubeWatchPage(
  YoutubeClient client,
  String videoId,
) async {
  try {
    final response = await client.parserHttp.get(
      Uri.parse('https://www.youtube.com/watch?v=$videoId&hl=en&has_verified=1'),
      headers: youtubePageHeaders(cookie: client.cookie),
    );
    final html = utf8.decode(response.bodyBytes);
    final player = extractJsonObjectAfter(html, 'ytInitialPlayerResponse');
    final context = extractJsonObjectAfter(html, '"INNERTUBE_CONTEXT":');
    final apiKey =
        RegExp(r'"INNERTUBE_API_KEY":"([^"]+)"').firstMatch(html)?.group(1) ??
        '';
    final pageCookies = _setCookieValues(
      response.headers['set-cookie'],
    ).join('; ');
    return YoutubePageContext(
      player: player,
      innertubeContext: context,
      apiKey: apiKey,
      pageCookies: pageCookies,
      initialData: extractJsonObjectAfter(html, 'ytInitialData'),
    );
  } on Object {
    return const YoutubePageContext();
  }
}

/// 解析 master playlist 为档位:同 label 的多个变体合并为多线路。
List<StreamQuality> parseYoutubeMasterPlaylist(
  String content,
  String masterUri,
) {
  final lines = const LineSplitter().convert(content);
  final grouped = <String, ({int height, int fps, int bandwidth, List<String> urls})>{};

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (!line.startsWith('#EXT-X-STREAM-INF:')) continue;
    final attributes = <String, String>{};
    for (final part in line.substring('#EXT-X-STREAM-INF:'.length).split(',')) {
      final eq = part.indexOf('=');
      if (eq <= 0) continue;
      attributes[part.substring(0, eq).trim()] = part
          .substring(eq + 1)
          .trim()
          .replaceAll('"', '');
    }
    String? variantUri;
    for (var j = i + 1; j < lines.length; j++) {
      final candidate = lines[j].trim();
      if (candidate.isEmpty || candidate.startsWith('#')) continue;
      variantUri = candidate;
      break;
    }
    if (variantUri == null || variantUri.isEmpty) continue;

    final absolute = _resolveUri(variantUri, masterUri);
    if (absolute.isEmpty) continue;

    final resolution = attributes['RESOLUTION'] ?? '';
    final resMatch = RegExp(r'^(\d+)x(\d+)$').firstMatch(resolution);
    final height = resMatch != null
        ? _shortSide(
            int.tryParse(resMatch.group(1)!) ?? 0,
            int.tryParse(resMatch.group(2)!) ?? 0,
          )
        : 0;
    final fpsRaw = double.tryParse(attributes['FRAME-RATE'] ?? '') ?? 0;
    final fps = fpsRaw.round();
    final bandwidth = int.tryParse(attributes['BANDWIDTH'] ?? '') ?? 0;
    final key = '$height:$fps';
    final existing = grouped[key];
    if (existing == null) {
      grouped[key] = (
        height: height,
        fps: fps,
        bandwidth: bandwidth,
        urls: [absolute],
      );
    } else if (!existing.urls.contains(absolute)) {
      if (bandwidth > existing.bandwidth) {
        grouped[key] = (
          height: height,
          fps: fps,
          bandwidth: bandwidth,
          urls: [absolute],
        );
      } else {
        existing.urls.add(absolute);
      }
    }
  }

  final qualities = grouped.values
      .map(
        (entry) => StreamQuality(
          name: entry.height == 0
              ? '自动'
              : (entry.fps > 30
                    ? '${entry.height}p${entry.fps}'
                    : '${entry.height}p'),
          rate: entry.bandwidth,
          lines: [
            for (var i = 0; i < entry.urls.length; i++)
              StreamLine(
                name: '线路 ${i + 1}',
                url: entry.urls[i],
                format: 'hls',
                headers: youtubePlaybackHeaders,
              ),
          ],
        ),
      )
      .toList(growable: false);
  qualities.sort((a, b) => b.rate.compareTo(a.rate));
  return qualities;
}

/// InnerTube `/player`:WEB(带页面 context/cookie)失败后尝试 ANDROID_VR。
Future<String> _innertubePlayerHls(
  YoutubeClient client,
  YoutubePageContext ctx,
  String videoId,
) async {
  final apiKey = ctx.apiKey;
  final uri = Uri.parse(
    'https://www.youtube.com/youtubei/v1/player'
    '${apiKey.isNotEmpty ? '?key=$apiKey&' : '?'}prettyPrint=false',
  );

  final visitorData =
      '${_mapOf(ctx.innertubeContext?['client'])['visitorData'] ?? ''}';

  if (ctx.innertubeContext != null) {
    final cookie = [ctx.pageCookies, client.cookie]
        .where((value) => value.trim().isNotEmpty)
        .join('; ');
    final body = <String, dynamic>{
      'context': ctx.innertubeContext,
      'videoId': videoId,
      'contentCheckOk': true,
      'racyCheckOk': true,
    };
    final result = await _postPlayer(
      client,
      uri,
      body,
      headers: {
        'User-Agent': kYoutubeUserAgent,
        'X-Youtube-Client-Name': '1',
        'X-Goog-Visitor-Id': visitorData,
        if (cookie.isNotEmpty) 'Cookie': cookie,
      },
    );
    if (result.isNotEmpty) return result;
  }

  final body = <String, dynamic>{
    'context': {
      'client': {
        'clientName': 'ANDROID_VR',
        'clientVersion': '1.60.19',
        'deviceMake': 'Oculus',
        'deviceModel': 'Quest 3',
        'osName': 'Android',
        'osVersion': '12L',
        'hl': 'en',
        'gl': 'US',
      },
    },
    'videoId': videoId,
    'contentCheckOk': true,
    'racyCheckOk': true,
  };
  return _postPlayer(
    client,
    uri,
    body,
    headers: {
      'User-Agent':
          'com.google.android.apps.youtube.vr.oculus/1.60.19 '
          '(Linux; U; Android 12L; eureka-user Build/SQ3A.220605.009.A1) gzip',
      'X-Youtube-Client-Name': '28',
      'X-Youtube-Client-Version': '1.60.19',
      // 必需:不带这个头,ANDROID_VR 分支固定返回 LOGIN_REQUIRED(reason
      // "Sign in to confirm you're not a bot"),hlsManifestUrl 为空 —— 兜底形同虚设。
      // 2026-09-22 隔离实测:补上后曾出现 status=OK + 6 档 HLS + 分片 200(250~450ms,
      // 无需 PO Token/Deno);但同一 IP 连续请求后被重新挑战(又变 LOGIN_REQUIRED),
      // 说明这是**机会性**提升而非可靠路径:上游按 IP 状态决定是否要求 bot 校验。
      // 主路径仍是 dlp(yt-dlp+Deno 能解挑战);本头只是让兜底不再必然失败。
      // visitorData 取自 watch 页的 INNERTUBE_CONTEXT。
      if (visitorData.isNotEmpty) 'X-Goog-Visitor-Id': visitorData,
    },
  );
}

Future<String> _postPlayer(
  YoutubeClient client,
  Uri uri,
  Map<String, dynamic> body, {
  required Map<String, String> headers,
}) async {
  try {
    final response = await client.parserHttp.postJson(
      uri,
      body: body,
      headers: headers,
    );
    final json = client.parserHttp.jsonMap(response);
    final statusText = '${_mapOf(json['playabilityStatus'])['status'] ?? ''}';
    if (statusText.isNotEmpty && statusText != 'OK') return '';
    return '${_mapOf(json['streamingData'])['hlsManifestUrl'] ?? ''}';
  } on Object {
    return '';
  }
}

/// InnerTube `/player` 回退(WEB → ANDROID_VR),返回 hlsManifestUrl。
Future<String> resolveYoutubeInnerTubeHls(
  YoutubeClient client,
  YoutubePageContext ctx,
  String videoId,
) => _innertubePlayerHls(client, ctx, videoId);

/// 拉取 playlist(master / media)文本。
Future<String> fetchYoutubePlaylist(YoutubeClient client, String uri) async {
  final response = await client.parserHttp.get(
    Uri.parse(uri),
    headers: {
      'User-Agent': kYoutubeUserAgent,
      'Referer': 'https://www.youtube.com/',
      if (client.cookie.trim().isNotEmpty) 'Cookie': client.cookie.trim(),
    },
  );
  return utf8.decode(response.bodyBytes);
}

/// 三段预校验:master 200 → 首选变体 200 → 首个分片 Range 200/206。
Future<bool> validateYoutubeChain(
  YoutubeClient client,
  String masterUri,
) async {
  final headers = {
    'User-Agent': kYoutubeUserAgent,
    'Referer': 'https://www.youtube.com/',
    if (client.cookie.trim().isNotEmpty) 'Cookie': client.cookie.trim(),
  };
  try {
    final masterResponse = await client.parserHttp.get(
      Uri.parse(masterUri),
      headers: headers,
    );
    final master = utf8.decode(masterResponse.bodyBytes);
    if (!master.contains('#EXTM3U')) return false;

    if (master.contains('#EXT-X-STREAM-INF')) {
      String? variantUri;
      for (final line in const LineSplitter().convert(master)) {
        final candidate = line.trim();
        if (candidate.isEmpty || candidate.startsWith('#')) continue;
        variantUri = candidate;
        break;
      }
      if (variantUri == null) return false;
      final variantUrl = _resolveUri(variantUri, masterUri);
      if (variantUrl.isEmpty) return false;
      final variantResponse = await client.parserHttp.get(
        Uri.parse(variantUrl),
        headers: headers,
      );
      final variant = utf8.decode(variantResponse.bodyBytes);
      return await _probeFirstSegment(client, variant, variantUrl, headers);
    }
    return await _probeFirstSegment(client, master, masterUri, headers);
  } on Object {
    return false;
  }
}

Future<bool> _probeFirstSegment(
  YoutubeClient client,
  String playlist,
  String baseUri,
  Map<String, String> headers,
) async {
  String? segmentUri;
  for (final line in const LineSplitter().convert(playlist)) {
    final candidate = line.trim();
    if (candidate.isEmpty || candidate.startsWith('#')) continue;
    segmentUri = candidate;
    break;
  }
  if (segmentUri == null) return false;
  final segmentUrl = _resolveUri(segmentUri, baseUri);
  if (segmentUrl.isEmpty) return false;
  try {
    await client.parserHttp.get(
      Uri.parse(segmentUrl),
      headers: {...headers, 'Range': 'bytes=0-2048'},
    );
    return true;
  } on Object {
    return false;
  }
}

String _resolveUri(String value, String base) {
  final resolved = Uri.tryParse(base)?.resolve(value);
  return resolved?.toString() ?? '';
}

Map<String, dynamic> _mapOf(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};

int _shortSide(int width, int height) {
  if (width <= 0) return height;
  if (height <= 0) return width;
  return width < height ? width : height;
}

List<String> _setCookieValues(String? header) {
  if (header == null || header.trim().isEmpty) return const [];
  final result = <String>[];
  for (final part in header.split(RegExp(r',(?=[^;,=\s]+=)'))) {
    final pair = part.split(';').first.trim();
    if (pair.contains('=')) result.add(pair);
  }
  return result;
}
