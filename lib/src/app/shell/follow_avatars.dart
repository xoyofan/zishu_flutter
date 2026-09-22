part of '../app_shell.dart';

/// 导航项里的在播关注头像堆叠(web `NavSidebar.vue` 的 `.nav-follow-avatars`)。
///
/// 规格取自 web CSS:`--nav-follow-avatar-size: 1.48rem`(≈23.68px)、
/// `--nav-follow-avatar-overlap: 0.32`(相邻头像左移 32% 宽度实现堆叠),
/// 上限 `NAV_FOLLOW_AVATAR_LIMIT = 3`;没有在播时**回落星形图标**
/// (web `v-else` 分支的 `StarFilled`)。
///
/// 在播列表走 [visibleFollowEntries] 的 `liveOnly`(与 hover 浮层同一份口径),数据由关注状态
/// 定时刷新链路(FollowStatusPoller,60s)驱动 —— 这里不另起定时器。
class _NavFollowAvatars extends ConsumerWidget {
  const _NavFollowAvatars({this.size = topSize});

  /// 顶栏尺寸:1.48rem。
  static const double topSize = 23.68;

  /// 底栏尺寸:56px 高的底栏里再留出文案行,取 20px。
  static const double bottomSize = 20;

  /// 重叠比例(web `--nav-follow-avatar-overlap`):相邻头像左移 size×0.32。
  static const double overlapRatio = 0.32;

  /// 上限(web `NAV_FOLLOW_AVATAR_LIMIT`)。
  static const int limit = 3;

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final live = visibleFollowEntries(
      ref.watch(followProvider),
      liveOnly: true,
    );
    if (live.isEmpty) {
      return Icon(
        Icons.star_border_rounded,
        size: size * 0.76,
        color: context.tokens.textSecondary,
      );
    }
    final shown = live.take(limit).toList();
    final step = size * (1 - overlapRatio);
    final width = size + (shown.length - 1) * step;
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              // 左起第一个在最上层(web 用 `zIndex: length - index` 配 margin-left 负值)。
              left: i * step,
              child: _NavFollowAvatar(entry: shown[i], size: size),
            ),
        ],
      ),
    );
  }
}

/// 单个圆形头像:封面图 + 首字兜底(与浮层单格同一套兜底口径)。
class _NavFollowAvatar extends StatelessWidget {
  const _NavFollowAvatar({required this.entry, required this.size});

  final FollowEntry entry;
  final double size;

  @override
  Widget build(BuildContext context) {
    final room = entry.room;
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: context.tokens.surfaceRaised,
        shape: BoxShape.circle,
      ),
      child: Text(
        room.anchorName.isEmpty ? '?' : room.anchorName.substring(0, 1),
        style: TextStyle(
          fontSize: size * 0.5, // ignore: design_token 几何比例(头像首字母随容器缩放),非排版字号档
          color: context.tokens.textSecondary,
        ),
      ),
    );
    return Container(
      key: Key('nav-follow-avatar-${room.site}-${room.roomId}'),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: context.tokens.surfaceSoft),
      ),
      child: room.cover.isEmpty
          ? fallback
          : ClipOval(
              child: CachedNetworkImage(
                imageUrl: room.cover,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_, _, _) => fallback,
              ),
            ),
    );
  }
}

/// 「我的关注」hover 出的主播网格:对齐 SFVideoLive
/// `FollowHoverAvatarGrid.vue`(7 列、头像 1.85rem、名字 .56rem、最多 5 行滚动)。
/// 开播中优先;无开播时退化为全部关注,避免空面板。
class _FollowFlyout extends ConsumerWidget {
  const _FollowFlyout({
    required this.columns,
    required this.onEnter,
    required this.onExit,
    required this.onOpenRoom,
  });

  /// 实际列数(由壳层按在播数算好传入,与面板宽度同源)。
  final int columns;

  /// 头像 1.85rem ≈ 29.6px。
  static const double _kAvatarSize = 29.6;

  /// 名字 .56rem ≈ 9px。
  static const double _kNameSize = AppFontSize.overline;

  /// 行间距 .22rem ≈ 3.52px;列间距 .06rem ≈ 0.96px。
  static const double _kRowGap = 3.52;
  static const double _kColumnGap = 0.96;

  /// 5 行可见高度 + padding(同 `.follow-hover-avatar-grid` 的 max-height)。
  static const double _kMaxHeight = 280;

  final VoidCallback onEnter;
  final VoidCallback onExit;

  /// 点主播格进播放页:由壳层提供(负责先收起浮层再入栈)。
  final void Function(FollowEntry entry) onOpenRoom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 只列**在播**:浮层是「现在能点进去看」的快捷入口。离线条目(包括离线
    // 超关)只在「我的关注」页/播放页侧栏保留 —— 两个入口的可见性口径不同,
    // 见 follow_sort.dart 的 isPlayFollowVisible 与 visibleFollowEntries。
    // 对齐参考实现 `NavSidebar.vue`:`liveFollows` + 空态「暂无开播」
    // (旧实现在没有在播时兜底展示全部条目,与参考实现相反)。
    //
    // 与导航项的头像堆叠共用 [visibleFollowEntries] 同一份口径(同一排序、同一
    // 在播判据),避免「浮层里有 A、导航头像里是 B」的两套世界。
    final live = visibleFollowEntries(
      ref.watch(followProvider),
      liveOnly: true,
    );
    return MouseRegion(
      onEnter: (_) => onEnter(),
      onExit: (_) => onExit(),
      child: _FlyoutPanel(
        key: const Key('follow-flyout-panel'),
        padding: const EdgeInsets.fromLTRB(3.52, 4.16, 3.52, 3.52),
        maxHeight: _kMaxHeight,
        child: live.isEmpty
            ? const _FlyoutHint('暂无开播')
            : GridView.builder(
                shrinkWrap: true,
                itemCount: live.length,
                // 列数按实际在播数收敛:条目少时不留空列(传进来的 columns
                // 与面板宽度同源,格宽因此保持稳定)。
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisExtent: 50,
                  mainAxisSpacing: _kRowGap,
                  crossAxisSpacing: _kColumnGap,
                ),
                itemBuilder: (context, index) => _FollowAvatarTile(
                  entry: live[index],
                  onTap: () => onOpenRoom(live[index]),
                ),
              ),
      ),
    );
  }
}

/// 关注浮层单格:圆形头像 + 单行名字(超长省略),点击进入播放页。
///
/// 每格底色与名字都取**平台品牌色**:底为低透明度品牌色,hover 时加深,
/// 让「哪个平台的主播」在网格里一眼可辨(未收录平台回退主文字色)。
class _FollowAvatarTile extends StatelessWidget {
  const _FollowAvatarTile({required this.entry, required this.onTap});

  final FollowEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final room = entry.room;
    final brand = PlatformBrandCatalog.byId(room.site);
    final color = brand?.color ?? context.tokens.textPrimary;
    return Tooltip(
      message: '${room.anchorName} · ${room.title}',
      child: Ink(
        color: color.withValues(alpha: 0.16),
        child: InkWell(
          hoverColor: color.withValues(alpha: 0.3),
          // 焦点/按下也用**平台品牌色**(本格的语义色,不用通用 accent),
          // 与 hover 同源;焦点另走抬升档保证键盘可见性。
          focusColor: AppStateLayer.focusOf(context.tokens.accent),
          splashColor: AppStateLayer.splashOf(color),
          // 按下在 hover(0.3)基础上再压一档(DESIGN.md §4.2)。
          highlightColor: AppStateLayer.pressedOf(color),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 0.96, vertical: 2.56),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _avatar(context, room),
                SizedBox(height: 1.92),
                Text(
                  room.anchorName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: _FollowFlyout._kNameSize,
                    color: color,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _avatar(BuildContext context, RoomSummary room) {
    final fallback = CircleAvatar(
      radius: _FollowFlyout._kAvatarSize / 2,
      backgroundColor: context.tokens.surfaceRaised,
      child: Text(
        room.anchorName.isEmpty ? '?' : room.anchorName.substring(0, 1),
        style: TextStyle(
          fontSize: AppFontSize.bodySecondary,
          color: context.tokens.textSecondary,
        ),
      ),
    );
    if (room.cover.isEmpty) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: room.cover,
        width: _FollowFlyout._kAvatarSize,
        height: _FollowFlyout._kAvatarSize,
        fit: BoxFit.cover,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
