# -*- coding: utf-8 -*-
"""播放页侧栏 5 项 UI 调整(用户口径 2026-09-20),一次性补丁脚本。"""
import io


def patch(path, pairs):
    s = io.open(path, encoding="utf-8").read()
    for old, new in pairs:
        n = s.count(old)
        assert n == 1, (path, repr(old[:60]), "count=", n)
        s = s.replace(old, new)
    io.open(path, "w", encoding="utf-8", newline="").write(s)
    print("ok", path)


# ── 1. 播放页左上角分类徽标:字号 11→12.5、行内垂直居中 ──
patch("lib/src/features/play/views/play_view.dart", [
    ("""                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),""",
     """                  return Container(
                    // 用户口径(2026-09-20):分类名文字更大、行内上下居中。
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 3,
                    ),"""),
    ("                        PlatformIcon(id: site, size: 12),",
     "                        PlatformIcon(id: site, size: 13),"),
    ("""                        Text(
                          categoryLabel.isNotEmpty ? categoryLabel : '直播',
                          style: context.textCaption.copyWith(
                            color: badgeFg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),""",
     """                        Text(
                          categoryLabel.isNotEmpty ? categoryLabel : '直播',
                          style: context.textBody.copyWith(
                            fontSize: 12.5,
                            height: 1,
                            color: badgeFg,
                            fontWeight: FontWeight.w600,
                          ),
                        ),"""),
    ("""                          child: Icon(
                            favorited
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 12,""",
     """                          child: Icon(
                            favorited
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 13,"""),
])

# ── 2/3. 侧栏头:关注数超万→XX万;铃铛/外链钮移到第二排分类名后 ──
patch("lib/src/features/play/widgets/play_side_panel.dart", [
    ("""    final followRoom = this.followRoom;
    final followersText = _statText(followRoom?.followers);""",
     """    final followRoom = this.followRoom;
    final followersText = _formatFollowersText(followRoom?.followers);"""),
    ("""/// 统计文本:空串(未关注/上游未提供)显示「—」占位,不伪造。
String _statText(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? '—' : text;
}""",
     """/// 统计文本:空串(未关注/上游未提供)显示「—」占位,不伪造。
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
}"""),
    ("""          _SideAvatar(
            avatar: avatar,
            label: anchor,
            live: isLive,
            followed: followed,
            remindOn: remindOn,
            externalUrl: externalUrl,
            onToggleRemind: onToggleRemind,
            onOpenExternal: onOpenExternal,
          ),""",
     """          _SideAvatar(avatar: avatar, label: anchor, live: isLive),"""),
    ("""                Row(
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
                  ],
                ),""",
     """                Row(
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
                    // 第二排分类名后,不再遮头像)。
                    const SizedBox(width: 4),
                    _HeaderIconButton(
                      key: const Key('play-side-notify'),
                      size: 16,
                      icon: remindOn
                          ? Icons.notifications_rounded
                          : Icons.notifications_off_rounded,
                      tooltip: followed
                          ? (remindOn ? '已开启开播/下播提醒，点击关闭' : '开启开播/下播提醒')
                          : '关注后可开启开播提醒',
                      onPressed: followed ? onToggleRemind : null,
                      activeColor: remindOn ? tokens.accent : null,
                    ),
                    const SizedBox(width: 3),
                    _HeaderIconButton(
                      key: const Key('play-side-external'),
                      size: 16,
                      icon: Icons.open_in_new_rounded,
                      tooltip: '打开直播间页面',
                      onPressed: externalUrl == null
                          ? null
                          : () => onOpenExternal(externalUrl!),
                      accent: const Color(0xFF60A5FA),
                    ),
                  ],
                ),"""),
    ("""class _SideAvatar extends StatelessWidget {
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
""",
     """class _SideAvatar extends StatelessWidget {
  const _SideAvatar({
    required this.avatar,
    required this.label,
    required this.live,
  });

  final String avatar;
  final String label;
  final bool live;
"""),
    ("""          Positioned(
            right: -4,
            top: -4,
            child: _HeaderIconButton(
              key: const Key('play-side-notify'),
              // web bell/bell-off 两态(SideHeader.vue:27):关=bell-off
              // 中性色;开=bell + 品牌紫激活色(语义=开播/下播提醒开关)。
              icon: remindOn
                  ? Icons.notifications_rounded
                  : Icons.notifications_off_rounded,
              tooltip: followed
                  ? (remindOn ? '已开启开播/下播提醒，点击关闭' : '开启开播/下播提醒')
                  : '关注后可开启开播提醒',
              // 未关注 = 无可提醒目标,禁用(web 直接隐藏,flutter 留占位)。
              onPressed: followed ? onToggleRemind : null,
              activeColor: remindOn ? context.tokens.accent : null,
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
}""",
     """        ],
      ),
    );
  }
}"""),
    ("""  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent,
    this.activeColor,
  });

  final IconData icon;
  final String tooltip;""",
     """  const _HeaderIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.accent,
    this.activeColor,
    this.size = 19,
  });

  /// 圆钮边长(默认 19;侧栏头分类行内用 16 紧凑版)。
  final double size;
  final IconData icon;
  final String tooltip;"""),
    ("""          child: SizedBox(
            width: 19,
            height: 19,
            child: Icon(
              icon,
              size: 11,""",
     """          child: SizedBox(
            width: size,
            height: size,
            child: Icon(
              icon,
              size: size - 8,"""),
    # ── 4. 视图切换 icon:换更成对的一组、更大、少 padding ──
    ("""                constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
                icon: Icon(
                  _grid ? Icons.list_rounded : Icons.grid_view_rounded,
                  size: 15,
                  color: _grid ? tokens.textSecondary : tokens.accent,
                ),""",
     """                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                icon: Icon(
                  // 卡片态显示「列表」入口、列表态显示「网格」入口(点击即切)。
                  _grid ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 18,
                  color: _grid ? tokens.textSecondary : tokens.accent,
                ),"""),
])

# ── 5. 列表行文字左 padding 4→1 ──
patch("lib/src/features/play/widgets/play_room_grid.dart", [
    ("padding: const EdgeInsets.fromLTRB(4, 3, 4, 2),",
     "// 用户口径(2026-09-20):列表模式文字左侧 padding 收窄,行内容更贴分类条纹。\n"
     "                padding: const EdgeInsets.fromLTRB(1, 3, 3, 2),"),
])
print("ALL DONE")
