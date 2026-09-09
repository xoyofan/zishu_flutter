/// IPTV 目录浏览与搜索:地区 → 分组两级分类 + 频道名子串搜索。
library;

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import 'channel_repository.dart';


class IptvBrowseRepository implements BrowseRepository {
  IptvBrowseRepository(this._repository);

  final IptvChannelRepository _repository;

  @override
  Future<CategoryResult> fetchCategories(String site) async {
    final snapshot = await _repository.loadAll();

    // country -> (group -> count)
    final regionMap = <String, Map<String, int>>{};
    for (final ch in snapshot.channels) {
      final country = ch.country ?? '未知地区';
      final group = ch.group;
      regionMap.putIfAbsent(country, () => {}).update(group, (n) => n + 1, ifAbsent: () => 1);
    }

    String label(String group, int n) => n > 1 ? '$group ($n)' : group;

    // 全部:跨地区合并分组
    final totals = <String, int>{};
    for (final counts in regionMap.values) {
      counts.forEach((group, n) => totals[group] = (totals[group] ?? 0) + n);
    }
    final groups = <CategoryGroup>[
      CategoryGroup(
        id: '_all',
        name: '全部',
        items: [
          for (final entry in totals.entries.sortedByLocale())
            CategoryItem(cid: entry.key, name: label(entry.key, entry.value), pic: ''),
        ],
      ),
    ];

    final regions = regionMap.keys.toList()..sort(compareZh);
    for (final country in regions) {
      final counts = regionMap[country]!;
      groups.add(
        CategoryGroup(
          id: country,
          name: country,
          items: [
            for (final entry in counts.entries.sortedByLocale())
              CategoryItem(
                cid: '$country:${entry.key}',
                name: label(entry.key, entry.value),
                pic: '',
              ),
          ],
        ),
      );
    }
    return CategoryResult(site: kIptvSiteId, groups: groups);
  }

  @override
  Future<RoomListResult> fetchRooms(RoomListRequest request) async {
    final snapshot = await _repository.loadAll();
    final filtered = filterByCid(snapshot.channels, request.cid ?? '');
    final page = request.page < 1 ? 1 : request.page;
    final start = (page - 1) * request.limit;
    final end = start + request.limit;
    final rooms = [
      for (final channel in filtered.sublist(
        start.clamp(0, filtered.length),
        end.clamp(0, filtered.length),
      ))
        _toRoom(channel),
    ];
    return RoomListResult(rooms: rooms, page: page, hasMore: end < filtered.length);
  }
}

/// cid → 频道过滤:`地区:分组` / 裸分组名(v1 兼容)/ `_all` 与空为全量。
List<IptvTaggedChannel> filterByCid(List<IptvTaggedChannel> channels, String cid) {
  if (cid.isEmpty || cid == '_all') return channels;
  final colon = cid.indexOf(':');
  if (colon == -1) {
    return channels.where((c) => c.group == cid).toList();
  }
  final region = cid.substring(0, colon);
  final group = cid.substring(colon + 1);
  return channels.where((c) {
    if ((c.country ?? '未知地区') != region) return false;
    return group.isEmpty ? true : c.group == group;
  }).toList();
}

RoomSummary _toRoom(IptvTaggedChannel channel) {
  return RoomSummary(
    site: kIptvSiteId,
    roomId: channel.id,
    title: channel.name,
    anchorName: channel.name,
    cid: channel.group,
    category: channel.group,
    online: 'TV',
    cover: channel.logo,
  );
}

extension on Iterable<MapEntry<String, int>> {
  Iterable<MapEntry<String, int>> sortedByLocale() =>
      toList()..sort((a, b) => compareZh(a.key, b.key));
}

int compareZh(String a, String b) => a.compareTo(b);
