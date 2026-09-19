/// Twitch 站点组装:房间解析 + 浏览 + 搜索共享一个 HTTP 实例与 GQL 客户端。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../registry/cached_room_resolver.dart';
import 'browse.dart';
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
  TwitchClient({
    http.Client? httpClient,
    this.clientId = kTwitchWebClientId,
  }) : _http = ParserHttp(
         client: httpClient,
         // Client-ID 必须在这里带上:GQL 客户端复用本实例,不再自行注入。
         defaultHeaders: {'Client-ID': clientId, 'Referer': 'https://www.twitch.tv/'},
       ) {
    gql = TwitchGqlClient(parserHttp: _http, clientId: clientId);
  }

  final String clientId;
  final ParserHttp _http;

  late final TwitchGqlClient gql;

  ParserHttp get parserHttp => _http;

  void close() => _http.close();
}

class TwitchRoomResolver implements RoomResolver {
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

    // 单档收敛(对齐 web 6b4983e):未指定清晰度时默认 480p 高清档,只把
    // 选中档的 media playlist 下发给播放器(跳过 AUTO 主清单的 ABR 逐级
    // 探测,首帧更快);其余档位以空线路占位供 UI chips 列出,点击后播放侧
    // 以该档为偏好重新解析。master m3u8 本就是 usher 的一次请求,收敛的是
    // 播放器侧的档位请求,不增加也不减少上游次数。
    final picked = _pickTwitchQuality(allStreams, preferredQuality);
    final streams = [
      picked,
      for (final stream in allStreams)
        if (!identical(stream, picked))
          StreamQuality(name: stream.name, rate: stream.rate, lines: const []),
    ];

    return _payload(
      roomId: user.login,
      sourceUrl: url,
      anchorName: user.name,
      title: stream.title,
      cover: stream.preview,
      avatar: user.avatar,
      category: stream.gameName,
      cid: stream.gameId,
      roomState: RoomState.live,
      streams: streams,
      // chips 保持平台原顺序(分辨率降序),不因默认选中档提前而打乱。
      availableQualities: [
        for (final item in allStreams) QualityOption(name: item.name, rate: item.rate),
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
    return matchQualityPreference(streams, requested, (stream) => stream.name) ??
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
    availableQualities: availableQualities ??
        [
          for (final stream in streams) QualityOption(name: stream.name, rate: stream.rate),
        ],
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
}) {
  final effectiveClient = client ?? TwitchClient(httpClient: httpClient, clientId: clientId);
  return SiteRegistration(
    id: kTwitchSiteId,
    name: 'Twitch',
    capabilities: const SiteCapabilities(
      browse: true,
      roomSearch: true,
      anchorSearch: true,
      multiQuality: true,
    ),
    resolver: CachedRoomResolver(TwitchRoomResolver(effectiveClient)),
    browse: TwitchBrowseRepository(effectiveClient.gql),
    search: TwitchSearchRepository(effectiveClient.gql),
  );
}
