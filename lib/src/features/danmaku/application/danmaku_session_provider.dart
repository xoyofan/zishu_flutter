/// 侧栏聊天用的弹幕会话 provider(A4)。
///
/// 按 `(site, roomId)` 订阅站点 [DanmakuConnector],把归一后的
/// [DanmakuMessage] 流暴露给 UI(侧栏聊天列表 / 后续叠加层共用同一会话)。
///
/// ## 必须遵守的两条 Riverpod 约束(项目已踩过的坑)
/// 1. **autoDispose**:切房/离开播放页后要真正触发 `ref.onDispose`。非 autoDispose
///    时最后一个 listener 关闭不会触发 onDispose,旧房间连接永不 `close()`(连接
///    泄漏),且 generation fence 形同虚设(旧房迟到消息串入)。
/// 2. **build() 内绝不写 state**:`build()` 的返回值才是初始状态,期间写入会被静默
///    丢弃。而 async 函数在首个 `await` 之前是同步执行的,「在 build() 里调用 async
///    的 `_connect()`」会把前半段同步跑进 build —— 一旦那段写 state 就会抛错并在
///    await 之前中断(表现为永远停在 connecting、一条消息收不到、过期会话不 close)。
///    故:能力判定直接在 build() 内 `return`;真正的连接推迟到 `Future.microtask`。
///
/// ## 数据来源
/// 站点 connector 从 [danmakuRegistryProvider] 取(默认真实 [buildSiteRegistry]),
/// 单测可 override 注入 fake connector 以确定性驱动消息流,不必依赖公网。
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/application/providers.dart' show useRealParser;

/// 单房间保留的弹幕条数上限(侧栏只展示最近若干条,长跑不无限涨)。
const int kChatFeedMax = 200;

/// 自动重试次数上限(不含首次连接):连续失败耗尽预算后保持「未连接」态,
/// 等待侧栏「重新连接弹幕」手动刷新,不做无限重试风暴。
const int kDanmakuConnectMaxRetries = 3;

/// 连接失败自动重试的基准退避延时:第 n 次重试等待 base * 2^(n-1)
/// (默认 800ms → 1.6s → 3.2s)。真机背景:douyu 对快速重连有限流,
/// 「切房回来首连被拒、稍后手动刷新才成功」——有限次退避既能穿过限流窗口,
/// 又不会对服务器形成重连风暴。单测 override 为 Duration.zero 确定性驱动。
final danmakuRetryBaseDelayProvider = Provider<Duration>(
  (ref) => const Duration(milliseconds: 800),
);

/// 站点注册表来源:默认真实注册表,但**仅在 `--dart-define=ZISHU_REAL_PARSER=true`
/// 时启用**——与 `roomSourceProvider`/`browseSourceProvider` 同源同语义。
///
/// fixture 模式(默认,含全部 widget 测试)下返回空注册表 → 侧栏显示「当前站点
/// 暂不支持弹幕」空态。这不是功能阉割,而是必须的:若 fixture 下也去 `connect`,
/// `DouyuDanmakuConnector` 会真的发起 WebSocket 连接,在 widget 测试里留下 pending
/// timer,污染其它用例(实测 `layout_test.dart` 的 sidePanelToggle 因此失败);
/// 也与「fixture 阶段不依赖公网」的项目约定一致。
///
/// 单测注入 fake connector:override 本 provider 即可绕过该开关。
final danmakuRegistryProvider = Provider<SiteRegistry>(
  (ref) => useRealParser ? buildSiteRegistry() : SiteRegistry(),
);

/// 弹幕消息的保序环形追加:FIFO,超出 [max] 丢弃最旧者。
///
/// 纯函数,便于单测确定性验证上限行为。
List<DanmakuMessage> appendDanmakuFeed(
  List<DanmakuMessage> list,
  DanmakuMessage message, {
  int max = kChatFeedMax,
}) {
  final next = List<DanmakuMessage>.of(list)..add(message);
  if (next.length > max) {
    next.removeRange(0, next.length - max);
  }
  return next;
}

/// 侧栏棋天列表的会话视图状态。
class DanmakuChatState {
  const DanmakuChatState({
    this.messages = const <DanmakuMessage>[],
    this.connection = DanmakuSessionState.disconnected,
    this.supported = true,
  });

  /// 已消费的弹幕(最新在末尾)。
  final List<DanmakuMessage> messages;

  /// 连接状态,对齐 [DanmakuSessionState]。
  final DanmakuSessionState connection;

  /// 该站点/房间是否支持弹幕;false 为明确空态(非异常)。
  final bool supported;

  /// 是否处于明确空态(站点不支持弹幕)。
  bool get isUnsupported => !supported;

  DanmakuChatState copyWith({
    List<DanmakuMessage>? messages,
    DanmakuSessionState? connection,
    bool? supported,
  }) {
    return DanmakuChatState(
      messages: messages ?? this.messages,
      connection: connection ?? this.connection,
      supported: supported ?? this.supported,
    );
  }
}

/// 弹幕会话入参:(site, roomId)。
typedef DanmakuSessionParams = ({String site, String roomId});

/// 侧栏聊天消费的弹幕会话控制器:family by (site, roomId)。
///
/// 一条会话同时服务侧栏聊天列表(本 provider)与后续叠加层——两者共用同一
/// [DanmakuSession],不重复建连。
class DanmakuSessionController extends Notifier<DanmakuChatState> {
  DanmakuSessionController(this._params);

  final DanmakuSessionParams _params;

  int _generation = 0;
  DanmakuSession? _session;
  StreamSubscription<DanmakuMessage>? _messageSub;
  StreamSubscription<DanmakuSessionState>? _stateSub;

  /// 当前自动重试轮次的退避等待 Timer(未在等待时为 null)。
  Timer? _retryTimer;

  /// 已连续失败的自动重试预算计数:连接成功或手动 reconnect 时重置。
  int _failedAttempts = 0;

  @override
  DanmakuChatState build() {
    final site = _params.site;
    final roomId = _params.roomId;
    final myGeneration = ++_generation;

    // 切房/销毁时同步失效当前代际并异步释放会话(close 异步,fire-and-forget)。
    ref.onDispose(() {
      _generation += 1;
      _retryTimer?.cancel();
      _retryTimer = null;
      unawaited(_releaseSession());
    });

    final connector = ref.read(danmakuRegistryProvider)[site]?.danmaku;

    // 站点未注册/未实现弹幕/声明不支持 → 明确空态,不发 connect、不抛异常。
    if (connector == null || !connector.capabilities.danmaku) {
      return const DanmakuChatState(
        messages: <DanmakuMessage>[],
        connection: DanmakuSessionState.disconnected,
        supported: false,
      );
    }

    // 连接必须推迟到 build() 之后:flutter 约束见文件头。
    unawaited(
      Future<void>.microtask(
        () => _connect(myGeneration, site, roomId, connector),
      ),
    );

    return const DanmakuChatState(
      messages: <DanmakuMessage>[],
      connection: DanmakuSessionState.connecting,
      supported: true,
    );
  }

  Future<void> _releaseSession() async {
    final messageSub = _messageSub;
    final stateSub = _stateSub;
    final session = _session;
    _messageSub = null;
    _stateSub = null;
    _session = null;
    await messageSub?.cancel();
    await stateSub?.cancel();
    await session?.close();
  }

  Future<void> _connect(
    int myGeneration,
    String site,
    String roomId,
    DanmakuConnector connector,
  ) async {
    // build 后可能已切房/销毁(onDispose 自增过 generation),直接放弃。
    if (myGeneration != _generation) return;

    final DanmakuSession session;
    try {
      session = await connector.connect(
        DanmakuSessionRequest(site: site, roomId: roomId),
      );
    } catch (_) {
      // 连接失败:保持「连接中」进入退避重试流程(预算耗尽由
      // [_scheduleRetry] 落回「未连接」);fence 失效则忽略。
      if (myGeneration == _generation) {
        _scheduleRetry(myGeneration, site, roomId, connector);
      }
      return;
    }

    // fence:期间已切房/销毁,立刻释放过期会话,不订阅、不漏消息。
    if (myGeneration != _generation) {
      unawaited(session.close());
      return;
    }

    // 连接成功:重置自动重试预算并撤销待发的退避 Timer
    // (下一轮异常断开从零重新计 [kDanmakuConnectMaxRetries] 次)。
    _failedAttempts = 0;
    _retryTimer?.cancel();
    _retryTimer = null;

    _session = session;
    _messageSub = session.messages.listen(
      (message) => _onMessage(myGeneration, message),
    );
    _stateSub = session.states.listen((connectionState) {
      if (myGeneration != _generation) return;
      if (connectionState == DanmakuSessionState.disconnected) {
        // 异常断开(服务端掐流/网络掉线;各站连接器自身不重连,
        // 见 live_parser danmaku onDone/onError → disconnected):
        // 转入有限次退避重试,等待期保持「连接中」,预算耗尽落回「未连接」。
        _scheduleRetry(myGeneration, site, roomId, connector);
        return;
      }
      state = state.copyWith(connection: connectionState);
    });

    // 会话已建立即视为已连接(部分 connector 不回发 connected 状态)。
    state = state.copyWith(connection: DanmakuSessionState.connected);
  }

  /// 连接失败/异常断开后的有限次指数退避重试。
  ///
  /// - 代际 fence:排程或触发时已切房/销毁/手动重连(代际自增)则放弃;
  /// - 预算:连续失败 [kDanmakuConnectMaxRetries] 次后放弃并保持「未连接」,
  ///   交还用户手动刷新;连接成功重置(见 [_connect]);
  /// - 退避:第 n 次等待 base * 2^(n-1)([danmakuRetryBaseDelayProvider])。
  void _scheduleRetry(
    int myGeneration,
    String site,
    String roomId,
    DanmakuConnector connector,
  ) {
    if (myGeneration != _generation) return;
    if (_failedAttempts >= kDanmakuConnectMaxRetries) {
      state = state.copyWith(connection: DanmakuSessionState.disconnected);
      return;
    }
    // 退避等待期间保持「连接中」:自动重试仍在流程内,不闪「未连接」。
    state = state.copyWith(connection: DanmakuSessionState.connecting);
    final delay =
        ref.read(danmakuRetryBaseDelayProvider) * (1 << _failedAttempts);
    _failedAttempts += 1;
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, () {
      _retryTimer = null;
      // 等待期间已切房/销毁/手动重连:放弃本轮自动重试。
      if (myGeneration != _generation) return;
      unawaited(
        Future<void>.microtask(() async {
          await _releaseSession();
          await _connect(myGeneration, site, roomId, connector);
        }),
      );
    });
  }

  void _onMessage(int generation, DanmakuMessage message) {
    // fence:旧房间迟到的消息直接丢弃。
    if (generation != _generation) return;
    state = state.copyWith(
      messages: appendDanmakuFeed(state.messages, message),
    );
  }

  /// 重连:销毁当前会话并重新走一次 connect。
  ///
  /// 供侧栏状态条的「重新连接弹幕」按钮调用;不动 current messages(历史保留)。
  /// 手动重连同时撤销待发的自动重试并重置其预算(手动刷新是重试耗尽后的出口)。
  void reconnect() {
    final site = _params.site;
    final roomId = _params.roomId;
    final connector = ref.read(danmakuRegistryProvider)[site]?.danmaku;
    if (connector == null || !connector.capabilities.danmaku) return;

    _retryTimer?.cancel();
    _retryTimer = null;
    _failedAttempts = 0;
    final myGeneration = ++_generation;
    state = state.copyWith(connection: DanmakuSessionState.connecting);
    unawaited(
      Future<void>.microtask(() async {
        await _releaseSession();
        await _connect(myGeneration, site, roomId, connector);
      }),
    );
  }
}

/// 侧栏聊天弹幕会话 provider:family by (site, roomId)。
///
/// **必须 autoDispose**(理由见文件头/类注释):`ref.onDispose` 只在 provider
/// 被销毁时触发,非 autoDispose 下切房不会销毁,旧连接泄漏且 fence 失效。
final danmakuSessionProvider = NotifierProvider.autoDispose
    .family<DanmakuSessionController, DanmakuChatState, DanmakuSessionParams>(
      DanmakuSessionController.new,
    );
