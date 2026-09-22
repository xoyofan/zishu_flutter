/// 平台筛选 chips:全平台 + 各平台(对齐 SFVideoLive FollowPlatformFilter)。
/// 选中态用平台品牌色点缀底色与描边,文字对比度交给主题文字色。
///
/// 「我的关注」页与播放页侧栏「关注」tab 共用本组件(web 两处也是同一个
/// `FollowPlatformFilter.vue`):侧栏窄容器传 [compact] + [columns],chips
/// 等宽分列铺排,放不下自动换到第二排(对齐 web `follow-tab-toolbar--stretch`
/// 的 6 列等宽网格);页面默认按内容自适应 Wrap。
library;

import 'package:flutter/material.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../../shared/presentation/zishu_tokens.dart';

/// 当前值为平台 id,'all' 表示全平台。
class FollowPlatformFilter extends StatelessWidget {
  const FollowPlatformFilter({
    super.key,
    required this.value,
    required this.onChanged,
    this.compact = false,
    this.columns,
    this.chipKey,
  });

  final String value;
  final ValueChanged<String> onChanged;

  /// 紧凑态(侧栏):更小的字号/内边距与间距。
  final bool compact;

  /// 等宽分列数(侧栏 6 列):每行恰好 [columns] 个等宽 chip,超出自动
  /// 换到第二排;为空则按内容自适应排布(页面)。
  final int? columns;

  /// 条目锚点工厂(测试用),如 `(id) => Key('play-side-follow-site-$id')`。
  final Key? Function(String siteId)? chipKey;

  double _gap() => compact ? AppSpacing.xs : AppSpacing.sm;

  @override
  Widget build(BuildContext context) {
    if (columns != null) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final gap = _gap();
          final maxWidth = constraints.maxWidth;
          if (!maxWidth.isFinite) {
            return _buildWrap(context, cellWidth: null, cellHeight: null);
          }
          final cellWidth = (maxWidth - gap * (columns! - 1)) / columns!;
          // 紧凑 chip:字号 11 * 1.25 + 上下 2 padding ≈ 18,取 24 留呼吸。
          return _buildWrap(
            context,
            cellWidth: cellWidth,
            cellHeight: compact ? 24.0 : 28.0,
          );
        },
      );
    }
    return _buildWrap(context, cellWidth: null, cellHeight: null);
  }

  /// chips 铺排:给了 [cellWidth] 就等宽定高(分列网格),否则按内容 Wrap。
  Widget _buildWrap(
    BuildContext context, {
    required double? cellWidth,
    required double? cellHeight,
  }) {
    final gap = _gap();
    return Wrap(
      spacing: gap,
      runSpacing: compact ? AppSpacing.xs : AppSpacing.sm,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        for (final brand in PlatformBrandCatalog.navPlatforms)
          if (cellWidth != null && cellHeight != null)
            SizedBox(
              width: cellWidth,
              height: cellHeight,
              child: _PlatformChip(
                label: brand.id == 'all' ? '全平台' : brand.name,
                accent: brand.id == 'all' ? context.tokens.accent : brand.color,
                showDot: brand.id != 'all',
                selected: value == brand.id,
                compact: compact,
                stretch: true,
                onTap: () => onChanged(brand.id),
                itemKey: chipKey?.call(brand.id),
              ),
            )
          else
            _PlatformChip(
              label: brand.id == 'all' ? '全平台' : brand.name,
              accent: brand.id == 'all' ? context.tokens.accent : brand.color,
              showDot: brand.id != 'all',
              selected: value == brand.id,
              compact: compact,
              stretch: false,
              onTap: () => onChanged(brand.id),
              itemKey: chipKey?.call(brand.id),
            ),
      ],
    );
  }
}

class _PlatformChip extends StatelessWidget {
  const _PlatformChip({
    required this.label,
    required this.accent,
    required this.showDot,
    required this.selected,
    required this.compact,
    required this.stretch,
    required this.onTap,
    this.itemKey,
  });

  final String label;
  final Color accent;
  final bool showDot;
  final bool selected;
  final bool compact;
  final bool stretch;
  final VoidCallback onTap;
  final Key? itemKey;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return InkWell(
      key: itemKey,
      borderRadius: AppRadius.allSm,
      onTap: onTap,
      // 状态反馈(全部走 token):未选中 hover 抬亮到 surfaceRaised;
      // 已选中的底本身就是 accent 淡底,hover 用 accent 低 alpha 加深而非盖掉选中色。
      // splash/highlight/focus 统一取本 chip 的 accent(全平台/平台品牌色)。
      hoverColor: selected
          ? accent.withValues(alpha: 0.12)
          : tokens.surfaceRaised,
      splashColor: AppStateLayer.splashOf(accent),
      highlightColor: AppStateLayer.pressedOf(accent),
      focusColor: AppStateLayer.focusOf(accent),
      child: AnimatedContainer(
        duration: AppMotion.fast,
        curve: AppMotion.curve,
        width: stretch ? double.infinity : null,
        height: stretch ? double.infinity : null,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 4 : AppSpacing.md,
          vertical: compact ? 2 : AppSpacing.xs,
        ),
        alignment: stretch ? Alignment.center : null,
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.18) : tokens.surface,
          borderRadius: AppRadius.allSm,
          border: Border.all(color: selected ? accent : tokens.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 紧凑分列态不显圆点:单元宽有限,平台用文字传达(web 侧栏
            // chips 本就是纯文字);页面常规 chips 保留品牌色圆点。
            if (showDot && !compact) ...[
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 5),
            ],
            if (stretch)
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: context.textBody.copyWith(
                    fontSize: compact
                        ? AppFontSize.label
                        : AppFontSize.bodySecondary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                    color: selected ? tokens.textPrimary : tokens.textSecondary,
                  ),
                ),
              )
            else
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textBody.copyWith(
                  fontSize: compact
                      ? AppFontSize.label
                      : AppFontSize.bodySecondary,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w400,
                  color: selected ? tokens.textPrimary : tokens.textSecondary,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
