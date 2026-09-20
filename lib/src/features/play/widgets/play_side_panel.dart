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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../danmaku/application/danmaku_session_provider.dart';
import '../../follow/application/follow_provider.dart';
import '../application/room_stats_provider.dart';
import '../../follow/application/follow_sort.dart';
import '../../follow/application/settings_provider.dart';
import '../../../platforms/common/open_external_url.dart';
import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/widgets/compact_switch.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import 'chat_badge_image.dart';
import 'play_meta_bar.dart';
import 'play_recommend_panel.dart';
import '../../follow/widgets/follow_platform_filter.dart';
import '../../follow/widgets/follow_room_list.dart';

/// 播放页侧栏的 UI 状态(会话级,跨切房保持)。
///
/// 切房走 `pushReplacement`:侧栏随路由整体重建,若 tab/视图是 widget 本地
/// 状态,点关注里的房间跳过去后右侧会退回「聊天」tab(用户口径 2026-09-19:
/// 「点击某一个后跳转后有右侧还是在当前关注 tab active」)。把这三项收进
/// **全局 KeepAlive provider** —— 顶部(AreaShell)/左侧(舞台)/右侧(侧栏)
/// 三块由此解耦:右侧点击只换舞台内容,右侧自身的 active 态不重置。
class PlaySidePanelPrefs {
  const PlaySidePanelPrefs({
    this.tabIndex = 0,
    this.followGrid = false,
    this.followSite = 'all',
  });

  /// 侧栏 tab:0=聊天 1=关注 2=推荐 3=设置。默认聊天(对齐 web)。
  final int tabIndex;

  /// 关注面板:true=封面网格,false=紧凑列表(用户口径默认列表)。
  final bool followGrid;

  /// 关注面板平台筛选('all' 或平台 id)。
  final String followSite;

  PlaySidePanelPrefs copyWith({
    int? tabIndex,
    bool? followGrid,
    String? followSite,
  }) => PlaySidePanelPrefs(
    tabIndex: tabIndex ?? this.tabIndex,
    followGrid: followGrid ?? this.followGrid,
    followSite: followSite ?? this.followSite,
  );
}

/// 全局(非 autoDispose):离开播放页也保留,下次进房延续上次的 tab/视图。
final playSidePanelPrefsProvider =
    NotifierProvider<PlaySidePanelPrefsController, PlaySidePanelPrefs>(
      PlaySidePanelPrefsController.new,
    );

class PlaySidePanelPrefsController extends Notifier<PlaySidePanelPrefs> {
  @override
  PlaySidePanelPrefs build() => const PlaySidePanelPrefs();

  void update({int? tabIndex, bool? followGrid, String? followSite}) {
    state = state.copyWith(
      tabIndex: tabIndex,
      followGrid: followGrid,
      followSite: followSite,
    );
  }
}

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

  /// 切换当前房间的开播提醒(关注条目已有的 remindOn 字段;与关注/超关
  /// 同款按 key 查询)。未关注时无可提醒目标,入口按钮本身已禁用,此处兜底。
  void _toggleRemindOn() {
    final key = _currentKey;
    final matched = ref.read(followProvider).where((e) => e.key == key);
    if (matched.isEmpty) return;
    ref.read(followProvider.notifier).toggleRemind(key);
  }

  /// 打开当前房间的 web 页(系统默认浏览器)。失败仅提示,不打断播放。
  Future<void> _openRoomExternal(String url) async {
    final ok = await openExternalUrl(url);
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('未能打开浏览器：$url')));
    }
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
    final remindOn = matched.isNotEmpty && matched.first.remindOn;

    return Container(
      key: const Key('play-side-panel'),
      decoration: BoxDecoration(
        color: tokens.surface,
        border: Border(left: BorderSide(color: tokens.border)),
      ),
      child: DefaultTabController(
        // 初始 tab 从会话级偏好恢复:切房(pushReplacement)重建侧栏后,
        // 右侧仍停在上次的 tab(如「关注」),不再退回聊天。
        initialIndex: ref
            .watch(playSidePanelPrefsProvider)
            .tabIndex
            .clamp(0, 3),
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
                followRoom: matched.isNotEmpty ? matched.first.room : null,
                followed: followed,
                superFollowed: superFollowed,
                remindOn: remindOn,
                externalUrl: roomExternalUrl(site, roomId, payload),
                onToggleFollow: _toggleFollow,
                onToggleSuperFollow: _toggleSuperFollow,
                onToggleRemind: _toggleRemindOn,
                onOpenExternal: _openRoomExternal,
              ),
            // 高度对齐 web `--el-tabs-header-height: 2rem`(32px)。
            SizedBox(
              height: 32,
              child: TabBar(
                onTap: (index) => ref
                    .read(playSidePanelPrefsProvider.notifier)
                    .update(tabIndex: index),
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
                labelColor: tokens.accent,
                unselectedLabelColor: tokens.textSecondary,
                indicatorColor: tokens.accent,
                indicatorWeight: 2,
                dividerColor: tokens.border,
                labelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.15,
                ),
                unselectedLabelStyle: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w500,
                  height: 1.15,
                ),
                labelPadding: EdgeInsets.zero,
                splashFactory: NoSplash.splashFactory,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              ),
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
class _SideHeader extends ConsumerWidget {
  const _SideHeader({
    required this.site,
    required this.roomId,
    required this.payload,
    required this.followRoom,
    required this.followed,
    required this.superFollowed,
    required this.remindOn,
    required this.externalUrl,
    required this.onToggleFollow,
    required this.onToggleSuperFollow,
    required this.onToggleRemind,
    required this.onOpenExternal,
  });

  final String site;
  final String roomId;
  final RoomPayload? payload;

  /// 当前房间的关注条目(null = 未关注)。
  ///
  /// 统计区数据源对齐 web `SideHeader.vue` + `useRoomStats.ts`:粉丝/贵宾/
  /// 人气等统计来自关注状态快照(本仓等价物 = 关注条目随
  /// `FollowController.refreshStatuses` 回填的 [RoomSummary]);[RoomPayload]
  /// 不携带统计字段,故未关注(或尚未刷新回填)时该项显示「—」,
  /// 不伪造数据。
  final RoomSummary? followRoom;

  final bool followed;
  final bool superFollowed;

  /// 开播提醒开关(关注条目 remindOn)。未关注时按钮禁用,该值无意义。
  final bool remindOn;

  /// 当前房间 web 页地址(null = 无稳定外链,按钮禁用)。
  final String? externalUrl;
  final VoidCallback onToggleFollow;
  final VoidCallback onToggleSuperFollow;
  final VoidCallback onToggleRemind;
  final ValueChanged<String> onOpenExternal;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName
        : '主播信息';
    final avatar = payload?.avatar.trim() ?? '';
    final title = payload?.title.trim() ?? '';
    final category = payload?.category.trim() ?? '';
    final isLive = payload?.isLive ?? false;
    // 统计区(对齐 web SideHeader「关注：N」行 + stats 列):已关注房间
    // 取关注条目回填;未关注/未回填时兜底调 roomStatsProvider(同一条解析
    // 真源,任意房间可查 —— 用户口径 2026-09-20 huya 等平台统计不能只服务
    // 已关注房间)。上游未提供 → '—' 占位,不伪造(数据诚实性)。
    final followRoom = this.followRoom;
    final RoomSummary? stats =
        followRoom ??
        ref.watch(roomStatsProvider((site: site, roomId: roomId))).value;
    final followersText = _formatFollowersText(stats?.followers);
    final audienceText = _statText(stats?.online);
    final vipText = _statText(stats?.vip);

    // 信息头高度随系统字号缩放:固定 64px 在大字体(1.15x/1.3x)下会把
    // 中间三行元信息挤出容器底部(移动端实测 1px RenderFlex 溢出)。
    final headerHeight = MediaQuery.textScalerOf(context).scale(64.0);
    return Container(
      key: const Key('play-side-header'),
      height: headerHeight,
      decoration: BoxDecoration(
        color: context.tokens.surface,
        border: Border(bottom: BorderSide(color: tokens.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 头像贴边出血:占满头高(无上下内边距、左侧贴边),对齐 web
          // `--room-aside-avatar-size = head-h + 2*pad-y`。
          _SideAvatar(avatar: avatar, label: anchor, live: isLive),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
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
                  // 分类显示在主播名后面那一行(用户口径 2026-09-19);
                  // 关注数与人气/VIP 合并到同一统计行,控制头高不溢出。
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          formatCategoryHeaderLabel(
                            payload?.site,
                            category,
                            payload?.cid,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 10, height: 1.15),
                        ),
                      ),
                      // 开播提醒 + 外链(用户口径 2026-09-20:从头像悬浮挪到
                      // 第二排分类名后,不再遮头像;显示改为文字)。
                      const SizedBox(width: 4),
                      _SideTextAction(
                        key: const Key('play-side-notify'),
                        label: remindOn ? '直播提醒中' : '直播提醒',
                        tooltip: followed
                            ? (remindOn ? '已开启开播/下播提醒，点击关闭' : '开启开播/下播提醒')
                            : '关注后可开启开播提醒',
                        onPressed: followed ? onToggleRemind : null,
                        active: remindOn,
                      ),
                      const SizedBox(width: 3),
                      _SideTextAction(
                        key: const Key('play-side-external'),
                        label: '跳转',
                        tooltip: '打开直播间页面',
                        onPressed: externalUrl == null
                            ? null
                            : () => onOpenExternal(externalUrl!),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          '关注 $followersText',
                          key: const Key('play-side-stat-followers'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.08),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // 人气/观众(web stats[0]「观众」列;online 为空 = 离线或
                      // 尚未刷新回填,显示「—」)。
                      _StatValue(
                        icon: Icons.people_alt_outlined,
                        value: audienceText,
                        color: context.tokens.statAudience,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      // VIP/贵宾(web stats[1] vip 列;douyu/huya 贵宾、
                      // douyin 会员、soop 订阅;其余平台上游无 → 「—」)。
                      _StatValue(
                        icon: Icons.workspace_premium_outlined,
                        value: vipText,
                        color: context.tokens.statVip,
                      ),
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
          ),
          const SizedBox(width: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(
              top: 5,
              bottom: 5,
              right: AppSpacing.sm,
            ),
            child: _SideActions(
              followed: followed,
              superFollowed: superFollowed,
              onToggleFollow: onToggleFollow,
              onToggleSuperFollow: onToggleSuperFollow,
            ),
          ),
        ],
      ),
    );
  }
}

/// 统计文本:空串(未关注/上游未提供)显示「—」占位,不伪造。
String _statText(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '—' : text;
}

/// 关注数显示格式(用户口径 2026-09-20):纯数字 ≥1万 显示「X.X万」
/// (≥100万 收敛为整数万);已带单位或非数字文本原样返回,不伪造。
String _formatFollowersText(String? raw) {
  final text = (raw?.trim() ?? '').replaceAll(',', '');
  if (text.isEmpty) return '—';
  final value = int.tryParse(text);
  if (value == null) return text;
  if (value >= 10000) {
    final wan = value / 10000;
    return wan >= 100
        ? '${wan.toStringAsFixed(0)}万'
        : '${wan.toStringAsFixed(1)}万';
  }
  return text;
}

/// 当前房间 web 页地址:解析结果自带的 sourceUrl(解析器实际进入的页面,
/// 最稳)优先;没有则按平台拼 —— 对齐 web `platformCatalog.ts`
/// `PLATFORM_EXTERNAL_URLS`(douyu/huya/bilibili);douyin 等无稳定 web
/// url 的平台返回 null(按钮禁用),若其 payload 自带真实页面 url 则放行。
@visibleForTesting
String? roomExternalUrl(String site, String roomId, RoomPayload? payload) {
  final id = roomId.trim();
  if (id.isEmpty) return null;
  final source = payload?.sourceUrl.trim() ?? '';
  if (source.isNotEmpty) return source;
  return switch (site) {
    'douyu' => 'https://www.douyu.com/$id',
    'huya' => 'https://www.huya.com/$id',
    'bilibili' => 'https://live.bilibili.com/$id',
    _ => null,
  };
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
    // 64×头高(贴边出血:高度由 Row stretch 撑满,不留上下 padding)。
    return SizedBox(
      width: 64,
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
        ],
      ),
    );
  }
}

/// 侧栏头第二排的小文字按钮(用户口径 2026-09-20:开播提醒/跳转显示为
/// 文字而非 icon)。描边 pill;[active] 时走品牌紫强调。
class _SideTextAction extends StatelessWidget {
  const _SideTextAction({
    super.key,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final String label;
  final String tooltip;

  /// null = 禁用(未关注无可提醒目标 / 无稳定 web url)。
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onPressed != null;
    final fg = !enabled
        ? tokens.textSecondary.withValues(alpha: 0.55)
        : active
        ? tokens.accent
        : tokens.textSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active && enabled
            ? tokens.accent.withValues(alpha: 0.14)
            : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: active && enabled
                ? tokens.accent.withValues(alpha: 0.55)
                : tokens.border,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 9.5,
                height: 1.2,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
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
  void _ingest(
    List<DanmakuMessage> snapshot, {
    required bool throttled,
    required int intervalSec,
  }) {
    final batch = _diffSnapshot(snapshot);
    if (!throttled) {
      _cancelReleaseTimer();
      var added = 0;
      for (final message in batch) {
        _pushDisplay(message);
        added += 1;
      }
      while (_pendingMessages.isNotEmpty) {
        _pushDisplay(_pendingMessages.removeAt(0));
        added += 1;
      }
      _onDisplayGrew(added);
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
        _releaseOnePending();
        _onDisplayGrew(1);
      }
    }
    _ensureReleaseTimer(intervalSec);
  }

  /// 追加进显示队列,超 [_kChatDisplayLimit] 裁头丢最旧
  /// (对齐 web pushChatDisplay + CHAT_DISPLAY_LIMIT)。
  void _pushDisplay(DanmakuMessage message) {
    _displayRows.add(_ChatRowData.fromMessage(message, widget.site));
    if (_displayRows.length > _kChatDisplayLimit) {
      _displayRows.removeRange(0, _displayRows.length - _kChatDisplayLimit);
    }
  }

  /// 从积压头部放行一条进显示(web releaseOneChatPending 的 shift 语义)。
  void _releaseOnePending() {
    if (_pendingMessages.isEmpty) return;
    _pushDisplay(_pendingMessages.removeAt(0));
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
  void _onReleaseTick() {
    _releaseTimer = null;
    if (!mounted || _pendingMessages.isEmpty) return;
    _releaseOnePending();
    setState(() {});
    _onDisplayGrew(1);
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
    _ingest(
      chat.messages,
      throttled: settings.chatThrottleMode == ChatThrottleMode.perNSeconds,
      intervalSec: settings.chatSpeed,
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
                          fontSize: 11,
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
              fontSize: 12,
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

/// 消息行高:对齐 web SideChatTab `CHAT_ITEM_LINE_HEIGHT = 1.48`(固定,
/// 不随间距设置变化;间距由列表行 padding 表达)。
const double _kChatLineHeight = 1.48;

/// 表情图边长 = 正文字号 × 该系数(对齐 web 表情与文字同行的视觉比例)。
const double _kEmojiSizeScale = 1.6;

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.data, required this.fontSize});

  final _ChatRowData data;

  /// 消息字号(web chatSettings.fontSize,12-24;用户名与正文同字号)。
  final double fontSize;

  Color _userColor() {
    var hash = 0;
    for (final unit in data.user.codeUnits) {
      hash = (hash * 31 + unit) % 360;
    }
    return HSLColor.fromAHSL(1, hash.toDouble(), 0.6, 0.68).toColor();
  }

  /// 正文段 spans:按 [DanmakuSegment] 富文本段展开(抖音表情图消息)。
  ///
  /// 回退链:
  /// - segments 为空(默认)→ 单段 [data.message] 纯文本,历史行为零破坏;
  /// - 文本段 / url 为空 / 图片加载失败(errorBuilder)→ 「[表情名]」文本,
  ///   样式与正文一致;
  /// - 表情段 url 非空 → [WidgetSpan] 内联 [Image.network],边长 = 字号 ×
  ///   [_kEmojiSizeScale],`fit: contain`,中线对齐文字。
  List<InlineSpan> _buildBodySpans(TextStyle bodyStyle) {
    final segments = data.segments;
    if (segments.isEmpty) {
      return [TextSpan(text: data.message, style: bodyStyle)];
    }
    final emojiSide = fontSize * _kEmojiSizeScale;
    return [
      for (final segment in segments)
        if (segment.isEmoji && segment.url.isNotEmpty)
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Image.network(
              segment.url,
              width: emojiSide,
              height: emojiSide,
              fit: BoxFit.contain,
              errorBuilder: (_, _, _) => Text(segment.text, style: bodyStyle),
            ),
          )
        else
          TextSpan(text: segment.text, style: bodyStyle),
    ];
  }

  /// 徽章内联进正文段落(见 build 注释):middle 对齐表情图 WidgetSpan 同款,
  /// 行尾 2px 间距对齐 web 徽章 margin-right 0.14em(14px 基 ≈ 2px)。
  ///
  /// 徽章底座 [_BadgeBox] 靠 `Container.alignment` 收缩定位,需要无界宽度
  /// 约束才不自撑满;旧 Row 布局天然给子项无界宽,段落 WidgetSpan 给的是
  /// 有界宽(会把徽章拉满整行),这里套一层 `Row(mainAxisSize: min)` 还原
  /// 无界宽约束,保持徽章收缩为内容宽。
  WidgetSpan _inlineBadge(Widget badge) => WidgetSpan(
    alignment: PlaceholderAlignment.middle,
    child: Padding(
      padding: const EdgeInsets.only(right: 2),
      child: Row(mainAxisSize: MainAxisSize.min, children: [badge]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final fanBadge = data.fanLevel;
    // 单段落内联流,对齐 web SideChatTab:.chat-item 为 block 段落、徽章
    // display:contents、正文 display:inline —— 徽章/昵称/正文同处一个
    // Text.rich 段落,正文折行时第二行从段落最左(= 条目内容区最左,
    // 徽章列正下方)顶格起排,而非缩进到昵称列(用户口径 2026-09-20:
    // 「同一个人发言第二行文字应该从最左边开始」)。
    return Text.rich(
      key: const Key('play-side-chat-message'),
      TextSpan(
        children: [
          // 徽章顺序对齐 web SideChatTab.vue:38-44 —— 平台用户等级 pill 在前、
          // 粉丝牌在后(用户口径 2026-09-19:「平台等级应该在粉丝等级前显示」)。
          if (data.userLevel > 0)
            _inlineBadge(
              _UserLevelBadge(site: data.site, level: data.userLevel),
            ),
          if (fanBadge != null &&
              _FanBadge.visibleFor(site: data.site, name: data.fanName))
            _inlineBadge(
              _FanBadge(
                site: data.site,
                name: data.fanName,
                level: fanBadge,
                colorStart: data.badgeColorStart,
                colorEnd: data.badgeColorEnd,
                colorBorder: data.badgeColorBorder,
                textColor: data.badgeTextColor,
                levelColor: data.badgeColorLevel,
              ),
            ),
          TextSpan(
            text: data.user,
            style: context.textSecondary.copyWith(
              color: _userColor(),
              fontWeight: FontWeight.w600,
              fontSize: fontSize,
              height: _kChatLineHeight,
            ),
          ),
          TextSpan(
            text: '：',
            style: context.textSecondary.copyWith(
              fontSize: fontSize,
              height: _kChatLineHeight,
            ),
          ),
          // 正文段:按 segments 富文本展开(空 = 单段纯文本)。
          ..._buildBodySpans(
            context.textSecondary.copyWith(
              color: tokens.textPrimary,
              fontSize: fontSize,
              height: _kChatLineHeight,
            ),
          ),
        ],
      ),
    );
  }
}

/// 等级梯度色表(对齐 web badgeHelpers.ts LEVEL_TIER_GRADIENTS,90deg)。
const _kTierGradients = <List<Color>>[
  [Color(0xffdc2626), Color(0xfff97316)], // ≥最高档
  [Color(0xffea580c), Color(0xfffbbf24)],
  [Color(0xff7c3aed), Color(0xffa855f7)],
  [Color(0xff2563eb), Color(0xff3b82f6)],
  [Color(0xff059669), Color(0xff10b981)],
];
const _kTierFallback = <Color>[Color(0xff6b7280), Color(0xff9ca3af)];

/// level → 梯度档(thresholds 从高到低,如斗鱼 [50,40,30,20,10])。
List<Color> _levelTier(int level, List<int> thresholds) {
  for (var i = 0; i < thresholds.length; i += 1) {
    if (level >= thresholds[i]) return _kTierGradients[i];
  }
  return _kTierFallback;
}

/// 虎牙粉丝条 7 档渐变(对齐 web HUYA_BAR_GRADIENTS)。
List<Color> _huyaBarGradient(int level) {
  final identity = level <= 4
      ? 1
      : level <= 7
      ? 2
      : level <= 10
      ? 3
      : level <= 13
      ? 4
      : level <= 16
      ? 11
      : level <= 19
      ? 12
      : 13;
  return switch (identity) {
    1 => [Color(0xff1a7f37), Color(0xff3fb950)],
    2 => [Color(0xff238636), Color(0xff56b362)],
    3 => [Color(0xff0969da), Color(0xff58a6ff)],
    4 => [Color(0xff218bff), Color(0xff79c0ff)],
    11 => [Color(0xff8957e5), Color(0xffbc8cff)],
    12 => [Color(0xffbf3989), Color(0xfff778ba)],
    _ => [Color(0xff93385f), Color(0xffdb6da9)],
  };
}

/// 粉丝牌(对齐 web ChatFanBadge 各平台分支;本地图优先 → 文字态兜底):
/// - 斗鱼:官方粉丝牌 PNG(`douyu/fans/{lv}.png`,等级已绘在图内 → 不叠数字)
///   作底图、团名叠右侧(web douyuOfficial);加载失败/无图回落中性深底团名
///   胶囊;无团名不渲染(web normalizeDouyuBadge 无名即 null);
/// - 抖音:img-only 站(web CHAT_FAN_BADGE_IMG_ONLY_SITES),有等级即整图
///   `douyin/fans/{lv}.png`;失败回落红色渐变圆盘文字态;
/// - 虎牙:房间定制图不在弹幕数据模型内、官方 v2 emblem 不用于粉丝牌
///   (web huyaFansBadgeStaticUrl 已废弃)→ 维持渐变条文字态;
/// - B 站:有协议渐变色维持「团名 级」渐变胶囊;无协议色走官方边框图
///   `medal-frame.png` + 文字叠层(web resolveBilibiliBadgeBgUrl),失败回落
///   中性深底;消费协议文字色/等级数字色(0 = 回落白/文字色);
/// - 其他:品牌色 pill。
class _FanBadge extends StatefulWidget {
  const _FanBadge({
    required this.site,
    required this.level,
    this.name,
    this.colorStart = 0,
    this.colorEnd = 0,
    this.colorBorder = 0,
    this.textColor = 0,
    this.levelColor = 0,
  });

  final String site;
  final int level;
  final String? name;
  final int colorStart;
  final int colorEnd;
  final int colorBorder;

  /// 粉丝牌文字色(0xRRGGBB;0 = 默认白)。
  final int textColor;

  /// 粉丝牌等级数字色(0xRRGGBB;0 = 回落 [textColor])。
  final int levelColor;

  /// 该组合是否会渲染出可见内容:douyu 无团名 → build 返回
  /// [SizedBox.shrink](零尺寸)。内联段落布局据此跳过该牌,不留一个
  /// 只贡献 padding 的空 WidgetSpan(旧 Row 布局会残留 2px 幽灵间距)。
  static bool visibleFor({required String site, String? name}) =>
      site != 'douyu' || (name != null && name.trim().isNotEmpty);

  @override
  State<_FanBadge> createState() => _FanBadgeState();
}

class _FanBadgeState extends State<_FanBadge> {
  /// 本地图加载失败/缺失:回落文字态(输入变化后重置重试)。
  bool _imgFailed = false;

  @override
  void didUpdateWidget(covariant _FanBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.level != widget.level ||
        oldWidget.name != widget.name) {
      _imgFailed = false;
    }
  }

  void _markImgFailed() {
    if (mounted) setState(() => _imgFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final site = widget.site;
    final level = widget.level;
    final name = widget.name;
    final colorStart = widget.colorStart;
    final colorEnd = widget.colorEnd;
    final colorBorder = widget.colorBorder;
    final textColor = widget.textColor;
    final levelColor = widget.levelColor;
    final hasName = name != null && name.trim().isNotEmpty;
    // web 斗鱼/B站文字态无梯度兜底:中性深底白字(web 无协议图/色时走
    // 官方图片牌,flutter 无图 → 深底占位保持可读)。
    const neutralBg = Color(0xff3a3a3a);
    final resolvedTextColor = textColor != 0 ? Color(textColor) : Colors.white;
    final resolvedLevelColor = levelColor != 0
        ? Color(levelColor)
        : resolvedTextColor;

    // 抖音:img-only 站,有等级即官方整图(fans/{lv}.png,等级绘在图内);
    // 失败/无图回落红色渐变圆盘文字态。
    // 圆盘尺寸对齐 web douyinTextFallback(14px 基):min 1.4em=19.6、字 0.78em≈11。
    if (site == 'douyin') {
      if (!_imgFailed &&
          badgeAssetPath(
            site: site,
            kind: ChatBadgeKind.fans,
            level: level,
          ).isNotEmpty) {
        return ChatBadgeImage(
          site: site,
          kind: ChatBadgeKind.fans,
          level: level,
          height: 21, // web chat-fan-badge__platform-img 1.48em ≈ 20.7
          onFail: _markImgFailed,
        );
      }
      return _BadgeBox(
        height: 19.6,
        minWidth: 19.6,
        radius: 999,
        gradient: const [Color(0xfffe2c55), Color(0xffff6b35)],
        child: Text(
          '$level',
          style: const TextStyle(
            fontSize: 11,
            height: 1.1,
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    // 虎牙:渐变条 = 圆盘等级 + 团名(无本地图分支,见类注释)。
    // 尺寸对齐 web huyaComposed(14px 基):条 1.15em≈16、圆盘 1.05em×0.67em≈10、
    // 圆盘字 0.67em≈9.4、团名 0.79em≈11。
    if (site == 'huya') {
      return _BadgeBox(
        height: 16,
        radius: 2,
        gradient: _huyaBarGradient(level),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              constraints: const BoxConstraints(minWidth: 10, minHeight: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.22),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$level',
                style: const TextStyle(
                  fontSize: 9.4,
                  height: 1.1,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            if (hasName) ...[
              const SizedBox(width: 2),
              Text(
                name.trim(),
                style: const TextStyle(
                  fontSize: 11,
                  height: 1.1,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      );
    }
    // B 站:有协议渐变色 → 「团名 级」渐变胶囊(to left:start 在右)+ 描边;
    // 无协议色 → 官方边框图 + 文字叠层,失败回落中性深底。
    if (site == 'bilibili') {
      // 互补缺省(web buildBilibiliBadgeStyle:start=colorStart||colorEnd)。
      final start = colorStart != 0 ? colorStart : colorEnd;
      final end = colorEnd != 0 ? colorEnd : colorStart;
      final hasProtocolColor = start != 0 || end != 0;
      final content = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasName)
            Flexible(
              child: Text(
                name.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12.6,
                  height: 1.1,
                  color: resolvedTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (hasName) const SizedBox(width: 2),
          Text(
            '$level',
            style: TextStyle(
              fontSize: 12.6,
              height: 1.1,
              color: resolvedLevelColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
      if (!hasProtocolColor && !_imgFailed) {
        return Container(
          height: 21, // web bilibiliComposed/官方边框牌 1.48em ≈ 20.7
          constraints: const BoxConstraints(minWidth: 49), // 3.5em
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChatBadgeImage(
                    site: site,
                    kind: ChatBadgeKind.fans,
                    level: level,
                    height: 21,
                    onFail: _markImgFailed,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(child: content),
              ),
            ],
          ),
        );
      }
      return _BadgeBox(
        height: 21,
        radius: 999,
        gradient: hasProtocolColor ? [Color(start), Color(end)] : null,
        color: hasProtocolColor ? null : neutralBg,
        // web `linear-gradient(to left, start, end)`:start 在右、end 在左。
        gradientBegin: Alignment.centerRight,
        gradientEnd: Alignment.centerLeft,
        border: colorBorder != 0 ? Color(colorBorder) : null,
        child: content,
      );
    }
    // 斗鱼:官方粉丝牌 PNG 整图为底(等级已绘在图内,不叠数字),团名叠右侧
    // (web douyuOfficial:content padding-left 1.58em≈22);失败回落中性深底
    // 团名胶囊;无团名则无可显示内容 → 不渲染。
    if (site == 'douyu') {
      if (!hasName) return const SizedBox.shrink();
      if (!_imgFailed &&
          badgeAssetPath(
            site: site,
            kind: ChatBadgeKind.fans,
            level: level,
          ).isNotEmpty) {
        return Container(
          height: 18, // web douyuOfficial 牌 1.28em ≈ 17.9
          constraints: const BoxConstraints(minWidth: 57), // 4.1em
          child: Stack(
            children: [
              Positioned.fill(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: ChatBadgeImage(
                    site: site,
                    kind: ChatBadgeKind.fans,
                    level: level,
                    height: 18,
                    onFail: _markImgFailed,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Center(
                  child: Text(
                    name.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.9, // web 0.78em
                      height: 1.1,
                      color: resolvedTextColor,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.01,
                      shadows: const [
                        Shadow(blurRadius: 2, color: Color(0x73000000)),
                        Shadow(
                          offset: Offset(0, 1),
                          blurRadius: 1,
                          color: Color(0x59000000),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return _BadgeBox(
        height: 15,
        radius: 999,
        color: neutralBg,
        child: Text(
          name.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 9,
            height: 1.1,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    // 其他平台:品牌色 pill(维持可见性,样式待该平台徽章对齐)。
    return _BadgeBox(
      height: 15,
      radius: 999,
      color: tokens.brand.withValues(alpha: 0.18),
      border: tokens.brand.withValues(alpha: 0.6),
      child: Text(
        label(site, name, hasName, level),
        style: TextStyle(
          fontSize: 9,
          height: 1.1,
          color: tokens.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 默认平台分支的胶囊文案:「团名 级」或纯等级。
  String label(String site, String? name, bool hasName, int level) =>
      hasName && name != null ? '${name.trim()} $level' : '$level';
}

/// 用户等级徽章(对齐 web ChatUserLevelBadge;本地图优先 → 文字兜底):
/// - 虎牙:消费/VIP emblem 整图 `huya/vip/v2/{identity}.png`(7 档 identity,
///   userLevels/huya.ts 档位表),图上叠白数字(web chatUserLevelOverlayText);
///   失败回落梯度数字 pill;
/// - 抖音:honor 荣誉图 `douyin/honor/{lv}.png`(≤75;图内含数字不叠文字);
///   失败/超档回落紫粉渐变数字;
/// - 斗鱼:保持文字「LV N」+ 梯度(CDN 全 404,web 强制文字);
/// - B 站:保持文字(wealth 不在本轮);
/// - 其他:「Lv N」+ 灰底(web default #6b7280)。
class _UserLevelBadge extends StatefulWidget {
  const _UserLevelBadge({required this.site, required this.level});

  final String site;
  final int level;

  @override
  State<_UserLevelBadge> createState() => _UserLevelBadgeState();
}

class _UserLevelBadgeState extends State<_UserLevelBadge> {
  /// 本地图加载失败/缺失:回落文字态(输入变化后重置重试)。
  bool _imgFailed = false;

  @override
  void didUpdateWidget(covariant _UserLevelBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site || oldWidget.level != widget.level) {
      _imgFailed = false;
    }
  }

  void _markImgFailed() {
    if (mounted) setState(() => _imgFailed = true);
  }

  @override
  Widget build(BuildContext context) {
    final site = widget.site;
    final level = widget.level;
    // 虎牙:消费/VIP emblem 整图 + 右下白数字叠层
    // (web chat-user-level--huya--icon:min-width 2.1em≈29、高 1.48em≈21、
    // 叠字 right .12em/bottom .06em、0.58em≈8.1、w700 白字黑影)。
    if (site == 'huya' &&
        !_imgFailed &&
        badgeAssetPath(
          site: site,
          kind: ChatBadgeKind.userLevel,
          level: level,
        ).isNotEmpty) {
      return Container(
        height: 21,
        constraints: const BoxConstraints(minWidth: 29),
        child: Stack(
          children: [
            // 非 positioned 子节点(图片)撑开 Stack 宽度,右下数字相对图定位;
            // Row 内宽度无界,Stack 不能只含 positioned 子节点(需有界约束)。
            Align(
              alignment: Alignment.centerLeft,
              child: ChatBadgeImage(
                site: site,
                kind: ChatBadgeKind.userLevel,
                level: level,
                height: 21,
                onFail: _markImgFailed,
              ),
            ),
            Positioned(
              right: 1.7,
              bottom: 0.8,
              child: Text(
                '$level',
                style: const TextStyle(
                  fontSize: 8.1,
                  height: 1,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  shadows: [Shadow(blurRadius: 2, color: Color(0x8c000000))],
                ),
              ),
            ),
          ],
        ),
      );
    }
    // 抖音:honor 整图(等级绘在图内);失败/超 75 档回落紫粉渐变数字。
    if (site == 'douyin' &&
        !_imgFailed &&
        badgeAssetPath(
          site: site,
          kind: ChatBadgeKind.userLevel,
          level: level,
        ).isNotEmpty) {
      return ChatBadgeImage(
        site: site,
        kind: ChatBadgeKind.userLevel,
        level: level,
        height: 21, // web chat-user-level__icon 1.48em ≈ 20.7
        onFail: _markImgFailed,
      );
    }
    // 斗鱼/B站/其他/图片兜底:既有文字态(web 文字样式)。
    List<Color> colors;
    var label = '';
    if (site == 'douyu' || site == 'bilibili') {
      label = 'LV$level';
      colors = _levelTier(level, const [50, 40, 30, 20, 10]);
    } else if (site == 'douyin') {
      label = '$level';
      colors = const [Color(0xffa855f7), Color(0xffec4899)];
    } else if (site == 'huya') {
      label = '$level';
      colors = _levelTier(level, const [80, 60, 40, 20, 10]);
    } else {
      // 其他平台:web userLevelLabel 默认纯数字,灰底不变(default #6b7280)。
      label = '$level';
      colors = const [Color(0xff6b7280)];
    }
    return _BadgeBox(
      height: 16,
      minWidth: 16,
      radius: 2,
      gradient: colors.length > 1 ? colors : null,
      color: colors.length == 1 ? colors.first : null,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          height: 1.1,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 徽章底座:固定行高 + 渐变/纯色/描边 + 居中内容。
///
/// 渐变默认方向对齐 CSS `linear-gradient(90deg, A, B)`:colors[0] 在左;
/// B 站 `to left`(start 在右)由调用方显式传 [gradientBegin]/[gradientEnd] 覆写。
class _BadgeBox extends StatelessWidget {
  const _BadgeBox({
    required this.height,
    required this.child,
    this.minWidth = 0,
    this.radius = 999,
    this.gradient,
    this.color,
    this.border,
    this.gradientBegin = Alignment.centerLeft,
    this.gradientEnd = Alignment.centerRight,
  });

  final double height;
  final double minWidth;
  final double radius;
  final List<Color>? gradient;
  final Color? color;
  final Color? border;
  final Alignment gradientBegin;
  final Alignment gradientEnd;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final decoration = BoxDecoration(
      gradient: gradient == null
          ? null
          : LinearGradient(
              begin: gradientBegin,
              end: gradientEnd,
              colors: gradient!,
            ),
      color: color,
      borderRadius: BorderRadius.circular(radius),
      border: border == null ? null : Border.all(color: border!, width: 1),
    );
    return Container(
      height: height,
      constraints: minWidth > 0 ? BoxConstraints(minWidth: minWidth) : null,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      alignment: Alignment.center,
      decoration: decoration,
      child: child,
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
  /// true = 封面网格,false = 紧凑列表(每条一行)。
  /// **默认列表**是用户口径(2026-09-19:「默认用列表显示 列表显示每个
  /// 是一行」);web 真源默认封面预览(`previewCover: true`),此处有意偏离。
  /// 取值与变更都会写进会话级偏好 —— 切房重建后不丢。
  bool get _grid => ref.watch(playSidePanelPrefsProvider).followGrid;
  set _grid(bool value) =>
      ref.read(playSidePanelPrefsProvider.notifier).update(followGrid: value);

  String get _siteFilter => ref.watch(playSidePanelPrefsProvider).followSite;
  set _siteFilter(String value) =>
      ref.read(playSidePanelPrefsProvider.notifier).update(followSite: value);

  /// 已展示条数(分页窗口)。对齐 web `PLAY_FOLLOW_PAGE_SIZE = 48`:
  /// 首屏只放 48 条,滚到底再放一页,底部提示「向下滚动加载更多…」。
  int _visibleCount = _kFollowPageSize;

  /// 距底部多少像素内视为「滚到底」(触发下一页加载)。
  static const double _kLoadMoreTriggerExtent = 96;

  /// 单页条数(web `PLAY_FOLLOW_PAGE_SIZE`)。
  static const int _kFollowPageSize = 48;

  /// 本轮待渲染的可见条目总数(由 build 写入,供滚动回调判定还有没有下一页)。
  int _visibleTotal = 0;

  /// 侧栏可见性口径:**只显在播**(用户口径 2026-09-19:「不用显示没开播
  /// 的」)。排序 = 超关在播 → 普通在播(follow_sort 统一档位,未开播档
  /// 自然为空)。
  ///
  /// 口径沿革:2026-09-18 曾对齐 web `isPlayFollowVisible` 保留离线超关
  /// (当时为修「关注没显示」),随后被本口径覆盖 —— web 真源的离线超关
  /// 分支为有意偏离,见 follow_sort.dart 注释。
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
    return Column(
      key: const Key('play-side-follow-panel'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 无「我的关注」标题(用户口径 2026-09-19:顶部不要标题);
        // 视图切换按钮挪进平台筛选行,对齐 web `follow-tab-toolbar`
        // (list 按钮 + 筛选 chips 同一行)。
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const SizedBox(width: AppSpacing.sm),
            Tooltip(
              message: _grid ? '切换为列表视图' : '切换为封面预览',
              child: IconButton(
                key: const Key('play-side-follow-view-toggle'),
                onPressed: () => setState(() => _grid = !_grid),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                icon: Icon(
                  // 卡片态显示「列表」入口、列表态显示「网格」入口(点击即切)。
                  _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 18,
                  color: _grid ? tokens.textSecondary : tokens.accent,
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                // 与「我的关注」页共用同一 [FollowPlatformFilter](web 两处
                // 同为 FollowPlatformFilter.vue):侧栏紧凑 + 6 列等宽,
                // chips 放不下自动换到第二排。
                child: FollowPlatformFilter(
                  value: _siteFilter,
                  onChanged: (site) => setState(() {
                    _siteFilter = site;
                    // 换平台等于换列表:分页窗口回到首屏(否则一换平台就直接铺满 48×n)。
                    _visibleCount = _kFollowPageSize;
                  }),
                  compact: true,
                  columns: 6,
                  chipKey: (id) => Key('play-side-follow-site-$id'),
                ),
              ),
            ),
          ],
        ),
        Expanded(
          child: entries.isEmpty
              ? const _PanelHint(
                  icon: Icons.star_border_rounded,
                  title: '我的关注',
                  text: '暂无在播关注',
                )
              : NotificationListener<ScrollNotification>(
                  onNotification: _onScroll,
                  // 与「我的关注」页共用同一 [FollowRoomList]:侧栏走 compact
                  // (卡片隐藏操作/统计、固定 2 列),两档 = 封面卡 / 列表。
                  // 列表是每主播一行的单行表格,侧栏窄列下左右 padding 再
                  // 收一档(用户口径 2026-09-20)。
                  child: FollowRoomList(
                    entries: windowed,
                    density: _grid ? FollowDensity.card : FollowDensity.row,
                    compact: true,
                    cardColumns: 2,
                    padding: EdgeInsets.fromLTRB(
                      _grid ? AppSpacing.sm : AppSpacing.xs,
                      0,
                      _grid ? AppSpacing.sm : AppSpacing.xs,
                      AppSpacing.sm,
                    ),
                    onTap: (entry) => _goRoom(entry.room),
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
        style: context.textCaption,
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
    final throttled = settings.chatThrottleMode == ChatThrottleMode.perNSeconds;
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
              trailing: CompactSwitch(
                key: const Key('play-side-setting-chat'),
                value: settings.chatEnabled,
                onChanged: (enabled) =>
                    ref.read(settingsProvider.notifier).setChatEnabled(enabled),
              ),
            ),
            // 聊天开时内联渲染设置(对齐 web SideSettingsTab.vue 41-105:
            // 透明度 10-100 / 字号 12-24 / 间距 0-16 / 速度 1-10 + 节流开关),
            // 控制**侧栏聊天区**的消息渲染(字号/行距/透明度/放行速率)。
            // 旧「弹幕样式 → 调整」入口(飘屏弹幕设置对话框)已按用户口径
            // (2026-09-19)移除,飘屏细项不再从侧栏进入。
            if (settings.chatEnabled) ...[
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-opacity'),
                label: '透明度',
                value: settings.chatOpacity.toDouble(),
                min: SettingsState.chatOpacityMin.toDouble(),
                max: SettingsState.chatOpacityMax.toDouble(),
                valueText: '${settings.chatOpacity}%',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatOpacity(value.round()),
              ),
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-font-size'),
                label: '字号',
                value: settings.chatFontSize.toDouble(),
                min: SettingsState.chatFontSizeMin.toDouble(),
                max: SettingsState.chatFontSizeMax.toDouble(),
                valueText: '${settings.chatFontSize}',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatFontSize(value.round()),
              ),
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-gap'),
                label: '间距',
                value: settings.chatLineSpacing.toDouble(),
                min: SettingsState.chatLineSpacingMin.toDouble(),
                max: SettingsState.chatLineSpacingMax.toDouble(),
                valueText: '${settings.chatLineSpacing}',
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatLineSpacing(value.round()),
              ),
              _SettingSliderRow(
                key: const Key('play-side-setting-chat-speed'),
                label: '速度',
                value: settings.chatSpeed.toDouble(),
                min: SettingsState.chatSpeedMin.toDouble(),
                max: SettingsState.chatSpeedMax.toDouble(),
                enabled: throttled,
                valueText: throttled
                    ? '每${settings.chatSpeed}秒一条'
                    : ChatThrottleMode.unlimited.label,
                leading: CompactSwitch(
                  key: const Key('play-side-setting-chat-throttle'),
                  value: throttled,
                  onChanged: (on) => ref
                      .read(settingsProvider.notifier)
                      .setChatThrottleMode(
                        on
                            ? ChatThrottleMode.perNSeconds
                            : ChatThrottleMode.unlimited,
                      ),
                ),
                onChanged: (value) => ref
                    .read(settingsProvider.notifier)
                    .setChatSpeed(value.round()),
              ),
            ],
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
        // 对齐 web .settings-group 圆角(--fluent-radius-sm ≈ 8)。
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: TextStyle(
              // 对齐 web .settings-group__title(.78rem ≈ 12.5)。
              fontSize: 12.5,
              height: 1.2,
              color: context.tokens.accent,
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
        Expanded(child: Text(label, style: context.textCaption)),
        trailing,
      ],
    );
  }
}

/// 设置滑杆行(对齐 web SideSettingsTab `.setting-row` 三列布局:
/// label 列约 3.25rem、滑杆弹性、数值右对齐)。
///
/// [leading] 供速度行放节流开关(web el-checkbox,位于滑杆前);
/// [enabled] = false 时滑杆禁用但数值文案保留(web 速度行在全量态的呈现)。
class _SettingSliderRow extends StatelessWidget {
  const _SettingSliderRow({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.valueText,
    required this.onChanged,
    this.enabled = true,
    this.leading,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final String valueText;

  /// null = 禁用(节流关闭时的速度滑杆)。
  final ValueChanged<double>? onChanged;
  final bool enabled;

  /// 滑杆前的附加控件(节流开关)。
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Row(
      children: [
        // 对齐 web label 列 3.25rem ≈ 52。
        SizedBox(width: 52, child: Text(label, style: context.textCaption)),
        if (leading != null) ...[leading!, const SizedBox(width: 4)],
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              divisions: (max - min).round(),
              activeColor: tokens.accent,
              inactiveColor: tokens.border,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ),
        // 右对齐数值文案(对齐 web .setting-value),宽度容纳「每10秒一条」。
        SizedBox(
          width: 72,
          child: Text(
            valueText,
            textAlign: TextAlign.right,
            style: context.textCaption,
          ),
        ),
      ],
    );
  }
}

/// 自绘迷你开关(对齐 web el-switch 密度:轨道 30×16、圆角 8、滑块 12)。
///
/// 选中轨道品牌紫(tokens.accent);未选中透明底 + #3a3a3a 描边。
/// 保留 Material Switch 的 value/onChanged/Semantics(toggled) 语义,
/// 只是视觉收敛为侧栏密度尺寸。
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
            Text(text, textAlign: TextAlign.center, style: context.textCaption),
          ],
        ),
      ),
    );
  }
}
