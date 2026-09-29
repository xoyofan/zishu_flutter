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

/// 抖音粉丝团徽章**彩色化**:协议常下发未点亮的灰图,换回同尺寸彩色款。
///
/// 口径抄 web `apps/web/src/utils/badges/fanBadges/douyin.ts` 的
/// `resolveDouyinColoredFansBadgeUrl`:
/// - `pop_gray_super_badge` → `pop_super_badge`(实测两者同为 60×48,仅颜色差异,
///   2026-09-26 实测真实弹幕 513 条里 152 条是灰图、361 条是彩色 —— 不换则
///   近三成徽章显示为灰色);
/// - 其余灰图(`advanced_gray` 等)→ 官方紧凑款 `pop_super_badge_{lv}`
///   (2026-09-27 用户口径:三模板统一最右紧凑款,不再用 new_badge 中等款);
/// - **官方模板族的彩色宽图**(`fansclub_level_v6` 150×48 / `fansclub_new_badge`
///   90×48 等)也统一紧凑款(2026-09-29 用户口径,官方实际渲染对比:宽图
///   被原样渲染成 65.6px 长条,即「粉丝团背景太宽」的根因);level 越界
///   (>20,紧凑款 CDN 404)保留协议原图。
/// 其余 URL 原样返回(真·主播定制款,非模板域)。
String douyinFansColoredBadgeUrl(String url, int level) {
  final text = url.trim();
  if (text.isEmpty) return '';
  if (RegExp(r'pop_gray_super_badge', caseSensitive: false).hasMatch(text)) {
    return text.replaceAll(
      RegExp(r'pop_gray_super_badge', caseSensitive: false),
      'pop_super_badge',
    );
  }
  if (_douyinGrayBadgePattern.hasMatch(text) && level > 0) {
    return douyinFansBadgeUrl(level);
  }
  // 已是紧凑款(非 gray 的 pop_super)不重复改写;模板域内的彩色宽图换紧凑。
  if (level > 0 &&
      _isDouyinFansClubTemplateUrl(text) &&
      !_douyinCompactBadgePattern.hasMatch(text)) {
    final compact = douyinFansBadgeUrl(level);
    if (compact.isNotEmpty) return compact;
  }
  return text;
}

final RegExp _douyinGrayBadgePattern = RegExp(
  r'advanced_gray|pop_gray_super_badge',
  caseSensitive: false,
);

/// 已是紧凑款模板(60×48)的命名特征。
final RegExp _douyinCompactBadgePattern = RegExp(
  r'pop_super_badge',
  caseSensitive: false,
);

/// 官方粉丝团模板域(对齐 web `isDouyinFansClubBgUrl`):URL 命名含
/// fansclub / fans_club 即模板族;域外的才是主播定制款。
bool _isDouyinFansClubTemplateUrl(String url) {
  final text = url.toLowerCase();
  return text.contains('fansclub') || text.contains('fans_club');
}

/// 抖音粉丝牌官方 CDN 兜底图 URL。
///
/// 2026-09-27 用户口径(dyx-compare.png 三模板实测对比):同一等级抖音官方
/// CDN 有**三种宽度**的牌——`fansclub_level_v6`(150×48 → 高 21 时 65.6px
/// 长条)、`fansclub_new_badge`(90×48 → 39.4px 中等)、
/// `ranklist_fansclub_pop_super_badge`(60×48 → 26.2px 紧凑款)。抖音聊天间
/// 实际展示的是**最右的紧凑款**(协议主流图即 pop_super,CDN 实测 1..20 全
/// 200、21+ 404)。此前兜底/灰图换彩用 new_badge,同一房间出现 39.4 与
/// 26.2 两种宽度 —— 统一改用 pop_super 模板。
///
/// 档位 1..20 有图;越界返回 '' → 调用方走红色渐变圆盘文字态。
String douyinFansBadgeUrl(int level) {
  if (level <= 0 || level > kDouyinFansMaxLevel) return '';
  return 'https://p3-webcast.douyinpic.com/img/webcast/'
      'ranklist_fansclub_pop_super_badge_$level'
      '.png~tplv-obj.image';
}

/// 粉丝牌(对齐 web ChatFanBadge 各平台分支;本地图优先 → 文字态兜底):
/// - 斗鱼:官方粉丝牌 PNG(`douyu/fans/{lv}.png`,等级已绘在图内 → 不叠数字)
///   作底图、团名叠右侧；加载失败/无图回落中性深底团名胶囊；无团名不渲染。
/// - 抖音:img-only 站(web `CHAT_FAN_BADGE_IMG_ONLY_SITES`),**协议图优先
///   (先灰图换彩色)**,无协议图/灰图换彩统一回落官方紧凑款
///   `pop_super_badge` CDN;失败回落红色渐变圆盘文字态;见
///   [douyinFansColoredBadgeUrl] 与 [douyinFansBadgeUrl];
/// - 虎牙:web `.chat-fan-badge--huya-composed` —— 「圆标 + 团名」**2px 圆角**
///   胶囊（高 `1.15em`、最小宽 `3.4em`），尾部再挂官网身份图标
///   （`vFlag > 0` 时优先 `vLogo`，无图/失败回落 V）；
/// - B 站:有协议渐变色 → `.chat-fan-badge--bilibili-composed`
///   （高 `1.48em`、最小宽 `3.5em`、左右 `.5em`）；无协议色 → 官方边框图
///   `medal-frame.png` + 文字叠层（web `resolveBilibiliBadgeBgUrl`，走
///   `.chat-fan-badge--has-bg` 的 `1.28em`/`3.2em` 口径）；消费协议
///   文字色/等级数字色(0 = 回落白/文字色)；
/// - 其他:协议图优先；无图回落品牌色 pill（Twitch/YY 是纯图标站，高 `1.15em`）。
class _FanBadge extends StatefulWidget {
  const _FanBadge({
    required this.site,
    required this.level,
    this.name,
    this.kind = '',
    this.url = '',
    this.iconUrl = '',
    this.levelUrl = '',
    this.vFlag = 0,
    this.vLogo = '',
    this.identity = 0,
    this.color = 0,
    this.colorStart = 0,
    this.colorEnd = 0,
    this.colorBorder = 0,
    this.textColor = 0,
    this.levelColor = 0,
    this.brid = 0,
    this.custom = false,
    this.months = 0,
    this.diafid = 0,
  });

  final String site;
  final int level;
  final String? name;
  final String kind;
  final String url;
  final String iconUrl;

  /// 虎牙定制牌独立等级数字图(`AppLevel <ua>_<level>.png`)。
  final String levelUrl;
  final int vFlag;
  final String vLogo;

  /// 粉丝牌所属房间号（斗鱼协议 `brid`，房间自定义前缀图的匹配键）。
  final int brid;

  /// 虎牙 `iCustomBadgeFlag == 1`:定制粉丝牌(NewFloor 空底框 + 等级图)。
  final bool custom;

  /// 斗鱼钻粉成长月数(协议 `dfgm`,>0 = 是钻粉,粉丝牌右侧叠 suffix 层)。
  final int months;

  /// 斗鱼钻粉 suffix 装扮 id(协议 `diafid`)→ 查主播装扮表取 suffix 图。
  final int diafid;

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
                  Positioned.fill(child: ClipOval(child: image)),
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
                        shadows: [
                          Shadow(color: Colors.black87, blurRadius: 1.5),
                        ],
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

    // 抖音:img-only 站(web `CHAT_FAN_BADGE_IMG_ONLY_SITES`)。
    // 链路:**协议图优先(先灰图换彩色)**,无协议图/灰图换彩统一回落官方
    // 紧凑款 `pop_super_badge`(60×48 → 26.2px,2026-09-27 用户口径
    // dyx-compare.png:三模板统一最右紧凑款);高度沿用 21px(与其他平台
    // 徽章一致),宽度按原图比例。
    //
    // 2026-09-26 用户报「粉丝牌背景太长」的根因:此前兜底模板写成
    // `fansclub_level_v6`(150×48 → 65.6px 长条);09-27 又发现兜底/
    // advanced_gray 换彩用的 `fansclub_new_badge`(39.4px)与协议主流图
    // `ranklist_fansclub_pop_super_badge`(26.2px)宽窄不一,同一房间两种
    // 宽度 —— 现统一紧凑款。
    if (site == 'douyin') {
      const badgeHeight = AppDouyinChatBadge.fanImageHeight;
      final officialUrl = douyinFansColoredBadgeUrl(remoteUrl, level).isNotEmpty
          ? douyinFansColoredBadgeUrl(remoteUrl, level)
          : douyinFansBadgeUrl(level);
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
      final tooltip = hasName ? '$name Lv.$level' : '粉丝牌 Lv.$level';
      // 身份图标（守盾 / V）是**独立身份徽章**，不是粉丝牌底图的一部分
      // （用户口径 2026-09-26）：作为粉丝牌右侧的并列兄弟节点单独渲染，
      // 且回到原尺寸 20（官网 `.fans-icon-sf` 实测 22/26/28 × 20）。
      final identity = widget.vFlag > 0 && widget.vLogo.isNotEmpty
          ? _HuyaSuperFanBadge(logo: widget.vLogo)
          : _HuyaFanIdentityIcon(level: level, identity: widget.identity);
      // 身份徽章放在 `huya-fan-badge` **之外**:否则这个 key 会把整个
      // Row 圈进来,量到的是 Row 高(身份图标 20)而非粉丝牌胶囊高(16.1)。
      Widget withIdentity(Widget badge) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          KeyedSubtree(key: const Key('huya-fan-badge'), child: badge),
          const SizedBox(width: 2),
          identity,
        ],
      );
      // 官方底图 URL 已由解析侧用房间级 `sFloorUrl` 模板拼好放进
      // `DanmakuBadge.url`（底图内含等级圆标与团名留白）。
      // `url` 为空 = 房间级资源没取到 → 降级自绘，**不编造 CDN 路径**。
      // **定制牌**(官网 NewFloor 空底框 + Lv 等级数字图 + 团名,shadow DOM
      // 实测:Floor 80×20 / Lv 58×20 / 名字左缘 ~42px,官网把等级图叠在
      // 底框左区、团名居右)。等级图缺失 → 回落通用底图路径(等级烘焙)。
      if (widget.custom &&
          widget.levelUrl.isNotEmpty &&
          remoteUrl.isNotEmpty &&
          !_imgFailed) {
        return Tooltip(
          message: tooltip,
          child: withIdentity(
            KeyedSubtree(
              key: const Key('huya-custom-fan-badge'),
              child: SizedBox(
                width: AppHuyaChatBadge.customFloorWidth,
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
                      left: 0,
                      top: 0,
                      width: AppHuyaChatBadge.customLevelWidth,
                      height: AppHuyaChatBadge.fanHeight,
                      child: CachedNetworkImage(
                        imageUrl: widget.levelUrl,
                        fit: BoxFit.contain,
                        cacheKey: widget.levelUrl,
                        errorWidget: (_, _, _) => const SizedBox.shrink(),
                      ),
                    ),
                    Positioned(
                      left: AppHuyaChatBadge.customNameLeft,
                      right: AppHuyaChatBadge.customNameRight,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Text(
                          name!.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: AppHuyaChatBadge.customNameFontSize,
                            height: 1,
                            color: AppOnBright.white,
                            fontWeight: FontWeight.w400,
                          ),
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
      if (remoteUrl.isNotEmpty && !_imgFailed) {
        return Tooltip(
          message: tooltip,
          child: withIdentity(
            SizedBox(
              height: AppHuyaChatBadge.fanHeight,
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
          ),
        );
      }
      return Tooltip(
        message: tooltip,
        child: withIdentity(
          Container(
            height: AppHuyaChatBadge.fanHeight,
            constraints: const BoxConstraints(
              minWidth: AppHuyaChatBadge.fanMinWidth,
            ),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: AppHuyaChatBadge.fanGradient(level),
              ),
              // web `.chat-fan-badge--huya { border-radius: 2px }`：不是胶囊。
              borderRadius: BorderRadius.circular(AppHuyaChatBadge.fanRadius),
            ),
            padding: const EdgeInsets.only(
              left: AppHuyaChatBadge.fanPadLeft,
              right: AppHuyaChatBadge.fanPadRight,
            ),
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _HuyaFanLevelDisc(level: level),
                if (hasName) ...[
                  // web `.chat-fan-badge__level-disc { margin: 0 .14em 0 0 }`
                  // （自身字号 .67em → 1.31px）。
                  const SizedBox(width: AppHuyaChatBadge.fanDiscGap),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 64),
                    child: Text(
                      name.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        // web `.chat-fan-badge__name--huya { font-size: .79em;
                        // font-weight: 700 }` —— 不是 12px/400。
                        fontSize: AppHuyaChatBadge.fanNameFontSize,
                        height: 1,
                        color: AppOnBright.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
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
      // web `.chat-fan-badge__content { gap: .18em; font-size: .9em }`；
      // composed 分支把 gap 覆写为 `.2em`。
      final contentGap = hasProtocolColor
          ? AppChatBadge.biliFanGap
          : AppChatBadge.fanGap;
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
                  fontSize: AppChatBadge.fanFontSize,
                  height: 1,
                  color: resolvedTextColor,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (hasName) SizedBox(width: contentGap),
          Text(
            '$level',
            style: TextStyle(
              fontSize: AppChatBadge.fanFontSize,
              height: 1,
              color: resolvedLevelColor,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      );
      // 无协议渐变色 → 官方边框图 `medal-frame.png` + 文字叠层。web 此时走
      // `.chat-fan-badge--has-bg`（不是 composed）：高 `1.28em`、`min-width: 3.2em`、
      // 内容 `padding: 0 .22em 0 .16em`，并叠 `text-shadow` 保证压图可读。
      if (!hasProtocolColor && !_imgFailed) {
        return Tooltip(
          message: hasName ? '$name Lv.$level' : '粉丝团 Lv.$level',
          child: KeyedSubtree(
            key: const Key('bilibili-fan-badge'),
            child: ClipRRect(
              borderRadius: const BorderRadius.all(Radius.circular(999)),
              child: Container(
                height: AppChatBadge.fanHeight,
                constraints: const BoxConstraints(
                  minWidth: AppChatBadge.fanMinWidth,
                ),
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
                          height: AppChatBadge.fanHeight,
                          assetPathOverride: bilibiliMedalFrameAssetPath(),
                          onFail: _markImgFailed,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(
                        left: AppChatBadge.fanPadLeft,
                        right: AppChatBadge.fanPadRight,
                      ),
                      child: Center(
                        child: DefaultTextStyle.merge(
                          style: const TextStyle(
                            shadows: AppChatBadge.fanTextShadow,
                          ),
                          child: content,
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
      // 有协议渐变色 → web `.chat-fan-badge--bilibili-composed`：高 `1.48em`、
      // `min-width: 3.5em`、`padding: 0 .5em`、圆角 999px、字重 700。
      return Tooltip(
        message: hasName ? '$name Lv.$level' : '粉丝团 Lv.$level',
        child: KeyedSubtree(
          key: const Key('bilibili-fan-badge'),
          child: _BadgeBox(
            height: AppChatBadge.biliFanHeight,
            minWidth: AppChatBadge.biliFanMinWidth,
            radius: AppRadius.pill,
            padding: const EdgeInsets.symmetric(
              horizontal: AppChatBadge.biliFanPadX,
            ),
            gradient: hasProtocolColor ? [Color(start), Color(end)] : null,
            color: hasProtocolColor ? null : neutralBg,
            // web `linear-gradient(to left, start, end)`:start 在右、end 在左。
            gradientBegin: Alignment.centerRight,
            gradientEnd: Alignment.centerLeft,
            border: colorBorder != 0 ? Color(colorBorder) : null,
            child: content,
          ),
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
      // 官方**组合样式**(2026-09-27 起,对齐官网 web `dy-fan-medal` lit 组件):
      // 等级桶背景图(5 级一档,wconf fans_medal_web_v5.json) + 房间自定义
      // 前缀图(brid 匹配) + 等级数字 + 团名。旧单张烘焙 PNG 是静态历史款,
      // 与官网当前样式(动态 webp 前缀/华丽桶图)脱节 —— 用户口径「部分粉丝牌
      // 是动态的还有复杂的样式,应该结合 web 来对齐」。配置拉取失败或等级
      // 无桶时回落旧渲染(legacyBuilder),不阻断显示。
      return _DouyuFanMedal(
        level: level,
        name: name.trim(),
        brid: widget.brid,
        months: widget.months,
        diafid: widget.diafid,
        textColor: resolvedTextColor,
        legacyBuilder: () =>
            _buildDouyuLegacyFanBadge(context, resolvedTextColor),
      );
    }
    // 其他平台:协议图优先;没有真实图才走品牌色文字胶囊。
    //
    // web 口径：Twitch / YY 是**纯图标徽章**（`.chat-fan-badge--platform-bg` /
    // `--yy`，高 `1.15em`）；其余平台有底图时用通用高度 `1.28em`。
    final isIconOnlySite = site == 'twitch' || site == 'yy';
    if (remoteUrl.isNotEmpty && !_imgFailed) {
      return ChatBadgeImage(
        site: site,
        kind: ChatBadgeKind.fans,
        level: level,
        height: isIconOnlySite
            ? AppChatBadge.iconHeight
            : AppChatBadge.fanHeight,
        src: remoteUrl,
        onFail: _markImgFailed,
      );
    }
    return _BadgeBox(
      height: AppChatBadge.fanHeight,
      radius: 999,
      padding: const EdgeInsets.only(
        left: AppChatBadge.fanPadLeft,
        right: AppChatBadge.fanPadRight,
      ),
      color: tokens.brand.withValues(alpha: 0.18),
      border: tokens.brand.withValues(alpha: 0.6),
      child: Text(
        label(site, name, hasName, level),
        style: TextStyle(
          fontSize: AppChatBadge.fanFontSize,
          height: 1,
          color: tokens.brand,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  /// 默认平台分支的胶囊文案:「团名 级」或纯等级。
  String label(String site, String? name, bool hasName, int level) =>
      hasName && name != null ? '${name.trim()} $level' : '$level';

  /// 斗鱼粉丝牌**旧渲染**(官方单张烘焙 PNG 时代):web 组合样式的配置
  /// 不可得(拉取失败/等级无桶)时由 [_DouyuFanMedal] 回落到这里。
  Widget _buildDouyuLegacyFanBadge(
    BuildContext context,
    Color resolvedTextColor,
  ) {
    final name = widget.name;
    if (name == null) return const SizedBox.shrink();
    final remoteUrl = widget.iconUrl.isNotEmpty ? widget.iconUrl : widget.url;
    // 协议图优先(官网旧款 `staticlive` 烘焙 PNG):失败走本地素材。
    if (remoteUrl.isNotEmpty && !_imgFailed) {
      return KeyedSubtree(
        key: const Key('douyu-fan-badge'),
        child: Container(
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
                  site: widget.site,
                  kind: ChatBadgeKind.fans,
                  level: widget.level,
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
                      fontSize: AppFontSize.caption,
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
        ),
      );
    }
    // 本地烘焙 PNG 贴左:等级已绘在图内。曾踩的坑(ImageRepeat.repeatX
    // 平铺复制等级徽、BoxFit.fill 压扁)见 git 历史,一律不用。
    if (!_imgFailed &&
        badgeAssetPath(
          site: widget.site,
          kind: ChatBadgeKind.fans,
          level: widget.level,
        ).isNotEmpty) {
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
                site: widget.site,
                kind: ChatBadgeKind.fans,
                level: widget.level,
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
                    fontSize: AppFontSize.caption,
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
          fontSize: AppFontSize.caption,
          height: 1.1,
          color: AppOnBright.white,
          fontWeight: FontWeight.w600,
          shadows: AppDouyuChatBadge.fanTextShadow,
        ),
      ),
    );
  }
}

/// 斗鱼粉丝牌官方组合样式(对齐官网 web `dy-fan-medal` lit 组件)。
///
/// 四层结构(2026-09-27 房间 96555 shadow DOM 实测):
/// 1. 背景图 `backdrop`:等级按 5 级一档分桶,配置源
///    `wconf.douyucdn.cn/resource/common/fans_medal_web_v5.json`(与官网
///    同一份数据,见 `DouyuFansMedalAssets`);
/// 2. 前缀图 `prefix`:房间自定义徽记,按 `brid` 匹配;底部对齐、顶部
///    溢出容器 3px(web 原样,24×22);
/// 3. 等级数字:web 是编译进 CSS 的 per-level 小图(AkrobatBlack 字形),
///    离线化成本高,这里用白字近似 —— 无前缀时占满左区 22×19,有前缀时
///    落在右侧 13×10 小盒;
/// 4. 团名 `name`:白字 12px 居中,右侧内缩 4px。
///
/// 配置未就绪/等级无桶 → [legacyBuilder](旧渲染),不阻断显示。
class _DouyuFanMedal extends StatefulWidget {
  const _DouyuFanMedal({
    required this.level,
    required this.name,
    required this.legacyBuilder,
    this.brid = 0,
    this.months = 0,
    this.diafid = 0,
    this.textColor = Colors.white,
  });

  final int level;
  final String name;
  final int brid;

  /// 钻粉成长月数(>0 = 叠钻粉 suffix 层,容器加宽 66→96)。
  final int months;

  /// 钻粉 suffix 装扮 id(`diafid`)→ 查装扮表取主播购买款 suffix 图。
  final int diafid;
  final Color textColor;
  final Widget Function() legacyBuilder;

  @override
  State<_DouyuFanMedal> createState() => _DouyuFanMedalState();
}

class _DouyuFanMedalState extends State<_DouyuFanMedal> {
  DouyuFansMedalConfig? _config;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final config = await DouyuFansMedalAssets.instance.get();
    if (!mounted) return;
    if (config == null) {
      setState(() => _loadFailed = true);
      return;
    }
    setState(() => _config = config);
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final backdropUrl = config?.backdropUrl(widget.level);
    if (config == null && !_loadFailed) {
      // 配置在途:占位避免布局跳动,不闪旧样式。
      return SizedBox(
        width: AppDouyuChatBadge.medalWidth,
        height: AppDouyuChatBadge.medalHeight,
      );
    }
    if (backdropUrl == null || backdropUrl.isEmpty) {
      // 配置拉取失败,或该等级没有桶图(理论上不会,commBg 覆盖 0..61+)
      // → 回落旧渲染。
      return widget.legacyBuilder();
    }
    final prefixUrl = _config?.prefixUrl(widget.brid);
    // suffix 图:有 diafid 且装扮表(inter_com_w_anchor_rights.json)命中
    // → 主播购买款(动图 webp);否则默认款(diamond_list[1] 的 6ab5daa PNG)。
    final suffixUrl =
        _config?.diamondSuffixUrl(widget.diafid) ?? kDouyuDiamondFanSuffixUrl;
    // 钻粉 suffix 层(月数>0):官网把钻粉钻石图结合在粉丝牌后面,容器
    // 加宽 66→84(computed 实测保底)。官网团名 span 按内容自适应、永不
    // 截断(overflow:visible 无 ellipsis),这里按团名实测宽度把容器继续
    // 撑开(suffix 上限 140),suffix 恒贴最右。
    //
    // 测量必须合并 DefaultTextStyle(2026-09-27 房间 84452「保飞派」被截
    // 成「保...」的根因):真实 Text 会继承 MaterialApp 主题的 fontFamily
    // (AppTypography.family),裸 TextStyle 的 TextPainter 用默认字体测宽,
    // CJK 字形推进宽度不同 → 测量宽 < 渲染宽 → 名字被 ellipsis。同因还
    // 要带上 textScaler;+2px 是亚像素/字距合成余量。
    final hasSuffix = widget.months > 0;
    final nameStyle = DefaultTextStyle.of(context).style.merge(
          TextStyle(
            fontSize: AppDouyuChatBadge.medalNameFontSize,
            height: 1,
            color: widget.textColor,
            fontWeight: FontWeight.w600,
          ),
        );
    final namePainter = TextPainter(
      text: TextSpan(text: widget.name, style: nameStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final nameWidth = namePainter.width + 2;
    final minWidth = hasSuffix
        ? AppDouyuChatBadge.medalWidthWithSuffix
        : AppDouyuChatBadge.medalWidth;
    // 官网容器是内容自适应的 min-width:66/84,团名更长就继续撑开
    // (非 suffix 右缘让位 medalRightGap,suffix 右缘让位 suffix 区+间隙)。
    var badgeWidth = minWidth;
    final needed = hasSuffix
        ? AppDouyuChatBadge.medalLeftZone +
            nameWidth +
            2 +
            AppDouyuChatBadge.medalSuffixWidth
        : AppDouyuChatBadge.medalLeftZone + nameWidth +
            AppDouyuChatBadge.medalRightGap;
    if (needed > badgeWidth) badgeWidth = needed;
    if (hasSuffix && badgeWidth > AppDouyuChatBadge.medalWidthWithSuffixMax) {
      badgeWidth = AppDouyuChatBadge.medalWidthWithSuffixMax;
    }
    return KeyedSubtree(
      key: const Key('douyu-fan-badge'),
      child: SizedBox(
        width: badgeWidth,
        height: AppDouyuChatBadge.medalHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // 1) 背景图(等级桶)
            Positioned.fill(
              child: CachedNetworkImage(
                imageUrl: backdropUrl,
                fit: BoxFit.fill,
                cacheKey: backdropUrl,
                placeholder: (_, _) => const SizedBox.shrink(),
                errorWidget: (_, _, _) => Container(
                  color: AppDouyuChatBadge.fanFallbackBg,
                ),
              ),
            ),
            // 2) 房间自定义前缀图(底部对齐,顶部溢出 3px = web 原样)
            if (prefixUrl != null && prefixUrl.isNotEmpty)
              Positioned(
                left: 1,
                bottom: 0,
                width: AppDouyuChatBadge.medalPrefixWidth,
                height: AppDouyuChatBadge.medalPrefixHeight,
                child: CachedNetworkImage(
                  imageUrl: prefixUrl,
                  fit: BoxFit.contain,
                  cacheKey: prefixUrl,
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
            // 3) 等级数字(白字近似 web 的 per-level 小图)。有前缀时 web
            //    computed 实测(2026-09-27):13×10 小盒、bottom:0 —— 数字
            //    **贴容器底**(用户报「数字太靠上」即此处当年误做整高居中);
            //    无前缀时 web 是整高数字图(0..19,字形本身略偏中下),
            //    文本居中近似可接受。
            Positioned(
              left: prefixUrl != null
                  ? AppDouyuChatBadge.medalLevelSmallLeft
                  : 1,
              width: prefixUrl != null
                  ? AppDouyuChatBadge.medalLevelSmallWidth
                  : AppDouyuChatBadge.medalLeftZone - 2,
              bottom: 0,
              height: prefixUrl != null
                  ? AppDouyuChatBadge.medalLevelSmallHeight
                  : AppDouyuChatBadge.medalHeight,
              child: Center(
                child: Text(
                  '${widget.level}',
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: prefixUrl != null
                        ? AppDouyuChatBadge.medalLevelSmallFontSize
                        : AppDouyuChatBadge.medalLevelFontSize,
                    height: 1,
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontFeatures: const [FontFeature.tabularFigures()],
                    shadows: [
                      // web 烘焙数字自带立体暗边;白字必须压暗才可读。
                      Shadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 1.5),
                    ],
                  ),
                ),
              ),
            ),
            // 4) 团名(有钻粉 suffix 时右缘让位 suffix 区,web
            //    `.container.has-suffix .name{right:30px}`)
            Positioned(
              left: AppDouyuChatBadge.medalLeftZone,
              right: hasSuffix
                  ? AppDouyuChatBadge.medalNameRightWithSuffix
                  : AppDouyuChatBadge.medalRightGap,
              top: 0,
              bottom: 0,
              child: Center(
                // 官网 .name overflow:visible、内容自适应永不截断(2026-09-27
                // 实测)。容器宽度已按文字实测撑开,visible 只是极端情况
                // (超长名触顶 140)下不截字、允许画出边界的兜底。
                child: Text(
                  widget.name,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.visible,
                  style: nameStyle,
                ),
              ),
            ),
            // 5) 钻粉 suffix 层(官网把钻粉钻石图**结合在粉丝牌后面**,即
            //    用户口径「gif 样式结合在粉丝牌后面」;默认款是静态 PNG,
            //    房间自定款动图 webp 协议未下发,降级统一默认款) + 月数
            //    白字。几何为 computed 实测:图 26×21 右侧贴底、顶溢 2px;
            //    月数字 15×12 贴底叠在图上。
            if (hasSuffix) ...[
              Positioned(
                right: AppDouyuChatBadge.medalSuffixRight,
                bottom: 0,
                width: AppDouyuChatBadge.medalSuffixWidth,
                height: AppDouyuChatBadge.medalSuffixHeight,
                child: CachedNetworkImage(
                  imageUrl: suffixUrl,
                  // 源图 33×24,官网按 CSS 档 30×21 缩放绘制(fill),contain
                  // 会因宽高比差异横向留白显得没靠右。
                  fit: BoxFit.fill,
                  cacheKey: suffixUrl,
                  filterQuality: FilterQuality.medium,
                  placeholder: (_, _) => const SizedBox.shrink(),
                  errorWidget: (_, _, _) => const SizedBox.shrink(),
                ),
              ),
              Positioned(
                right: AppDouyuChatBadge.medalSuffixRight,
                bottom: 0,
                width: AppDouyuChatBadge.medalSuffixMonthWidth,
                height: AppDouyuChatBadge.medalSuffixMonthHeight,
                child: Center(
                  child: Text(
                    '${widget.months}',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppDouyuChatBadge.medalSuffixMonthFontSize,
                      height: 1,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.45),
                          blurRadius: 1.5,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
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

/// 用户等级徽章（各平台按 web `ChatUserLevelBadge.vue` 形态渲染）。
///
/// 尺寸口径统一在 `DESIGN.md` §4.4；这里只记分支语义：
/// - 虎牙:官方 `consumeLevelBadgeV2` 图（高 1.48em），等级数字叠在**右下角**；
///   贵族/VIP emblem 与平台等级是两种身份，不把 `vip/v2` 图片冒充平台等级；
/// - 抖音:honor 荣誉图 `douyin/honor/{lv}.png`(≤75;图内含数字不叠文字);
///   失败/超档回落紫粉渐变数字;
/// - 斗鱼:`LV{level}` 渐变文字胶囊（高 `1.15em`、圆角 2px、字号 `.64em`）；
/// - B 站:`LV{level}` 渐变文字胶囊（高 `1.48em`、圆角 999px、字号 `.64em`）；
///   protocol wealth 图不在本轮；
/// - 其他:纯数字 + 灰底 `#6b7280`（web default 分支）。
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
            // 与官方图裁剪后同宽(32)——不撑成 45px 空胶囊(用户 2026-09-27
            // 反馈背景太宽)。
            minWidth: AppHuyaChatBadge.levelWidthCropped,
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
          // 用户口径 2026-09-26:官方图右侧裁掉 7px(45→38)。官方图右半段是
          // 纯渐变空底(留给叠字),裁掉不丢信息。
          width: AppHuyaChatBadge.levelWidthCropped,
          child: Stack(
            children: [
              Positioned.fill(
                child: ClipRRect(
                  // 只圆右侧：裁切后右圆头已被切掉，用与左端同半径补回，
                  // 否则胶囊右端是直角、看起来像被切断。
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(AppHuyaChatBadge.levelRadius),
                    bottomRight: Radius.circular(AppHuyaChatBadge.levelRadius),
                  ),
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
              ),
              // web `.chat-user-level--huya .chat-user-level__huya-lv`：
              // 数字绝对定位在官方图**右下角**（`right: .12em; bottom: .06em`，
              // `font-size: .58em`，白色 + `text-shadow: 0 0 2px rgba(0,0,0,.55)`）。
              Positioned(
                right: AppHuyaChatBadge.levelTextRight,
                bottom: AppHuyaChatBadge.levelTextBottom,
                child: Text(
                  '$level',
                  style: const TextStyle(
                    fontSize: AppHuyaChatBadge.levelTextFontSize,
                    height: 1,
                    color: AppOnBright.white,
                    fontWeight: FontWeight.w700,
                    shadows: [
                      // 对齐 web text-shadow 的 0 0 2px rgba(0,0,0,.55)。
                      Shadow(color: Color(0x8C000000), blurRadius: 2),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    // 斗鱼平台等级：**web 口径**（`.chat-user-level--douyu`）—— `LV{level}`
    // 文字胶囊，宽自适应、圆角 2px、高 `1.15em`、字号 `.64em`、左右内边距 `.26em`。
    // 渐变取 web `buildDouyuUserLevelStyle` → `levelTierGradient(level,
    // [50,40,30,20,10])`（与斗鱼官网那套米金/绿/蓝/靛/紫无关的通用 tier 表）。
    //
    // ⚠️ 斗鱼官网自己那套「小徽标 + 数字」32×16 全圆端胶囊已按"UI 参考 web"
    // 下线（用户口径 2026-09-26「复刻原网页样式」），依据见 `DESIGN.md` §4.4。
    // 协议里的 iconUrl 从来不能把它变成图片。
    if (site == 'douyu') {
      return KeyedSubtree(
        key: const Key('douyu-user-level-pill'),
        child: Container(
          height: AppDouyuChatBadge.levelHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppChatBadge.levelPadX,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _levelTier(level, const [50, 40, 30, 20, 10]),
            ),
            borderRadius: BorderRadius.circular(AppDouyuChatBadge.levelRadius),
          ),
          child: Text(
            'LV$level',
            style: const TextStyle(
              fontSize: AppChatBadge.levelFontSize,
              height: 1,
              color: AppOnBright.white,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ),
      );
    }
    // B 站平台等级：web `buildBilibiliUserLevelStyle` 直接复用斗鱼的 tier 渐变，
    // CSS 走 `.chat-user-level--bilibili` —— 高 `1.48em`（**不**被 douyu 的
    // `1.15em` 覆盖）、`min-width:auto`、圆角 999px、文字 `.64em` + `.26em` 内边距。
    if (site == 'bilibili') {
      return KeyedSubtree(
        key: const Key('bilibili-user-level-pill'),
        child: Container(
          height: AppChatBadge.levelHeight,
          padding: const EdgeInsets.symmetric(
            horizontal: AppChatBadge.levelPadX,
          ),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _levelTier(level, const [50, 40, 30, 20, 10]),
            ),
            borderRadius: BorderRadius.circular(AppRadius.pill),
          ),
          child: Text(
            'LV$level',
            style: const TextStyle(
              fontSize: AppChatBadge.levelFontSize,
              height: 1,
              color: AppOnBright.white,
              fontWeight: FontWeight.w700,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
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
        height: site == 'douyin'
            ? AppDouyinChatBadge.honorHeight
            : 21,
        src: remoteUrl,
        onFail: _markImgFailed,
      );
      return image;
    }
    // 抖音:honor 整图(等级绘在图内);失败/超 75 档回落紫粉渐变数字。
    // 素材是 96×48 的长胶囊(内容只占 x 16..86),两侧半透明留白是素材本身的
    // 一部分:曾按内容区裁到 76/48(高 21 → 33.25px),实测会把图标与数字
    // 边缘切掉,2026-09-27 回退为原比例整图。
    // 高度 2026-09-29 官方口径再缩:21 → 15(粉丝牌 21 的 ~0.71),
    // 官方渲染里 honor 明显小于粉丝牌(用户口径「前面的平台背景和文字
    // 也应该更小一点」),宽随原图比例 96×48 → 30px。
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
        height: AppDouyinChatBadge.honorHeight,
        onFail: _markImgFailed,
      );
    }
    // 斗鱼/B站已在上面按 web 胶囊提前返回；这里是「图片兜底 / 其他平台」文字态。
    // 尺寸取 web `.chat-user-level` 的通用口径：高 `1.48em`、`min-width: 1.2em`、
    // **圆角 0**（web 基础类就是 `border-radius: 0`，只有 bilibili/douyu 覆写成
    // 圆角）、文字 `1em` + 左右 `.22em` 内边距、灰底 `#6b7280` + 白字 700。
    List<Color> colors;
    var label = '';
    if (site == 'douyin') {
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
    // 抖音文字态与 honor 整图同高(官方口径:honor 明显小于粉丝牌),
    // 字号按高度比例缩(通用 1em@20.72 → .72em)。
    final douyinCompact = site == 'douyin';
    return _BadgeBox(
      key: const Key('other-user-level-pill'),
      height: douyinCompact
          ? AppDouyinChatBadge.honorHeight
          : AppChatBadge.levelHeight,
      minWidth: douyinCompact
          ? AppDouyinChatBadge.honorHeight
          : AppChatBadge.levelMinWidth,
      radius: 0,
      padding: EdgeInsets.symmetric(
        horizontal: douyinCompact
            ? AppChatBadge.levelPadX
            : AppChatBadge.levelPadXWide,
      ),
      gradient: colors.length > 1 ? colors : null,
      color: widget.color != 0
          ? Color(0xff000000 | (widget.color & 0xffffff))
          : (colors.length == 1 ? colors.first : null),
      child: Text(
        label,
        style: TextStyle(
          fontSize: douyinCompact
              ? AppChatBadge.levelFontSizeWide * 0.72
              : AppChatBadge.levelFontSizeWide,
          height: 1,
          color: AppOnBright.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// 虎牙粉丝牌胶囊左侧的圆形等级徽记（web `.chat-fan-badge__level-disc`）。
///
/// 官网 `fans-icon` 的 `padding-left:18px` 区域就是这枚圆标（等级数字绘在
/// 官方底图里）；底图不可得时用同尺寸圆形 + 数字复刻。web 口径：
/// `min-width: 1.05em`（自身字号 `.67em` → 直径 9.85）、`background: rgba(0,0,0,.22)`、
/// 字重 800、`border-radius: 999px`。
class _HuyaFanLevelDisc extends StatelessWidget {
  const _HuyaFanLevelDisc({required this.level});

  final int level;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: AppHuyaChatBadge.fanLevelDisc,
      height: AppHuyaChatBadge.fanLevelDisc,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppHuyaChatBadge.fanLevelDiscBg,
        shape: BoxShape.circle,
      ),
      child: Text(
        '$level',
        style: const TextStyle(
          fontSize: AppHuyaChatBadge.fanLevelDiscFontSize,
          height: 1,
          color: AppOnBright.white,
          fontWeight: FontWeight.w800,
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
      height: AppHuyaChatBadge.fanIdentitySize,
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
                // 用户口径 2026-09-26:回到原尺寸。此前按
                // AppFontSize.caption(11) 渲染,比官网的 20 小了一半。
                height: AppHuyaChatBadge.fanIdentitySize,
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
      fontSize: AppHuyaChatBadge.fanIdentitySize * 0.82,
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
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
  });

  final double height;
  final double minWidth;
  final double radius;
  final List<Color>? gradient;
  final Color? color;
  final Color? border;
  final Alignment gradientBegin;
  final Alignment gradientEnd;

  /// 内容内边距。默认 4/1 是历史值；按 web 口径复刻时显式传入
  /// （如用户等级文字 `.22em` = 3.08、B 站渐变牌 `.5em` = 7）。
  final EdgeInsetsGeometry padding;

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
      padding: padding,
      alignment: Alignment.center,
      decoration: decoration,
      child: child,
    );
  }
}
