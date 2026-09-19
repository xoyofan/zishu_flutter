/// Twitch 房间:元信息 GQL + PlaybackAccessToken + usher m3u8 多画质。
library;

import 'dart:convert';

import '../../catalog/category_name_remap.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import 'gql.dart';
import 'normalize.dart';

/// 播放令牌:usher 需要 token + sig 换取 m3u8。
class TwitchPlaybackToken {
  const TwitchPlaybackToken({required this.value, required this.signature});

  final String value;
  final String signature;
}

/// 直播间元信息。
class TwitchStreamInfo {
  const TwitchStreamInfo({
    required this.id,
    required this.title,
    required this.viewers,
    required this.gameId,
    required this.gameName,
    required this.preview,
  });

  final String id;
  final String title;
  final int viewers;
  final String gameId;
  final String gameName;
  final String preview;
}

/// Twitch 用户(主播)。[stream] 为空表示未开播。
class TwitchUser {
  const TwitchUser({
    required this.id,
    required this.login,
    required this.displayName,
    required this.avatar,
    this.stream,
  });

  final String id;
  final String login;
  final String displayName;
  final String avatar;
  final TwitchStreamInfo? stream;

  bool get isLive => stream != null;

  String get name => displayName.isNotEmpty ? displayName : login;
}

/// 元信息查询;用户不存在时返回 null。
Future<TwitchUser?> fetchTwitchUser(TwitchGqlClient gql, String login) async {
  final data = await gql.query(
    operationName: 'UseLive',
    variables: {'channelLogin': login},
    query: r'''
query UseLive($channelLogin: String!) {
  user(login: $channelLogin) {
    id
    login
    displayName
    profileImageURL(width: 300)
    stream {
      id
      title
      viewersCount
      createdAt
      type
      game { id name displayName boxArtURL }
      previewImageURL
    }
  }
}''',
  );
  final record = _mapOf((data as Map?)?['user']);
  if (record == null) return null;
  return TwitchUser(
    id: _text(record['id']),
    login: _text(record['login']).isNotEmpty ? _text(record['login']) : login,
    displayName: _text(record['displayName']),
    avatar: fillTwitchImageTemplate(_text(record['profileImageURL']), width: 300, height: 300),
    stream: _streamInfo(record['stream']),
  );
}

TwitchStreamInfo? _streamInfo(Object? value) {
  final record = _mapOf(value);
  if (record == null) return null;
  return TwitchStreamInfo(
    id: _text(record['id']),
    title: _text(record['title']),
    viewers: (record['viewersCount'] as num?)?.toInt() ?? 0,
    gameId: _text(_mapOf(record['game'])?['id']),
    gameName: remapCategoryName(
      'twitch',
      () {
        final game = _mapOf(record['game']);
        final zh = _text(game?['displayName']);
        return zh.isNotEmpty ? zh : _text(game?['name']);
      }(),
    ),
    preview: fillTwitchImageTemplate(_text(record['previewImageURL'])),
  );
}

/// 换取直播播放令牌。
Future<TwitchPlaybackToken> fetchTwitchPlaybackToken(
  TwitchGqlClient gql,
  String login,
) async {
  final data = await gql.query(
    operationName: 'PlaybackAccessToken_Template',
    variables: {
      'isLive': true,
      'login': login,
      'isVod': false,
      'vodID': '',
      'playerType': 'site',
    },
    query: r'''
query PlaybackAccessToken_Template($login: String!, $isLive: Boolean!, $vodID: ID!, $isVod: Boolean!, $playerType: String!) {
  streamPlaybackAccessToken(channelName: $login, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isLive) {
    value
    signature
  }
  videoPlaybackAccessToken(id: $vodID, params: {platform: "web", playerBackend: "mediaplayer", playerType: $playerType}) @include(if: $isVod) {
    value
    signature
  }
}''',
  );
  final token = _mapOf((data as Map?)?['streamPlaybackAccessToken']);
  final value = _text(token?['value']);
  final signature = _text(token?['signature']);
  if (value.isEmpty || signature.isEmpty) {
    throw const TwitchGqlException('未获取到播放令牌');
  }
  return TwitchPlaybackToken(value: value, signature: signature);
}

/// usher 主播放列表:token 必须 URL 编码,否则 403/空响应。
Future<String> fetchTwitchMasterPlaylist(
  ParserHttp http, {
  required String login,
  required TwitchPlaybackToken token,
  required String clientId,
}) async {
  final response = await http.get(
    Uri.https('usher.ttvnw.net', '/api/channel/hls/$login.m3u8', {
      'client_id': clientId,
      'token': token.value,
      'sig': token.signature,
      'allow_source': 'true',
      'allow_audio_only': 'true',
      'type': 'any',
    }),
  );
  return utf8.decode(response.bodyBytes);
}

/// 解析 master m3u8:一档画质一条线路,按分辨率降序。
///
/// 丢弃无 `RESOLUTION` 的 `audio_only` 档——直播场景无画面,进入画质列表只会干扰默认选档。
List<StreamQuality> parseTwitchMasterPlaylist(String body) {
  final qualities = <StreamQuality>[];
  final mediaNames = <String, String>{};
  String? pendingAttributes;

  for (final rawLine in const LineSplitter().convert(body)) {
    final line = rawLine.trim();
    if (line.startsWith('#EXT-X-MEDIA:')) {
      final attrs = _parseAttributes(line);
      final group = attrs['GROUP-ID'];
      final name = attrs['NAME'];
      if (group != null && name != null) mediaNames[group] = name;
      continue;
    }
    if (line.startsWith('#EXT-X-STREAM-INF:')) {
      pendingAttributes = line;
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;
    final attrs = _parseAttributes(pendingAttributes ?? '');
    pendingAttributes = null;

    final resolution = attrs['RESOLUTION'] ?? '';
    final height = _heightOf(resolution);
    if (height == 0) continue; // audio_only

    final group = attrs['VIDEO'] ?? '';
    final mediaName = mediaNames[group];
    final isSource = mediaName != null && mediaName.contains('(source)');
    final name = isSource
        ? '原画'
        : (mediaName != null && mediaName.isNotEmpty ? mediaName : _fallbackName(resolution, attrs['FRAME-RATE']));

    qualities.add(
      StreamQuality(
        name: name,
        rate: height,
        lines: [
          StreamLine(
            name: 'HLS',
            url: line,
            format: 'hls',
            headers: const {'Referer': 'https://www.twitch.tv/'},
          ),
        ],
      ),
    );
  }

  qualities.sort((a, b) => b.rate.compareTo(a.rate));
  return qualities;
}

/// 属性行解析:兼容 `KEY=value` 与 `KEY="value, with comma"`。
Map<String, String> _parseAttributes(String line) {
  final result = <String, String>{};
  for (final match in RegExp(r'([A-Z0-9\-]+)=("([^"]*)"|[^,]*)').allMatches(line)) {
    result[match.group(1)!] = (match.group(3) ?? match.group(2) ?? '').trim();
  }
  return result;
}

int _heightOf(String resolution) {
  final parts = resolution.toLowerCase().split('x');
  if (parts.length != 2) return 0;
  return int.tryParse(parts[1]) ?? 0;
}

String _fallbackName(String resolution, String? frameRate) {
  final parts = resolution.split('x');
  if (parts.length != 2) return '自动';
  final fps = double.tryParse(frameRate ?? '') ?? 0;
  final suffix = fps > 30 ? fps.round().toString() : '';
  return '${parts[1]}p$suffix';
}

/// usher 主列表逐档取最高画质时用于展示在线数。
String twitchOnlineText(int viewers) => formatOnlineCount(viewers);

Map<String, dynamic>? _mapOf(Object? value) => value is Map<String, dynamic>
    ? value
    : (value is Map ? Map<String, dynamic>.from(value) : null);

String _text(Object? value) => value?.toString() ?? '';
