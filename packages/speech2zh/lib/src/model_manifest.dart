/// 模型清单:sherpa-onnx 流式 zipformer int8(EN/KO)。
///
/// 文件从 HuggingFace `resolve/main` 单文件直链下载(避免整包 tar.bz2
/// 解压依赖);国内无代理环境可将 [SpeechModelManifest.baseUrl] 换成
/// hf-mirror 等镜像。大小校验用精确字节数。
library;

/// 识别语言。
enum SpeechLanguage {
  english('en'),
  korean('ko');

  const SpeechLanguage(this.code);

  /// ISO 639-1 代码(翻译 hook / UI 显示用)。
  final String code;
}

/// 单个模型文件:仓库内相对名 + 精确字节数。
class SpeechModelFile {
  const SpeechModelFile(this.name, this.size);

  final String name;
  final int size;
}

/// 一种语言的完整模型定义。
class SpeechModelSpec {
  const SpeechModelSpec({
    required this.language,
    required this.repo,
    required this.files,
  });

  final SpeechLanguage language;
  final String repo;
  final List<SpeechModelFile> files;

  /// 仓库内模型目录名(组织名不落入本地目录)。
  String get dirName => repo.split('/').last;

  /// 模型目录名。

  SpeechModelFile file(String name) => files.singleWhere((f) => f.name == name);

  int get totalBytes => files.fold(0, (a, f) => a + f.size);
}

class SpeechModelManifest {
  SpeechModelManifest({this.baseUrl = 'https://huggingface.co'});

  /// 仓库根(可替换为镜像,如 https://hf-mirror.com)。
  final String baseUrl;

  static const english = SpeechModelSpec(
    language: SpeechLanguage.english,
    repo: 'csukuangfj/sherpa-onnx-streaming-zipformer-en-2023-06-26',
    files: [
      // 字节数按 **HuggingFace 仓库实际文件**填写 —— 与 GitHub release 的
      // tar.bz2 包不完全一致(int8 权重重新导出过)。填错会让每次下载都
      // `size mismatch` 而永远无法就绪(2026-09-21 真机故障)。
      SpeechModelFile(
        'encoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        71083163,
      ),
      SpeechModelFile(
        'decoder-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        1307236,
      ),
      SpeechModelFile(
        'joiner-epoch-99-avg-1-chunk-16-left-128.int8.onnx',
        259335,
      ),
      SpeechModelFile('tokens.txt', 5048),
    ],
  );

  static const korean = SpeechModelSpec(
    language: SpeechLanguage.korean,
    repo: 'k2-fsa/sherpa-onnx-streaming-zipformer-korean-2024-06-16',
    files: [
      SpeechModelFile('encoder-epoch-99-avg-1.int8.onnx', 126968852),
      SpeechModelFile('decoder-epoch-99-avg-1.int8.onnx', 2844692),
      SpeechModelFile('joiner-epoch-99-avg-1.int8.onnx', 2581421),
      SpeechModelFile('tokens.txt', 60246),
    ],
  );

  static SpeechModelSpec specOf(SpeechLanguage language) => switch (language) {
    SpeechLanguage.english => english,
    SpeechLanguage.korean => korean,
  };

  /// 单文件下载直链。
  Uri fileUri(SpeechModelSpec spec, SpeechModelFile file) =>
      Uri.parse('$baseUrl/${spec.repo}/resolve/main/${file.name}');
}
