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

    // ChoiceChip 需要 Material 祖先;播放页为无壳布局,这里用透明 Material 自给。
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        height: 40,
        child: ListView(
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
            for (final line in activeQuality?.lines ?? const <StreamLine>[])
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
