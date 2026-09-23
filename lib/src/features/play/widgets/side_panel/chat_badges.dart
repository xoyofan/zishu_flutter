part of '../play_side_panel.dart';

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

String _soopSubscriberAsset(int months) {
  final name = months >= 24
      ? 'subscriber_24mo.png'
      : months >= 12
      ? 'subscriber_12mo.png'
      : months >= 6
      ? 'subscriber_6mo.png'
      : 'subscriber_basic.png';
  return 'assets/badges/soop/$name';
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
    this.kind = '',
    this.url = '',
    this.iconUrl = '',
    this.vFlag = 0,
    this.vLogo = '',
    this.color = 0,
    this.colorStart = 0,
    this.colorEnd = 0,
    this.colorBorder = 0,
    this.textColor = 0,
    this.levelColor = 0,
  });

  final String site;
  final int level;
  final String? name;
  final String kind;
  final String url;
  final String iconUrl;
  final int vFlag;
  final String vLogo;
  final int color;
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
        oldWidget.name != widget.name ||
        oldWidget.kind != widget.kind ||
        oldWidget.url != widget.url ||
        oldWidget.iconUrl != widget.iconUrl ||
        oldWidget.vFlag != widget.vFlag ||
        oldWidget.vLogo != widget.vLogo) {
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
    final remoteUrl = widget.iconUrl.isNotEmpty ? widget.iconUrl : widget.url;
    // web 斗鱼/B站文字态无梯度兜底:中性深底白字(web 无协议图/色时走
    // 官方图片牌,flutter 无图 → 深底占位保持可读)。
    const neutralBg = Color(0xff3a3a3a);
    final resolvedTextColor = textColor != 0 ? Color(textColor) : Colors.white;
    final resolvedLevelColor = levelColor != 0
        ? Color(levelColor)
        : resolvedTextColor;

    // SOOP:订阅牌优先使用主播自定义头像/本地分档图；管理员、铁粉、粉丝团
    // 是协议位域解析出的文字色块，与 Web 的 0005 徽章顺序一致。
    if (site == 'soop') {
      if (widget.kind == 'subscriber') {
        const size = 18.0;
        final asset = _soopSubscriberAsset(level);
        final image = widget.url.isNotEmpty
            ? Image.network(
                widget.url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Image.asset(
                  asset,
                  width: size,
                  height: size,
                  fit: BoxFit.cover,
                ),
              )
            : Image.asset(asset, width: size, height: size, fit: BoxFit.cover);
        return Padding(
          padding: const EdgeInsets.only(right: 2),
          child: Tooltip(
            message: '订阅 $level 个月',
            child: SizedBox(
              height: size,
              width: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: ClipOval(child: image),
                  ),
                  Positioned(
                    right: -7,
                    bottom: -5,
                    child: Text(
                      '$level',
                      style: const TextStyle(
                        fontSize: 8,
                        height: 1,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        shadows: [Shadow(color: Colors.black87, blurRadius: 1.5)],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      final shortLabel = switch (widget.kind) {
        'manager' => 'M',
        'topfan' => 'T',
        'fanclub' => 'F',
        _ => name?.trim().isNotEmpty == true ? name!.trim() : '',
      };
      final tooltip = switch (widget.kind) {
        'manager' => '管理员',
        'topfan' => '铁粉',
        'fanclub' => '粉丝团',
        _ => shortLabel,
      };
      if (shortLabel.isEmpty) return const SizedBox.shrink();
      return Tooltip(
        message: tooltip,
        child: _BadgeBox(
          height: 18,
          minWidth: 18,
          radius: 3,
          color: widget.color == 0
              ? const Color(0xff6b7280)
              : Color(0xff000000 | (widget.color & 0xffffff)),
          child: Text(
            shortLabel,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1,
              color: Colors.white,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    // 抖音:协议图优先,有等级再回落官方整图/红色渐变圆盘文字态。
    // 圆盘尺寸对齐 web douyinTextFallback(14px 基):min 1.4em=19.6、字 0.78em≈11。
    if (site == 'douyin') {
      if (remoteUrl.isNotEmpty && !_imgFailed) {
        return ChatBadgeImage(
          site: site,
          kind: ChatBadgeKind.fans,
          level: level,
          height: 21,
          src: remoteUrl,
          onFail: _markImgFailed,
        );
      }
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
            fontSize: AppFontSize.caption,
            height: 1.1,
            color: Colors.white,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
    }
    // 虎牙:房间定制图优先,失败后回落 7 档渐变条 + 等级圆盘 + 团名。
    // vFlag>0 时按 Web ChatHuyaSuperFanBadge 追加 V/vLogo。
    // 尺寸对齐 web huyaComposed(14px 基):条 1.15em≈16、圆盘 1.05em×0.67em≈10、
    // 圆盘字 0.67em≈9.4、团名 0.79em≈11。
    if (site == 'huya') {
      if (remoteUrl.isNotEmpty && !_imgFailed) {
        return Tooltip(
          message: hasName ? '$name Lv.$level' : '粉丝牌 Lv.$level',
          child: SizedBox(
            height: 16,
            child: Stack(
              children: [
                Positioned.fill(
                  child: ChatBadgeImage(
                    site: site,
                    kind: ChatBadgeKind.fans,
                    level: level,
                    height: 16,
                    src: remoteUrl,
                    onFail: _markImgFailed,
                  ),
                ),
                if (hasName)
                  Positioned(
                    left: 5,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Text(
                        name.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppFontSize.caption,
                          height: 1.1,
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      }
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
                  fontSize: AppFontSize.overline,
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
                  fontSize: AppFontSize.caption,
                  height: 1.1,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            if (widget.vFlag > 0) ...[
              const SizedBox(width: 2),
              Tooltip(
                message: '超粉',
                child: widget.vLogo.isNotEmpty
                    ? ColorFiltered(
                        colorFilter: chatWebImageFilter,
                        child: Image.network(
                          widget.vLogo,
                          width: 14,
                          height: 14,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const _HuyaSuperFanMark(),
                        ),
                      )
                    : const _HuyaSuperFanMark(),
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
                  fontSize: AppFontSize.body,
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
              fontSize: AppFontSize.body,
              height: 1.1,
              color: resolvedLevelColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
      if (!hasProtocolColor && !_imgFailed) {
        return Tooltip(
          message: hasName ? '$name Lv.$level' : '粉丝团 Lv.$level',
          child: ClipRRect(
            borderRadius: const BorderRadius.all(Radius.circular(999)),
            child: Container(
              height: 21, // web bilibiliComposed/官方边框牌 1.48em ≈ 20.7
              constraints: const BoxConstraints(minWidth: 49), // 3.5em
              decoration: const BoxDecoration(),
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
                        assetPathOverride: bilibiliMedalFrameAssetPath(),
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
            ),
          ),
        );
      }
      return Tooltip(
        message: hasName ? '$name Lv.$level' : '粉丝团 Lv.$level',
        child: _BadgeBox(
          height: 21,
          radius: 999,
          gradient: hasProtocolColor ? [Color(start), Color(end)] : null,
          color: hasProtocolColor ? null : neutralBg,
          // web `linear-gradient(to left, start, end)`:start 在右、end 在左。
          gradientBegin: Alignment.centerRight,
          gradientEnd: Alignment.centerLeft,
          border: colorBorder != 0 ? Color(colorBorder) : null,
          child: content,
        ),
      );
    }
    // 斗鱼:协议图优先,再回落官方粉丝牌 PNG;团名叠右侧,等级已绘在图内。
    // 失败回落中性深底团名胶囊;无团名则无可显示内容 → 不渲染。
    if (site == 'douyu') {
      if (!hasName) return const SizedBox.shrink();
      if (remoteUrl.isNotEmpty && !_imgFailed) {
        return Container(
          height: 18,
          constraints: const BoxConstraints(minWidth: 57),
          child: Stack(
            children: [
              Positioned.fill(
                child: ChatBadgeImage(
                  site: site,
                  kind: ChatBadgeKind.fans,
                  level: level,
                  height: 18,
                  src: remoteUrl,
                  onFail: _markImgFailed,
                ),
              ),
              Positioned(
                left: 22,
                top: 0,
                bottom: 0,
                child: Center(child: Text(name.trim())),
              ),
            ],
          ),
        );
      }
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
                      fontSize: AppFontSize.caption, // web 0.78em
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
            fontSize: AppFontSize.overline,
            height: 1.1,
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    // 其他平台:协议图优先;没有真实图才走中性文字胶囊。
    if (remoteUrl.isNotEmpty && !_imgFailed) {
      return ChatBadgeImage(
        site: site,
        kind: ChatBadgeKind.fans,
        level: level,
        height: site == 'twitch' ? 18 : 15,
        src: remoteUrl,
        onFail: _markImgFailed,
      );
    }
    return _BadgeBox(
      height: 15,
      radius: 999,
      color: tokens.brand.withValues(alpha: 0.18),
      border: tokens.brand.withValues(alpha: 0.6),
      child: Text(
        label(site, name, hasName, level),
        style: TextStyle(
          fontSize: AppFontSize.overline,
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
  const _UserLevelBadge({
    required this.site,
    required this.level,
    this.iconUrl = '',
    this.badgeStyle = 0,
    this.isPolished = 0,
    this.color = 0,
  });

  final String site;
  final int level;
  final String iconUrl;
  final int badgeStyle;
  final int isPolished;
  final int color;

  @override
  State<_UserLevelBadge> createState() => _UserLevelBadgeState();
}

class _UserLevelBadgeState extends State<_UserLevelBadge> {
  /// 本地图加载失败/缺失:回落文字态(输入变化后重置重试)。
  bool _imgFailed = false;

  @override
  void didUpdateWidget(covariant _UserLevelBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.site != widget.site ||
        oldWidget.level != widget.level ||
        oldWidget.iconUrl != widget.iconUrl ||
        oldWidget.badgeStyle != widget.badgeStyle ||
        oldWidget.isPolished != widget.isPolished ||
        oldWidget.color != widget.color) {
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
    final remoteUrl = widget.iconUrl;
    // 协议/平台直接提供的等级图优先,失败后走本地 emblem/文字回退。
    if (remoteUrl.isNotEmpty && !_imgFailed) {
      final image = ChatBadgeImage(
        site: site,
        kind: ChatBadgeKind.userLevel,
        level: level,
        height: 21,
        src: remoteUrl,
        onFail: _markImgFailed,
      );
      if (site == 'huya') {
        return Container(
          height: 21,
          constraints: const BoxConstraints(minWidth: 29),
          child: Stack(
            children: [
              Positioned.fill(child: image),
              Positioned(
                right: 1.7,
                bottom: 0.8,
                child: Text(
                  '$level',
                  style: const TextStyle(
                    fontSize: AppFontSize.overline,
                    height: 1,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    shadows: [Shadow(color: Color(0x8c000000), blurRadius: 2)],
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return image;
    }
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
                  fontSize: AppFontSize.overline,
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
      color: widget.color != 0
          ? Color(0xff000000 | (widget.color & 0xffffff))
          : (colors.length == 1 ? colors.first : null),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: AppFontSize.overline,
          height: 1.1,
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _HuyaSuperFanMark extends StatelessWidget {
  const _HuyaSuperFanMark();

  @override
  Widget build(BuildContext context) => Text(
    'V',
    style: TextStyle(
      fontSize: AppFontSize.overline,
      height: 1,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      color: context.tokens.chatSuperFan,
    ),
  );
}

/// B站大航海独立身份徽章,按 Web SideChatTab 的小号描边 chip 渲染。
class _GuardBadge extends StatelessWidget {
  const _GuardBadge({required this.badge});

  final DanmakuBadge badge;

  @override
  Widget build(BuildContext context) {
    final color = badge.color == 0
        ? context.tokens.textSecondary
        : Color(0xff000000 | (badge.color & 0xffffff));
    return Tooltip(
      message: badge.name,
      child: Container(
        constraints: const BoxConstraints(minWidth: 18),
        padding: const EdgeInsets.symmetric(horizontal: 3),
        decoration: BoxDecoration(
          border: Border.all(color: color),
          borderRadius: AppRadius.allSm,
        ),
        child: Text(
          badge.name,
          style: TextStyle(
            fontSize: AppFontSize.overline,
            height: 1.1,
            color: color,
            fontWeight: FontWeight.w600,
          ),
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
