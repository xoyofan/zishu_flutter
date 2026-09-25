/// 抖音关注列表导入:分页读取当前账号关注的用户,转换为统一房间摘要。
library;

import 'dart:convert';
import 'dart:math';

import '../../models/models.dart';
import '../douyu/json_utils.dart';
import 'ab_sign.dart';
import 'normalize.dart';
import 'room_api.dart';

const String _kDouyinWebUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/151.0.0.0 Safari/537.36';

class DouyinFollowImportProgress {
  const DouyinFollowImportProgress({
    required this.page,
    required this.imported,
    this.total = 0,
  });

  final int page;
  final int imported;
  final int total;
}

/// 拉取当前抖音账号的全部关注用户。
///
/// 关注接口与直播状态接口分开:前者用于导入 700 多条关注,后者只返回
/// 当前正在直播的关注。接口按 max_time 顺序游标分页,不并发请求。
Future<List<RoomSummary>> fetchDouyinFollowingAnchors(
  DouyinClient client, {
  void Function(DouyinFollowImportProgress progress)? onProgress,
}) async {
  final cookie = await client.sessionCookie();
  final secUid = await _fetchDouyinSecUid(client, cookie);
  if (secUid.isEmpty) {
    throw StateError('无法获取抖音当前账号 sec_uid');
  }

  final rooms = <RoomSummary>[];
  final seen = <String>{};
  var offset = 0;
  var total = 0;
  var sourceType = 2;
  onProgress?.call(const DouyinFollowImportProgress(page: 0, imported: 0));

  for (var page = 0; page < 500; page++) {
    final json = await _signedDouyinGet(
      client,
      path: '/aweme/v1/web/user/following/list/',
      cookie: cookie,
      referer: 'https://www.douyin.com/user/$secUid',
      params: <String, String>{
        ..._douyinWebBaseParams(cookie),
        'sec_user_id': secUid,
        'max_time': '0',
        'min_time': '0',
        'offset': '$offset',
        'count': '50',
        'source_type': '$sourceType',
        'address_book_access': '2',
        'gps_access': '1',
        'is_top': '0',
        'msToken': _cookiePart(cookie, 'msToken').isEmpty
            ? randomDouyinMsToken(184)
            : _cookiePart(cookie, 'msToken'),
      },
    );
    if (jsonInt(json['status_code']) != 0) {
      throw StateError('抖音关注列表获取失败');
    }

    _collectFollowingRooms(json, rooms, seen);
    total = jsonInt(json['total']);
    onProgress?.call(
      DouyinFollowImportProgress(
        page: page + 1,
        imported: rooms.length,
        total: total,
      ),
    );
    final hasMore = jsonBool(json['has_more'] ?? json['hasMore']);
    if (!hasMore) break;
    final nextOffset = jsonInt(json['offset']);
    offset = nextOffset > offset ? nextOffset : offset + 50;
    sourceType = 1;
  }
  return rooms;
}

Map<String, String> _douyinWebBaseParams(String cookie) {
  final verifyFp = _buildVerifyFp(cookie);
  return <String, String>{
    'device_platform': 'webapp',
    'aid': '6383',
    'channel': 'channel_pc_web',
    'pc_client_type': '1',
    'pc_libra_divert': 'Windows',
    'support_h265': '1',
    'support_dash': '0',
    'webcast_sdk_version': '170400',
    'webcast_version_code': '170400',
    'version_code': '170400',
    'version_name': '17.4.0',
    'cookie_enabled': 'true',
    'screen_width': '1920',
    'screen_height': '1080',
    'browser_language': 'zh-CN',
    'browser_platform': 'Win32',
    'browser_name': 'Chrome',
    'browser_version': '151.0.0.0',
    'browser_online': 'true',
    'engine_name': 'Blink',
    'engine_version': '151.0.0.0',
    'os_name': 'Windows',
    'os_version': '10',
    'cpu_core_num': '16',
    'device_memory': '16',
    'platform': 'PC',
    'downlink': '10',
    'effective_type': '4g',
    'round_trip_time': '50',
    'webid': _buildWebId(cookie),
    'verifyFp': verifyFp,
    'fp': verifyFp,
  };
}

Future<Map<String, dynamic>> _signedDouyinGet(
  DouyinClient client, {
  required String path,
  required String cookie,
  required String referer,
  required Map<String, String> params,
}) async {
  final query = serializeDouyinQuery(
    params.entries.map((entry) => MapEntry(entry.key, entry.value)).toList(),
  );
  final signature = douyinAbSign(query, _kDouyinWebUserAgent);
  final uri = Uri.parse(
    'https://www.douyin.com$path?$query&a_bogus=${Uri.encodeComponent(signature)}',
  );
  final response = await client.parserHttp.get(
    uri,
    headers: {
      ...douyinPcHeaders(referer: referer, cookie: cookie),
      'User-Agent': _kDouyinWebUserAgent,
      'Accept': 'application/json, text/plain, */*',
    },
  );
  final decoded = jsonDecode(utf8.decode(response.bodyBytes));
  if (decoded is! Map) {
    throw const FormatException('抖音接口返回了非对象 JSON');
  }
  return Map<String, dynamic>.from(decoded);
}

Future<String> _fetchDouyinSecUid(DouyinClient client, String cookie) async {
  try {
    final json = await _signedDouyinGet(
      client,
      path: '/aweme/v1/web/user/profile/self/',
      cookie: cookie,
      referer: 'https://www.douyin.com/',
      params: <String, String>{
        'device_platform': 'webapp',
        'aid': '6383',
      },
    );
    final secUid = _findSecUid(json);
    if (secUid.isNotEmpty) return secUid;
  } catch (_) {
    // profile/self 被限流时继续尝试网页自身使用的 query/user。
  }
  try {
    final json = await _signedDouyinGet(
      client,
      path: '/aweme/v1/web/query/user/',
      cookie: cookie,
      referer: 'https://www.douyin.com/',
      params: <String, String>{
        'device_platform': 'webapp',
        'aid': '6383',
      },
    );
    final secUid = _findSecUid(json);
    if (secUid.isNotEmpty) return secUid;
  } catch (_) {
    // query/user 也可能被限流,继续尝试关注页 HTML。
  }
  try {
    final response = await client.parserHttp.get(
      Uri.parse('https://www.douyin.com/follow'),
      headers: douyinPcHeaders(cookie: cookie),
    );
    final html = utf8.decode(response.bodyBytes);
    final match = RegExp(
      r'<script[^>]+(?:id="RENDER_DATA"|id="SIGI_STATE")[^>]*>(.*?)</script>',
      dotAll: true,
    ).firstMatch(html);
    if (match != null) {
      final encoded = match.group(1) ?? '';
      final decoded = Uri.decodeComponent(encoded);
      final htmlSecUid = _findSecUid(jsonDecode(decoded));
      if (htmlSecUid.isNotEmpty) return htmlSecUid;
    }
  } catch (_) {
    // HTML 页面也可能被风控替换为登录壳,继续走统一错误。
  }
  throw StateError('无法获取抖音当前账号 sec_uid');
}

String _findSecUid(Object? value) {
  if (value is Map) {
    for (final entry in value.entries) {
      if (entry.key == 'sec_uid' || entry.key == 'secUid') {
        final text = entry.value?.toString() ?? '';
        if (text.startsWith('MS4wLjABAAAA')) return text;
      }
    }
    for (final child in value.values) {
      final found = _findSecUid(child);
      if (found.isNotEmpty) return found;
    }
  } else if (value is List) {
    for (final child in value) {
      final found = _findSecUid(child);
      if (found.isNotEmpty) return found;
    }
  }
  return '';
}

void _collectFollowingRooms(
  Object? value,
  List<RoomSummary> rooms,
  Set<String> seen,
) {
  if (value is List) {
    for (final item in value) {
      _collectFollowingRooms(item, rooms, seen);
    }
    return;
  }
  if (value is! Map) return;

  final user = value['user'] is Map ? jsonMapOf(value['user']) : value;
  final roomId = _firstText([
    user['web_rid'],
    user['room_id_str'],
    user['room_id'],
    user['roomId'],
    user['unique_id'],
    user['display_id'],
  ]);
  final nickname = _firstText([user['nickname'], user['nick_name']]);
  if (roomId.isNotEmpty && nickname.isNotEmpty && seen.add(roomId)) {
    rooms.add(
      RoomSummary(
        site: kDouyinSiteId,
        roomId: roomId,
        title: nickname,
        anchorName: nickname,
        cid: '',
        category: '关注',
        online: '',
        cover: _imageUrl(user['avatar_thumb']),
        avatar: _imageUrl(user['avatar_thumb']),
        roomState: RoomState.offline,
      ),
    );
  }
  for (final child in value.values) {
    if (child is Map || child is List) _collectFollowingRooms(child, rooms, seen);
  }
}

String _imageUrl(Object? value) {
  final list = jsonListOf(jsonMapOf(value)['url_list']);
  return list.isEmpty ? '' : httpsDouyinUrl(list.first);
}

String _firstText(Iterable<Object?> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty && text != 'null') return text;
  }
  return '';
}

String _buildVerifyFp(String cookie) {
  final existing = _cookiePart(cookie, 's_v_web_id');
  if (existing.isNotEmpty) return existing;
  final stamp = DateTime.now().millisecondsSinceEpoch.toRadixString(36);
  final random = Random.secure();
  String digits(int count) =>
      List.generate(count, (_) => random.nextInt(10)).join();
  return 'verify_${stamp}_${digits(8)}_${digits(4)}_${digits(4)}'
      '_${digits(4)}_${digits(12)}';
}

String _buildWebId(String cookie) {
  final existing = _cookiePart(cookie, 'webid');
  if (existing.isNotEmpty) return existing;
  final uifid = _cookiePart(cookie, 'UIFID');
  if (uifid.isNotEmpty) return uifid;
  return '${1000000000 + Random.secure().nextInt(2000000000)}';
}

String _cookiePart(String cookie, String name) {
  for (final part in cookie.split(';')) {
    final pair = part.trim().split('=');
    if (pair.length >= 2 && pair.first == name) return pair.skip(1).join('=');
  }
  return '';
}
