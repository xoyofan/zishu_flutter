import 'dart:io';

import 'package:speech2zh/src/model_manifest.dart';
import 'package:speech2zh/src/model_manager.dart';
import 'package:test/test.dart';

void main() {
  test('模型下载进度按已接收字节计算,不会在首个文件期间卡在 0%', () {
    expect(
      modelDownloadProgress(
        doneBytes: 0,
        receivedBytes: 1024,
        totalBytes: 4096,
      ),
      0.25,
    );
    expect(
      modelDownloadProgress(
        doneBytes: 2048,
        receivedBytes: 1024,
        totalBytes: 4096,
      ),
      0.75,
    );
  });

  group('inspect(断点续传状态)', () {
    late Directory dir;
    late ModelManager manager;
    final spec = SpeechModelManifest.specOf(SpeechLanguage.english);

    setUp(() {
      dir = Directory.systemTemp.createTempSync('speech2zh_test');
      manager = ModelManager(baseDir: dir.path);
    });

    tearDown(() => dir.deleteSync(recursive: true));

    String filePath(String name) =>
        '${manager.modelDir(SpeechLanguage.english)}'
        '${Platform.pathSeparator}$name';

    test('无任何文件:0 字节、未就绪、无 .part', () {
      final info = manager.inspect(SpeechLanguage.english);
      expect(info.downloadedBytes, 0);
      expect(info.ready, isFalse);
      expect(info.hasPartial, isFalse);
      expect(info.totalBytes, spec.totalBytes);
    });

    test('残留 .part 计入已下载字节,可续传', () {
      final first = spec.files.first;
      File('${filePath(first.name)}.part')
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(2048, 0));

      final info = manager.inspect(SpeechLanguage.english);
      expect(info.downloadedBytes, 2048);
      expect(info.ready, isFalse);
      expect(info.hasPartial, isTrue);
      expect(info.progress, closeTo(2048 / spec.totalBytes, 1e-9));
    });

    test('全部文件字节数匹配:就绪', () {
      for (final f in spec.files) {
        final file = File(filePath(f.name));
        file.createSync(recursive: true);
        // truncate 造出精确大小的稀疏文件,避免真写几十 MB。
        final raf = file.openSync(mode: FileMode.write);
        raf.truncateSync(f.size);
        raf.closeSync();
      }

      final info = manager.inspect(SpeechLanguage.english);
      expect(info.ready, isTrue);
      expect(info.downloadedBytes, spec.totalBytes);
      expect(info.progress, 1);
    });
    test('模型已就绪:完全不碰 HTTP 栈(修复「就绪却永远停在 100%」)', () async {
      final manager = ModelManager(
        baseDir: dir.path,
        httpClientFactory: () => throw StateError('HTTP 不应被触及:模型已就绪'),
      );
      for (final f in spec.files) {
        final file = File(
          '${manager.modelDir(SpeechLanguage.english)}'
          '${Platform.pathSeparator}${f.name}',
        );
        file.createSync(recursive: true);
        final raf = file.openSync(mode: FileMode.write);
        raf.truncateSync(f.size);
        raf.closeSync();
      }

      final progress = <double>[];
      final modelDir = await manager
          .ensureDownloaded(SpeechLanguage.english, onProgress: progress.add)
          .timeout(const Duration(seconds: 5));

      expect(modelDir, manager.modelDir(SpeechLanguage.english));
      expect(progress.last, 1);
    });

    test('下载失败后在途任务被摘除,重试会重新发起(不再被死 Future 拴住)', () async {
      var factoryCalls = 0;
      final manager = ModelManager(
        baseDir: dir.path,
        // 首个文件缺失 → 必须走 HTTP,而这里的 factory 总是抛错。
        httpClientFactory: () {
          factoryCalls++;
          throw StateError('boom');
        },
      );

      await expectLater(
        manager.ensureDownloaded(SpeechLanguage.english),
        throwsA(isA<Object>()),
      );
      final afterFirst = factoryCalls;
      expect(afterFirst, greaterThan(0));

      // 第二次必须是新的一轮(而不是复用上一个已失败的 Future)。
      await expectLater(
        manager.ensureDownloaded(SpeechLanguage.english),
        throwsA(isA<Object>()),
      );
      expect(factoryCalls, greaterThan(afterFirst), reason: '失败后重试应重新进入下载流程');
    });

    test('abandon 可在看门狗超时时解开在途任务', () async {
      final manager = ModelManager(baseDir: dir.path);
      manager.abandon(SpeechLanguage.korean);
      // 摘除后再次调用不应复用旧任务(此处仅验证不抛错且能正常返回目录)。
      final info = manager.inspect(SpeechLanguage.korean);
      expect(info.ready, isFalse);
    });
  });
}
