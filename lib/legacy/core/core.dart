/// 核心解析公开 API。
///
/// 仅导出平台无关的数据契约、站点模型和 streaming-server 客户端。
/// Windows/Web UI 不应深入 import `core/` 内部文件。
library;

export 'contracts/browse_models.dart';
export 'contracts/room_models.dart';
export 'models/danmaku_message.dart';
export 'playback/playback_urls.dart';
export 'remote/remote_site_source.dart';
export 'remote/stream_api_client.dart';
export 'sites/live_danmaku.dart';
export 'sites/live_site.dart';
export 'sites/models/live_anchor_item.dart';
export 'sites/models/live_area.dart';
export 'sites/models/live_category.dart';
export 'sites/models/live_message.dart';
export 'sites/models/live_play_quality.dart';
export 'sites/models/live_room.dart';
export 'sites/site_registry.dart';
