/// Twitch 站点组装:房间解析 + 浏览 + 搜索共享一个 HTTP 实例与 GQL 客户端。
library;

import 'package:http/http.dart' as http;

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import 'browse.dart';
import 'gql.dart';
import 'normalize.dart';
import 'room_api.dart';
import 'search.dart';

/// Twitch 解析源标识。
const String kTwitchSource = 'live_parser/twitch';

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

  @override
  Future<RoomPayload> resolveRoom(RoomRequest request) async {
    final login = normalizeTwitchLogin(request.roomIdOrUrl);
    if (login.isEmpty) {
      throw const ParserHttpException('无法识别的 Twitch 房间输入');
    }
    final url = 'https://www.twitch.tv/$login';

    final user = await fetchTwitchUser(_client.gql, login);
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

    final token = await fetchTwitchPlaybackToken(_client.gql, user.login);
    final playlist = await fetchTwitchMasterPlaylist(
      _client.parserHttp,
      login: user.login,
      token: token,
      clientId: _client.clientId,
    );
    final streams = parseTwitchMasterPlaylist(playlist);
    if (streams.isEmpty) {
      throw const ParserHttpException('未获取到可播放的 HLS 地址');
    }

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
    );
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
    availableQualities: [
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
    resolver: TwitchRoomResolver(effectiveClient),
    browse: TwitchBrowseRepository(effectiveClient.gql),
    search: TwitchSearchRepository(effectiveClient.gql),
  );
}
