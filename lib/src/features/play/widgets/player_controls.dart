/// 播放控制条:播放/暂停(快照驱动)、音量滑杆+静音、直播延迟占位文案、
/// 画质/线路 selectbox(2026-09-11 裁决:从独立 QualityLineBar 行移入控制栏,
/// 对齐参考播放器的控制栏布局)、弹幕显隐开关、画中画、刷新视频、网页全屏与
/// 全屏按钮。只经 LivePlayer 接口下达指令,不触碰 media_kit。
///
/// **本组件不再自带键盘绑定**:快捷键的唯一宿主是播放页(见 play_view.dart)。
/// 旧实现在此内联了一份 Space/M/F 的 `CallbackShortcuts`,而 `Shortcuts` 沿焦点链
/// 由内向外命中即停——用户点过控制条任意按钮/滑杆后焦点留在条内,再按 F 会被
/// 内层截获,只切窗口不进沉浸态(全屏按钮失效的同一类错位)。
///
/// 呈现态由 `screenMode` 传入(单一真源在 playScreenProvider):全屏/网页全屏
/// 按钮的图标、tooltip 与高亮都由它派生,不再各自维护本地 bool。
///
/// 画质/线路锚点契约(自 QualityLineBar 迁移,保持不变):
/// - 入口:`play-quality-menu` + 当前档名标签 `play-quality-current`;
/// - 菜单项:`play-quality-{name}` / `play-line-item-{name}`(菜单打开才挂载);
/// - 线路入口:`play-line-menu`。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:live_parser/live_parser.dart';

import '../../../platforms/common/playback/live_player.dart'
    show LivePlayer, PlayerSnapshot;
import '../../../platforms/common/playback/play_screen_mode.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/play_provider.dart';
import '../application/room_volume_provider.dart';
import '../application/sleep_timer_provider.dart';

class PlayerControlsBar extends ConsumerStatefulWidget {
  const PlayerControlsBar({
    super.key,
    required this.site,
    required this.roomId,
    required this.showDanmaku,
    required this.danmakuEnabled,
    required this.screenMode,
    required this.onDanmakuToggle,
    required this.onToggleWidescreen,
    required this.onToggleFullscreen,
    required this.onTogglePip,
  });

  final String site;
  final String roomId;

  /// 舞台弹幕叠加层当前是否显示(播放页本地开关)。
  final bool showDanmaku;

  /// 设置项「弹幕」总开关:决定控制条上这枚按钮是否可见。
  final bool danmakuEnabled;

  /// 当前呈现态(控制条图标/tooltip 据此切换)。
  final PlayScreenMode screenMode;

  /// 切换舞台弹幕显示。
  final VoidCallback onDanmakuToggle;

  /// 切换网页全屏(视频区占满窗口,但不请求系统窗口全屏)。
  final VoidCallback onToggleWidescreen;

  /// 切换全屏(同时请求系统窗口全屏)。
  final VoidCallback onToggleFullscreen;

  /// 切换画中画小窗。
  final VoidCallback onTogglePip;

  @override
  ConsumerState<PlayerControlsBar> createState() => _PlayerControlsBarState();
}

class _PlayerControlsBarState extends ConsumerState<PlayerControlsBar> {
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
    return Material(
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
    );
  }

  /// 控制条主行;[compact] 为 true 时隐藏音量滑杆/延迟文案/画中画/网页全屏,
  /// 只留播放/静音/画质/线路/弹幕/刷新/全屏等核心按钮。
  Widget buildRow(
    BuildContext context,
    PlayerSnapshot snapshot,
    LivePlayer player,
    bool compact,
    PlayState? play,
  ) {
    final tokens = context.tokens;
    final payload = play?.payload;
    // 布局(pure_live 同款手感):左组贴播放区左缘,右组贴播放区右缘,
    // 随播放区宽度自适应 —— 两组成两个 Align 分列 Stack 左右,互不挤占。
    // 右组顺序:画质 → 线路 → 弹幕 → PiP(!compact) → 睡眠定时(超集) →
    // 刷新 → 网页全屏(!compact) → 全屏。
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── 左组:播放/暂停 + 静音 + 音量滑杆(!compact) + 直播中文案 ──
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                    color: AppOnVideo.text,
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
                    color: AppOnVideo.text,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(width: AppSpacing.xs),
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
                        activeColor: tokens.accent,
                        // 未激活轨道在视频上需保持可见:浅色主题 border 近白
                        // 会隐形。
                        inactiveColor: AppOnVideo.textMuted,
                        onChanged: (value) {
                          unawaited(player.setVolume(value));
                          unawaited(
                            ref
                                .read(roomVolumeStoreProvider)
                                .save(
                                  site: widget.site,
                                  roomId: widget.roomId,
                                  volume: value,
                                ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── 右组:画质 → 线路 → 弹幕 → PiP → 睡眠 → 刷新 → 网页全屏 → 全屏 ──
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
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
                  const SizedBox(width: AppSpacing.xs),
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
                          ? tokens.accent
                          : AppOnVideo.textMuted,
                    ),
                  ),
                if (!compact)
                  IconButton(
                    // 测试锚点:画中画切换。
                    key: const Key('play-toggle-pip'),
                    tooltip: '画中画',
                    onPressed: widget.onTogglePip,
                    icon: Icon(
                      Icons.picture_in_picture_alt_rounded,
                      size: 20,
                      color: AppOnVideo.text,
                    ),
                  ),
                if (!compact) const _SleepTimerButton(),
                IconButton(
                  // 测试锚点:刷新视频(重开当前线路,不重解析 payload)。
                  key: const Key('play-refresh-stream'),
                  tooltip: '刷新视频',
                  onPressed: () {
                    // 复用 playControllerProvider 的 retry 通路:payload 已就位
                    // 时只 bump 代际并重新 open 当前线路(轻量重开流),不重解析
                    // 房间;仅当解析失败(payload 为 null)时 retry 才整体重解析。
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
                    color: AppOnVideo.text,
                  ),
                ),
                if (!compact)
                  IconButton(
                    // 测试锚点:网页全屏切换(视频铺满窗口,不动系统窗口)。
                    key: const Key('play-toggle-widescreen'),
                    tooltip: widget.screenMode.isWidescreen
                        ? '退出网页全屏 (W)'
                        : '网页全屏 (W)',
                    onPressed: widget.onToggleWidescreen,
                    icon: Icon(
                      widget.screenMode.isWidescreen
                          ? Icons.close_fullscreen_rounded
                          : Icons.open_in_full_rounded,
                      size: 20,
                      color: widget.screenMode.isWidescreen
                          ? tokens.accent
                          : AppOnVideo.text,
                    ),
                  ),
                IconButton(
                  // 测试锚点:全屏切换按钮。图标随呈现态切换(对齐 pure_live)。
                  key: const Key('play-toggle-fullscreen'),
                  tooltip: widget.screenMode.isFullscreen
                      ? '退出全屏 (F)'
                      : '全屏 (F)',
                  onPressed: widget.onToggleFullscreen,
                  icon: Icon(
                    widget.screenMode.isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    size: 20,
                    color: widget.screenMode.isFullscreen
                        ? tokens.accent
                        : AppOnVideo.text,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  Icon(Icons.check_rounded, size: 16, color: tokens.accent)
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
          // 窄条防护:入口包 Flexible + ellipsis(Flexible 包裹下档名过长
          // 收缩,不把控制条撑溢出)。
          Flexible(
            child: Text(
              key: const Key('play-quality-current'),
              activeQuality?.name ?? '画质',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySecondary.copyWith(
                color: AppOnVideo.textMuted,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_drop_down_rounded,
            size: 18,
            color: AppOnVideo.textMuted,
          ),
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
                  Icon(Icons.check_rounded, size: 16, color: tokens.accent)
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
          // 窄条防护:线路名同样 Flexible + ellipsis。
          Flexible(
            child: Text(
              activeLine?.name ?? '线路',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.bodySecondary.copyWith(
                color: AppOnVideo.textMuted,
              ),
            ),
          ),
          const Icon(
            Icons.arrow_drop_down_rounded,
            size: 18,
            color: AppOnVideo.textMuted,
          ),
        ],
      ),
    );
  }
}

/// 睡眠定时入口(flutter 超集,web 无对应):预设/自定义分钟后停止播放。
class _SleepTimerButton extends ConsumerWidget {
  const _SleepTimerButton();

  /// 菜单里的「自定义…」项值;预设档位为分钟数,「关闭定时」为 0。
  static const int _customValue = -1;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final timer = ref.watch(sleepTimerProvider);
    final active = timer.active;
    return PopupMenuButton<int>(
      // 测试锚点:睡眠定时入口。
      key: const Key('play-sleep-timer'),
      tooltip: active ? '睡眠定时 (剩余 ${timer.remainingLabel})' : '睡眠定时',
      padding: EdgeInsets.zero,
      onSelected: (value) {
        if (value == _customValue) {
          unawaited(_pickCustomMinutes(context, ref));
          return;
        }
        final controller = ref.read(sleepTimerProvider.notifier);
        if (value <= 0) {
          controller.cancel();
          _toast(context, '已取消睡眠定时');
          return;
        }
        controller.start(Duration(minutes: value));
        _toast(context, '已设定 $value 分钟后停止播放');
      },
      itemBuilder: (context) => [
        if (active)
          const PopupMenuItem<int>(
            key: Key('play-sleep-timer-off'),
            value: 0,
            child: Text('关闭定时'),
          ),
        for (final minutes in SleepTimerController.presetsMinutes)
          PopupMenuItem<int>(
            key: Key('play-sleep-timer-$minutes'),
            value: minutes,
            child: Text('$minutes 分钟'),
          ),
        const PopupMenuItem<int>(
          key: Key('play-sleep-timer-custom'),
          value: _customValue,
          child: Text('自定义…'),
        ),
      ],
      child: Icon(
        active ? Icons.bedtime_rounded : Icons.bedtime_outlined,
        size: 20,
        color: active ? tokens.accent : tokens.textPrimary,
      ),
    );
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  Future<void> _pickCustomMinutes(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    try {
      final minutes = await showDialog<int>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('自定义睡眠定时'),
          content: TextField(
            key: const Key('play-sleep-timer-custom-input'),
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: '分钟(1-${SleepTimerController.maxCustomMinutes})',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(dialogContext)
                      .pop(int.tryParse(controller.text.trim())),
              child: const Text('确定'),
            ),
          ],
        ),
      );
      if (minutes == null || minutes <= 0) return;
      final clamped = minutes > SleepTimerController.maxCustomMinutes
          ? SleepTimerController.maxCustomMinutes
          : minutes;
      if (!context.mounted) return;
      ref.read(sleepTimerProvider.notifier).start(Duration(minutes: clamped));
      _toast(context, '已设定 $clamped 分钟后停止播放');
    } finally {
      controller.dispose();
    }
  }
}
