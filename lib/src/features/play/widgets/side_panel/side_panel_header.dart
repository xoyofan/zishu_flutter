part of '../play_side_panel.dart';

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
    // 第 3 列(tone=svip):web `ROOM_STAT_COLUMNS` 的 `field: "diamondFans"`
    // 槽位,douyu 钻粉 / huya 超粉 / douyin 会员 / bilibili 大航海。
    // 与上两列同口径:始终渲染,上游未提供 → '—'(数据诚实性,不伪造 0)。
    final svipText = _statText(stats?.diamondFans);

    // 信息头高度随系统字号缩放:固定 64px 在大字体(1.15x/1.3x)下会把
    // 中间三行元信息挤出容器底部(移动端实测 1px RenderFlex 溢出)。
    final headerHeight = MediaQuery.textScalerOf(context).scale(64.0);
    return Container(
      key: const Key('play-side-header'),
      height: headerHeight,
      decoration: BoxDecoration(
        // 3.2 毛玻璃侧栏:头部与面板同处**一个**玻璃平面。
        // 在玻璃面上(沉浸侧滑面板内)时不再铺不透明底 —— 否则会把面板透出的
        // 画面整块挡住(实测:只改面板一层滤镜时,画面被根/头部两层不透明底
        // 挡死,虚化完全看不见)。常规布局下面板背后只有画布底色,头部保持
        // 不透明 `surface` → 像素与改动前完全一致。
        color: AmbientGlass.onGlass(context)
            ? tokens.surface.withValues(alpha: 0)
            : tokens.surface,
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
            child: Column(
              // spaceBetween:第一行贴顶、第三行贴底,去掉上下留白,空间全给行间距。
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 第一行:主播名(中文化) + 粉丝数药丸(紧挨昵称、靠左)。
                Row(
                  children: [
                    Flexible(
                      child: TranslatedText(
                        anchor,
                        translateName: true,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.subtitle,
                          height: 1.08,
                          fontWeight: FontWeight.w600,
                          color: isLive ? tokens.liveBadge : tokens.textPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    // 粉丝数(用户口径 2026-09-22:紧挨昵称靠左 + 圆弧外框)。
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: tokens.border),
                        borderRadius: AppRadius.allPill,
                      ),
                      child: Text(
                        '关注 $followersText',
                        key: const Key('play-side-stat-followers'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: AppFontSize.bodySecondary,
                          height: 1.2,
                          color: tokens.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
                // 分类显示在主播名后面那一行(用户口径 2026-09-19)。
                const SizedBox(height: 4),
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
                        style: const TextStyle(
                          fontSize: AppFontSize.bodySecondary,
                          height: 1.1,
                        ),
                      ),
                    ),
                    // 提醒(铃铛) + 网页(浏览器图标)。
                    const SizedBox(width: 4),
                    _SideTextAction(
                      key: const Key('play-side-notify'),
                      icon: remindOn
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_none_rounded,
                      label: remindOn ? '提醒中' : '提醒',
                      tooltip: followed
                          ? (remindOn ? '已开启开播/下播提醒，点击关闭' : '开启开播/下播提醒')
                          : '关注后可开启开播提醒',
                      onPressed: followed ? onToggleRemind : null,
                      active: remindOn,
                    ),
                    const SizedBox(width: 3),
                    _SideTextAction(
                      key: const Key('play-side-external'),
                      icon: Icons.open_in_browser_rounded,
                      label: '网页',
                      tooltip: '打开直播间页面',
                      onPressed: externalUrl == null
                          ? null
                          : () => onOpenExternal(externalUrl!),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 统计行:人气 + VIP + 第 3 列(SVIP 档)。「关注 N」已上移到
                // 第一排昵称右侧(用户口径 2026-09-22)。
                // 整行收进一个 FittedBox(scaleDown)兜底 —— 328px 面板
                // 配 1.3x 系统字号时多段内容会顶到行宽上限,等比缩放优于
                // RenderFlex 溢出(本项目有过溢出史)。列间距用 xs 而非
                // sm,为第 3 列腾出宽度。
                Flexible(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // 人气/观众(web stats[0]「观众」列;online 为空 = 离线或
                        // 尚未刷新回填,显示「—」)。
                        _StatValue(
                          key: const Key('play-side-stat-audience'),
                          icon: AppIcons.eye,
                          value: audienceText,
                          color: context.tokens.statAudience,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        // VIP/贵宾(web stats[1] vip 列;douyu/huya 贵宾、
                        // douyin 会员、soop 订阅;其余平台上游无 → 「—」)。
                        _StatValue(
                          key: const Key('play-side-stat-vip'),
                          icon: AppIcons.crown,
                          value: vipText,
                          color: context.tokens.statVip,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        // 第 3 列(web stats[2],tone 恒为 svip):
                        // douyu 钻粉 / huya 超粉 / douyin 会员 / bilibili
                        // 大航海,同一字段 [RoomSummary.diamondFans] 承载。
                        // 语义随平台变,故挂 Tooltip 说明列名(图标仅一个,
                        // 不额外占宽度)。
                        _StatValue(
                          key: const Key('play-side-stat-svip'),
                          icon: AppIcons.gem,
                          value: svipText,
                          color: context.tokens.statSvip,
                          tooltip: '${_svipStatLabel(site)} $svipText',
                        ),
                      ],
                    ),
                  ),
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
          Padding(
            padding: const EdgeInsets.only(
              top: 2,
              bottom: 2,
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

/// 第 3 统计列(tone=svip)在各平台的列名,逐字对齐 web
/// `ROOM_STAT_COLUMNS`(SFVideoLive `apps/web/src/config/platformCatalog.ts:29`):
/// douyu 钻粉 / huya 超粉 / douyin 会员 / bilibili 大航海。
/// 未登记该列的平台(xhs / youtube / soop / twitch 等)无专属语义,
/// 回落通用「会员」;这些平台的 [RoomSummary.diamondFans] 恒为空,
/// 列值显示「—」,不伪造。
String _svipStatLabel(String site) => switch (site) {
  'douyu' => '钻粉',
  'huya' => '超粉',
  'douyin' => '会员',
  'bilibili' => '大航海',
  _ => '会员',
};

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
                            fontSize: AppFontSize.display,
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
                              fontSize: AppFontSize.display,
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

/// 侧栏头第二排的小文字按钮:提醒/网页显示为图标 + 文字。描边 pill;
/// [active] 时走品牌紫强调。
///
/// 交互态:hover 抬一档底/highlight+splash 走 accent 低 alpha+键盘焦点走
/// accent 覆盖色(均只改颜色,不动尺寸;禁用态由 InkWell 自行忽略交互)。
class _SideTextAction extends StatelessWidget {
  const _SideTextAction({
    super.key,
    required this.icon,
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final String tooltip;

  /// null = 禁用(未关注无可提醒目标 / 无稳定 web url)。
  final VoidCallback? onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final enabled = onPressed != null;
    // 开启态 = 有 accent 底色/描边;禁用态连底色都不给(§4.2「不额外加灰罩」)。
    final on = active && enabled;
    final fg = !enabled
        ? tokens.textSecondary.withValues(alpha: 0.55)
        : active
        ? tokens.accent
        : tokens.textSecondary;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: on ? tokens.accent.withValues(alpha: 0.14) : Colors.transparent,
        shape: StadiumBorder(
          side: BorderSide(
            color: on ? tokens.accent.withValues(alpha: 0.55) : tokens.border,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onPressed,
          // hover:开启态在 accent 底色上再深一档;常态透明底按 §4.2 抬到
          // surfaceRaised(与卡片/浮层同一档)。
          hoverColor: on
              ? tokens.accent.withValues(alpha: 0.24)
              : tokens.surfaceRaised,
          // splash/highlight:accent 低 alpha;禁用态由 InkWell 自行忽略。
          splashColor: AppStateLayer.splashOf(tokens.accent),
          highlightColor: AppStateLayer.pressedOf(tokens.accent),
          // 键盘焦点:Material 系的 focusColor 覆盖色(外扩环留给自绘 chip)。
          focusColor: AppStateLayer.focusOf(tokens.accent),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 12, color: fg),
                const SizedBox(width: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    height: 1.2,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              ],
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
    final tokens = context.tokens;
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
              selected: followed,
              colors: _ActionChipColors(
                background: tokens.playFollowBg,
                hoverBackground: tokens.playFollowBgHover,
                activeBackground: tokens.playFollowBgActive,
                border: tokens.playFollowBorder,
                foreground: tokens.playFollowText,
                activeForeground: tokens.playFollowTextActive,
              ),
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
              selected: superFollowed,
              colors: _ActionChipColors(
                background: tokens.playSuperBg,
                hoverBackground: tokens.playSuperBgHover,
                activeBackground: tokens.playSuperBgActive,
                border: tokens.playSuperBorder,
                foreground: tokens.playSuperText,
                activeForeground: tokens.playSuperTextActive,
              ),
              onPressed: onToggleSuperFollow,
            ),
          ),
        ],
      ),
    );
  }
}

/// 关注 / 超关 chip 的状态配色族(红系 `playFollow*` / 紫系 `playSuper*`)。
///
/// 六个值全部来自 `context.tokens`(深浅主题各自解析,浅色主题下是浅底深字),
/// widget 内不出现裸色值。[activeBackground] / [activeForeground] 即 token 文档
/// 里的「已关注底 / 已关注文字」,同时充当**按下态**:未关注时按下就先预告
/// 已关注的配色(DESIGN.md §4.2「active / pressed 在 hover 基础上再压一档」)。
class _ActionChipColors {
  const _ActionChipColors({
    required this.background,
    required this.hoverBackground,
    required this.activeBackground,
    required this.border,
    required this.foreground,
    required this.activeForeground,
  });

  /// 常态底(未关注)。
  final Color background;

  /// hover 底:token `playFollowBgHover` / `playSuperBgHover`
  /// (此前全库零引用,本 chip 是它们的唯一接线点)。
  final Color hoverBackground;

  /// 已关注底 / 按下底。
  final Color activeBackground;

  /// 描边(常态与各态共用,不在状态间跳色)。
  final Color border;

  /// 常态文字与图标。
  final Color foreground;

  /// 已关注 / 按下时的文字与图标。
  final Color activeForeground;
}

/// 「关注 / 超关」chip:六态中的 rest / hover / pressed / focus 都在此自绘。
///
/// - 底色 / 描边由 [AnimatedContainer] 过渡(`AppMotion.fast` + `AppMotion.curve`),
///   **只改颜色与阴影,不改尺寸位置**(`DESIGN.md` §7 裁决:禁按压缩放/位移);
/// - 键盘焦点用 [AppFocus.ring] 外扩(2px 环 + 2px 间隙,不占布局);
/// - hover / pressed 另叠 [AppElevation.accentGlow] 强调色光晕(§6 已登记档位,
///   语义已从「选中态」扩到「选中态 + hover 态」)。
class _SideActionButton extends StatefulWidget {
  const _SideActionButton({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.colors,
    required this.onPressed,
  });

  final IconData icon;
  final String label;

  /// 已关注 / 已超关(常态即取 [colors] 的 active 档,与旧实现逐位同色)。
  final bool selected;
  final _ActionChipColors colors;
  final VoidCallback onPressed;

  @override
  State<_SideActionButton> createState() => _SideActionButtonState();
}

class _SideActionButtonState extends State<_SideActionButton> {
  bool _hovered = false;
  bool _pressed = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colors = widget.colors;
    // 已关注与按下共用 active 档:按下即「预告」已关注的配色,视觉不断层。
    final active = widget.selected || _pressed;
    final background = active
        ? colors.activeBackground
        : (_hovered ? colors.hoverBackground : colors.background);
    final foreground = active ? colors.activeForeground : colors.foreground;
    // 同屏只给一个最强信号:焦点环优先于 hover 光晕;两者都外扩、都不改尺寸。
    final glow = _focused
        ? AppFocus.ring(tokens.accent)
        : (_hovered || _pressed
              ? AppElevation.accentGlow(colors.border)
              : null);
    return Tooltip(
      message: widget.label,
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        decoration: BoxDecoration(
          color: background,
          borderRadius: AppRadius.allPill,
          border: Border.all(color: colors.border),
          boxShadow: glow,
        ),
        child: Material(
          // 透明壳只为 InkWell 提供墨水宿主;底色/描边由上面的
          // AnimatedContainer 承担(这样才能过渡)。
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: AppRadius.allPill,
            onTap: widget.onPressed,
            onHover: (value) => setState(() => _hovered = value),
            onFocusChange: (value) => setState(() => _focused = value),
            onTapDown: (_) => setState(() => _pressed = true),
            onTapUp: (_) => setState(() => _pressed = false),
            onTapCancel: () => setState(() => _pressed = false),
            // 涟漪/按压覆盖色从 chip **自身**文字色推导
            // (button-states「状态色由基色推导」),不引入外来色相。
            splashColor: AppStateLayer.splashOf(colors.activeForeground),
            highlightColor: AppStateLayer.pressedOf(colors.activeForeground),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(widget.icon, size: 12, color: foreground),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.label,
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
      ),
    );
  }
}

class _StatValue extends StatelessWidget {
  const _StatValue({
    super.key,
    required this.icon,
    required this.value,
    required this.color,
    this.tooltip,
  });

  final IconData icon;
  final String value;
  final Color color;

  /// 悬浮说明(第 3 列的列名随平台变,需要显式标注);null = 不加 Tooltip。
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: color.withValues(alpha: 0.88)),
        const SizedBox(width: 2),
        Text(
          value,
          style: TextStyle(
            fontSize: AppFontSize.body,
            height: 1,
            color: color,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
    final message = tooltip;
    if (message == null) return content;
    return Tooltip(message: message, child: content);
  }
}
