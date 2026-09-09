/// IPTV 频道搜索:按频道名 / tvg-id 子串匹配全部启用源频道。
library;

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import 'channel_repository.dart';

class IptvSearchRepository implements SearchRepository {
  IptvSearchRepository(this._repository);

  final IptvChannelRepository _repository;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final keyword = request.query.trim().toLowerCase();
    if (keyword.isEmpty) {
      return const SearchResult(site: kIptvSiteId, hits: <SearchHit>[]);
    }
    final snapshot = await _repository.loadAll();
    final hits = <SearchHit>[];
    for (final channel in snapshot.channels) {
      if (!channel.name.toLowerCase().contains(keyword) &&
          !channel.tvgId.toLowerCase().contains(keyword)) {
        continue;
      }
      hits.add(
        SearchHit(
          id: channel.id,
          anchor: channel.name,
          title: channel.name,
          avatar: channel.logo,
          cover: channel.logo,
          state: SearchHitState.live,
          category: channel.group,
          online: 'TV',
        ),
      );
      if (hits.length >= request.limit) break;
    }
    return SearchResult(site: kIptvSiteId, hits: hits);
  }
}
