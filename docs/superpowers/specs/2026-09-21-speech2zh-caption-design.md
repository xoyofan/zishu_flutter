# 语音识别中文字幕(speech2zh)设计

日期:2026-09-21。状态:设计已经用户批准,本文档为实施基线。

## 目标

播放页开启「译」开关(默认开)后,本地识别直播语音(英语/韩语),翻译为中文,
显示在底部控制栏上方的字幕条中。纯本地推理,免 API key。Windows 优先。

## 可行性结论(2026-09-20 spike,build/spike_asr 一次性代码)

- sherpa-onnx 1.13.8(pub `sherpa_onnx`,MIT)+ Windows CPU:
  - 流式 zipformer int8(EN):13.3 倍实时,partial 逐词上屏,质量良好。
  - 流式 zipformer int8(KO):13.3 倍实时,与官方参考文本几乎逐字一致。
  - 离线 whisper tiny int8(EN):10.2 倍实时,逐字正确(备选路线,暂不用)。
- 识别文本经现有 gtx 翻译引擎韩→中验证通过。
- 模型体积:EN int8 ≈ 68MB,KO int8 ≈ 126MB;运行时下载,不进仓库。
- 已知坑:本机 System32 有全局旧版 onnxruntime.dll(1.17.1),依赖搜索先于
  PATH 命中会导致初始化崩溃。app 内插件库 bundling 在 exe 同目录(搜索优先级
  更高)不受影响;引擎初始化仍做防御性预加载。

## 模块边界(与三端架构同规)

- `packages/speech2zh/`:纯 Dart 包(禁 Flutter/Widget/media-kit/dart:ui;
  `sherpa_onnx` 为纯 dart:ffi 依赖,允许)。
  - `SpeechRecognizer` 抽象 + `SherpaStreamingRecognizer` 实现(可插拔,后续可加
    whisper/云 ASR 实现)。
  - `SpeechModelManager`:模型清单 + 下载(HuggingFace 单文件直链,走
    live_parser `UpstreamProxy`)+ 大小校验 + 就绪状态;模型目录由调用方传入。
  - `CaptionPipeline`:PCM 16kHz 单声道 float32 进 → 流式识别(sherpa 内置
    endpoint 分句,不引 VAD 模型)→ 翻译 hook(`Future<String?> Function(String)`)
    → `CaptionSegment{text, translated, isFinal}` 流出。
  - 所有推理与模型 IO 在独立 isolate(`sherpa_onnx` 要求每 isolate 重新 init)。
- `lib/src/platforms/windows/speech/`:WASAPI 进程级 loopback 采集
  (AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK,dart:ffi 直调 COM),
  实现 `AudioTapSource` 接口;48kHz float32 立体声 → 16k 单声道线性重采样。
- UI 轨 `lib/src/features/play/`:「译」开关 + 字幕条 + riverpod provider。

## 关键决策

1. 音频来源:WASAPI process loopback(只采本进程播放声,不加带宽、与播放同步、
   与流格式无关)。已排除 media-kit 取 PCM(无公开通道);独立拉流为 Android 期备选。
2. 语言策略:跟随平台先验(SOOP→ko,Twitch/YouTube→en),设置面板可手动切换;
   切语言即重载模型。第一版不做自动语言识别。
3. 字幕口径:译文就绪才上屏(与弹幕翻译同口径);partial 不上屏;翻译失败保留
   上一条字幕并重试,不显示原文。
4. 「译」开关复刻「弹」方块形态(amber 激活 + √ 角标),默认开,
   `SharedPreferencesAsync` 持久化。开启但模型未就绪时字幕条位置显示下载进度。
5. 模型下载:HuggingFace resolve 直链单文件(encoder/decoder/joiner int8 +
   tokens.txt),避免 tar.bz2 解压依赖;走系统代理(UpstreamProxy 同源)。
6. 生命周期:切台/暂停重置识别流;推理 isolate 随开关关闭销毁。

## 测试与门禁

- speech2zh 单测:分句/endpoint 流水线状态机(mock 引擎)、模型清单解析、
  重采样。
- UI:字幕条 goldens、「译」开关状态。
- 门禁:`flutter analyze` + `flutter test` + parser test +
  `flutter build windows --debug -t lib/main.dart`(带
  `--dart-define=ZISHU_REAL_PARSER=true` 的真机验证另行)。

## Wave 划分

- W1:packages/speech2zh 核心 + 单测。
- W2:Windows WASAPI 采集 + 与流水线联调(wav 回灌 + 真机)。
- W3:UI 开关/字幕条/持久化/goldens + 门禁全绿。
