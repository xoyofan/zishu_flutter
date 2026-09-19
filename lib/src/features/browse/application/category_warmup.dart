/// 分类索引预热:启动后异步逐站拉取各浏览平台的分类索引。
///
/// 用户口径(2026-09-19):「各个平台的分类和映射应该初始打开时异步给预热
/// 好在内存里,这样 Hover 时候就马上显示了。」—— 分类映射(remap 归一表与
/// cross-categories 全量表)是编译期内嵌常量,启动即在内存;本模块只负责
/// **分类索引**(各站分类树,需网络拉取)的预热:`browseCategoriesProvider`
/// 一旦构建,结果会缓存在 provider 与各站 repository 的进程内存缓存中,
/// hover 平台分类浮层时立即命中,不再等网络。
///
/// 设计约束:
/// - **串行逐站**:避免启动期并发请求风暴挤占首页首屏数据;
/// - **失败静默**:预热失败不重试不报错 —— hover 时该站分类 provider 会
///   自然重试拉取,预热只是加速命中而非唯一路径;
/// - 调用方保证延迟到首屏之后(如启动 2s 后),不与本页数据抢带宽。
library;

import 'package:live_parser/live_parser.dart' show CategoryResult;

import '../../../shared/presentation/platform_brands.dart';

/// 异步逐站预热分类索引。
///
/// [fetchCategories] 通常传 `(site) => ref.read(browseCategoriesProvider(site)
/// .future)`;[sites] 为要预热的平台 id 集合(一般取
/// `PlatformBrandCatalog.browsePlatforms` 的 id)。
Future<void> warmupBrowseCategories(
  Future<CategoryResult> Function(String site) fetchCategories,
  Iterable<String> sites,
) async {
  for (final site in sites) {
    try {
      await fetchCategories(site);
    } catch (_) {
      // 预热失败静默:hover 时该站分类 provider 会自行重试拉取。
    }
  }
}

/// 全部支持浏览的平台 id(预热站点集合)。
Iterable<String> browseWarmupSites() sync* {
  for (final brand in PlatformBrandCatalog.browsePlatforms) {
    yield brand.id;
  }
}
