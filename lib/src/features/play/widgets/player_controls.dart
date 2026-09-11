/// 播放控制条:播放/暂停(快照驱动)、音量滑杆+静音、直播延迟占位文案、
/// 画质/线路 selectbox(2026-09-11 裁决:从独立 QualityLineBar 行移入控制栏,
/// 对齐参考播放器的控制栏布局)、弹幕显隐开关、画中画、刷新视频与全屏按钮。
/// 只经 LivePlayer 接口下达指令,不触碰 media_kit。
///
/// 本组件同时是播放页的键盘绑定宿主(桌面快捷键):`CallbackShortcuts` 内联在
/// 组件树上——焦点在控制条内任意控件(含音量 Slider)时按键依然可达,无需
/// 抢占 `Focus`/`FocusScope`;未聚焦时事件照旧冒泡,不影响其它输入。
///
/// 画质/线路锚点契约(自 QualityLineBar 迁移,保持不变):
/// - 入口:`play-quality-menu` + 当前档名标签 `play-quality-current`;
/// - 菜单项:`play-quality-{name}` / `play-line-item-{name}`(菜单打开才挂载);
/// - 线路入口:`play-line-menu`。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/live_player.dart'
    show LivePlayer, PlayerSnapshot;
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
    // 画质/线路 selectbox 的数据源:本房间的解析结果(未解析成功时不渲染)。
    final play = ref
        .watch(
          playControllerProvider((site: widget.site, roomId: widget.roomId)),
        )
        .value;

    // Slider 需要 Material 祖先;播放页为无壳布局,这里用透明 Material 自给。
    // SnackBar 的宿主由播放页根级 Scaffold 提供(见 play_view.dart)。
    // 不可在本组件内套 Scaffold:控制条位于无界高度的 Stack 内,Scaffold 的
    // CustomMultiChildLayout 会拿到无限高约束 → performLayout 断言失败,
    // 进而整页渲染不出来(实测连坐 50 个用例)。
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
          // 收缩判据用控制条「自身可用宽」而非视口宽:宽视口也可能因常驻
          // 侧栏挤压出 ~390dp 的窄控制条(实测 800 视口 → 392dp 溢出)。
          child: LayoutBuilder(
            builder: (context, constraints) {
              final snapshot =
                  ref.watch(playerSnapshotProvider).value ??
                  const PlayerSnapshot();
              final player = ref.read(playerProvider);
              final compact = constraints.maxWidth < 560;
              return buildRow(context, snapshot, player, compact, play);
            },
          ),
        ),
      ),
    );
  }

  /// 控制条主行;[compact] 为 true 时隐藏音量滑杆/延迟文案/画中画。
  Widget buildRow(
    BuildContext context,
    PlayerSnapshot snapshot,
    LivePlayer player,
    bool compact,
    PlayState? play,
  ) {
    final tokens = context.tokens;
    final payload = play?.payload;
    return Row(
      children: [
        IconButton(
          // 测试锚点:播放/暂停按钮。
          key: const Key('play-toggle-play'),
          tooltip: snapshot.playing ? '暂停 (Space)' : '播放 (Space)',
          onPressed: () => (snapshot.playing ? player.pause() : player.play()),
          icon: Icon(
            snapshot.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
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
            snapshot.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
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
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
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
        // 画质/线路 selectbox:自 QualityLineBar 迁入控制栏(2026-09-11
        // 裁决)。房间未解析成功时不渲染,避免空菜单入口。
        if (payload != null) ...[
          _QualitySelectBox(
            payload: payload,
            activeQuality: play?.quality,
            onQualityTap: (quality) => ref
                .read(
                  playControllerProvider((
                    site: widget.site,
                    roomId: widget.roomId,
                  )).notifier,
                )
                .switchQuality(quality),
          ),
          const SizedBox(width: AppSpacing.sm),
          _LineSelectBox(
            activeQuality: play?.quality,
            activeLine: play?.line,
            onLineTap: (line) => ref
                .read(
                  playControllerProvider((
                    site: widget.site,
                    roomId: widget.roomId,
                  )).notifier,
                )
                .switchLine(line),
          ),
          const SizedBox(width: AppSpacing.sm),
        ],
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
              color: widget.showDanmaku ? tokens.brand : tokens.textSecondary,
            ),
          ),
        if (!compact)
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
          // 测试锚点:刷新视频(重开当前线路,不重解析 payload)。
          key: const Key('play-refresh-stream'),
          tooltip: '刷新视频',
          onPressed: () {
            // 复用 playControllerProvider 的 retry 通路:payload 已就位时
            // 只 bump 代际并重新 open 当前线路(轻量重开流),不重解析房间;
            // 仅当解析失败(payload 为 null)时 retry 才整体重解析,语义也合理。
            ref
                .read(
                  playControllerProvider((
                    site: widget.site,
                    roomId: widget.roomId,
                  )).notifier,
                )
                .retry();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('已刷新'),
                duration: Duration(seconds: 2),
              ),
            );
          },
          icon: Icon(
            Icons.refresh_rounded,
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
    );
  }
}

/// 画质 selectbox:入口显示当前档名(`play-quality-current`),菜单项沿用
/// `play-quality-{name}` 锚点,选中档打勾。自 QualityLineBar 迁入。
class _QualitySelectBox extends StatelessWidget {
  const _QualitySelectBox({
    required this.payload,
    required this.activeQuality,
    required this.onQualityTap,
  });

  final RoomPayload payload;
  final StreamQuality? activeQuality;
  final ValueChanged<StreamQuality> onQualityTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PopupMenuButton<StreamQuality>(
      // 测试锚点:画质下拉入口。
      key: const Key('play-quality-menu'),
      tooltip: '选择画质',
      padding: EdgeInsets.zero,
      onSelected: onQualityTap,
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
    );
  }
}

/// 线路 selectbox:入口显示当前线路名,菜单项锚点 `play-line-item-{name}`。
class _LineSelectBox extends StatelessWidget {
  const _LineSelectBox({
    required this.activeQuality,
    required this.activeLine,
    required this.onLineTap,
  });

  final StreamQuality? activeQuality;
  final StreamLine? activeLine;
  final ValueChanged<StreamLine> onLineTap;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return PopupMenuButton<StreamLine>(
      // 测试锚点:线路下拉入口。
      key: const Key('play-line-menu'),
      tooltip: '选择线路',
      padding: EdgeInsets.zero,
      onSelected: onLineTap,
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
          Text(activeLine?.name ?? '线路', style: AppTypography.bodySecondary),
          const Icon(Icons.arrow_drop_down_rounded, size: 18),
        ],
      ),
    );
  }
}
