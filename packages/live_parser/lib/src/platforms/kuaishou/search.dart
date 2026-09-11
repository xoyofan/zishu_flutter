/// 快手搜索:平台未开放主播/房间搜索(pure_live 同口径仅能搜分类),
/// 这里返回空结果而不是抛错,保证搜索页选中快手时是「无结果」而非失败态。
library;

import '../../contracts/contracts.dart';
import '../../models/models.dart';
import 'normalize.dart';

class KuaishouSearchRepository implements SearchRepository {
  const KuaishouSearchRepository();

  @override
  Future<SearchResult> search(SearchRequest request) async =>
      SearchResult(site: kKuaishouSiteId, hits: const []);
}
