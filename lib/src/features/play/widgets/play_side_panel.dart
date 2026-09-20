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

import 'package:flutter/foundation.dart' show listEquals;
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
import '../../../shared/application/translation/translation_provider.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/widgets/compact_switch.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import 'chat_badge_image.dart';
import 'play_meta_bar.dart';
import 'play_recommend_panel.dart';
import '../../follow/widgets/follow_platform_filter.dart';
import '../../follow/widgets/follow_room_list.dart';

part 'side_panel/side_panel_header.dart';
part 'side_panel/chat_tab.dart';
part 'side_panel/chat_row.dart';
part 'side_panel/chat_badges.dart';
part 'side_panel/follow_panel.dart';
part 'side_panel/recommend_panel.dart';
part 'side_panel/settings_panel.dart';

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
