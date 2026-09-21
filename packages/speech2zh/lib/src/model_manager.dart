/// 模型下载与就绪管理。
///
/// 目录布局:`<baseDir>/<repo>/<file>`;单文件 `.part` 临时下载支持
/// HTTP Range 断点续传,完成后原子改名;按精确字节校验,已就绪文件跳过。
library;

import 'dart:async';
import 'dart:io';

import 'model_manifest.dart';

class ModelDownloadException implements Exception {
  ModelDownloadException(this.message);
  final String message;

  @override
  String toString() => 'ModelDownloadException: $message';
}

class ModelDownloadInfo {
  const ModelDownloadInfo({
    required this.downloadedBytes,
    required this.totalBytes,
    required this.ready,
  });

  final int downloadedBytes;
  final int totalBytes;
  final bool ready;

  bool get hasPartial => downloadedBytes > 0 && !ready;
  double get progress => totalBytes == 0 ? 1 : downloadedBytes / totalBytes;
}

double modelDownloadProgress({
  required int doneBytes,
  required int receivedBytes,
  required int totalBytes,
}) => (doneBytes + receivedBytes) / totalBytes;

class ModelManager {
  ModelManager({
    required this.baseDir,
    this.baseUrl,
    HttpClient Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  final String baseDir;
  final String? baseUrl;
  final HttpClient Function() _httpClientFactory;
  final Map<SpeechLanguage, Future<String>> _inflight = {};
  final Set<SpeechLanguage> _cancelled = {};

  String modelDir(SpeechLanguage language) {
    final spec = SpeechModelManifest.specOf(language);
    return '$baseDir${Platform.pathSeparator}${spec.dirName}';
  }

  ModelDownloadInfo inspect(SpeechLanguage language) {
    final spec = SpeechModelManifest.specOf(language);
    final dir = Directory(modelDir(language));
    var downloaded = 0;
    var ready = true;
    for (final f in spec.files) {
      final file = File('${dir.path}${Platform.pathSeparator}${f.name}');
      if (file.existsSync() && file.lengthSync() == f.size) {
        downloaded += f.size;
        continue;
      }
      ready = false;
      final part = File('${file.path}.part');
      if (part.existsSync()) {
        downloaded += part.lengthSync().clamp(0, f.size);
      }
    }
    return ModelDownloadInfo(
      downloadedBytes: downloaded,
      totalBytes: spec.totalBytes,
      ready: ready,
    );
  }

  Future<bool> isReady(SpeechLanguage language) async {
    final spec = SpeechModelManifest.specOf(language);
    final dir = Directory(modelDir(language));
    for (final f in spec.files) {
      final file = File('${dir.path}${Platform.pathSeparator}${f.name}');
      if (!await file.exists() || await file.length() != f.size) return false;
    }
    return true;
  }

  /// 确保模型就绪,返回模型目录。
  ///
  /// 并发调用合并到同一在途任务;任务结束(成功/失败)即从在途表移除。
  Future<String> ensureDownloaded(
    SpeechLanguage language, {
    void Function(double progress)? onProgress,
    int maxAttemptsPerFile = 3,
  }) {
    final existing = _inflight[language];
    if (existing != null) return existing;
    _cancelled.remove(language);
    final future = _download(language, onProgress, maxAttemptsPerFile);
    _inflight[language] = future;
    // 只用于摘除在途表项:必须吞掉错误,否则失败会被当作未处理异步异常。
    future.whenComplete(() => _inflight.remove(language)).ignore();
    return future;
  }

  /// 放弃当前在途任务并重开(看门狗超时时由宿主调用)。
  void abandon(SpeechLanguage language) {
    _inflight.remove(language);
    cancel(language);
  }

  /// 标记取消:在途下载在下一个 chunk 边界停下并抛错。
  void cancel(SpeechLanguage language) {
    _cancelled.add(language);
  }

  void _checkCancelled(SpeechLanguage language) {
    if (_cancelled.contains(language)) {
      throw ModelDownloadException('download cancelled');
    }
  }

  Future<String> _download(
    SpeechLanguage language,
    void Function(double progress)? onProgress,
    int maxAttemptsPerFile,
  ) async {
    final manifest = SpeechModelManifest(
      baseUrl: baseUrl ?? 'https://huggingface.co',
    );
    final spec = SpeechModelManifest.specOf(language);
    final dir = Directory(modelDir(language));
    await dir.create(recursive: true);
    final sep = Platform.pathSeparator;
    var doneBytes = 0;
    final pending = <SpeechModelFile>[];
    for (final f in spec.files) {
      final file = File('${dir.path}$sep${f.name}');
      if (await file.exists() && await file.length() == f.size) {
        doneBytes += f.size;
      } else {
        pending.add(f);
      }
    }
    onProgress?.call(doneBytes / spec.totalBytes);
    // 全部文件已就绪:不碰 HTTP 栈。建/关 HttpClient 在这个分支毫无意义,
    // 而一旦它卡住,在途任务就永远挂着 —— 表现为「模型就绪却永远停在 100%」。
    if (pending.isEmpty) return dir.path;

    final client = _httpClientFactory()
      ..connectionTimeout = const Duration(seconds: 12);
    try {
      for (final f in pending) {
        _checkCancelled(language);
        final target = File('${dir.path}$sep${f.name}');
        Object? lastError;
        for (var attempt = 1; attempt <= maxAttemptsPerFile; attempt++) {
          try {
            await _downloadOne(
              language,
              manifest,
              spec,
              f,
              client,
              target,
              onProgress: (receivedBytes) => onProgress?.call(
                modelDownloadProgress(
                  doneBytes: doneBytes,
                  receivedBytes: receivedBytes,
                  totalBytes: spec.totalBytes,
                ),
              ),
            );
            lastError = null;
            break;
          } catch (e) {
            lastError = e;
          }
        }
        if (lastError != null) {
          throw ModelDownloadException('failed ${f.name}: $lastError');
        }
        doneBytes += f.size;
        onProgress?.call(doneBytes / spec.totalBytes);
      }
    } finally {
      client.close(force: true);
      _cancelled.remove(language);
    }
    return dir.path;
  }

  Future<void> _downloadOne(
    SpeechLanguage language,
    SpeechModelManifest manifest,
    SpeechModelSpec spec,
    SpeechModelFile f,
    HttpClient client,
    File target, {
    void Function(int receivedBytes)? onProgress,
  }) async {
    final part = File('${target.path}.part');
    var offset = part.existsSync() ? part.lengthSync() : 0;
    if (offset < 0 || offset > f.size) {
      offset = 0;
      if (part.existsSync()) await part.delete();
    }
    final request = await client
        .getUrl(manifest.fileUri(spec, f))
        .timeout(const Duration(seconds: 20));
    if (offset > 0) {
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$offset-');
    }
    final response = await request.close().timeout(const Duration(minutes: 5));
    if (response.statusCode != 200 && response.statusCode != 206) {
      throw ModelDownloadException('HTTP ${response.statusCode} for ${f.name}');
    }
    final append = offset > 0 && response.statusCode == 206;
    if (!append) offset = 0;
    final out = part.openWrite(mode: append ? FileMode.append : FileMode.write);
    var received = offset;
    onProgress?.call(received);
    try {
      await for (final chunk in response.timeout(const Duration(seconds: 30))) {
        _checkCancelled(language);
        received += chunk.length;
        out.add(chunk);
        onProgress?.call(received);
      }
      await out.flush();
      await out.close();
      if (received != f.size) {
        throw ModelDownloadException(
          'size mismatch for ${f.name}: got $received want ${f.size}',
        );
      }
      await part.rename(target.path);
    } catch (_) {
      await out.close().catchError((_) {});
      // 保留 .part,下次 ensureDownloaded 会通过 Range 继续。
      rethrow;
    }
  }
}
