/// 登录会话状态层:data-server 账号登录 + 本机凭据缓存 + 启动自动登录。
///
/// 启动自动登录链(满足「每次打开就是登录的」):
/// 1. 缓存 token 未过期 → `/auth/me` 校验通过 → 直接进入登录态;
///    网络异常时**离线宽限**按已登录处理(token 还在缓存,恢复网络后自动可用);
/// 2. 校验 401/过期 → 有缓存账密则静默重登并刷新 token;
///    无缓存账密时用默认账号([kDefaultAuthUsername])兜底静默登录;
/// 3. 都没有 → 匿名态(顶栏头像打开登录框手动登录)。
///
/// 凭据缓存只落本机 SharedPreferencesAsync(`zishu.auth.*` 键,明文但不出本机),
/// 不进仓库、不进构建产物;不勾「记住密码」时只缓存 token(30 天有效)。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'data_server_api.dart';

/// 默认账号(本机自用客户端;dart-define 可覆盖,传空字符串即关闭默认自动登录):
/// 本机无缓存凭据时用于静默登录并缓存,满足「默认登录我的账号、打开即登录」。
const String kDefaultAuthUsername = String.fromEnvironment(
  'ZISHU_AUTH_USER',
  defaultValue: 'xoyofan',
);

const String kDefaultAuthPassword = String.fromEnvironment(
  'ZISHU_AUTH_PASS',
  defaultValue: 'sf2012',
);

/// 本机缓存键(SharedPreferencesAsync,无 flutter. 前缀)。
const String _kToken = 'zishu.auth.token';
const String _kExpiresAt = 'zishu.auth.expiresAt';
const String _kUserId = 'zishu.auth.userId';
const String _kUsername = 'zishu.auth.username';
const String _kPassword = 'zishu.auth.password';

/// 登录阶段:restoring(启动恢复中) → authenticated / anonymous。
enum AuthPhase { restoring, authenticated, anonymous }

class AuthState {
  const AuthState({required this.phase, this.session, this.lastError});

  final AuthPhase phase;
  final DataSession? session;

  /// 最近一次手动登录的失败原因(登录框展示)。
  final String? lastError;

  AuthState copyWith({AuthPhase? phase, DataSession? session, String? lastError}) {
    return AuthState(
      phase: phase ?? this.phase,
      session: session ?? this.session,
      lastError: lastError,
    );
  }

  /// 可用的 token(已登录才有)。
  String? get token => phase == AuthPhase.authenticated ? session?.token : null;
}

class AuthController extends Notifier<AuthState> {
  final DataServerApi _api = DataServerApi();

  @override
  AuthState build() {
    // 启动异步恢复登录态;完成前 UI 呈现恢复中(顶栏头像按占位渲染)。
    Future.microtask(_restore);
    return const AuthState(phase: AuthPhase.restoring);
  }

  /// 启动自动登录链,详见库注释。
  Future<void> _restore() async {
    // 存储读取全部收进 try:存储不可用(测试环境未设平台实例/系统异常)直接匿名,
    // 绝不落到网络调用(fake_async 测试环境禁止真实 HTTP)。
    String? token;
    int expiresAt = 0;
    int cachedUserId = 0;
    String cachedUser = '';
    String? password;
    try {
      final prefs = SharedPreferencesAsync();
      token = await prefs.getString(_kToken);
      expiresAt = (await prefs.getInt(_kExpiresAt)) ?? 0;
      cachedUserId = (await prefs.getInt(_kUserId)) ?? 0;
      cachedUser = await prefs.getString(_kUsername) ?? '';
      password = await prefs.getString(_kPassword);
    } catch (_) {
      state = const AuthState(phase: AuthPhase.anonymous);
      return;
    }

    // 1) 缓存 token 有效 → /auth/me 校验;网络异常 → 离线宽限按已登录呈现。
    if (token != null &&
        token.isNotEmpty &&
        DateTime.now().millisecondsSinceEpoch < expiresAt - 60000) {
      try {
        final username = await _api.checkToken(token);
        if (username != null) {
          state = AuthState(
            phase: AuthPhase.authenticated,
            session: DataSession(
              token: token,
              expiresAt: expiresAt,
              userId: cachedUserId,
              username: username,
            ),
          );
          return;
        }
      } on Exception {
        // 网络不通(checkToken 401 返回 null,非 401 异常才会到这):
        // 离线宽限,token 未过期,恢复网络后自动可用。
        state = AuthState(
          phase: AuthPhase.authenticated,
          session: DataSession(
            token: token,
            expiresAt: expiresAt,
            userId: cachedUserId,
            username: cachedUser,
          ),
        );
        return;
      }
      // 401 → token 失效,继续走静默重登。
    }

    // 2) 缓存账密 → 静默重登;无缓存账密时用默认账号兜底(见 kDefaultAuth*)。
    final username = cachedUser.isNotEmpty ? cachedUser : kDefaultAuthUsername;
    final secret = (password != null && password.isNotEmpty)
        ? password
        : (username.isNotEmpty && username == kDefaultAuthUsername
            ? kDefaultAuthPassword
            : null);
    if (username.isNotEmpty && secret != null && secret.isNotEmpty) {
      try {
        final session = await _api.login(username, secret);
        await _cacheSession(session, keepPassword: true);
        state = AuthState(phase: AuthPhase.authenticated, session: session);
        return;
      } on Exception {
        // 重登失败(密码改了/服务不可达):落到匿名,错误信息不阻塞启动。
      }
    }

    // 3) 匿名态:顶栏头像打开登录框手动登录。
    state = const AuthState(phase: AuthPhase.anonymous);
  }

  /// 手动登录(登录框)。成功后缓存会话;[remember] 时同时缓存账密供下次静默重登。
  Future<bool> login(String username, String password,
      {bool remember = true}) async {
    try {
      final session = await _api.login(username, password);
      await _cacheSession(session, keepPassword: remember);
      state = AuthState(phase: AuthPhase.authenticated, session: session);
      return true;
    } on DataServerUnauthorized {
      state = state.copyWith(lastError: '用户名或密码错误');
      return false;
    } on DataServerException catch (e) {
      state = state.copyWith(lastError: e.message);
      return false;
    }
  }

  /// 退出登录:清空本机缓存(含账密)并转匿名。
  Future<void> logout() async {
    final prefs = SharedPreferencesAsync();
    for (final key in [_kToken, _kExpiresAt, _kUserId, _kUsername, _kPassword]) {
      try {
        await prefs.remove(key);
      } catch (_) {}
    }
    state = const AuthState(phase: AuthPhase.anonymous);
  }

  Future<void> _cacheSession(DataSession session,
      {required bool keepPassword}) async {
    final prefs = SharedPreferencesAsync();
    try {
      await prefs.setString(_kToken, session.token);
      await prefs.setInt(_kExpiresAt, session.expiresAt);
      await prefs.setInt(_kUserId, session.userId);
      await prefs.setString(_kUsername, session.username);
      if (!keepPassword) await prefs.remove(_kPassword);
    } catch (_) {
      // 写缓存失败不影响本次登录态。
    }
  }
}

/// 登录会话 provider(应用级)。
final authProvider = NotifierProvider<AuthController, AuthState>(AuthController.new);
