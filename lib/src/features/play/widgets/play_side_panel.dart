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
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

class PlaySidePanel extends StatefulWidget {
  const PlaySidePanel({
    super.key,
    this.site,
    this.roomId,
    this.payload,
    this.onToggleFollow,
    this.onToggleSuperFollow,
    this.playbackStatus = const PlaybackStatus(),
  });

  final String? site;
  final String? roomId;
  final RoomPayload? payload;
  final VoidCallback? onToggleFollow;
  final VoidCallback? onToggleSuperFollow;

  /// 聊天状态条左侧的播放状态指示(播放中/已暂停/静音)。
  /// 默认构造即可表达「播放中」,不引入 provider 依赖。
  final PlaybackStatus playbackStatus;

  @override
  State<PlaySidePanel> createState() => _PlaySidePanelState();
}

class _PlaySidePanelState extends State<PlaySidePanel> {
  bool _followed = false;
  bool _superFollowed = false;

  void _toggleFollow() {
    setState(() => _followed = !_followed);
    widget.onToggleFollow?.call();
  }

  void _toggleSuperFollow() {
    setState(() => _superFollowed = !_superFollowed);
    widget.onToggleSuperFollow?.call();
  }

  @override
  Widget build(BuildContext context) {
    final payload = widget.payload;
    final site = widget.site ?? payload?.site ?? '';
    final roomId = widget.roomId ?? payload?.roomId ?? '';
    final tokens = context.tokens;

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
            _SideHeader(
              site: site,
              roomId: roomId,
              payload: payload,
              followed: _followed,
              superFollowed: _superFollowed,
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
                  _ChatSampleList(playbackStatus: widget.playbackStatus),
                  _FollowPanel(),
                  _RecommendPanel(),
                  _SettingsPanel(),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
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
                          color: isLive ? tokens.liveBadge : tokens.textSecondary,
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
                      color: AppColors.playStatAudienceText,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    _StatValue(
                      icon: Icons.workspace_premium_outlined,
                      value: '—',
                      color: AppColors.playStatVipText,
                    ),
                    if (category.isNotEmpty) ...[
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(
                        child: Text(
                          category,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 10, color: tokens.textSecondary),
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
  const _SideAvatar({required this.avatar, required this.label, required this.live});

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
                            color: live ? tokens.liveBadge : tokens.textSecondary,
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
                              color: live ? tokens.liveBadge : tokens.textSecondary,
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
        color: AppColors.surfaceRaised,
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
              color: accent ?? AppColors.textSecondary,
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
              key: const Key('play-side-follow'),
              icon: followed ? Icons.favorite_rounded : Icons.favorite_border_rounded,
              label: followed ? '已关注' : '关注',
              foreground: followed
                  ? AppColors.playFollowTextActive
                  : AppColors.playFollowText,
              background: followed
                  ? AppColors.playFollowBgActive
                  : AppColors.playFollowBg,
              border: AppColors.playFollowBorder,
              onPressed: onToggleFollow,
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: _SideActionButton(
              key: const Key('play-side-super-follow'),
              icon: superFollowed ? Icons.star_rounded : Icons.star_border_rounded,
              label: superFollowed ? '已超关' : '超关',
              foreground: superFollowed
                  ? AppColors.playSuperTextActive
                  : AppColors.playSuperText,
              background: superFollowed
                  ? AppColors.playSuperBgActive
                  : AppColors.playSuperBg,
              border: AppColors.playSuperBorder,
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
  const _StatValue({required this.icon, required this.value, required this.color});

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

/// 一条样例弹幕:可选粉丝团徽章 + 用户名 + 正文。
class _ChatSample {
  const _ChatSample(this.user, this.message, {this.fanLevel});

  final String user;
  final String message;
  final int? fanLevel;
}

const List<_ChatSample> _chatSamples = [
  _ChatSample('星河不入梦', '来了来了，主播这波操作可以', fanLevel: 12),
  _ChatSample('奶茶三分甜', '晚上好呀，刚下班就来蹲直播'),
  _ChatSample('皮蛋solo', '这波是教科书级别，学会了吗', fanLevel: 7),
  _ChatSample('夜色温柔', '画质终于不糊了，表扬'),
  _ChatSample('风起于青萍之末', '前排围观，顺便签到', fanLevel: 23),
  _ChatSample('小狮子嗷呜', 'BGM 叫什么名字呀？'),
  _ChatSample('代码搬运工', '这个走位有点东西', fanLevel: 5),
  _ChatSample('今天也想摸鱼', '关注了关注了，明天还来'),
  _ChatSample('山间清风', '主播声音好听，讲解也细', fanLevel: 9),
  _ChatSample('烤冷面加蛋', '水友赛什么时候安排一下'),
  _ChatSample('云端漫步', '刚刚那波团战复盘讲得好', fanLevel: 31),
  _ChatSample('一只小海豹', '来了来了，老规矩先点个关注'),
];

/// 播放状态指示:聊天状态条左侧「播放中/已暂停/静音」文案 + 图标。
///
/// 组件内可配置参数,默认表达「播放中」;不引入 provider 依赖。状态文案
/// 一律避免全角冒号(见文件头硬约束),用半角括号区分静音态。
class PlaybackStatus {
  const PlaybackStatus({this.playing = true, this.muted = false});

  final bool playing;
  final bool muted;

  String get label =>
      playing ? (muted ? '播放中(静音)' : '播放中') : '已暂停';
}

class _ChatSampleList extends StatelessWidget {
  const _ChatSampleList({required this.playbackStatus});

  final PlaybackStatus playbackStatus;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: 31,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.surfaceSoft,
            border: Border(bottom: BorderSide(color: tokens.border)),
          ),
          child: Row(
            children: [
              Icon(
                playbackStatus.playing
                    ? Icons.play_arrow_rounded
                    : Icons.pause_rounded,
                size: 11,
                color: playbackStatus.playing
                    ? tokens.liveBadge
                    : tokens.textSecondary,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  playbackStatus.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption,
                ),
              ),
              const SizedBox(width: 12),
              Icon(Icons.circle, size: 7, color: tokens.liveBadge),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  '弹幕已连接',
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
                  onPressed: () {},
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  icon: Icon(Icons.refresh_rounded, size: 15, color: tokens.textSecondary),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              AppSpacing.xs,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            children: [
              for (final sample in _chatSamples)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: _ChatRow(sample: sample),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.sample});

  final _ChatSample sample;

  Color _userColor() {
    var hash = 0;
    for (final unit in sample.user.codeUnits) {
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
        if (sample.fanLevel != null) ...[
          _FanBadge(level: sample.fanLevel!),
          const SizedBox(width: 3),
        ],
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: sample.user,
                  style: AppTypography.bodySecondary.copyWith(
                    color: _userColor(),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                TextSpan(text: '：', style: AppTypography.bodySecondary),
                TextSpan(
                  text: sample.message,
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
        color: AppColors.brand.withValues(alpha: 0.18),
        borderRadius: AppRadius.allSm,
        border: Border.all(color: AppColors.brand.withValues(alpha: 0.6)),
      ),
      child: Text(
        '粉丝 $level',
        style: const TextStyle(
          fontSize: 9,
          height: 1.1,
          color: AppColors.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FollowPanel extends StatelessWidget {
  const _FollowPanel();

  @override
  Widget build(BuildContext context) {
    return const _PanelHint(
      key: Key('play-side-follow-panel'),
      icon: Icons.star_border_rounded,
      title: '我的关注',
      text: '关注的直播间会显示在这里',
    );
  }
}

class _RecommendPanel extends StatelessWidget {
  const _RecommendPanel();

  @override
  Widget build(BuildContext context) {
    return const _PanelHint(
      key: Key('play-side-recommend-panel'),
      icon: Icons.auto_awesome_outlined,
      title: '相关推荐',
      text: '相同分类的直播间会显示在这里',
    );
  }
}

class _SettingsPanel extends StatelessWidget {
  const _SettingsPanel();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ListView(
      key: const Key('play-side-settings-panel'),
      padding: const EdgeInsets.all(AppSpacing.sm),
      children: [
        _SettingsGroup(
          title: '播放',
          children: [
            _SettingRow(
              label: '线路格式',
              trailing: DropdownButton<String>(
                value: '自动',
                isDense: true,
                underline: const SizedBox.shrink(),
                dropdownColor: tokens.surfaceRaised,
                style: TextStyle(fontSize: 11, color: tokens.textPrimary),
                items: const [
                  DropdownMenuItem(value: '自动', child: Text('自动')),
                  DropdownMenuItem(value: 'HLS', child: Text('HLS')),
                  DropdownMenuItem(value: 'FLV', child: Text('FLV')),
                ],
                onChanged: (_) {},
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
                value: true,
                onChanged: (_) {},
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            _SettingRow(
              label: '透明度',
              trailing: SizedBox(
                width: 98,
                child: Slider(
                  value: 0.82,
                  onChanged: (_) {},
                  min: 0.1,
                  max: 1,
                  activeColor: tokens.brand,
                ),
              ),
            ),
            _SettingRow(
              label: '字号',
              trailing: SizedBox(
                width: 98,
                child: Slider(
                  value: 0.35,
                  onChanged: (_) {},
                  min: 0,
                  max: 1,
                  activeColor: tokens.brand,
                ),
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
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 5),
      decoration: BoxDecoration(
        color: AppColors.surfaceSoft,
        borderRadius: AppRadius.allSm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 11,
              height: 1.2,
              color: AppColors.brand,
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
        Expanded(
          child: Text(label, style: AppTypography.caption),
        ),
        trailing,
      ],
    );
  }
}

class _PanelHint extends StatelessWidget {
  const _PanelHint({
    super.key,
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
