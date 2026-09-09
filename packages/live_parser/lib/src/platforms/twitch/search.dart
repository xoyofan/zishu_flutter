/// Twitch 搜索:GQL searchFor 的频道(主播)检索。
library;

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import '../../utils/format_online.dart';
import 'gql.dart';
import 'normalize.dart';

class TwitchSearchRepository implements SearchRepository {
  TwitchSearchRepository(this._gql);

  final TwitchGqlClient _gql;

  @override
  Future<SearchResult> search(SearchRequest request) async {
    final data = await _gql.query(
      operationName: 'SearchResultsPage_SearchResults',
      variables: {'query': request.query},
      query: r'''
query SearchResultsPage_SearchResults($query: String!) {
  searchFor(userQuery: $query, platform: "web") {
    channels {
      edges {
        item {
          ... on User {
            id
            login
            displayName
            profileImageURL(width: 300)
            stream { id title viewersCount game { id name } previewImageURL }
          }
        }
      }
    }
  }
}''',
    );

    final channels = _mapOf((data as Map?)?['searchFor'])?['channels'];
    final edges = _mapOf(channels)?['edges'];
    final hits = <SearchHit>[];
    if (edges is List) {
      for (final edge in edges) {
        final user = _mapOf(_mapOf(edge)?['item']);
        if (user == null) continue;
        final login = _text(user['login']);
        if (login.isEmpty) continue;
        final stream = _mapOf(user['stream']);
        hits.add(
          SearchHit(
            id: login,
            anchor: _text(user['displayName']).isNotEmpty
                ? _text(user['displayName'])
                : login,
            title: _text(stream?['title']),
            avatar: fillTwitchImageTemplate(
              _text(user['profileImageURL']),
              width: 300,
              height: 300,
            ),
            cover: fillTwitchImageTemplate(_text(stream?['previewImageURL'])),
            state: stream == null ? SearchHitState.offline : SearchHitState.live,
            category: _text(_mapOf(stream?['game'])?['name']),
            online: formatOnlineCount(stream?['viewersCount']),
          ),
        );
        if (hits.length >= request.limit) break;
      }
    }
    return SearchResult(site: kTwitchSiteId, hits: hits);
  }
}

Map<String, dynamic>? _mapOf(Object? value) => value is Map<String, dynamic>
    ? value
    : (value is Map ? Map<String, dynamic>.from(value) : null);

String _text(Object? value) => value?.toString() ?? '';
