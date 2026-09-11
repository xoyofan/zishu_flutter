/// YouTube 直播浏览:抓取 /live、/gaming、/music、/news 页面内嵌 videoId。
library;

import 'dart:convert';

import '../../contracts/contracts.dart';
import '../../http/parser_http.dart';
import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';
import 'room_api.dart';

const List<({String cid, String name})> kYoutubeCategories = [
  (cid: 'live', name: '正在直播'),
  (cid: 'gaming', name: '游戏'),
  (cid: 'music', name: '音乐'),
  (cid: 'news', name: '新闻'),
];

class YoutubeBrowseRepository implements BrowseRepository {
  YoutubeBrowseRepository(this._http);

  final ParserHttp _http;

  @override
  Future<CategoryResult> fetchCategories(String site) async => CategoryResult(
    site: kYoutubeSiteId,
    groups: [
      CategoryGroup(
        id: '',
        name: '',
        items: [
          for (final category in kYoutubeCategories)
            CategoryItem(cid: category.cid, name: category.name, pic: ''),
        ],
      ),
    ],
  );

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final cid = request.cid ?? '';
    final page = request.page < 1 ? 1 : request.page;
    final limit = request.limit.clamp(1, 60);
    final rooms = await fetchYoutubeLiveRooms(_http, cid: cid);
    final start = (page - 1) * limit;
    final sliced = start >= rooms.length
        ? const <RoomSummary>[]
        : rooms.sublist(start, (start + limit).clamp(0, rooms.length));
    return RoomListResult(
      rooms: sliced,
      page: page,
      hasMore: start + limit < rooms.length,
    );
  }
}

/// 抓取指定 YouTube 直播页并归一为房间摘要。
///
/// 优先解析 `ytInitialData`(videoRenderer 与标题一一对应);失败才退回
/// 正则扫描(正则的标题匹配可能挂到相邻视频上)。
Future<List<RoomSummary>> fetchYoutubeLiveRooms(
  ParserHttp http, {
  required String cid,
}) async {
  final path = switch (cid) {
    'gaming' => '/gaming',
    'music' => '/music',
    'news' => '/news',
    _ => '/live',
  };
  final categoryName = _categoryLabel(cid);
  try {
    final response = await http.get(
      Uri.parse('https://www.youtube.com$path'),
      headers: youtubePageHeaders(),
    );
    final html = utf8.decode(response.bodyBytes);
    final fromJson = _roomsFromInitialData(html, categoryName);
    if (fromJson.isNotEmpty) return fromJson;
    return _roomsFromRegex(html, categoryName);
  } on Object {
    return const [];
  }
}

List<RoomSummary> _roomsFromInitialData(String html, String categoryName) {
  final data = extractJsonObjectAfter(html, 'ytInitialData');
  if (data == null) return const [];
  final renderers = <Map<String, dynamic>>[];
  _collectVideoRenderers(data, renderers);
  final seen = <String>{};
  final rooms = <RoomSummary>[];
  for (final renderer in renderers) {
    final videoId = '${renderer['videoId'] ?? ''}'.trim();
    if (!isValidYoutubeVideoId(videoId) || !seen.add(videoId)) continue;
    final title = _runsText(renderer['title']) ?? '';
    final thumbnails = jsonListOf(jsonMapOf(renderer['thumbnail'])['thumbnails']);
    final cover = thumbnails.isEmpty
        ? 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg'
        : '${jsonMapOf(thumbnails.last)['url'] ?? ''}';
    rooms.add(
      RoomSummary(
        site: kYoutubeSiteId,
        roomId: videoId,
        title: title,
        anchorName: '',
        cid: videoId,
        category: categoryName,
        online: _runsText(renderer['viewCountText']) ?? '',
        cover: cover,
      ),
    );
  }
  return rooms;
}

void _collectVideoRenderers(Object? node, List<Map<String, dynamic>> out) {
  if (out.length > 200) return;
  if (node is List) {
    for (final item in node) {
      _collectVideoRenderers(item, out);
    }
    return;
  }
  if (node is Map) {
    final renderer = node['videoRenderer'];
    if (renderer is Map) out.add(Map<String, dynamic>.from(renderer));
    for (final value in node.values) {
      _collectVideoRenderers(value, out);
    }
  }
}

String? _runsText(Object? raw) {
  final map = jsonMapOf(raw);
  final simple = map['simpleText'];
  if (simple is String && simple.isNotEmpty) return simple;
  final runs = jsonListOf(map['runs']);
  final buffer = StringBuffer();
  for (final run in runs) {
    buffer.write('${jsonMapOf(run)['text'] ?? ''}');
  }
  final text = buffer.toString();
  return text.isEmpty ? null : text;
}

List<RoomSummary> _roomsFromRegex(String html, String categoryName) {
  final seen = <String>{};
  final rooms = <RoomSummary>[];
  for (final match in RegExp(
    r'"videoId":"([A-Za-z0-9_-]{11})"',
  ).allMatches(html)) {
    final videoId = match.group(1)!;
    if (!seen.add(videoId)) continue;
    rooms.add(
      RoomSummary(
        site: kYoutubeSiteId,
        roomId: videoId,
        title: '',
        anchorName: '',
        cid: videoId,
        category: categoryName,
        online: '',
        cover: 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg',
      ),
    );
  }
  return rooms;
}

String _categoryLabel(String cid) => switch (cid) {
  'gaming' => '游戏',
  'music' => '音乐',
  'news' => '新闻',
  _ => '正在直播',
};
