/// 抖音搜索:主播(discover)+ 直播间(综搜回退)。
///
/// 需要 www.douyin.com 会话 cookie;自动引导失败时静默返回空结果,
/// 不阻塞其它平台的聚合搜索。
library;

import 'dart:convert';
import 'dart:math';

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import '../../utils/search_helpers.dart';
import '../douyu/json_utils.dart';
import 'ab_sign.dart';
import 'normalize.dart';
import 'room_api.dart';

class DouyinSearchRepository implements SearchRepository {
  DouyinSearchRepository(this._client);

  final DouyinClient _client;
  String? _wwwCookieCache;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final keyword = request.query.trim();
    final limit = request.limit.clamp(1, 20).toInt();
    if (keyword.isEmpty) {
      return const SearchResult(site: kDouyinSiteId, hits: []);
    }

    // type 分流对齐 web(search/douyin.ts:searchDouyinAnchors=discover 主播、
    // searchDouyinRooms=综搜房间,两档互不回退);缺省 null = 主播优先、
    // 房间补位的既有混合行为(向后兼容)。
    final type = request.type;
    final hits = <SearchHit>[];
    if (type == SearchType.rooms) {
      hits.addAll(await _searchRooms(keyword, limit));
    } else if (type == SearchType.anchors) {
      try {
        hits.addAll(await _searchAnchors(keyword, limit));
      } on Object {
        // 主播档 discover 不可用:返回空,不回退房间(对齐 web 单接口语义)。
      }
    } else {
      try {
        hits.addAll(await _searchAnchors(keyword, limit));
      } on Object {
        // discover 不可用时继续房间搜索。
      }
      if (hits.length < limit) {
        hits.addAll(await _searchRooms(keyword, limit - hits.length));
      }
    }
    return SearchResult(
      site: kDouyinSiteId,
      hits: sortSearchHits(keyword, trimSearchHits(hits, limit)),
    );
  }

  Future<String> _wwwCookie() async {
    final cached = _wwwCookieCache;
    if (cached != null) return cached;
    var cookie = await _client.sessionCookie();
    try {
      final response = await _client.parserHttp.get(
        Uri.parse('https://www.douyin.com/'),
        headers: {
          'User-Agent': kDouyinUserAgent,
          'Accept-Language': 'zh-CN,zh;q=0.9',
          'Referer': 'https://www.douyin.com/',
          'Cookie': cookie,
        },
      );
      final setCookie = response.headers['set-cookie'];
      final extra = _parseCookiePairs(setCookie);
      if (extra.isNotEmpty) {
        cookie = '${cookie.trim()}; ${extra.join('; ')}';
      }
    } on Object {
      // 引导失败仍用 live cookie 尝试。
    }
    _wwwCookieCache = cookie;
    return cookie;
  }

  Future<List<SearchHit>> _searchAnchors(String keyword, int limit) async {
    final cookie = await _wwwCookie();
    final msToken = _cookiePart(cookie, 'msToken').isNotEmpty
        ? _cookiePart(cookie, 'msToken')
        : randomDouyinMsToken();
    final verifyFp = _buildVerifyFp(cookie);
    final webid = _buildWebId(cookie);

    final hits = <SearchHit>[];
    for (final channel in const ['aweme_user_web', 'aweme_user_live']) {
      final json = await _discoverRequest(
        _discoverParams(
          keyword: keyword,
          limit: limit,
          channel: channel,
          msToken: msToken,
          verifyFp: verifyFp,
          webid: webid,
          compact: false,
        ),
        cookie: cookie,
      );
      if (json == null) continue;
      final users = _flattenSearchUsers(json);
      for (final user in users) {
        final hit = _mapUserToHit(user);
        if (hit != null) hits.add(hit);
      }
      if (hits.length >= limit) break;
    }

    if (hits.isEmpty) {
      final json = await _discoverRequest(
        _discoverParams(
          keyword: keyword,
          limit: limit,
          channel: 'aweme_user_web',
          msToken: msToken,
          verifyFp: verifyFp,
          webid: webid,
          compact: true,
        ),
        cookie: cookie,
        signed: false,
      );
      if (json != null) {
        for (final user in _flattenSearchUsers(json)) {
          final hit = _mapUserToHit(user);
          if (hit != null) hits.add(hit);
        }
      }
    }
    return hits;
  }

  Map<String, String> _discoverParams({
    required String keyword,
    required int limit,
    required String channel,
    required String msToken,
    required String verifyFp,
    required String webid,
    required bool compact,
  }) {
    final count = '${limit.clamp(5, 20)}';
    if (compact) {
      return {
        'device_platform': 'webapp',
        'aid': '6383',
        'channel': 'channel_pc_web',
        'search_channel': channel,
        'keyword': keyword,
        'search_source': 'normal_search',
        'query_correct_type': '1',
        'is_filter_search': '0',
        'offset': '0',
        'count': count,
        'version_code': '160100',
        'version_name': '16.1.0',
        'msToken': msToken,
      };
    }
    return {
      'device_platform': 'webapp',
      'aid': '6383',
      'channel': 'channel_pc_web',
      'search_channel': channel,
      'keyword': keyword,
      'search_source': channel == 'aweme_user_live'
          ? 'switch_tab'
          : 'normal_search',
      'query_correct_type': '1',
      'is_filter_search': '0',
      'offset': '0',
      'count': count,
      'need_filter_settings': '1',
      'list_type': 'single',
      'update_version_code': '170400',
      'pc_client_type': '1',
      'version_code': '170400',
      'version_name': '17.4.0',
      'cookie_enabled': 'true',
      'screen_width': '1920',
      'screen_height': '1080',
      'browser_language': 'zh-CN',
      'browser_platform': 'Win32',
      'browser_name': 'Chrome',
      'browser_version': '141.0.0.0',
      'browser_online': 'true',
      'engine_name': 'Blink',
      'engine_version': '141.0.0.0',
      'os_name': 'Windows',
      'os_version': '10',
      'cpu_core_num': '16',
      'device_memory': '8',
      'platform': 'PC',
      'msToken': msToken,
      'verifyFp': verifyFp,
      'fp': verifyFp,
      'webid': webid,
    };
  }

  Future<Map<String, dynamic>?> _discoverRequest(
    Map<String, String> params, {
    required String cookie,
    bool signed = true,
  }) async {
    final query = serializeDouyinQuery(
      params.entries.map((entry) => MapEntry(entry.key, entry.value)).toList(),
    );
    final suffix = signed
        ? '&a_bogus=${Uri.encodeComponent(douyinAbSign(query, kDouyinUserAgent))}'
        : '';
    final uri = Uri.parse(
      'https://www.douyin.com/aweme/v1/web/discover/search/?$query$suffix',
    );
    try {
      final response = await _client.parserHttp.get(
        uri,
        headers: {
          ...douyinPcHeaders(referer: 'https://www.douyin.com/', cookie: cookie),
        },
      );
      final text = utf8.decode(response.bodyBytes);
      if (_isCaptchaBody(text)) return null;
      final decoded = jsonDecode(text);
      if (decoded is! Map) return null;
      final json = Map<String, dynamic>.from(decoded);
      final nil = jsonMapOf(json['search_nil_info']);
      final nilType = jsonText(nil['search_nil_type']);
      if (nilType == 'verify_check') return null;
      return json;
    } on Object {
      return null;
    }
  }

  Future<List<SearchHit>> _searchRooms(String keyword, int limit) async {
    final capped = limit.clamp(1, 20);
    final cookie = await _wwwCookie();
    final msToken = _cookiePart(cookie, 'msToken').isNotEmpty
        ? _cookiePart(cookie, 'msToken')
        : randomDouyinMsToken();
    final verifyFp = _buildVerifyFp(cookie);
    final webid = _buildWebId(cookie);

    Map<String, String> params(String searchChannel) => {
      'device_platform': 'webapp',
      'aid': '6383',
      'channel': 'channel_pc_web',
      'search_channel': searchChannel,
      'keyword': keyword,
      'search_source': 'switch_tab',
      'query_correct_type': '1',
      'need_filter_settings': '1',
      'list_type': 'single',
      'offset': '0',
      'count': '$capped',
      'os_version': '10',
      'msToken': msToken,
      'verifyFp': verifyFp,
      'webid': webid,
    };

    final hits = <SearchHit>[];
    final liveItems = await _roomSearchRequest(
      'https://www.douyin.com/aweme/v1/web/live/search/',
      params('aweme_user_live'),
      cookie,
      keyword,
    );
    hits.addAll(parseDouyinRoomSearchItems(liveItems));
    if (hits.length < capped) {
      final generalItems = await _roomSearchRequest(
        'https://www.douyin.com/aweme/v1/web/general/search/stream/',
        params('aweme_live'),
        cookie,
        keyword,
      );
      hits.addAll(parseDouyinRoomSearchItems(generalItems));
    }
    return hits;
  }

  Future<List<Object?>> _roomSearchRequest(
    String endpoint,
    Map<String, String> params,
    String cookie,
    String keyword,
  ) async {
    final query = serializeDouyinQuery(
      params.entries.map((entry) => MapEntry(entry.key, entry.value)).toList(),
    );
    try {
      final response = await _client.parserHttp.get(
        Uri.parse('$endpoint?$query'),
        headers: {
          ...douyinPcHeaders(
            referer:
                'https://www.douyin.com/search/'
                '${Uri.encodeComponent(keyword)}?type=live',
            cookie: cookie,
          ),
        },
      );
      final text = utf8.decode(response.bodyBytes);
      if (_isCaptchaBody(text)) return const [];
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const [];
      final json = Map<String, dynamic>.from(decoded);
      if (jsonInt(json['status_code']) != 0) return const [];
      return jsonListOf(json['data']);
    } on Object {
      return const [];
    }
  }
}

/// 解析直播间搜索条目(兼容 lives/live_info/rawdata 嵌套 JSON)。
List<SearchHit> parseDouyinRoomSearchItems(List<Object?> items) {
  final hits = <SearchHit>[];
  final seen = <String>{};
  for (final raw in items) {
    var item = jsonMapOf(raw);
    var id = _firstId([item['room_id_str'], item['web_rid'], item['id_str']]);
    var owner = jsonMapOf(item['owner']);
    var room = jsonMapOf(item['room']);
    var title = jsonText(room['title']).trim().isNotEmpty
        ? jsonText(room['title']).trim()
        : jsonText(item['title']).trim();
    var status = jsonInt(item['status']);

    final rawDataStr = _firstNonEmptyText([
      jsonMapOf(item['lives'])['rawdata'],
      jsonMapOf(item['live_info'])['rawdata'],
      item['rawdata'],
    ]);
    if (id.isEmpty && rawDataStr.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawDataStr);
        final rd = jsonMapOf(decoded);
        id = _firstId([rd['room_id_str'], rd['web_rid'], rd['id_str']]);
        owner = jsonMapOf(rd['owner']).isEmpty ? owner : jsonMapOf(rd['owner']);
        room = jsonMapOf(rd['room']).isEmpty ? room : jsonMapOf(rd['room']);
        final rdTitle = jsonText(room['title']).trim().isNotEmpty
            ? jsonText(room['title']).trim()
            : jsonText(rd['title']).trim();
        if (rdTitle.isNotEmpty) title = rdTitle;
        if (status == 0) status = jsonInt(rd['status']);
      } on FormatException {
        // rawdata 不是 JSON 时忽略。
      }
    }
    if (id.isEmpty || !seen.add(id)) continue;
    final avatarList = jsonListOf(jsonMapOf(owner['avatar_thumb'])['url_list']);
    final coverList = jsonListOf(jsonMapOf(room['cover'])['url_list']);
    hits.add(
      SearchHit(
        id: id,
        anchor: jsonText(owner['nickname']).trim(),
        title: title,
        avatar: avatarList.isEmpty ? '' : httpsDouyinUrl(avatarList.first),
        cover: coverList.isEmpty ? '' : httpsDouyinUrl(coverList.first),
        state: status == 2 || status == 1
            ? SearchHitState.live
            : SearchHitState.offline,
        category: pickDouyinRoomCategory(item['partition_road_map']),
        online: '',
      ),
    );
  }
  return hits;
}

/// 从 partition_road_map(对象或数组)取首个字符串分类。
String pickDouyinRoomCategory(Object? raw) {
  if (raw is List) {
    for (final item in raw) {
      if (item is String && item.isNotEmpty) return item;
    }
    return '';
  }
  if (raw is Map) {
    for (final value in raw.values) {
      if (value is String && value.isNotEmpty) return value;
    }
  }
  return '';
}

List<Map<String, dynamic>> _flattenSearchUsers(Map<String, dynamic> json) {
  final users = <Map<String, dynamic>>[];
  void push(Object? entry) {
    final map = jsonMapOf(entry);
    if (map.isEmpty) return;
    final info = jsonMapOf(map['user_info']);
    users.add(info.isEmpty ? map : {...map, ...info});
  }

  for (final entry in jsonListOf(json['user_list'])) {
    push(entry);
  }
  for (final block in jsonListOf(json['data'])) {
    final data = jsonMapOf(block);
    for (final entry in jsonListOf(data['user_list'])) {
      push(entry);
    }
    for (final entry in jsonListOf(data['users'])) {
      push(entry);
    }
  }
  return users;
}

SearchHit? _mapUserToHit(Map<String, dynamic> user) {
  final id = _pickSearchUserId(user);
  if (id.isEmpty) return null;
  final live = jsonInt(user['live_status']) == 1;
  final avatarList = jsonListOf(jsonMapOf(user['avatar_thumb'])['url_list']);
  final fans = user['follower_count'];
  return SearchHit(
    id: id,
    anchor: jsonText(user['nickname']).trim(),
    title: _firstNonEmptyText([user['title'], user['nickname']]),
    avatar: avatarList.isEmpty ? '' : httpsDouyinUrl(avatarList.first),
    cover: '',
    state: live ? SearchHitState.live : SearchHitState.offline,
    category: '',
    online: live ? '' : '',
    fans: (fans is num && fans > 0) ? '$fans' : '',
  );
}

String _pickSearchUserId(Map<String, dynamic> user) {
  final candidates = <Object?>[
    user['unique_id'],
    user['display_id'],
    user['web_rid'],
    jsonMapOf(jsonMapOf(user['room_data'])['owner'])['web_rid'],
    user['room_id_str'],
    user['room_id'],
    jsonMapOf(user['room'])['id_str'],
    jsonMapOf(user['room_data'])['id_str'],
  ];
  return _firstId(candidates);
}

String _firstId(List<Object?> values) {
  for (final value in values) {
    final text = jsonText(value).trim();
    if (text.isNotEmpty && text != '0') return text;
  }
  return '';
}

String _firstNonEmptyText(List<Object?> values) {
  for (final value in values) {
    final text = jsonText(value).trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

bool _isCaptchaBody(String text) {
  final trimmed = text.trim();
  return trimmed.isEmpty ||
      trimmed.startsWith('<!DOCTYPE') ||
      trimmed.startsWith('<html') ||
      trimmed.contains('验证码');
}

String _buildVerifyFp(String cookie) {
  final existing = _cookiePart(cookie, 's_v_web_id');
  if (existing.isNotEmpty) return existing;
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  String digits(int n) =>
      List.generate(n, (_) => random.nextInt(10)).join();
  return 'verify_${stamp}_${digits(8)}_${digits(4)}_${digits(4)}'
      '_${digits(4)}_${digits(12)}';
}

String _buildWebId(String cookie) {
  final existing = _cookiePart(cookie, 'webid');
  if (existing.isNotEmpty) return existing;
  final uifid = _cookiePart(cookie, 'UIFID');
  if (uifid.isNotEmpty) return uifid;
  return '${1000000000 + Random.secure().nextInt(7000000001)}';
}

String _cookiePart(String cookie, String name) {
  for (final part in cookie.split(';')) {
    final index = part.indexOf('=');
    if (index <= 0) continue;
    if (part.substring(0, index).trim() == name) {
      return part.substring(index + 1).trim();
    }
  }
  return '';
}

List<String> _parseCookiePairs(String? header) {
  if (header == null || header.trim().isEmpty) return const [];
  final result = <String>[];
  for (final part in header.split(RegExp(r',(?=[^;,=\s]+=)'))) {
    final pair = part.split(';').first.trim();
    if (pair.contains('=')) result.add(pair);
  }
  return result;
}

/// 抖音在线人数(供搜索兜底扫描等场景复用)。
String douyinOnlineText(Map<String, dynamic> room) =>
    formatOnlineCount(douyinOnlineRaw(room));
