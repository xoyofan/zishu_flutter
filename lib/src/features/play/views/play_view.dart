import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:live_parser/live_parser.dart' show DanmakuMessage, RoomPayload;

import '../../../platforms/common/playback/live_player.dart' show PlayerSnapshot;
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../../danmaku/application/danmaku_session_provider.dart'
    show DanmakuChatState, danmakuSessionProvider;
import '../../danmaku/widgets/danmaku_overlay.dart';
import '../application/play_provider.dart';
import '../../follow/application/settings_provider.dart';
import '../widgets/play_side_panel.dart';
import '../widgets/player_controls.dart';
import '../widgets/quality_line_bar.dart';

/// 播放页(U5 布局基线):44px 房间头 + 视频舞台/控制条/画质线路条 +
/// 右侧 328px 信息栏。编排全部收敛在 playControllerProvider/LivePlayer,
/// Widget 只消费状态与接口,不直接触碰 media_kit。
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

  /// 桌面快捷键:Space / M / F 走与按钮完全相同的通路。
  /// 播放/暂停按快照取反;`toggleFullscreen` 在平台层当前是空实现,
  /// 这里照常调用接口,不伪造本地全屏态。
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

  void _toggleFullscreen() => ref.read(playerProvider).toggleFullscreen();

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
    final brand = PlatformBrandCatalog.byId(widget.site);
    final size = MediaQuery.sizeOf(context);
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

    // 桌面快捷键宿主:套在播放页内容外层,焦点落在页内任意位置(含控制条
    // 按钮、右侧侧栏)时按键都可达;未聚焦/事件没被消费时照旧冒泡,不会
    // 吞掉输入框的按键(输入框自身的 Shortcuts 优先级更高)。
    final stage = CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): _togglePlayback,
        const SingleActivator(LogicalKeyboardKey.keyM): _toggleMuted,
        const SingleActivator(LogicalKeyboardKey.keyF): _toggleFullscreen,
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
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
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
                    onDanmakuToggle: () => ref
                        .read(playControllerProvider(_params).notifier)
                        .toggleDanmaku(),
                  ),
                  QualityLineBar(
                    payload: play?.payload,
                    activeQuality: play?.quality,
                    activeLine: play?.line,
                    onQualityTap: (quality) => ref
                        .read(playControllerProvider(_params).notifier)
                        .switchQuality(quality),
                    onLineTap: (line) => ref
                        .read(playControllerProvider(_params).notifier)
                        .switchLine(line),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomHeader(
          title: play?.payload?.title ?? (async.hasError ? '房间解析失败' : '加载中…'),
          category: play?.payload?.category ?? '',
          brandColor: brand?.color ?? context.tokens.brand,
          sidePanelVisible: _sidePanelVisible,
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
}

class _RoomHeader extends StatelessWidget {
  const _RoomHeader({
    required this.title,
    required this.category,
    required this.brandColor,
    required this.sidePanelVisible,
    required this.onToggleSidePanel,
  });

  final String title;
  final String category;
  final Color brandColor;
  final bool sidePanelVisible;
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
            onPressed: () => context.pop(),
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

  /// 已转发条数(与 provider 的 FIFO 快照尾部对齐)。
  int _sentCount = 0;

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
      ref.read(danmakuSessionProvider((site: widget.site, roomId: widget.roomId)))
          .messages,
    );
  }

  void _pushTail(List<DanmakuMessage> messages) {
    if (messages.length > _sentCount) {
      for (final m in messages.skip(_sentCount)) {
        _controller.add(m);
      }
      _sentCount = messages.length;
    } else if (messages.length < _sentCount) {
      // 环形缓冲回退(理论上不发生):重置基准,避免漏发/重发。
      _sentCount = messages.length;
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
    return DanmakuOverlay(
      messages: _controller.stream,
      enabled: widget.visible,
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
                onRetry: widget.onRetry,
              ),
            ),
        ],
      );
    }

    // 点视频帧 = 播放/暂停,同时把键盘焦点收到舞台:焦点落在播放页子树后,
    // 页面级 Space/M/F 快捷键才沿焦点树冒泡生效(与「先点视频区再用快捷键」
    // 的桌面直觉一致)。子层 overlay(重试按钮等)自行消费点击。
    return Focus(
      // 测试锚点:定位舞台焦点节点(测试里点是命中舞台本身)。
      key: const Key('play-stage-focus'),
      focusNode: _focusNode,
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
        if (action != null) ...[
          const SizedBox(height: AppSpacing.md),
          action!,
        ],
      ],
    );
  }
}

/// 播放错误浮层卡片:错误文案 + 重试。
class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message, required this.onRetry});

  final String message;
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
