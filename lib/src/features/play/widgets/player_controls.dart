/// 播放控制条:播放/暂停(快照驱动)、音量滑杆+静音、直播延迟占位文案、
/// 画中画与全屏占位按钮。只经 LivePlayer 接口下达指令,不触碰 media_kit。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platforms/common/playback/live_player.dart'
    show PlayerSnapshot;
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/play_provider.dart';

class PlayerControlsBar extends ConsumerWidget {
  const PlayerControlsBar({
    super.key,
    required this.site,
    required this.roomId,
  });

  final String site;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final snapshot =
        ref.watch(playerSnapshotProvider).value ?? const PlayerSnapshot();
    final player = ref.read(playerProvider);
    // 窄屏(<768)/大字体下隐藏音量滑杆与延迟文案:仅四枚按钮已占 192dp,
    // 加上 96dp 滑杆后 360dp 视口必然溢出(实测溢出 230-285dp)。
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;

    // Slider 需要 Material 祖先;播放页为无壳布局,这里用透明 Material 自给。
    return Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Row(
          children: [
            IconButton(
              tooltip: snapshot.playing ? '暂停 (Space)' : '播放 (Space)',
              onPressed: () =>
                  (snapshot.playing ? player.pause() : player.play()),
              icon: Icon(
                snapshot.playing
                    ? Icons.pause_rounded
                    : Icons.play_arrow_rounded,
                size: 20,
                color: tokens.textPrimary,
              ),
            ),
            IconButton(
              tooltip: snapshot.muted ? '取消静音 (M)' : '静音 (M)',
              onPressed: () => player.setMuted(!snapshot.muted),
              icon: Icon(
                snapshot.muted
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                size: 20,
                color: tokens.textPrimary,
              ),
            ),
            if (!compact) ...[
              SizedBox(
                width: 96,
                child: SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 10,
                    ),
                  ),
                  child: Slider(
                    value: (snapshot.muted ? 0.0 : snapshot.volume).clamp(
                      0.0,
                      100.0,
                    ),
                    max: 100,
                    activeColor: tokens.brand,
                    inactiveColor: tokens.border,
                    onChanged: (value) => player.setVolume(value),
                  ),
                ),
              ),
              Expanded(
                child: Center(
                  child: Text('直播中 · 低延迟追帧中', style: AppTypography.caption),
                ),
              ),
            ],
            const Spacer(),
            IconButton(
              tooltip: '画中画',
              onPressed: () {
                // 画中画为占位 action,平台接入后续迭代。
              },
              icon: Icon(
                Icons.picture_in_picture_alt_rounded,
                size: 20,
                color: tokens.textPrimary,
              ),
            ),
            IconButton(
              tooltip: '全屏 (F)',
              onPressed: () => player.toggleFullscreen(),
              icon: Icon(
                Icons.fullscreen_rounded,
                size: 20,
                color: tokens.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
