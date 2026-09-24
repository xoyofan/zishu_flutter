// 一次性探针:拉 bilibili 真实房间 resolve,打印画质档位与线路,
// 并检测三类「清晰度重复」:
//   A. availableQualities / streams 内部同名或同 rate 重复;
//   B. 不同档位间线路 URL 完全相同(档位内容重复);
//   C. 菜单数据源(availableQualities)与 streams 档名集合不一致。
import 'package:live_parser/live_parser.dart';

Future<void> main(List<String> args) async {
  final bili = buildSiteRegistry().byId('bilibili')!;
  final String roomId;
  if (args.isNotEmpty) {
    roomId = args.first;
  } else {
    final browse = await bili.browse!.fetchRooms(
      const RoomListRequest(site: 'bilibili'),
    );
    final first = browse.rooms.first;
    roomId = first.roomId;
    // ignore: avoid_print
    print('[browse] first=${first.roomId} category=${first.category} '
        'online=${first.audience}');
  }
  final payload = await bili.resolver.resolveRoom(
    RoomRequest(site: 'bilibili', roomIdOrUrl: roomId),
  );
  final qNames = payload.availableQualities.map((q) => q.name).toList();
  // ignore: avoid_print
  print('[resolve] qualities=$qNames');

  // A. 档位列表自身重复检测。
  final qNameSeen = <String>{};
  for (final name in qNames) {
    if (!qNameSeen.add(name)) {
      // ignore: avoid_print
      print('[DUP-A] availableQualities 重复档名: $name');
    }
  }
  final qRateSeen = <int>{};
  for (final q in payload.availableQualities) {
    if (!qRateSeen.add(q.rate)) {
      // ignore: avoid_print
      print('[DUP-A] availableQualities 重复 rate: ${q.rate}');
    }
  }
  final sNameSeen = <String>{};
  for (final s in payload.streams) {
    if (!sNameSeen.add(s.name)) {
      // ignore: avoid_print
      print('[DUP-A] streams 重复档名: ${s.name}');
    }
  }

  for (final q in payload.streams) {
    // ignore: avoid_print
    print('[stream] ${q.name} rate=${q.rate} lines=${q.lines.length} '
        'formats=${q.lines.map((l) => l.format).toSet().toList()}');
  }

  // B. 跨档线路 URL 重复检测(两档指向同一路流)。
  final urlOwners = <String, List<String>>{};
  for (final s in payload.streams) {
    for (final line in s.lines) {
      urlOwners.putIfAbsent(line.url, () => []).add(s.name);
    }
  }
  urlOwners.forEach((url, owners) {
    if (owners.toSet().length > 1) {
      // ignore: avoid_print
      print('[DUP-B] 同一 URL 被多档共享(${owners.toSet().toList()}): '
          '...${Uri.parse(url).host}${url.length > 80 ? url.substring(url.length - 40) : url}');
    }
  });

  // C. 菜单数据源与 streams 集合一致性。
  final streamNames = payload.streams.map((s) => s.name).toSet();
  for (final option in payload.availableQualities) {
    if (!streamNames.contains(option.name)) {
      // ignore: avoid_print
      print('[DUP-C] availableQualities 中的 ${option.name} 在 streams 缺线路');
    }
  }

  final dupCount = qNames.length - qNames.toSet().length;
  // ignore: avoid_print
  print('[summary] qualities=${qNames.length} unique=${qNames.toSet().length} '
      'streams=${payload.streams.length} dupItems=$dupCount');
}
