/// 斗鱼钻粉 suffix 装扮表端到端回归(2026-09-27 用户报「钻粉图标全是
/// 一种样式」):
///
/// 官网口径(chatmsg 实测):`diaf=1 && dfgm>0` 渲染 suffix 层,图 URL 按
/// **`diafid`** 查 `inter_com_w_anchor_rights.json` 的 `list[diafid].webPic`
/// (主播装扮款,动图 webp),无 diafid 回落默认款(`diamond_list['1']`
/// 6ab5daa PNG)。
///
/// 本测试拦截 HTTP(重写到本地 server 供配置 fixture),直接推
/// [DanmakuMessage],断言三个用户(diafid=126 / 100085 / 缺失)的粉丝牌
/// 分别请求装扮款×2 + 默认款×1 —— 防止「全回落默认款」回退。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:live_parser/live_parser.dart'
    show
        DanmakuBadge,
        DanmakuConnector,
        DanmakuMessage,
        DanmakuMessageType,
        DanmakuSession,
        DanmakuSessionRequest,
        DanmakuSessionState,
        DouyuFansMedalAssets,
        SiteCapabilities,
        SiteRegistration,
        SiteRegistry,
        buildSiteRegistry,
        kDouyuDiamondFanSuffixUrl;
import 'package:zishu_flutter/src/app/app_theme.dart';
import 'package:zishu_flutter/src/features/danmaku/application/danmaku_session_provider.dart';
import 'package:zishu_flutter/src/features/play/widgets/play_side_panel.dart';

class _FakeDanmakuSession implements DanmakuSession {
  final messagesController = StreamController<DanmakuMessage>.broadcast();
  final statesController = StreamController<DanmakuSessionState>.broadcast();

  @override
  Stream<DanmakuMessage> get messages => messagesController.stream;

  @override
  Stream<DanmakuSessionState> get states => statesController.stream;

  void emitConnected() => statesController.add(DanmakuSessionState.connected);

  void push(DanmakuMessage message) => messagesController.add(message);

  @override
  Future<void> close() async {
    await messagesController.close();
    await statesController.close();
  }
}

class _FakeDanmakuConnector implements DanmakuConnector {
  _FakeDanmakuSession? session;

  @override
  SiteCapabilities get capabilities => const SiteCapabilities(danmaku: true);

  @override
  Future<DanmakuSession> connect(DanmakuSessionRequest request) async {
    return session ??= _FakeDanmakuSession();
  }
}

SiteRegistry _registryFor(String siteId, DanmakuConnector connector) {
  final registry = buildSiteRegistry();
  final target = registry[siteId]!;
  registry.register(
    SiteRegistration(
      id: target.id,
      name: target.name,
      capabilities: target.capabilities,
      resolver: target.resolver,
      browse: target.browse,
      search: target.search,
      danmaku: connector,
    ),
  );
  return registry;
}

/// 把所有域名重写到本地 server 的 HttpClient(记录原始 URL)。
class _RewritingClient implements HttpClient {
  _RewritingClient(this._inner, this._port, this._onRequest);

  final HttpClient _inner;
  final int _port;
  final void Function(Uri url) _onRequest;

  Uri _rewrite(Uri url) => url.replace(scheme: 'http', host: '127.0.0.1', port: _port);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) {
    _onRequest(url);
    return _inner.openUrl(method, _rewrite(url));
  }

  @override
  Future<HttpClientRequest> open(
    String method,
    String host,
    int port,
    String path,
  ) => _inner.open(method, host, port, path);

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) =>
      _inner.addCredentials(url, realm, credentials);

  @override
  void addProxyCredentials(
    String host,
    int port,
    String realm,
    HttpClientCredentials credentials,
  ) => _inner.addProxyCredentials(host, port, realm, credentials);

  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) =>
      _inner.authenticate = f;

  @override
  set authenticateProxy(
    Future<bool> Function(String host, int port, String scheme, String? realm)? f,
  ) => _inner.authenticateProxy = f;

  @override
  bool get autoUncompress => _inner.autoUncompress;

  @override
  set autoUncompress(bool value) => _inner.autoUncompress = value;

  @override
  set badCertificateCallback(
    bool Function(X509Certificate cert, String host, int port)? callback,
  ) => _inner.badCertificateCallback = callback;

  @override
  void close({bool force = false}) => _inner.close(force: force);

  @override
  set connectionFactory(
    Future<ConnectionTask<Socket>> Function(Uri host, String? context, int? port)?
    f,
  ) => _inner.connectionFactory = f;

  @override
  set findProxy(String Function(Uri url)? f) => _inner.findProxy = f;

  @override
  set connectionTimeout(Duration? value) => _inner.connectionTimeout = value;

  @override
  Duration? get connectionTimeout => _inner.connectionTimeout;

  @override
  Future<HttpClientRequest> delete(String host, int port, String path) =>
      _inner.delete(host, port, path);

  @override
  Future<HttpClientRequest> deleteUrl(Uri url) => _inner.deleteUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> get(String host, int port, String path) =>
      _inner.get(host, port, path);

  @override
  Future<HttpClientRequest> getUrl(Uri url) => _inner.getUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> head(String host, int port, String path) =>
      _inner.head(host, port, path);

  @override
  Future<HttpClientRequest> headUrl(Uri url) => _inner.headUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> patch(String host, int port, String path) =>
      _inner.patch(host, port, path);

  @override
  Future<HttpClientRequest> patchUrl(Uri url) => _inner.patchUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> post(String host, int port, String path) =>
      _inner.post(host, port, path);

  @override
  Future<HttpClientRequest> postUrl(Uri url) => _inner.postUrl(_rewrite(url));

  @override
  Future<HttpClientRequest> put(String host, int port, String path) =>
      _inner.put(host, port, path);

  @override
  Future<HttpClientRequest> putUrl(Uri url) => _inner.putUrl(_rewrite(url));

  @override
  Duration get idleTimeout => _inner.idleTimeout;

  @override
  set idleTimeout(Duration value) => _inner.idleTimeout = value;

  @override
  int? get maxConnectionsPerHost => _inner.maxConnectionsPerHost;

  @override
  set maxConnectionsPerHost(int? value) => _inner.maxConnectionsPerHost = value;

  @override
  set keyLog(void Function(String line)? callback) => _inner.keyLog = callback;

  @override
  String? get userAgent => _inner.userAgent;

  @override
  set userAgent(String? value) => _inner.userAgent = value;
}

class _RewriteOverrides extends HttpOverrides {
  _RewriteOverrides(this.port, this.onRequest);

  final int port;
  final void Function(Uri url) onRequest;

  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      _RewritingClient(super.createHttpClient(context), port, onRequest);
}

/// 最小可解析配置:fans_medal_web_v5(背景桶 + 空前缀表)与
/// anchor_rights(126/100085 两款装扮)。
const String _kFansConfigJson =
    '{"code":0,"data":{"commBg":{"bg_20":"com_bg_20"},'
    '"bgPics":{"com_bg_20":"https://cdn.test/bg20.png"},"fansMedals":[]}}';
const String _kRightsJson =
    '{"code":0,"data":{"list":{'
    '"126":{"id":126,"webPic":"https://cdn.test/d126.webp","vswitch":{"web":1}},'
    '"100085":{"id":100085,"webPic":"https://cdn.test/d100085.png",'
    '"vswitch":{"web":"1"}}}}}';

/// 1×1 透明 PNG(图 URL 请求成功即可,内容只要能过解码)。
final List<int> _kTinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhf'
  'DwAChwGA60e6kgAAAABJRU5ErkJggg==',
);

Future<HttpServer> _startFixtureServer() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((request) async {
    final path = request.uri.path;
    final body = path.contains('fans_medal_web_v5')
        ? _kFansConfigJson.codeUnits
        : path.contains('inter_com_w_anchor_rights')
        ? _kRightsJson.codeUnits
        : _kTinyPng;
    request.response.add(body);
    await request.response.close();
  });
  return server;
}

DanmakuMessage _diamondUser(
  String uid, {
  required int months,
  required int diafid,
}) {
  return DanmakuMessage(
    type: DanmakuMessageType.chat,
    roomId: '63136',
    userName: 'u$uid',
    userId: uid,
    text: 'hi',
    badgeName: '保飞派',
    badgeLevel: 20,
    badges: [
      DanmakuBadge(
        name: '保飞派',
        level: 20,
        months: months,
        diamondIconId: diafid,
      ),
    ],
    rawType: 'chatmsg',
  );
}

void main() {
  late HttpServer server;
  final requestedUrls = <Uri>[];

  setUp(() async {
    server = await _startFixtureServer();
    // 顺序敏感:必须先装 overrides 再首次访问单例 —— _client 是构造期
    // 创建的 IOClient,HttpClient() 在创建时读取 HttpOverrides.global。
    HttpOverrides.global = _RewriteOverrides(
      server.port,
      requestedUrls.add,
    );
    DouyuFansMedalAssets.instance.reset();
    requestedUrls.clear();
    addTearDown(() {
      HttpOverrides.global = null;
      server.close(force: true);
      DouyuFansMedalAssets.instance.reset();
    });
  });

    testWidgets('钻粉 suffix 图按 diafid 区分:装扮款×2 + 默认款×1', (
    tester,
  ) async {
    // 预热配置(真实 IO 走 runAsync,重写后命中本地 fixture)。
    await tester.runAsync(() async {
      final config = await DouyuFansMedalAssets.instance.get();
      expect(config, isNotNull);
      expect(config!.diamondIconByDiafid, hasLength(2));
      expect(config.diamondSuffixUrl(126), 'https://cdn.test/d126.webp');
      expect(config.diamondSuffixUrl(100085), 'https://cdn.test/d100085.png');
      expect(config.diamondSuffixUrl(0), isNull);
    });

    final connector = _FakeDanmakuConnector();
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(500, 1200);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          danmakuRegistryProvider.overrideWithValue(
            _registryFor('douyu', connector),
          ),
        ],
        child: MaterialApp(
          theme: ZishuTheme.dark(),
          home: Scaffold(
            body: SizedBox(
              width: 392,
              child: PlaySidePanel(site: 'douyu', roomId: '63136'),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 面板自身的网络在预热完成后恢复正常直连(overrides 仅服务预热)。
    HttpOverrides.global = null;

    final session = connector.session;
    expect(session, isNotNull);
    session!
      ..emitConnected()
      ..push(_diamondUser('a', months: 27, diafid: 126))
      ..push(_diamondUser('b', months: 40, diafid: 100085))
      ..push(_diamondUser('c', months: 6, diafid: 0));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // 翻译默认开启(译文就绪才放行),假时钟推过 2.5s 超时兜底,消息才会
    // 落入显示队列。
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 100));

    final badgeUrls = tester
        .widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage))
        .map((w) => w.imageUrl)
        .toSet();
    // 三个用户应分别请求:126 装扮款 webp / 100085 装扮款 png / 默认款 PNG。
    expect(
      badgeUrls,
      containsAll(<String>[
        'https://cdn.test/d126.webp',
        'https://cdn.test/d100085.png',
        kDouyuDiamondFanSuffixUrl,
      ]),
      reason: '钻粉 suffix 图必须按 diafid 区分(用户报「全是一种样式」)',
    );
    // 泵过翻译协调器的 6s 重试 Timer,避免测试结束时报 pending timer。
    await tester.pump(const Duration(seconds: 8));
  });
}
