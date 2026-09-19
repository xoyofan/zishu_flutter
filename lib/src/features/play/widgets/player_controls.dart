/// 播放控制条:左组[播放/暂停(快照驱动) → 刷新]紧邻成组 → 弹幕开关 →
/// 飘屏弹幕设置入口(→ 睡眠定时与「直播中·低延迟追帧中」文案,flutter 超集,
/// 置左组尾部);右组[音量静音+白系滑杆 → 画质 → 线路 → 画中画 → 网页全屏],
/// 全屏独立最右。布局基线对齐 SFVideoLive web `PlayerControls.vue` +
/// `styles/responsive-chrome.css`(.controls-bar:背景 rgba(0,0,0,.72)、
/// padding .28rem .65rem、图标 1.38rem≈22、按钮 2.55rem≈41)。
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
/// - 线路入口:`play-line-menu`(仅线路数 >1 时渲染,对齐 web `v-if="lines.length >1"`)。
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
import '../../danmaku/widgets/danmaku_settings_dialog.dart';
import '../application/play_provider.dart';
import '../application/room_volume_provider.dart';
import '../application/sleep_timer_provider.dart';

/// web `.controls-bar` 水平内边距 `.65rem`(1rem = 16px)。
const double _kBarPaddingH = 10.4;

/// web `.controls-bar` 纵向内边距 `.28rem`。
const double _kBarPaddingV = 4.5;

/// 控制按钮边长:web `2.55rem`(height/min-width)≈ 41。
const double _kControlExtent = 41;

/// 控制图标尺寸:web `--ctrl-icon-size: 1.38rem` ≈ 22。
const double _kIconSize = 22;

/// 音量滑杆宽:web `ctrl-volume-slider` 96px;窄区(≤680 容器档)52px。
const double _kVolumeSliderWidth = 96;
const double _kVolumeSliderWidthCompact = 52;

/// 画质/线路菜单弹层底色:web on-video 弹层 `rgba(20, 20, 20, .95)`。
const Color _kMenuSurface = Color(0xF2141414);

/// 控制按钮统一点击区约束(web 2.55rem 方形按钮,原 IconButton 默认 48)。
const BoxConstraints _kControlConstraints = BoxConstraints(
  minWidth: _kControlExtent,
  minHeight: _kControlExtent,
);

/// 收缩点击区:MaterialTapTargetSize.padded 会把按钮重新撑回 48×48,盖过
/// [constraints] 的 41 下限;shrinkWrap 才能让 web 2.55rem 方形按钮真正生效。
const ButtonStyle _kControlButtonStyle = ButtonStyle(
  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
);

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
  /// 飘屏弹幕设置对话框是否开着(web `danmakuSettingsOpen`):开着时设置入口
  /// 的方框边框与齿轮角标转 amber。对话框经 [showDanmakuSettingsDialog] 的
  /// Future 归还关闭时机,无需全局 provider。
  bool _danmakuSettingsOpen = false;

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
      // 收缩判据用控制条「自身可用宽」而非视口宽:宽视口也可能因常驻
      // 侧栏挤压出 ~390dp 的窄控制条(实测 800 视口 → 392dp 溢出)。
      child: LayoutBuilder(
        builder: (context, constraints) {
          final snapshot =
              ref.watch(playerSnapshotProvider).value ??
              const PlayerSnapshot();
          final player = ref.read(playerProvider);
          final compact = constraints.maxWidth < 560;
          // web `.controls-bar`:纯色底 rgba(0,0,0,.72)(on-video-bg-bar),
          // padding .28rem .65rem。播放页外层容器的旧渐变声明在 play_view.dart,
          // 由其归属轨处理;本组件只负责条自身背景。
          return Container(
            padding: const EdgeInsets.symmetric(
              horizontal: _kBarPaddingH,
              vertical: _kBarPaddingV,
            ),
            color: Colors.black.withValues(alpha: 0.72),
            child: buildRow(context, snapshot, player, compact, play),
          );
        },
      ),
    );
  }

  /// 控制条主行;[compact] 为 true 时隐藏延迟文案/画中画/网页全屏/飘屏弹幕
  /// 设置/睡眠定时与 picker 前置图标(web ≤680 容器档),音量滑杆收窄为
  /// 52px 但不再隐藏。
  Widget buildRow(
    BuildContext context,
    PlayerSnapshot snapshot,
    LivePlayer player,
    bool compact,
    PlayState? play,
  ) {
    final tokens = context.tokens;
    final payload = play?.payload;
    // 线路按钮仅在线路数 >1 时渲染(web `v-if="lines.length >1"`);
    // 选中画质未就绪(拿不到线路数)时保持现状渲染。
    final lines = play?.quality?.lines;
    return Row(
      children: [
        // ── 左组:播放/暂停 + 刷新(web el-button-group,成组紧邻)────────
        IconButton(
          // 测试锚点:播放/暂停按钮。
          key: const Key('play-toggle-play'),
          tooltip: snapshot.playing ? '暂停 (Space)' : '播放 (Space)',
          constraints: _kControlConstraints,
          style: _kControlButtonStyle,
          onPressed: () => (snapshot.playing ? player.pause() : player.play()),
          icon: Icon(
            snapshot.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            size: _kIconSize,
            color: tokens.textPrimary,
          ),
        ),
        IconButton(
          // 测试锚点:刷新视频(重开当前线路,不重解析 payload)。
          key: const Key('play-refresh-stream'),
          tooltip: '刷新视频',
          constraints: _kControlConstraints,
          style: _kControlButtonStyle,
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
            size: _kIconSize,
            color: tokens.textPrimary,
          ),
        ),
        // ── 弹幕开关 + 飘屏设置(web ctrl-danmaku-group,「弹」字方框徽标)──
        if (widget.danmakuEnabled)
          IconButton(
            // 测试锚点:舞台弹幕叠加层显隐开关。
            key: const Key('play-toggle-danmaku'),
            tooltip: widget.showDanmaku ? '隐藏弹幕' : '显示弹幕',
            constraints: _kControlConstraints,
            style: _kControlButtonStyle,
            onPressed: widget.onDanmakuToggle,
            icon: _DanmakuMark(
              size: _kIconSize,
              // 开启态 amber(含右上 √ 角标),关闭态灰(web ctrl-icon--active)。
              color: widget.showDanmaku ? tokens.brand : tokens.textSecondary,
              showCheck: widget.showDanmaku,
            ),
          ),
        // 飘屏弹幕设置入口:与侧栏设置页共用同一对话框(避免两处控件分叉),
        // 对齐 web `components/play/PlayerControls.vue:43-52` 的
        // `ctrl-danmaku-settings-btn`(title「飘屏弹幕设置」),与弹幕开关同组。
        //
        // 归入非紧凑区(compact 时不渲染):实测 360/375/393dp 手机宽度下再加
        // 一枚按钮会让控制条溢出(mobile_phones_test 的 pagesOverflowMatrix
        // 抓到过 play@AndroidSmall/iPhoneSE/iPhone15 三条 FAIL)。窄屏下弹幕样式
        // 仍可从播放页侧栏「设置」页进入(play_side_panel.dart 的同一对话框),
        // 桌面/平板则多出这条一步直达的通路。
        if (widget.danmakuEnabled && !compact)
          IconButton(
            // 测试锚点:飘屏弹幕设置(弹幕样式对话框)入口。
            key: const Key('play-danmaku-settings'),
            tooltip: '飘屏弹幕设置',
            constraints: _kControlConstraints,
            style: _kControlButtonStyle,
            onPressed: () async {
              // 打开态由本地会话态派生(web danmakuSettingsOpen):对话框
              // Future 在关闭时完成,随后复位。期间边框与齿轮角标转 amber。
              setState(() => _danmakuSettingsOpen = true);
              await showDanmakuSettingsDialog(context);
              if (mounted) setState(() => _danmakuSettingsOpen = false);
            },
            icon: _DanmakuMark(
              // 设置入口方框小一号(web 同组次级规格)。
              size: 18,
              color: tokens.textPrimary,
              gearColor: _danmakuSettingsOpen
                  ? tokens.brand
                  : tokens.textPrimary,
            ),
          ),
        // 睡眠定时:与画中画/网页全屏同属非紧凑区控件 —— 窄屏(手机竖屏)下
        // 控制条横向预算已近满(flutter 超集,置于左组尾部)。
        if (!compact) const _SleepTimerButton(),
        // 「直播中·低延迟追帧中」占位文案:吃掉左组与右组之间的弹性中段
        // (flutter 超集);紧凑区没有它,改用 Spacer 撑开左右两组。
        if (!compact)
          Expanded(
            child: Center(
              child: Text('直播中 · 低延迟追帧中', style: context.textCaption),
            ),
          )
        else
          const Spacer(),
        // ── 右组:音量(静音 + 白系滑杆)───────────────────────────────
        IconButton(
          // 测试锚点:静音切换按钮。
          key: const Key('play-toggle-mute'),
          tooltip: snapshot.muted ? '取消静音 (M)' : '静音 (M)',
          constraints: _kControlConstraints,
          style: _kControlButtonStyle,
          onPressed: () => player.setMuted(!snapshot.muted),
          icon: Icon(
            snapshot.muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            size: _kIconSize,
            color: tokens.textPrimary,
          ),
        ),
        // 音量滑杆:web 白系(runway 白 22%、填充白、thumb 14 纯白;
        // active 取纯白,简化 web 白 75%→100% 渐变)。压在控制条暗底上,
        // 浅色主题下同样成立(on-video 面永远深底)。
        SizedBox(
          width: compact ? _kVolumeSliderWidthCompact : _kVolumeSliderWidth,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 7,
                elevation: 3,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 11),
              overlayColor: Colors.white.withValues(alpha: 0.12),
            ),
            child: Slider(
              value: (snapshot.muted ? 0.0 : snapshot.volume).clamp(
                0.0,
                100.0,
              ),
              max: 100,
              activeColor: Colors.white,
              inactiveColor: Colors.white.withValues(alpha: 0.22),
              thumbColor: Colors.white,
              onChanged: (value) {
                player.setVolume(value);
                // 房间独立音量:拖动即记入本房间(键 room_vol_{site}_{roomId}),
                // 下次进同一房间按全局静音 → 房间值 → 默认音量的顺序恢复。
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
        const SizedBox(width: AppSpacing.xs),
        // ── 右组:画质 → 线路 → 画中画;全屏独立最右 ────────────────────
        // 画质/线路 selectbox:自 QualityLineBar 迁入控制栏(2026-09-11
        // 裁决)。房间未解析成功时不渲染,避免空菜单入口。两者都包 Flexible:
        // 窄控制条下由内部的档名/线路名 ellipsis 让位,保证行不溢出。
        if (payload != null) ...[
          Flexible(
            child: _QualitySelectBox(
              payload: payload,
              compact: compact,
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
          ),
          const SizedBox(width: AppSpacing.sm),
          // 线路入口:仅线路数 >1 时渲染(web 同款 v-if)。
          if (lines == null || lines.length > 1) ...[
            Flexible(
              child: _LineSelectBox(
                compact: compact,
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
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
        ],
        if (!compact)
          IconButton(
            // 测试锚点:画中画切换。
            key: const Key('play-toggle-pip'),
            tooltip: '画中画',
            constraints: _kControlConstraints,
            style: _kControlButtonStyle,
            onPressed: widget.onTogglePip,
            icon: Icon(
              Icons.picture_in_picture_alt_rounded,
              size: _kIconSize,
              color: tokens.textPrimary,
            ),
          ),
        if (!compact)
          IconButton(
            // 测试锚点:网页全屏切换(视频铺满窗口,不动系统窗口)。
            key: const Key('play-toggle-widescreen'),
            tooltip: widget.screenMode.isWidescreen ? '退出网页全屏 (W)' : '网页全屏 (W)',
            constraints: _kControlConstraints,
            style: _kControlButtonStyle,
            onPressed: widget.onToggleWidescreen,
            icon: Icon(
              widget.screenMode.isWidescreen
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              size: _kIconSize,
              color: widget.screenMode.isWidescreen
                  ? tokens.brand
                  : tokens.textPrimary,
            ),
          ),
        IconButton(
          // 测试锚点:全屏切换按钮。图标随呈现态切换(对齐 pure_live)。
          key: const Key('play-toggle-fullscreen'),
          tooltip: widget.screenMode.isFullscreen ? '退出全屏 (F)' : '全屏 (F)',
          constraints: _kControlConstraints,
          style: _kControlButtonStyle,
          onPressed: widget.onToggleFullscreen,
          icon: Icon(
            widget.screenMode.isFullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            size: _kIconSize,
            color: widget.screenMode.isFullscreen
                ? tokens.brand
                : tokens.textPrimary,
          ),
        ),
      ],
    );
  }
}

/// 画质/线路菜单选中项主体:选中档 amber 文字 + amber 14% 底、前置打勾
/// (对齐 web 弹层菜单 active 态 `color-mix(amber 12%, transparent)` 同族)。
Widget _popupItemBody(
  BuildContext context, {
  required bool selected,
  required String label,
}) {
  final tokens = context.tokens;
  return Container(
    color: selected ? tokens.brand.withValues(alpha: 0.14) : null,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (selected)
          Icon(Icons.check_rounded, size: 16, color: tokens.brand)
        else
          const SizedBox(width: 16),
        const SizedBox(width: AppSpacing.xs),
        Text(label, style: selected ? TextStyle(color: tokens.brand) : null),
      ],
    ),
  );
}

/// 画质 selectbox:入口 `settings` 前置图标 + 当前档名(`play-quality-current`),
/// 菜单项沿用 `play-quality-{name}` 锚点,选中档 amber 高亮。自 QualityLineBar 迁入。
class _QualitySelectBox extends StatelessWidget {
  const _QualitySelectBox({
    required this.payload,
    required this.compact,
    required this.activeQuality,
    required this.onQualityTap,
  });

  final RoomPayload payload;

  /// 紧凑区:隐藏前置图标(对齐 web ≤680 容器档 `.ctrl-picker-icon{display:none}`),
  /// 只留档名 + 下拉箭头。
  final bool compact;

  final StreamQuality? activeQuality;
  final ValueChanged<StreamQuality> onQualityTap;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<StreamQuality>(
      // 测试锚点:画质下拉入口。
      key: const Key('play-quality-menu'),
      tooltip: '选择画质',
      padding: EdgeInsets.zero,
      onSelected: onQualityTap,
      // 暗色皮肤:web ctrl 弹层(on-video 面板 rgba(20,20,20,.95) + 白 12% 描边)。
      color: _kMenuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: Colors.white12),
      ),
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
            child: _popupItemBody(
              context,
              selected: activeQuality?.name == option.name,
              label: option.name,
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 前置图标:对齐 web `ctrl-picker-icon`(Icon name="settings")。
          if (!compact) ...[
            const Icon(Icons.settings_rounded, size: 16),
            const SizedBox(width: 3),
          ],
          // 档名可收缩:窄控制条下 ellipsis 让位(web ≤680 档 label
          // ellipsis / ≤420 档隐藏标签的同族兜底)。
          Flexible(
            child: Text(
              // 测试锚点:菜单未打开时也暴露当前画质名,供断言口径兜底。
              key: const Key('play-quality-current'),
              activeQuality?.name ?? '画质',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: context.textSecondary,
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded, size: 18),
        ],
      ),
    );
  }
}

/// 线路 selectbox:入口 `list` 前置图标 + 当前线路名,菜单项锚点
/// `play-line-item-{name}`;仅在线路数 >1 时由外层渲染。
class _LineSelectBox extends StatelessWidget {
  const _LineSelectBox({
    required this.compact,
    required this.activeQuality,
    required this.activeLine,
    required this.onLineTap,
  });

  /// 紧凑区隐藏前置图标,语义同 [_QualitySelectBox.compact]。
  final bool compact;

  final StreamQuality? activeQuality;
  final StreamLine? activeLine;
  final ValueChanged<StreamLine> onLineTap;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<StreamLine>(
      // 测试锚点:线路下拉入口。
      key: const Key('play-line-menu'),
      tooltip: '选择线路',
      padding: EdgeInsets.zero,
      onSelected: onLineTap,
      color: _kMenuSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: const BorderSide(color: Colors.white12),
      ),
      itemBuilder: (context) => [
        for (final line in activeQuality?.lines ?? const <StreamLine>[])
          PopupMenuItem<StreamLine>(
            // 测试锚点:线路菜单项锚点。
            key: Key('play-line-item-${line.name}'),
            value: line,
            child: _popupItemBody(
              context,
              selected: activeLine?.url == line.url,
              label: line.name,
            ),
          ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!compact) ...[
            const Icon(Icons.list_rounded, size: 16),
            const SizedBox(width: 3),
          ],
          Flexible(
            child: Text(
              activeLine?.name ?? '线路',
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: context.textSecondary,
            ),
          ),
          const Icon(Icons.arrow_drop_down_rounded, size: 18),
        ],
      ),
    );
  }
}

/// 「弹」字方框徽标:对齐 web `.ctrl-danmaku-mark`(2px currentColor 边框、
/// 圆角 5、内文字 0.64em),开启态整标 amber + 右上 √ 角标,关闭态灰;
/// 齿轮角标(右下)用于飘屏设置入口(web corner--gear)。
class _DanmakuMark extends StatelessWidget {
  const _DanmakuMark({
    required this.size,
    required this.color,
    this.showCheck = false,
    this.gearColor,
  });

  /// 方框边长(web 1.08em × 1.38rem ≈ 22;设置入口小一号 ≈ 18)。
  final double size;

  /// 方框边框与「弹」字颜色。
  final Color color;

  /// 是否渲染右上 √ 角标(开启态)。
  final bool showCheck;

  /// 右下齿轮角标颜色(非 null 即渲染)。
  final Color? gearColor;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(color: color, width: 2),
            borderRadius: BorderRadius.circular(5),
          ),
          child: Text(
            '弹',
            style: TextStyle(
              fontSize: size * 0.6,
              height: 1,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
        if (showCheck)
          _DanmakuCorner(
            top: -3,
            right: -3,
            child: Text(
              '√',
              style: TextStyle(
                fontSize: 11,
                height: 1,
                fontWeight: FontWeight.w800,
                color: tokens.brand,
              ),
            ),
          ),
        if (gearColor != null)
          _DanmakuCorner(
            bottom: -3,
            right: -3,
            child: Icon(Icons.settings_rounded, size: 10, color: gearColor),
          ),
      ],
    );
  }
}

/// 角标底座:web `.ctrl-danmaku-corner`(深底 rgba(18,18,18,.92)、圆角 3、
/// 1px 黑 35% 外圈),压住方框边框保证角标可读(on-video 面,两主题同值)。
class _DanmakuCorner extends StatelessWidget {
  const _DanmakuCorner({
    this.top,
    this.right,
    this.bottom,
    required this.child,
  });

  final double? top;
  final double? right;
  final double? bottom;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: top,
      right: right,
      bottom: bottom,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 1.5, vertical: 1),
        decoration: BoxDecoration(
          color: const Color(0xEB121212),
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.35)),
          ],
        ),
        child: child,
      ),
    );
  }
}

/// 睡眠定时按钮:入口锚点 `play-sleep-timer`,菜单给预设档位 + 自定义分钟数。
///
/// 定时状态挂在应用级 `sleepTimerProvider`(非 autoDispose):离开播放页时
/// 定时不被清掉,到点才停播。本组件只负责下指令与提示,不动播放器。
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
        size: _kIconSize,
        color: active ? tokens.brand : tokens.textPrimary,
      ),
    );
  }

  /// 弹一次提示;控制条可能处于已隐藏 chrome 的态,故用页面根 Scaffold 的
  /// ScaffoldMessenger(由 MaterialApp 提供)。
  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  /// 自定义分钟数:简单数字输入对话框;取消/非法值不改变现有定时。
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
              onPressed: () => Navigator.of(
                dialogContext,
              ).pop(int.tryParse(controller.text.trim())),
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
