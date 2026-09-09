import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../platforms/common/playback/live_player.dart' show PlayerSnapshot;
import '../../../shared/presentation/design_tokens.dart';
import '../../../shared/presentation/zishu_tokens.dart';
import '../../../shared/presentation/platform_brands.dart';
import '../application/play_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(playControllerProvider(_params));
    final play = async.value;
    final brand = PlatformBrandCatalog.byId(widget.site);
    // U9 响应式:窄屏(<768)把 328px 信息栏堆叠到视频区下方,
    // 否则固定宽侧栏会把视频舞台挤成 0 宽(实测 360dp 下视频区只剩 3dp)。
    final stackSidePanel =
        MediaQuery.sizeOf(context).width < AppBreakpoints.phone;
    final showPanel = _sidePanelVisible;

    final stage = Column(
      children: [
        Expanded(
          child: _VideoStage(
            async: async,
            onRetry: () =>
                ref.read(playControllerProvider(_params).notifier).retry(),
          ),
        ),
        PlayerControlsBar(site: widget.site, roomId: widget.roomId),
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
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _RoomHeader(
          title: play?.payload?.title ?? (async.hasError ? '房间解析失败' : '加载中…'),
          category: play?.payload?.category ?? '',
          brandColor: brand?.color ?? context.tokens.brand,
          sidePanelVisible: _sidePanelVisible,
          onToggleSidePanel:
              () => setState(() => _sidePanelVisible = !_sidePanelVisible),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              0,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: stackSidePanel
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(flex: 3, child: stage),
                      if (showPanel) ...[
                        const SizedBox(height: AppSpacing.md),
                        const Expanded(flex: 2, child: PlaySidePanel()),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: stage),
                      if (showPanel) ...[
                        const SizedBox(width: AppSpacing.md),
                        const SizedBox(
                          width: AppSpacing.playSidePanelWidth,
                          child: PlaySidePanel(),
                        ),
                      ],
                    ],
                  ),
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
            child: Text(
              [if (category.isNotEmpty) category, title].join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.title.copyWith(fontSize: 14),
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

/// 视频舞台:加载/解析失败/fixture 占位/真实画面 + 缓冲与错误 overlay。
class _VideoStage extends ConsumerWidget {
  const _VideoStage({required this.async, required this.onRetry});

  final AsyncValue<PlayState> async;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
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
              action: _RetryButton(onRetry: onRetry),
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
                onRetry: onRetry,
              ),
            ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: tokens.surfaceSoft,
        borderRadius: AppRadius.allLg,
        border: Border.all(color: tokens.border),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      padding: payload == null || payload.source == 'fixture'
          ? const EdgeInsets.all(AppSpacing.xl)
          : EdgeInsets.zero,
      child: content,
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
