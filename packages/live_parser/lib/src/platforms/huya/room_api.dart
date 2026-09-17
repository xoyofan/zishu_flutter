/// 虎牙房间信息:profileRoom 接口、页面流数据、房间状态判定与播放地址签名。
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../http/parser_http.dart';
import '../../utils/header_sanitizer.dart';
import 'anti_code.dart';
import '../douyu/json_utils.dart';
import 'normalize.dart';

const String kHuyaSiteId = 'huya';

/// 虎牙房间状态;契约 [RoomState] 无 replay,replay 归 offline(不可直接播放)。
enum HuyaRoomState { live, replay, offline }

const Map<String, String> kHuyaPcHeaders = {
  'Referer': 'https://www.huya.com/',
};

/// 小程序接口 UA:别名房间页需要它才能返回 ProfileRoom 数据。
const Map<String, String> kHuyaMobileHeaders = {
  'user-agent': 'ios/7.830 (ios 17.0; ; iPhone 15 (A2846/A3089/A3090/A3092))',
  'xweb_xhr': '1',
  'referer': 'https://servicewechat.com/wx74767bf0b684f7d3/301/page-frame.html',
  'accept-language': 'zh-CN,zh;q=0.9',
};

/// 虎牙媒体流(HLS/FLV)请求头。
///
/// 虎牙 CDN 以 Referer/Origin 做防盗链,缺头时地址可能 403 或半开连接。
/// UA 取本 package 解析链路实际使用的 [kDefaultParserUserAgent]:上游有进程级
/// `HuyaSite.playUserAgent`(由远端配置刷新),本 package 未维护该字段,
/// 而**不为头再发一次网络请求**,直接沿用解析期 UA。
Map<String, String> huyaPlaybackHeaders(String roomId) {
  final rid = roomId.trim();
  return sanitizeHeaders({
    'user-agent': kDefaultParserUserAgent,
    'origin': 'https://www.huya.com',
    'referer': rid.isEmpty ? 'https://www.huya.com/' : 'https://www.huya.com/$rid',
  });
}

String httpsHuyaUrl(String text) {
  final value = text.trim();
  if (value.isEmpty) return '';
  if (value.startsWith('//')) return 'https:$value';
  return value.replaceAll('http://', 'https://');
}

/// 别名房间回源小程序页面换取数字房间号。
Future<String> resolveHuyaNumericRoomId(ParserHttp http, String url) async {
  final roomId = huyaRoomIdFromUrl(url);
  if (!isHuyaAliasRoomId(roomId)) return roomId;
  final response = await http.get(Uri.parse(url), headers: kHuyaMobileHeaders);
  final match = RegExp(r'ProfileRoom":(\d+),"sPrivateHost').firstMatch(
    utf8.decode(response.bodyBytes),
  );
  if (match == null) {
    throw ParserHttpException('无法解析虎牙房间号: $url');
  }
  return match.group(1)!;
}

/// mp.huya.com profileRoom:头像、状态、弹幕参数与回退流地址的统一数据源。
Future<Map<String, dynamic>?> fetchHuyaProfileRoomData(ParserHttp http, String roomId) async {
  final response = await http.get(
    Uri.parse(
      'https://mp.huya.com/cache.php?m=Live&do=profileRoom&roomid=$roomId&showSecret=1',
    ),
    headers: kHuyaPcHeaders,
  );
  final payload = jsonMapOf(jsonDecode(utf8.decode(response.bodyBytes)));
  return jsonMapOf(payload['data']).isEmpty ? null : jsonMapOf(payload['data']);
}

bool _isReplayFlag(Object? value) =>
    value == 1 || value == '1' || value == true;

bool _isReplayStatus(String status) => status == 'REPLAY' || status == 'VOD';

bool _hlsLooksReplay(Map<String, dynamic> liveData) {
  final hls = jsonText(liveData['hls'] ?? liveData['hlsUrl']);
  if (hls.isEmpty) return false;
  return hls.contains('livereplay') ||
      hls.contains('al-vod.cdn.huya.com') ||
      hls.contains('/vhuya/clips/');
}

bool _hasFlvStreamList(Map<String, dynamic> data) {
  final stream = jsonMapOf(data['stream']);
  return jsonMapOfList(stream['baseSteamList']).isNotEmpty ||
      jsonMapOfList(stream['baseSteamInfoList']).isNotEmpty;
}

/// 「无 FLV 流」且疑似录播/重播时,需再读页面 TT_ROOM_DATA.isOn 区分真重播与已下播。
bool profileNeedsPageCheck(Map<String, dynamic> data) {
  if (_hasFlvStreamList(data)) return false;
  final liveData = jsonMapOf(data['liveData']);
  final liveStatus = jsonText(data['liveStatus']).toUpperCase();
  final realLiveStatus = jsonText(data['realLiveStatus']).toUpperCase();
  if (_isReplayFlag(liveData['isReplay'])) return true;
  if (_isReplayStatus(liveStatus) || _isReplayStatus(realLiveStatus)) return true;
  if (_hlsLooksReplay(liveData)) return true;
  return false;
}

/// 页面 TT_ROOM_DATA 摘要。
class HuyaPageRoomFlags {
  const HuyaPageRoomFlags({required this.isOn, required this.isReplay});

  final bool isOn;
  final bool isReplay;
}

/// 读取房间页 TT_ROOM_DATA.isOn/isReplay;页面不可达时返回 null。
Future<HuyaPageRoomFlags?> fetchHuyaPageRoomFlags(ParserHttp parserHttp, String roomId) async {
  final http.Response response;
  try {
    response = await http.get(
      Uri.parse('https://www.huya.com/$roomId'),
      headers: kHuyaPcHeaders,
    );
  } on ParserHttpException catch (error) {
    if (error.statusCode != null) return null;
    rethrow;
  }
  final match = RegExp(r'TT_ROOM_DATA\s*=\s*(\{[\s\S]*?\});').firstMatch(
    utf8.decode(response.bodyBytes),
  );
  if (match == null) return null;
  final tt = jsonMapOf(jsonDecode(match.group(1)!));
  return HuyaPageRoomFlags(isOn: tt['isOn'] != null && tt['isOn'] != false, isReplay: tt['isReplay'] == true);
}

/// 状态判定,对齐 SFVideoLive huyaRoomState。
HuyaRoomState huyaRoomState(Map<String, dynamic> data, HuyaPageRoomFlags? page) {
  final liveData = jsonMapOf(data['liveData']);
  final liveStatus = jsonText(data['liveStatus']).toUpperCase();
  final realLiveStatus = jsonText(data['realLiveStatus']).toUpperCase();
  final hasFlv = _hasFlvStreamList(data);

  if (liveStatus == 'OFF' && realLiveStatus == 'OFF') return HuyaRoomState.offline;
  if (page != null && !page.isOn) return HuyaRoomState.offline;

  final replayHint =
      _isReplayFlag(liveData['isReplay']) ||
      _isReplayStatus(liveStatus) ||
      _isReplayStatus(realLiveStatus) ||
      _hlsLooksReplay(liveData);

  if (liveStatus == 'ON' || realLiveStatus == 'ON') {
    if (_isReplayFlag(liveData['isReplay']) || (page?.isReplay ?? false)) {
      return HuyaRoomState.replay;
    }
    return HuyaRoomState.live;
  }

  if (replayHint) {
    if (hasFlv || (page?.isOn ?? false)) return HuyaRoomState.replay;
    return HuyaRoomState.offline;
  }

  if (hasFlv && liveStatus != 'OFF' && realLiveStatus != 'OFF') {
    return HuyaRoomState.live;
  }

  return HuyaRoomState.offline;
}

List<Map<String, dynamic>> jsonMapOfList(Object? value) =>
    value is List ? value.whereType<Map<String, dynamic>>().toList() : const [];

/// 页面流数据:gameLiveInfo + gameStreamInfoList + vMultiStreamInfo。
class HuyaWebStreamData {
  const HuyaWebStreamData({
    required this.gameLiveInfo,
    required this.streamInfoList,
    required this.multiStreamInfo,
  });

  final Map<String, dynamic> gameLiveInfo;
  final List<Map<String, dynamic>> streamInfoList;
  final List<Map<String, dynamic>> multiStreamInfo;

  static HuyaWebStreamData? fromHtml(String html) {
    final match = RegExp(r'stream:\s*(\{"data".*?),"iWebDefaultBitRate"').firstMatch(html);
    if (match == null) return null;
    final decoded = jsonMapOf(jsonDecode('${match.group(1)}}'));
    final first = jsonMapOfList(decoded['data']).isEmpty
        ? const <String, dynamic>{}
        : jsonMapOfList(decoded['data']).first;
    return HuyaWebStreamData(
      gameLiveInfo: jsonMapOf(first['gameLiveInfo']),
      streamInfoList: jsonMapOfList(first['gameStreamInfoList']),
      multiStreamInfo: jsonMapOfList(decoded['vMultiStreamInfo']),
    );
  }
}

/// 拉取房间页并解析流数据;页面缺失流数据返回 null(未开播或不存在)。
Future<HuyaWebStreamData?> fetchHuyaWebStreamData(ParserHttp http, String url) async {
  final response = await http.get(Uri.parse(url), headers: kHuyaPcHeaders);
  return HuyaWebStreamData.fromHtml(utf8.decode(response.bodyBytes));
}

/// 清晰度档位:vMultiStreamInfo 原序;空则单「默认」档。
List<HuyaQualityItem> huyaQualityItems(HuyaWebStreamData data) {
  if (data.multiStreamInfo.isNotEmpty) {
    return [
      for (final item in data.multiStreamInfo)
        HuyaQualityItem(
          name: jsonText(item['sDisplayName']).isEmpty
              ? '档${_intOf(item['iBitRate'])}'
              : jsonText(item['sDisplayName']),
          rate: _intOf(item['iBitRate']),
        ),
    ];
  }
  return const [HuyaQualityItem(name: '默认', rate: 0)];
}

class HuyaQualityItem {
  const HuyaQualityItem({required this.name, required this.rate});

  final String name;
  final int rate;
}

int _intOf(Object? value) => value is num ? value.toInt() : int.tryParse('${value ?? ''}') ?? 0;

/// 线路名:iLineIndex 优先,退回 CDN 类型。
String huyaLineName(Map<String, dynamic> streamInfo) {
  final index = streamInfo['iLineIndex'];
  if (index is num) return '线路${index.toInt()}';
  final cdn = jsonText(streamInfo['sCdnType']);
  return '线路${cdn.isEmpty ? 'CDN' : cdn}';
}

String _ratioSuffix(Object? ratio) {
  final text = '$ratio';
  return ratio == null || ratio == 0 || text == '0' || text.isEmpty ? '' : text;
}

String? buildHuyaHlsUrl(Map<String, dynamic> streamInfo, Object? ratio) {
  final hlsUrl = jsonText(streamInfo['sHlsUrl']);
  final streamName = jsonText(streamInfo['sStreamName']);
  final antiCode = jsonText(streamInfo['sHlsAntiCode']);
  if (hlsUrl.isEmpty || streamName.isEmpty || antiCode.isEmpty) return null;
  final signed = buildHuyaAntiCode(antiCode, streamName);
  final suffix = _ratioSuffix(ratio);
  return httpsHuyaUrl('$hlsUrl/$streamName.m3u8?$signed&ratio=$suffix');
}

String? buildHuyaFlvUrl(Map<String, dynamic> streamInfo, Object? ratio) {
  final flvUrl = jsonText(streamInfo['sFlvUrl']);
  final streamName = jsonText(streamInfo['sStreamName']);
  final suffix = jsonText(streamInfo['sFlvUrlSuffix'] ?? 'flv');
  final antiCode = jsonText(streamInfo['sFlvAntiCode']);
  if (flvUrl.isEmpty || streamName.isEmpty || antiCode.isEmpty) return null;
  final signed = buildHuyaAntiCode(antiCode, streamName);
  final ratioText = _ratioSuffix(ratio);
  return httpsHuyaUrl('$flvUrl/$streamName.$suffix?$signed&ratio=$ratioText');
}

/// 房间页头像等 profile 摘要(带页面复核的三态判定)。
class HuyaProfileBrief {
  const HuyaProfileBrief({required this.avatar, required this.roomState, required this.data});

  final String avatar;
  final HuyaRoomState roomState;
  final Map<String, dynamic>? data;
}

Future<HuyaProfileBrief> fetchHuyaProfileBrief(ParserHttp http, String roomId) async {
  final data = await fetchHuyaProfileRoomData(http, roomId);
  if (data == null) {
    return const HuyaProfileBrief(avatar: '', roomState: HuyaRoomState.offline, data: null);
  }
  final profile = jsonMapOf(data['profileInfo']);
  var roomState = huyaRoomState(data, null);
  if (profileNeedsPageCheck(data)) {
    final flags = await fetchHuyaPageRoomFlags(http, roomId);
    if (flags != null) {
      roomState = huyaRoomState(data, flags);
    }
  }
  return HuyaProfileBrief(
    avatar: httpsHuyaUrl(jsonText(profile['avatar180'] ?? profile['avatar'])),
    roomState: roomState,
    data: data,
  );
}
