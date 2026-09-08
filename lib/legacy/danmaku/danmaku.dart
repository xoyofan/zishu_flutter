/// 跨端弹幕 transport 公开 API。
///
/// 通道接口与协议解析可由 Windows/Web 共用；具体条件导出负责选择平台实现。
library;

export 'danmaku_backoff.dart';
export 'danmaku_channel.dart';
export 'danmaku_channel_resolver.dart';
export 'douyu_danmaku_codec.dart';
export 'douyu_ws_danmaku_channel.dart';
export 'remote_danmaku_source.dart';
export 'sse_danmaku_channel.dart';
