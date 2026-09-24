/// 虎牙超粉(SideHeader 第 3 列 svip tone「超粉」)真机探针。
///
/// 目的:用真实虎牙房间验证 `wupui/getSuperFansInfo` +
/// `wupui/getSuperFansRankPanel` 两个 wup 请求(见
/// `lib/src/platforms/huya/huya_wup.dart`)在线上可用,并把
/// `RoomSummary.diamondFans` 的真实取值打出来(不伪造:
/// 失败/为 0 一律打印「(空)」)。
///
/// 运行:`dart run tool/_probe_huya_superfans.dart [roomId ...]`
/// 默认从虎牙推荐列表取前 3 个在播房间;虎牙是国内站点,直连不走代理。
library;

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:live_parser/live_parser.dart';
import 'package:live_parser/src/platforms/huya/huya_site.dart';
import 'package:live_parser/src/platforms/huya/huya_wup.dart';
import 'package:live_parser/src/platforms/huya/room_api.dart';
import 'package:live_parser/src/platforms/douyu/json_utils.dart';

/// 单步 HTTP 超时(探针层兜底,避免无响应时挂死)。
const Duration _kStepTimeout = Duration(seconds: 20);

/// 整轮探测的总时间上限。
const Duration _kTotalBudget = Duration(seconds: 120);

String _hex(Uint8List bytes, {int limit = 4096}) {
  final head = bytes.length <= limit ? bytes : bytes.sublist(0, limit);
  return head.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

/// 包一层显式超时:超时归为「未取到数据」,不重试。
Future<T> _withTimeout<T>(Future<T> future, String label) => future.timeout(
  _kStepTimeout,
  onTimeout: () => throw TimeoutException(label),
);

Future<List<String>> _pickLiveRooms(int limit) async {
  final registry = buildSiteRegistry();
  final browse = registry['huya']!.browse;
  if (browse == null) return const [];
  final list = await browse.fetchRooms(
    RoomListRequest(site: 'huya', page: 1, limit: limit),
  );
  for (final room in list.rooms) {
    stdout.writeln(
      'browse: ${room.roomId}「${room.anchorName}」online=${room.audience}',
    );
  }
  return [for (final room in list.rooms) room.roomId];
}

Future<void> _probeRoom(String roomId) async {
  final parserHttp = ParserHttp();
  final wup = HuyaWupClient();
  try {
    final rid = await _withTimeout(
      resolveHuyaNumericRoomId(parserHttp, roomId),
      'resolveHuyaNumericRoomId($roomId)',
    );
    final profile = await _withTimeout(
      fetchHuyaProfileRoomData(parserHttp, rid),
      'fetchHuyaProfileRoomData($rid)',
    );
    final liveData = profile == null ? const {} : jsonMapOf(profile['liveData']);
    final profileInfo = profile == null
        ? const {}
        : jsonMapOf(profile['profileInfo']);
    final presenterUid =
        int.tryParse('${profileInfo['uid'] ?? liveData['uid'] ?? ''}') ?? 0;
    final channelId = int.tryParse(
      '${liveData['liveChannel'] ?? liveData['channel'] ?? ''}',
    );
    stdout.writeln(
      '\n== 房间 $rid ==\n'
      'presenterUid=$presenterUid channelId=${channelId ?? 0}',
    );
    if (presenterUid <= 0) {
      stdout.writeln('  无 presenterUid,跳过 wup');
      return;
    }

    final info = await _withTimeout(
      wup.fetchSuperFansInfo(
        presenterUid: presenterUid,
        channelId: channelId ?? presenterUid,
      ),
      'getSuperFansInfo($rid)',
    );
    stdout.writeln(
      'getSuperFansInfo  : ${info == null ? 'null(请求失败/解码失败)' : ''}'
      '${info == null ? '' : 'iSuperFansNum=${info.superFansNum} '
          'iYearSuperFansNum=${info.yearSuperFansNum} total=${info.total} '
          '(可信=${isPlausibleHuyaSuperFanCount(info.total, presenterUid)})'}',
    );
    final panel = await _withTimeout(
      wup.fetchSuperFansRankPanel(presenterUid: presenterUid),
      'getSuperFansRankPanel($rid)',
    );
    stdout.writeln(
      'getSuperFansRankPanel: ${panel == null ? 'null(请求失败/解码失败)' : ''}'
      '${panel == null ? '' : 'iNum=${panel.num} iPlusNum=${panel.plusNum} '
          'total=${panel.total} '
          '(可信=${isPlausibleHuyaSuperFanCount(panel.total, presenterUid)})'}',
    );
    final count = await wup.fetchSuperFanCount(
      presenterUid: presenterUid,
      channelId: channelId ?? presenterUid,
    );
    final vip = await wup.fetchVipBarCount(
      presenterUid: presenterUid,
      channelId: channelId ?? presenterUid,
    );
    stdout.writeln(
      '贵宾(wup 原始)=${vip ?? 'null'}  超粉(wup 原始)=${count ?? 'null'}',
    );

    // 走完整 refreshRoomSummary:真实展示口径(失败/为 0 为空串)。
    final resolver = HuyaRoomResolver(HuyaClient());
    try {
      final summary = await _withTimeout(
        resolver.refreshRoomSummary(RoomRequest(site: 'huya', roomIdOrUrl: rid)),
        'refreshRoomSummary($rid)',
      );
      stdout.writeln(
        'refreshRoomSummary: state=${summary.roomState.name} '
        'audience=${summary.audience ?? '(空)'} '
        'vip=${summary.vip ?? '(空)'} '
        'svip=${summary.svip ?? '(空)'} '
        'followers=${summary.followers ?? '(空)'}',
      );
    } catch (error) {
      stdout.writeln('refreshRoomSummary 失败: $error');
    }

    // 供 golden 复用:真实响应报文(十六进制)。
    for (final (label, request) in <(String, Uint8List)>[
      (
        'info',
        buildSuperFansInfoRequest(
          presenterUid: presenterUid,
          channelId: channelId ?? presenterUid,
          requestId: 12345,
        ),
      ),
      (
        'panel',
        buildSuperFansRankPanelRequest(
          presenterUid: presenterUid,
          requestId: 12345,
        ),
      ),
    ]) {
      final raw = await _withTimeout(_rawResponse(request), 'raw $label($rid)');
      if (raw != null) {
        stdout.writeln('$label response hex(${raw.length}B)=${_hex(raw)}');
      }
    }
  } finally {
    parserHttp.close();
    wup.close();
  }
}

/// 直连抓一次原始响应报文(仅供探针记录 golden,golden 由人工确认后落测试)。
Future<Uint8List?> _rawResponse(Uint8List body) async {
  final client = http.Client();
  try {
    final response = await client
        .post(
          Uri.parse(kHuyaWupUrl),
          headers: kHuyaWupHeaders,
          body: body,
        )
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      stdout.writeln('raw wup HTTP ${response.statusCode}');
      return null;
    }
    return response.bodyBytes;
  } on Exception catch (error) {
    stdout.writeln('raw wup 异常: $error');
    return null;
  } finally {
    client.close();
  }
}

Future<void> main(List<String> args) async {
  final clock = Stopwatch()..start();
  final rooms = args.isNotEmpty
      ? args.take(3).toList()
      : await _pickLiveRooms(3).timeout(
          _kStepTimeout,
          onTimeout: () => const <String>[],
        );
  if (rooms.isEmpty) {
    stdout.writeln('没有可探测的房间');
    return;
  }
  for (final roomId in rooms.take(3)) {
    if (clock.elapsed > _kTotalBudget) {
      stdout.writeln('超过总时间预算 ${_kTotalBudget.inSeconds}s,停止');
      break;
    }
    try {
      await _probeRoom(roomId);
    } on Exception catch (error) {
      stdout.writeln('\n== 房间 $roomId 探测失败: $error');
    }
  }
  stdout.writeln('\n== done(${clock.elapsedMilliseconds}ms) ==');
}
