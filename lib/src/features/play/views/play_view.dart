import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show DanmakuMessage, RoomPayload;

import '../../../platforms/common/playback/idle_releasing_live_player.dart';
import '../../../platforms/common/playback/live_player.dart'
    show PlayerSnapshot, PlaybackNotice;
import '../../../platforms/common/playback/playback_retry.dart'
    show retryProgressLabel;
import '../../../shared/domain/category_display.dart';
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/category_colors.dart';
import '../../../shared/presentation/widgets/platform_icon.dart';
import '../../../shared/presentation/widgets/retry_button.dart';
import '../../../shared/presentation/widgets/translated_text.dart';
import '../../../shared/application/global_actions.dart';
import '../../../shared/application/translation/translation_provider.dart';
import '../../browse/application/my_category_provider.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../danmaku/application/danmaku_session_provider.dart'
    show DanmakuChatState, danmakuSessionProvider;
import '../../danmaku/application/danmaku_settings_provider.dart';
import '../../danmaku/application/danmaku_tail_forwarder.dart';
import '../../danmaku/widgets/danmaku_overlay.dart';
import '../application/play_provider.dart';
import '../application/play_screen_provider.dart';
import '../application/sleep_timer_provider.dart';
import '../application/speech_caption_provider.dart';
import '../../follow/application/settings_provider.dart';
import '../widgets/caption_overlay.dart'
    show CaptionDownloadAction, CaptionDownloadDialog, CaptionOverlay;
import '../widgets/pip_surface.dart';
import '../widgets/play_immersive_side_sheet.dart';
import '../widgets/play_side_panel.dart';
import '../widgets/player_controls.dart';

/// 播放页(U5 布局基线,2026-09-18 改左右布局):左列 = 44px 房间头(标题) +
/// 视频舞台/控制条/画质线路条;右列 = 侧栏全高(268/328/392/425 按视口分档)。
/// 编排全部收敛在 playControllerProvider/LivePlayer,
/// Widget 只消费状态与接口,不直接触碰 media_kit。
///
/// 呈现态(normal / widescreen / fullscreen / PiP)由 [playScreenProvider] 单一
/// 维护:布局、控制条图标、自动隐藏、快捷键与平台窗口调用全部由它派生。
/// 旧实现把沉浸态放在页面本地 bool、窗口全屏放在播放器里,两边互不感知,
/// 是全屏按钮与 F 键错位的根因(见 play_screen_provider.dart 顶部说明)。
class PlayView extends ConsumerStatefulWidget {
  const PlayView({super.key, required this.site, required this.roomId});

  final String site;
  final String roomId;

  @override
  ConsumerState<PlayView> createState() => _PlayViewState();
}

class _PlayViewState extends ConsumerState<PlayView> {
  late final PlayParams _params = (site: widget.site, roomId: widget.roomId);
  bool _sidePanelVisible = true;

  /// 舞台宿主键:沉浸态切换时舞台会在 Row/Column 与全屏 SizedBox 间换位,
  /// 用 GlobalKey 保活元素与内部焦点节点,使快捷键在进出全屏后仍可达。
  final GlobalKey _stageKey = GlobalKey(debugLabel: 'play-stage-host');

  /// 呈现态控制器(三态 + PiP)。initState 取一次:dispose 期不再经过 ref,
  /// 规避"离开页面时读已销毁 provider"的风险。
  late final PlayScreenController _screen;

  /// 控制条是否可见:隐藏 chrome 的呈现态下鼠标静止 ~3s 后淡出,移动/悬停即
  /// 显示;常规态恒为可见。
  bool _controlsVisible = true;

  /// 控制条自动隐藏计时器(仅 [PlayScreenState.hidesChrome] 态生效)。
  Timer? _hideTimer;

  /// 鼠标是否停在控制条上:停靠期间不进入隐藏倒计时(对齐参考实现的
  /// `_isMouseOverController`),避免鼠标还在按钮上时控制条自己消失。
  bool _hoveringControls = false;

  /// 沉浸态右缘侧抽屉是否展开(web `immersiveSideOpen`)。
  bool _immersiveSideOpen = false;

  /// 沉浸态右缘热区防抖锁(web `lockImmersiveSide`,IMMERSIVE_SIDE_LOCK_MS
  /// = 720):进入沉浸态瞬间锁死,防止紧接的点击误开抽屉。
  ///
  /// 用「bool + Timer」而非 DateTime 截止值:widget 测试的 pump 推进的是
  /// FakeAsync 时钟,真实 `DateTime.now()` 不会走,锁会永远解不开。
  bool _immersiveSideLocked = false;
  Timer? _immersiveSideLockTimer;

  /// 抽屉自动收起计时(web `scheduleHideImmersiveSide`,
  /// IMMERSIVE_SIDE_IDLE_MS = 3000)。
  Timer? _immersiveSideHideTimer;

  @override
  void initState() {
    super.initState();
    _screen = ref.read(playScreenProvider.notifier);
    // Esc 走全局键盘 handler(见 _onGlobalKey),与 Space/M/F/W 的
    // CallbackShortcuts 分工:字母键尊重输入框焦点,Esc 必须不依赖焦点。
    HardwareKeyboard.instance.addHandler(_onGlobalKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onGlobalKey);
    GlobalActions.unregister(GlobalActionNames.refreshPlay, owner: this);
    _hideTimer?.cancel();
    _immersiveSideLockTimer?.cancel();
    _immersiveSideHideTimer?.cancel();
    // 窗口呈现(全屏/PiP)的复位由 playScreenProvider 的 onDispose 负责
    // (autoDispose:离开播放页即触发),此处不再手动调用,避免与 provider
    // 销毁时序打架——旧做法在 dispose 期走 ref,会撞上"provider 已销毁"。
    super.dispose();
  }

  /// F5 刷新播放页:与控制条「刷新视频」同通路 —— retry(payload 已就位时
  /// bump 代际并重开当前线路;解析失败才整体重解析)。
  void _refreshStream() {
    ref.read(playControllerProvider(_params).notifier).retry();
  }

  /// 返回上一页。
  ///
  /// 正常路径栈里必有上一层(浏览页/壳层);仅当播放页处于栈底(深链直达、
  /// 或壳层被 `go` 重置的历史遗留)时退化为回该平台首页 —— 无条件 pop 会让
  /// go_router 抛出 `GoError: There is nothing to pop`,按钮表现为"点了没反应"。
  void _goBack() {
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    router.go(
      PlatformBrandCatalog.supportsBrowse(widget.site)
          ? '/${widget.site}'
          : '/all',
    );
  }

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

  void _toggleMuted() {
    final snapshot =
        ref.read(playerSnapshotProvider).value ?? const PlayerSnapshot();
    ref.read(playerProvider).setMuted(!snapshot.muted);
  }

  /// 切换全屏:呈现态由 provider 单源维护,系统窗口全屏是它的下游副作用。
  /// 按钮 / F 键 / Esc 全部走这一条通路,不再有"本地沉浸态"与"平台全屏"
  /// 两条互不感知的分支。
  void _toggleFullscreen() => unawaited(_screen.toggleFullscreen());

  /// 网页全屏:视频区占满窗口,但不请求系统窗口全屏。
  void _toggleWidescreen() => unawaited(_screen.toggleWidescreen());

  /// 画中画小窗切换。
  void _togglePip() => unawaited(_screen.togglePip());

  /// 切换字幕开关;首次开启先询问是否下载模型。
  Future<void> _toggleSpeechCaption() async {
    final settings = ref.read(settingsProvider);
    if (settings.speechCaptionEnabled) {
      await ref.read(settingsProvider.notifier).setSpeechCaptionEnabled(false);
      return;
    }
    // 不支持的站点没有语言先验(控制条也不出按钮),这里兼作双保险。
    final language = speechLanguageForSite(widget.site);
    if (language == null) return;
    final manager = ref.read(speechModelManagerProvider);
    final info = manager.inspect(language);
    if (!mounted) return;
    final action = await showDialog<CaptionDownloadAction>(
      context: context,
      builder: (context) =>
          CaptionDownloadDialog(language: language, info: info),
    );
    if (!mounted || action == null) return;
    if (action == CaptionDownloadAction.download) {
      await ref.read(settingsProvider.notifier).setSpeechCaptionEnabled(true);
    }
  }

  /// 全局键盘 handler:**只接管 Esc**,其余键一律放行。
  ///
  /// 职责必须与 `CallbackShortcuts` 严格分工、互不重叠 ——
  /// `HardwareKeyboard.addHandler` 注册的 handler 由 `DispatchKeyMessage` 在
  /// **焦点树之前**无条件调用,而调用结果**不会**阻止事件继续流向
  /// `FocusManager`(见 hardware_keyboard.dart 的 handleRawKeyMessage:
  /// `handled = _dispatchKeyMessage(...) || handled`)。因此若这里也处理
  /// Space/M/F/W,同一次按键会被"全局 handler + 页面 CallbackShortcuts"
  /// 各处理一遍:F 会 enter 又立即 exit(=没切)、Space 会 toggle 两次(=没动)。
  ///
  /// 为什么只有 Esc 走全局:`Shortcuts` 沿焦点链由内向外查找,焦点残留在已隐藏
  /// 的侧栏输入框或页面之外时会漏键,而 Esc 必须"随时可退出全屏"。字母/空格键
  /// 则必须留在焦点树内,否则焦点在聊天输入框时打字会被抢(参考实现同样只把
  /// Escape 放进 addHandler,见 pure_live video_keyboard.dart:31-62)。
  bool _onGlobalKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    // 常规态放行:不打扰输入框与路由自身的 Esc 语义。
    if (!ref.read(playScreenProvider).hidesChrome) return false;
    unawaited(_screen.handleEscape());
    return true;
  }

  /// 控制条唤醒:取消隐藏计时、立即可见,隐藏 chrome 态下重新排程自动隐藏。
  void _wakeControls() {
    _hideTimer?.cancel();
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  /// 鼠标进入控制条:停靠期间不排程隐藏。
  void _enterControls() {
    _hoveringControls = true;
    _wakeControls();
  }

  /// 鼠标离开控制条:恢复隐藏倒计时。
  void _exitControls() {
    _hoveringControls = false;
    _scheduleHideControls();
  }

  /// 排程 3s 后淡出控制条。仅隐藏 chrome 的呈现态生效;鼠标停在控制条上或
  /// 已回到常规态时不排程。
  void _scheduleHideControls() {
    _hideTimer?.cancel();
    if (!ref.read(playScreenProvider).hidesChrome || _hoveringControls) {
      return;
    }
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _controlsVisible) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  /// 沉浸态切换的抽屉联动(web enterImmersiveLayout/onFullscreenChange):
  /// 进入或退出沉浸态都强制关抽屉;进入时加 720ms 防抖锁。
  void _onChromeVisibilityChanged(bool hidesChrome) {
    _immersiveSideHideTimer?.cancel();
    if (_immersiveSideOpen) setState(() => _immersiveSideOpen = false);
    if (hidesChrome) {
      _immersiveSideLocked = true;
      _immersiveSideLockTimer?.cancel();
      _immersiveSideLockTimer = Timer(const Duration(milliseconds: 720), () {
        if (mounted) _immersiveSideLocked = false;
      });
    } else {
      _immersiveSideLocked = false;
      _immersiveSideLockTimer?.cancel();
    }
  }

  /// 打开沉浸抽屉(web `openImmersiveSidePanel`):锁内拒绝;打开即藏控制条
  /// (`showControls = false` + 清控制条计时),并启动 3s 自动收起。
  void _openImmersiveSide() {
    if (_immersiveSideLocked) return;
    _immersiveSideHideTimer?.cancel();
    if (!_immersiveSideOpen) setState(() => _immersiveSideOpen = true);
    _hideTimer?.cancel();
    if (_controlsVisible) setState(() => _controlsVisible = false);
    _scheduleImmersiveSideHide();
  }

  /// 关闭沉浸抽屉(web watch(immersiveSideOpen) 的 else 分支):任何途径的
  /// 关闭(背景/toggle/超时)在沉浸态下都同时唤醒控制条(revealControls)。
  void _closeImmersiveSide() {
    _immersiveSideHideTimer?.cancel();
    if (!_immersiveSideOpen) return;
    setState(() => _immersiveSideOpen = false);
    _wakeControls();
  }

  /// 排程 3s 无交互自动收起抽屉(web `scheduleHideImmersiveSide`)。
  void _scheduleImmersiveSideHide() {
    _immersiveSideHideTimer?.cancel();
    _immersiveSideHideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) _closeImmersiveSide();
    });
  }

  /// 沉浸态舞台点击分流(web `onPlayFrameClick` 的沉浸分支):
  /// - 抽屉开着 → 点背景关闭 + 唤醒控制条;
  /// - 点击落在右缘热区(x/width ≥ 2/3,`PLAY_IMMERSIVE_TAP_ZONE`)→ 开抽屉;
  /// - 其余 → 仅唤醒控制条。
  ///
  /// 沉浸态下点击**不切换播放/暂停**(web 同一分支直接 return)。
  void _onImmersiveFrameTapUp(Offset localPosition) {
    if (_immersiveSideOpen) {
      _closeImmersiveSide();
      return;
    }
    final box = _stageKey.currentContext?.findRenderObject() as RenderBox?;
    final width = box?.size.width ?? 0;
    final zone = localPosition.dx / (width <= 0 ? 1 : width);
    if (zone >= 2 / 3) {
      _openImmersiveSide();
    } else {
      _wakeControls();
    }
  }

  /// 侧栏状态条的真实播放状态(用户口径 2026-09-20:暂停要显示「已暂停」,
  /// 不再写死「播放中」)。响应性由 build 内对 playerSnapshotProvider 的
  /// watch 提供;sheet 回调等非 build 路径取当前值即可。
  PlaybackStatus get _sidePanelPlaybackStatus {
    final snapshot =
        ref.read(playerSnapshotProvider).value ?? const PlayerSnapshot();
    return PlaybackStatus(playing: snapshot.playing, muted: snapshot.muted);
  }

  /// 横屏手机:侧栏以底部 sheet 滑出(sheet 宽近全屏,满足 W12 sheet 形态)。
  Future<void> _showSidePanelSheet(RoomPayload? payload) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.sizeOf(sheetContext).height * 0.72,
        decoration: BoxDecoration(
          color: context.tokens.surface,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: PlaySidePanel(
          site: widget.site,
          roomId: widget.roomId,
          payload: payload,
          playbackStatus: _sidePanelPlaybackStatus,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // 注册 F5 刷新(builder 层快捷键经此落地,注销随本 State dispose):
    // 与控制条「刷新视频」同通路(retry —— payload 就位时轻量重开当前线路)。
    GlobalActions.register(
      GlobalActionNames.refreshPlay,
      owner: this,
      action: _refreshStream,
    );
    // 订阅播放快照:播放/暂停/静音变化实时刷新侧栏状态条。
    ref.watch(playerSnapshotProvider);
    final async = ref.watch(playControllerProvider(_params));
    final play = async.value;
    // 设置项「弹幕」总开关:关闭时控制条的弹幕按钮整体隐藏。
    final danmakuEnabled = ref.watch(
      settingsProvider.select((settings) => settings.danmakuEnabled),
    );
    final speechCaptionEnabled = ref.watch(
      settingsProvider.select((settings) => settings.speechCaptionEnabled),
    );
    // 舞台弹幕叠加层显隐:控制条按钮/后续快捷键切换(不进设置持久化)。
    final showDanmaku = play?.showDanmaku ?? true;
    // 睡眠定时:app 级 provider(不随播放页 autoDispose),这里只读剩余时间
    // 与到点次数。
    final sleepTimer = ref.watch(sleepTimerProvider);
    ref.listen<int>(sleepTimerProvider.select((state) => state.firedCount), (
      previous,
      next,
    ) {
      // 到点即停播(由 controller 完成),这里只负责告知用户"是被定时停的"。
      if (previous == null || next <= previous) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          const SnackBar(
            content: Text('睡眠定时已到，已停止播放'),
            duration: Duration(seconds: 3),
          ),
        );
    });
    final brand = PlatformBrandCatalog.byId(widget.site);
    final size = MediaQuery.sizeOf(context);
    // 呈现态(三态 + PiP):布局、控制条图标、自动隐藏、快捷键的唯一依据。
    final screen = ref.watch(playScreenProvider);
    // 呈现态切换时同步控制条可见性:进入隐藏 chrome 的态立即显示并起 3s 倒计时;
    // 回到常规态则恒显。用 listen 而非在 build 里做副作用。
    ref.listen<PlayScreenState>(playScreenProvider, (previous, next) {
      if (previous?.hidesChrome == next.hidesChrome &&
          previous?.pip == next.pip) {
        return;
      }
      _hoveringControls = false;
      _hideTimer?.cancel();
      // 沉浸态切换时联动右缘抽屉(强制关 + 进入时 720ms 防抖锁)。
      _onChromeVisibilityChanged(next.hidesChrome);
      if (!_controlsVisible) setState(() => _controlsVisible = true);
      _scheduleHideControls();
    });
    // U9 响应式:
    // - 窄屏(<768):328px 信息栏堆叠到视频区下方,否则固定宽侧栏会把
    //   视频舞台挤成 0 宽(实测 360dp 下只剩 3dp);
    // - 横屏手机(宽>=768 且高<600):侧栏不再以 328px 常驻右栏存在,
    //   经 play-side-panel-toggle 以底部 sheet 滑出(W12 横屏验收口径)。
    final stackSidePanel = size.width < AppBreakpoints.phone;
    final isLandscapePhone =
        size.width >= AppBreakpoints.phone && size.height < 600;
    final showPanel = _sidePanelVisible && !isLandscapePhone;
    // 侧栏宽度按视口分档(268/328/392/425),对齐 main.css:228-244。
    final sidePanelWidth = AppSpacing.playSidePanelWidthFor(size.width);
    // 舞台圆角(web `.play-frame` 12px,≤640 为 0;沉浸铺满态不裁)。
    final stageRadius = BorderRadius.circular(
      size.width < AppBreakpoints.compact ? 0 : 12,
    );
    Widget stageInFrame(Widget child) =>
        ClipRRect(borderRadius: stageRadius, child: child);

    // 舞台整块挂 MouseRegion:鼠标在视频任意位置移动都唤醒控制条(隐藏
    // chrome 态下重新排程自动隐藏),这是"淡出后移动鼠标即唤出"的入口。
    //
    // 快捷键分工(两者必须互不重叠,否则同一次按键会被处理两遍):
    // - Space / M / F / W → 本 `CallbackShortcuts`,沿焦点链查找;焦点在舞台或
    //   控制条内(同为舞台子树)时可达,且焦点在聊天输入框时会被输入框先消费,
    //   不会抢打字。控制条**不再**内联自己的一份绑定:那会让内层先命中,F 键
    //   只切窗口不进沉浸态(旧实现的病灶)。
    // - Esc → 全局 handler [_onGlobalKey],不依赖焦点,只 4 个键之外的键都放行。
    final stage = MouseRegion(
      onHover: (_) => _wakeControls(),
      child: CallbackShortcuts(
        key: _stageKey,
        bindings: {
          const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
          const SingleActivator(LogicalKeyboardKey.keyM): _toggleMuted,
          const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
          const SingleActivator(LogicalKeyboardKey.keyW): _toggleWidescreen,
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            _VideoStage(
              async: async,
              showDanmaku: showDanmaku,
              onRetry: () =>
                  ref.read(playControllerProvider(_params).notifier).retry(),
              // 沉浸态下舞台点击走「控制条/抽屉」分流,不切播放
              // (web onPlayFrameClick 沉浸分支);常规态保持切播放。
              onFrameTapUp: screen.hidesChrome ? _onImmersiveFrameTapUp : null,
            ),
            // 弹幕叠加层:位于视频之上、控制条之下(参考 play 布局层级)。
            // 与右侧侧栏聊天共用 danmakuSessionProvider 的同一会话,不重复建连。
            _DanmakuLayer(
              site: widget.site,
              roomId: widget.roomId,
              visible: showDanmaku && danmakuEnabled,
            ),
            // 语音字幕条:控制栏上方一点,不随控制栏淡出(字幕常显语义);
            // 由全局「译」开关驱动,内部自管模型下载/引擎加载状态。
            if (!screen.pip)
              Positioned(
                left: 24,
                right: 24,
                bottom: 68,
                child: CaptionOverlay(site: widget.site, roomId: widget.roomId),
              ),
            // 睡眠定时剩余时间:舞台右上角常驻徒标,不进控制条随时间变化的
            // 可见性(控制条淡出后仍需可见)。
            if (sleepTimer.active)
              Positioned(
                top: AppSpacing.sm,
                right: AppSpacing.sm,
                child: _SleepTimerBadge(remaining: sleepTimer.remainingLabel),
              ),
            // PiP 小窗不渲染控制条(小窗只留画面,退出走 Esc)。
            if (!screen.pip)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                // 控制条区域悬停:停留期间不进入隐藏倒计时;离开恢复倒计时。
                child: MouseRegion(
                  onEnter: (_) => _enterControls(),
                  onExit: (_) => _exitControls(),
                  child: AnimatedOpacity(
                    // 测试锚点:控制条容器(淡出/唤醒可断言其 opacity)。
                    key: const Key('play-controls-bar-wrap'),
                    duration: const Duration(milliseconds: 200),
                    opacity: _controlsVisible ? 1.0 : 0.0,
                    // 淡出后必须阻断命中:否则不可见的按钮仍会被点中,
                    // 且底部条带会持续吞掉"点视频切播放/暂停"的点击。
                    child: AbsorbPointer(
                      absorbing: !_controlsVisible,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              context.tokens.background.withValues(alpha: 0.0),
                              context.tokens.background.withValues(alpha: 0.72),
                            ],
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            PlayerControlsBar(
                              site: widget.site,
                              roomId: widget.roomId,
                              showDanmaku: showDanmaku,
                              danmakuEnabled: danmakuEnabled,
                              speechCaptionEnabled: speechCaptionEnabled,
                              screenMode: screen.mode,
                              onDanmakuToggle: () => ref
                                  .read(
                                    playControllerProvider(_params).notifier,
                                  )
                                  .toggleDanmaku(),
                              onCaptionToggle: () =>
                                  unawaited(_toggleSpeechCaption()),
                              onToggleWidescreen: _toggleWidescreen,
                              onToggleFullscreen: _toggleFullscreen,
                              onTogglePip: _togglePip,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );

    // 播放页根级 Scaffold:给内容有界的宽高约束,同时提供 ScaffoldMessenger
    // 宿主(控制条「刷新视频」的 SnackBar 需要 descendant Scaffold 才能呈现)。
    // 播放页虽已套 AppShell(顶栏常在),沉浸态下壳层 chrome 会收起,
    // 因此这一层 Scaffold 必须自己提供,理由见 player_controls.dart。
    late final Widget body;
    if (screen.pip) {
      // 画中画小窗:只铺画面,桌面下由包壳提供拖拽/缩放边缘。
      body = PipResizeSurface(child: stage);
    } else if (screen.hidesChrome) {
      // 网页全屏 / 全屏:视频占满窗口,隐藏房间头与侧栏;控制条自动隐藏可唤醒。
      // 右缘侧抽屉(对齐 web PlayImmersiveSideSheet):仅在沉浸态挂载,
      // 与舞台同一 Stack;payload 未就绪时无内容可展示,不挂载(web sideReady)。
      final immersivePanelWidth = size.width < AppBreakpoints.phone
          // 手机:面板宽不超过视口 88%(web `min(320px, 88vw)`)。
          ? math.min(
              AppSpacing.playSidePanelWidthFor(size.width),
              size.width * 0.88,
            )
          : AppSpacing.playSidePanelWidthFor(size.width);
      body = SizedBox.expand(
        // 测试锚点:全屏 / 网页全屏的沉浸容器。
        key: const Key('play-immersive-stage'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            stage,
            if (play?.payload != null)
              PlayImmersiveSideSheet(
                open: _immersiveSideOpen,
                panelWidth: immersivePanelWidth,
                onClose: _closeImmersiveSide,
                onInteract: _scheduleImmersiveSideHide,
                child: PlaySidePanel(
                  site: widget.site,
                  roomId: widget.roomId,
                  payload: play?.payload,
                  playbackStatus: _sidePanelPlaybackStatus,
                ),
              ),
          ],
        ),
      );
    } else {
      // 左右布局(用户口径 2026-09-18):左列 = 房间头(标题行) + 播放舞台,
      // 右列 = 侧栏全高(从 body 顶到 body 底)。旧布局房间头全宽横跨侧栏
      // 上方,侧栏从 44px 头下才开始;现头部只属于左列,侧栏独占右列全高。
      final leftColumn = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoomHeader(
            title: play?.payload?.title ?? (async.hasError ? '房间解析失败' : '加载中…'),
            site: widget.site,
            cid: play?.payload?.cid ?? '',
            cateNo: play?.payload?.cateNo ?? '',
            category: play?.payload?.category ?? '',
            brandColor: brand?.color ?? context.tokens.brand,
            sidePanelVisible: _sidePanelVisible,
            onBack: _goBack,
            onToggleSidePanel: isLandscapePhone
                ? () => _showSidePanelSheet(play?.payload)
                : () => setState(() => _sidePanelVisible = !_sidePanelVisible),
          ),
          Expanded(
            child: stackSidePanel
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: stageInFrame(stage)),
                      if (showPanel) ...[
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          flex: 2,
                          child: PlaySidePanel(
                            site: widget.site,
                            roomId: widget.roomId,
                            payload: play?.payload,
                            playbackStatus: _sidePanelPlaybackStatus,
                            // 窄屏堆叠:视频正下方紧跟移动信息条
                            // (头像 + 昵称 + 4 项统计 + 关注/超关)。
                            compactHeader: true,
                          ),
                        ),
                      ],
                    ],
                  )
                : stageInFrame(stage),
          ),
        ],
      );
      body = Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: leftColumn),
          if (!stackSidePanel && showPanel) ...[
            // 播放区与侧栏的间隔:用户口径 2026-09-19 改为 2px(原 md=16 过大)。
            const SizedBox(width: 2),
            SizedBox(
              width: sidePanelWidth,
              child: PlaySidePanel(
                site: widget.site,
                roomId: widget.roomId,
                payload: play?.payload,
                playbackStatus: _sidePanelPlaybackStatus,
              ),
            ),
          ],
        ],
      );
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      resizeToAvoidBottomInset: false,
      body: body,
    );
  }
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.title,
    required this.site,
    required this.cid,
    this.cateNo = '',
    required this.category,
    required this.brandColor,
    required this.sidePanelVisible,
    required this.onBack,
    required this.onToggleSidePanel,
  });

  final String title;

  /// 当前房间平台(收藏分类的归属站点)。
  final String site;

  /// 当前房间分类 id;为空表示拿不到分类上下文 → 不显示收藏星。
  final String cid;

  /// 平台分类号(soop 等 cid 另作他用的站点非空);收藏分类优先用它。
  final String cateNo;
  final String category;
  final Color brandColor;
  final bool sidePanelVisible;

  /// 返回上一页(栈底时退化为平台首页,见 _PlayViewState._goBack)。
  final VoidCallback onBack;
  final VoidCallback onToggleSidePanel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // 分类徽标配色:优先分类色板(web `categoryHeaderStyle`),无分类色回退
    // 平台色;前景按底色亮度取对比色。
    // 收藏与徽标映射统一用分类号:soop 的 cid 是房间号,按分类号才能
    // 命中「我的分类」判重与跨平台/中文映射表。
    final favoriteCid = cateNo.isNotEmpty ? cateNo : cid;
    final categoryStyle = CategoryColors.opaqueFor(
      category: category,
      site: site,
      cid: favoriteCid,
    );
    final badgeBg =
        categoryStyle?.background ??
        (category.trim().isNotEmpty ? brandColor : null);
    final badgeFg =
        categoryStyle?.foreground ??
        (badgeBg == null
            ? tokens.textSecondary
            : ThemeData.estimateBrightnessForColor(badgeBg) == Brightness.dark
            ? tokens.textPrimary
            : tokens.surfaceSoft);
    // 徽标文字统一走跨平台中文映射(twitch/soop 等海外平台的英文/韩文
    // 原名按 cid/别名归一为中文,与侧栏 formatCategoryHeaderLabel 同口径)。
    final categoryLabel = formatCategoryHeaderLabel(
      site,
      category,
      favoriteCid,
    );
    // 自适应高度(web `padding .28rem .5rem .32rem`):内容撑开,不再固定 44。
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 4.5, 4, 5),
      child: Row(
        children: [
          IconButton(
            // 测试锚点:返回上一页按钮。点击区 32(web 2rem×2rem)。
            key: const Key('play-back'),
            tooltip: '返回',
            onPressed: onBack,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            // 键盘焦点可见(Material 系 focusColor 覆盖色,不动盒模型)。
            focusColor: AppStateLayer.focusOf(tokens.accent),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
          ),
          const SizedBox(width: AppSpacing.sm),
          if (badgeBg != null)
            Consumer(
              builder: (context, ref, _) {
                // 分类徽标(web PlayHeader.vue:82-133):平台图标 + 分类文字 +
                // 内嵌收藏星标(仅房间带分类上下文时);星标点击切换「我的分类」。
                // 已收藏判定按跨平台分类 key(2026-09-20 对齐 web
                // useMyCrossCategories):收藏过任一平台的「英雄联盟」,
                // 所有平台的英雄联盟房间星标都亮。
                final favorited =
                    favoriteCid.isNotEmpty &&
                    isCategoryFavorited(
                      ref.watch(myCategoriesProvider),
                      site: site,
                      cid: favoriteCid,
                      name: categoryLabel,
                    );
                return Container(
                  // 用户口径(2026-09-20):分类名文字更大、行内上下居中。
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: badgeBg.withValues(alpha: 0.92),
                    borderRadius: AppRadius.allSm,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PlatformIcon(id: site, size: 13),
                      const SizedBox(width: 3),
                      Text(
                        categoryLabel.isNotEmpty ? categoryLabel : '直播',
                        style: context.textBody.copyWith(
                          fontSize: AppFontSize.body,
                          height: 1,
                          color: badgeFg,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (cid.isNotEmpty) ...[
                        const SizedBox(width: 2),
                        InkWell(
                          key: const Key('play-category-favorite'),
                          onTap: () => ref
                              .read(myCategoriesProvider.notifier)
                              .toggleForCategory(
                                MyCategoryEntry(
                                  site: site,
                                  // 分类收藏的 cid 必须是**分类号**;soop 的
                                  // payload.cid 是房间号,真实分类号在 cateNo。
                                  cid: favoriteCid,
                                  // 收藏快照存中文展示名(与 web 收藏口径一致),
                                  // 渲染侧还会再映射一次兜底旧快照。
                                  name: categoryLabel,
                                ),
                              ),
                          // 星标压在平台色徽章上:hover 用半透明白灰(不遮徽章本色),
                          // 按下/焦点走 accent 低 alpha。
                          hoverColor: tokens.surfaceRaised.withValues(
                            alpha: 0.24,
                          ),
                          splashColor: AppStateLayer.splashOf(tokens.accent),
                          highlightColor: AppStateLayer.pressedOf(
                            tokens.accent,
                          ),
                          focusColor: AppStateLayer.focusOf(tokens.accent),
                          child: Icon(
                            favorited
                                ? Icons.star_rounded
                                : Icons.star_border_rounded,
                            size: 13,
                            color: favorited
                                ? tokens.brand
                                : badgeFg.withValues(alpha: 0.85),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Center(
              // 仅标题(web 不在标题里拼分类:分类已由左侧徽标承载)。
              // 标题自动中文化:原文先显示,译文到达替换。
              child: TranslatedText(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: context.textTitle.copyWith(
                  fontSize: AppFontSize.subtitle,
                ),
              ),
            ),
          ),
          IconButton(
            // 测试锚点:侧栏折叠/展开按钮。
            key: const Key('play-side-panel-toggle'),
            tooltip: sidePanelVisible ? '收起侧栏' : '展开侧栏',
            onPressed: onToggleSidePanel,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            focusColor: AppStateLayer.focusOf(tokens.accent),
            icon: Icon(
              sidePanelVisible
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              size: 18,
              color: tokens.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 弹幕叠加层桥接:监听 [danmakuSessionProvider](与右侧侧栏聊天共用同一
/// autoDispose 会话,不重复建连),把每次新增的尾部消息经单实例
/// [StreamController.broadcast] 转发给 [DanmakuOverlay](overlay 吃稳定流,
/// didUpdateWidget 仅在流实例变化时重订阅)。visible=false 时保持挂载但
/// 停绘,避免频繁切开关导致会话重建/弹幕丢失。
class _DanmakuLayer extends ConsumerStatefulWidget {
  const _DanmakuLayer({
    required this.site,
    required this.roomId,
    required this.visible,
  });

  final String site;
  final String roomId;
  final bool visible;

  @override
  ConsumerState<_DanmakuLayer> createState() => _DanmakuLayerState();
}

class _DanmakuLayerState extends ConsumerState<_DanmakuLayer> {
  late final StreamController<DanmakuMessage> _controller =
      StreamController<DanmakuMessage>.broadcast();

  /// 尾部转发器:按对象身份追踪已转发位置,把环形缓冲快照换算成新增弹幕。
  /// 不能按 length 比较——缓冲灌满后 length 恒为上限,叠加层会永远收不到
  /// 新消息(实测:聊天在滚、视频无弹幕)。对齐 SFVideo useDanmaku 的
  /// 「飘屏与聊天独立队列」结构(overlay 自身另有 maxVisible 上限)。
  final DanmakuTailForwarder _forwarder = DanmakuTailForwarder();

  ProviderSubscription<DanmakuChatState>? _sub;

  @override
  void initState() {
    super.initState();
    // listenManual 在 initState 合法(不在 build 里);订阅存活到 dispose。
    _sub = ref.listenManual(
      danmakuSessionProvider((site: widget.site, roomId: widget.roomId)),
      (prev, next) => _pushTail(next.messages),
    );
    // 首帧已存在的消息(如热重载/重建)也补发一次。
    _pushTail(
      ref
          .read(
            danmakuSessionProvider((site: widget.site, roomId: widget.roomId)),
          )
          .messages,
    );
  }

  void _pushTail(List<DanmakuMessage> messages) {
    for (final m in _forwarder.forward(messages)) {
      _controller.add(m);
    }
  }

  @override
  void dispose() {
    _sub?.close();
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // 细粒度设置(透明度/字号/速度/显示区域):在此注入 overlay。
    // 总开关仍由 [widget.visible](danmakuEnabled)控制(enabled=visible)。
    // 此前只传 messages/enabled,设置面板的滑杆全是死控件 —— 改这里即接通。
    final settings = ref.watch(danmakuSettingsProvider);
    // 飘屏正文中文化:开启时原文先上屏,译文返回原位替换(条目已离场则
    // 丢弃)。关闭时传 null,overlay 零额外开销。
    final translateOn = ref.watch(
      settingsProvider.select((s) => s.translationEnabled),
    );
    return DanmakuOverlay(
      messages: _controller.stream,
      enabled: widget.visible,
      opacity: settings.opacity / 100,
      fontSize: settings.fontSize.toDouble(),
      speedFactor: settings.speed,
      displayAreaRatio: settings.displayAreaRatio,
      translateBody: translateOn
          ? (text, segments) => ref
                .read(translationCoordinatorProvider)
                .translateBody(text: text, segments: segments)
          : null,
    );
  }
}

/// 视频舞台:加载/解析失败/fixture 占位/真实画面 + 缓冲与错误 overlay。
/// 点击舞台空白区切换播放/暂停(桌面鼠标 + 触屏一致);控制条与画质条
/// 叠层在其上方,各自消费自己的点击,不会误触播放切换。
class _VideoStage extends ConsumerStatefulWidget {
  const _VideoStage({
    required this.async,
    required this.showDanmaku,
    required this.onRetry,
    this.onFrameTapUp,
  });

  final AsyncValue<PlayState> async;

  /// 舞台弹幕叠加层是否显示(叠加层由独立组件轨道挂载,这里只透传)。
  final bool showDanmaku;

  final VoidCallback onRetry;

  /// 沉浸态舞台点击分流回调(传 `localPosition`,见播放页
  /// `_onImmersiveFrameTapUp`);为空时保持「点击切播放/暂停」。
  final void Function(Offset localPosition)? onFrameTapUp;

  @override
  ConsumerState<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends ConsumerState<_VideoStage> {
  /// 舞台焦点节点:点舞台时把焦点收进来,页面级 Space/M/F 快捷键沿焦点树
  /// 冒泡生效。**必须自持 FocusNode** —— `Focus.of(context)` 在 build context
  /// 上取到的是外层 scope(焦点停在 ModalScope),requestFocus 等于空操作。
  final FocusNode _focusNode = FocusNode(debugLabel: 'play-stage');

  /// 当前房间是否出过播放画面:暂停遮罩只在「播过后暂停」出现,
  /// 区别于「尚未首帧」的加载态。切房后重置,避免新房间首帧前的
  /// !playing 间隙闪现遮罩。
  bool _everPlayed = false;
  Object? _lastRoomId;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  /// 点击舞台:切换播放/暂停。与舞台内 overlay 同帧构建,播放控制条
  /// 位于本组件上层,因此按钮/滑杆的点击不会落到这里。
  void _onStageTap() {
    final snapshot =
        ref.read(playerSnapshotProvider).value ?? const PlayerSnapshot();
    final player = ref.read(playerProvider);
    if (snapshot.playing) {
      player.pause();
    } else {
      player.play();
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = widget.async;
    final play = async.value;
    final snapshot =
        ref.watch(playerSnapshotProvider).value ?? const PlayerSnapshot();
    final payload = play?.payload;

    // 房间切换检测 + 播放闩锁:遮罩只对「本房间已出过画面后的暂停」生效。
    final roomId = payload?.roomId;
    if (roomId != _lastRoomId) {
      _lastRoomId = roomId;
      _everPlayed = false;
    }
    if (snapshot.playing) _everPlayed = true;

    final Widget content;
    if (payload == null) {
      // 尚未解析成功:区分加载中与失败。
      content = async.hasError
          ? _StagePlaceholder(
              icon: Icons.error_outline_rounded,
              text: '房间解析失败，请重试',
              action: RetryButton(
                onRetry: widget.onRetry,
                variant: RetryButtonVariant.outlined,
              ),
            )
          : const _StagePlaceholder(
              icon: Icons.play_circle_fill_rounded,
              text: '正在解析房间…',
            );
    } else if (payload.source == 'fixture') {
      final line = play?.line;
      content = _StagePlaceholder(
        icon: Icons.play_circle_fill_rounded,
        text: 'fixture 数据，G1 接真实流后自动播放',
        detail: line == null
            ? '暂无可用线路'
            : '当前线路：${line.name}（${line.format.toUpperCase()}）',
      );
    } else {
      content = Stack(
        fit: StackFit.expand,
        children: [
          if (ref.watch(playerProvider)
              case final IdleReleasingLivePlayer idlePlayer)
            StreamBuilder<int>(
              stream: idlePlayer.viewChanges,
              builder: (_, snapshot) => idlePlayer.buildVideoView(),
            )
          else
            ref.read(playerProvider).buildVideoView(),
          // 暂停遮罩:流已出过画面后用户暂停 → 居中紫薯 logo。仅在
          // 「曾经播过 + 现在没播 + 不在缓冲/报错」时出现,避免解析中/首帧前
          // 闪现 logo。
          if (_everPlayed &&
              !snapshot.playing &&
              !snapshot.buffering &&
              snapshot.error == null)
            const _PausedOverlay(),
          if (snapshot.notice != PlaybackNotice.none)
            Center(
              child: _PlaybackNoticeOverlay(
                notice: snapshot.notice,
                progress: snapshot.retryAttempt > 0
                    ? retryProgressLabel(
                        snapshot.retryAttempt,
                        snapshot.retryLimit,
                      )
                    : '',
              ),
            ),
          if (snapshot.error != null && snapshot.notice == PlaybackNotice.none)
            Center(
              child: _ErrorCard(
                message: snapshot.error!,
                // 自动重连中显示进度,让"程序在自救"这件事对用户可见;
                // 未在重连(或已放弃)时为空串,不占位。
                progress: snapshot.reconnecting
                    ? retryProgressLabel(
                        snapshot.retryAttempt,
                        snapshot.retryLimit,
                      )
                    : '',
                onRetry: widget.onRetry,
              ),
            ),
        ],
      );
    }

    // 点视频帧 = 播放/暂停,同时把键盘焦点收到舞台:焦点落在播放页子树后,
    // 页面级 Space/M/F 快捷键才沿焦点树冒泡生效(与「先点视频区再用快捷键」
    // 的桌面直觉一致)。子层 overlay(重试按钮等)自行消费点击。
    //
    // `autofocus: true` 是快捷键可达性的**前提**,不是可选优化(对齐参考实现
    // pure_live,其播放器包在 `Focus(autofocus: true)` 里)。
    // 原因:`Shortcuts`/`CallbackShortcuts` 只在「焦点链」上生效;而 Flutter 在
    // 页面内无人持焦时把 primaryFocus 停在 `ModalScope` 根上,此时按键根本不
    // 会流经播放页的快捷键节点。实测:点击音量滑杆**不会**把焦点移进控制条
    // (Slider 不请求焦点),焦点仍在 ModalScope → F 键静默失效。让舞台默认
    // 持焦即可让焦点链始终覆盖播放页;点控制条按钮时焦点落在按钮(舞台子树
    // 内)同样可达,且按钮自身对 Space 的处理在前面命中、不会被重复触发。
    return Focus(
      // 测试锚点:定位舞台焦点节点(测试里点是命中舞台本身)。
      key: const Key('play-stage-focus'),
      focusNode: _focusNode,
      autofocus: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          // 画面本身可点(切播放/暂停,沉浸态右缘热区开抽屉):补上指针光标
          // (GestureDetector 不会自带 cursor,这是 G3 里“可点却没反应”的根因)。
          // onTapUp 而非 onTap:沉浸态分流需要点击在舞台内的相对位置
          // (右缘 2/3 热区判定);常规态回调为空,退化为切播放/暂停。
          // onDoubleTap = 播放/暂停(主流播放器肌肉记忆,与单击同义):
          // 双击判定会令单击回调延迟约 300ms —— 支持双击的固有代价
          // (YouTube 同款)。沉浸态(onFrameTapUp 非空)不注册双击:抽屉/热区
          // 是精细交互,保持立即响应;那里双击也无独立语义。
          onDoubleTap: widget.onFrameTapUp == null
              ? () {
                  _focusNode.requestFocus();
                  _onStageTap();
                }
              : null,
          onTapUp: (details) {
            // 焦点交给舞台节点(自持 FocusNode),再处理点击语义。
            _focusNode.requestFocus();
            final handler = widget.onFrameTapUp;
            if (handler != null) {
              handler(details.localPosition);
              return;
            }
            _onStageTap();
          },
          child: Container(
            alignment: Alignment.center,
            padding: payload == null || payload.source == 'fixture'
                ? const EdgeInsets.all(AppSpacing.xl)
                : EdgeInsets.zero,
            child: content,
          ),
        ),
      ),
    );
  }
}

/// 暂停态遮罩:半透明压暗 + 居中紫薯 logo(点击画面即恢复,由舞台
/// GestureDetector 统一处理)。
class _PausedOverlay extends StatelessWidget {
  const _PausedOverlay();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        color: AppOnVideo.pauseScrim,
        alignment: Alignment.center,
        child: SvgPicture.asset(
          'assets/ui/icons/play-purple.svg',
          width: 96,
          height: 96,
          semanticsLabel: '播放',
        ),
      ),
    );
  }
}

/// 解析中/失败/fixture 数据的舞台占位。
class _StagePlaceholder extends StatelessWidget {
  const _StagePlaceholder({
    required this.icon,
    required this.text,
    this.detail,
    this.action,
  });

  final IconData icon;
  final String text;
  final String? detail;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 56, color: tokens.surfaceRaised),
        const SizedBox(height: AppSpacing.md),
        Text(text, style: context.textSecondary),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(detail!, style: context.textCaption),
        ],
        if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
      ],
    );
  }
}

/// 缓冲/恢复中的脱敏原因浮层。只展示稳定状态映射，不暴露 URL、token 或 mpv 日志。
class _PlaybackNoticeOverlay extends StatelessWidget {
  const _PlaybackNoticeOverlay({required this.notice, this.progress = ''});

  final PlaybackNotice notice;
  final String progress;

  String get _message => switch (notice) {
    PlaybackNotice.networkJitter => '网络波动，缓冲中…',
    PlaybackNotice.sourceOpenFailed => '直播地址暂时无法打开，正在切换线路…',
    PlaybackNotice.reconnecting => '网络不稳定，正在重新连接…',
    PlaybackNotice.recoveringNewUrl => '正在获取新的直播地址…',
    PlaybackNotice.none => '正在缓冲直播画面…',
  };

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        child: Container(
        key: const Key('playback-notice-overlay'),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.md,
        ),
        decoration: BoxDecoration(
          color: context.tokens.surfaceRaised.withValues(alpha: 0.90),
          borderRadius: AppRadius.allMd,
          border: Border.all(color: context.tokens.border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: AppSpacing.sm),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Text(
                _message,
                textAlign: TextAlign.center,
                style: context.textSecondary.copyWith(
                  color: context.tokens.textPrimary,
                ),
              ),
            ),
            if (progress.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(progress, style: context.textCaption),
            ],
          ],
        ),
        ),
      ),
    );
  }
}

/// 播放错误浮层卡片:错误文案(已由播放器归类为处置建议) + 重连进度 + 重试。
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.message,
    required this.onRetry,
    this.progress = '',
  });

  final String message;

  /// 自动重连进度文案;空串表示未在重连。
  final String progress;

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised.withValues(alpha: 0.92),
        borderRadius: AppRadius.allMd,
        border: Border.all(color: tokens.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline_rounded, size: 32, color: tokens.error),
          const SizedBox(height: AppSpacing.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Text(
              message,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: context.textSecondary.copyWith(color: tokens.textPrimary),
            ),
          ),
          if (progress.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(progress, style: context.textCaption),
          ],
          const SizedBox(height: AppSpacing.md),
          RetryButton(onRetry: onRetry, variant: RetryButtonVariant.outlined),
        ],
      ),
    );
  }
}

/// 舞台右上角的睡眠定时倒计时标注(锚点 `play-sleep-remaining`)。
///
/// 不放进控制条:控制条在沉浸态会淡出,而"还有多久停"属于需要一直可见的状态。
class _SleepTimerBadge extends StatelessWidget {
  const _SleepTimerBadge({required this.remaining});

  /// 剩余时间文案(`mm:ss` / `h:mm:ss`,由 SleepTimerState.remainingLabel 给出)。
  final String remaining;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Container(
      key: const Key('play-sleep-remaining'),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: tokens.surfaceRaised.withValues(alpha: 0.72),
        borderRadius: AppRadius.allPill,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bedtime_rounded, size: 14, color: tokens.accent),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '定时 $remaining',
            style: context.textCaption.copyWith(color: tokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
