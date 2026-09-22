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
import '../../../shared/presentation/widgets/ambient_cta_hover.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../application/play_provider.dart';
import '../../danmaku/application/danmaku_settings_provider.dart';
import '../../danmaku/domain/danmaku_settings.dart';
import '../../../shared/presentation/widgets/compact_switch.dart';
import '../../../shared/presentation/widgets/settings_slider_row.dart';
import '../application/room_volume_provider.dart';
import '../application/sleep_timer_provider.dart';
import '../application/speech_caption_provider.dart' show supportsSpeechCaption;

/// on-video 控件的 Material 墨色(控制条压在视频画面上)。
///
/// 控制条是**恒定暗底**(`AppOnVideo` 语义),所以 hover / pressed / focus 的
/// 覆盖色也必须恒定亮色:用主题默认的 `colorScheme.onSurface` 会在浅色主题下
/// 变成**深色**覆盖层 —— 压在暗 scrim 上等于没有反馈,键盘焦点更是完全看不见
/// (Windows 键盘可达性验收项)。
///
/// `PopupMenuButton` 的 `child:` 形态内部自带 `InkWell` 且不暴露颜色参数,
/// 它的 hover/focus 只能从 Theme 层统一给,故这里同时提供 Theme 版本。
ThemeData _onVideoInkTheme(BuildContext context) => Theme.of(context).copyWith(
  hoverColor: AppOnVideo.text.withValues(alpha: 0.12),
  highlightColor: AppStateLayer.pressedOf(AppOnVideo.text),
  focusColor: AppStateLayer.focusOf(AppOnVideo.text),
  splashColor: AppStateLayer.splashOf(AppOnVideo.text),
);

/// 控制条 `IconButton` 的状态覆盖色(`IconButton` 走 `colorScheme` 默认值,
/// 不受 `Theme.hoverColor` 影响,必须逐个显式给)。
/// `animationDuration` 用 [AppMotion.fast],与全局 hover 口径一致。
ButtonStyle _onVideoButtonStyle() => ButtonStyle(
  animationDuration: AppMotion.fast,
  overlayColor: WidgetStateProperty.resolveWith<Color?>((states) {
    if (states.contains(WidgetState.focused)) {
      return AppOnVideo.text.withValues(alpha: 0.24);
    }
    if (states.contains(WidgetState.pressed)) {
      return AppOnVideo.text.withValues(alpha: 0.18);
    }
    if (states.contains(WidgetState.hovered)) {
      return AppOnVideo.text.withValues(alpha: 0.12);
    }
    return null;
  }),
);

class PlayerControlsBar extends ConsumerStatefulWidget {
  const PlayerControlsBar({
    super.key,
    required this.site,
    required this.roomId,
    required this.showDanmaku,
    required this.danmakuEnabled,
    required this.speechCaptionEnabled,
    required this.screenMode,
    required this.onDanmakuToggle,
    required this.onCaptionToggle,
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

  /// 语音字幕「译」开关(全局设置项,默认开)。
  final bool speechCaptionEnabled;

  /// 当前呈现态(控制条图标/tooltip 据此切换)。
  final PlayScreenMode screenMode;

  /// 切换舞台弹幕显示。
  final VoidCallback onDanmakuToggle;

  /// 切换语音字幕开关。
  final VoidCallback onCaptionToggle;

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
    // 控制条整体切到 on-video 墨色:hover/pressed/focus 用恒定亮色覆盖层
    // (主题默认的 onSurface 在浅色主题下是深色,压在暗 scrim 上等于无反馈)。
    return Theme(
      data: _onVideoInkTheme(context),
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

  /// 控制条主行;[compact] 为 true 时隐藏音量滑杆/延迟文案/画中画/网页全屏,
  /// 只留播放/刷新/弹幕/静音/画质/线路/全屏等核心按钮。
  Widget buildRow(
    BuildContext context,
    PlayerSnapshot snapshot,
    LivePlayer player,
    bool compact,
    PlayState? play,
  ) {
    final tokens = context.tokens;
    final payload = play?.payload;
    // 布局(用户口径 2026-09-20 重排):左组=播放/暂停 → 刷新 → 睡眠定时等
    // 低频设置 → 弹幕开关「弹」→ 飘屏弹幕设置「弹」(样式复刻 SFVideo
    // PlayerControls 的 ctrl-danmaku-group);右组=音量组靠右(静音+滑杆) →
    // 画质 → 线路 → 画中画 → 网页全屏 → 全屏(两个独立按钮保留)。
    // 两组成两个 Align 分列 Stack 左右,互不挤占。
    return SizedBox(
      height: 48,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // ── 左组:播放/暂停 → 刷新 → 睡眠 → 弹幕开关/设置 ──
          Align(
            alignment: Alignment.centerLeft,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AmbientCtaHover(
                  // 本按钮是 M3 IconButton(默认 StadiumBorder = 胶囊/圆),
                  // 流光描边必须同形,否则圆角处会露出直角(清单 2.2)。
                  borderRadius: AppRadius.allPill,
                  child: IconButton(
                    // 测试锚点:播放/暂停按钮。
                    key: const Key('play-toggle-play'),
                    style: _onVideoButtonStyle(),
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
                ),
                IconButton(
                  // 测试锚点:刷新视频(重开当前线路,不重解析 payload)。
                  key: const Key('play-refresh-stream'),
                  style: _onVideoButtonStyle(),
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
                if (!compact) const _SleepTimerButton(),
                if (widget.danmakuEnabled) ...[
                  IconButton(
                    // 测试锚点:舞台弹幕叠加层显隐开关(SFVideo「弹」方块 +
                    // 右上 √ 角标;激活色 amber,复刻 ctrl-danmaku-mark)。
                    key: const Key('play-toggle-danmaku'),
                    style: _onVideoButtonStyle(),
                    tooltip: widget.showDanmaku ? '隐藏弹幕' : '显示弹幕',
                    onPressed: widget.onDanmakuToggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: _DanmakuMark(
                      active: widget.showDanmaku,
                      corner: widget.showDanmaku
                          ? _DanmakuCorner.check
                          : _DanmakuCorner.none,
                    ),
                  ),
                  _DanmakuSettingsButton(
                    key: const Key('play-danmaku-settings'),
                    show: widget.showDanmaku,
                    onToggleShow: widget.onDanmakuToggle,
                  ),
                ],
                // 语音字幕只对 youtube/twitch/soop 生效(用户口径 2026-09-22):
                // 其余平台连入口都不出,避免误导用户以为开了会有字幕。
                if (supportsSpeechCaption(widget.site))
                  IconButton(
                    // 测试锚点:语音字幕开关(SFVideo「弹」方块同款形态,
                    // 字为「译」+ √ 角标;全局设置持久化,默认关)。
                    key: const Key('play-toggle-caption'),
                    style: _onVideoButtonStyle(),
                    tooltip: widget.speechCaptionEnabled ? '关闭语音字幕' : '开启语音字幕',
                    onPressed: widget.onCaptionToggle,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 32,
                      minHeight: 32,
                    ),
                    icon: _TranslateMark(active: widget.speechCaptionEnabled),
                  ),
              ],
            ),
          ),
          // ── 右组:音量组靠右 → 画质 → 线路 → PiP → 网页全屏 → 全屏 ──
          Align(
            alignment: Alignment.centerRight,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  // 测试锚点:静音切换按钮。
                  key: const Key('play-toggle-mute'),
                  style: _onVideoButtonStyle(),
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
                    // 真差异保留(2026-09-20 实测):局部 overlay 10 vs 全局 9
                    // 不止悬停光环——M3 Slider 的 track 左右 inset =
                    // max(overlayRadius, thumbRadius),删除局部覆盖会让
                    // track/thumb 几何整体漂移 1px,打破 play_style golden。
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
                        // 静音时滑杆归零(语义=无声);解除静音回快照值。
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
                if (!compact)
                  IconButton(
                    // 测试锚点:画中画切换。
                    key: const Key('play-toggle-pip'),
                    style: _onVideoButtonStyle(),
                    tooltip: '画中画',
                    onPressed: widget.onTogglePip,
                    icon: Icon(
                      Icons.picture_in_picture_alt_rounded,
                      size: 20,
                      color: AppOnVideo.text,
                    ),
                  ),
                if (!compact)
                  IconButton(
                    // 测试锚点:网页全屏切换(视频铺满窗口,不动系统窗口)。
                    key: const Key('play-toggle-widescreen'),
                    style: _onVideoButtonStyle(),
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
                  style: _onVideoButtonStyle(),
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

/// 「弹」字方块(SFVideo `ctrl-danmaku-mark` 复刻):正方形 + 2px 描边 +
/// 圆角,内含「弹」字;[corner] 叠加右下角标 —— 开关态为 √(amber)、设置态
/// 为齿轮,激活(开/菜单展开)时描边与内容转品牌金 amber。
enum _DanmakuCorner { none, check, gear }

class _DanmakuMark extends StatelessWidget {
  const _DanmakuMark({required this.active, this.corner = _DanmakuCorner.none});

  /// 激活(弹幕开 / 菜单展开):描边与文字转 amber(SFVideo --amber)。
  final bool active;
  final _DanmakuCorner corner;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.tokens.accent : AppOnVideo.textMuted;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            '弹',
            style: TextStyle(
              fontSize: AppFontSize.body,
              height: 1,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        if (corner == _DanmakuCorner.check)
          _DanmakuCornerBadge(
            background: const Color(0xF2121212),
            child: Text(
              '√',
              style: TextStyle(
                fontSize: AppFontSize.overline,
                height: 1,
                fontWeight: FontWeight.w800,
                color: context.tokens.accent,
              ),
            ),
          ),
        if (corner == _DanmakuCorner.gear)
          _DanmakuCornerBadge(
            background: const Color(0xF2121212),
            child: Icon(
              Icons.settings_rounded,
              size: 9,
              color: active ? context.tokens.accent : AppOnVideo.textMuted,
            ),
          ),
      ],
    );
  }
}

/// 「译」字方块(语音字幕开关;形态复刻 [_DanmakuMark]):正方形 + 2px
/// 描边 + 圆角,内含「译」字;激活(开)时右下 √ 角标、描边与文字转 amber。
class _TranslateMark extends StatelessWidget {
  const _TranslateMark({required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    final color = active ? context.tokens.accent : AppOnVideo.textMuted;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            '译',
            style: TextStyle(
              fontSize: AppFontSize.body,
              height: 1,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        if (active)
          Positioned(
            right: -3,
            bottom: -3,
            child: Container(
              width: 11,
              height: 11,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xF2121212),
                borderRadius: BorderRadius.circular(3),
                boxShadow: AppElevation.hairline,
              ),
              child: Text(
                '√',
                style: TextStyle(
                  fontSize: AppFontSize.overline,
                  height: 1,
                  fontWeight: FontWeight.w800,
                  color: context.tokens.accent,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 「弹」方块右下角标(SFVideo `ctrl-danmaku-corner`):面板底色小圆角块。
class _DanmakuCornerBadge extends StatelessWidget {
  const _DanmakuCornerBadge({required this.background, required this.child});

  final Color background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: -3,
      bottom: -3,
      child: Container(
        width: 11,
        height: 11,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(3),
          boxShadow: AppElevation.hairline,
        ),
        child: child,
      ),
    );
  }
}

/// 飘屏弹幕设置入口:「弹」方块 + 右下齿轮角标;点击向上弹出
/// [_OverlayDanmakuSettingsPanel](SFVideo OverlayDanmakuSettingsPanel 复刻:
/// 显示/透明度/字号/速度/区域)。侧栏「设置」tab 的弹幕设置是聊天侧栏的
/// 弹幕样式,与本面板(舞台飘屏弹幕)无关、互不影响。
class _DanmakuSettingsButton extends ConsumerStatefulWidget {
  const _DanmakuSettingsButton({
    super.key,
    required this.show,
    required this.onToggleShow,
  });

  /// 舞台弹幕当前显隐(与「弹」开关同一状态源)。
  final bool show;
  final VoidCallback onToggleShow;

  @override
  ConsumerState<_DanmakuSettingsButton> createState() =>
      _DanmakuSettingsButtonState();
}

class _DanmakuSettingsButtonState
    extends ConsumerState<_DanmakuSettingsButton> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(danmakuSettingsProvider);
    return MenuAnchor(
      controller: _menu,
      menuChildren: [
        // 弹幕设置 popover 恒定暗底(0xF2121212):内部 Material 控件
        // (CompactSwitch / 滑杆 / 区域 selectbox)的墨色同样切到 on-video,
        // 否则浅色主题下 hover/focus 覆盖层是深色,压在暗底上看不见。
        Theme(
          data: _onVideoInkTheme(context),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _settingsTitle(),
              _settingsRow(
                label: '显示',
                // 开关大小对齐侧栏「聊天弹幕」开关(全局 CompactSwitch 30×16)。
                trailing: CompactSwitch(
                  value: widget.show,
                  onChanged: (_) => widget.onToggleShow(),
                ),
              ),
              SettingsSliderRow(
                // popover 恒定暗底(0xF2121212):标签用 AppOnVideo 亮色。
                onVideo: true,
                label: '透明度',
                value: settings.opacity.toDouble(),
                min: DanmakuSettings.kOpacityMin.toDouble(),
                max: DanmakuSettings.kOpacityMax.toDouble(),
                divisions:
                    DanmakuSettings.kOpacityMax - DanmakuSettings.kOpacityMin,
                display: '${settings.opacity}%',
                onChanged: (v) => ref
                    .read(danmakuSettingsProvider.notifier)
                    .setOpacity(v.round()),
              ),
              SettingsSliderRow(
                onVideo: true,
                label: '字号',
                value: settings.fontSize.toDouble(),
                min: DanmakuSettings.kFontSizeMin.toDouble(),
                max: DanmakuSettings.kFontSizeMax.toDouble(),
                divisions:
                    DanmakuSettings.kFontSizeMax - DanmakuSettings.kFontSizeMin,
                display: '${settings.fontSize}',
                onChanged: (v) => ref
                    .read(danmakuSettingsProvider.notifier)
                    .setFontSize(v.round()),
              ),
              SettingsSliderRow(
                onVideo: true,
                label: '速度',
                value: settings.speed.toDouble(),
                min: DanmakuSettings.kSpeedMin.toDouble(),
                max: DanmakuSettings.kSpeedMax.toDouble(),
                divisions:
                    DanmakuSettings.kSpeedMax - DanmakuSettings.kSpeedMin,
                display: '${settings.speed}',
                onChanged: (v) => ref
                    .read(danmakuSettingsProvider.notifier)
                    .setSpeed(v.round()),
              ),
              _settingsAreaRow(
                current: settings.displayAreaRatio,
                onPick: (v) => ref
                    .read(danmakuSettingsProvider.notifier)
                    .setDisplayAreaRatio(v),
              ),
            ],
          ),
        ),
      ],
      style: MenuStyle(
        alignment: Alignment.topCenter,
        backgroundColor: const WidgetStatePropertyAll(Color(0xF2121212)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        ),
      ),
      builder: (context, controller, child) {
        final open = controller.isOpen;
        return IconButton(
          // key 挂在外层 _DanmakuSettingsButton 上(勿在此重复)。
          tooltip: '飘屏弹幕设置',
          // 控制条内按钮统一 on-video 墨色(hover/pressed/focus)。
          style: _onVideoButtonStyle(),
          onPressed: () =>
              (controller.isOpen ? controller.close() : controller.open()),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: _DanmakuMark(active: open, corner: _DanmakuCorner.gear),
        );
      },
      child: const SizedBox.shrink(),
    );
  }

  Widget _settingsTitle() => Container(
    width: double.infinity,
    padding: const EdgeInsets.only(bottom: 4),
    margin: const EdgeInsets.only(bottom: 6),
    decoration: const BoxDecoration(
      border: Border(bottom: BorderSide(color: Color(0x1FFFFFFF))),
    ),
    child: Text(
      '飘屏弹幕',
      style: TextStyle(
        fontSize: AppFontSize.bodySecondary,
        fontWeight: FontWeight.w600,
        color: context.tokens.accent,
      ),
    ),
  );

  Widget _settingsRow({
    required String label,
    Widget? slider,
    Widget? trailing,
  }) => SizedBox(
    width: 216,
    child: Row(
      children: [
        SizedBox(
          width: 38,
          child: Text(
            label,
            style: TextStyle(
              fontSize: AppControls.labelFontSize,
              color: AppOnVideo.textMuted,
            ),
          ),
        ),
        if (slider != null)
          Expanded(child: slider)
        else ...[
          const SizedBox(width: 8),
          trailing ?? const SizedBox.shrink(),
        ],
        if (slider != null) ...[
          const SizedBox(width: 6),
          trailing ?? const SizedBox.shrink(),
        ],
      ],
    ),
  );

  Widget _settingsAreaRow({
    required double current,
    required ValueChanged<double> onPick,
  }) => SizedBox(
    width: 216,
    child: Row(
      children: [
        const SizedBox(
          width: 38,
          child: Text(
            '区域',
            style: TextStyle(
              fontSize: AppControls.labelFontSize,
              color: AppOnVideo.textMuted,
            ),
          ),
        ),
        const Spacer(),
        PopupMenuButton<double>(
          initialValue: current,
          tooltip: '弹幕显示区域',
          onSelected: onPick,
          itemBuilder: (context) => [
            for (final (label, ratio) in const [
              ('全屏', 1.0),
              ('3/4', 0.75),
              ('半屏', 0.5),
              ('1/4', 0.25),
            ])
              PopupMenuItem<double>(
                value: ratio,
                child: Row(
                  children: [
                    if (current == ratio)
                      Icon(
                        Icons.check_rounded,
                        size: 16,
                        color: context.tokens.accent,
                      )
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: AppSpacing.xs),
                    Text(label),
                  ],
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: AppOnVideo.textMuted),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  switch (current) {
                    0.75 => '3/4',
                    0.5 => '半屏',
                    0.25 => '1/4',
                    _ => '全屏',
                  },
                  style: const TextStyle(
                    fontSize: AppFontSize.caption,
                    color: AppOnVideo.text,
                  ),
                ),
                const Icon(
                  Icons.arrow_drop_down_rounded,
                  size: 16,
                  color: AppOnVideo.textMuted,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
