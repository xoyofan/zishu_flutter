/// data-server 远程数据服务客户端:账号登录(JWT) + 我的关注云同步。
///
/// 服务端为独立部署的 Node/TS `data-server`(与解析 server 完全分离,
/// 见 docs/implementation-plan.md「远程 data-server」节),API 契约:
/// - `POST /api/auth/login` `{username,password}` → `{ok,token,expiresAt,user{id,username}}`
/// - `GET  /api/auth/me`(Bearer)           → `{ok,user}`(401 = 未登录/过期)
/// - `GET  /api/me/follows`(Bearer)        → `{ok,follows[],updatedAt}`
/// - `POST /api/me/follows`(Bearer) `{follows[]}` → 服务端**全量替换**并按
///   `clientUpdatedAt` 逐条合并(键 = site:roomId),因此整表推送即可同步删除。
library;

import 'package:dio/dio.dart';

/// 生产部署地址(SFVideoLive data-server)。
/// 自建/调试可用 `--dart-define=ZISHU_DATA_SERVER_URL=<url>` 覆盖。
const String kDefaultDataServerUrl = 'http://106.14.46.209:8765';

const String kDataServerUrl = String.fromEnvironment(
  'ZISHU_DATA_SERVER_URL',
  defaultValue: kDefaultDataServerUrl,
);

/// 登录会话:JWT + 过期时间(epoch ms) + 用户信息。
class DataSession {
  const DataSession({
    required this.token,
    required this.expiresAt,
    required this.userId,
    required this.username,
  });

  factory DataSession.fromJson(Map<String, dynamic> json) {
    final user = (json['user'] as Map?) ?? const {};
    return DataSession(
      token: json['token']?.toString() ?? '',
      expiresAt: (json['expiresAt'] as num?)?.toInt() ?? 0,
      userId: (user['id'] as num?)?.toInt() ?? 0,
      username: user['username']?.toString() ?? '',
    );
  }

  final String token;
  final int expiresAt;
  final int userId;
  final String username;

  /// token 是否已过有效期(留 60s 余量)。
  bool get isExpired =>
      DateTime.now().millisecondsSinceEpoch >= expiresAt - 60000;
}

/// 远端关注条目:data-server `StoredFollowItem` 契约字段。
/// zishu 侧只需要其中子集,多余字段(lastLiveAt/streamHabit 等)透传保留。
class RemoteFollow {
  const RemoteFollow({
    required this.site,
    required this.id,
    required this.title,
    required this.anchor,
    required this.cover,
    required this.avatar,
    required this.addedAt,
    required this.superFollow,
    required this.liveNotify,
    required this.clientUpdatedAt,
    this.lastLiveAt = 0,
    this.liveStartAt = 0,
  });

  factory RemoteFollow.fromJson(Map<String, dynamic> json) {
    return RemoteFollow(
      site: json['site']?.toString() ?? '',
      id: json['id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      anchor: json['anchor']?.toString() ?? '',
      cover: json['cover']?.toString() ?? '',
      avatar: json['avatar']?.toString() ?? '',
      addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      superFollow: json['super'] == true,
      liveNotify: json['liveNotify'] == true,
      clientUpdatedAt: (json['clientUpdatedAt'] as num?)?.toInt() ?? 0,
      lastLiveAt: (json['lastLiveAt'] as num?)?.toInt() ?? 0,
      liveStartAt: (json['liveStartAt'] as num?)?.toInt() ?? 0,
    );
  }

  final String site;
  final String id;
  final String title;
  final String anchor;
  final String cover;
  final String avatar;
  final int addedAt;
  final bool superFollow;
  final bool liveNotify;
  final int clientUpdatedAt;
  final int lastLiveAt;
  final int liveStartAt;

  /// 稳定键:平台 + 房间号(与 FollowEntry.key 同构)。
  String get key => '$site:$id';

  Map<String, dynamic> toJson() => {
        'site': site,
        'id': id,
        'title': title,
        'anchor': anchor,
        'cover': cover,
        'avatar': avatar,
        'addedAt': addedAt,
        'super': superFollow,
        'liveNotify': liveNotify,
        'clientUpdatedAt': clientUpdatedAt,
        'lastLiveAt': lastLiveAt,
        'liveStartAt': liveStartAt,
      };
}

/// 登录/会话类业务错误(区别于网络异常,UI 可直接展示 message)。
class DataServerException implements Exception {
  const DataServerException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// token 失效(401):调用方据此走静默重登或转匿名。
class DataServerUnauthorized implements Exception {
  const DataServerUnauthorized();
  @override
  String toString() => '登录已过期';
}

class DataServerApi {
  DataServerApi({String? baseUrl})
      : _dio = Dio(
          BaseOptions(
            baseUrl: baseUrl ?? kDataServerUrl,
            connectTimeout: const Duration(seconds: 8),
            receiveTimeout: const Duration(seconds: 12),
          ),
        );

  final Dio _dio;

  Map<String, dynamic> _body(Response<dynamic> r) {
    final data = r.data;
    if (data is Map<String, dynamic>) return data;
    if (data is Map) return data.map((k, v) => MapEntry(k.toString(), v));
    return const {};
  }

  /// 把 Dio 异常翻译成业务异常(服务端 error 字段是中文可直显)。
  Exception _translate(DioException e) {
    final status = e.response?.statusCode;
    final data = e.response?.data;
    final message = data is Map ? data['error']?.toString() : null;
    if (status == 401) return const DataServerUnauthorized();
    if (message != null && message.isNotEmpty) return DataServerException(message);
    return DataServerException('网络异常(${e.type.name})');
  }

  /// 登录:成功返回会话,失败抛 [DataServerException](账密错误为 401→[DataServerUnauthorized])。
  Future<DataSession> login(String username, String password) async {
    try {
      final r = await _dio.post('/api/auth/login', data: {
        'username': username,
        'password': password,
      });
      final body = _body(r);
      if (body['ok'] != true) {
        throw DataServerException(body['error']?.toString() ?? '登录失败');
      }
      return DataSession.fromJson(body);
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  /// 校验 token:有效返回用户名;401 返回 null;网络错误原样抛出(调用方做离线宽限)。
  Future<String?> checkToken(String token) async {
    try {
      final r = await _dio.get('/api/auth/me',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      final body = _body(r);
      if (body['ok'] != true) return null;
      final user = (body['user'] as Map?) ?? const {};
      return user['username']?.toString();
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) return null;
      rethrow;
    }
  }

  /// 拉取我的关注(登录态)。
  Future<List<RemoteFollow>> fetchFollows(String token) async {
    try {
      final r = await _dio.get('/api/me/follows',
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      final body = _body(r);
      if (body['ok'] != true) {
        throw DataServerException(body['error']?.toString() ?? '拉取关注失败');
      }
      final list = body['follows'];
      return [
        if (list is List)
          for (final item in list)
            if (item is Map)
              RemoteFollow.fromJson(item.map((k, v) => MapEntry(k.toString(), v))),
      ];
    } on DioException catch (e) {
      throw _translate(e);
    }
  }

  /// 全量推送我的关注(服务端整表替换 + clientUpdatedAt 合并,删除随之同步)。
  Future<void> pushFollows(String token, List<RemoteFollow> items) async {
    try {
      final r = await _dio.post('/api/me/follows',
          data: {'follows': [for (final i in items) i.toJson()]},
          options: Options(headers: {'Authorization': 'Bearer $token'}));
      final body = _body(r);
      if (body['ok'] != true) {
        throw DataServerException(body['error']?.toString() ?? '同步关注失败');
      }
    } on DioException catch (e) {
      throw _translate(e);
    }
  }
}
