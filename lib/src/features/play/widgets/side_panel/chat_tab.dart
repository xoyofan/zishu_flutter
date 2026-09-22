part of '../play_side_panel.dart';

/// 一条展示用弹幕行数据:徽章等级(可空) + 用户名 + 正文。
///
/// 由真实 [DanmakuMessage] 映射而来(见 [_ChatRowData.fromMessage])。
/// 保留该轻量视图模型:列表只关心展示字段,不把解析包的整个模型透进 Widget 层。
class _ChatRowData {
  const _ChatRowData(
    this.user,
    this.message, {
    required this.site,
    this.fanName,
    this.fanLevel,
    this.badgeColorStart = 0,
    this.badgeColorEnd = 0,
    this.badgeColorBorder = 0,
    this.badgeTextColor = 0,
    this.badgeColorLevel = 0,
    this.userLevel = 0,
    this.color = 0,
    this.segments = const [],
  });

  final String user;
  final String message;

  /// 富文本段(空 = 纯文本,正文渲染回退单段 [message],零破坏)。
  final List<DanmakuSegment> segments;

  /// 平台 id:徽章/等级 pill 的样式分档依据(对齐 web ChatFanBadge/
  /// ChatUserLevelBadge 的 per-site 分支)。
  final String site;

  /// 粉丝团名(抖音协议无团名 → null,徽章退化为纯等级圆盘,
  /// 对齐 web ChatFanBadge 的 douyinTextFallback 分支)。
  final String? fanName;

  /// 粉丝团等级(null = 无粉丝牌)。
  final int? fanLevel;

  /// 粉丝牌渐变起止色(B 站协议色;0 = 未提供)。
  final int badgeColorStart;
  final int badgeColorEnd;
  final int badgeColorBorder;

  /// 粉丝牌文字色/等级数字色(B 站新协议;0 = 未提供,回落白/文字色)。
  final int badgeTextColor;
  final int badgeColorLevel;

  /// 用户等级(0 = 不渲染等级 pill)。
  final int userLevel;

  /// 正文颜色(0 = 默认)。当前侧栏按平台主题统一着色,保留字段以备后续。
  final int color;

  factory _ChatRowData.fromMessage(DanmakuMessage message, String site) {
    return _ChatRowData(
      message.userName,
      message.text,
      site: site,
      fanName: message.badgeLevel > 0 ? message.badgeName : null,
      fanLevel: message.badgeLevel > 0 ? message.badgeLevel : null,
      badgeColorStart: message.badgeColorStart,
      badgeColorEnd: message.badgeColorEnd,
      badgeColorBorder: message.badgeColorBorder,
      badgeTextColor: message.badgeTextColor,
      badgeColorLevel: message.badgeColorLevel,
      userLevel: message.userLevel,
      color: message.color,
      segments: message.segments,
    );
  }
}

/// 播放状态指示:聊天状态条左侧「播放中/已暂停/静音」文案 + 图标。
///
/// 组件内可配置参数,默认表达「播放中」;不引入 provider 依赖。状态文案
/// 一律避免全角冒号(见文件头硬约束),用半角括号区分静音态。
class PlaybackStatus {
  const PlaybackStatus({this.playing = true, this.muted = false});

  final bool playing;
  final bool muted;

  String get label => playing ? (muted ? '播放中(静音)' : '播放中') : '已暂停';
}

/// 聊天 tab:消费真实弹幕会话([danmakuSessionProvider]),含连接状态条 + 消息列表。
///
/// 能力:
/// - 状态条左侧播放状态指示 + 弹幕连接状态(已连接/连接中/未连接/当前站点不支持);
/// - 双队列节流(对齐 web useDanmaku):全量直通;限速时新消息进积压队列,
///   每 speed 秒从头部放一条进显示(首条立即、超限裁头丢最旧),速度滑杆即时生效;
/// - 默认锚定底部(最新消息在底部、历史向上翻):贴底时新消息自动跟随滚底;
///   用户上滑离底时暂停跟随,并显示「N 条新消息」跳底按钮;
/// - 状态条右侧「重新连接」按钮触发 [DanmakuSessionController.reconnect]。
class _ChatTab extends ConsumerStatefulWidget {
  const _ChatTab({
    required this.site,
    required this.roomId,
    required this.playbackStatus,
  });

  final String site;
  final String roomId;
  final PlaybackStatus playbackStatus;

  @override
  ConsumerState<_ChatTab> createState() => _ChatTabState();
}

class _ChatTabState extends ConsumerState<_ChatTab>
    with AutomaticKeepAliveClientMixin {
  final ScrollController _scrollController = ScrollController();

  /// 显示队列 A(对齐 web useDanmaku `chatMessages`):已放行的消息行,
  /// 最新在末尾;超 [_kChatDisplayLimit] 从头部裁掉最旧。
  final List<_ChatRowData> _displayRows = <_ChatRowData>[];

  /// 积压队列 B(对齐 web `chatPending`):仅限速模式使用,新消息先入队,
  /// 每 speed 秒从头部放一条进显示;超 [_kChatPendingLimit] 从头部裁掉最旧。
  final List<DanmakuMessage> _pendingMessages = <DanmakuMessage>[];

  /// 上一次 `chat.messages` 快照:会话侧只追加 + 裁头(`appendDanmakuFeed`),
  /// 元素对象引用稳定 → 按对象身份 diff 出本次真正新增的批次(每条消息只
  /// ingest 一次,天然去重)。
  List<DanmakuMessage>? _lastSnapshot;

  /// 用户是否贴底:贴底时新显示内容自动跟随滚底;离底时累计「N 条新消息」。
  bool _pinnedToBottom = true;

  /// 离底期间累计的新显示条数(「N 条新消息」按钮文案)。
  int _unseenCount = 0;

  /// 限速放行定时器(单次,放行后续排,对齐 web setTimeout 链)与其间隔(秒);
  /// 间隔变化(速度滑杆)时重启。
  Timer? _releaseTimer;
  int? _releaseIntervalSec;

  /// 房间代数:切房时自增。翻译是异步的,「译文就绪再放出」的等待期间
  /// 可能跨切房(State 复用不 dispose)——await 返回后代数不一致即丢弃,
  /// 防旧房消息串进新房列表(同 danmaku_session 的 generation fence 思路)。
  int _roomGeneration = 0;

  /// 显示队列出口的单条翻译等待上限:译文超时未到就以原文放行,
  /// 宁可原文也不无限拖住队列(协调器自身另有 6s 请求超时)。
  static const Duration _kTranslateWaitLimit = Duration(milliseconds: 2500);

  /// 显示队列上限(对齐 web useDanmaku `CHAT_DISPLAY_LIMIT = 200`)。
  static const int _kChatDisplayLimit = 200;

  /// 积压队列上限(对齐 web useDanmaku `CHAT_PENDING_LIMIT = 100`)。
  static const int _kChatPendingLimit = 100;

  /// TabBarView 只挂载当前页,切换 tab 会 dispose 离屏子页。若聊天页被销毁,
  /// `danmakuSessionProvider`(autoDispose)也会一并销毁 → 会话被 close、消息丢失,
  /// 切回聊天时重新建连从头开始。故聊天页必须 keepAlive,让会话跨 tab 存活。
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    // 用户上滑/下滑时维护贴底状态与「N 条新消息」显隐。
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void didUpdateWidget(covariant _ChatTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 切房(pushReplacement 重建面板、State 复用):双队列与放行进度全部归零
    // (对齐 web clearChatQueues),新会话首条重新立即显示,并恢复贴底 ——
    // 新房间首批内容出现即默认滚到底部(用户口径:默认从最底下往上走)。
    if (oldWidget.site != widget.site || oldWidget.roomId != widget.roomId) {
      _cancelReleaseTimer();
      _roomGeneration += 1; // 在途翻译放行作废,防旧房消息串入新房。
      _displayRows.clear();
      _pendingMessages.clear();
      _lastSnapshot = null;
      _unseenCount = 0;
      _pinnedToBottom = true;
    }
  }

  @override
  void dispose() {
    _cancelReleaseTimer();
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _cancelReleaseTimer() {
    _releaseTimer?.cancel();
    _releaseTimer = null;
    _releaseIntervalSec = null;
  }

  // ---- 双队列节流(对齐 web useDanmaku.ts 180-320 行)----

  /// 快照 diff:返回相对上次快照真正新增的消息。会话侧 `appendDanmakuFeed`
  /// 只在尾部追加、超上限从头部裁剪,故按「上次末条的对象身份」在新快照中
  /// 定位即可切出新增后缀(覆盖纯追加与「追加 + 裁头」两种形态);找不到
  /// 身份链(单帧涌入 ≥ 会话上限)时退化为全量重放。
  List<DanmakuMessage> _diffSnapshot(List<DanmakuMessage> snapshot) {
    final prev = _lastSnapshot;
    _lastSnapshot = snapshot;
    if (identical(prev, snapshot)) return const [];
    if (prev == null || prev.isEmpty || snapshot.isEmpty) return snapshot;
    final last = prev.last;
    for (var i = snapshot.length - 1; i >= 0; i -= 1) {
      if (identical(snapshot[i], last)) return snapshot.sublist(i + 1);
    }
    return snapshot;
  }

  /// ingest(对齐 web ingestChatBatch):
  /// - 限速关:新消息直通显示;限速期积压一并放出(web drainChatPendingToDisplay),
  ///   并停掉放行定时器;
  /// - 限速开:新消息进积压队列(超 [_kChatPendingLimit] 裁头丢最旧);显示
  ///   列表为空时首条立即放行(web pushChatPendingBatch);其余交给
  ///   [_ensureReleaseTimer] 按 speed 逐条放行。
  ///
  /// 翻译口径(用户 2026-09-20):**译文就绪才放行显示** —— 所有放行路径
  /// (直通批量 / 限速逐条 / 首条立即)都先经 [_translateForDisplay] 完成
  /// 中文化(有 2.5s 上限,超时以原文放行),显示列表里永远是终稿文本。
  void _ingest(
    List<DanmakuMessage> snapshot, {
    required bool throttled,
    required int intervalSec,
    required bool translateEnabled,
  }) {
    final batch = _diffSnapshot(snapshot);
    if (!throttled) {
      _cancelReleaseTimer();
      final outgoing = [...batch, ..._pendingMessages];
      _pendingMessages.clear();
      if (outgoing.isNotEmpty) {
        // 批内并行发起翻译(协调器去重/节流),按到达顺序逐条放行。
        unawaited(
          _drainToDisplay(outgoing, translateEnabled: translateEnabled),
        );
      }
      return;
    }
    if (batch.isNotEmpty) {
      _pendingMessages.addAll(batch);
      if (_pendingMessages.length > _kChatPendingLimit) {
        _pendingMessages.removeRange(
          0,
          _pendingMessages.length - _kChatPendingLimit,
        );
      }
      if (_displayRows.isEmpty) {
        // 首条立即显示(web pushChatPendingBatch:显示空且有积压即放一条)。
        unawaited(_releaseOnePending(translateEnabled: translateEnabled));
      }
    }
    _ensureReleaseTimer(intervalSec);
  }

  /// 批量放行(直通模式):并行提交翻译,按序 await、按序入显示队列;
  /// 每条落地即刷新(消息逐条浮现),全部完成后统一走滚动跟随。
  Future<void> _drainToDisplay(
    List<DanmakuMessage> messages, {
    required bool translateEnabled,
  }) async {
    final generation = _roomGeneration;
    final futures = [
      for (final message in messages)
        _translateForDisplay(message, enabled: translateEnabled),
    ];
    var added = 0;
    var touched = false;
    for (final future in futures) {
      final translated = await future;
      if (!mounted || generation != _roomGeneration) return;
      _pushTranslated(translated);
      added += 1;
      touched = true;
      // 每条落地即请求一帧:消息以帧粒度逐条浮现,不积攒到批末。
      setState(() {});
    }
    if (touched) _onDisplayGrew(added);
  }

  /// 追加进显示队列,超 [_kChatDisplayLimit] 裁头丢最旧
  /// (对齐 web pushChatDisplay + CHAT_DISPLAY_LIMIT)。入参必须是
  /// 已完成中文化的终稿消息(见 [_translateForDisplay])。
  void _pushTranslated(DanmakuMessage message) {
    _displayRows.add(_ChatRowData.fromMessage(message, widget.site));
    if (_displayRows.length > _kChatDisplayLimit) {
      _displayRows.removeRange(0, _displayRows.length - _kChatDisplayLimit);
    }
  }

  /// 显示队列出口的中文化:开关关 / 已是中文 → 原消息直通(零开销);
  /// 需翻译 → 逐段译文重建消息(表情段保留),超 [_kTranslateWaitLimit]
  /// 未就绪以原文放行 —— 宁可原文,不拖住整条聊天流。
  Future<DanmakuMessage> _translateForDisplay(
    DanmakuMessage message, {
    required bool enabled,
  }) async {
    if (!enabled) return message;
    List<DanmakuSegment> segments;
    try {
      segments = await ref
          .read(translationCoordinatorProvider)
          .translateBody(text: message.text, segments: message.segments)
          .timeout(_kTranslateWaitLimit, onTimeout: () => message.segments);
    } catch (_) {
      return message;
    }
    final unchanged = message.segments.isEmpty
        ? segments.isEmpty
        : listEquals(segments, message.segments);
    if (unchanged) return message;
    return DanmakuMessage(
      type: message.type,
      userName: message.userName,
      userId: message.userId,
      text: [for (final segment in segments) segment.text].join(),
      color: message.color,
      segments: segments,
      id: message.id,
      sentAt: message.sentAt,
      rawType: message.rawType,
      roomId: message.roomId,
    );
  }

  /// 从积压头部放行一条进显示(web releaseOneChatPending 的 shift 语义):
  /// 译文就绪(或超时回原文)后入显示队列并刷新;限速模式每 tick 一条,
  /// 翻译等待融入放行间隔,不占用 UI 帧。
  Future<void> _releaseOnePending({required bool translateEnabled}) async {
    if (_pendingMessages.isEmpty) return;
    final generation = _roomGeneration;
    final message = _pendingMessages.removeAt(0);
    final translated = await _translateForDisplay(
      message,
      enabled: translateEnabled,
    );
    if (!mounted || generation != _roomGeneration) return;
    _pushTranslated(translated);
    setState(() {});
    _onDisplayGrew(1);
  }

  /// 限速放行调度(web scheduleChatRelease / ensureChatReleaseTimer):
  /// 无积压不排表;已有定时器且间隔未变则不动;速度滑杆变化 → 重启定时器。
  void _ensureReleaseTimer(int intervalSec) {
    if (_pendingMessages.isEmpty) return;
    if (_releaseTimer != null && _releaseIntervalSec != intervalSec) {
      _releaseTimer!.cancel();
      _releaseTimer = null;
    }
    _releaseTimer ??= Timer(Duration(seconds: intervalSec), _onReleaseTick);
    _releaseIntervalSec = intervalSec;
  }

  /// 到点放行一条;积压未尽则按当前速度续排下一发(web releaseOneChatPending)。
  /// 速度在定时器存续期内变化时,下一次调度会用新速度(滑杆即时生效)。
  /// 放行等待译文期间不重入排程(定时器已置空),完成后续排。
  Future<void> _onReleaseTick() async {
    _releaseTimer = null;
    if (!mounted || _pendingMessages.isEmpty) return;
    await _releaseOnePending(
      translateEnabled: ref.read(settingsProvider).translationEnabled,
    );
    if (!mounted) return;
    if (_pendingMessages.isNotEmpty) {
      _ensureReleaseTimer(ref.read(settingsProvider).chatSpeed);
    }
  }

  /// 用户当前是否停在底部(容差 24px,避免像素误差导致误判)。
  bool get _isAtBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 24;
  }

  void _onScrollChanged() {
    if (!mounted) return;
    final atBottom = _isAtBottom;
    final changed =
        atBottom != _pinnedToBottom || (atBottom && _unseenCount > 0);
    _pinnedToBottom = atBottom;
    if (atBottom) _unseenCount = 0;
    if (changed) setState(() {});
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (!animate) {
      _scrollController.jumpTo(target);
      return;
    }
    _scrollController
        .animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        )
        .then((_) {
          // ListView.builder 惰性构建:尾部行未 realize 时 maxScrollExtent 可能
          // 滞后(只统计已构建行),动画目标偏短、落点差一至数行。落定后按最新
          // extent 校正一次,保证「回到底部」真的到底。被打断时该回调不来或被
          // pinned 守卫挡下,均无害。
          if (!mounted || !_scrollController.hasClients || !_pinnedToBottom) {
            return;
          }
          final position = _scrollController.position;
          if (position.pixels < position.maxScrollExtent - 0.5) {
            _scrollController.jumpTo(position.maxScrollExtent);
          }
        });
  }

  /// 新显示内容到达后:贴底时自动跟随滚底(首帧也在内 —— 默认锚底,
  /// 用户口径 2026-09-19:「默认应该从最底下往上走」);离底时仅累计未读。
  ///
  /// 滚动放在 post-frame:首帧 ListView 尚未挂载(hasClients=false)时也
  /// 能在挂载后跳到底部,修复旧实现「首帧吞掉滚动、列表停在顶部」的问题。
  void _onDisplayGrew(int added) {
    if (added <= 0) return;
    if (!_pinnedToBottom) {
      _unseenCount += added;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollToBottom(animate: false);
      }
    });
  }

  String _connectionLabel(DanmakuSessionState connection, bool supported) {
    if (!supported) return '弹幕不支持';
    return switch (connection) {
      DanmakuSessionState.connecting => '弹幕连接中',
      DanmakuSessionState.connected => '弹幕已连接',
      DanmakuSessionState.disconnected => '弹幕未连接',
    };
  }

  Color _connectionColor(
    DanmakuSessionState connection,
    bool supported,
    ZishuTokens tokens,
  ) {
    if (!supported) return tokens.textSecondary;
    return connection == DanmakuSessionState.connected
        ? tokens.liveBadge
        : tokens.textSecondary;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // AutomaticKeepAliveClientMixin 要求
    final tokens = context.tokens;
    final params = (site: widget.site, roomId: widget.roomId);
    // 聊天设置:总开关 + 消息渲染参数(字号/行距/透明度/节流,对齐 web
    // chatSettings,见 SideSettingsTab.vue 41-105 / useDanmaku.ts DEFAULT_CHAT)。
    final settings = ref.watch(settingsProvider);
    final chatEnabled = settings.chatEnabled;
    final chat = ref.watch(danmakuSessionProvider(params));
    if (!chatEnabled) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Text(
            '聊天已关闭',
            textAlign: TextAlign.center,
            style: context.textCaption,
          ),
        ),
      );
    }
    // 双队列 ingest + 限速放行(对齐 web useDanmaku):全量直通 / 逐条放行。
    // 翻译口径:译文就绪才放行显示(见 _ingest 注释)。
    _ingest(
      chat.messages,
      throttled: settings.chatThrottleMode == ChatThrottleMode.perNSeconds,
      intervalSec: settings.chatSpeed,
      translateEnabled: settings.translationEnabled,
    );
    final rows = _displayRows;

    final newCount = _pinnedToBottom ? 0 : _unseenCount;
    final messageFontSize = settings.chatFontSize.toDouble();
    final rowSpacing = settings.chatLineSpacing.toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: MediaQuery.textScalerOf(context).scale(31),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: context.tokens.surfaceSoft,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Row(
            children: [
              Icon(
                widget.playbackStatus.playing
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 11,
                color: widget.playbackStatus.playing
                    ? tokens.liveBadge
                    : tokens.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  widget.playbackStatus.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textCaption,
                ),
              ),
              const SizedBox(width: 12),
              Icon(
                Icons.circle,
                size: 7,
                color: _connectionColor(
                  chat.connection,
                  chat.supported,
                  tokens,
                ),
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  _connectionLabel(chat.connection, chat.supported),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textCaption,
                ),
              ),
              const Spacer(),
              // 对齐 web SideChatTab:图标 + 「刷新」文字的小按钮(高 24)。
              Tooltip(
                message: '重新连接弹幕',
                child: TextButton(
                  key: const Key('play-side-chat-refresh'),
                  onPressed: chat.supported
                      ? () => ref
                            .read(danmakuSessionProvider(params).notifier)
                            .reconnect()
                      : null,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 24),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: tokens.textSecondary,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.refresh_rounded, size: 13),
                      const SizedBox(width: 2),
                      Text(
                        '刷新',
                        style: TextStyle(
                          fontSize: AppFontSize.caption,
                          height: 1,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              // 聊天区不透明度(web chatSettings.opacity,10-100 → 0.1-1.0)。
              Opacity(
                key: const Key('play-side-chat-opacity'),
                opacity: settings.chatOpacity / 100,
                child: rows.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.md),
                          child: Text(
                            chat.isUnsupported ? '当前站点暂不支持弹幕' : '暂无弹幕，等待水友发言…',
                            textAlign: TextAlign.center,
                            style: context.textCaption,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.sm,
                          AppSpacing.xs,
                          AppSpacing.sm,
                          AppSpacing.sm,
                        ),
                        itemCount: rows.length,
                        itemBuilder: (context, index) => Padding(
                          key: const Key('play-side-chat-row'),
                          // 行间距 = web chatSettings.gap(0-16px)。
                          padding: EdgeInsets.only(bottom: rowSpacing),
                          child: _ChatRow(
                            data: rows[index],
                            fontSize: messageFontSize,
                          ),
                        ),
                      ),
              ),
              if (newCount > 0)
                // 对齐 web .chat-new-bar:底部水平居中,距底 0.5rem=8。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Center(
                    child: _NewMessagesButton(
                      count: newCount,
                      onTap: () {
                        setState(() => _unseenCount = 0);
                        _scrollToBottom();
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 「N 条新消息」跳底按钮:用户离开底部且有新消息时浮在列表底部居中
/// (对齐 web .chat-new-bar;字号 0.8rem→12)。
class _NewMessagesButton extends StatelessWidget {
  const _NewMessagesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.tokens.accent,
      borderRadius: AppRadius.allMd,
      child: InkWell(
        key: const Key('play-side-chat-jump-bottom'),
        borderRadius: AppRadius.allMd,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Text(
            '$count 条新消息',
            style: const TextStyle(
              fontSize: AppFontSize.bodySecondary,
              height: 1.1,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
