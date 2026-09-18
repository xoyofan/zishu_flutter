/// 播放页右侧信息栏:主播信息头 + 聊天/关注/推荐/设置四个 Tab。
///
/// 结构对齐 SFVideoLive `PlaySidePanel.vue` / `SideHeader.vue`:
/// - 信息头约 3.35rem,左侧主播头像与状态按钮;
/// - 中部主播名/关注/开播与统计;
/// - 右侧关注/超关两枚纵向操作按钮;
/// - 下方四等分 Tab,默认聊天。
///
/// [payload] 可选:传入真实 live_parser 解析结果后,信息头直接显示主播、标题、
/// 分类和头像;不传时仍可作为通用空状态侧栏使用。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../danmaku/application/danmaku_session_provider.dart';
import '../../danmaku/widgets/danmaku_settings_dialog.dart';
import '../../follow/application/follow_provider.dart';
import '../../follow/application/follow_sort.dart';
import '../../follow/application/settings_provider.dart';
import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import 'play_meta_bar.dart';
import 'play_recommend_panel.dart';
import 'play_room_grid.dart';

class PlaySidePanel extends ConsumerStatefulWidget {
  const PlaySidePanel({
    super.key,
    this.site,
    this.roomId,
    this.payload,
    this.onToggleFollow,
    this.onToggleSuperFollow,
    this.playbackStatus = const PlaybackStatus(),
    this.compactHeader = false,
  });

  final String? site;
  final String? roomId;
  final RoomPayload? payload;
  final VoidCallback? onToggleFollow;
  final VoidCallback? onToggleSuperFollow;

  /// 聊天状态条左侧的播放状态指示(播放中/已暂停/静音)。
  /// 默认构造即可表达「播放中」,不引入 provider 依赖。
  final PlaybackStatus playbackStatus;

  /// 窄屏(移动竖屏堆叠)用移动「直播信息条」[PlayMetaBar] 代替桌面信息头。
  /// 两者同源数据与回调,仅排布不同;桌面(>=768)保持 false。
  final bool compactHeader;

  @override
  ConsumerState<PlaySidePanel> createState() => _PlaySidePanelState();
}

class _PlaySidePanelState extends ConsumerState<PlaySidePanel> {
  /// 关注上限:超出拒绝并提示(与「我的关注」页同源,落库前在此拦截)。
  static const int _kFollowCap = 200;

  String get _currentKey {
    final site = widget.site ?? widget.payload?.site ?? '';
    final roomId = widget.roomId ?? widget.payload?.roomId ?? '';
    return '$site:$roomId';
  }

  /// 当前房间 → 关注条目用的 [RoomSummary]。
  ///
  /// 注意 [RoomSummary.online] 在真实解析场景是**在线人数文案**;而 [RoomPayload]
  /// 没有携带在线人数(见 live_parser 模型),只有 [RoomPayload.isLive] 状态。
  /// 这里写入占位文案「直播中」而非空串,是为了让刚加入关注的房间在
  /// `FollowEntry.isLive`(口径 = online 非空)下立即算作在播,不被误当离线;
  /// 真实在线人数等下一次状态刷新(`refreshStatuses`)回填。
  RoomSummary _currentRoom(String site, String roomId) {
    final payload = widget.payload;
    return RoomSummary(
      site: site,
      roomId: roomId,
      title: payload?.title ?? '',
      anchorName: payload?.anchorName ?? '',
      cid: payload?.cid ?? '',
      category: payload?.category ?? '',
      online: payload?.isLive == true ? '直播中' : '',
      cover: payload?.cover ?? '',
    );
  }

  void _toggleFollow() {
    final key = _currentKey;
    final notifier = ref.read(followProvider.notifier);
    final list = ref.read(followProvider);
    final followed = list.any((entry) => entry.key == key);
    if (followed) {
      notifier.remove(key);
    } else if (list.length >= _kFollowCap) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('关注已达上限（200）')));
    } else {
      final site = widget.site ?? widget.payload?.site ?? '';
      final roomId = widget.roomId ?? widget.payload?.roomId ?? '';
      notifier.addFromRoom(_currentRoom(site, roomId));
    }
    widget.onToggleFollow?.call();
  }

  void _toggleSuperFollow() {
    final key = _currentKey;
    final notifier = ref.read(followProvider.notifier);
    final matched = ref.read(followProvider).where((e) => e.key == key);
    if (matched.isEmpty) {
      final site = widget.site ?? widget.payload?.site ?? '';
      final roomId = widget.roomId ?? widget.payload?.roomId ?? '';
      notifier.addFromRoom(_currentRoom(site, roomId), isSpecial: true);
    } else {
      notifier.toggleSpecial(key);
    }
    widget.onToggleSuperFollow?.call();
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final site = widget.site ?? payload?.site ?? '';
    final roomId = widget.roomId ?? payload?.roomId ?? '';
    final tokens = context.tokens;
    final followList = ref.watch(followProvider);
    final key = '$site:$roomId';
    final matched = followList.where((e) => e.key == key);
    final followed = matched.isNotEmpty;
    final superFollowed = matched.isNotEmpty && matched.first.isSpecial;

    return Container(
      key: const Key('play-side-panel'),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      child: DefaultTabController(
        length: 4,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 窄屏用移动信息条(紧凑排布),桌面用完整信息头 —— 同源数据与回调。
            if (widget.compactHeader)
              PlayMetaBar(
                payload: payload,
                followed: followed,
                superFollowed: superFollowed,
                onToggleFollow: _toggleFollow,
                onToggleSuperFollow: _toggleSuperFollow,
              )
            else
              _SideHeader(
                site: site,
                roomId: roomId,
                payload: payload,
                followed: followed,
                superFollowed: superFollowed,
                onToggleFollow: _toggleFollow,
                onToggleSuperFollow: _toggleSuperFollow,
              ),
            TabBar(
              tabs: const [
                KeyedSubtree(
                  key: Key('play-side-tab-chat'),
                  child: Tab(text: '聊天'),
                ),
                KeyedSubtree(
                  key: Key('play-side-tab-follow'),
                  child: Tab(text: '关注'),
                ),
                KeyedSubtree(
                  key: Key('play-side-tab-recommend'),
                  child: Tab(text: '推荐'),
                ),
                KeyedSubtree(
                  key: Key('play-side-tab-settings'),
                  child: Tab(text: '设置'),
                ),
              ],
              labelColor: tokens.brand,
              unselectedLabelColor: tokens.textSecondary,
              indicatorColor: tokens.brand,
              indicatorWeight: 2,
              dividerColor: tokens.border,
              labelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.15,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.15,
              ),
              labelPadding: EdgeInsets.zero,
              splashFactory: NoSplash.splashFactory,
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  _ChatTab(
                    site: site,
                    roomId: roomId,
                    playbackStatus: widget.playbackStatus,
                  ),
                  const _FollowPanel(),
                  _RecommendPanel(
                    site: site,
                    roomId: roomId,
                    cid: payload?.cid ?? '',
                    category: payload?.category ?? '',
                  ),
                  const _SettingsPanel(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// SFVideo 侧栏信息头:头像 + 主播元信息 + 统计 + 关注操作。
class _SideHeader extends StatelessWidget {
  const _SideHeader({
    required this.site,
    required this.roomId,
    required this.payload,
    required this.followed,
    required this.superFollowed,
    required this.onToggleFollow,
    required this.onToggleSuperFollow,
  });

  final String site;
  final String roomId;
  final RoomPayload? payload;
  final bool followed;
  final bool superFollowed;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleSuperFollow;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName
        : '主播信息';
    final avatar = payload?.avatar.trim() ?? '';
    final title = payload?.title.trim() ?? '';
    final category = payload?.category.trim() ?? '';
    final isLive = payload?.isLive ?? false;

    // 信息头高度随系统字号缩放:固定 64px 在大字体(1.15x/1.3x)下会把
    // 中间三行元信息挤出容器底部(移动端实测 1px RenderFlex 溢出)。
    final headerHeight = MediaQuery.textScalerOf(context).scale(64.0);
    return Container(
      key: const Key('play-side-header'),
      height: headerHeight,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SideAvatar(avatar: avatar, label: anchor, live: isLive),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  anchor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.08,
                    fontWeight: FontWeight.w600,
                    color: isLive ? tokens.liveBadge : tokens.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '关注 —',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11, height: 1.08),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Flexible(
                      child: Text(
                        isLive ? '开播中' : '开播 —',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          height: 1.08,
                          color: isLive
                              ? tokens.liveBadge
                              : tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _StatValue(
                      icon: Icons.people_alt_outlined,
                      value: '—',
                      color: context.tokens.statAudience,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _StatValue(
                      icon: Icons.workspace_premium_outlined,
                      value: '—',
                      color: context.tokens.statVip,
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          // 播放页头部:中文优先;跨平台 key(如 huwai)→ 中文名;
                          // 有原生中文则保留。
                          formatCategoryHeaderLabel(payload?.site, category, payload?.cid),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: tokens.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (title.isNotEmpty && title != anchor)
                  Semantics(
                    label: '房间标题 $title',
                    child: const SizedBox.shrink(),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          _SideActions(
            followed: followed,
            superFollowed: superFollowed,
            onToggleFollow: onToggleFollow,
            onToggleSuperFollow: onToggleSuperFollow,
          ),
        ],
      ),
    );
  }
}

class _SideAvatar extends StatelessWidget {
  const _SideAvatar({
    required this.avatar,
    required this.label,
    required this.live,
  });

  final String avatar;
  final String label;
  final bool live;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fallback = label.isEmpty ? '?' : label.substring(0, 1);
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomRight: Radius.circular(AppRadius.sm),
              ),
              child: avatar.isEmpty
                  ? ColoredBox(
                      color: tokens.surfaceRaised,
                      child: Center(
                        child: Text(
                          fallback,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: live
                                ? tokens.liveBadge
                                : tokens.textSecondary,
                          ),
                        ),
                      ),
                    )
                  : Image.network(
                      avatar,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => ColoredBox(
                        color: tokens.surfaceRaised,
                        child: Center(
                          child: Text(
                            fallback,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: live
                                  ? tokens.liveBadge
                                  : tokens.textSecondary,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            right: -4,
            top: -4,
            child: _HeaderIconButton(
              key: const Key('play-side-notify'),
              icon: Icons.notifications_none_rounded,
              tooltip: '开播提醒',
              onPressed: () {},
            ),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: _HeaderIconButton(
              key: const Key('play-side-external'),
              icon: Icons.open_in_new_rounded,
              tooltip: '打开直播间页面',
              onPressed: () {},
              accent: const Color(0xFF60A5FA),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderIconButton extends StatelessWidget {
  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: context.tokens.surfaceRaised,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 19,
            height: 19,
            child: Icon(
              icon,
              size: 11,
              color: accent ?? context.tokens.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _SideActions extends StatelessWidget {
  const _SideActions({
    required this.followed,
    required this.superFollowed,
    required this.onToggleFollow,
    required this.onToggleSuperFollow,
  });

  final bool followed;
  final bool superFollowed;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleSuperFollow;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 59,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(
            child: _SideActionButton(
              key: const Key('play-side-follow-btn'),
              icon: followed
                  ? Icons.favorite_rounded
                  : Icons.favorite_border_rounded,
              label: followed ? '已关注' : '关注',
              foreground: followed
                  ? context.tokens.playFollowTextActive
                  : context.tokens.playFollowText,
              background: followed
                  ? context.tokens.playFollowBgActive
                  : context.tokens.playFollowBg,
              border: context.tokens.playFollowBorder,
              onPressed: onToggleFollow,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: _SideActionButton(
              key: const Key('play-side-super-follow'),
              icon: superFollowed
                  ? Icons.star_rounded
                  : Icons.star_border_rounded,
              label: superFollowed ? '已超关' : '超关',
              foreground: superFollowed
                  ? context.tokens.playSuperTextActive
                  : context.tokens.playSuperText,
              background: superFollowed
                  ? context.tokens.playSuperBgActive
                  : context.tokens.playSuperBg,
              border: context.tokens.playSuperBorder,
              onPressed: onToggleSuperFollow,
            ),
          ),
        ],
      ),
    );
  }
}

class _SideActionButton extends StatelessWidget {
  const _SideActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
    required this.border,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;
  final Color border;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.allSm,
          side: BorderSide(color: border),
        ),
        child: InkWell(
          borderRadius: AppRadius.allSm,
          onTap: onPressed,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: foreground),
              const SizedBox(width: 2),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w600,
                    color: foreground,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({
    required this.icon,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 11, color: color.withValues(alpha: 0.88)),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            height: 1,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// 一条展示用弹幕行数据:徽章等级(可空) + 用户名 + 正文。
///
/// 由真实 [DanmakuMessage] 映射而来(见 [_ChatRowData.fromMessage])。
/// 保留该轻量视图模型:列表只关心展示字段,不把解析包的整个模型透进 Widget 层。
class _ChatRowData {
  const _ChatRowData(this.user, this.message, {this.fanLevel, this.color = 0});

  final String user;
  final String message;
  final int? fanLevel;

  /// 正文颜色(0 = 默认)。当前侧栏按平台主题统一着色,保留字段以备后续。
  final int color;

  factory _ChatRowData.fromMessage(DanmakuMessage message) {
    return _ChatRowData(
      message.userName,
      message.text,
      fanLevel: message.badgeLevel > 0 ? message.badgeLevel : null,
      color: message.color,
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
/// - 列表随新消息自动滚底;用户上滑离开底部时暂停,并显示「N 条新消息」跳底按钮;
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

  /// 已「消费」到列表末尾的消息条数(用于统计用户离开底部后到达的新消息)。
  int _seenCount = 0;

  /// TabBarView 只挂载当前页,切换 tab 会 dispose 离屏子页。若聊天页被销毁,
  /// `danmakuSessionProvider`(autoDispose)也会一并销毁 → 会话被 close、消息丢失,
  /// 切回聊天时重新建连从头开始。故聊天页必须 keepAlive,让会话跨 tab 存活。
  @override
  bool get wantKeepAlive => true;

  /// 用户当前是否停在底部(容差 24px,避免像素误差导致误判)。
  bool get _isAtBottom {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.pixels >= position.maxScrollExtent - 24;
  }

  @override
  void initState() {
    super.initState();
    // 用户上滑/下滑时刷新「N 条新消息」显隐(滚到底部即清零)。
    _scrollController.addListener(_onScrollChanged);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScrollChanged);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScrollChanged() {
    if (mounted) setState(() {});
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    final target = _scrollController.position.maxScrollExtent;
    if (animate) {
      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(target);
    }
  }

  /// 新消息到达后:贴底时自动滚到底;离开底部时仅累计未读。
  void _syncAutoScroll(int messageCount) {
    if (!_scrollController.hasClients) {
      _seenCount = messageCount;
      return;
    }
    final wasAtBottom = _isAtBottom || _seenCount == 0;
    _seenCount = messageCount;
    if (!wasAtBottom) return;
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
    // 聊天总开关:关闭时仅隐藏内容区并显示占位,弹幕会话 provider 仍被 watch(不停)。
    final chatEnabled = ref.watch(
      settingsProvider.select((s) => s.chatEnabled),
    );
    final chat = ref.watch(danmakuSessionProvider(params));
    if (!chatEnabled) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.md),
          child: Text(
            '聊天已关闭',
            textAlign: TextAlign.center,
            style: AppTypography.caption,
          ),
        ),
      );
    }
    final rows = [
      for (final message in chat.messages) _ChatRowData.fromMessage(message),
    ];

    _syncAutoScroll(rows.length);

    final atBottom = _isAtBottom;
    final pending = atBottom ? 0 : (rows.length - _seenCount).clamp(0, 1 << 30);

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
                  style: AppTypography.caption,
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
                  style: AppTypography.caption,
                ),
              ),
              const Spacer(),
              Tooltip(
                message: '重新连接弹幕',
                child: IconButton(
                  key: const Key('play-side-chat-refresh'),
                  onPressed: chat.supported
                      ? () => ref
                            .read(danmakuSessionProvider(params).notifier)
                            .reconnect()
                      : null,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 24,
                    minHeight: 24,
                  ),
                  icon: Icon(
                    Icons.refresh_rounded,
                    size: 15,
                    color: tokens.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: Stack(
            children: [
              if (rows.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      chat.isUnsupported ? '当前站点暂不支持弹幕' : '暂无弹幕，等待水友发言…',
                      textAlign: TextAlign.center,
                      style: AppTypography.caption,
                    ),
                  ),
                )
              else
                ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.sm,
                    AppSpacing.xs,
                    AppSpacing.sm,
                    AppSpacing.sm,
                  ),
                  itemCount: rows.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _ChatRow(data: rows[index]),
                  ),
                ),
              if (pending > 0)
                Positioned(
                  right: AppSpacing.sm,
                  bottom: AppSpacing.sm,
                  child: _NewMessagesButton(
                    count: pending,
                    onTap: () {
                      _seenCount = rows.length;
                      _scrollToBottom();
                    },
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 「N 条新消息」跳底按钮:用户离开底部且有新消息时浮在列表右下角。
class _NewMessagesButton extends StatelessWidget {
  const _NewMessagesButton({required this.count, required this.onTap});

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: context.tokens.brand,
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
              fontSize: 10,
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

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.data});

  final _ChatRowData data;

  Color _userColor() {
    var hash = 0;
    for (final unit in data.user.codeUnits) {
      hash = (hash * 31 + unit) % 360;
    }
    return HSLColor.fromAHSL(1, hash.toDouble(), 0.6, 0.68).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (data.fanLevel != null) ...[
          _FanBadge(level: data.fanLevel!),
          const SizedBox(width: 3),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: data.user,
                  style: AppTypography.bodySecondary.copyWith(
                    color: _userColor(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '：', style: AppTypography.bodySecondary),
                TextSpan(
                  text: data.message,
                  style: AppTypography.bodySecondary.copyWith(
                    color: tokens.textPrimary,
                  ),
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _FanBadge extends StatelessWidget {
  const _FanBadge({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: context.tokens.brand.withValues(alpha: 0.18),
        borderRadius: AppRadius.allSm,
        border: Border.all(color: context.tokens.brand.withValues(alpha: 0.6)),
      ),
      child: Text(
        '粉丝 $level',
        style: TextStyle(
          fontSize: 9,
          height: 1.1,
          color: context.tokens.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 侧栏「关注」tab:对齐 SFVideoLive `PlayFollowRecommendTabs.vue` ——
/// 顶部视图切换(封面网格 / 紧凑列表)+ 平台筛选 chips,下方用预览网格呈现关注,
/// 开播优先排序。空态提示与「我的关注」标题文案保持不变(测试锚点)。
class _FollowPanel extends ConsumerStatefulWidget {
  const _FollowPanel();

  @override
  ConsumerState<_FollowPanel> createState() => _FollowPanelState();
}

class _FollowPanelState extends ConsumerState<_FollowPanel> {
  /// true = 封面网格(参考实现的默认 preview 布局),false = 紧凑列表。
  bool _grid = true;
  String _siteFilter = 'all';

  /// 已展示条数(分页窗口)。对齐 web `PLAY_FOLLOW_PAGE_SIZE = 48`:
  /// 首屏只放 48 条,滚到底再放一页,底部提示「向下滚动加载更多…」。
  int _visibleCount = _kFollowPageSize;

  /// 距底部多少像素内视为「滚到底」(触发下一页加载)。
  static const double _kLoadMoreTriggerExtent = 96;

  /// 单页条数(web `PLAY_FOLLOW_PAGE_SIZE`)。
  static const int _kFollowPageSize = 48;

  /// 本轮待渲染的可见条目总数(由 build 写入,供滚动回调判定还有没有下一页)。
  int _visibleTotal = 0;

  /// 侧栏可见性口径:在播 + 离线超关(与 web `isPlayFollowVisible` 一致),
  /// 排序仍走 follow_sort 的统一档位(超关 → 开播 → 未开播)。
  ///
  /// 旧实现传 `liveOnly: true` 把离线一律丢掉 —— 关注的主播恰好都没开播时
  /// 侧栏整片空白,即用户报的「关注没显示」。
  List<FollowEntry> _visible(List<FollowEntry> entries) =>
      playSidebarFollowEntries(entries, site: _siteFilter);

  /// 滚动到底附近再放一页(web 的哨兵/scroll 触发)。
  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical ||
        _visibleTotal <= _visibleCount) {
      return false;
    }
    if (notification.metrics.maxScrollExtent - notification.metrics.pixels <=
        _kLoadMoreTriggerExtent) {
      setState(() => _visibleCount += _kFollowPageSize);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final entries = _visible(ref.watch(followProvider));
    _visibleTotal = entries.length;
    final hasMore = entries.length > _visibleCount;
    final windowed = hasMore ? entries.sublist(0, _visibleCount) : entries;
    final rooms = [for (final entry in windowed) entry.room];
    final superKeys = <String>{
      for (final entry in windowed)
        if (entry.isSpecial) entry.key,
    };
    return Column(
      key: const Key('play-side-follow-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelTitle(
          tokens,
          '我的关注',
          trailing: Tooltip(
            message: _grid ? '切换为列表视图' : '切换为封面预览',
            child: IconButton(
              key: const Key('play-side-follow-view-toggle'),
              onPressed: () => setState(() => _grid = !_grid),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
              icon: Icon(
                _grid ? Icons.list_rounded : Icons.grid_view_rounded,
                size: 15,
                color: _grid ? tokens.textSecondary : tokens.brand,
              ),
            ),
          ),
        ),
        _SidePlatformChips(
          value: _siteFilter,
          onChanged: (site) => setState(() {
            _siteFilter = site;
            // 换平台等于换列表:分页窗口回到首屏(否则一换平台就直接铺满 48×n)。
            _visibleCount = _kFollowPageSize;
          }),
        ),
        Expanded(
          child: entries.isEmpty
              ? const _PanelHint(
                  icon: Icons.star_border_rounded,
                  title: '我的关注',
                  text: '暂无在播关注；离线超关主播会保留在此列表',
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  child: _grid
                      ? PlayRoomGrid(
                          rooms: rooms,
                          superKeys: superKeys,
                          keyPrefix: 'play-follow-room-',
                          onTap: _goRoom,
                        )
                      : PlayRoomList(
                          rooms: rooms,
                          superKeys: superKeys,
                          onTap: _goRoom,
                        ),
                ),
        ),
        if (hasMore) const _FollowMoreHint(),
      ],
    );
  }

  /// 切房：用 pushReplacement（只替换栈顶播放页）而非 go。
  ///
  /// - push：旧播放页连同其 media-kit 会话被压在栈下继续存活 → 切房泄漏；
  /// - go：整条历史栈被重置（go_router 会把壳层页也换掉）→ 播放页左上角
  ///   「返回」无栈可回，抛 `GoError: There is nothing to pop`，表现为点了没反应；
  /// - pushReplacement：旧播放页被卸载（会话随 autoDispose 收干净），
  ///   下层浏览页保留为返回目标 —— 两者兼得。
  void _goRoom(RoomSummary room) =>
      context.pushReplacement('/${room.site}/play/${room.roomId}');
}

/// 侧栏关注列表底部提示:还有更多时引导滚动。
///
/// 对齐 web `.follow-recommend__more-hint`(「向下滚动加载更多…」) —— 列表
/// 滚到底部会自动再放一页,这行提示是给用户的可见信号。
class _FollowMoreHint extends StatelessWidget {
  const _FollowMoreHint();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Text(
        '向下滚动加载更多…',
        textAlign: TextAlign.center,
        style: AppTypography.caption,
      ),
    );
  }
}

/// 侧栏平台筛选 chips:横向滚动的小 chip(侧栏窄,Wrap 会折成多行)。
class _SidePlatformChips extends StatelessWidget {
  const _SidePlatformChips({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return SizedBox(
      height: 28,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
        itemCount: PlatformBrandCatalog.navigationPlatforms.length,
        separatorBuilder: (context, _) => const SizedBox(width: 5),
        itemBuilder: (context, index) {
          final brand = PlatformBrandCatalog.navigationPlatforms[index];
          final selected = value == brand.id;
          final accent = brand.id == 'all' ? tokens.brand : brand.color;
          return InkWell(
            key: Key('play-side-follow-site-${brand.id}'),
            borderRadius: AppRadius.allPill,
            onTap: () => onChanged(brand.id),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: selected
                    ? accent.withValues(alpha: 0.18)
                    : tokens.surface,
                borderRadius: AppRadius.allPill,
                border: Border.all(color: selected ? accent : tokens.border),
              ),
              child: Text(
                brand.id == 'all' ? '全平台' : brand.name,
                style: AppTypography.caption.copyWith(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? tokens.textPrimary : tokens.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 面板标题行:左标题(12px 加粗)+ 可选右侧操作。
class _PanelTitle extends StatelessWidget {
  const _PanelTitle(this.tokens, this.title, {this.trailing});

  final ZishuTokens tokens;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.sm, AppSpacing.sm, 6, 4),
      child: Row(
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              height: 1.2,
              fontWeight: FontWeight.w600,
              color: tokens.textPrimary,
            ),
          ),
          const Spacer(),
          ?trailing,
        ],
      ),
    );
  }
}

/// 侧栏「推荐」tab:跨平台「相关推荐」。
///
/// 逻辑与呈现都在 [PlayRecommendPanel](参考实现 `usePlayRecommend.ts` 逐条复刻:
/// 站点顺序 douyu/huya/bilibili/douyin、每站 3 条交错合并、分类映射与热门兜底、
/// 滚动分页);本类只做「把播放页上下文与切房回调接上」的薄壳,避免侧栏文件里
/// 再养一份编排。
class _RecommendPanel extends StatelessWidget {
  const _RecommendPanel({
    required this.site,
    required this.roomId,
    required this.cid,
    required this.category,
  });

  final String site;

  /// 当前房间号:推荐里要剔除它自己。
  final String roomId;
  final String cid;

  /// 当前房间分类名:其它平台的分类映射按它匹配。
  final String category;

  @override
  Widget build(BuildContext context) {
    return PlayRecommendPanel(
      site: site,
      roomId: roomId,
      cid: cid,
      category: category,
      // 切房语义与「关注」tab 完全一致:pushReplacement 只换栈顶播放页 ——
      // 旧播放页被卸载(media-kit 会话随 autoDispose 收干净),下层浏览页
      // 保留为返回目标(go 会重置整条栈,左上角「返回」将无栈可回)。
      onTap: (room) =>
          context.pushReplacement('/${room.site}/play/${room.roomId}'),
    );
  }
}

class _SettingsPanel extends ConsumerWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final settings = ref.watch(settingsProvider);
    return ListView(
      key: const Key('play-side-settings-panel'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      children: [
        _SettingsGroup(
          title: '播放',
          children: [
            _SettingRow(
              label: '线路格式',
              trailing: DropdownButton<PreferredLineFormat>(
                key: const Key('play-side-setting-line-format'),
                value: settings.preferredLineFormat,
                isDense: true,
                underline: const SizedBox.shrink(),
                dropdownColor: tokens.surfaceRaised,
                style: TextStyle(fontSize: 11, color: tokens.textPrimary),
                items: [
                  for (final format in PreferredLineFormat.values)
                    DropdownMenuItem(value: format, child: Text(format.label)),
                ],
                onChanged: (format) {
                  if (format != null) {
                    ref
                        .read(settingsProvider.notifier)
                        .setPreferredLineFormat(format);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        _SettingsGroup(
          title: '聊天弹幕',
          children: [
            _SettingRow(
              label: '聊天',
              trailing: Switch(
                key: const Key('play-side-setting-chat'),
                value: settings.chatEnabled,
                onChanged: (enabled) =>
                    ref.read(settingsProvider.notifier).setChatEnabled(enabled),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            // 细粒度弹幕设置(透明度/字号/速度/显示区域)统一走对话框:
            // 此前这里是两个 `onChanged: (_) {}` 的死滑杆,现在与设置页共用
            // 同一面板(见 danmaku_settings_dialog.dart)。
            _SettingRow(
              label: '弹幕样式',
              trailing: TextButton(
                key: const Key('play-side-setting-danmaku-style'),
                onPressed: () => showDanmakuSettingsDialog(context),
                style: TextButton.styleFrom(
                  foregroundColor: tokens.brand,
                  minimumSize: const Size(0, 28),
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
                child: const Text('调整', style: TextStyle(fontSize: 11)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 5,
      ),
      decoration: BoxDecoration(
        color: context.tokens.surfaceSoft,
        borderRadius: AppRadius.allSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              height: 1.2,
              color: context.tokens.brand,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          ...children,
        ],
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({required this.label, required this.trailing});

  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label, style: AppTypography.caption)),
        trailing,
      ],
    );
  }
}

class _PanelHint extends StatelessWidget {
  const _PanelHint({
    required this.icon,
    required this.title,
    required this.text,
  });

  final IconData icon;
  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 30, color: tokens.surfaceRaised),
            const SizedBox(height: AppSpacing.sm),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: tokens.textPrimary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              text,
              textAlign: TextAlign.center,
              style: AppTypography.caption,
            ),
          ],
        ),
      ),
    );
  }
}
