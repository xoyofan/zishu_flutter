/// 搜索数据源 provider:编译开关切换 fixture / 真实解析。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/application/providers.dart' show useRealParser;
import '../../../shared/application/search_source.dart';

/// 搜索数据源:开启真实解析时委托 live_parser,否则用 fixture。
///
/// 开关直接复用 [useRealParser](providers.dart,同读 `ZISHU_REAL_PARSER`),
/// 不再单独定义 `useRealParserSearch`——两处重复定义会产生漂移
/// (A1 分支原留 TODO,随本次合并落掉)。
final searchSourceProvider = Provider<SearchSource>(
  (ref) => useRealParser ? ParserSearchSource() : const FixtureSearchSource(),
);
