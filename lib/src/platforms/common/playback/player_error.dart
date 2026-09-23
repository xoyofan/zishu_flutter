/// 播放错误的语义分类与归一(纯 Dart,无 Flutter 依赖)。
///
/// 移植自 pure_live 的 `PlayerErrorClassifier`,并按 zishu 的可观测面收敛。
/// 存在的前提是:media_kit 的 `Player.stream.error` 转发的是 **mpv 的 error
/// 级日志行**,其中相当一部分并非终局失败 —— 例如硬解拒绝某个 profile 后
/// mpv 已自动软解、直播丢包后跟上了关键帧、播放器正在被替换时的取消噪音。
/// 若把这些行一律当"播放失败"弹卡片给用户,会出现「画面照常在播、卡片却
/// 悬在中间」的错误体验。
///
/// 因此分类器回答两个问题:
///
/// 1. **哪一类错误**([kind]) —— 用于给出用户可读的处置建议;
/// 2. **是否终局**([terminal]) —— 即"不换源 / 不改播放器状态就无法自愈"。
///    非终局的诊断交给 mpv 自愈,不上报;终局的才展示并进入重连/切线路路径。
///
/// 纯逻辑、无 IO 与 Flutter 依赖,便于在 VM 单测里直接喂字符串断言。
library;

/// 播放错误的语义类别。
///
/// 刻意比 pure_live 的 `PlayerErrorType` 窄:只保留 zishu 当前能观测且能给出
/// 差异化处置的类别(`initialization` 并入 [source],`unknown` 并入 [native])。
enum PlayerErrorKind {
  /// 无错误。
  none,

  /// 网络/传输层:超时、连接被拒/重置、DNS 失败、TLS 握手失败。
  network,

  /// 源侧:HTTP 4xx、协议不支持、打开输入失败、EOF、demuxer 报错。
  source,

  /// 解码:不支持的编码(终局)或解码过程中的可自愈抖动(非终局)。
  codec,

  /// 视频输出:surface/texture/GPU 上下文问题。
  texture,

  /// 播放器生命周期:已被释放、操作被取消(切源竞态的常见噪音)。
  lifecycle,

  /// 其余 mpv 原生诊断(多为可自愈噪音)。
  native,
}

/// 单条诊断的语义解释。
class PlayerErrorClassification {
  const PlayerErrorClassification({
    required this.kind,
    required this.code,
    required this.terminal,
  });

  /// 无错误哨兵(空串 / 纯空白输入的归属)。
  static const PlayerErrorClassification none = PlayerErrorClassification(
    kind: PlayerErrorKind.none,
    code: 'none',
    terminal: false,
  );

  /// 语义类别。
  final PlayerErrorKind kind;

  /// 细分工位码(如 `transport`、`decoder_init`、`source_open`),
  /// 用于日志与测试断言;UI 不直接展示。
  final String code;

  /// 是否"不换源 / 不改播放器状态就无法自愈"。
  ///
  /// true → 展示错误并进入重连/切线路路径;
  /// false → 视为可自愈噪音,不上报(避免假错误卡片)。
  final bool terminal;

  /// 是否属于真实错误(非 [none])。
  bool get isError => kind != PlayerErrorKind.none;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PlayerErrorClassification &&
          other.kind == kind &&
          other.code == code &&
          other.terminal == terminal;

  @override
  int get hashCode => Object.hash(kind, code, terminal);

  @override
  String toString() =>
      'PlayerErrorClassification(kind: $kind, code: $code, terminal: $terminal)';
}

/// 把 mpv / media_kit 的原始诊断文本归一到 [PlayerErrorClassification]。
///
/// 判定顺序刻意从"最具体且最严重"排到"最泛化":先生命周期与视频输出这类
/// 与内容无关的终局错误,再解码与源侧,最后网络,兜底 [PlayerErrorKind.native]。
/// 同一字符串可能同时命中多组标记(例如 `failed to open input` 既像源侧又像
/// 网络),排序即优先级。
abstract final class PlayerErrorClassifier {
  /// 归类一条诊断文本。空串 / 纯空白 → [PlayerErrorClassification.none]。
  ///
  /// [nativePrefix] 为 mpv 日志的组件前缀(`vd` / `ad` / `ffmpeg/video` 等),
  /// 用于在码位里标记音视频通道;不影响类别判定。
  static PlayerErrorClassification classify(
    String message, {
    String? nativePrefix,
  }) {
    final value = message.trim().toLowerCase();
    if (value.isEmpty) return PlayerErrorClassification.none;
    final channel = _channelOf(nativePrefix);

    if (_containsAny(value, _lifecycleMarkers)) {
      return PlayerErrorClassification(
        kind: PlayerErrorKind.lifecycle,
        code: _tag(channel, 'lifecycle'),
        terminal: true,
      );
    }
    if (_containsAny(value, _textureMarkers)) {
      return PlayerErrorClassification(
        kind: PlayerErrorKind.texture,
        code: _tag(channel, 'video_output'),
        terminal: true,
      );
    }
    if (_containsAny(value, _codecInitMarkers)) {
      return PlayerErrorClassification(
        kind: PlayerErrorKind.codec,
        code: _tag(channel, 'decoder_init'),
        terminal: true,
      );
    }
    // `codec` 是过宽的运行时标记；带 mpv 组件前缀时，`codec: Failed to open
    // https://...m3u8` 会先命中它并被误判成可自愈的解码抖动。源打开失败是
    // 更具体的语义，必须先于通用 codec 标记判断，否则签名 URL 失效不会
    // 进入 source 级恢复。
    if (_containsAny(value, _sourceOpenMarkers)) {
      return PlayerErrorClassification(
        kind: PlayerErrorKind.source,
        code: 'source_open',
        terminal: true,
      );
    }
    if (_containsAny(value, _codecRuntimeMarkers)) {
      // 解码抖动:坏帧后跟着关键帧即可恢复,不打扰用户。
      return PlayerErrorClassification(
        kind: PlayerErrorKind.codec,
        code: _tag(channel, 'decoder_runtime'),
        terminal: false,
      );
    }
    if (_containsAny(value, _networkMarkers)) {
      return PlayerErrorClassification(
        kind: PlayerErrorKind.network,
        code: 'transport',
        terminal: true,
      );
    }
    if (_containsAny(value, _sourceRuntimeMarkers)) {
      return PlayerErrorClassification(
        kind: PlayerErrorKind.source,
        code: 'source_runtime',
        terminal: false,
      );
    }
    return const PlayerErrorClassification(
      kind: PlayerErrorKind.native,
      code: 'native_diagnostic',
      terminal: false,
    );
  }

  /// 一次归类出"是否值得上报给用户":只有终局错误才该弹卡片。
  static bool shouldSurface(String message) =>
      classify(message).terminal;

  static const List<String> _lifecycleMarkers = <String>[
    'player has been disposed',
    'player has been released',
    'operation was cancelled',
    'operation was canceled',
  ];

  static const List<String> _textureMarkers = <String>[
    'surface has been released',
    'failed to create surface',
    'failed to create texture',
    'texture is unavailable',
    'egl_bad',
    'vulkan error',
    'gpu context failed',
  ];

  static const List<String> _codecInitMarkers = <String>[
    'no decoder found',
    'unsupported codec',
    'codec is not supported',
    'could not find codec parameters',
  ];

  static const List<String> _codecRuntimeMarkers = <String>[
    'mediacodec',
    'decoder',
    'decode',
    'codec',
    'invalid nal',
    'non-existing pps',
    'missing reference picture',
    'corrupt decoded frame',
    'error while decoding',
  ];

  static const List<String> _sourceOpenMarkers = <String>[
    'server returned 401',
    'server returned 403',
    'server returned 404',
    'http error 401',
    'http error 403',
    'http error 404',
    'protocol not found',
    'unknown protocol',
    'no protocol handler',
    'failed to open input',
    'failed to open http://',
    'failed to open https://',
    'error opening input',
    'unable to open input',
    'invalid data found when processing input',
    'no streams found',
  ];

  static const List<String> _networkMarkers = <String>[
    'connection timed out',
    'network timeout',
    'network is unreachable',
    'host is unreachable',
    'connection refused',
    'connection reset',
    'failed to resolve',
    'temporary failure in name resolution',
    'name or service not known',
    'tls handshake',
    'ssl handshake',
    'certificate verify failed',
    'input/output error',
    'i/o error',
  ];

  static const List<String> _sourceRuntimeMarkers = <String>[
    'demuxer',
    'failed to open',
    'error opening',
    'unable to open',
    'end of file',
    'unexpected eof',
  ];

  static bool _containsAny(String value, List<String> markers) =>
      markers.any(value.contains);

  static String _tag(String? channel, String code) =>
      channel == null ? code : '${channel}_$code';

  static String? _channelOf(String? nativePrefix) {
    final prefix = nativePrefix?.trim().toLowerCase();
    return switch (prefix) {
      'ad' || 'ffmpeg/audio' => 'audio',
      'vd' || 'ffmpeg/video' => 'video',
      _ => null,
    };
  }
}

/// 错误类别 → 用户可读的处置建议。
///
/// 单独暴露为函数(而非塞进枚举),便于 UI 层与日志层各自取用,也便于单测
/// 逐类别断言文案。返回的句子已包含"怎么做",UI 不必再拼后缀。
String playerErrorHint(PlayerErrorKind kind) => switch (kind) {
  PlayerErrorKind.none => '',
  PlayerErrorKind.network => '网络中断或直播源超时，请检查网络后重试或切换线路',
  PlayerErrorKind.source => '直播地址已失效，可能需要重新解析房间或切换线路',
  PlayerErrorKind.codec => '该线路编码当前无法解码，请切换清晰度或线路',
  PlayerErrorKind.texture => '视频渲染失败，请切换线路或重启播放器',
  PlayerErrorKind.lifecycle => '播放器已重置，请点击重试',
  PlayerErrorKind.native => '直播流反复中断，请点击重试或切换线路',
};
