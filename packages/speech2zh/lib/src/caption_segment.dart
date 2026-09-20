/// 字幕段与流水线状态(纯数据,UI 直接消费)。
library;

/// 一条最终字幕(原文 + 译文)。
///
/// 口径:译文就绪才产生 [CaptionSegment];[translated] 为 null 表示
/// 翻译失败被放弃(按弹幕同口径,UI 不应显示原文)。
class CaptionSegment {
  const CaptionSegment({
    required this.text,
    required this.translated,
    required this.language,
    this.at,
  });

  /// 识别原文(韩语/英语)。
  final String text;

  /// 中文译文;null = 翻译失败放弃。
  final String? translated;

  /// 识别语言代码('en' / 'ko')。
  final String language;

  /// 产生时刻(流水线注入,便于调试与 UI 排序)。
  final DateTime? at;

  @override
  String toString() =>
      'CaptionSegment(${language}: $text -> ${translated ?? "<null>"})';
}

/// 流水线相位(UI 状态提示:下载中/加载模型/监听/错误)。
enum CaptionPhase { idle, downloading, loadingModel, listening, error }

/// 流水线状态快照。
class CaptionStatus {
  const CaptionStatus({
    required this.phase,
    this.downloadProgress,
    this.message,
  });

  const CaptionStatus.idle() : this(phase: CaptionPhase.idle);

  final CaptionPhase phase;

  /// 模型下载进度 0.0-1.0(仅 [CaptionPhase.downloading])。
  final double? downloadProgress;

  /// 人读信息(错误原因等)。
  final String? message;

  CaptionStatus copyWith({CaptionPhase? phase, double? downloadProgress, String? message}) =>
      CaptionStatus(
        phase: phase ?? this.phase,
        downloadProgress: downloadProgress ?? this.downloadProgress,
        message: message ?? this.message,
      );

  @override
  String toString() =>
      'CaptionStatus($phase${downloadProgress == null ? '' : ' ${((downloadProgress ?? 0) * 100).toStringAsFixed(0)}%'}'
      '${message == null ? '' : ' $message'})';
}
