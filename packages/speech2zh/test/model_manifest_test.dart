import 'package:test/test.dart';
import 'package:speech2zh/src/model_manifest.dart';

void main() {
  test('EN/KO 清单:文件数与总量', () {
    final en = SpeechModelManifest.specOf(SpeechLanguage.english);
    final ko = SpeechModelManifest.specOf(SpeechLanguage.korean);
    expect(en.files, hasLength(4));
    expect(ko.files, hasLength(4));
    expect(en.totalBytes, 70108816 + 540688 + 259416 + 5048);
    expect(ko.totalBytes, 126968852 + 2844692 + 2581421 + 60246);
    expect(en.language.code, 'en');
    expect(ko.language.code, 'ko');
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
