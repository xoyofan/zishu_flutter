/// 全局 providers:数据源端口注入。G1 接线时把 fixture 换成
/// DirectLiveParserGateway 实现,Widget 与 controller 不变。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/user/application/platform_credentials_provider.dart';
import 'browse_source.dart';
import 'fixture_sources.dart';
import 'parser_sources.dart';

/// 通过 `--dart-define=ZISHU_REAL_PARSER=true` 启用真实 live_parser。
/// 默认 fixture，避免 widget 测试和离线开发依赖公网。
const bool useRealParser = bool.fromEnvironment(
  'ZISHU_REAL_PARSER',
  defaultValue: false,
);

/// 栏目浏览数据源(首页/分类/搜索底卡)。
final browseSourceProvider = Provider<BrowseSource>((ref) {
  if (!useRealParser) return const FixtureBrowseSource();
  final cookie = ref.watch(
    platformCredentialsProvider.select(
      (state) => state.credentialFor('douyin').value,
    ),
  );
  return ParserBrowseSource(douyinCookie: cookie);
});

/// 房间解析数据源(播放页)。
final roomSourceProvider = Provider<RoomSource>((ref) {
  if (!useRealParser) return const FixtureRoomSource();
  final cookie = ref.watch(
    platformCredentialsProvider.select(
      (state) => state.credentialFor('douyin').value,
    ),
  );
  return ParserRoomSource(douyinCookie: cookie);
});

/// 房间状态刷新能力:真实解析源实现 [RoomRefresher] 时暴露;
/// fixture 源不实现 → null,关注列表保持「样例数据、零网络」的既有行为
/// (定时轮询件也据此不建 timer)。
final roomRefresherProvider = Provider<RoomRefresher?>((ref) {
  final source = ref.watch(roomSourceProvider);
  return source is RoomRefresher ? source : null;
});

/// 关注直播批量快照源;当前由真实解析源按平台能力提供。
final followLiveRefresherProvider = Provider<FollowLiveRefresher?>((ref) {
  final source = ref.watch(roomSourceProvider);
  if (source is FollowLiveRefresher) {
    return source as FollowLiveRefresher;
  }
  return null;
});

/// 平台关注列表导入源;真实解析源按平台能力提供。
final followImportSourceProvider = Provider<FollowImportSource?>((ref) {
  final source = ref.watch(roomSourceProvider);
  if (source is FollowImportSource) return source as FollowImportSource;
  return null;
});
