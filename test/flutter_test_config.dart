/// 全局测试配置(dart_test 约定文件,flutter test 自动加载)。
///
/// **禁外网、放行本地回环**:widget 测试是 fake-async 环境,任何真实外网
/// HTTP(如内容翻译的公共实例请求)都会留下 pending Timer 直接炸测试。
/// 这里把 HttpClient 全局替换为「外网立即抛 SocketException」的桩,依赖
/// 外网的功能(翻译等)在测试中走既有的失败回退路径,微任务级完成、零
/// Timer。127.0.0.1/localhost 回环放行 —— 本地代理类测试(twitch 广告
/// 过滤的 loopback server)需要真实自连。需要外网的测试应显式注入
/// fake/mock,而不是联网。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(Future<void> Function() testMain) async {
  // 在设置全局桩【之前】构造唯一的真实回环 client,供桩转发;
  // global 设置后 new HttpClient() 会递归回到桩。
  _sharedRealClient = HttpClient();
  HttpOverrides.global = _NoNetworkHttpOverrides();
  await testMain();
}

/// 唯一的真实 HttpClient(仅回环流量):进程级共享,退出时由运行时回收。
HttpClient? _sharedRealClient;

class _NoNetworkHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _NoNetworkHttpClient();
}

bool _isLoopbackHost(String host) {
  final normalized = host.replaceFirst(RegExp(r'^\[|\]$'), '');
  return normalized == '127.0.0.1' ||
      normalized == 'localhost' ||
      normalized == '::1';
}

/// 桩 HttpClient:外网请求立即抛 [SocketException](微任务级失败,无
/// pending Timer);回环请求与配置/生命周期成员全部转发给真实 client
/// (在空 override zone 中构造,防递归)。
class _NoNetworkHttpClient implements HttpClient {
  HttpClient get _real => _sharedRealClient!;

  Never _blocked(String method, String target) => throw SocketException(
    'network is disabled in tests (see test/flutter_test_config.dart); '
    'request: $method $target',
  );

  Future<HttpClientRequest> _openUrl(String method, Uri url) =>
      _isLoopbackHost(url.host)
      ? _real.openUrl(method, url)
      : _blocked(method, '$url');

  Future<HttpClientRequest> _open(
    String method,
    String host,
    int port,
    String path,
  ) => _isLoopbackHost(host)
      ? _real.open(method, host, port, path)
      : _blocked(method, '$host:$port$path');

  // ---- 请求入口:回环放行,外网拦截 ----

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) =>
      _openUrl(method, url);

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _open(method, host, port, path);

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _open('GET', host, port, path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _openUrl('GET', url);

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _open('POST', host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _openUrl('POST', url);

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _open('PUT', host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _openUrl('PUT', url);

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _open('DELETE', host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _openUrl('DELETE', url);

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _open('HEAD', host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _openUrl('HEAD', url);

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _open('PATCH', host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _openUrl('PATCH', url);

  // ---- 配置/生命周期:转发真实 client(成员清单对齐 dart:io 接口;
  // authenticate/findProxy/keyLog/badCertificateCallback/connectionFactory
  // 为 setter-only)----

  @override
  void close({bool force = false}) {
    // 共享真实 client 不随单个测试的 client.close 关闭(否则后续回环
    // 请求全挂);连接由进程退出统一回收。
  }

  @override
  Duration get idleTimeout => _real.idleTimeout;

  @override
  set idleTimeout(Duration value) => _real.idleTimeout = value;

  @override
  Duration? get connectionTimeout => _real.connectionTimeout;

  @override
  set connectionTimeout(Duration? value) => _real.connectionTimeout = value;

  @override
  int? get maxConnectionsPerHost => _real.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _real.maxConnectionsPerHost = value;

  @override
  bool get autoUncompress => _real.autoUncompress;

  @override
  set autoUncompress(bool value) => _real.autoUncompress = value;

  @override
  String? get userAgent => _real.userAgent;

  @override
  set userAgent(String? value) => _real.userAgent = value;

  @override
  set authenticate(
    Future<bool> Function(Uri url, String scheme, String? realm)? f,
  ) => _real.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)?
    f,
  ) => _real.authenticateProxy = f;

  @override
  void addCredentials(
    Uri url,
    String realm,
    HttpClientCredentials credentials,
  ) => _real.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _real.addProxyCredentials(host, port, realm, credentials);

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(
      Uri url,
      String? proxyHost,
      int? proxyPort,
    )?
    f,
  ) => _real.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _real.findProxy = f;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _real.badCertificateCallback = callback;

  @override
  set keyLog(Function(String line)? callback) => _real.keyLog = callback;
}
