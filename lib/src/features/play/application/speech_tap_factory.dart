/// 语音字幕音频源工厂:平台实现条件导出(Windows WASAPI / 其余平台桩)。
///
/// 用法:`createSpeechTap()` 在 Windows 返回 WASAPI loopback 实现,
/// Web 等未支持平台抛 [UnsupportedError](UI 侧按平台先隐藏「译」入口)。
library;

import 'package:speech2zh/speech2zh.dart';

import '../../../platforms/windows/speech/speech_tap_impl.dart'
    if (dart.library.js_interop) '../../../platforms/web/speech/speech_tap_stub.dart';

/// 供 provider 创建当前平台的 [AudioTapSource]。
AudioTapSource createSpeechTap() => speechTapImpl();
