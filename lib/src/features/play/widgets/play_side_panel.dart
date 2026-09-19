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
import '../../../platforms/common/open_external_url.dart';
import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/platform_icon.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import 'play_meta_bar.dart';
import 'play_recommend_panel.dart';
import 'play_room_grid.dart';

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
  }) =>
      PlaySidePanelPrefs(
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

  void update({
    int? tabIndex,
    bool? followGrid,
    String? followSite,
  }) {
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
                labelColor: tokens.brand,
                unselectedLabelColor: tokens.textSecondary,
                indicatorColor: tokens.brand,
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
class _SideHeader extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final anchor = payload?.anchorName.trim().isNotEmpty == true
        ? payload!.anchorName
        : '主播信息';
    final avatar = payload?.avatar.trim() ?? '';
    final title = payload?.title.trim() ?? '';
    final category = payload?.category.trim() ?? '';
    final isLive = payload?.isLive ?? false;
    // 统计区(对齐 web SideHeader「关注：N」行 + stats 列):
    // 未关注/上游未提供 → '—' 占位,不伪造(数据诚实性)。
    final followRoom = this.followRoom;
    final followersText = _statText(followRoom?.followers);
    final audienceText = _statText(followRoom?.online);
    final vipText = _statText(followRoom?.vip);

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
          _SideAvatar(
            avatar: avatar,
            label: anchor,
            live: isLive,
            followed: followed,
            remindOn: remindOn,
            externalUrl: externalUrl,
            onToggleRemind: onToggleRemind,
            onOpenExternal: onOpenExternal,
          ),
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
    required this.followed,
    required this.remindOn,
    required this.externalUrl,
    required this.onToggleRemind,
    required this.onOpenExternal,
  });

  final String avatar;
  final String label;
  final bool live;

  /// 当前房间是否已关注(决定提醒按钮可用性,web `v-if="roomIsFollowed"`
  /// 的 flutter 占位等价:不隐藏、禁用)。
  final bool followed;

  /// 开播提醒开关(web `liveNotifyEnabled`)。
  final bool remindOn;

  /// 当前房间 web 页地址(null = 无稳定外链)。
  final String? externalUrl;
  final VoidCallback onToggleRemind;
  final ValueChanged<String> onOpenExternal;

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
          Positioned(
            right: -4,
            top: -4,
            child: _HeaderIconButton(
              key: const Key('play-side-notify'),
              // web bell/bell-off 两态(SideHeader.vue:27):关=bell-off
              // 中性色;开=bell + amber 激活色(语义=开播/下播提醒开关)。
              icon: remindOn
                  ? Icons.notifications_rounded
                  : Icons.notifications_off_rounded,
              tooltip: followed
                  ? (remindOn ? '已开启开播/下播提醒，点击关闭' : '开启开播/下播提醒')
                  : '关注后可开启开播提醒',
              // 未关注 = 无可提醒目标,禁用(web 直接隐藏,flutter 留占位)。
              onPressed: followed ? onToggleRemind : null,
              activeColor: remindOn ? const Color(0xfff3d04e) : null,
            ),
          ),
          Positioned(
            right: -4,
            bottom: -4,
            child: _HeaderIconButton(
              key: const Key('play-side-external'),
              icon: Icons.open_in_new_rounded,
              tooltip: '打开直播间页面',
              onPressed: externalUrl == null
                  ? null
                  : () => onOpenExternal(externalUrl!),
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
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;

  /// null = 禁用(未关注无可提醒目标 / 无稳定 web url)。
  final VoidCallback? onPressed;

  /// 图标强调色(如外链蓝 #60a5fa,web `.room-aside-link-btn`)。
  final Color? accent;

  /// 激活态色(amber #f3d04e,web `--amber`):图标取该色,底色取该色
  /// 22% 混底,对齐 web `.room-aside-notify-btn--on`。
  final Color? activeColor;

  @override
  Widget build(BuildContext context) {
    final active = activeColor;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: active != null
            ? Color.alphaBlend(
                active.withValues(alpha: 0.22),
                context.tokens.surfaceRaised,
              )
            : context.tokens.surfaceRaised,
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
              color: active ?? accent ?? context.tokens.textSecondary,
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
  });

  final String user;
  final String message;

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
    final rows = [
      for (final message in chat.messages) _ChatRowData.fromMessage(message, widget.site),
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
              if (rows.isEmpty)
                Center(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Text(
                      chat.isUnsupported ? '当前站点暂不支持弹幕' : '暂无弹幕，等待水友发言…',
                      textAlign: TextAlign.center,
                      style: context.textCaption,
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
                // 对齐 web .chat-new-bar:底部水平居中,距底 0.5rem=8。
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 8,
                  child: Center(
                    child: _NewMessagesButton(
                      count: pending,
                      onTap: () {
                        _seenCount = rows.length;
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
    final fanBadge = data.fanLevel;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 徽章顺序对齐 web SideChatTab.vue:38-44 —— 平台用户等级 pill 在前、
        // 粉丝牌在后(用户口径 2026-09-19:「平台等级应该在粉丝等级前显示」)。
        // 间距对齐 web:徽章 margin-right 0.14em(14px 基 ≈ 2px)。
        if (data.userLevel > 0) ...[
          _UserLevelBadge(site: data.site, level: data.userLevel),
          const SizedBox(width: 2),
        ],
        if (fanBadge != null) ...[
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
          const SizedBox(width: 2),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: data.user,
                  style: context.textSecondary.copyWith(
                    color: _userColor(),
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    height: 1.48,
                  ),
                ),
                TextSpan(
                  text: '：',
                  style: context.textSecondary.copyWith(
                    fontSize: 14,
                    height: 1.48,
                  ),
                ),
                TextSpan(
                  text: data.message,
                  style: context.textSecondary.copyWith(
                    color: tokens.textPrimary,
                    fontSize: 14,
                    height: 1.48,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
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

/// 粉丝牌(对齐 web ChatFanBadge 文字态各平台分支;图片分支待契约补 URL):
/// - 斗鱼:胶囊只显示团名(web `CHAT_FAN_BADGE_HIDE_LEVEL_SITES` 含 douyu,
///   等级已绘在官方 PNG 里;文字态无梯度 → 中性深底白字兜底;无团名不渲染);
/// - B 站:胶囊「团名 级」,协议渐变(`to left`:start 在右→end 在左)+ 描边,
///   start/end 互补缺省;无协议色时中性深底兜底(web 走官方边框图);
///   消费协议文字色/等级数字色(0 = 回落白/文字色);
/// - 抖音:红色渐变圆盘只显示等级数字(douyinTextFallback 明确样式);
/// - 虎牙:渐变条 = 等级圆盘(黑 22% 叠层) + 团名(HUYA_BAR_GRADIENTS 7 档);
/// - 其他:品牌色 pill。
class _FanBadge extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final hasName = name != null && name!.trim().isNotEmpty;
    // web 斗鱼/B站文字态无梯度兜底:中性深底白字(web 无协议图/色时走
    // 官方图片牌,flutter 无图 → 深底占位保持可读)。
    const neutralBg = Color(0xff3a3a3a);
    final resolvedTextColor = textColor != 0 ? Color(textColor) : Colors.white;
    final resolvedLevelColor = levelColor != 0
        ? Color(levelColor)
        : resolvedTextColor;

    // 抖音:红色渐变圆盘(无团名,只显示等级数字)。
    // 尺寸对齐 web douyinTextFallback(14px 基):min 1.4em=19.6、字 0.78em≈11。
    if (site == 'douyin') {
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
    // 虎牙:渐变条 = 圆盘等级 + 团名。
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
                name!.trim(),
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
    // B 站:协议渐变(to left:start 在右)+ 描边;无协议色回落中性深底。
    if (site == 'bilibili') {
      // 互补缺省(web buildBilibiliBadgeStyle:start=colorStart||colorEnd)。
      final start = colorStart != 0 ? colorStart : colorEnd;
      final end = colorEnd != 0 ? colorEnd : colorStart;
      final hasProtocolColor = start != 0 || end != 0;
      return _BadgeBox(
        height: 21,
        radius: 999,
        gradient: hasProtocolColor ? [Color(start), Color(end)] : null,
        color: hasProtocolColor ? null : neutralBg,
        // web `linear-gradient(to left, start, end)`:start 在右、end 在左。
        gradientBegin: Alignment.centerRight,
        gradientEnd: Alignment.centerLeft,
        border: colorBorder != 0 ? Color(colorBorder) : null,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (hasName)
              Flexible(
                child: Text(
                  name!.trim(),
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
        ),
      );
    }
    // 斗鱼:胶囊只显示团名(等级已绘在官方 PNG,文字态不再重复;
    // 无团名则无可显示内容 → 不渲染)。
    if (site == 'douyu') {
      if (!hasName) return const SizedBox.shrink();
      return _BadgeBox(
        height: 15,
        radius: 999,
        color: neutralBg,
        child: Text(
          name!.trim(),
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
        label(hasName),
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
  String label(bool hasName) => hasName ? '${name!.trim()} $level' : '$level';
}

/// 用户等级 pill(对齐 web ChatUserLevelBadge 文字兜底):
/// - 斗鱼/B 站:「LV N」+ 等级梯度([50,40,30,20,10]),方角;
/// - 抖音:纯数字 + 固定紫粉渐变(#a855f7→#ec4899);
/// - 虎牙:纯数字 + 梯度([80,60,40,20,10]);
/// - 其他:「Lv N」+ 灰底(web default #6b7280)。
class _UserLevelBadge extends StatelessWidget {
  const _UserLevelBadge({required this.site, required this.level});

  final String site;
  final int level;

  @override
  Widget build(BuildContext context) {
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
  set _siteFilter(String value) => ref
      .read(playSidePanelPrefsProvider.notifier)
      .update(followSite: value);

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
    final rooms = [for (final entry in windowed) entry.room];
    final superKeys = <String>{
      for (final entry in windowed)
        if (entry.isSpecial) entry.key,
    };
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
                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: Icon(
                  _grid ? Icons.list_rounded : Icons.grid_view_rounded,
                  size: 15,
                  color: _grid ? tokens.textSecondary : tokens.brand,
                ),
              ),
            ),
            Expanded(
              child: _SidePlatformChips(
                value: _siteFilter,
                onChanged: (site) => setState(() {
                  _siteFilter = site;
                  // 换平台等于换列表:分页窗口回到首屏(否则一换平台就直接铺满 48×n)。
                  _visibleCount = _kFollowPageSize;
                }),
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
        style: context.textCaption,
      ),
    );
  }
}

/// 侧栏平台筛选:平台图标格子(与顶栏平台 tab 同款 [PlatformIcon]),
/// Wrap 自动折行(用户口径 2026-09-19:「chips 不用文字,用平台图标;
/// 可以 2 行显示,不必非要一行」)。
///
/// 选中态对齐顶栏:图标底色提亮 + 品牌色描边 + 品牌色柔光。
class _SidePlatformChips extends StatelessWidget {
  const _SidePlatformChips({required this.value, required this.onChanged});

  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      child: Wrap(
        spacing: 5,
        runSpacing: 4,
        children: [
          for (final brand in PlatformBrandCatalog.navigationPlatforms)
            Tooltip(
              message: brand.id == 'all' ? '全平台' : brand.name,
              child: InkWell(
                key: Key('play-side-follow-site-${brand.id}'),
                borderRadius: AppRadius.allSm,
                onTap: () => onChanged(brand.id),
                child: AnimatedContainer(
                  duration: AppMotion.fast,
                  width: 30,
                  height: 30,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == brand.id
                        ? tokens.surfaceRaised
                        : Colors.transparent,
                    border: Border.all(
                      color: value == brand.id
                          ? brand.color
                          : Colors.transparent,
                    ),
                    borderRadius: AppRadius.allSm,
                    boxShadow: value == brand.id
                        ? [
                            BoxShadow(
                              color: brand.color.withValues(alpha: 0.22),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: PlatformIcon(id: brand.id, size: 24),
                ),
              ),
            ),
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
              trailing: _MiniSwitch(
                key: const Key('play-side-setting-chat'),
                value: settings.chatEnabled,
                onChanged: (enabled) =>
                    ref.read(settingsProvider.notifier).setChatEnabled(enabled),
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
        Expanded(child: Text(label, style: context.textCaption)),
        trailing,
      ],
    );
  }
}

/// 自绘迷你开关(对齐 web el-switch 密度:轨道 30×16、圆角 8、滑块 12)。
///
/// 选中轨道 amber(#f3d04e,web `--amber`);未选中透明底 + #3a3a3a 描边。
/// 保留 Material Switch 的 value/onChanged/Semantics(toggled) 语义,
/// 只是视觉收敛为侧栏密度尺寸。
class _MiniSwitch extends StatelessWidget {
  const _MiniSwitch({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const track = Color(0xfff3d04e);
    const offBorder = Color(0xff3a3a3a);
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        child: AnimatedContainer(
          duration: AppMotion.fast,
          width: 30,
          height: 16,
          decoration: BoxDecoration(
            color: value ? track : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: value ? track : offBorder),
          ),
          child: AnimatedAlign(
            duration: AppMotion.fast,
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            child: AnimatedContainer(
              duration: AppMotion.fast,
              width: 12,
              height: 12,
              margin: const EdgeInsets.all(1),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? Colors.white : context.tokens.textSecondary,
              ),
            ),
          ),
        ),
      ),
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
              style: context.textCaption,
            ),
          ],
        ),
      ),
    );
  }
}
