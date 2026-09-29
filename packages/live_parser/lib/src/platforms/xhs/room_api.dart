/// 小红书房间解析:模拟 iOS App UA 直抓 `www.xiaohongshu.com/livestream/<roomId>`
/// 页面 SSR 的 `window.__INITIAL_STATE__`,免签名(desktop UA 的 SSR 里
/// roomInfo 为空,流地址由客户端 JS 加载;iOS UA 直出全量数据)。
///
/// 链路与字段口径对齐参考实现(SFVideoLive services/streaming-server
/// src/resolve/xhs/index.ts,2026-09-04 抓包验证):
/// * `liveStatus == "success"` 且 pullConfig 里有流 → 在播;
/// * 标题含「回放」按未开播处理(StreamGet 同款约定);
/// * `pageStatus == "error"`(未找到直播间)→ 房间不存在;
/// * pullConfig 是 JSON 字符串:h264[]/h265[] 多线路 CDN 直链,
///   清晰度只有「原画」单档;「高清」低码率档 = 同 URL 扩展名前插
///   `_hcv520`(web 播放器清晰度切换同款规则),在解析侧派生;
/// * xhslink 短链:302 跟随后按最终 URL 分流(/livestream/ 直连,
///   /user/profile/ 只回主播名,均对齐参考实现)。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'signing.dart';

/// 小红书站点标识(与 UI PlatformBrandCatalog / nav 对齐)。
const String kXhsSiteId = 'xhs';

/// 小红书解析源标识。
const String kXhsSource = 'live_parser/xhs';

/// live-room 分类/列表 API host(非 edith)。
const String kXhsLiveRoomHost = 'live-room.xiaohongshu.com';

/// 画质两档:原画 = pullConfig 原链,高清 = 同 URL 加 `_hcv520` 后缀。
const String kXhsDefaultQuality = '原画';
const String kXhsHdQuality = '高清';

/// 纯数字 roomId 的最小位数(参考实现 `^\d{6,}$` 同款,防误伤短码)。
final RegExp _pureRoomId = RegExp(r'^\d{6,}$');

final RegExp _livestreamPath = RegExp(
  r'xiaohongshu\.com/livestream/(\d+)',
  caseSensitive: false,
);

final RegExp _profilePath = RegExp(
  r'xiaohongshu\.com/(user/profile/[0-9a-f]+)',
  caseSensitive: false,
);

/// 房间页地址(取流与 sourceUrl 共用)。
String xhsSourceUrl(String roomId) =>
    'https://www.xiaohongshu.com/livestream/$roomId';

/// 房间号/URL 归一:支持纯数字 roomId 与 `/livestream/<roomId>` 直链;
/// xhslink 短链原样透传(302 解析需要网络,见 [XhsClient.fetchLiveContext])。
String normalizeXhsRoomId(String value) {
  final raw = value.trim();
  if (raw.isEmpty) return raw;
  // 短链(含/不含 scheme)原样透传。
  if (raw.contains('xhslink.com')) return raw;
  if (_pureRoomId.hasMatch(raw)) return raw;
  final livestream = _livestreamPath.firstMatch(raw);
  if (livestream != null) return livestream.group(1)!;
  // 兜底:取第一段 6 位以上数字(与参考实现 normalizeUrl 同款)。
  final digits = RegExp(r'(\d{6,})').firstMatch(raw);
  return digits?.group(1) ?? raw;
}

/// Cookie 未配置/缺少键/上游 -101 时抛出;宿主据此提示用户重新保存凭证。
class XhsCookieExpiredException implements Exception {
  const XhsCookieExpiredException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 从 deeplink query 里取参数(host_nickname / host_avatar / host_id),
/// URL 解码失败保留原值(参考实现 deeplinkParam 同款)。
String _deeplinkParam(String deeplink, String key) {
  final index = deeplink.indexOf('$key=');
  if (index < 0) return '';
  final rest = deeplink.substring(index + key.length + 1);
  final end = rest.indexOf('&');
  final value = end >= 0 ? rest.substring(0, end) : rest;
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  }
}

String _firstNonEmpty(List<String> values) {
  for (final value in values) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) return trimmed;
  }
  return '';
}

/// 解析 pullConfig JSON 字符串为多线路 CDN 直链。
///
/// * h264[] 与 h265[] 合并(h265 实测常为空),按 master_url 去重;
/// * 线路名按 CDN host 命名:live-source-play(主)/ -hw(华为)/
///   -bak(备用);格式按扩展名判 hls/flv。
List<StreamLine> parseXhsPullConfig(Object? raw) {
  final text = raw is String ? raw.trim() : '';
  if (text.isEmpty) return const [];
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return const [];
  }
  if (decoded is! Map) return const [];
  final conf = Map<String, dynamic>.from(decoded);
  final entries = [
    for (final codec in const ['h264', 'h265']) ...jsonListOf(conf[codec]),
  ];
  final lines = <StreamLine>[];
  final seen = <String>{};
  for (final entry in entries) {
    final item = jsonMapOf(entry);
    final url = jsonText(item['master_url']).trim();
    if (url.isEmpty ||
        !(url.startsWith('http://') || url.startsWith('https://')) ||
        !seen.add(url)) {
      continue;
    }
    final isHls = url.toLowerCase().contains('.m3u8');
    final host = Uri.tryParse(url)?.host ?? '';
    final cdn = host.contains('-bak')
        ? '备用线路'
        : host.contains('-hw')
        ? '华为线路'
        : '主线路';
    lines.add(
      StreamLine(
        name: '$cdn·${isHls ? 'HLS' : 'FLV'}',
        url: url,
        format: isHls ? 'hls' : 'flv',
      ),
    );
  }
  return lines;
}

/// 原画线路 → 高清(低码率)线路:扩展名前插 `_hcv520`
/// (web 播放器清晰度切换同款规则);无法派生时回退原线路。
List<StreamLine> xhsHdLines(List<StreamLine> lines) {
  final hd = <StreamLine>[];
  for (final line in lines) {
    final url = line.url.replaceFirstMapped(
      RegExp(r'(\.m3u8|\.flv)$', caseSensitive: false),
      (match) => '_hcv520${match.group(1)}',
    );
    if (url == line.url) continue;
    hd.add(StreamLine(name: line.name, url: url, format: line.format));
  }
  return hd.isEmpty ? lines : hd;
}

/// 直播间页 SSR 解析出的房间上下文(取流与轻量刷新共用)。
class XhsPageContext {
  const XhsPageContext({
    required this.roomId,
    required this.live,
    required this.roomMissing,
    required this.lines,
    required this.anchorName,
    required this.title,
    required this.cover,
    required this.avatar,
    required this.hostId,
    required this.viewerCount,
    required this.errorMessage,
  });

  /// 归一后的房间号(roomInfo.roomId 为 0/缺失时回退入参)。
  final String roomId;

  /// 在播(liveStatus==success 且派生出线路且非「回放」)。
  final bool live;

  /// 页面无房间数据(初始状态缺失/解析失败/未找到直播间)。
  /// 与「主播存在但未开播」区分:前者映射 notFound,后者 offline。
  final bool roomMissing;

  /// 原画线路(pullConfig 解析结果;离线/回放为空)。
  final List<StreamLine> lines;
  final String anchorName;
  final String title;
  final String cover;
  final String avatar;

  /// 主播 uid(deeplink host_id,供后续扩展使用)。
  final String hostId;

  /// 已格式化的观众数字符串(如「1万+」,上游直出,原样保留)。
  final String viewerCount;
  final String errorMessage;
}

/// 从直播间页 HTML 解析 `window.__INITIAL_STATE__`。
///
/// 纯函数,离线单测直接喂 fixture HTML;字段映射与参考实现
/// pageContext() 逐项对齐。
XhsPageContext parseXhsInitialState(String html, {required String fallbackRoomId}) {
  XhsPageContext missingState(String message) => XhsPageContext(
    roomId: fallbackRoomId,
    live: false,
    roomMissing: true,
    lines: const [],
    anchorName: '',
    title: '',
    cover: '',
    avatar: '',
    hostId: '',
    viewerCount: '',
    errorMessage: message,
  );

  final match = RegExp(
    r'window\.__INITIAL_STATE__\s*=\s*(.*?)</script>',
    dotAll: true,
  ).firstMatch(html);
  if (match == null) return missingState('未获取到房间数据');
  // 语句结尾的分号会被 `.*?</script>` 一并捕获,裁掉后再解码。
  var stateText = match.group(1)!.trim();
  if (stateText.endsWith(';')) {
    stateText = stateText.substring(0, stateText.length - 1);
  }
  final Object? decoded;
  try {
    // JS 里的 undefined 不是合法 JSON,统一替换为 null(参考实现同款)。
    decoded = jsonDecode(stateText.replaceAll('undefined', 'null'));
  } on FormatException {
    return missingState('未获取到房间数据');
  }
  if (decoded is! Map) return missingState('未获取到房间数据');
  final liveStream = jsonMapOf(Map<String, dynamic>.from(decoded))['liveStream'];
  final stream = jsonMapOf(liveStream);
  if (stream.isEmpty) return missingState('未获取到房间数据');

  final pageStatus = jsonText(stream['pageStatus']);
  if (pageStatus == 'error') {
    final message = jsonText(stream['errorMessage']).trim();
    return missingState(message.isEmpty ? '未找到直播间' : message);
  }

  final roomData = jsonMapOf(stream['roomData']);
  final roomInfo = jsonMapOf(roomData['roomInfo']);
  if (roomInfo.isEmpty) return missingState('未获取到房间数据');
  final hostInfo = jsonMapOf(roomData['hostInfo']);
  final deeplink = jsonText(roomInfo['deeplink']);
  final title = jsonText(roomInfo['roomTitle']);
  // 「回放」标题 = 未开播(StreamGet 同款约定):即使 liveStatus==success
  // 且带 pullConfig 也按离线处理,不派生线路。
  final replay = title.contains('回放');
  final lines = replay ? const <StreamLine>[] : parseXhsPullConfig(roomInfo['pullConfig']);
  final live = jsonText(stream['liveStatus']) == 'success' && lines.isNotEmpty;
  final rawRoomId = jsonText(roomInfo['roomId']).trim();
  final resolvedRoomId = rawRoomId.isNotEmpty && rawRoomId != '0'
      ? rawRoomId
      : fallbackRoomId;
  return XhsPageContext(
    roomId: resolvedRoomId,
    live: live,
    roomMissing: false,
    lines: lines,
    // 主播名:hostInfo.nickName 缺失时回退 deeplink query 的 host_nickname。
    anchorName: _firstNonEmpty([
      jsonText(hostInfo['nickName']),
      _deeplinkParam(deeplink, 'host_nickname'),
    ]),
    title: title,
    cover: jsonText(roomInfo['roomCover']),
    avatar: _firstNonEmpty([
      _deeplinkParam(deeplink, 'host_avatar'),
      jsonText(hostInfo['avatar']),
    ]),
    hostId: _deeplinkParam(deeplink, 'host_id'),
    viewerCount: jsonText(roomInfo['displayViewerCount']),
    errorMessage: live ? '' : (replay ? '回放' : '未开播'),
  );
}

/// 小红书底层客户端:直连页抓取(iOS UA,免签名)+ live-room 签名 API。
///
/// 凭证(整串 Cookie 或 `a1=...; web_session=...`)来自用户凭证页;
/// [signer] 供测试注入桩签名(生产路径由 credential 构造 [XhsSigner])。
class XhsClient {
  XhsClient({
    http.Client? httpClient,
    String credential = '',
    XhsSigner? signer,
  }) : credential = credential.trim() {
    _ownsHttpClient = httpClient == null;
    _httpClient = httpClient ?? http.Client();
    parserHttp = ParserHttp(client: _httpClient);
    _injectedSigner = signer;
  }

  /// 外部注入的凭证;空串 = 未配置(browse 侧请求直接抛
  /// [XhsCookieExpiredException],对齐参考实现 ensureCookies 语义)。
  final String credential;

  late final ParserHttp parserHttp;
  late final http.Client _httpClient;
  late final bool _ownsHttpClient;
  late final XhsSigner? _injectedSigner;
  XhsSigner? _signerCache;

  /// 签名器:测试注入优先,其次按 credential 构造(带缓存)。
  /// 未配置/缺少 a1+web_session 抛 [XhsCookieExpiredException]。
  XhsSigner requireSigner() {
    final injected = _injectedSigner;
    if (injected != null) return injected;
    final cached = _signerCache;
    if (cached != null) return cached;
    final value = credential;
    if (value.isEmpty) {
      throw const XhsCookieExpiredException(
        '小红书 Cookie 未配置,请在凭证页填入 a1 与 web_session',
      );
    }
    final XhsSigner signer;
    try {
      signer = XhsSigner.fromCredential(value);
    } on ArgumentError {
      throw const XhsCookieExpiredException('小红书 Cookie 缺少 a1 或 web_session');
    }
    _signerCache = signer;
    return signer;
  }

  /// 房间解析入口:输入归一后的 roomId、/livestream/ 直链或 xhslink 短链。
  Future<XhsPageContext> fetchLiveContext(String roomIdOrUrl) async {
    final normalized = normalizeXhsRoomId(roomIdOrUrl);
    if (normalized.contains('xhslink.com')) {
      return _resolveShortLink(normalized);
    }
    return fetchRoomContext(normalized);
  }

  /// 抓取并解析直播间页(iOS App UA,无签名;对齐参考实现 iOS 头)。
  Future<XhsPageContext> fetchRoomContext(String roomId) async {
    final response = await parserHttp.get(
      Uri.parse(xhsSourceUrl(roomId)),
      headers: {
        ...XhsStreamHeaders.headers(),
        'Accept-Language': 'zh-CN,zh;q=0.9',
      },
    );
    return parseXhsInitialState(
      utf8.decode(response.bodyBytes),
      fallbackRoomId: roomId,
    );
  }

  /// live-room API JSON GET(带签名头)。路径/参数与参考实现 categories.ts 对齐。
  Future<Map<String, dynamic>> getSignedJson(
    String path,
    Map<String, Object?> params,
  ) async {
    final signer = requireSigner();
    final query = <String, String>{
      for (final entry in params.entries) entry.key: '${entry.value}',
    };
    final response = await parserHttp.get(
      Uri.https(kXhsLiveRoomHost, path, query),
      headers: signer.signedHeaders('GET', path, params: params),
    );
    return parserHttp.jsonMap(response);
  }

  /// xhslink 短链 → 逐跳 302 → 最终 URL 分流(参考实现 loadMetaFromShortLink
  /// 同款;package:http 不暴露最终 URL,改为手动跟随重定向):
  /// * `/livestream/<roomId>` → 常规房间解析;
  /// * `/user/profile/<uid>` → 主页壳页,只取 `<title>@xx 的个人主页` 主播名,
  ///   按离线处理;
  /// * 未知形态 → 离线空记录。
  Future<XhsPageContext> _resolveShortLink(String link) async {
    final target = link.startsWith('http://') || link.startsWith('https://')
        ? link
        : 'https://$link';
    final Uri? parsed = Uri.tryParse(target);
    if (parsed == null) {
      return _unresolvedShortLink(link, '短链地址无法解析');
    }
    Uri current = parsed;
    http.Response? finalResponse;
    try {
      for (var hop = 0; hop < 5; hop++) {
        final request = http.Request('GET', current)
          ..followRedirects = false
          ..headers.addAll(XhsStreamHeaders.headers());
        final response = await http.Response.fromStream(
          await _httpClient.send(request),
        );
        final status = response.statusCode;
        final location = response.headers['location']?.trim() ?? '';
        final isRedirect = status == 301 ||
            status == 302 ||
            status == 303 ||
            status == 307 ||
            status == 308;
        if (!isRedirect || location.isEmpty) {
          // 终点响应保留:若是直播页可直接解析,省一次重复请求。
          finalResponse = response;
          break;
        }
        final next = current.resolve(location);
        if (next == current) break;
        current = next;
      }
    } on Object {
      return _unresolvedShortLink(link, '短链跳转失败');
    }
    final finalUrl = current.toString();
    final livestream = _livestreamPath.firstMatch(finalUrl);
    if (livestream != null) {
      final response = finalResponse;
      if (response != null &&
          response.statusCode >= 200 &&
          response.statusCode < 300) {
        return parseXhsInitialState(
          utf8.decode(response.bodyBytes),
          fallbackRoomId: livestream.group(1)!,
        );
      }
      return fetchRoomContext(livestream.group(1)!);
    }
    final profile = _profilePath.firstMatch(finalUrl);
    if (profile != null) {
      return XhsPageContext(
        roomId: link,
        live: false,
        // 主页形态是合法的「主播存在但无房间」:按离线而非 notFound
        // (参考实现 offlineMeta(anchorName) 同款)。
        roomMissing: false,
        lines: const [],
        anchorName: await _fetchProfileAnchor(
          'https://www.xiaohongshu.com/${profile.group(1)}',
        ),
        title: '',
        cover: '',
        avatar: '',
        hostId: '',
        viewerCount: '',
        errorMessage: '主播未开播',
      );
    }
    return _unresolvedShortLink(link, '短链未解析到直播间');
  }

  XhsPageContext _unresolvedShortLink(String link, String message) =>
      XhsPageContext(
        roomId: link,
        live: false,
        roomMissing: false,
        lines: const [],
        anchorName: '',
        title: '',
        cover: '',
        avatar: '',
        hostId: '',
        viewerCount: '',
        errorMessage: message,
      );

  /// 主页 SSR `<title>` 取主播名(desktop UA;失败留空,不阻塞离线记录)。
  Future<String> _fetchProfileAnchor(String profileUrl) async {
    try {
      final response = await parserHttp.get(
        Uri.parse(profileUrl),
        headers: const {
          'Accept': 'text/html,application/xhtml+xml,*/*;q=0.8',
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': 'https://www.xiaohongshu.com/',
        },
      );
      final html = utf8.decode(response.bodyBytes);
      final match = RegExp(
        r'<title>@(.*?)\s*的个人主页</',
        dotAll: true,
      ).firstMatch(html);
      return match?.group(1)?.trim() ?? '';
    } on Object {
      return '';
    }
  }

  void close() {
    if (_ownsHttpClient) _httpClient.close();
  }
}
