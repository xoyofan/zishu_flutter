import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show DanmakuMessage, RoomPayload;

import '../../../platforms/common/playback/live_player.dart'
    show PlayerSnapshot;
import '../../../platforms/common/playback/playback_retry.dart'
    show retryProgressLabel;
import '../../../shared/presentation/design_tokens.dart';
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
import '../../follow/application/settings_provider.dart';
import '../widgets/pip_surface.dart';
import '../widgets/play_side_panel.dart';
import '../widgets/player_controls.dart';

/// 播放页(U5 布局基线):44px 房间头 + 视频舞台/控制条/画质线路条 +
/// 右侧 328px 信息栏。编排全部收敛在 playControllerProvider/LivePlayer,
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
    _hideTimer?.cancel();
    // 窗口呈现(全屏/PiP)的复位由 playScreenProvider 的 onDispose 负责
    // (autoDispose:离开播放页即触发),此处不再手动调用,避免与 provider
    // 销毁时序打架——旧做法在 dispose 期走 ref,会撞上"provider 已销毁"。
    super.dispose();
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

  /// 横屏手机:侧栏以底部 sheet 滑出(sheet 宽近全屏,满足 W12 sheet 形态)。
  Future<void> _showSidePanelSheet(RoomPayload? payload) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        height: MediaQuery.sizeOf(sheetContext).height * 0.72,
        decoration: const BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: PlaySidePanel(
          site: widget.site,
          roomId: widget.roomId,
          payload: payload,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(playControllerProvider(_params));
    final play = async.value;
    // 设置项「弹幕」总开关:关闭时控制条的弹幕按钮整体隐藏。
    final danmakuEnabled = ref.watch(
      settingsProvider.select((settings) => settings.danmakuEnabled),
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
            ),
            // 弹幕叠加层:位于视频之上、控制条之下(参考 play 布局层级)。
            // 与右侧侧栏聊天共用 danmakuSessionProvider 的同一会话,不重复建连。
            _DanmakuLayer(
              site: widget.site,
              roomId: widget.roomId,
              visible: showDanmaku && danmakuEnabled,
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
                              AppColors.background.withValues(alpha: 0.0),
                              AppColors.background.withValues(alpha: 0.72),
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
                              screenMode: screen.mode,
                              onDanmakuToggle: () => ref
                                  .read(
                                    playControllerProvider(_params).notifier,
                                  )
                                  .toggleDanmaku(),
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
      body = SizedBox.expand(
        // 测试锚点:全屏 / 网页全屏的沉浸容器。
        key: const Key('play-immersive-stage'),
        child: stage,
      );
    } else {
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _RoomHeader(
            title: play?.payload?.title ?? (async.hasError ? '房间解析失败' : '加载中…'),
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
                      Expanded(flex: 3, child: stage),
                      if (showPanel) ...[
                        const SizedBox(height: AppSpacing.md),
                        Expanded(
                          flex: 2,
                          child: PlaySidePanel(
                            site: widget.site,
                            roomId: widget.roomId,
                            payload: play?.payload,
                          ),
                        ),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: stage),
                      if (showPanel) ...[
                        const SizedBox(width: AppSpacing.md),
                        SizedBox(
                          width: sidePanelWidth,
                          child: PlaySidePanel(
                            site: widget.site,
                            roomId: widget.roomId,
                            payload: play?.payload,
                          ),
                        ),
                      ],
                    ],
                  ),
          ),
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
    required this.category,
    required this.brandColor,
    required this.sidePanelVisible,
    required this.onBack,
    required this.onToggleSidePanel,
  });

  final String title;
  final String category;
  final Color brandColor;
  final bool sidePanelVisible;

  /// 返回上一页(栈底时退化为平台首页,见 _PlayViewState._goBack)。
  final VoidCallback onBack;
  final VoidCallback onToggleSidePanel;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    // 平台色底上按亮度取对比文字色,避免散落色值。
    final onBrand =
        ThemeData.estimateBrightnessForColor(brandColor) == Brightness.dark
        ? tokens.textPrimary
        : tokens.surfaceSoft;
    return SizedBox(
      height: 44,
      child: Row(
        children: [
          IconButton(
            // 测试锚点:返回上一页按钮。
            key: const Key('play-back'),
            tooltip: '返回',
            onPressed: onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
          ),
          const SizedBox(width: AppSpacing.xs),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: brandColor.withValues(alpha: 0.92),
              borderRadius: AppRadius.allSm,
            ),
            child: Text(
              '直播',
              style: AppTypography.caption.copyWith(
                color: onBrand,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Center(
              child: Text(
                [if (category.isNotEmpty) category, title].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.title.copyWith(fontSize: 14),
              ),
            ),
          ),
          IconButton(
            // 测试锚点:侧栏折叠/展开按钮。
            key: const Key('play-side-panel-toggle'),
            tooltip: sidePanelVisible ? '收起侧栏' : '展开侧栏',
            onPressed: onToggleSidePanel,
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
    return DanmakuOverlay(
      messages: _controller.stream,
      enabled: widget.visible,
      opacity: settings.opacity / 100,
      fontSize: settings.fontSize.toDouble(),
      speedFactor: settings.speed,
      displayAreaRatio: settings.displayAreaRatio,
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
  });

  final AsyncValue<PlayState> async;

  /// 舞台弹幕叠加层是否显示(叠加层由独立组件轨道挂载,这里只透传)。
  final bool showDanmaku;

  final VoidCallback onRetry;

  @override
  ConsumerState<_VideoStage> createState() => _VideoStageState();
}

class _VideoStageState extends ConsumerState<_VideoStage> {
  /// 舞台焦点节点:点舞台时把焦点收进来,页面级 Space/M/F 快捷键沿焦点树
  /// 冒泡生效。**必须自持 FocusNode** —— `Focus.of(context)` 在 build context
  /// 上取到的是外层 scope(焦点停在 ModalScope),requestFocus 等于空操作。
  final FocusNode _focusNode = FocusNode(debugLabel: 'play-stage');

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

    final Widget content;
    if (payload == null) {
      // 尚未解析成功:区分加载中与失败。
      content = async.hasError
          ? _StagePlaceholder(
              icon: Icons.error_outline_rounded,
              text: '房间解析失败，请重试',
              action: _RetryButton(onRetry: widget.onRetry),
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
          ref.read(playerProvider).buildVideoView(),
          if (snapshot.buffering && snapshot.error == null)
            const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          if (snapshot.error != null)
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
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // 焦点交给舞台节点(自持 FocusNode),再切播放状态。
          _focusNode.requestFocus();
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
        Text(text, style: AppTypography.bodySecondary),
        if (detail != null) ...[
          const SizedBox(height: AppSpacing.xs),
          Text(detail!, style: AppTypography.caption),
        ],
        if (action != null) ...[const SizedBox(height: AppSpacing.md), action!],
      ],
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
              style: AppTypography.bodySecondary.copyWith(
                color: tokens.textPrimary,
              ),
            ),
          ),
          if (progress.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(progress, style: AppTypography.caption),
          ],
          const SizedBox(height: AppSpacing.md),
          _RetryButton(onRetry: onRetry),
        ],
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh_rounded, size: 16),
      label: const Text('重试'),
      style: OutlinedButton.styleFrom(
        foregroundColor: tokens.brand,
        side: BorderSide(color: tokens.brand.withValues(alpha: 0.6)),
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
          Icon(Icons.bedtime_rounded, size: 14, color: tokens.brand),
          const SizedBox(width: AppSpacing.xs),
          Text(
            '定时 $remaining',
            style: AppTypography.caption.copyWith(color: tokens.textPrimary),
          ),
        ],
      ),
    );
  }
}
