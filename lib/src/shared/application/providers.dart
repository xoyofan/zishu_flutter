/// 全局 providers:数据源端口注入。G1 接线时把 fixture 换成
/// DirectLiveParserGateway 实现,Widget 与 controller 不变。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'browse_source.dart';
import 'fixture_sources.dart';

/// 栏目浏览数据源(首页/分类/搜索底卡)。
final browseSourceProvider = Provider<BrowseSource>((ref) => const FixtureBrowseSource());

/// 房间解析数据源(播放页)。
final roomSourceProvider = Provider<RoomSource>((ref) => const FixtureRoomSource());
