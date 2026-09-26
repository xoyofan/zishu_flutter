import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/cover_badges.dart';
import '../../../shared/presentation/widgets/outline_chip.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// SFVideoLive 风格房间卡片:16:9 封面 + 四角 tag + 标题/chips 两行。
///
/// 封面四角口径(2026-09 用户改版裁决):
/// - 左上:分类实底角标([CoverCategoryBadge],分类色,不改线框、不挪位);
/// - 右上:平台身份/榜单线框 tag(`room.identityLabel`,如虎牙
///   「超级明星」;复用 [OutlineChip] 视觉,空则不渲染,暂不做跳转);
/// - 左下:主播昵称(平台品牌色底 + `chipForeground` 文字,单行省略,
///   不包手势,点击落到整卡 onTap 进房);平台名角标已移除,左下让给昵称;
/// - 右下:热度([CoverOnlineBadge],未开播不显示;轮播状态角标同位)。
///
/// 四角角标统一由 [CoverBadge] 家族/线框 chip 渲染,与播放页侧栏预览卡
/// 共用,避免两处角位漂移。封面下两行:第 1 行标题、第 2 行特色 chips
/// (占位恒定行高,与 [metaHeightFor] 的两行预算同源)。
class RoomCard extends StatelessWidget {
  const RoomCard({super.key, required this.room, this.onTap});

  final RoomRecord room;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Material(
      // 测试锚点:定位/点击具体房间卡片。
      key: Key('room-card-${room.site}-${room.roomId}'),
      color: tokens.surface,
      borderRadius: AppRadius.allMd,
      child: InkWell(
        borderRadius: AppRadius.allMd,
        onTap: onTap,
        // 状态反馈(M3 state layer,全部走 token):hover 抬亮到 surfaceRaised;
        // splash/highlight/focus 用 accent 低 alpha(8–12%),键盘焦点可见。
        // 只改颜色,不位移/不缩放(DESIGN.md §7)。
        hoverColor: tokens.surfaceRaised,
        splashColor: AppStateLayer.splashOf(tokens.accent),
        highlightColor: AppStateLayer.pressedOf(tokens.accent),
        focusColor: AppStateLayer.focusOf(tokens.accent),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _Cover(room: room),
            _RoomCardMeta(room: room),
          ],
        ),
      ),
    );
  }
}

/// 封面下元信息:**两行**(标题 + chips,2026-09 用户改版)。
///
/// 对齐参考实现 `RoomCard.vue` 的 `.room-card__body`(padding 6/8/8):
/// - 第 1 行:房间标题(缺标题回退主播名,仍缺则占位不塌陷);
/// - 第 2 行:特色 chip 行([RoomRecord.chips] 按 [SiteChipKind] 排序
///   —— 游戏/类型 tag 在前、language 在后;promoTag 保留为尾部 chip,
///   已与某个 chip 同名时不重复;平台名不进 chip,平台名角标也已移除)。
///   chip 可压缩(见下方 [Flexible] 说明),保证窄卡片也不溢出。
///   主播昵称不再在 meta 行,已移到封面左下角。
///
/// **两行高度必须恒定**:多数房间没有 chip,若不占位,同一网格里卡片高度
/// 参差 —— 第 2 行缺内容也用固定行高占位,与 [metaHeightFor] 的 58px
/// 两行预算同源(见 `room_card_meta_height_test`)。
class _RoomCardMeta extends StatelessWidget {
  const _RoomCardMeta({required this.room});

  final RoomRecord room;

  /// 元信息行高:12px 字号 × 1.35 行高(与参考实现 `min-height: 1.35em` 同口径)。
  static const double _metaLineHeight = 17;

  @override
  Widget build(BuildContext context) {
    final title = (room.title ?? '').trim().isNotEmpty
        ? room.title!
        : ((room.anchorName ?? '').trim().isNotEmpty
              ? room.anchorName!
              : ' ');
    // chip 顺序:按 SiteChipKind 枚举序分桶拼接(桶内保输入序),
    // 实现「游戏/类型 tag 在前,language 在后」;UI 不看平台。
    final siteChips = [
      for (final kind in SiteChipKind.values)
        ...room.chips.where((chip) => chip.kind == kind),
    ];
    // promoTag 保留为特色 chip;已单独成 chip(name 相同)时不重复。
    final promoTag = (room.promoTag ?? '').trim();
    final chipWidgets = <Widget>[
      for (final chip in siteChips)
        OutlineChip(
          key: Key('room-meta-chip-${chip.name}'),
          label: chip.name,
          // 可点判据只看 filterCid(Stage 1 口径);点击进该标签的过滤
          // 房间列表,与分类浮层跳 `/:site/category/:cid` 同一路由。
          onTap: chip.navigable
              ? () => context.go(
                  '/${room.site}/category/${Uri.encodeComponent(chip.filterCid!)}',
                )
              : null,
        ),
      if (promoTag.isNotEmpty &&
          !siteChips.any((chip) => chip.name == promoTag))
        OutlineChip(key: Key('room-meta-chip-$promoTag'), label: promoTag),
    ];
    return Padding(
      // 参考实现 .room-card__body:padding 6px 8px 8px。
      padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 标题自动中文化(原文先显示,译文到达替换;关翻译/失败回原文)。
          TranslatedText(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: context.textTitle.copyWith(fontSize: AppFontSize.subtitle),
          ),
          const SizedBox(height: AppSpacing.xs),
          // 第 2 行:特色 chips;为空时同样占满一行,保证所有平台卡片等高。
          //
          // chip 一律包 [Flexible](松约束):够宽时保持自然宽度,不够宽时
          // 按份压缩、内部 Text 省略,**不换行也不溢出** —— 与官网单行
          // `overflow:hidden` 容器同口径(最窄列 4@768px 卡片 ~175px,
          // 文字缩放 1.3 时三个 6 字标签刚性排布会溢出 136px,实测)。
          SizedBox(
            height: _metaLineHeight,
            child: chipWidgets.isEmpty
                ? null
                : Row(
                    children: [
                      for (final (index, chip) in chipWidgets.indexed) ...[
                        if (index > 0) const SizedBox(width: 6),
                        Flexible(child: chip),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.room});

  final RoomRecord room;

  @override
  Widget build(BuildContext context) {
    final replay = room.isReplay;
    // 在播判据只看状态真源 roomState(浏览目录按 4a-i 已赋 live),
    // 不再用统计数字是否存在推断在线。
    final live = room.isLive;
    final brand = PlatformBrandCatalog.byId(room.site);
    final identity = (room.identityLabel ?? '').trim();
    final anchor = (room.anchorName ?? '').trim();
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(
            color: context.tokens.surfaceSoft,
            child: (room.cover ?? '').isEmpty
                ? _CoverPlaceholder(room: room)
                : CachedNetworkImage(
                    imageUrl: room.cover!,
                    fit: BoxFit.cover,
                    placeholder: (_, _) =>
                        ColoredBox(color: context.tokens.surfaceRaised),
                    errorWidget: (_, _, _) => _CoverPlaceholder(room: room),
                  ),
          ),
          // 离线:整封面遮罩 + 「未开播」(web `.room-card__offline`,z-index 2)。
          // 放在角标之前复刻 web 的层级(遮罩 z2 低于角标 z3,角标浮于其上);
          // 判据沿用本组件的 `live`(roomState 真源),不另造第二套离线判定。
          // 注:web 的「上次开播 X」文案由 follow 域数据支撑,网格数据源
          // 无该字段,离线一律显示「未开播」。
          if (!live && !replay)
            const Positioned.fill(
              key: Key('room-card-offline'),
              child: CoverOfflineOverlay(),
            ),
          // 左上:分类实底角标(保持现状,不改线框、不挪位)。
          Positioned(
            left: 0,
            top: 0,
            child: CoverCategoryBadge(
              // 测试锚点:按角位断言用(卡片各自子树内唯一,不与同页其它卡冲突)。
              key: const Key('cover-badge-category'),
              corner: CoverCorner.topLeft,
              category: room.category ?? '',
              site: room.site,
              cid: room.cid ?? '',
            ),
          ),
          // 右上:平台身份/榜单线框 tag(room.identityLabel,如虎牙「超级明星」;
          // 空则不渲染,暂不做跳转)。
          if (identity.isNotEmpty)
            Positioned(
              right: 0,
              top: 0,
              child: OutlineChip(
                // 测试锚点:右上身份 tag。
                key: const Key('cover-badge-identity'),
                label: identity,
              ),
            ),
          // 左下:主播昵称(平台品牌色底 + chipForeground 文字,单行省略);
          // 不包手势,点击落到整卡 onTap(进房)。平台名角标已移除,左下让给昵称。
          if (anchor.isNotEmpty)
            Positioned(
              left: 0,
              bottom: 0,
              child: CoverBadge(
                // 测试锚点:左下昵称条。
                key: const Key('cover-badge-anchor'),
                corner: CoverCorner.bottomLeft,
                background: brand?.color,
                foreground: brand?.chipForeground,
                child: Text(
                  anchor,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          // 右下:热度(未开播不显示)。
          if (live)
            Positioned(
              right: 0,
              bottom: 0,
              child: CoverOnlineBadge(
                key: const Key('cover-badge-online'),
                corner: CoverCorner.bottomRight,
                // 观众数取统一记录的 audience;未知为 null → 空串,角标按
                // 既有契约隐藏(不伪造 0,不把状态文案当人数)。
                online: room.audience ?? '',
              ),
            ),
          if (replay)
            Positioned(
              right: 0,
              bottom: 0,
              child: CoverBadge(
                key: const Key('room-card-replay'),
                corner: CoverCorner.bottomRight,
                background: context.tokens.brandBright,
                child: Text(
                  '轮播',
                  style: context.textCaption.copyWith(
                    color: context.tokens.surfaceSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          // 左下平台名角标已移除(用户口径 2026-09:全平台封面左下不再显示
          // 平台 tag,位置让给主播昵称;平台信息由页签上下文承载)。
        ],
      ),
    );
  }
}

class _CoverPlaceholder extends StatelessWidget {
  const _CoverPlaceholder({required this.room});

  final RoomRecord room;

  @override
  Widget build(BuildContext context) {
    final category = room.category ?? '';
    return ColoredBox(
      color: context.tokens.surfaceRaised,
      child: Center(
        child: Text(
          category.isEmpty ? room.site : category,
          style: context.textSecondary,
        ),
      ),
    );
  }
}
