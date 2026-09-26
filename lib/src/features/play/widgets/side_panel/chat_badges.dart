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

/// 抖音粉丝牌官网聊天行同款图 URL(60×48 紧凑款,
/// `fansclub_new_advanced_badge_{level}_xmp.png`)。
///
/// 档位 1..20 有图(实测 2026-09-25:21+ 返回 404,上限同
/// [kDouyinFansMaxLevel]);越界返回 '' → 调用方走红色渐变圆盘文字态。
String douyinFansBadgeUrl(int level) {
  if (level <= 0 || level > kDouyinFansMaxLevel) return '';
  return 'https://p3-webcast.douyinpic.com/img/webcast/'
      'fansclub_level_v6_$level.png~tplv-obj.image';
}

/// 粉丝牌(对齐 web ChatFanBadge 各平台分支;本地图优先 → 文字态兜底):
/// - 斗鱼:官方粉丝牌 PNG(`douyu/fans/{lv}.png`,等级已绘在图内 → 不叠数字)
///   作底图、团名叠右侧；加载失败/无图回落中性深底团名胶囊；无团名不渲染。
/// - 抖音:img-only 站(web CHAT_FAN_BADGE_IMG_ONLY_SITES),有等级即整图
///   `fansclub_new_advanced_badge_{lv}_xmp.png`(官网聊天行同款 60×48 **远程**
///   图,见 [douyinFansBadgeUrl]);失败回落红色渐变圆盘文字态;
/// - 虎牙:对齐虎牙官网聊天栏的「皇冠 + 等级 + 团名」粉丝牌胶囊；
///   `vFlag > 0` 时优先显示 `vLogo`，无图/失败回落 V；
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
    this.identity = 0,
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

  /// 身份图标档位（虎牙 `tExternal.iFansIdentity`）。
  final int identity;

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

    // 抖音:img-only 站,**只用官网聊天行同款 60×48 紧凑图**
    // (`fansclub_new_advanced_badge_N_xmp`)。高度沿用 21px(与其他平台徽章
    // 一致),宽度随 60/48 原图比例 → 26px,不再有宽底长条。
    //
    // 回归:先后用过两个都不对的素材 ——
    //   - WS 协议下发的 `fansclub_level_v6_N.png`(**150×48 黄色宽底长条**,
    //     同高度下宽 65px,背景颜色远比徽章宽,用户报障「背景没那么宽」)；
    //   - 本地 `assets/badges/douyin/fans/N.png`(实为粉翼大摆台,非官网样式)。
    if (site == 'douyin') {
      const badgeHeight = 21.0;
      final officialUrl =
          remoteUrl.isNotEmpty ? remoteUrl : douyinFansBadgeUrl(level);
      if (officialUrl.isNotEmpty && !_imgFailed) {
        return ChatBadgeImage(
          site: site,
          kind: ChatBadgeKind.fans,
          level: level,
          height: badgeHeight,
          src: officialUrl,
          // 本地 `assets/badges/douyin/fans/*` 实为粉翼大摆台(非官网样式),
          // 加载失败时宁可落红色渐变圆盘,也不回退到错的画风。
          assetPathOverride: '',
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
    // 虎牙官网 333003 DOM 实测：粉丝牌 `fans-icon` 高 20，结构为
    // `[圆形等级徽记][团名][身份图标]`（`padding-left:18px` 是等级圆标区，
    // `padding-right` 等于身份图标宽 22/26/28）。
    //
    // 底图分两路（**优先官方**）：
    // 1. 房间级 `wupui/getResourceInfo` 下发的 `sFloorUrl` 模板 → 拼出官方底图，
    //    与官网像素一致（底图已含等级圆标与团名区，故只叠身份图标）。
    // 2. 取不到模板（未登录/资源请求失败/房间无定制）→ 降级为实测 7 档底色 +
    //    同构布局自绘，**不编造 CDN 路径**。
    if (site == 'huya') {
      final identity = widget.vFlag > 0 && widget.vLogo.isNotEmpty
          ? _HuyaSuperFanBadge(logo: widget.vLogo)
          : _HuyaFanIdentityIcon(level: level, identity: widget.identity);
      final tooltip = hasName ? '$name Lv.$level' : '粉丝牌 Lv.$level';
      // 官方底图 URL 已由解析侧用房间级 `sFloorUrl` 模板拼好放进
      // `DanmakuBadge.url`（底图内含等级圆标与团名留白），故这里只叠身份图标。
      // `url` 为空 = 房间级资源没取到 → 降级自绘，**不编造 CDN 路径**。
      if (remoteUrl.isNotEmpty && !_imgFailed) {
        return Tooltip(
          message: tooltip,
          child: KeyedSubtree(
            key: const Key('huya-fan-badge'),
            child: SizedBox(
              height: AppHuyaChatBadge.fanHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ChatBadgeImage(
                      site: site,
                      kind: ChatBadgeKind.fans,
                      level: level,
                      height: AppHuyaChatBadge.fanHeight,
                      src: remoteUrl,
                      useDiskCache: false,
                      onFail: _markImgFailed,
                    ),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: identity,
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return Tooltip(
        message: tooltip,
        child: KeyedSubtree(
          key: const Key('huya-fan-badge'),
          child: Container(
            height: AppHuyaChatBadge.fanHeight,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppHuyaChatBadge.fanGradient(level),
              ),
              borderRadius: BorderRadius.circular(AppHuyaChatBadge.fanHeight / 2),
            ),
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HuyaFanLevelDisc(level: level),
                if (hasName) ...[
                  const SizedBox(width: AppSpacing.xs),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 64),
                    child: Text(
                      name.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: AppFontSize.bodySecondary,
                        height: 1.1,
                        color: AppOnBright.white,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ),
                ],
                const SizedBox(width: AppSpacing.xs),
                identity,
              ],
            ),
          ),
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
    // 斗鱼:官网聊天栏为「官方粉丝牌图 + 团名」；等级已经画在图内，不再叠数字。
    // 协议图优先，失败后回落官方粉丝牌 PNG；无图时使用同尺寸中性团名胶囊。
    // 依据：斗鱼官网房间 252140 聊天栏实测截图。
    if (site == 'douyu') {
      // 斗鱼聊天行的其余 3 类徽章（至尊大钻石 / 贵族 / 超粉 / 钻粉）由解析包
      // 按官网顺序编进 [DanmakuBadge.kind]，在这里按 kind 分档渲染。
      switch (widget.kind) {
        case 'supreme':
          return _DouyuSupremeMedal(level: level);
        case 'noble':
          return _DouyuNobleChip(level: level);
        case 'superfan':
          return const _DouyuSuperFanMark();
        case 'diamondfan':
          return const _DouyuDiamondFanChip();
        default:
          break; // 空 kind = 粉丝牌，走下面的官方图分支
      }
      if (!hasName) return const SizedBox.shrink();
      if (remoteUrl.isNotEmpty && !_imgFailed) {
        return Container(
          height: AppDouyuChatBadge.fanHeight,
          constraints: const BoxConstraints(
            minWidth: AppDouyuChatBadge.fanImageWidth,
          ),
          decoration: const BoxDecoration(
            color: AppDouyuChatBadge.fanFallbackBg,
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: ChatBadgeImage(
                  site: site,
                  kind: ChatBadgeKind.fans,
                  level: level,
                  height: AppDouyuChatBadge.fanHeight,
                  src: remoteUrl,
                  useDiskCache: false,
                  onFail: _markImgFailed,
                ),
              ),
              Positioned(
                left: AppDouyuChatBadge.fanTextInset,
                right: AppSpacing.xs,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    name.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.bodySecondary,
                      height: 1.1,
                      color: resolvedTextColor,
                      fontWeight: FontWeight.w600,
                      shadows: AppDouyuChatBadge.fanTextShadow,
                    ),
                  ),
                ),
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
        // 徽章图**原样贴左**(60×19 自然尺寸,不拉伸/不裁切/不重复),容器
        // 宽度由团名文字决定;比徽章宽出来的右侧用 [fanFallbackBg] 中性深底
        // 补上,保证团名任何长度都落在底色上。
        //
        // 官网是「按团名长度渲染的整牌图」(实测宽 58/76 随团名变,团名烧在
        // 图里,DOM 零文字节点),但那张图由前端按团名 id 从 sta-op 换取,
        // **协议不下发** —— 实测 9999 房真实弹幕 stt 只有 bn/bl/bc,bimg 为
        // 空,故「等级图 + 叠文字」是必然降级。
        //
        // 踩过的坑(2026-09-26):曾用 ImageRepeat.repeatX 把 60px 图平铺填
        // 宽,结果等级徽被复制到右侧(用户报「右侧显示了重复的左侧部分」);
        // 曾用 BoxFit.stretch 铺满,则徽标横向压扁。两者都算篸改徽章,
        // 一律不用 —— 延长底色不延长徽章。
        return Container(
          height: AppDouyuChatBadge.fanHeight,
          constraints: const BoxConstraints(
            minWidth: AppDouyuChatBadge.fanImageWidth,
          ),
          decoration: const BoxDecoration(
            color: AppDouyuChatBadge.fanFallbackBg,
          ),
          child: Stack(
            children: [
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: ChatBadgeImage(
                  site: site,
                  kind: ChatBadgeKind.fans,
                  level: level,
                  height: AppDouyuChatBadge.fanHeight,
                  onFail: _markImgFailed,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(
                  left: AppDouyuChatBadge.fanTextInset,
                  right: AppSpacing.xs,
                ),
                child: Center(
                  child: Text(
                    name.trim(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppFontSize.bodySecondary,
                      height: 1.1,
                      color: resolvedTextColor,
                      fontWeight: FontWeight.w600,
                      shadows: AppDouyuChatBadge.fanTextShadow,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }
      return _BadgeBox(
        height: AppDouyuChatBadge.fanHeight,
        minWidth: AppDouyuChatBadge.fanImageWidth,
        radius: AppRadius.pill,
        color: AppDouyuChatBadge.fanFallbackBg,
        child: Text(
          name.trim(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: AppFontSize.bodySecondary,
            height: 1.1,
            color: AppOnBright.white,
            fontWeight: FontWeight.w600,
            shadows: AppDouyuChatBadge.fanTextShadow,
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

/// 斗鱼至尊大钻石徽章（官网 lit 组件 `dy-supreme-medal`）。
///
/// **降级占位**：官网图标由 `getDiamondIconExt({diafid})` 拼 URL，该 URL 模板
/// 本轮**未取到**（只确证了 `sl`/`sid`/`diafid` 三个字段），因此这里
/// **不构造任何 CDN 路径**，只用协议等级数字占位：等大圆角方块 + 数字，
/// 几何对齐官网 `:host` 实测的 28×28。拿到官方 URL 规则后改远程图即可。
class _DouyuSupremeMedal extends StatelessWidget {
  const _DouyuSupremeMedal({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: '至尊大钻石 Lv.$level',
      child: Container(
        key: const Key('douyu-supreme-medal'),
        width: AppDouyuChatBadge.supremeSide,
        height: AppDouyuChatBadge.supremeSide,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.surfaceRaised,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: tokens.border),
        ),
        child: Text(
          '$level',
          style: TextStyle(
            fontSize: AppFontSize.title,
            height: 1.1,
            color: tokens.textPrimary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// 斗鱼贵族徽章（官网 lit 组件 `dy-noble-level`，字段 `ne`）。
///
/// **降级占位**：官网图标取 `resource/noble/global/web.json` 的
/// `all_level_list[level].icons.web_symbol_picN`，而图里的 host 字段需要一次
/// 额外网络请求才能拿到（JSON 本体 URL 与 host 均未确证），本轮不请求，
/// **不拼任何 CDN 路径**，只渲染「贵族 N」文字胶囊。`ne` 的真实取值也未采到，
/// 故不对等级区间做任何分档假设。
class _DouyuNobleChip extends StatelessWidget {
  const _DouyuNobleChip({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: '贵族 Lv.$level',
      child: _BadgeBox(
        key: const Key('douyu-noble-chip'),
        height: AppDouyuChatBadge.levelHeight,
        minWidth: AppDouyuChatBadge.levelHeight,
        radius: AppRadius.pill,
        color: tokens.surfaceRaised,
        border: tokens.border,
        child: Text(
          '贵族 $level',
          style: TextStyle(
            fontSize: AppFontSize.overline,
            height: 1.1,
            color: tokens.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 斗鱼超粉标记（字段 `sahf`，官网 `getIsShowSuperIcon`）。
///
/// 官网是「超粉」图标图，URL 未确证 → 降级为金色 V 字（与虎牙超粉 V 同语义，
/// 但不复用虎牙那个私有类：它在同一个 part 文件里，语义属虎牙粉丝牌内部位）。
class _DouyuSuperFanMark extends StatelessWidget {
  const _DouyuSuperFanMark();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '超粉',
      child: Text(
        'V',
        key: const Key('douyu-superfan-mark'),
        style: TextStyle(
          fontSize: AppFontSize.caption,
          height: 1,
          fontWeight: FontWeight.w900,
          fontStyle: FontStyle.italic,
          color: context.tokens.chatSuperFan,
        ),
      ),
    );
  }
}

/// 斗鱼钻粉标记（字段 `diaf` / `cdiaf`）。
///
/// **降级占位**：官网钻粉是图标（`diafid` + `getDiamondIconExt`），URL 规则
/// 未确证 → 只渲染「钻粉」文字 chip，不拼任何 CDN 路径。
class _DouyuDiamondFanChip extends StatelessWidget {
  const _DouyuDiamondFanChip();

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Tooltip(
      message: '钻粉',
      child: _BadgeBox(
        key: const Key('douyu-diamondfan-chip'),
        height: AppDouyuChatBadge.levelHeight,
        minWidth: AppDouyuChatBadge.levelHeight,
        radius: AppRadius.pill,
        color: tokens.surfaceRaised,
        border: tokens.border,
        child: Text(
          '钻粉',
          style: TextStyle(
            fontSize: AppFontSize.overline,
            height: 1.1,
            color: tokens.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// 用户等级徽章(各平台按官网形态渲染):
/// - 虎牙:对齐虎牙官网 333003 聊天栏的纯数字小圆角胶囊；贵族/VIP emblem
///   与平台等级是两种身份，不再把 `vip/v2` 图片冒充平台等级；
/// - 抖音:honor 荣誉图 `douyin/honor/{lv}.png`(≤75;图内含数字不叠文字);
///   失败/超档回落紫粉渐变数字;
/// - 斗鱼:纯数字等级胶囊，按官网低/中/高档使用绿/蓝/橙红配色；
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
    final localPath = badgeAssetPath(
      site: site,
      kind: ChatBadgeKind.userLevel,
      level: level,
    );
    // 虎牙平台等级：直接用**官方 CDN 图**，不做任何自绘。
    //
    // 官网 `components/ConsumeLevelBadge/index.tsx` 逻辑：
    //   variant = iBadgeStyle == E_STYLE_NORMAL ? tier(level) : "hide"
    //   tone    = iIsPolished == 1 ? "light" : "gray"
    //   url     = https://diy-assets.msstatic.com/consumeLevelBadgeV2/{variant}/{tone}.png
    // 图为 90×40 的 @2x 素材（等效 45×20），左侧菱形已绘在图内，
    // 右侧留白由官网的 `<span>` 叠 12px/700 白字——下方同样叠字。
    if (site == 'huya') {
      final url = huyaConsumeLevelBadgeUrl(
        level: level,
        badgeStyle: widget.badgeStyle,
        isPolished: widget.isPolished,
      );
      if (url.isEmpty) {
        return const SizedBox.shrink();
      }
      // 官方图加载失败：官网此时 src 为空串（实际会留一个破图位）。
      // 【有意偏离】本实现降级为同尺寸纯数字胶囊，而不是留 45x20 幽灵空位
      // 或直接吞掉等级——聊天流里每行一个空洞比降级更糟。
      if (_imgFailed) {
        return KeyedSubtree(
          key: const Key('huya-user-level-fallback'),
          child: _BadgeBox(
            height: kHuyaConsumeLevelBadgeHeight,
            minWidth: kHuyaConsumeLevelBadgeWidth,
            radius: AppRadius.pill,
            color: context.tokens.surfaceRaised,
            child: Text(
              '$level',
              style: const TextStyle(
                fontSize: AppFontSize.bodySecondary,
                height: 1.1,
                color: AppOnBright.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        );
      }
      return KeyedSubtree(
        key: const Key('huya-user-level-pill'),
        child: SizedBox(
          height: kHuyaConsumeLevelBadgeHeight,
          width: kHuyaConsumeLevelBadgeWidth,
          child: Stack(
            children: [
              Positioned.fill(
                child: ChatBadgeImage(
                  site: site,
                  kind: ChatBadgeKind.userLevel,
                  level: level,
                  height: kHuyaConsumeLevelBadgeHeight,
                  src: url,
                  assetPathOverride: '',
                  useDiskCache: false,
                  onFail: _markImgFailed,
                ),
              ),
              // 官网 `<span>` 的 padding-left:20px 即左侧菱形区宽度。
              Positioned(
                left: AppHuyaChatBadge.levelEmblem,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Text(
                    '$level',
                    style: const TextStyle(
                      fontSize: AppFontSize.bodySecondary,
                      height: 1.1,
                      color: AppOnBright.white,
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
    // 斗鱼官网 252140 逐像素实测：LV 是 `[小徽标][数字]` 全圆角胶囊 32×16，
    // 水平渐变分 5 档（<15 米金 / 15–29 绿 / 30–39 蓝 / 40–49 靛 / ≥50 紫）。
    // 协议里的 iconUrl 不能把它变成图片。
    if (site == 'douyu') {
      final emblemSide = AppDouyuChatBadge.levelEmblem - AppSpacing.xs;
      return KeyedSubtree(
        key: const Key('douyu-user-level-pill'),
        child: Container(
          height: AppDouyuChatBadge.levelHeight,
          width: AppDouyuChatBadge.levelWidth,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: AppDouyuChatBadge.levelGradient(level),
            ),
            borderRadius: BorderRadius.circular(AppDouyuChatBadge.levelRadius),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // 官网 LV 胶囊左侧的小徽标(canvas 绘制)；用同尺寸浅色圆点占位。
              Container(
                width: emblemSide,
                height: emblemSide,
                margin: const EdgeInsets.only(right: AppSpacing.xs),
                decoration: BoxDecoration(
                  color: AppOnBright.white.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(emblemSide / 2),
                ),
              ),
              Text(
                '$level',
                style: const TextStyle(
                  fontSize: AppFontSize.overline,
                  height: 1.1,
                  color: AppOnBright.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 有本地固定素材时第一帧直接显示本地图,避免远程图加载前后跳变;
    // 只有本地没有素材的平台才直接走协议图。
    if (remoteUrl.isNotEmpty && !_imgFailed && localPath.isEmpty) {
      final image = ChatBadgeImage(
        site: site,
        kind: ChatBadgeKind.userLevel,
        level: level,
        height: 21,
        src: remoteUrl,
        onFail: _markImgFailed,
      );
      return image;
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
        height: 21,
        onFail: _markImgFailed,
      );
    }
    // 斗鱼已在上面按官网数字胶囊提前返回；B站/其他/图片兜底沿用既有文字态。
    List<Color> colors;
    var label = '';
    if (site == 'bilibili') {
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

/// 虎牙粉丝牌胶囊左侧的圆形等级徽记。
///
/// 官网 `fans-icon` 的 `padding-left:18px` 区域就是这枚圆标（等级数字绘在
/// 官方底图里）；底图不可得时用同尺寸圆形 + 数字复刻。
class _HuyaFanLevelDisc extends StatelessWidget {
  const _HuyaFanLevelDisc({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppHuyaChatBadge.fanLevelDisc,
      height: AppHuyaChatBadge.fanLevelDisc,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppOnBright.white.withValues(alpha: 0.28),
        shape: BoxShape.circle,
      ),
      child: Text(
        '$level',
        style: const TextStyle(
          fontSize: AppFontSize.overline,
          height: 1.1,
          color: AppOnBright.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 虎牙粉丝牌尾部的身份图标（官网 `fans-icon-sf`，对应 `3_0_{identity}.png`）。
///
/// 协议 `vFlag>0` 时优先用 `vLogo` 远程图（见 [_HuyaSuperFanBadge]）；否则按
/// 粉丝牌等级映射到本地 `assets/badges/huya/vip/v2/{identity}.png`
/// （identity 1 = 金色 V，12/13 = 守盾）。本地素材与官网 `3_0_{identity}.png`
/// 尺寸一致（78×60 / 84×60 → 按高 20 缩放得官方 26 / 28 宽）。
class _HuyaFanIdentityIcon extends StatelessWidget {
  const _HuyaFanIdentityIcon({required this.level, this.identity = 0});

  final int level;

  /// 协议下发的身份档位（`tExternal.iFansIdentity`）；0 时按等级回落。
  final int identity;

  @override
  Widget build(BuildContext context) {
    // 官方身份图标 URL：`.../fansBadge/3/v2/{identity}.png`（实测 7 档全 200）。
    // 协议未下发 `iFansIdentity` 时按等级回落（见 `huyaFansIdentityFallback`）；
    // 官网真实语义由粉丝团配置决定、与等级非单调，故仅作兜底。
    final id = identity > 0 ? identity : huyaFansIdentityFallback(level);
    if (id <= 0) return const SizedBox.shrink();
    return SizedBox(
      key: const Key('huya-fan-identity-icon'),
      height: AppHuyaChatBadge.fanHeight,
      child: Image.network(
        huyaFansIdentityUrl(id),
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) => const SizedBox.shrink(),
      ),
    );
  }
}

/// 虎牙超粉标记：官网粉丝牌胶囊内的皇冠位，优先 `vLogo`，失败回落 V。
class _HuyaSuperFanBadge extends StatelessWidget {
  const _HuyaSuperFanBadge({required this.logo});

  final String logo;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      key: const Key('huya-fan-v-mark'),
      message: '超粉',
      child: logo.isEmpty
          ? _fallbackMark(context)
          : ColorFiltered(
              colorFilter: chatWebImageFilter,
              child: CachedNetworkImage(
                imageUrl: logo,
                cacheKey: logo,
                width: AppFontSize.caption,
                height: AppFontSize.caption,
                fit: BoxFit.contain,
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => _fallbackMark(context),
              ),
            ),
    );
  }

  Widget _fallbackMark(BuildContext context) => Text(
    'V',
    style: TextStyle(
      fontSize: AppFontSize.label,
      height: 1,
      fontWeight: FontWeight.w900,
      fontStyle: FontStyle.italic,
      color: context.tokens.chatSuperFan,
    ),
  );
}

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
    super.key,
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
