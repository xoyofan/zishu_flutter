/// 画质/线路选择条:上排为房间全部画质档位,下排为选中画质下的线路。
library;

import 'package:flutter/material.dart';
import 'package:live_parser/live_parser.dart';

import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';

class QualityLineBar extends StatelessWidget {
  const QualityLineBar({
    super.key,
    required this.payload,
    required this.activeQuality,
    required this.activeLine,
    required this.onQualityTap,
    required this.onLineTap,
  });

  final RoomPayload? payload;
  final StreamQuality? activeQuality;
  final StreamLine? activeLine;
  final ValueChanged<StreamQuality> onQualityTap;
  final ValueChanged<StreamLine> onLineTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final payload = this.payload;
    if (payload == null) return const SizedBox(height: AppSpacing.sm);

    // 响应式断点:宽屏(≥1024)保持现有横向 chips(现状不动,避免回归);
    // 窄屏(<1024)把画质/线路收进两个 PopupMenuButton,避免一行 chip 挤占
    // 视频区且更易点中(平板上横向 ListView 虽不溢出但档位多时难点)。
    final narrow = MediaQuery.sizeOf(context).width < AppBreakpoints.tablet;

    // ChoiceChip 需要 Material 祖先;播放页为无壳布局,这里用透明 Material 自给。
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: 40,
        child: narrow
            ? _narrowMenus(tokens)
            : ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final option in payload.availableQualities)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: _Chip(
                        // 测试锚点:定位/点击画质 chip。
                        anchorKey: Key('play-quality-${option.name}'),
                        label: option.name,
                        selected: activeQuality?.name == option.name,
                        onTap: () {
                          final match = payload.streams
                              .where((stream) => stream.name == option.name)
                              .firstOrNull;
                          if (match != null) onQualityTap(match);
                        },
                      ),
                    ),
                  VerticalDivider(width: AppSpacing.lg, color: tokens.border),
                  for (final line
                      in activeQuality?.lines ?? const <StreamLine>[])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: _Chip(
                        // 测试锚点:定位/点击线路 chip。
                        anchorKey: Key('play-line-${line.name}'),
                        label: line.name,
                        selected: activeLine?.url == line.url,
                        onTap: () => onLineTap(line),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// 窄屏(<1024):画质/线路收进两个下拉入口,布局整体防溢出(不叠加固定宽)。
  ///
  /// 入口按钮:`play-quality-menu`(当前画质名 + 下拉箭头)与 `play-line-menu`;
  /// 菜单项锚点沿用 `play-quality-{name}` / `play-line-item-{name}`,挂在
  /// PopupMenuItem 上,选中项打勾。画质入口内标签额外带 `play-quality-current`,
  /// 保证 `anchorKeysWithPrefix('play-quality-')` 在菜单未打开时也至少命中
  /// `play-quality-menu` + `play-quality-current` 两项。
  Widget _narrowMenus(ZishuTokens tokens) {
    final payload = this.payload!;
    // 撑满可用宽:与宽屏 ListView 分支同宽口径(横屏用例以本条宽度作为视频
    // 主区宽度的代理),内部 Row 保持 min,菜单入口仍靠左排列。
    return SizedBox(
      width: double.infinity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          PopupMenuButton<StreamQuality>(
            // 测试锚点:画质下拉入口。
            key: const Key('play-quality-menu'),
            tooltip: '选择画质',
            onSelected: (quality) => onQualityTap(quality),
            itemBuilder: (context) => [
              for (final option in payload.availableQualities)
                PopupMenuItem<StreamQuality>(
                  // 测试锚点:菜单项沿用画质 chip 锚点(挂 PopupMenuItem)。
                  key: Key('play-quality-${option.name}'),
                  value: payload.streams
                      .where((stream) => stream.name == option.name)
                      .firstOrNull,
                  enabled:
                      payload.streams
                          .where((stream) => stream.name == option.name)
                          .firstOrNull !=
                      null,
                  child: Row(
                    children: [
                      if (activeQuality?.name == option.name)
                        Icon(Icons.check_rounded, size: 16, color: tokens.brand)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text(option.name),
                    ],
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 测试锚点:菜单未打开时也暴露当前画质名,供断言口径兜底。
                Text(
                  key: const Key('play-quality-current'),
                  activeQuality?.name ?? '画质',
                  style: AppTypography.bodySecondary,
                ),
                const Icon(Icons.arrow_drop_down_rounded, size: 18),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          PopupMenuButton<StreamLine>(
            // 测试锚点:线路下拉入口。
            key: const Key('play-line-menu'),
            tooltip: '选择线路',
            onSelected: (line) => onLineTap(line),
            itemBuilder: (context) => [
              for (final line in activeQuality?.lines ?? const <StreamLine>[])
                PopupMenuItem<StreamLine>(
                  // 测试锚点:线路菜单项锚点。
                  key: Key('play-line-item-${line.name}'),
                  value: line,
                  child: Row(
                    children: [
                      if (activeLine?.url == line.url)
                        Icon(Icons.check_rounded, size: 16, color: tokens.brand)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: AppSpacing.xs),
                      Text(line.name),
                    ],
                  ),
                ),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  activeLine?.name ?? '线路',
                  style: AppTypography.bodySecondary,
                ),
                const Icon(Icons.arrow_drop_down_rounded, size: 18),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.anchorKey,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  /// 测试锚点:直接挂在 ChoiceChip 上,便于断言选中态。
  final Key anchorKey;

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return ChoiceChip(
      key: anchorKey,
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: AppTypography.bodySecondary.copyWith(
        color: selected ? tokens.brand : tokens.textSecondary,
        fontWeight: selected ? FontWeight.w700 : null,
      ),
      side: BorderSide(color: selected ? tokens.brand : tokens.border),
      showCheckmark: false,
    );
  }
}
