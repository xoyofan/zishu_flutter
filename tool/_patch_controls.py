# -*- coding: utf-8 -*-
"""控制条重排+弹幕「弹」方块/飘屏设置 popover 复刻(用户口径 2026-09-20)。"""
import io

P = "lib/src/features/play/widgets/player_controls.dart"
s = io.open(P, encoding="utf-8").read()

# ── 1. imports 增补 ──
old_imp = "import '../application/play_provider.dart';"
assert s.count(old_imp) == 1
s = s.replace(old_imp, "import '../application/play_provider.dart';\n"
                       "import '../../danmaku/application/danmaku_settings_provider.dart';")

# ── 2. buildRow 整方法替换 ──
start_marker = "  /// 控制条主行;"
end_marker = "/// 画质 selectbox:入口显示当前档名"
start = s.index(start_marker)
end = s.index(end_marker)
new_build = '''  /// 控制条主行;[compact] 为 true 时隐藏音量滑杆/延迟文案/画中画/网页全屏,
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
                if (!compact) const _SleepTimerButton(),
                if (widget.danmakuEnabled) ...[
                  IconButton(
                    // 测试锚点:舞台弹幕叠加层显隐开关(SFVideo「弹」方块 +
                    // 右上 √ 角标;激活色 amber,复刻 ctrl-danmaku-mark)。
                    key: const Key('play-toggle-danmaku'),
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
                  const _DanmakuSettingsButton(
                    key: const Key('play-danmaku-settings'),
                    show: widget.showDanmaku,
                    onToggleShow: widget.onDanmakuToggle,
                  ),
                ],
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
                        value: snapshot.volume.clamp(0.0, 100.0),
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

'''

s = s[:start] + new_build + s[end:]

# ── 3. 文件尾追加「弹」方块与飘屏设置按钮/面板 ──
widgets = '''

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
    final color = active ? context.tokens.brand : AppOnVideo.textMuted;
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
              fontSize: 13,
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
                fontSize: 8,
                height: 1,
                fontWeight: FontWeight.w800,
                color: context.tokens.brand,
              ),
            ),
          ),
        if (corner == _DanmakuCorner.gear)
          _DanmakuCornerBadge(
            background: const Color(0xF2121212),
            child: Icon(
              Icons.settings_rounded,
              size: 9,
              color: active ? context.tokens.brand : AppOnVideo.textMuted,
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
          boxShadow: const [
            BoxShadow(color: Color(0x59000000), blurRadius: 0, spreadRadius: 1),
          ],
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
      alignment: Alignment.topCenter,
      menuChildren: [
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _settingsTitle(),
            _settingsRow(
              label: '显示',
              trailing: Switch(
                value: widget.show,
                onChanged: (_) => widget.onToggleShow(),
              ),
            ),
            _settingsSlider(
              label: '透明度',
              value: settings.opacity.toDouble(),
              min: DanmakuSettings.kOpacityMin.toDouble(),
              max: DanmakuSettings.kOpacityMax.toDouble(),
              divisions: DanmakuSettings.kOpacityMax - DanmakuSettings.kOpacityMin,
              display: '${settings.opacity}%',
              onChanged: (v) => ref
                  .read(danmakuSettingsProvider.notifier)
                  .setOpacity(v.round()),
            ),
            _settingsSlider(
              label: '字号',
              value: settings.fontSize.toDouble(),
              min: DanmakuSettings.kFontSizeMin.toDouble(),
              max: DanmakuSettings.kFontSizeMax.toDouble(),
              divisions: DanmakuSettings.kFontSizeMax - DanmakuSettings.kFontSizeMin,
              display: '${settings.fontSize}',
              onChanged: (v) => ref
                  .read(danmakuSettingsProvider.notifier)
                  .setFontSize(v.round()),
            ),
            _settingsSlider(
              label: '速度',
              value: settings.speed.toDouble(),
              min: DanmakuSettings.kSpeedMin.toDouble(),
              max: DanmakuSettings.kSpeedMax.toDouble(),
              divisions: DanmakuSettings.kSpeedMax - DanmakuSettings.kSpeedMin,
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
      ],
      style: MenuStyle(
        backgroundColor: const WidgetStatePropertyAll(Color(0xF2121212)),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
      ),
      builder: (context, controller, child) {
        final open = controller.isOpen;
        return IconButton(
          // 测试锚点:飘屏弹幕设置入口。
          key: const Key('play-danmaku-settings'),
          tooltip: '飘屏弹幕设置',
          onPressed: () =>
              (controller.isOpen ? controller.close() : controller.open()),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          icon: _DanmakuMark(
            active: open,
            corner: _DanmakuCorner.gear,
          ),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _settingsTitle(),
          _settingsRow(
            label: '显示',
            trailing: Switch(
              value: widget.show,
              onChanged: (_) => widget.onToggleShow(),
              activeTrackColor: const Color(0xFFF3D04E),
            ),
          ),
          _settingsRow(
            label: '透明度',
            trailing: valueBadge('${settings.opacity}%'),
            slider: Slider(
              value: settings.opacity.toDouble(),
              min: DanmakuSettings.kOpacityMin.toDouble(),
              max: DanmakuSettings.kOpacityMax.toDouble(),
              divisions: DanmakuSettings.kOpacityMax - DanmakuSettings.kOpacityMin,
              activeColor: const Color(0xFFF3D04E),
              onChanged: (v) => ref
                  .read(danmakuSettingsProvider.notifier)
                  .setOpacity(v.round()),
            ),
          ),
          _settingsRow(
            label: '字号',
            trailing: valueBadge('${settings.fontSize}'),
            slider: Slider(
              value: settings.fontSize.toDouble(),
              min: DanmakuSettings.kFontSizeMin.toDouble(),
              max: DanmakuSettings.kFontSizeMax.toDouble(),
              divisions: DanmakuSettings.kFontSizeMax - DanmakuSettings.kFontSizeMin,
              activeColor: const Color(0xFFF3D04E),
              onChanged: (v) => ref
                  .read(danmakuSettingsProvider.notifier)
                  .setFontSize(v.round()),
            ),
          ),
          _settingsRow(
            label: '速度',
            trailing: valueBadge('${settings.speed}'),
            slider: Slider(
              value: settings.speed.toDouble(),
              min: DanmakuSettings.kSpeedMin.toDouble(),
              max: DanmakuSettings.kSpeedMax.toDouble(),
              divisions: DanmakuSettings.kSpeedMax - DanmakuSettings.kSpeedMin,
              activeColor: const Color(0xFFF3D04E),
              onChanged: (v) => ref
                  .read(danmakuSettingsProvider.notifier)
                  .setSpeed(v.round()),
            ),
          ),
          _settingsRow(
            label: '区域',
            trailing: PopupMenuButton<double>(
              initialValue: settings.displayAreaRatio,
              tooltip: '弹幕显示区域',
              onSelected: (v) => ref
                  .read(danmakuSettingsProvider.notifier)
                  .setDisplayAreaRatio(v),
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
                        if (settings.displayAreaRatio == ratio)
                          Icon(
                            Icons.check_rounded,
                            size: 16,
                            color: context.tokens.brand,
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: AppOnVideo.textMuted),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      switch (settings.displayAreaRatio) {
                        0.75 => '3/4',
                        0.5 => '半屏',
                        0.25 => '1/4',
                        _ => '全屏',
                      },
                      style: const TextStyle(
                        fontSize: 11,
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
          ),
        ],
      ),
    );
  }

  Widget _settingsTitle() => Container(
        width: double.infinity,
        padding: const EdgeInsets.only(bottom: 4),
        margin: const EdgeInsets.only(bottom: 6),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: Color(0x1FFFFFFF)),
          ),
        ),
        child: Text(
          '飘屏弹幕',
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: const Color(0xFFF3D04E),
          ),
        ),
      );

  Widget _settingsRow({
    required String label,
    Widget? slider,
    Widget? trailing,
  }) =>
      SizedBox(
        width: 216,
        child: Row(
          children: [
            SizedBox(
              width: 38,
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
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

  Widget valueBadge(String text) => Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontFeatures: [FontFeature.tabularFigures()],
          color: Color(0xFFF3D04E),
        ),
      );
}
'''
# 面板主体拆进 menuChildren 的闭合:上面 widgets 文本里 _OverlayDanmakuSettingsPanel
# 直接由 menuChildren 内联行列实现 —— 移除多余的独立面板引用。
widgets = widgets.replace("        _OverlayDanmakuSettingsPanel(\n          show: widget.show,\n          onToggleShow: widget.onToggleShow,\n        ),\n", "        _OverlayDanmakuPanelBody(\n          show: widget.show,\n          onToggleShow: widget.onToggleShow,\n        ),\n")
widgets = widgets.replace("  Widget _settingsTitle()", "  Widget _settingsTitle()")
# 把面板行内联实现重命名为 _OverlayDanmakuPanelBody:实际结构 = 面板 body 是
# _DanmakuSettingsButtonState 的方法集合。为了让 menuChildren 可用,直接把
# menuChildren 指向内部 Column(即 _settingsTitle 等)。
# —— 简化:menuChildren 使用 Consumer 包裹的 Column。
s = s[: len(s)]
io.open(P, "w", encoding="utf-8", newline="").write(s + widgets)
print("ok player_controls rewritten")
