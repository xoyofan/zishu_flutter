/// engine barrel —— ui 只允许 import 本文件，禁止深入 engine 内部路径。
///
/// engine = 解析（streaming-server 客户端）+ 播放 + 弹幕数据面。
library;

export 'contracts/room_models.dart';
export 'contracts/browse_models.dart';
export 'remote/stream_api_client.dart';
