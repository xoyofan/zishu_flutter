part of '../play_side_panel.dart';

/// 消息行高:对齐 web SideChatTab `CHAT_ITEM_LINE_HEIGHT = 1.48`(固定,
/// 不随间距设置变化;间距由列表行 padding 表达)。
const double _kChatLineHeight = 1.48;

/// 表情图边长 = 正文字号 × 网页同款比例。
const double _kEmojiSizeScale = 1.15;

class _ChatRow extends StatelessWidget {
  const _ChatRow({required this.data, required this.fontSize});

  final _ChatRowData data;

  /// 消息字号(web chatSettings.fontSize,12-24;用户名与正文同字号)。
  final double fontSize;

  Color _userColor(BuildContext context) {
    if (data.color == 0) return context.tokens.textSecondary;
    return DanmakuStyle.resolveColor(data.color);
  }

  /// 正文段 spans:按 [DanmakuSegment] 富文本段展开(抖音表情图消息)。
  ///
  /// 回退链:
  /// - segments 为空(默认)→ 单段 [data.message] 纯文本,历史行为零破坏;
  /// - 文本段 / url 为空 / 图片加载失败(errorBuilder)→ 「[表情名]」文本,
  ///   样式与正文一致;
  /// - 表情段 url 非空 → [WidgetSpan] 内联 [Image.network],边长 = 字号 ×
  ///   [_kEmojiSizeScale],`fit: contain`,中线对齐文字。
  ///
  /// 中文化在双队列出口完成(见 _ChatTab._translateForDisplay):进显示
  /// 列表的行已是终稿译文,本组件只做纯展示、不触发任何异步。
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
            child: ColorFiltered(
              colorFilter: chatWebImageFilter,
              child: CachedNetworkImage(
                imageUrl: segment.url,
                cacheKey: segment.url,
                key: Key(
                  'chat-emoji-image-${segment.name.isNotEmpty ? segment.name : segment.text}',
                ),
                width: emojiSide,
                height: emojiSide,
                fit: BoxFit.contain,
                // 表情源图 96×96(抖音官方贴图固定档),显示尺寸 = 字号×1.15
                // (~14-28 逻辑像素),是 3-6 倍下采样;默认 FilterQuality.low
                // 双线性采样会发虚/带锯齿,与徽章图(chat_badges 1414)同口径
                // 用 medium(mipmap) 保下采样清晰度。
                filterQuality: FilterQuality.medium,
                placeholder: (_, _) => SizedBox(
                  width: emojiSide,
                  height: emojiSide,
                ),
                errorWidget: (_, _, _) => Text(segment.text, style: bodyStyle),
              ),
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
      strutStyle: StrutStyle(
        fontSize: fontSize,
        height: _kChatLineHeight,
        forceStrutHeight: true,
      ),
      TextSpan(
        children: [
          // 徽章顺序对齐 web SideChatTab.vue:38-44 —— 平台用户等级 pill 在前、
          // 粉丝牌在后(用户口径 2026-09-19:「平台等级应该在粉丝等级前显示」)。
          if (data.userLevel > 0)
            _inlineBadge(
              _UserLevelBadge(
                site: data.site,
                level: data.userLevel,
                iconUrl: data.userLevelIconUrl,
                badgeStyle: data.userLevelBadgeStyle,
                isPolished: data.userLevelIsPolished,
                color: data.userLevelColor,
              ),
            ),
          ...data.badges.map(
            (badge) => _inlineBadge(
              _FanBadge(
                site: data.site,
                name: badge.name,
                level: badge.level,
                kind: badge.kind,
                url: badge.url,
                iconUrl: badge.iconUrl,
                vFlag: badge.vFlag,
                vLogo: badge.vLogo,
                identity: badge.identity,
                color: badge.color,
                colorStart: data.badgeColorStart,
                colorEnd: data.badgeColorEnd,
                colorBorder: data.badgeColorBorder,
                textColor: data.badgeTextColor,
                levelColor: data.badgeColorLevel,
                brid: badge.badgeRoomId,
              ),
            ),
          ),
          if (data.badges.isEmpty &&
              fanBadge != null &&
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
          if (data.guard != null)
            _inlineBadge(
              _GuardBadge(badge: data.guard!),
            ),
          TextSpan(
            text: data.user,
            style: context.textSecondary.copyWith(
              color: _userColor(context),
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
