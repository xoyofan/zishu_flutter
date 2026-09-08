/// 旧 Web 播放适配层公开 API。
///
/// Windows 新 UI 禁止依赖本 barrel；Windows 播放后端放到
/// `lib/platforms/windows/playback/`。
library;

export 'proxy_urls.dart';
export 'web_player_backend.dart';
export 'web_video_player_adapter.dart';
