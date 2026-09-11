/// 快手房间详情、清晰度与播放地址 API。
///
/// 房间信息藏在页面内联的 `window.__INITIAL_STATE__`(SSR),无需签名接口;
/// 清晰度/线路从 `liveStream.playUrls` 的 adaptationSet 表示中提取。
library;

import 'dart:convert';

import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';

/// 快手播放请求需带 referer(CDN 防盗链)。
const Map<String, String> kKuaishouPlayHeaders = {
  'Referer': 'https://live.kuaishou.com/',
};

/// 房间页/列表页通用请求头。
Map<String, String> kuaishouHeaders({String cookie = ''}) => {
  'User-Agent':
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36',
  'Accept':
      'text/html,application/xhtml+xml,application/xml;q=0.9,'
      'image/webp,image/apng,*/*;q=0.8',
  'Accept-Language': 'zh-CN,zh;q=0.9',
  'Referer': 'https://live.kuaishou.com/',
  if (cookie.trim().isNotEmpty) 'Cookie': cookie.trim(),
};

/// 归一后的快手房间详情。
class KuaishouRoomDetail {
  const KuaishouRoomDetail({
    required this.roomId,
    required this.anchorName,
    required this.avatar,
    required this.title,
    required this.introduction,
    required this.category,
    required this.cover,
    required this.viewers,
    required this.isLive,
    required this.liveStreamId,
    required this.playUrls,
  });

  final String roomId;
  final String anchorName;
  final String avatar;
  final String title;
  final String introduction;
  final String category;
  final String cover;

  /// 在线人数(原始字符串,展示时走 [formatOnlineCount])。
  final String viewers;
  final bool isLive;

  /// 弹幕 feed 需要的直播流 id;未开播时可能为空。
  final String liveStreamId;

  /// `liveStream.playUrls` 原始结构,交给 [parseKuaishouQualities] 解析。
  final Object? playUrls;
}

/// 请求房间页并解析初始状态。
Future<KuaishouRoomDetail> fetchKuaishouRoomDetail(
  ParserHttp http,
  String roomId, {
  String cookie = '',
}) async {
  final response = await http.get(
    Uri.parse(kuaishouSourceUrl(roomId)),
    headers: kuaishouHeaders(cookie: cookie),
  );
  return parseKuaishouInitialState(
    utf8.decode(response.bodyBytes),
    fallbackRoomId: roomId,
  );
}

/// 从房间页 HTML 解析 `window.__INITIAL_STATE__`。
KuaishouRoomDetail parseKuaishouInitialState(
  String html, {
  required String fallbackRoomId,
}) {
  final stateText = RegExp(
    r'window\.__INITIAL_STATE__=(.*?);',
  ).firstMatch(html)?.group(1);
  if (stateText == null || stateText.trim().isEmpty) {
    throw const FormatException('Kuaishou initial state is missing');
  }
  final decoded = jsonDecode(stateText.replaceAll('undefined', 'null'));
  final liveroom = decoded is Map
      ? Map<String, dynamic>.from(decoded['liveroom'] is Map ? decoded['liveroom'] as Map : const {})
      : const <String, dynamic>{};
  final playList = jsonListOf(liveroom['playList']);
  if (playList.isEmpty) {
    throw const FormatException('Kuaishou room metadata is missing');
  }
  final room = _asMap(playList.first);
  final liveStream = _asMap(room['liveStream']);
  final author = _asMap(room['author']);
  final gameInfo = _asMap(room['gameInfo']);
  final live = jsonBool(room['isLiving']);
  final description = jsonText(author['description']).replaceAll('\n', ' ');
  final roomId = jsonText(author['id']).trim();

  return KuaishouRoomDetail(
    roomId: roomId.isEmpty ? fallbackRoomId : roomId,
    anchorName: jsonText(author['name']),
    avatar: httpsKuaishouUrl(author['avatar']),
    title: description,
    introduction: description,
    category: jsonText(gameInfo['name']),
    cover: kuaishouPosterUrl(liveStream['poster']),
    viewers: live ? formatOnlineCount(gameInfo['watchingCount']) : '',
    isLive: live,
    liveStreamId: jsonText(liveStream['id']).trim(),
    playUrls: liveStream['playUrls'],
  );
}

/// 解析 playUrls 为画质档位:优先 AVC;同一档位的多条 CDN 合并为多线路。
List<StreamQuality> parseKuaishouQualities(Object? raw) {
  final descriptors = raw is List ? raw : <Object?>[raw];
  final merged = <String, ({String name, int sort, List<String> urls})>{};

  for (final rawDescriptor in descriptors) {
    if (rawDescriptor is! Map) continue;
    dynamic descriptor = rawDescriptor;
    for (final codec in const ['h264', 'avc', 'hevc', 'h265']) {
      final candidate = _asMap(rawDescriptor)[codec];
      if (_representationsOf(candidate).isNotEmpty) {
        descriptor = candidate;
        break;
      }
    }

    for (final item in _representationsOf(descriptor)) {
      final representation = _asMap(item);
      final url = jsonText(representation['url']).trim();
      if (!url.startsWith('http://') && !url.startsWith('https://')) continue;
      final sort = jsonInt(representation['level']) != 0
          ? jsonInt(representation['level'])
          : jsonInt(representation['bitrate']);

      var rawName = '';
      for (final key in const ['name', 'shortName', 'qualityType']) {
        final candidate = jsonText(representation[key]).trim();
        if (candidate.isNotEmpty) {
          rawName = candidate;
          break;
        }
      }
      if (rawName.isEmpty) rawName = sort > 0 ? '清晰度 $sort' : '默认';
      final name = kuaishouQualityLabel(rawName);

      final key = '$name\u0000$sort';
      final existing = merged[key];
      if (existing == null) {
        merged[key] = (name: name, sort: sort, urls: [url]);
      } else if (!existing.urls.contains(url)) {
        existing.urls.add(url);
      }
    }
  }

  final qualities = merged.values
      .map(
        (entry) => StreamQuality(
          name: entry.name,
          rate: entry.sort,
          lines: [
            for (var i = 0; i < entry.urls.length; i++)
              StreamLine(
                name: '线路 ${i + 1}',
                url: entry.urls[i],
                format: entry.urls[i].toLowerCase().contains('.m3u8')
                    ? 'hls'
                    : 'flv',
                headers: kKuaishouPlayHeaders,
              ),
          ],
        ),
      )
      .toList(growable: false);
  qualities.sort((a, b) => b.rate.compareTo(a.rate));
  return qualities;
}

/// 清晰度名归一:已是中文原样保留,常见英文 token 映射为中文。
String kuaishouQualityLabel(String rawName) {
  final raw = rawName.trim();
  if (raw.isEmpty) return '默认';
  if (RegExp(r'[\u3400-\u9fff]').hasMatch(raw)) return raw;
  final token = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '');
  return switch (token) {
    'original' || 'origin' || 'source' => '原画',
    'blue' || 'bluray' || 'blueray' => '蓝光',
    'uhd' || 'super' || 'superhd' || 'fullhd' || 'fhd' => '超清',
    'hd' || 'high' => '高清',
    'sd' || 'standard' || 'medium' => '标清',
    'low' || 'ld' || 'smooth' || 'fluent' => '流畅',
    'auto' => '自动',
    _ => raw,
  };
}

List<Object?> _representationsOf(Object? descriptor) {
  final map = _asMap(descriptor);
  if (map.isEmpty) return const [];
  final adaptationSet = _asMap(map['adaptationSet']);
  final representations = adaptationSet['representation'] ?? map['representation'];
  return jsonListOf(representations);
}

Map<String, dynamic> _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
