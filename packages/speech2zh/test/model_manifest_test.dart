import 'package:test/test.dart';
import 'package:speech2zh/src/model_manifest.dart';

void main() {
  test('EN/KO 清单:文件数与总量', () {
    final en = SpeechModelManifest.specOf(SpeechLanguage.english);
    final ko = SpeechModelManifest.specOf(SpeechLanguage.korean);
    expect(en.files, hasLength(4));
    expect(ko.files, hasLength(4));
    // 字节数必须与 HuggingFace 仓库实际文件一致(与 GitHub release 包不同),否则每次下载都 size mismatch。
    expect(en.totalBytes, 71083163 + 1307236 + 259335 + 5048);
    expect(ko.totalBytes, 126968852 + 2844692 + 2581421 + 60246);
    expect(
      SpeechModelManifest.english.dirName,
      'sherpa-onnx-streaming-zipformer-en-2023-06-26',
    );
    expect(
      SpeechModelManifest.korean.dirName,
      'sherpa-onnx-streaming-zipformer-korean-2024-06-16',
    );
  });

  test('fileUri 默认官方源,可替换镜像', () {
    final f = SpeechModelManifest.english.file('tokens.txt');
    expect(
      SpeechModelManifest().fileUri(SpeechModelManifest.english, f).toString(),
      'https://huggingface.co/${SpeechModelManifest.english.repo}'
      '/resolve/main/tokens.txt',
    );
    final mirror = SpeechModelManifest(baseUrl: 'https://hf-mirror.com');
    expect(
      mirror.fileUri(SpeechModelManifest.english, f).host,
      'hf-mirror.com',
    );
  });
}
