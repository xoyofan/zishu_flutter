/// Twitch 站点组装:房间解析 + 浏览 + 搜索共享一个 HTTP 实例与 GQL 客户端。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/danmaku_transport.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../models/room_record.dart';
import '../../registry/cached_room_resolver.dart';
import '../../registry/site_display.dart';
import 'browse.dart';
import 'danmaku.dart';
import 'gql.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

/// Twitch 解析源标识。
const String kTwitchSource = 'live_parser/twitch';

/// 未指定清晰度时的默认档:480p 高清(对齐 web 6b4983e 的产品决策)。
///
/// 「自动」主清单(AUTO)会让播放器先拉 master m3u8 做 ABR 逐级探测,
/// 首帧显著慢于直连单档;进房默认直接下发 480p 的 media playlist,
/// 用户切档时再按档重新解析。
const String kTwitchDefaultQuality = '480p';

/// Twitch 客户端:GQL 与 usher 共用同一个 HTTP 实例。
class TwitchClient {
  TwitchClient({http.Client? httpClient, this.clientId = kTwitchWebClientId})
    : _http = ParserHttp(
        client: httpClient,
        // Client-ID 必须在这里带上:GQL 客户端复用本实例,不再自行注入。
        defaultHeaders: {
          'Client-ID': clientId,
          'Referer': 'https://www.twitch.tv/',
        },
      ) {
    gql = TwitchGqlClient(parserHttp: _http, clientId: clientId);
  }

  final String clientId;
  final ParserHttp _http;

  late final TwitchGqlClient gql;

  ParserHttp get parserHttp => _http;

  void close() => _http.close();
}

class TwitchRoomResolver implements RoomResolver, RoomSummaryRefresher {
  TwitchRoomResolver(this._client);

  final TwitchClient _client;

  /// 直播结果短缓存(对齐 SF playlistCache 20s):短时间内重复进房不再打 GQL/usher。
  ///
  /// 键 = login + 偏好档:单档化后不同偏好档解析出不同的选中档,若只按 login
  /// 缓存,切档会命中上一档的 payload(占位档永远拿不到线路)。
  final Map<String, ({DateTime at, RoomPayload payload})> _cache = {};
  static const Duration _cacheTtl = Duration(seconds: 20);

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final login = normalizeTwitchLogin(request.roomIdOrUrl);
    if (login.isEmpty) {
      throw const ParserHttpException('无法识别的 Twitch 房间输入');
    }
    final url = 'https://www.twitch.tv/$login';
    final key =
        '${login.toLowerCase()}\u0000${request.preferredQuality?.trim() ?? ''}';
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.at) < _cacheTtl) {
      return cached.payload;
    }

    final payload = await _resolve(login, url, request.preferredQuality);
    if (payload.isLive) {
      _cache[key] = (at: DateTime.now(), payload: payload);
    }
    return payload;
  }

  /// 轻量状态刷新:只打 GQL UseLive 元信息查询,不碰播放令牌/usher 取流
  /// (RoomSummaryRefresher 契约:刷新不得出现取流/签名相关调用)。
  ///
  /// 在播(stream 非空)回填标题/分类/封面与观看数文案;离线一律 `online`
  /// 空串(出口归 null,在播判据是 [RoomRecord.roomState])。主播不存在按上游报错抛
  /// 异常,不返回伪造资料;离线时元信息字段留空,宿主合并口径是
  /// 「刷新非空才覆盖」,不会冲掉本地已有值。
  @override
  Future<RoomRecord> refreshRoomSummary(RoomRequest request) async {
    final login = normalizeTwitchLogin(request.roomIdOrUrl);
    if (login.isEmpty) {
      throw const ParserHttpException('无法识别的 Twitch 房间输入');
    }
    final user = await _retryTwitch(() => fetchTwitchUser(_client.gql, login));
    if (user == null) {
      throw ParserHttpException('主播不存在: $login');
    }
    final stream = user.stream;
    return RoomRecord.fromSummary(RoomSummary(
      site: kTwitchSiteId,
      roomId: user.login,
      title: stream?.title ?? '',
      anchorName: user.name,
      cid: stream?.gameId ?? '',
      category: stream?.gameName ?? '',
      online: stream == null ? '' : twitchOnlineText(stream.viewers),
      cover: stream?.preview ?? '',
      // 头像:UseLive 查询已带回的 profileImageURL(零额外请求)。
      avatar: user.avatar,
      startedAt: stream?.startedAt,
    ));
  }

  Future<RoomPayload> _resolve(
    String login,
    String url,
    String? preferredQuality,
  ) async {
    // metadata 与 playback token 互不依赖(都只需 login),并行请求;
    // token 对离线房会失败,静默置空,不影响离线资料返回。
    final results = await Future.wait<Object?>([
      _retryTwitch(() => fetchTwitchUser(_client.gql, login)),
      _retryTwitch(() => _fetchTokenOrEmpty(login)),
    ]);
    final user = results[0] as TwitchUser?;
    final token = results[1] as TwitchPlaybackToken;
    if (user == null) {
      return _payload(
        roomId: login,
        sourceUrl: url,
        roomState: RoomState.notFound,
        error: '主播不存在',
      );
    }
    final stream = user.stream;
    if (stream == null) {
      return _payload(
        roomId: user.login,
        sourceUrl: url,
        anchorName: user.name,
        avatar: user.avatar,
        roomState: RoomState.offline,
      );
    }
    if (token.value.isEmpty || token.signature.isEmpty) {
      throw const ParserHttpException('未获取到播放令牌');
    }

    final playlist = await _retryTwitch(
      () => fetchTwitchMasterPlaylist(
        _client.parserHttp,
        login: user.login,
        token: token,
        clientId: _client.clientId,
      ),
    );
    final allStreams = parseTwitchMasterPlaylist(playlist);
    if (allStreams.isEmpty) {
      throw const ParserHttpException('未获取到可播放的 HLS 地址');
    }

    // 全档线路一次拿到(master m3u8 本身就带每档 media playlist 地址):
    // 只把选中档排到首位(播放侧取 streams.first 起播,不做 ABR 逐级探测,
    // 首帧仍然快),其余档位**保留真实线路**。
    //
    // 历史实现把非选中档的线路清空成占位,代价是切档必须整轮重新解析
    // (GQL token + usher,约 2-3 个请求);实测切换延迟与「Twitch 解析慢」
    // 均源于此。承载全档线路不增加任何上游请求,切档变为零延迟。
    final picked = _pickTwitchQuality(allStreams, preferredQuality);
    final streams = [
      picked,
      for (final stream in allStreams)
        if (!identical(stream, picked)) stream,
    ];

    return _payload(
      roomId: user.login,
      sourceUrl: url,
      anchorName: user.name,
      title: stream.title,
      cover: stream.preview,
      avatar: user.avatar,
      startedAt: stream.startedAt,
      category: stream.gameName,
      cid: stream.gameId,
      roomState: RoomState.live,
      streams: streams,
      // chips 保持平台原顺序(分辨率降序),不因默认选中档提前而打乱。
      availableQualities: [
        for (final item in allStreams)
          QualityOption(name: item.name, rate: item.rate),
      ],
    );
  }

  /// 档位选择:指定偏好档按精确/双向包含匹配(matchQualityPreference);
  /// 未指定时默认 [kTwitchDefaultQuality](480p 高清);两者都未命中时回退
  /// 首档(分辨率降序后的最高档),保证任何主列表都有可播结果。
  StreamQuality _pickTwitchQuality(
    List<StreamQuality> streams,
    String? preferredQuality,
  ) {
    final preference = preferredQuality?.trim() ?? '';
    final requested = preference.isEmpty ? kTwitchDefaultQuality : preference;
    return matchQualityPreference(
          streams,
          requested,
          (stream) => stream.name,
        ) ??
        streams.first;
  }

  Future<TwitchPlaybackToken> _fetchTokenOrEmpty(String login) async {
    try {
      return await fetchTwitchPlaybackToken(_client.gql, login);
    } on Object {
      return const TwitchPlaybackToken(value: '', signature: '');
    }
  }

  Future<T> _retryTwitch<T>(Future<T> Function() action) async {
    Object? lastError;
    for (var attempt = 0; attempt < 3; attempt++) {
      if (attempt > 0) {
        await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
      }
      try {
        return await action();
      } on Object catch (error) {
        lastError = error;
      }
    }
    Error.throwWithStackTrace(lastError!, StackTrace.current);
  }

  RoomPayload _payload({
    required String roomId,
    required String sourceUrl,
    required RoomState roomState,
    String anchorName = '',
    String title = '',
    String cover = '',
    String avatar = '',
    String category = '',
    String cid = '',
    DateTime? startedAt,
    List<StreamQuality> streams = const [],
    List<QualityOption>? availableQualities,
    String? error,
  }) => RoomPayload(
    site: kTwitchSiteId,
    roomId: roomId,
    sourceUrl: sourceUrl,
    anchorName: anchorName,
    title: title,
    cover: cover,
    avatar: avatar,
    category: category,
    cid: cid,
    roomState: roomState,
    streams: streams,
    availableQualities:
        availableQualities ??
        [
          for (final stream in streams)
            QualityOption(name: stream.name, rate: stream.rate),
        ],
    startedAt: startedAt,
    source: kTwitchSource,
    fetchedAt: DateTime.now(),
    error: error,
  );
}

/// 组装 Twitch 注册项;[httpClient] 供测试注入 fake。
SiteRegistration buildTwitchRegistration({
  http.Client? httpClient,
  TwitchClient? client,
  String clientId = kTwitchWebClientId,
  DanmakuTransport? danmakuTransport,
}) {
  final effectiveClient =
      client ?? TwitchClient(httpClient: httpClient, clientId: clientId);
  return SiteRegistration(
    id: kTwitchSiteId,
    name: 'Twitch',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      danmaku: true,
      multiQuality: true,
    ),
    display: kTwitchDisplay,
    resolver: CachedRoomResolver(TwitchRoomResolver(effectiveClient)),
    browse: TwitchBrowseRepository(effectiveClient.gql),
    search: TwitchSearchRepository(effectiveClient.gql),
    danmaku: TwitchDanmakuConnector(transport: danmakuTransport),
  );
}
