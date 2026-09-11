/// 播放控制条:播放/暂停(快照驱动)、音量滑杆+静音、直播延迟占位文案、
/// 弹幕显隐开关、画中画与全屏按钮。只经 LivePlayer 接口下达指令,不触碰 media_kit。
///
/// 本组件同时是播放页的键盘绑定宿主(桌面快捷键):`CallbackShortcuts` 内联在
/// 组件树上——焦点在控制条内任意控件(含音量 Slider)时按键依然可达,无需
/// 抢占 `Focus`/`FocusScope`;未聚焦时事件照旧冒泡,不影响其它输入。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../platforms/common/playback/live_player.dart'
    show PlayerSnapshot;
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/play_provider.dart';

class PlayerControlsBar extends ConsumerStatefulWidget {
  const PlayerControlsBar({
    super.key,
    required this.site,
    required this.roomId,
    required this.showDanmaku,
    required this.danmakuEnabled,
    required this.onDanmakuToggle,
  });

  final String site;
  final String roomId;

  /// 舞台弹幕叠加层当前是否显示(播放页本地开关)。
  final bool showDanmaku;

  /// 设置项「弹幕」总开关:决定控制条上这枚按钮是否可见。
  final bool danmakuEnabled;

  /// 切换舞台弹幕显示。
  final VoidCallback onDanmakuToggle;

  @override
  ConsumerState<PlayerControlsBar> createState() => _PlayerControlsBarState();
}

class _PlayerControlsBarState extends ConsumerState<PlayerControlsBar> {
  /// 播放/暂停切换:与点击视频帧共用同一条通路(快照驱动)。
  void _togglePlayback() {
    final snapshot =
        ref.read(playerSnapshotProvider).value ?? const PlayerSnapshot();
    final player = ref.read(playerProvider);
    if (snapshot.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  /// 静音切换:muted 为 true 表示当前静音,再按即取消静音。
  void _toggleMuted() {
    final snapshot =
        ref.read(playerSnapshotProvider).value ?? const PlayerSnapshot();
    ref.read(playerProvider).setMuted(!snapshot.muted);
  }

  /// 全屏切换:接口在平台层当前为空实现(Windows 全屏后续迭代),
  /// 这里照常调用接口,不伪造本地全屏态。
  void _toggleFullscreen() => ref.read(playerProvider).toggleFullscreen();

  /// 桌面键盘绑定。固定三组单选键(Space/M/F),不抢 Ctrl/Alt 组合键。
  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final snapshot =
        ref.watch(playerSnapshotProvider).value ?? const PlayerSnapshot();
    final player = ref.read(playerProvider);
    // 窄屏(<768)/大字体下隐藏音量滑杆与延迟文案:仅四枚按钮已占 192dp,
    // 加上 96dp 滑杆后 360dp 视口必然溢出(实测溢出 230-285dp)。
    final compact = MediaQuery.sizeOf(context).width < AppBreakpoints.phone;

    // Slider 需要 Material 祖先;播放页为无壳布局,这里用透明 Material 自给。
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMuted,
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
      },
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              IconButton(
                // 测试锚点:播放/暂停按钮。
                key: const Key('play-toggle-play'),
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
                // 测试锚点:静音切换按钮。
                key: const Key('play-toggle-mute'),
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
              // 弹幕显隐开关:受设置项「弹幕」总开关约束,关闭时整枚按钮隐藏。
              if (widget.danmakuEnabled)
                IconButton(
                  // 测试锚点:舞台弹幕叠加层显隐开关。
                  key: const Key('play-toggle-danmaku'),
                  tooltip: widget.showDanmaku ? '隐藏弹幕' : '显示弹幕',
                  onPressed: widget.onDanmakuToggle,
                  icon: Icon(
                    widget.showDanmaku
                        ? Icons.subtitles_rounded
                        : Icons.subtitles_off_rounded,
                    size: 20,
                    color: widget.showDanmaku
                        ? tokens.brand
                        : tokens.textSecondary,
                  ),
                ),
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
                // 测试锚点:全屏切换按钮。
                key: const Key('play-toggle-fullscreen'),
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
      ),
    );
  }
}
