/// Windows 语音字幕音频源实现(io 条件导出分支)。
library;

import 'package:speech2zh/speech2zh.dart';

import 'wasapi_loopback_tap.dart';

AudioTapSource speechTapImpl() => WasapiLoopbackTap();
