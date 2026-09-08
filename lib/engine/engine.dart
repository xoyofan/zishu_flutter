/// engine barrel —— ui 只允许 import 本文件，禁止深入 engine 内部路径。
///
/// engine = 解析（streaming-server 客户端）+ 播放 + 弹幕数据面。
library;

export 'contracts/room_models.dart';
export 'contracts/browse_models.dart';
export 'remote/stream_api_client.dart';
export 'remote/remote_site_source.dart';
export 'sites/live_site.dart';
export 'sites/live_danmaku.dart';
export 'sites/models/live_room.dart';
export 'sites/models/live_area.dart';
export 'sites/models/live_category.dart';
export 'sites/models/live_play_quality.dart';
export 'sites/models/live_anchor_item.dart';
export 'sites/models/live_message.dart';
export 'sites/site_registry.dart';
export 'remote/remote_danmaku_source.dart';
export 'danmaku/danmaku_message.dart';
export 'danmaku/danmaku_channel.dart';
export 'danmaku/danmaku_channel_resolver.dart';
export 'playback/web_video_player_adapter.dart';
export 'playback/proxy_urls.dart';
export 'playback/web_player_backend.dart';
