/// 关注条目通用小部件:封面、平台圆点、分类标签、状态点、条目操作按钮。
/// 颜色一律取自 context.tokens,唯一例外是轮播强调色 [kFollowReplayAccent]
/// (web 真源 CSS 变量 `--follow-state-replay-accent`,已收敛到
/// `AppColors.brandBright`)。
library;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 离线置灰滤镜(灰度矩阵,数值非颜色)。
final ColorFilter kGrayscaleFilter = ColorFilter.matrix(<double>[
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0.2126, 0.7152, 0.0722, 0, 0, //
  0, 0, 0, 1, 0,
]);

/// 轮播(replay)状态强调色,对齐 web 真源 `--follow-state-replay-accent`
/// (#f5dc70,SFVideoLive `apps/web/src/styles/main.css:133`):亮金黄,
/// 与在播的 `tokens.liveBadge`(绿)区分。
///
/// 「轮播」小标签:紧凑/单行行内元信息、卡片封面角标共用。
///
/// 对齐 web 关注项的 replay 状态样式(follow-item--replay:金黄描边 +
/// 低透明度底),文字取用户口径「轮播」(2026-09-19)。
class FollowReplayBadge extends StatelessWidget {
  const FollowReplayBadge({super.key, this.fontSize = 10});

  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final accent = context.tokens.brandBright;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.16),
        borderRadius: AppRadius.allSm,
        border: Border.all(color: accent.withValues(alpha: 0.55)),
      ),
      child: Text(
        '轮播',
        style: context.textCaption.copyWith(
          fontSize: fontSize,
          height: 1,
          color: accent,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 封面图:cached_network_image 加载,离线时置灰压暗;加载失败回退占位块。
class FollowCoverImage extends StatelessWidget {
  const FollowCoverImage({
    super.key,
    required this.cover,
    required this.fallbackLabel,
    this.width,
    this.height,
    this.offline = false,
  });

  final String cover;
  final String fallbackLabel;
  final double? width;
  final double? height;
  final bool offline;

  @override
  Widget build(BuildContext context) {
    Widget image = cover.isEmpty
        ? _placeholder(context)
        : CachedNetworkImage(
            imageUrl: cover,
            fit: BoxFit.cover,
            width: width,
            height: height,
            placeholder: (_, _) => _placeholder(context),
            errorWidget: (_, _, _) => _placeholder(context),
          );
    if (offline) {
      image = Opacity(
        opacity: 0.6,
        child: ColorFiltered(colorFilter: kGrayscaleFilter, child: image),
      );
    }
    return image;
  }

  Widget _placeholder(BuildContext context) {
    return ColoredBox(
      color: context.tokens.surfaceRaised,
      child: Center(
        child: Text(
          fallbackLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: context.textSecondary,
        ),
      ),
    );
  }
}

/// 平台品牌色圆点(未收录平台回退次级文字色)。
class FollowPlatformDot extends StatelessWidget {
  const FollowPlatformDot({super.key, required this.site});

  final String site;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color:
            PlatformBrandCatalog.byId(site)?.color ??
            context.tokens.textSecondary,
      ),
    );
  }
}

/// 直播状态点:开播红点 / 离线灰点。
class FollowStatusDot extends StatelessWidget {
  const FollowStatusDot({super.key, required this.live});

  final bool live;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: live ? context.tokens.liveBadge : context.tokens.textSecondary,
      ),
    );
  }
}

/// 分类小标签(raised 底 + caption 字号)。
class FollowCategoryTag extends StatelessWidget {
  const FollowCategoryTag({
    super.key,
    required this.label,
    this.site = '',
    this.cid = '',
  });

  final String label;
  final String site;
  final String cid;

  @override
  Widget build(BuildContext context) {
    // 跨平台统一中文分类名:命中映射用 canonical 名,否则回落平台原名。
    final display = displayCategoryName(site, label, cid);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: context.tokens.surfaceRaised,
        borderRadius: AppRadius.allSm,
      ),
      child: Text(
        display,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: context.textCaption,
      ),
    );
  }
}

/// 覆盖在封面上的浮层小标签(离线/在线人数/平台名等)。
///
/// 参考实现的封面角标一律**紧贴所在角、直角无圆角**;调用方用
/// [Positioned] 以 0 偏移贴边,本组件只负责底色与内边距。
class FollowCoverTag extends StatelessWidget {
  const FollowCoverTag({super.key, required this.child, this.accent});

  final Widget child;

  /// 可选强调底色(如平台品牌色)。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: (accent ?? context.tokens.surfaceSoft).withValues(alpha: 0.88),
      ),
      child: child,
    );
  }
}

/// 主播名:全站统一取**平台品牌色**(离线压暗淡化),未收录平台回退文字 token。
///
/// 关注三密度 / 播放页房间卡 / 侧栏列表共用,保证「看名字就知道是哪个平台」。
class FollowAnchorName extends StatelessWidget {
  const FollowAnchorName({
    super.key,
    required this.site,
    required this.name,
    required this.live,
    this.fontSize = 12.5,
    this.fontWeight = FontWeight.w600,
    this.textAlign,
  });

  final String site;
  final String name;
  final bool live;
  final double fontSize;
  final FontWeight fontWeight;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final brand = PlatformBrandCatalog.byId(site);
    final Color color;
    if (brand != null) {
      color = live ? brand.color : brand.color.withValues(alpha: 0.6);
    } else {
      color = live ? tokens.textPrimary : tokens.textSecondary;
    }
    return TranslatedText(
      name,
      // 主播名中文化(韩/日名翻,英文/中文名原样):原文先显示,译文到达替换。
      translateName: true,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: textAlign,
      style: context.textBody.copyWith(
        fontSize: fontSize,
        fontWeight: fontWeight,
        color: color,
      ),
    );
  }
}

/// 条目级小操作按钮(特别关注/提醒/删除),三密度共用。
class FollowIconAction extends StatelessWidget {
  const FollowIconAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.active = false,
    this.danger = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// 激活态(金色),如已特别关注/提醒开启。
  final bool active;

  /// 危险操作(删除)用 error 色。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final Color color = danger
        ? tokens.error
        : active
        ? tokens.accent
        : tokens.textSecondary;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      // 状态反馈(全部走 token):hover 抬亮到 surfaceRaised;
      // 键盘焦点/按压用 accent 低 alpha(26×26 小目标也能看出焦点)。
      style: IconButton.styleFrom(
        hoverColor: tokens.surfaceRaised,
        highlightColor: tokens.accent.withValues(alpha: 0.10),
        focusColor: tokens.accent.withValues(alpha: 0.10),
      ),
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.all(AppSpacing.xs),
      constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
      icon: Icon(icon, size: 16, color: color),
    );
  }
}

/// 表单控件(Switch / Checkbox)的状态层(hover / focus / pressed)统一取 token。
///
/// Material 的 M3 默认值取 `ThemeData.hoverColor`(白 4%)/ `focusColor`
/// (白 12%)——既非 token 也非 accent;这里显式改为 accent 低 alpha(8–12%),
/// 与全库其它 hover/焦点口径一致。未列状态返回 null = 不叠状态层(同原默认)。
WidgetStateProperty<Color?> controlStateLayer(ZishuTokens tokens) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return tokens.accent.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return tokens.accent.withValues(alpha: 0.08);
      }
      if (states.contains(WidgetState.pressed)) {
        return tokens.accent.withValues(alpha: 0.10);
      }
      return null;
    });

/// 离线卡的「上次开播」文案,语义对齐 web
/// `apps/web/src/utils/follow/followDisplay.ts` 的 `offlineLastLiveLabel`。
///
/// - [lastLiveAt] 毫秒 epoch;`<= 0`(从未记录)回落「未开播」;
/// - 有记录 → 「上次开播 MM-DD HH:mm」(本地时区,与 web 的日级展示同源)。
///
/// 纯函数无 UI 依赖,关注卡与后续任何离线展示位共用,禁止再造第二份格式化。
String offlineLastLiveLabel(int lastLiveAt) {
  if (lastLiveAt <= 0) return '未开播';
  final time = DateTime.fromMillisecondsSinceEpoch(lastLiveAt);
  String two(int value) => value.toString().padLeft(2, '0');
  return '上次开播 '
      '${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
