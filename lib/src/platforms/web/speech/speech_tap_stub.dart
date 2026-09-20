/// 语音字幕音频源 Web/未支持平台桩(条件导出分支)。
library;

import 'package:speech2zh/speech2zh.dart';

AudioTapSource speechTapImpl() =>
    throw UnsupportedError('语音字幕暂不支持当前平台');
