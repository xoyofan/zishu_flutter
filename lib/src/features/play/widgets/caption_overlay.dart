/// 语音识别中文字幕条:显示最新译文与下载/加载状态。
///
/// 位置由调用方(Positioned)决定 —— 控制栏上方一点;控制栏淡出时字幕
/// 仍常显(字幕语义)。译文就绪才上屏(与弹幕翻译同口径)。
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/speech_caption_provider.dart';

class CaptionOverlay extends ConsumerWidget {
  const CaptionOverlay({super.key, required this.site, required this.roomId});

  final String site;
  final String roomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state =
        ref.watch(roomSpeechCaptionProvider((site: site, roomId: roomId)));
    final caption = state.caption?.trim();
    final hasText = caption != null && caption.isNotEmpty;
    // 仅显示「有字幕」与「模型准备中」两类;error 静默(避免测试/离线环境
    // 网络失败时遮挡画面,排查走日志)。
    if (!hasText &&
        state.phase != CaptionUiPhase.downloading &&
        state.phase != CaptionUiPhase.loadingModel) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final String? hint = switch (state.phase) {
      CaptionUiPhase.downloading => () {
          final pct = state.downloadProgress;
          return pct == null
              ? '字幕模型准备中…'
              : '字幕模型下载中 ${(pct * 100).toStringAsFixed(0)}%';
        }(),
      CaptionUiPhase.loadingModel => '字幕引擎加载中…',
      _ => null,
    };
    final text = hasText ? caption : (hint ?? '');

    return IgnorePointer(
      child: Center(
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          constraints: const BoxConstraints(maxWidth: 720),
          decoration: BoxDecoration(
            color: const Color(0xCC101010),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            text,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: hint != null && !hasText
                  ? Colors.white.withValues(alpha: 0.72)
                  : Colors.white,
              height: 1.35,
            ),
          ),
        ),
      ),
    );
  }
}
