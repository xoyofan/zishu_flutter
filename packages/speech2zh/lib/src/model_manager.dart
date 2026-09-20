/// 模型下载与就绪管理。
///
/// 目录布局:`<baseDir>/<repo>/<file>`;单文件 `.part` 临时下载完成后
/// 原子改名;按精确字节校验,已就绪文件跳过。HTTP 客户端由调用方注入
/// (app 层可传入代理感知的 client,与解析/翻译同源)。
library;

import 'dart:io';

import 'model_manifest.dart';

class ModelDownloadException implements Exception {
  ModelDownloadException(this.message);
  final String message;

  @override
  String toString() => 'ModelDownloadException: $message';
}

class ModelManager {
  ModelManager({
    required this.baseDir,
    this.baseUrl,
    HttpClient Function()? httpClientFactory,
  })  : _httpClientFactory = httpClientFactory ?? HttpClient.new;

  /// 模型根目录(由 app 层传入应用数据目录)。
  final String baseDir;

  /// 覆盖清单默认下载源(hf-mirror 等镜像);null 用清单默认。
  final String? baseUrl;

  final HttpClient Function() _httpClientFactory;

  final Map<SpeechLanguage, Future<String>> _inflight = {};

  /// 模型落盘目录(存在与否不保证,见 [isReady]/[ensureDownloaded])。
  String modelDir(SpeechLanguage language) {
    final spec = SpeechModelManifest.specOf(language);
    final sep = Platform.pathSeparator;
    return '$baseDir${sep}${spec.dirName}';
  }

  /// 全部文件存在且字节数匹配。
  Future<bool> isReady(SpeechLanguage language) async {
    final spec = SpeechModelManifest.specOf(language);
    final dir = Directory(modelDir(language));
    for (final f in spec.files) {
      final file = File('${dir.path}${Platform.pathSeparator}${f.name}');
      if (!await file.exists()) return false;
      final len = await file.length();
      if (len != f.size) return false;
    }
    return true;
  }

  /// 确保模型就绪,返回模型目录。重复调用会合并到同一在途任务。
  Future<String> ensureDownloaded(
    SpeechLanguage language, {
    void Function(double progress)? onProgress,
    int maxAttemptsPerFile = 3,
  }) {
    return _inflight.putIfAbsent(language, () => _download(language, onProgress, maxAttemptsPerFile).whenComplete(() => _inflight.remove(language)));
  }

  Future<String> _download(
    SpeechLanguage language,
    void Function(double progress)? onProgress,
    int maxAttemptsPerFile,
  ) async {
    final manifest = SpeechModelManifest(baseUrl: baseUrl ?? 'https://huggingface.co');
    final spec = SpeechModelManifest.specOf(language);
    final dirPath = modelDir(language);
    final dir = Directory(dirPath);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final sep = Platform.pathSeparator;

    // 已就绪的先跳过,只补缺失/损坏文件。
    var doneBytes = 0;
    final pending = <SpeechModelFile>[];
    for (final f in spec.files) {
      final file = File('${dir.path}$sep${f.name}');
      var ok = false;
      if (await file.exists()) {
        ok = await file.length() == f.size;
      }
      if (ok) {
        doneBytes += f.size;
      } else {
        pending.add(f);
      }
    }
    onProgress?.call(doneBytes / spec.totalBytes);

    final client = _httpClientFactory();
    try {
      for (final f in pending) {
        final target = File('${dir.path}$sep${f.name}');
        var lastError;
        for (var attempt = 1; attempt <= maxAttemptsPerFile; attempt++) {
          try {
            await _downloadOne(manifest, spec, f, client, target);
            lastError = null;
            break;
          } catch (e) {
            lastError = e;
            if (await target.exists()) {
              await target.delete();
            }
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
    }
    return dirPath;
  }

  Future<void> _downloadOne(
    SpeechModelManifest manifest,
    SpeechModelSpec spec,
    SpeechModelFile f,
    HttpClient client,
    File target,
  ) async {
    final partPath = '${target.path}.part';
    final request = await client.getUrl(manifest.fileUri(spec, f));
    final response = await request.close();
    if (response.statusCode != 200) {
      throw ModelDownloadException('HTTP ${response.statusCode} for ${f.name}');
    }
    final part = File(partPath);
    final out = part.openWrite();
    var received = 0;
    try {
      await for (final chunk in response) {
        received += chunk.length;
        out.add(chunk);
      }
      await out.flush();
      await out.close();
      if (received != f.size) {
        throw ModelDownloadException(
            'size mismatch for ${f.name}: got $received want ${f.size}');
      }
      await part.rename(target.path);
    } catch (_) {
      await out.close().catchError((_) {});
      if (await part.exists()) {
        await part.delete();
      }
      rethrow;
    }
  }
}
