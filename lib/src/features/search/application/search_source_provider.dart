/// 搜索数据源 provider:编译开关切换 fixture / 真实解析。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/application/search_source.dart';

/// 与 providers.dart 的 [useRealParser] 同源(均读 `ZISHU_REAL_PARSER`),
/// A12 收口时合并为同一常量,避免两处重复定义产生漂移。默认 false:走 fixture,
/// 保证 widget 测试不依赖公网和站点接口状态。
const bool useRealParserSearch = bool.fromEnvironment(
  'ZISHU_REAL_PARSER',
  defaultValue: false,
);

/// 搜索数据源:开启真实解析时委托 live_parser,否则用 fixture。
final searchSourceProvider = Provider<SearchSource>(
  (ref) => useRealParserSearch
      ? ParserSearchSource()
      : const FixtureSearchSource(),
);
